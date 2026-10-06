#include "SysMon.h"

#ifdef Q_OS_WIN
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <qt_windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <shellapi.h>
#include <vector>
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
#ifdef Q_OS_WIN
    for (const char *var : {"ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"}) {
        const QString path = qEnvironmentVariable(var) + QStringLiteral("/Mem Reduct/memreduct.exe");
        if (QFileInfo::exists(path)) { m_cleaner = QDir::toNativeSeparators(path); break; }
    }
    if (!m_cleaner.isEmpty()) {
        m_cleanerIni = qEnvironmentVariable("APPDATA") + QStringLiteral("/Henry++/Mem Reduct/memreduct.ini");
        m_iniStamp = QFileInfo(m_cleanerIni).lastModified().toMSecsSinceEpoch();
        m_lastReduct = lastReduct();
    }
#endif
#ifdef Q_OS_WIN
    // every engine of every graphics card, per process; summed up in readGpu()
    PDH_HQUERY query = nullptr;
    PDH_HCOUNTER counter = nullptr;
    if (PdhOpenQueryW(nullptr, 0, &query) == ERROR_SUCCESS) {
        if (PdhAddEnglishCounterW(query, L"\\GPU Engine(*)\\Utilization Percentage", 0, &counter) == ERROR_SUCCESS) {
            m_gpuQuery = query;
            m_gpuCounter = counter;
            PdhCollectQueryData(query); // (a rate: the first reading only sets the base)
        } else {
            PdhCloseQuery(query);
        }
    }
#endif
    m_timer.setInterval(1500);
    connect(&m_timer, &QTimer::timeout, this, &SysMon::read);
    if (available()) {
        m_timer.start();
        QTimer::singleShot(300, this, &SysMon::read); // a first reading soon, not in a second and a half
    }
    // KISEL_DEMO_SWEEP=<ms>: act out a clean at that time, to look at Teto sweeping
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_SWEEP"); at > 0)
        QTimer::singleShot(at, this, &SysMon::clean);
}

SysMon::~SysMon()
{
#ifdef Q_OS_WIN
    if (m_gpuQuery)
        PdhCloseQuery(static_cast<PDH_HQUERY>(m_gpuQuery));
#endif
}

// The graphics card's load: Windows counts it per process and per engine. The 3D engines
// are added up for each card, and the busiest card is the figure.
void SysMon::readGpu()
{
#ifdef Q_OS_WIN
    if (!m_gpuQuery || PdhCollectQueryData(static_cast<PDH_HQUERY>(m_gpuQuery)) != ERROR_SUCCESS)
        return;
    DWORD bytes = 0, count = 0;
    const auto counter = static_cast<PDH_HCOUNTER>(m_gpuCounter);
    if (PdhGetFormattedCounterArrayW(counter, PDH_FMT_DOUBLE, &bytes, &count, nullptr) != PDH_MORE_DATA || bytes == 0)
        return;
    std::vector<char> buffer(bytes);
    auto *items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W *>(buffer.data());
    if (PdhGetFormattedCounterArrayW(counter, PDH_FMT_DOUBLE, &bytes, &count, items) != ERROR_SUCCESS)
        return;
    QHash<QString, double> cards; // "luid_..._phys_n" -> the sum of its 3D engines
    for (DWORD i = 0; i < count; ++i) {
        const QString name = QString::fromWCharArray(items[i].szName);
        if (!name.contains(QLatin1String("engtype_3D")) || items[i].FmtValue.CStatus != ERROR_SUCCESS)
            continue;
        const int from = name.indexOf(QLatin1String("luid_")), to = name.indexOf(QLatin1String("_eng_"));
        cards[from >= 0 && to > from ? name.mid(from, to - from) : QString()] += items[i].FmtValue.doubleValue;
    }
    double busiest = 0;
    for (const double v : std::as_const(cards))
        busiest = qMax(busiest, v);
    m_hasGpu = count > 0;
    m_gpu = qBound(0.0, busiest / 100.0, 1.0);
#endif
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

// one value from Mem Reduct's settings file (empty if it is not there)
QByteArray SysMon::cleanerSetting(const char *key) const
{
#ifdef Q_OS_WIN
    QFile f(m_cleanerIni);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QByteArray start = QByteArray(key) + '=';
    while (!f.atEnd()) {
        const QByteArray line = f.readLine().trimmed();
        if (line.startsWith(start))
            return line.mid(start.size());
    }
#else
    Q_UNUSED(key);
#endif
    return {};
}

// when Mem Reduct last cleaned, by its own account (0 if it has not said)
qint64 SysMon::lastReduct() const
{
    return cleanerSetting("StatisticLastReduct").toLongLong();
}

// the news of a clean, kept up for eight seconds
void SysMon::announce(qreal freed)
{
    m_freed = qMax(0.0, freed);
    m_cleaning = false;
    m_justCleaned = true;
    emit changed();
    QTimer::singleShot(8000, this, [this] { m_justCleaned = false; emit changed(); });
}

void SysMon::clean()
{
    const bool rehearsal = qEnvironmentVariableIsSet("KISEL_DEMO_SWEEP"); // (development: the show without the cleaning)
    if ((m_cleaner.isEmpty() && !rehearsal) || m_cleaning)
        return;
#ifdef Q_OS_WIN
    if (!rehearsal) {
    // "open" lets Windows ask for the rights Mem Reduct needs; declined, nothing happens
    const auto r = reinterpret_cast<quintptr>(ShellExecuteW(nullptr, L"open", reinterpret_cast<LPCWSTR>(m_cleaner.utf16()), L"-clean", nullptr, SW_HIDE));
    if (r <= 32)
        return;
    }
#endif
    const qreal before = m_memUsed;
    m_cleaning = true;
    m_justCleaned = false;
    emit changed();
    QTimer::singleShot(4000, this, [this, before] {
        read();
        m_lastReduct = lastReduct(); // (ours: not to be announced a second time)
        announce(before - m_memUsed);
    });
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
    readGpu();
    // a clean Mem Reduct did by itself: its settings file has a newer "last clean"
    if (!m_cleanerIni.isEmpty()) {
        const qint64 stamp = QFileInfo(m_cleanerIni).lastModified().toMSecsSinceEpoch();
        if (stamp != m_iniStamp) {
            m_iniStamp = stamp;
            const qint64 last = lastReduct();
            if (last != m_lastReduct) {
                m_lastReduct = last;
                // (not if the user has told Mem Reduct to keep its results to itself)
                if (!m_cleaning && !m_justCleaned && cleanerSetting("BalloonCleanResults") != "false")
                    announce(qMax(m_recent[0], qMax(m_recent[1], m_recent[2])) - m_memUsed);
            }
        }
    }
    m_recent[0] = m_recent[1]; m_recent[1] = m_recent[2]; m_recent[2] = m_memUsed;
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
    m_worry = m_mem > 0.92 ? QStringLiteral("mem")
            : m_hot >= 4 ? QStringLiteral("cpu")
            : QString();
    emit changed();
}

} // namespace kisel
