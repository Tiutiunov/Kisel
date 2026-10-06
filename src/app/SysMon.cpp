#include "SysMon.h"

#ifdef Q_OS_WIN
#include <qt_windows.h>
#else
#include <QFile>
#endif

namespace kisel {

SysMon::SysMon(QObject *parent)
    : QObject(parent)
{
    for (int i = 0; i < 36; ++i)
        m_history.append(0.0);
    readCpu(m_lastIdle, m_lastTotal);
    m_timer.setInterval(1500);
    connect(&m_timer, &QTimer::timeout, this, &SysMon::read);
    if (available()) {
        m_timer.start();
        QTimer::singleShot(300, this, &SysMon::read); // a first reading soon, not in a second and a half
    }
}

bool SysMon::available() const
{
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
    return true;
#else
    return false;
#endif
}

// idle and total processor time since boot, in whatever unit the system counts
bool SysMon::readCpu(quint64 &idle, quint64 &total) const
{
#ifdef Q_OS_WIN
    FILETIME i, k, u;
    if (!GetSystemTimes(&i, &k, &u))
        return false;
    const auto v = [](const FILETIME &f) { return (quint64(f.dwHighDateTime) << 32) | f.dwLowDateTime; };
    idle = v(i);
    total = v(k) + v(u); // (kernel time includes idle time)
    return true;
#elif defined(Q_OS_LINUX)
    QFile f(QStringLiteral("/proc/stat"));
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QList<QByteArray> p = f.readLine().simplified().split(' '); // cpu user nice system idle iowait irq softirq steal
    if (p.size() < 6)
        return false;
    total = 0;
    for (int n = 1; n < p.size() && n <= 8; ++n)
        total += p[n].toULongLong();
    idle = p[4].toULongLong() + p[5].toULongLong();
    return true;
#else
    Q_UNUSED(idle); Q_UNUSED(total);
    return false;
#endif
}

void SysMon::read()
{
    quint64 idle = 0, total = 0;
    if (readCpu(idle, total) && total > m_lastTotal) {
        m_cpu = qBound(0.0, 1.0 - double(idle - m_lastIdle) / double(total - m_lastTotal), 1.0);
        m_lastIdle = idle;
        m_lastTotal = total;
    }

#ifdef Q_OS_WIN
    MEMORYSTATUSEX ms;
    ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms) && ms.ullTotalPhys > 0) {
        const double gb = 1024.0 * 1024.0 * 1024.0;
        m_memTotal = double(ms.ullTotalPhys) / gb;
        m_memUsed = double(ms.ullTotalPhys - ms.ullAvailPhys) / gb;
        m_mem = m_memUsed / m_memTotal;
    }
    SYSTEM_POWER_STATUS ps;
    if (GetSystemPowerStatus(&ps)) {
        m_hasBattery = !(ps.BatteryFlag & 128) && ps.BatteryFlag != 255 && ps.BatteryLifePercent != 255;
        m_battery = m_hasBattery ? ps.BatteryLifePercent / 100.0 : 1.0;
        m_charging = ps.ACLineStatus != 0;
    }
#elif defined(Q_OS_LINUX)
    QFile f(QStringLiteral("/proc/meminfo"));
    if (f.open(QIODevice::ReadOnly)) {
        double totalKb = 0, availKb = 0;
        while (!f.atEnd()) {
            const QByteArray line = f.readLine();
            if (line.startsWith("MemTotal:")) totalKb = line.mid(9).simplified().split(' ').value(0).toDouble();
            else if (line.startsWith("MemAvailable:")) availKb = line.mid(13).simplified().split(' ').value(0).toDouble();
        }
        if (totalKb > 0) {
            m_memTotal = totalKb / 1024.0 / 1024.0;
            m_memUsed = (totalKb - availKb) / 1024.0 / 1024.0;
            m_mem = m_memUsed / m_memTotal;
        }
    }
#endif

    m_history.removeFirst();
    m_history.append(m_cpu);
    m_hot = m_cpu > 0.9 ? m_hot + 1 : 0;
    m_worry = m_hasBattery && !m_charging && m_battery < 0.15 ? QStringLiteral("battery")
            : m_mem > 0.92 ? QStringLiteral("mem")
            : m_hot >= 4 ? QStringLiteral("cpu")
            : QString();
    emit changed();
}

} // namespace kisel
