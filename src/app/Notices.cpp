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

#include "Notices.h"

#include <QTimer>

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

    void report(bool available, int count, const QString &app, const QStringList &apps = {}, const QVariantList &counts = {},
                const QString &target = {})
    {
        QMetaObject::invokeMethod(owner, [o = owner, available, count, app, apps, counts, target] {
            o->apply(available, count, app, apps, counts, target); }, Qt::QueuedConnection);
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
        while (!stop) {
            try {
                const auto list = listener.GetNotificationsAsync(un::NotificationKinds::Toast).get();
                std::set<quint32> now;
                for (const auto &n : list) {
                    const quint32 id = n.Id();
                    now.insert(id);
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
            // the one program they are all from, if it is one
            QString target = unseen.empty() ? QString() : unseen.front().aumid;
            for (const auto &u : unseen)
                if (u.aumid != target)
                    target.clear();
            if (!told || count != lastCount || app != lastApp || apps != lastApps || counts != lastCounts || target != lastTarget) {
                lastTarget = target;
                told = true;
                lastCount = count;
                lastApp = app;
                lastApps = apps;
                lastCounts = counts;
                report(true, count, app, apps, counts, target);
            }
            std::unique_lock lock(mutex);
            wake.wait_for(lock, std::chrono::milliseconds(1200), [this] { return stop.load() || dismissed.load(); });
        }
    }
#else
    void run() { report(false, 0, {}); }
#endif
};

Notices::Notices(QObject *parent)
    : QObject(parent)
    , m_worker(std::make_unique<Worker>())
{
    m_worker->owner = this;
    // KISEL_DEMO_NOTE=<ms>: act out notifications from "Telegram" and "Discord" at that time (development)
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_NOTE"); at > 0) {
        m_demo = true;
        m_available = true;
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

void Notices::apply(bool available, int count, const QString &app, const QStringList &apps, const QVariantList &counts,
                    const QString &target)
{
    m_target = target;
    if (m_demo || (available == m_available && count == m_count && app == m_app && apps == m_apps && counts == m_counts))
        return;
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
#endif
}

} // namespace kisel
