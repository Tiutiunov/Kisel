#include <QtGlobal>

#ifdef Q_OS_WIN
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.UI.Notifications.Management.h>
#include <windows.h>
#endif

#include "Notices.h"

#include <QTimer>

#include <atomic>
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

    void report(bool available, int count, const QString &app)
    {
        QMetaObject::invokeMethod(owner, [o = owner, available, count, app] { o->apply(available, count, app); },
                                  Qt::QueuedConnection);
    }

#ifdef Q_OS_WIN
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
        std::vector<std::pair<quint32, QString>> unseen;   // in the order they came
        bool first = true;
        bool told = false;
        int lastCount = -1;
        QString lastApp;
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
                        known = known || u.first == id;
                    if (known)
                        continue;
                    QString name;
                    try {
                        if (const auto info = n.AppInfo()) {
                            const winrt::hstring s = info.DisplayInfo().DisplayName();
                            name = QString::fromWCharArray(s.c_str(), int(s.size()));
                        }
                    } catch (...) {
                    }
                    if (name == QLatin1String("Kisel")) { // (our own are not news)
                        seen.insert(id);
                        continue;
                    }
                    unseen.emplace_back(id, name);
                }
                first = false;
                // gone from the notification centre: looked at
                for (auto it = unseen.begin(); it != unseen.end();)
                    it = now.count(it->first) ? it + 1 : unseen.erase(it);
                for (auto it = seen.begin(); it != seen.end();)
                    it = now.count(*it) ? std::next(it) : seen.erase(it);
            } catch (...) {
            }
            if (dismissed.exchange(false)) {
                for (const auto &u : unseen)
                    seen.insert(u.first);
                unseen.clear();
            }
            const int count = int(unseen.size());
            const QString app = unseen.empty() ? QString() : unseen.back().second;
            if (!told || count != lastCount || app != lastApp) {
                told = true;
                lastCount = count;
                lastApp = app;
                report(true, count, app);
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
    // KISEL_DEMO_NOTE=<ms>: act out a notification from "Telegram" at that time (development)
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_NOTE"); at > 0) {
        m_demo = true;
        m_available = true;
        QTimer::singleShot(at, this, [this] { m_count = 2; m_app = QStringLiteral("Telegram"); emit changed(); });
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

void Notices::apply(bool available, int count, const QString &app)
{
    if (m_demo || (available == m_available && count == m_count && app == m_app))
        return;
    m_available = available;
    m_count = count;
    m_app = app;
    emit changed();
}

void Notices::dismiss()
{
    if (m_demo) {
        m_count = 0;
        emit changed();
        return;
    }
    m_worker->dismissed = true;
    m_worker->wake.notify_one();
    // (at once here; the thread follows)
    if (m_count > 0) {
        m_count = 0;
        emit changed();
    }
}

void Notices::open()
{
    dismiss();
#ifdef Q_OS_WIN
    if (m_demo)
        return;
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
