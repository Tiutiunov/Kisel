#include "SysMon.h"

#include "PartNames.h"

#ifdef Q_OS_WIN
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSettings>
#include <QStorageInfo>
#include <QThread>
#include <qt_windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <psapi.h>
#include <thread>
#include <vector>
#else
#include <QFile>
#include <QStorageInfo>
#include <QThread>
#endif

#include <QThreadPool>
#include <QVariantMap>

namespace kisel {

// (see SysMon.h; everything in it is touched by the working thread alone, and its
// figures are handed to the interface's thread as a copy)
struct SysMon::Probe
{
    int m_cpuFan = -1, m_gpuFan = -1, m_cpuTemp = -1, m_gpuTemp = -1;
    int m_cpuMhz = -1, m_gpuMhz = -1, m_gpuMemUsed = -1, m_gpuMemTotal = -1;
    qreal m_gpuWatts = -1, m_gpuWattsMax = -1;
    QString m_gpuName;
    QVariantList m_disks;
    void *m_cpuQuery = nullptr, *m_cpuBase = nullptr, *m_cpuPace = nullptr; // PDH: the clock, and how much of it is in use
    bool m_cpuQueryTried = false;
    void *m_acpi = nullptr;       // the laptop's ACPI device (Windows, ASUS), once opened
    bool m_acpiTried = false;
    void *m_nvml = nullptr;       // NVIDIA's library, once loaded, and its first card
    void *m_nvmlCard = nullptr;
    bool m_nvmlTried = false;

    void readMachine();
    void readDisks();
    ~Probe();
};

SysMon::Probe::~Probe()
{
#ifdef Q_OS_WIN
    if (m_cpuQuery)
        PdhCloseQuery(static_cast<PDH_HQUERY>(m_cpuQuery));
    if (m_acpi)
        CloseHandle(static_cast<HANDLE>(m_acpi));
    if (m_nvml) {
        if (const auto stop = reinterpret_cast<int (*)()>(GetProcAddress(static_cast<HMODULE>(m_nvml), "nvmlShutdown")))
            stop();
        FreeLibrary(static_cast<HMODULE>(m_nvml));
    }
#endif
}

SysMon::SysMon(QObject *parent)
    : QObject(parent)
    , m_probe(std::make_unique<Probe>())
{
    for (int i = 0; i < 36; ++i)
        m_history.append(0.0);
    readCpu(m_lastIdle, m_lastTotal);
#ifdef Q_OS_WIN
    m_cpuThreads = QThread::idealThreadCount();
    m_cpuName = QSettings(QStringLiteral("HKEY_LOCAL_MACHINE\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0"), QSettings::NativeFormat)
                    .value(QStringLiteral("ProcessorNameString")).toString().simplified();
    m_cpuName = shortPartName(m_cpuName);
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
    // KISEL_DEMO_CLEAN=<ms>: a real clean at that time
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_CLEAN"); at > 0)
        QTimer::singleShot(at, this, &SysMon::clean);
}

SysMon::~SysMon()
{
    // (a reading under way still holds the probe: it is let finish)
    for (int i = 0; i < 300 && m_probing.load(); ++i)
        QThread::msleep(10);
#ifdef Q_OS_WIN
    if (m_gpuQuery)
        PdhCloseQuery(static_cast<PDH_HQUERY>(m_gpuQuery));
#endif
}

void SysMon::setWatching(bool on)
{
    if (on == m_watching)
        return;
    m_watching = on;
    if (on) {
        m_diskAge = 1000; // (the drives at once)
        QTimer::singleShot(0, this, &SysMon::read);
    } else {
        // Nobody is looking: a minute on, what the probe holds is let go (NVIDIA's library
        // above all: loaded, it keeps a few megabytes and a line to the card open).
        QTimer::singleShot(60000, this, [this] {
            if (!m_watching && !m_probing.load())
                m_probe = std::make_unique<Probe>();
        });
    }
    emit changed();
}

// The fixed drives and how full each is. Asked now and then: it changes slowly.
void SysMon::Probe::readDisks()
{
    QVariantList out;
    const double gb = 1024.0 * 1024.0 * 1024.0;
    // KISEL_DEMO_DISKS=<n>: n made-up drives, to look at a machine with many (development)
    if (const int n = qEnvironmentVariableIntValue("KISEL_DEMO_DISKS"); n > 0) {
        const double used[] = {0.98, 0.74, 0.35, 0.91, 0.12, 0.6, 0.83, 0.5};
        for (int i = 0; i < qMin(n, 8); ++i) {
            const double total = i == 0 ? 476 : i % 2 ? 931 : 1863;
            out.append(QVariantMap {{QStringLiteral("name"), QString(QChar('C' + i)) + QLatin1Char(':')}, {QStringLiteral("used"), used[i]},
                                    {QStringLiteral("freeGb"), total * (1 - used[i])}, {QStringLiteral("totalGb"), total}});
        }
        m_disks = out;
        return;
    }
    for (const QStorageInfo &v : QStorageInfo::mountedVolumes()) {
        if (!v.isValid() || !v.isReady() || v.bytesTotal() <= 0)
            continue;
#ifdef Q_OS_WIN
        const QString root = QDir::toNativeSeparators(v.rootPath());
        if (GetDriveTypeW(reinterpret_cast<LPCWSTR>(root.utf16())) != DRIVE_FIXED)
            continue;
        const QString name = root.left(2);
#else
        if (v.isReadOnly() || !v.device().startsWith("/dev/"))
            continue;
        const QString name = v.rootPath();
#endif
        out.append(QVariantMap {{QStringLiteral("name"), name},
                                {QStringLiteral("used"), 1.0 - double(v.bytesAvailable()) / double(v.bytesTotal())},
                                {QStringLiteral("freeGb"), double(v.bytesAvailable()) / gb},
                                {QStringLiteral("totalGb"), double(v.bytesTotal()) / gb}});
    }
    m_disks = out;
}

// The fans and the temperatures (see SysMon.h for where they come from).
void SysMon::Probe::readMachine()
{
#ifdef Q_OS_WIN
    // ASUS laptops: \\.\ATKACPI answers "what is the state of device N" (the method DSTS).
    // A value under 65536 means "no such device here".
    if (!m_acpiTried) {
        m_acpiTried = true;
        const HANDLE h = CreateFileW(L"\\\\.\\ATKACPI", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h != INVALID_HANDLE_VALUE)
            m_acpi = h;
    }
    const auto state = [this](quint32 device) -> int {
        if (!m_acpi)
            return -1;
        const quint32 in[4] = {0x53545344 /* "DSTS" */, 8, device, 0};
        quint32 out[4] = {0, 0, 0, 0};
        DWORD got = 0;
        if (!DeviceIoControl(static_cast<HANDLE>(m_acpi), 0x0022240C, const_cast<quint32 *>(in), sizeof in, out, sizeof out, &got, nullptr))
            return -1;
        return out[0] >= 65536 ? int(out[0] - 65536) : -1;
    };
    const auto fan = [&state](quint32 device) { const int v = state(device); return v >= 0 && v <= 150 ? v * 100 : -1; };
    const auto temp = [&state](quint32 device) { const int v = state(device); return v > 0 && v < 130 ? v : -1; };
    m_cpuFan = fan(0x00110013);
    m_gpuFan = fan(0x00110014);
    m_cpuTemp = temp(0x00120094);
    m_gpuTemp = temp(0x00120097);

    // The processor's clock: its nominal one, times how much of it Windows says is in
    // use (over 100 % when it is boosted)
    if (!m_cpuQueryTried) {
        m_cpuQueryTried = true;
        PDH_HQUERY q = nullptr;
        PDH_HCOUNTER base = nullptr, pace = nullptr;
        if (PdhOpenQueryW(nullptr, 0, &q) == ERROR_SUCCESS) {
            if (PdhAddEnglishCounterW(q, L"\\Processor Information(_Total)\\Processor Frequency", 0, &base) == ERROR_SUCCESS
                && PdhAddEnglishCounterW(q, L"\\Processor Information(_Total)\\% Processor Performance", 0, &pace) == ERROR_SUCCESS) {
                m_cpuQuery = q;
                m_cpuBase = base;
                m_cpuPace = pace;
                PdhCollectQueryData(q);
            } else {
                PdhCloseQuery(q);
            }
        }
    }
    if (m_cpuQuery && PdhCollectQueryData(static_cast<PDH_HQUERY>(m_cpuQuery)) == ERROR_SUCCESS) {
        PDH_FMT_COUNTERVALUE base {}, pace {};
        if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(m_cpuBase), PDH_FMT_DOUBLE, nullptr, &base) == ERROR_SUCCESS
            && PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(m_cpuPace), PDH_FMT_DOUBLE, nullptr, &pace) == ERROR_SUCCESS
            && base.doubleValue > 100 && pace.doubleValue > 1)
            m_cpuMhz = int(base.doubleValue * pace.doubleValue / 100.0 + 0.5);
    }

    // NVIDIA: its own library, from the system folder and nowhere else
    {
        if (!m_nvmlTried) {
            m_nvmlTried = true;
            if (const HMODULE lib = LoadLibraryExW(L"nvml.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32)) {
                const auto init = reinterpret_cast<int (*)()>(GetProcAddress(lib, "nvmlInit_v2"));
                const auto card = reinterpret_cast<int (*)(unsigned, void **)>(GetProcAddress(lib, "nvmlDeviceGetHandleByIndex_v2"));
                void *first = nullptr;
                if (init && card && GetProcAddress(lib, "nvmlDeviceGetTemperature") && init() == 0 && card(0, &first) == 0 && first) {
                    m_nvml = lib;
                    m_nvmlCard = first;
                    char name[96] = {0};
                    const auto named = reinterpret_cast<int (*)(void *, char *, unsigned)>(GetProcAddress(lib, "nvmlDeviceGetName"));
                    if (named && named(first, name, sizeof name - 1) == 0)
                        m_gpuName = shortPartName(QString::fromLatin1(name));
                } else {
                    FreeLibrary(lib);
                }
            }
        }
        if (m_nvml) {
            const auto read = reinterpret_cast<int (*)(void *, int, unsigned *)>(GetProcAddress(static_cast<HMODULE>(m_nvml), "nvmlDeviceGetTemperature"));
            unsigned t = 0;
            if (m_gpuTemp < 0 && read && read(m_nvmlCard, 0, &t) == 0 && t > 0 && t < 130)
                m_gpuTemp = int(t);
            const HMODULE lib = static_cast<HMODULE>(m_nvml);
            // one unsigned figure about the card, by the name of the function that gives it
            const auto figure = [this, lib](const char *fn) -> qint64 {
                const auto f = reinterpret_cast<int (*)(void *, unsigned *)>(GetProcAddress(lib, fn));
                unsigned v = 0;
                return f && f(m_nvmlCard, &v) == 0 ? qint64(v) : -1;
            };
            unsigned mhz = 0;
            const auto clock = reinterpret_cast<int (*)(void *, int, unsigned *)>(GetProcAddress(lib, "nvmlDeviceGetClockInfo"));
            m_gpuMhz = clock && clock(m_nvmlCard, 0, &mhz) == 0 && mhz > 0 ? int(mhz) : -1;
            const qint64 mw = figure("nvmlDeviceGetPowerUsage"), cap = figure("nvmlDeviceGetEnforcedPowerLimit");
            m_gpuWatts = mw >= 0 ? mw / 1000.0 : -1;
            m_gpuWattsMax = cap > 0 ? cap / 1000.0 : -1;
            struct { quint64 total, free, used; } mem {0, 0, 0};
            const auto room = reinterpret_cast<int (*)(void *, void *)>(GetProcAddress(lib, "nvmlDeviceGetMemoryInfo"));
            if (room && room(m_nvmlCard, &mem) == 0 && mem.total > 0) {
                m_gpuMemUsed = int(mem.used >> 20);
                m_gpuMemTotal = int(mem.total >> 20);
            }
        }
    }
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

bool SysMon::canClean() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

#ifdef Q_OS_WIN
namespace {
// Trim the working set of every program this user may touch. (Other users' and the
// system's are refused by OpenProcess, and that is fine.)
void trimWorkingSets()
{
    std::vector<DWORD> ids(8192);
    DWORD bytes = 0;
    if (!K32EnumProcesses(ids.data(), DWORD(ids.size() * sizeof(DWORD)), &bytes))
        return;
    const DWORD self = GetCurrentProcessId();
    for (DWORD i = 0; i < bytes / sizeof(DWORD); ++i) {
        if (ids[i] == 0 || ids[i] == self)
            continue;
        if (HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SET_QUOTA, FALSE, ids[i])) {
            K32EmptyWorkingSet(h);
            CloseHandle(h);
        }
    }
}

// Press a hotkey in the form the Windows hotkey control stores it: the low byte is the
// key, the high byte the modifiers (1 shift, 2 control, 4 alt).
void pressHotkey(int stored)
{
    const WORD key = WORD(stored & 0xFF);
    const int mods = (stored >> 8) & 0xFF;
    std::vector<WORD> keys;
    if (mods & 2) keys.push_back(VK_CONTROL);
    if (mods & 4) keys.push_back(VK_MENU);
    if (mods & 1) keys.push_back(VK_SHIFT);
    keys.push_back(key);
    std::vector<INPUT> in;
    for (const WORD k : keys) { INPUT e = {}; e.type = INPUT_KEYBOARD; e.ki.wVk = k; in.push_back(e); }
    for (auto k = keys.rbegin(); k != keys.rend(); ++k) { INPUT e = {}; e.type = INPUT_KEYBOARD; e.ki.wVk = *k; e.ki.dwFlags = KEYEVENTF_KEYUP; in.push_back(e); }
    SendInput(UINT(in.size()), in.data(), sizeof(INPUT));
}
} // namespace
#endif

void SysMon::clean()
{
    const bool rehearsal = qEnvironmentVariableIsSet("KISEL_DEMO_SWEEP"); // (development: the show without the cleaning)
    if (m_cleaning || (!canClean() && !rehearsal))
        return;
#ifdef Q_OS_WIN
    if (!rehearsal) {
        const int hotkey = cleanerSetting("HotkeyCleanEnable") == "true" ? cleanerSetting("HotkeyClean").toInt() : 0;
        if (!m_cleanerIni.isEmpty() && (hotkey & 0xFF) != 0)
            pressHotkey(hotkey);                      // Mem Reduct's own clean, by its hotkey
        else
            std::thread(trimWorkingSets).detach();    // ours: off the interface's thread, it takes a moment
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

    // (off this thread: see Probe. One reading at a time; a slow one makes the next wait its turn.)
    if (m_watching && !m_probing.exchange(true)) {
        const bool drives = ++m_diskAge >= 20;
        if (drives)
            m_diskAge = 0;
        QThreadPool::globalInstance()->start([this, drives] {
            Probe &p = *m_probe;
            p.readMachine();
            if (drives)
                p.readDisks();
            QMetaObject::invokeMethod(this, [this, cpuFan = p.m_cpuFan, gpuFan = p.m_gpuFan, cpuTemp = p.m_cpuTemp, gpuTemp = p.m_gpuTemp,
                                             cpuMhz = p.m_cpuMhz, gpuMhz = p.m_gpuMhz, used = p.m_gpuMemUsed, total = p.m_gpuMemTotal,
                                             watts = p.m_gpuWatts, cap = p.m_gpuWattsMax, name = p.m_gpuName, drives, disks = p.m_disks] {
                m_cpuFan = cpuFan; m_gpuFan = gpuFan; m_cpuTemp = cpuTemp; m_gpuTemp = gpuTemp;
                m_cpuMhz = cpuMhz; m_gpuMhz = gpuMhz; m_gpuMemUsed = used; m_gpuMemTotal = total;
                m_gpuWatts = watts; m_gpuWattsMax = cap; m_gpuName = name;
                if (drives)
                    m_disks = disks;
                emit changed();
            }, Qt::QueuedConnection);
            m_probing = false;
        });
    }

    m_history.removeFirst();
    m_history.append(m_cpu);
    m_hot = m_cpu > 0.9 ? m_hot + 1 : 0;
    m_worry = m_mem > 0.92 ? QStringLiteral("mem")
            : m_hot >= 4 ? QStringLiteral("cpu")
            : QString();
    emit changed();
}

} // namespace kisel
