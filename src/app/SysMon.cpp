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

#ifdef Q_OS_WIN
#include <wbemidl.h>

namespace {
// What Windows itself knows of each graphics adapter, whoever made it: the kernel's
// graphics interface as an ordinary program may call it (gdi32's D3DKMT functions; it is
// where Task Manager has its figures from). Only what is asked for here is declared.
struct KmtAdapter { UINT handle; LUID luid; ULONG sources; BOOL precise; };
struct KmtEnum { ULONG count; KmtAdapter *adapters; };
struct KmtQuery { UINT handle; UINT type; void *data; UINT size; };
struct KmtClose { UINT handle; };
struct KmtNames { WCHAR adapter[MAX_PATH], bios[MAX_PATH], dac[MAX_PATH], chip[MAX_PATH]; };
struct KmtMemory { ULONGLONG dedicatedVideo, dedicatedSystem, sharedSystem; };
struct KmtPerf { ULONG index; ULONGLONG memHz, maxMemHz, maxMemHzOc, memBand, pcieBand; ULONG fanRpm, power, deciCelsius; UCHAR powerState; };
enum { KmtSegmentSize = 3, KmtRegistryInfo = 8, KmtAdapterType = 15, KmtPerfData = 62 };
enum { KmtRenders = 1, KmtSoftware = 4, KmtDiscrete = 16, KmtIndirect = 64 }; // bits of the adapter's type
}
#endif

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
    void *m_zoneQuery = nullptr, *m_zones = nullptr; // PDH: Windows' own thermal zones
    bool m_zoneQueryTried = false;
    QString m_gpuLuid;            // the card the figures are of, as Windows' counters name it
    void *m_memQuery = nullptr, *m_memUsed = nullptr; // PDH: the memory in use on each card
    bool m_memQueryTried = false;
    void *m_dell = nullptr;       // Dell's own monitoring service (WMI), once reached
    bool m_dellTried = false;
    int m_dellAge = 0;

    int m_dellCpu = -1, m_dellGpu = -1; // (kept between its readings)

    void readCard();
    void readDell();
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
    if (m_zoneQuery)
        PdhCloseQuery(static_cast<PDH_HQUERY>(m_zoneQuery));
    if (m_memQuery)
        PdhCloseQuery(static_cast<PDH_HQUERY>(m_memQuery));
    if (m_dell)
        static_cast<IWbemServices *>(m_dell)->Release();
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

// The graphics card, whoever made it: its name, its memory, its temperature and its own
// fan, as Windows reports them for every adapter. Of several, the one read is the
// discrete card of a laptop that has two, else the one with the most memory of its own.
// Software renderers and the make-believe adapters of remote-display programs are passed over.
void SysMon::Probe::readCard()
{
#ifdef Q_OS_WIN
    const HMODULE gdi = GetModuleHandleW(L"gdi32.dll");
    const auto list = reinterpret_cast<LONG (WINAPI *)(KmtEnum *)>(gdi ? GetProcAddress(gdi, "D3DKMTEnumAdapters2") : nullptr);
    const auto ask = reinterpret_cast<LONG (WINAPI *)(KmtQuery *)>(gdi ? GetProcAddress(gdi, "D3DKMTQueryAdapterInfo") : nullptr);
    const auto shut = reinterpret_cast<LONG (WINAPI *)(KmtClose *)>(gdi ? GetProcAddress(gdi, "D3DKMTCloseAdapter") : nullptr);
    if (!list || !ask || !shut)
        return;
    KmtAdapter adapters[16] = {};
    KmtEnum all {16, adapters};
    if (list(&all) != 0)
        return;
    const auto query = [ask](UINT handle, UINT type, void *data, UINT size) {
        KmtQuery q {handle, type, data, size};
        return ask(&q) == 0;
    };
    int best = -1;
    bool bestDiscrete = false;
    ULONGLONG bestMemory = 0;
    for (ULONG i = 0; i < all.count && i < 16; ++i) {
        UINT type = 0;
        KmtMemory memory {};
        if (!query(adapters[i].handle, KmtAdapterType, &type, sizeof type) || !(type & KmtRenders) || (type & (KmtSoftware | KmtIndirect)))
            continue;
        query(adapters[i].handle, KmtSegmentSize, &memory, sizeof memory);
        const bool discrete = type & KmtDiscrete;
        if (best < 0 || (discrete && !bestDiscrete) || (discrete == bestDiscrete && memory.dedicatedVideo > bestMemory)) {
            best = int(i);
            bestDiscrete = discrete;
            bestMemory = memory.dedicatedVideo;
        }
    }
    if (best >= 0) {
        const KmtAdapter &a = adapters[best];
        m_gpuLuid = QStringLiteral("luid_0x%1_0x%2_phys_0").arg(quint32(a.luid.HighPart), 8, 16, QLatin1Char('0')).arg(quint32(a.luid.LowPart), 8, 16, QLatin1Char('0'));
        KmtNames names {};
        if (query(a.handle, KmtRegistryInfo, &names, sizeof names)) {
            names.adapter[MAX_PATH - 1] = 0;
            const QString name = shortPartName(QString::fromWCharArray(names.adapter));
            if (!name.isEmpty())
                m_gpuName = name;
        }
        // (a card with next to no memory of its own lives on the machine's: that is its room)
        KmtMemory memory {};
        if (query(a.handle, KmtSegmentSize, &memory, sizeof memory)) {
            const ULONGLONG room = memory.dedicatedVideo >= (512ull << 20) ? memory.dedicatedVideo : memory.dedicatedVideo + memory.sharedSystem;
            m_gpuMemTotal = room > 0 ? int(room >> 20) : -1;
        }
        KmtPerf perf {};
        if (query(a.handle, KmtPerfData, &perf, sizeof perf)) {
            const int c = int(perf.deciCelsius / 10.0 + 0.5);
            if (m_gpuTemp < 0 && c >= 5 && c <= 125)
                m_gpuTemp = c;
            if (m_gpuFan < 0 && perf.fanRpm > 0 && perf.fanRpm < 20000)
                m_gpuFan = int(perf.fanRpm);
        }
    }
    for (ULONG i = 0; i < all.count && i < 16; ++i) {
        KmtClose c {adapters[i].handle};
        shut(&c);
    }

    // ...and how much of its memory is in use, which Windows counts for each card
    if (m_gpuLuid.isEmpty())
        return;
    if (!m_memQueryTried) {
        m_memQueryTried = true;
        PDH_HQUERY q = nullptr;
        PDH_HCOUNTER c = nullptr;
        if (PdhOpenQueryW(nullptr, 0, &q) == ERROR_SUCCESS) {
            if (PdhAddEnglishCounterW(q, L"\\GPU Adapter Memory(*)\\Dedicated Usage", 0, &c) == ERROR_SUCCESS) {
                m_memQuery = q;
                m_memUsed = c;
            } else {
                PdhCloseQuery(q);
            }
        }
    }
    DWORD bytes = 0, count = 0;
    const auto used = static_cast<PDH_HCOUNTER>(m_memUsed);
    if (m_memQuery && PdhCollectQueryData(static_cast<PDH_HQUERY>(m_memQuery)) == ERROR_SUCCESS
        && PdhGetFormattedCounterArrayW(used, PDH_FMT_LARGE, &bytes, &count, nullptr) == PDH_MORE_DATA && bytes > 0) {
        std::vector<char> buffer(bytes);
        auto *items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W *>(buffer.data());
        if (PdhGetFormattedCounterArrayW(used, PDH_FMT_LARGE, &bytes, &count, items) == ERROR_SUCCESS)
            for (DWORD i = 0; i < count; ++i)
                if (items[i].FmtValue.CStatus == ERROR_SUCCESS && QString::fromWCharArray(items[i].szName).startsWith(m_gpuLuid, Qt::CaseInsensitive))
                    m_gpuMemUsed = int(items[i].FmtValue.largeValue >> 20);
    }
#endif
}

// Dell laptops: the fans, from Dell's own monitoring service where it is installed
// ("Dell Command | Monitor": the WMI namespace root\dcim\sysman, whose numeric sensors
// include the tachometers). Dell offers no other way to an ordinary program, so
// without that service a Dell shows no fan. Asked now and then: the service is slow.
void SysMon::Probe::readDell()
{
#ifdef Q_OS_WIN
    if (!m_dellTried) {
        m_dellTried = true;
        const QString maker = QSettings(QStringLiteral("HKEY_LOCAL_MACHINE\\HARDWARE\\DESCRIPTION\\System\\BIOS"), QSettings::NativeFormat)
                                  .value(QStringLiteral("SystemManufacturer")).toString();
        if (!maker.contains(QLatin1String("Dell"), Qt::CaseInsensitive))
            return;
        CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        IWbemLocator *locator = nullptr;
        if (FAILED(CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER, IID_IWbemLocator, reinterpret_cast<void **>(&locator))) || !locator)
            return;
        IWbemServices *services = nullptr;
        BSTR space = SysAllocString(L"ROOT\\DCIM\\SYSMAN");
        const HRESULT hr = locator->ConnectServer(space, nullptr, nullptr, nullptr, WBEM_FLAG_CONNECT_USE_MAX_WAIT, nullptr, nullptr, &services);
        SysFreeString(space);
        locator->Release();
        if (FAILED(hr) || !services)
            return;
        CoSetProxyBlanket(services, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr, RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE);
        m_dell = services;
    }
    if (!m_dell || (m_dellAge++ % 3) != 0) // (every third reading: about five seconds)
        return;
    IEnumWbemClassObject *rows = nullptr;
    BSTR lang = SysAllocString(L"WQL");
    BSTR text = SysAllocString(L"SELECT ElementName, CurrentReading, UnitModifier FROM DCIM_NumericSensor WHERE SensorType = 5");
    const HRESULT hr = static_cast<IWbemServices *>(m_dell)->ExecQuery(lang, text, WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, nullptr, &rows);
    SysFreeString(lang);
    SysFreeString(text);
    if (FAILED(hr) || !rows)
        return;
    int cpu = -1, gpu = -1, other = -1;
    for (;;) {
        IWbemClassObject *row = nullptr;
        ULONG got = 0;
        if (FAILED(rows->Next(3000, 1, &row, &got)) || got == 0 || !row)
            break;
        VARIANT name, reading, power;
        VariantInit(&name); VariantInit(&reading); VariantInit(&power);
        row->Get(L"ElementName", 0, &name, nullptr, nullptr);
        row->Get(L"CurrentReading", 0, &reading, nullptr, nullptr);
        row->Get(L"UnitModifier", 0, &power, nullptr, nullptr);
        double rpm = -1;
        if (SUCCEEDED(VariantChangeType(&reading, &reading, 0, VT_R8)))
            rpm = reading.dblVal;
        if (rpm >= 0 && SUCCEEDED(VariantChangeType(&power, &power, 0, VT_I4)))
            for (int i = 0; i < qAbs(power.lVal) && i < 6; ++i)
                rpm = power.lVal > 0 ? rpm * 10 : rpm / 10;
        if (rpm >= 0 && rpm < 20000) {
            const QString label = name.vt == VT_BSTR && name.bstrVal ? QString::fromWCharArray(name.bstrVal).toLower() : QString();
            if (label.contains(QLatin1String("video")) || label.contains(QLatin1String("gpu")) || label.contains(QLatin1String("graphics")))
                gpu = qMax(gpu, int(rpm));
            else if (label.contains(QLatin1String("cpu")) || label.contains(QLatin1String("processor")))
                cpu = qMax(cpu, int(rpm));
            else if (other < 0)
                other = int(rpm);
            else if (gpu < 0)
                gpu = int(rpm); // (two unnamed fans: the first is taken for the processor's, the second for the card's)
        }
        VariantClear(&name); VariantClear(&reading); VariantClear(&power);
        row->Release();
    }
    rows->Release();
    if (cpu < 0)
        cpu = other;
    m_dellCpu = cpu;
    m_dellGpu = gpu;
#endif
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
    if (m_cpuFan < 0 && m_gpuFan < 0) { // (not an ASUS: a Dell, perhaps)
        readDell();
        m_cpuFan = m_dellCpu;
        m_gpuFan = m_dellGpu;
    }
    m_gpuMemUsed = -1;
    readCard();

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

    // NVIDIA: its own library, from the system folder and nowhere else. It adds what
    // Windows does not tell (the clock, the power drawn and its limit), and only when the
    // card being read is NVIDIA's.
    m_gpuMhz = -1; m_gpuWatts = -1; m_gpuWattsMax = -1;
    if (m_gpuName.isEmpty() || m_gpuName.contains(QLatin1String("RTX")) || m_gpuName.contains(QLatin1String("GTX"))
        || m_gpuName.contains(QLatin1String("Quadro")) || m_gpuName.contains(QLatin1String("NVIDIA"), Qt::CaseInsensitive)
        || m_gpuName.contains(QLatin1String("GT ")) || m_gpuName.contains(QLatin1String("MX")) || m_gpuName.contains(QLatin1String("Titan"), Qt::CaseInsensitive)) {
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
                    if (m_gpuName.isEmpty() && named && named(first, name, sizeof name - 1) == 0)
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

    // Where neither of those tells a temperature (any laptop that is not an ASUS, any card
    // that is not NVIDIA's: an ARM machine has neither), Windows' own thermal zones do,
    // to anyone who asks: the firmware's sensors, in kelvins, each under the name the
    // firmware gave it. A zone named for the processor or the graphics card is taken for
    // it; with no such names, the hottest zone stands for the processor, which is what
    // it nearly always is.
    if (m_cpuTemp < 0 || m_gpuTemp < 0) {
        if (!m_zoneQueryTried) {
            m_zoneQueryTried = true;
            PDH_HQUERY q = nullptr;
            PDH_HCOUNTER c = nullptr;
            if (PdhOpenQueryW(nullptr, 0, &q) == ERROR_SUCCESS) {
                if (PdhAddEnglishCounterW(q, L"\\Thermal Zone Information(*)\\Temperature", 0, &c) == ERROR_SUCCESS) {
                    m_zoneQuery = q;
                    m_zones = c;
                } else {
                    PdhCloseQuery(q);
                }
            }
        }
        DWORD bytes = 0, count = 0;
        const auto zones = static_cast<PDH_HCOUNTER>(m_zones);
        if (m_zoneQuery && PdhCollectQueryData(static_cast<PDH_HQUERY>(m_zoneQuery)) == ERROR_SUCCESS
            && PdhGetFormattedCounterArrayW(zones, PDH_FMT_DOUBLE, &bytes, &count, nullptr) == PDH_MORE_DATA && bytes > 0) {
            std::vector<char> buffer(bytes);
            auto *items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W *>(buffer.data());
            if (PdhGetFormattedCounterArrayW(zones, PDH_FMT_DOUBLE, &bytes, &count, items) == ERROR_SUCCESS) {
                int cpu = -1, gpu = -1, hottest = -1;
                for (DWORD i = 0; i < count; ++i) {
                    if (items[i].FmtValue.CStatus != ERROR_SUCCESS)
                        continue;
                    const int c = int(items[i].FmtValue.doubleValue - 273.15 + 0.5);
                    if (c < 5 || c > 125) // (a zone that is not read answers nought, or nonsense)
                        continue;
                    const QString name = QString::fromWCharArray(items[i].szName).toLower();
                    if (name.contains(QLatin1String("gpu")))
                        gpu = qMax(gpu, c);
                    else if (name.contains(QLatin1String("cpu")))
                        cpu = qMax(cpu, c);
                    else if (!name.contains(QLatin1String("bat")) && !name.contains(QLatin1String("skin")) && !name.contains(QLatin1String("chg")))
                        hottest = qMax(hottest, c);
                }
                if (m_cpuTemp < 0)
                    m_cpuTemp = cpu >= 0 ? cpu : hottest;
                if (m_gpuTemp < 0)
                    m_gpuTemp = gpu;
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
    m_hasGpu = !cards.isEmpty(); // (a machine with no card that Windows counts shows no ring for one)
    m_cardLoads = cards;
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
                                             watts = p.m_gpuWatts, cap = p.m_gpuWattsMax, name = p.m_gpuName, luid = p.m_gpuLuid, drives, disks = p.m_disks] {
                m_cpuFan = cpuFan; m_gpuFan = gpuFan; m_cpuTemp = cpuTemp; m_gpuTemp = gpuTemp;
                m_cpuMhz = cpuMhz; m_gpuMhz = gpuMhz; m_gpuMemUsed = used; m_gpuMemTotal = total;
                m_gpuWatts = watts; m_gpuWattsMax = cap; m_gpuName = name; m_gpuLuid = luid;
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
