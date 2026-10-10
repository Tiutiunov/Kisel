#include <QtGlobal>

#ifdef Q_OS_WIN
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.UI.Notifications.Management.h>
#include <windows.h>
#include <shellapi.h>
#endif
#ifdef KISEL_WITH_DBUS1
#include <dbus/dbus.h>
#endif

#include "Notices.h"

#include <QDateTime>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantMap>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <iterator>
#include <set>
#include <thread>
#include <utility>
#include <vector>

namespace kisel {

struct Notices::Worker
{
    Notices *owner = nullptr;
    std::thread thread;
    std::mutex mutex;
    std::condition_variable wake;
    std::atomic<bool> stop {false};
    std::atomic<bool> dismissed {false};
    std::atomic<bool> words {false};

    void report(bool available, int count, const QString &app, const QStringList &apps = {}, const QVariantList &counts = {},
                const QString &target = {}, const QVariantList &recent = {})
    {
        QMetaObject::invokeMethod(owner, [o = owner, available, count, app, apps, counts, target, recent] {
            o->apply(available, count, app, apps, counts, target, recent); }, Qt::QueuedConnection);
    }

#ifdef Q_OS_WIN
    // the program whose window is in front: its file's name without ".exe", lower case
    static QString frontProgram()
    {
        DWORD pid = 0;
        GetWindowThreadProcessId(GetForegroundWindow(), &pid);
        QString name;
        if (HANDLE h = pid ? OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid) : nullptr) {
            wchar_t path[MAX_PATH];
            DWORD size = MAX_PATH;
            if (QueryFullProcessImageNameW(h, 0, path, &size))
                name = QString::fromWCharArray(path, int(size));
            CloseHandle(h);
        }
        name = name.mid(name.lastIndexOf(QLatin1Char('\\')) + 1).toLower();
        if (name.endsWith(QLatin1String(".exe")))
            name.chop(4);
        return name;
    }

    struct Note
    {
        quint32 id;
        QString name;  // the program, as Windows shows it
        QString key;   // its name and its identifier, lower case: what the program in front is matched against
        QString aumid; // its identifier in Windows (what its Start menu entry starts)
        std::chrono::steady_clock::time_point came;
    };

    // One of the newest few, for the list in Rin's card
    struct Recent
    {
        quint32 id;
        QString name, aumid, title, text;
        qint64 at;       // ms since the epoch
        bool read;       // its words have been asked for
    };
    static constexpr int kRecent = 8;

    // The title and the text of a notification, as its banner shows them: one line each
    static void wordsOf(const winrt::Windows::UI::Notifications::UserNotification &n, QString *title, QString *text)
    {
        namespace un = winrt::Windows::UI::Notifications;
        try {
            const auto binding = n.Notification().Visual().GetBinding(un::KnownNotificationBindings::ToastGeneric());
            if (!binding)
                return;
            QStringList lines;
            for (const auto &t : binding.GetTextElements()) {
                const winrt::hstring s = t.Text();
                const QString line = QString::fromWCharArray(s.c_str(), int(s.size())).simplified();
                if (!line.isEmpty())
                    lines.append(line);
            }
            if (lines.isEmpty())
                return;
            *title = lines.takeFirst().left(80);
            *text = lines.join(QLatin1Char(' ')).left(200);
        } catch (...) {
        }
    }

    void run()
    {
        namespace un = winrt::Windows::UI::Notifications;
        winrt::init_apartment(); // a thread of our own, so the blocking .get() calls below are allowed
        un::Management::UserNotificationListener listener {nullptr};
        bool allowed = false;
        try {
            listener = un::Management::UserNotificationListener::Current();
            auto status = listener.GetAccessStatus();
            if (status == un::Management::UserNotificationListenerAccessStatus::Unspecified)
                status = listener.RequestAccessAsync().get(); // (Windows asks the user, once)
            allowed = status == un::Management::UserNotificationListenerAccessStatus::Allowed;
        } catch (...) {
            allowed = false;
        }
        if (!allowed) {
            report(false, 0, {});
            return;
        }

        std::set<quint32> seen;                            // looked at, or there before we started
        std::vector<Note> unseen;                          // in the order they came
        bool first = true;
        bool told = false;
        int lastCount = -1;
        QString lastApp;
        QStringList lastApps;
        QVariantList lastCounts;
        QString lastTarget;
        std::vector<Recent> recent; // newest first
        QVariantList lastRecent;
        bool hadWords = false;
        while (!stop) {
            const bool wantWords = words.load();
            if (hadWords && !wantWords) // (switched off: what was read is let go)
                for (auto &r : recent) {
                    r.title.clear();
                    r.text.clear();
                    r.read = false;
                }
            hadWords = wantWords;
            try {
                const auto list = listener.GetNotificationsAsync(un::NotificationKinds::Toast).get();
                std::set<quint32> now;
                for (const auto &n : list) {
                    const quint32 id = n.Id();
                    now.insert(id);
                    // the list in Rin's card: what is in the centre at the start is in it too
                    {
                        auto have = std::find_if(recent.begin(), recent.end(), [id](const Recent &r) { return r.id == id; });
                        if (have == recent.end()) {
                            Recent r {id, {}, {}, {}, {}, 0, false};
                            try {
                                if (const auto info = n.AppInfo()) {
                                    const winrt::hstring s = info.DisplayInfo().DisplayName();
                                    r.name = QString::fromWCharArray(s.c_str(), int(s.size()));
                                    const winrt::hstring a = info.AppUserModelId();
                                    r.aumid = QString::fromWCharArray(a.c_str(), int(a.size()));
                                }
                                r.at = qint64(winrt::clock::to_time_t(n.CreationTime())) * 1000;
                            } catch (...) {
                            }
                            if (r.at <= 0)
                                r.at = QDateTime::currentMSecsSinceEpoch();
                            if (!r.name.isEmpty() && r.name != QLatin1String("Kisel")) {
                                recent.push_back(r);
                                have = std::prev(recent.end());
                            }
                        }
                        if (have != recent.end() && wantWords && !have->read) {
                            wordsOf(n, &have->title, &have->text);
                            have->read = true;
                        }
                    }
                    if (first) {
                        seen.insert(id);
                        continue;
                    }
                    if (seen.count(id))
                        continue;
                    bool known = false;
                    for (const auto &u : unseen)
                        known = known || u.id == id;
                    if (known)
                        continue;
                    QString name, key, aumid;
                    try {
                        if (const auto info = n.AppInfo()) {
                            const winrt::hstring s = info.DisplayInfo().DisplayName();
                            name = QString::fromWCharArray(s.c_str(), int(s.size()));
                            const winrt::hstring a = info.AppUserModelId();
                            aumid = QString::fromWCharArray(a.c_str(), int(a.size()));
                            key = (name + QLatin1Char(' ') + aumid).toLower();
                        }
                    } catch (...) {
                    }
                    if (name == QLatin1String("Kisel")) { // (our own are not news)
                        seen.insert(id);
                        continue;
                    }
                    unseen.push_back({id, name, key, aumid, std::chrono::steady_clock::now()});
                }
                first = false;
                // Gone from the notification centre after having lain there a while:
                // someone dismissed it, so it has been looked at. Gone within moments is
                // something else (a passing banner, or a program such as Discord taking
                // its own notification back): nobody has looked, and Rin keeps her sign up.
                for (auto it = unseen.begin(); it != unseen.end();) {
                    const bool lain = std::chrono::steady_clock::now() - it->came > std::chrono::seconds(25);
                    if (now.count(it->id)) {
                        ++it;
                    } else if (lain && it->id != 0) {
                        it = unseen.erase(it);
                    } else {
                        it->id = 0; // (kept, and no longer tied to the centre)
                        it->came = std::chrono::steady_clock::now() - std::chrono::hours(1);
                        ++it;
                    }
                }
                for (auto it = seen.begin(); it != seen.end();)
                    it = now.count(*it) ? std::next(it) : seen.erase(it);
            } catch (...) {
            }
            // The program itself brought to the front: its notifications have been looked at.
            if (!unseen.empty()) {
                const QString front = frontProgram();
                if (front.size() >= 3) {
                    for (auto it = unseen.begin(); it != unseen.end();) {
                        if (it->key.contains(front)) {
                            if (it->id)
                                seen.insert(it->id);
                            it = unseen.erase(it);
                        } else {
                            ++it;
                        }
                    }
                }
            }
            if (dismissed.exchange(false)) {
                for (const auto &u : unseen)
                    if (u.id)
                        seen.insert(u.id);
                unseen.clear();
            }
            const int count = int(unseen.size());
            const QString app = unseen.empty() ? QString() : unseen.back().name;
            // by program, newest first
            QStringList apps;
            QVariantList counts;
            for (auto it = unseen.rbegin(); it != unseen.rend(); ++it) {
                const int at = int(apps.indexOf(it->name));
                if (at < 0) {
                    apps.append(it->name);
                    counts.append(1);
                } else {
                    counts[at] = counts[at].toInt() + 1;
                }
            }
            // the newest few, for Rin's card
            std::stable_sort(recent.begin(), recent.end(), [](const Recent &a, const Recent &b) { return a.at > b.at; });
            if (int(recent.size()) > kRecent)
                recent.resize(kRecent);
            QVariantList recentNow;
            for (const auto &r : recent) {
                bool fresh = false;
                for (const auto &u : unseen)
                    fresh = fresh || (u.id != 0 && u.id == r.id);
                recentNow.append(QVariantMap {{QStringLiteral("app"), r.name}, {QStringLiteral("aumid"), r.aumid},
                                              {QStringLiteral("title"), r.title}, {QStringLiteral("text"), r.text},
                                              {QStringLiteral("at"), r.at}, {QStringLiteral("fresh"), fresh}});
            }
            // the one program they are all from, if it is one
            QString target = unseen.empty() ? QString() : unseen.front().aumid;
            for (const auto &u : unseen)
                if (u.aumid != target)
                    target.clear();
            if (!told || count != lastCount || app != lastApp || apps != lastApps || counts != lastCounts || target != lastTarget
                || recentNow != lastRecent) {
                lastRecent = recentNow;
                lastTarget = target;
                told = true;
                lastCount = count;
                lastApp = app;
                lastApps = apps;
                lastCounts = counts;
                report(true, count, app, apps, counts, target, recentNow);
            }
            std::unique_lock lock(mutex);
            wake.wait_for(lock, std::chrono::milliseconds(1200), [this, wantWords] { return stop.load() || dismissed.load() || words.load() != wantWords; });
        }
    }
#elif defined(KISEL_WITH_DBUS1)
    // Plasma: every program shows a notification by calling Notify on the session bus,
    // and the bus lets a program of the same user listen in (as `dbus-monitor` does).
    // That is all this is: a second connection that only listens. It sends nothing after
    // asking to listen, and the bus would cut it off if it tried.
    //
    //   Notify            a notification: its program, and (only with `words` on) what it says
    //   its answer        the number the desktop gave it
    //   NotificationClosed(number, 2)   the user shut it: looked at
    //   ActionInvoked(number, ...)      the user clicked it: looked at
    //
    // One that merely runs out of time goes to Plasma's own list unread, and stays
    // unread here. Wayland tells nobody which window is in front, so "its program was
    // brought up" is not known here as it is on Windows.
    struct Note
    {
        quint32 id = 0;       // the desktop's number for it, once its answer has been seen
        quint32 serial = 0;   // the call's own number, by which the answer is matched
        QString from;         // ...and who made it
        QString name, entry;  // the program, and its desktop file's name (what starts it)
        QString title, text;
        qint64 at = 0;
        bool unseen = true;
    };
    static constexpr int kKept = 48;
    static constexpr int kRecent = 8;

    static QString plain(QString s)
    {
        static const QRegularExpression tag(QStringLiteral("<[^>]{1,200}>"));
        s.remove(tag);
        s.replace(QLatin1String("&amp;"), QLatin1String("&")).replace(QLatin1String("&lt;"), QLatin1String("<"))
            .replace(QLatin1String("&gt;"), QLatin1String(">")).replace(QLatin1String("&quot;"), QLatin1String("\""));
        return s.simplified();
    }

    static QString text(DBusMessageIter *it)
    {
        if (dbus_message_iter_get_arg_type(it) != DBUS_TYPE_STRING)
            return {};
        const char *s = nullptr;
        dbus_message_iter_get_basic(it, &s);
        return QString::fromUtf8(s);
    }

    // Notify(s program, u replaces, s icon, s summary, s body, as actions, a{sv} hints, i timeout)
    void noted(DBusMessage *m, std::vector<Note> &notes)
    {
        DBusMessageIter it;
        if (!dbus_message_iter_init(m, &it))
            return;
        Note n;
        n.name = text(&it).simplified();
        dbus_message_iter_next(&it);
        quint32 replaces = 0;
        if (dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_UINT32)
            dbus_message_iter_get_basic(&it, &replaces);
        dbus_message_iter_next(&it); // (the icon)
        dbus_message_iter_next(&it);
        const QString summary = text(&it);
        dbus_message_iter_next(&it);
        const QString body = text(&it);
        dbus_message_iter_next(&it); // (the actions)
        dbus_message_iter_next(&it);
        bool passing = false;
        if (dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_ARRAY) {
            DBusMessageIter hints;
            dbus_message_iter_recurse(&it, &hints);
            for (; dbus_message_iter_get_arg_type(&hints) == DBUS_TYPE_DICT_ENTRY; dbus_message_iter_next(&hints)) {
                DBusMessageIter pair, value;
                dbus_message_iter_recurse(&hints, &pair);
                const QString key = text(&pair);
                dbus_message_iter_next(&pair);
                if (dbus_message_iter_get_arg_type(&pair) != DBUS_TYPE_VARIANT)
                    continue;
                dbus_message_iter_recurse(&pair, &value);
                const int type = dbus_message_iter_get_arg_type(&value);
                if (key == QLatin1String("desktop-entry") && type == DBUS_TYPE_STRING) {
                    n.entry = text(&value);
                } else if (key == QLatin1String("transient") && type == DBUS_TYPE_BOOLEAN) {
                    dbus_bool_t b = 0;
                    dbus_message_iter_get_basic(&value, &b);
                    passing = passing || b;
                } else if (key == QLatin1String("urgency") && type == DBUS_TYPE_BYTE) {
                    unsigned char u = 1;
                    dbus_message_iter_get_basic(&value, &u);
                    passing = passing || u == 0; // (low: a track that changed, a volume that moved)
                }
            }
        }
        if (n.name.isEmpty())
            n.name = n.entry.mid(n.entry.lastIndexOf(QLatin1Char('.')) + 1);
        // (our own are not news; nor is what the program itself calls passing)
        if (passing || n.name.isEmpty() || n.name.compare(QLatin1String("Kisel"), Qt::CaseInsensitive) == 0)
            return;
        if (!n.name.isEmpty())
            n.name[0] = n.name.at(0).toUpper();
        if (words.load()) {
            n.title = plain(summary).left(80);
            n.text = plain(body).left(200);
        }
        n.at = QDateTime::currentMSecsSinceEpoch();
        n.serial = dbus_message_get_serial(m);
        n.from = QString::fromLatin1(dbus_message_get_sender(m));
        // one that takes the place of an earlier one is that one, new again
        if (replaces != 0) {
            for (Note &old : notes) {
                if (old.id == replaces) {
                    n.id = replaces;
                    old = n;
                    return;
                }
            }
        }
        notes.push_back(n);
        if (int(notes.size()) > kKept)
            notes.erase(notes.begin());
    }

    DBusConnection *listen()
    {
        DBusError err;
        dbus_error_init(&err);
        DBusConnection *c = dbus_bus_get_private(DBUS_BUS_SESSION, &err);
        if (!c) {
            dbus_error_free(&err);
            return nullptr;
        }
        dbus_connection_set_exit_on_disconnect(c, false);
        DBusMessage *ask = dbus_message_new_method_call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.Monitoring", "BecomeMonitor");
        const char *rules[] = {"type='method_call',interface='org.freedesktop.Notifications',member='Notify'",
                               "type='method_return',sender='org.freedesktop.Notifications'",
                               "type='signal',interface='org.freedesktop.Notifications'"};
        DBusMessageIter it, list;
        dbus_message_iter_init_append(ask, &it);
        dbus_message_iter_open_container(&it, DBUS_TYPE_ARRAY, "s", &list);
        for (const char *&rule : rules)
            dbus_message_iter_append_basic(&list, DBUS_TYPE_STRING, &rule);
        dbus_message_iter_close_container(&it, &list);
        const dbus_uint32_t flags = 0;
        dbus_message_iter_append_basic(&it, DBUS_TYPE_UINT32, &flags);
        DBusMessage *answer = dbus_connection_send_with_reply_and_block(c, ask, 3000, &err);
        dbus_message_unref(ask);
        if (!answer) {
            dbus_error_free(&err);
            dbus_connection_close(c);
            dbus_connection_unref(c);
            return nullptr;
        }
        dbus_message_unref(answer);
        return c;
    }

    void run()
    {
        DBusConnection *c = listen();
        if (!c) {
            report(false, 0, {});
            return;
        }
        std::vector<Note> notes; // oldest first
        bool told = false;
        int lastCount = -1;
        QStringList lastApps;
        QVariantList lastCounts, lastRecent;
        QString lastTarget;
        bool hadWords = false;
        auto retryAt = std::chrono::steady_clock::now();
        while (!stop) {
            if (c && !dbus_connection_get_is_connected(c)) { // (the session's bus went: asked for again now and then)
                dbus_connection_close(c);
                dbus_connection_unref(c);
                c = nullptr;
                retryAt = std::chrono::steady_clock::now() + std::chrono::seconds(5);
            }
            if (!c) {
                if (std::chrono::steady_clock::now() >= retryAt) {
                    c = listen();
                    retryAt = std::chrono::steady_clock::now() + std::chrono::seconds(5);
                }
                if (!c) {
                    std::unique_lock lock(mutex);
                    wake.wait_for(lock, std::chrono::milliseconds(500), [this] { return stop.load(); });
                    continue;
                }
            }
            dbus_connection_read_write(c, 400);
            while (DBusMessage *m = dbus_connection_pop_message(c)) {
                const int type = dbus_message_get_type(m);
                if (type == DBUS_MESSAGE_TYPE_METHOD_CALL && dbus_message_is_method_call(m, "org.freedesktop.Notifications", "Notify")) {
                    noted(m, notes);
                } else if (type == DBUS_MESSAGE_TYPE_METHOD_RETURN) {
                    const quint32 serial = dbus_message_get_reply_serial(m);
                    const char *to = dbus_message_get_destination(m);
                    quint32 id = 0;
                    if (to && dbus_message_get_args(m, nullptr, DBUS_TYPE_UINT32, &id, DBUS_TYPE_INVALID))
                        for (Note &n : notes)
                            if (n.serial == serial && n.serial != 0 && n.from == QLatin1String(to)) {
                                n.id = id;
                                n.serial = 0;
                            }
                } else if (type == DBUS_MESSAGE_TYPE_SIGNAL) {
                    quint32 id = 0, why = 0;
                    const bool shut = dbus_message_is_signal(m, "org.freedesktop.Notifications", "NotificationClosed")
                                   && dbus_message_get_args(m, nullptr, DBUS_TYPE_UINT32, &id, DBUS_TYPE_UINT32, &why, DBUS_TYPE_INVALID) && why == 2;
                    DBusMessageIter it;
                    bool clicked = false;
                    if (dbus_message_is_signal(m, "org.freedesktop.Notifications", "ActionInvoked") && dbus_message_iter_init(m, &it)
                        && dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_UINT32) {
                        dbus_message_iter_get_basic(&it, &id);
                        clicked = true;
                    }
                    if ((shut || clicked) && id != 0)
                        for (Note &n : notes)
                            if (n.id == id)
                                n.unseen = false;
                }
                dbus_message_unref(m);
            }
            const bool wantWords = words.load();
            if (hadWords && !wantWords) // (switched off: what was read is let go)
                for (Note &n : notes) {
                    n.title.clear();
                    n.text.clear();
                }
            hadWords = wantWords;
            if (dismissed.exchange(false))
                for (Note &n : notes)
                    n.unseen = false;

            int count = 0;
            QString app, target;
            bool oneTarget = true;
            QStringList apps;      // by program, newest first
            QVariantList counts;
            for (auto n = notes.rbegin(); n != notes.rend(); ++n) {
                if (!n->unseen)
                    continue;
                if (count++ == 0) {
                    app = n->name;
                    target = n->entry;
                } else if (n->entry != target) {
                    oneTarget = false;
                }
                const int at = int(apps.indexOf(n->name));
                if (at < 0) {
                    apps.append(n->name);
                    counts.append(1);
                } else {
                    counts[at] = counts[at].toInt() + 1;
                }
            }
            if (!oneTarget)
                target.clear();
            QVariantList recentNow;
            for (auto n = notes.rbegin(); n != notes.rend() && recentNow.size() < kRecent; ++n)
                recentNow.append(QVariantMap {{QStringLiteral("app"), n->name}, {QStringLiteral("aumid"), n->entry},
                                              {QStringLiteral("title"), n->title}, {QStringLiteral("text"), n->text},
                                              {QStringLiteral("at"), n->at}, {QStringLiteral("fresh"), n->unseen}});
            if (!told || count != lastCount || apps != lastApps || counts != lastCounts || target != lastTarget || recentNow != lastRecent) {
                told = true;
                lastCount = count;
                lastApps = apps;
                lastCounts = counts;
                lastTarget = target;
                lastRecent = recentNow;
                report(true, count, app, apps, counts, target, recentNow);
            }
        }
        if (c) {
            dbus_connection_close(c);
            dbus_connection_unref(c);
        }
    }
#else
    void run() { report(false, 0, {}); }
#endif
};

#ifndef Q_OS_WIN
namespace {
// Start the program a desktop file names (a notification says which is its own), the
// way the launcher would. One that is running already shows its window.
void launch(const QString &entry)
{
    if (entry.isEmpty() || entry.contains(QLatin1Char('/')))
        return;
    const QString file = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, entry + QStringLiteral(".desktop"));
    if (file.isEmpty())
        return;
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return;
    bool main = false;
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            main = line == QLatin1String("[Desktop Entry]");
            continue;
        }
        if (!main || !line.startsWith(QLatin1String("Exec=")))
            continue;
        QStringList words = QProcess::splitCommand(line.mid(5));
        // (the places for files and addresses, of which there are none)
        words.removeIf([](const QString &w) { return w.size() == 2 && w.at(0) == QLatin1Char('%'); });
        if (!words.isEmpty()) {
            const QString program = words.takeFirst();
            QProcess::startDetached(program, words);
        }
        return;
    }
}
} // namespace
#endif

Notices::Notices(QObject *parent)
    : QObject(parent)
    , m_worker(std::make_unique<Worker>())
{
    m_worker->owner = this;
    // KISEL_DEMO_NOTE=<ms>: act out notifications from "Telegram" and "Discord" at that time (development)
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_NOTE"); at > 0) {
        m_demo = true;
        m_available = true;
        const qint64 t = QDateTime::currentMSecsSinceEpoch();
        const auto one = [t](const char *app, const char *title, const char *text, int minutesAgo, bool fresh) {
            return QVariantMap {{QStringLiteral("app"), QString::fromLatin1(app)}, {QStringLiteral("aumid"), QString()},
                                {QStringLiteral("title"), QString::fromLatin1(title)}, {QStringLiteral("text"), QString::fromLatin1(text)},
                                {QStringLiteral("at"), t - qint64(minutesAgo) * 60000}, {QStringLiteral("fresh"), fresh}};
        };
        // (KISEL_DEMO_WORDS=1: ...with their words, as if the key in Rin's card were on)
        const bool w = qEnvironmentVariableIsSet("KISEL_DEMO_WORDS");
        m_words = w;
        m_recent = {one("Telegram", w ? "Sasha" : "", w ? "Are you coming tonight? We start at eight." : "", 0, true),
                    one("Discord", w ? "#general" : "", w ? "The build is green again" : "", 4, true),
                    one("Telegram", w ? "Mum" : "", w ? "Call me when you can" : "", 37, false),
                    one("Steam", w ? "Download complete" : "", w ? "Hollow Knight is ready to play" : "", 190, false)};
        QTimer::singleShot(at, this, [this] { m_count = 3; m_app = QStringLiteral("Telegram");
            m_apps = {QStringLiteral("Telegram"), QStringLiteral("Discord")}; m_counts = {2, 1}; emit changed(); });
        // KISEL_DEMO_NOTE_END=<ms>: ...and they are looked at
        if (const int end = qEnvironmentVariableIntValue("KISEL_DEMO_NOTE_END"); end > 0)
            QTimer::singleShot(end, this, &Notices::dismiss);
        return;
    }
    m_worker->thread = std::thread([w = m_worker.get()] { w->run(); });
}

Notices::~Notices()
{
    m_worker->stop = true;
    m_worker->wake.notify_one();
    if (m_worker->thread.joinable())
        m_worker->thread.join();
}

void Notices::setWords(bool on)
{
    if (on == m_words)
        return;
    m_words = on;
    m_worker->words = on;
    m_worker->wake.notify_one();
    emit changed();
}

void Notices::openRecent(int index)
{
#ifdef Q_OS_WIN
    const QString aumid = m_recent.value(index).toMap().value(QStringLiteral("aumid")).toString();
    if (aumid.isEmpty())
        return;
    const QString entry = QStringLiteral("shell:AppsFolder\\") + aumid;
    ShellExecuteW(nullptr, L"open", L"explorer.exe", reinterpret_cast<LPCWSTR>(entry.utf16()), nullptr, SW_SHOWNORMAL);
#else
    launch(m_recent.value(index).toMap().value(QStringLiteral("aumid")).toString());
#endif
}

void Notices::apply(bool available, int count, const QString &app, const QStringList &apps, const QVariantList &counts,
                    const QString &target, const QVariantList &recent)
{
    m_target = target;
    if (m_demo || (available == m_available && count == m_count && app == m_app && apps == m_apps && counts == m_counts && recent == m_recent))
        return;
    m_recent = recent;
    m_available = available;
    m_count = count;
    m_app = app;
    m_apps = apps;
    m_counts = counts;
    emit changed();
}

void Notices::dismiss()
{
    if (m_demo) {
        m_count = 0;
        m_apps.clear();
        m_counts.clear();
        emit changed();
        return;
    }
    m_worker->dismissed = true;
    m_worker->wake.notify_one();
    // (at once here; the thread follows)
    if (m_count > 0) {
        m_count = 0;
        m_apps.clear();
        m_counts.clear();
        emit changed();
    }
}

void Notices::open()
{
    const QString target = m_target;
    dismiss();
#ifdef Q_OS_WIN
    if (m_demo)
        return;
    // all from one program: bring that program up, as its Start menu entry would (a
    // program that is already running shows its window)
    if (!target.isEmpty()) {
        const QString entry = QStringLiteral("shell:AppsFolder\\") + target;
        ShellExecuteW(nullptr, L"open", L"explorer.exe", reinterpret_cast<LPCWSTR>(entry.utf16()), nullptr, SW_SHOWNORMAL);
        return;
    }
    // Win+N: the notification centre
    INPUT in[4] = {};
    for (INPUT &e : in)
        e.type = INPUT_KEYBOARD;
    in[0].ki.wVk = VK_LWIN;
    in[1].ki.wVk = 'N';
    in[2].ki.wVk = 'N';
    in[2].ki.dwFlags = KEYEVENTF_KEYUP;
    in[3].ki.wVk = VK_LWIN;
    in[3].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(4, in, sizeof(INPUT));
#else
    // all from one program: that program is brought up (Plasma has no call that opens its
    // own list of notifications, so from several nothing more is done)
    if (!m_demo)
        launch(target);
#endif
}

} // namespace kisel
