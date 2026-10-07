#include <QtGlobal>

#ifdef Q_OS_WIN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <windows.h>
#endif

#include "NetMon.h"

#include <QTimer>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace kisel {

namespace {
constexpr int kHistory = 30;     // readings kept: a minute at one every two seconds
constexpr int kLateMs = 250;     // an answer slower than this is late
constexpr int kLostForDown = 3;  // echoes lost in a row before the connection counts as down
constexpr int kLateForSlow = 3;
} // namespace

struct NetMon::Worker
{
    NetMon *owner = nullptr;
    std::thread thread;
    std::mutex mutex;
    std::condition_variable wake;
    std::atomic<bool> stop {false};

#ifdef Q_OS_WIN
    // bytes in and out over every adapter that is up (not the loopback)
    static bool counters(quint64 &in, quint64 &out)
    {
        PMIB_IF_TABLE2 table = nullptr;
        if (GetIfTable2(&table) != NO_ERROR)
            return false;
        in = out = 0;
        for (ULONG i = 0; i < table->NumEntries; ++i) {
            const MIB_IF_ROW2 &row = table->Table[i];
            // (hardware interfaces only: the same bytes are counted again on the filter
            // and virtual layers stacked on top of them)
            if (row.OperStatus != IfOperStatusUp || row.Type == IF_TYPE_SOFTWARE_LOOPBACK || !row.InterfaceAndOperStatusFlags.HardwareInterface)
                continue;
            in += row.InOctets;
            out += row.OutOctets;
        }
        FreeMibTable(table);
        return true;
    }

    void run()
    {
        const HANDLE icmp = IcmpCreateFile();
        IN_ADDR target {};
        InetPtonA(AF_INET, "1.1.1.1", &target);
        char payload[32] = "kisel";
        char reply[sizeof(ICMP_ECHO_REPLY) + sizeof(payload) + 8];
        quint64 lastIn = 0, lastOut = 0;
        bool have = counters(lastIn, lastOut);
        auto lastAt = std::chrono::steady_clock::now();
        while (!stop) {
            int ping = -1;
            if (icmp != INVALID_HANDLE_VALUE
                && IcmpSendEcho(icmp, target.S_un.S_addr, payload, sizeof(payload), nullptr, reply, sizeof(reply), 1500) > 0) {
                const auto *r = reinterpret_cast<const ICMP_ECHO_REPLY *>(reply);
                if (r->Status == IP_SUCCESS)
                    ping = int(r->RoundTripTime);
            }
            quint64 in = 0, out = 0;
            qreal down = 0, up = 0;
            const auto now = std::chrono::steady_clock::now();
            if (counters(in, out)) {
                const qreal dt = std::chrono::duration<qreal>(now - lastAt).count();
                if (have && dt > 0.2 && in >= lastIn && out >= lastOut) {
                    down = qreal(in - lastIn) / dt;
                    up = qreal(out - lastOut) / dt;
                }
                lastIn = in;
                lastOut = out;
                lastAt = now;
                have = true;
            }
            QMetaObject::invokeMethod(owner, [o = owner, ping, down, up] { o->apply(ping, down, up); }, Qt::QueuedConnection);
            std::unique_lock lock(mutex);
            wake.wait_for(lock, std::chrono::milliseconds(2000), [this] { return stop.load(); });
        }
        if (icmp != INVALID_HANDLE_VALUE)
            IcmpCloseHandle(icmp);
    }
#else
    void run() {}
#endif
};

NetMon::NetMon(QObject *parent)
    : QObject(parent)
    , m_worker(std::make_unique<Worker>())
{
    m_worker->owner = this;
    // KISEL_DEMO_NET=<ms>: act out the connection going down at that time and coming
    // back six seconds later (development); steady readings otherwise
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_NET"); at > 0) {
        m_demo = true;
        auto *tick = new QTimer(this);
        tick->setInterval(400);
        auto *clock = new int(0);
        connect(tick, &QTimer::timeout, this, [this, at, clock] {
            *clock += 400;
            const bool down = *clock >= at && *clock < at + 6000;
            apply(down ? -1 : 24 + (*clock / 400) % 7 * 3, down ? 0 : 2.4e6, down ? 0 : 3.1e5);
        });
        connect(this, &QObject::destroyed, [clock] { delete clock; });
        tick->start();
        return;
    }
    if (available())
        m_worker->thread = std::thread([w = m_worker.get()] { w->run(); });
}

NetMon::~NetMon()
{
    m_worker->stop = true;
    m_worker->wake.notify_one();
    if (m_worker->thread.joinable())
        m_worker->thread.join();
}

bool NetMon::available() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return m_demo;
#endif
}

void NetMon::apply(int ping, qreal down, qreal up)
{
    m_ping = ping;
    m_down = down;
    m_up = up;
    m_history.append(ping);
    while (m_history.size() > kHistory)
        m_history.removeFirst();

    m_lost = ping < 0 ? m_lost + 1 : 0;
    m_late = ping > kLateMs ? m_late + 1 : 0;
    const bool wasOnline = m_online;
    if (m_lost >= kLostForDown)
        m_online = false;
    else if (ping >= 0)
        m_online = true;
    m_slow = m_online && m_late >= kLateForSlow;
    if (!wasOnline && m_online) {
        m_justBack = true;
        QTimer::singleShot(6000, this, [this] { m_justBack = false; emit changed(); });
    }
    emit changed();
}

} // namespace kisel
