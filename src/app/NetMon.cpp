#include <QtGlobal>

#ifdef Q_OS_WIN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <windows.h>
#endif
#ifdef Q_OS_LINUX
#include <QFile>
#include <QFileInfo>
#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/ip_icmp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
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
constexpr qreal kFast = 500 * 1024.0;   // bytes a second: this much coming in is a download, if it lasts
constexpr qreal kIdle = 100 * 1024.0;   // ...and under this it is over, if that lasts
constexpr int kReadingsToTell = 4;      // eight seconds
constexpr qreal kStep = 2.0;            // seconds between readings
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
#elif defined(Q_OS_LINUX)
    // bytes in and out over every adapter there is in hardware (not the loopback, not
    // the bridges and tunnels laid over them, where the same bytes are counted again)
    static bool counters(quint64 &in, quint64 &out)
    {
        QFile f(QStringLiteral("/proc/net/dev"));
        if (!f.open(QIODevice::ReadOnly))
            return false;
        in = out = 0;
        for (int n = 0; n < 200; ++n) {
            const QByteArray line = f.readLine();
            if (line.isEmpty())
                break;
            const int colon = line.indexOf(':');
            if (colon < 0)
                continue;
            const QString name = QString::fromLatin1(line.left(colon)).trimmed();
            if (!QFileInfo::exists(QStringLiteral("/sys/class/net/%1/device").arg(name)))
                continue;
            const QList<QByteArray> p = line.mid(colon + 1).simplified().split(' '); // 8 figures received, then 8 sent
            if (p.size() < 9)
                continue;
            in += p[0].toULongLong();
            out += p[8].toULongLong();
        }
        return true;
    }

    // One echo to 1.1.1.1 and how long its answer took, in ms; -1 if none came. Linux
    // lets an ordinary program send an echo through a socket made for just that. Where
    // a system does not (it is a setting), the time it takes to be let in at the same
    // address's door stands for it: one handshake there and back.
    int sock = -1;
    bool viaDoor = false;
    quint16 seq = 0;

    int echo()
    {
        using clock = std::chrono::steady_clock;
        sockaddr_in to {};
        to.sin_family = AF_INET;
        inet_pton(AF_INET, "1.1.1.1", &to.sin_addr);
        if (sock < 0 && !viaDoor) {
            sock = ::socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, IPPROTO_ICMP);
            if (sock < 0)
                viaDoor = true;
        }
        const auto began = clock::now();
        const auto since = [&began] { return int(std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - began).count()); };
        if (!viaDoor) {
            struct { icmphdr head; char body[32]; } packet {};
            packet.head.type = ICMP_ECHO;
            packet.head.un.echo.sequence = htons(++seq);
            std::memcpy(packet.body, "kisel", 5);
            if (::sendto(sock, &packet, sizeof packet, 0, reinterpret_cast<sockaddr *>(&to), sizeof to) < 0)
                return -1; // (no network at all just now)
            while (since() < 1500) {
                pollfd p {sock, POLLIN, 0};
                if (::poll(&p, 1, 1500 - since()) <= 0)
                    return -1;
                char answer[128];
                const ssize_t got = ::recv(sock, answer, sizeof answer, 0);
                if (got < ssize_t(sizeof(icmphdr)))
                    continue;
                icmphdr head;
                std::memcpy(&head, answer, sizeof head);
                if (head.type == ICMP_ECHOREPLY && ntohs(head.un.echo.sequence) == seq)
                    return qMax(1, since());
            }
            return -1;
        }
        to.sin_port = htons(443);
        const int s = ::socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        if (s < 0)
            return -1;
        int ms = -1;
        if (::connect(s, reinterpret_cast<sockaddr *>(&to), sizeof to) == 0 || errno == EINPROGRESS) {
            pollfd p {s, POLLOUT, 0};
            int err = 0;
            socklen_t len = sizeof err;
            if (::poll(&p, 1, 1500) > 0 && ::getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0)
                ms = qMax(1, since());
        }
        ::close(s);
        return ms;
    }

    void run()
    {
        quint64 lastIn = 0, lastOut = 0;
        bool have = counters(lastIn, lastOut);
        auto lastAt = std::chrono::steady_clock::now();
        while (!stop) {
            const int ping = echo();
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
        if (sock >= 0)
            ::close(sock);
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
    // back six seconds later (development); steady readings otherwise.
    // KISEL_DEMO_FETCH=<ms>: act out a download from that time for twelve seconds.
    const int fetchAt = qEnvironmentVariableIntValue("KISEL_DEMO_FETCH");
    if (const int at = fetchAt > 0 ? 100000000 : qEnvironmentVariableIntValue("KISEL_DEMO_NET"); at > 0) {
        m_demo = true;
        auto *tick = new QTimer(this);
        tick->setInterval(fetchAt > 0 ? 2000 : 400);
        auto *clock = new int(0);
        connect(tick, &QTimer::timeout, this, [this, at, clock, fetchAt] {
            *clock += fetchAt > 0 ? 2000 : 400;
            if (fetchAt > 0) {
                const bool on = *clock >= fetchAt && *clock < fetchAt + 12000;
                apply(22 + (*clock / 2000) % 5 * 2, on ? 6.3e6 : 2.1e4, 4.0e4);
                return;
            }
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
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
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
    // a download: a lot coming in, steadily
    if (!m_downloading) {
        if (down >= kFast) {
            ++m_fast;
            m_pending += down * kStep;
            if (m_fast >= kReadingsToTell) {
                m_downloading = true;
                m_justFetched = false;
                m_fetched = m_pending;
                m_idle = 0;
            }
        } else {
            m_fast = 0;
            m_pending = 0;
        }
    } else {
        m_fetched += down * kStep;
        m_idle = down < kIdle ? m_idle + 1 : 0;
        if (m_idle >= kReadingsToTell) {
            m_downloading = false;
            m_fast = 0;
            m_pending = 0;
            m_justFetched = true;
            QTimer::singleShot(8000, this, [this] { m_justFetched = false; emit changed(); });
        }
    }
    if (!wasOnline && m_online) {
        m_justBack = true;
        QTimer::singleShot(6000, this, [this] { m_justBack = false; emit changed(); });
    }
    emit changed();
}

} // namespace kisel
