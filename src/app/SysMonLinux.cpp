#include "SysMonLinux.h"

#include "PartNames.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLibrary>
#include <QRegularExpression>

namespace kisel::linuxmon {

namespace {
QByteArray slurp(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.read(4096).trimmed();
}

// a whole number from a one-line file ("0x10de" too), or `none`
qint64 figure(const QString &path, qint64 none = -1)
{
    if (path.isEmpty())
        return none;
    const QByteArray text = slurp(path);
    bool ok = false;
    const qint64 v = text.toLongLong(&ok, 0);
    return ok ? v : none;
}

QStringList folders(const QString &in, const QString &pattern)
{
    QStringList out;
    for (const QString &name : QDir(in).entryList({pattern}, QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot, QDir::Name))
        out.append(in + QLatin1Char('/') + name);
    return out;
}

// The card's name out of the list of PCI devices every distribution carries:
// "Navi 23 [Radeon RX 6600/6600 XT/6600M]" is read as "Radeon RX 6600".
QString pciName(int vendor, int device)
{
    for (const char *where : {"/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids", "/usr/share/pci.ids"}) {
        QFile f(QString::fromLatin1(where));
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QByteArray v = QByteArray::number(vendor, 16).rightJustified(4, '0');
        const QByteArray d = '\t' + QByteArray::number(device, 16).rightJustified(4, '0');
        bool mine = false;
        while (!f.atEnd()) {
            const QByteArray line = f.readLine();
            if (line.isEmpty() || line.at(0) == '#')
                continue;
            if (line.at(0) != '\t') {
                if (mine)
                    break; // (the next maker: it was not there)
                mine = line.startsWith(v);
                continue;
            }
            if (!mine || !line.startsWith(d) || line.at(1) == '\t')
                continue;
            QString name = QString::fromUtf8(line.mid(d.size())).trimmed();
            const int open = name.lastIndexOf(QLatin1Char('[')), close = name.lastIndexOf(QLatin1Char(']'));
            if (open >= 0 && close > open)
                name = name.mid(open + 1, close - open - 1);
            const int slash = name.indexOf(QLatin1Char('/'));
            if (slash > 0)
                name.truncate(slash);
            return name.trimmed();
        }
    }
    return {};
}

enum { Nvidia = 0x10de, Amd = 0x1002, Intel = 0x8086 };
} // namespace

QString cpuName()
{
    QFile f(QStringLiteral("/proc/cpuinfo"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    // (it has no size to go by: read it line by line)
    for (int i = 0; i < 400; ++i) {
        const QByteArray line = f.readLine();
        if (line.isEmpty())
            break;
        if (line.startsWith("model name") || line.startsWith("Model name") || line.startsWith("Hardware")) {
            const int colon = line.indexOf(':');
            if (colon > 0)
                return QString::fromUtf8(line.mid(colon + 1)).simplified();
        }
    }
    return {};
}

Reader::Reader() = default;

Reader::~Reader()
{
    if (m_nvml) {
        if (const auto stop = reinterpret_cast<int (*)()>(m_nvml->resolve("nvmlShutdown")))
            stop();
        m_nvml->unload();
        delete m_nvml;
    }
}

void Reader::lookForCard()
{
    // Of several cards the one read is NVIDIA's or AMD's own (the discrete card of a
    // laptop that has two), else the one the screen hangs on. The make-believe cards of
    // virtual machines are passed over.
    int best = 0;
    static const QRegularExpression card(QStringLiteral("/card\\d+$"));
    for (const QString &dir : folders(QStringLiteral("/sys/class/drm"), QStringLiteral("card*"))) {
        if (!card.match(dir).hasMatch())
            continue;
        const int vendor = int(figure(dir + QStringLiteral("/device/vendor"), 0));
        const bool boot = figure(dir + QStringLiteral("/device/boot_vga"), 0) == 1;
        const int score = vendor == Nvidia ? 4 : vendor == Amd ? (boot ? 2 : 3) : vendor == Intel ? (boot ? 1 : 3) : 0;
        if (score <= best)
            continue;
        best = score;
        m_card = dir;
        m_vendor = vendor;
    }
    if (m_card.isEmpty())
        return;
    m_cardName = shortPartName(pciName(m_vendor, int(figure(m_card + QStringLiteral("/device/device"), 0))));
    const QStringList mons = folders(m_card + QStringLiteral("/device/hwmon"), QStringLiteral("hwmon*"));
    m_cardMon = mons.value(0);
    if (m_vendor == Intel) {
        for (const char *file : {"/gt/gt0/rc6_residency_ms", "/power/rc6_residency_ms", "/device/tile0/gt0/gtidle/idle_residency_ms"}) {
            if (QFileInfo::exists(m_card + QLatin1String(file))) {
                m_sleep = m_card + QLatin1String(file);
                break;
            }
        }
    }
}

void Reader::look()
{
    m_looked = true;
    m_cpuTemp.clear();
    m_cpuFan.clear();
    m_gpuFan.clear();
    m_clocks.clear();
    if (m_card.isEmpty())
        lookForCard();

    for (const QString &cpu : folders(QStringLiteral("/sys/devices/system/cpu"), QStringLiteral("cpu[0-9]*"))) {
        const QString file = cpu + QStringLiteral("/cpufreq/scaling_cur_freq");
        if (QFileInfo::exists(file))
            m_clocks.append(file);
    }

    // The processor's sensor, by the name of the driver that reads it; the best known first.
    static const char *const cpuChips[] = {"k10temp", "zenpower", "coretemp", "cpu_thermal", "cpu-thermal", "cpuss0_thermal",
                                           "soc_thermal", "thinkpad", "acpitz"};
    int bestChip = int(std::size(cpuChips));
    QList<Fan> fans;
    for (const QString &mon : folders(QStringLiteral("/sys/class/hwmon"), QStringLiteral("hwmon*"))) {
        const QString chip = QString::fromLatin1(slurp(mon + QStringLiteral("/name")));
        const bool ofCard = !m_cardMon.isEmpty() && QFileInfo(mon).canonicalFilePath() == QFileInfo(m_cardMon).canonicalFilePath();
        for (int i = 0; i < bestChip; ++i) {
            if (chip != QLatin1String(cpuChips[i]))
                continue;
            // within it: the reading named for the whole processor, else the first
            QString pick;
            for (const QString &label : folders(mon, QStringLiteral("temp*_label"))) {
                const QString what = QString::fromLatin1(slurp(label)).toLower();
                if (what == QLatin1String("tctl") || what == QLatin1String("tdie") || what.startsWith(QLatin1String("package"))
                    || what == QLatin1String("cpu")) {
                    pick = label.left(label.size() - 5) + QStringLiteral("input");
                    break;
                }
            }
            if (pick.isEmpty() && QFileInfo::exists(mon + QStringLiteral("/temp1_input")))
                pick = mon + QStringLiteral("/temp1_input");
            if (!pick.isEmpty()) {
                m_cpuTemp = pick;
                bestChip = i;
            }
        }
        for (const QString &input : folders(mon, QStringLiteral("fan*_input"))) {
            const QString label = QString::fromLatin1(slurp(input.left(input.size() - 5) + QStringLiteral("label"))).toLower();
            fans.append({input, label, ofCard ? QStringLiteral("card") : chip});
        }
    }

    // The fans. One that is named for the processor or for the card is that one. With no
    // names, a laptop's first fan is the processor's and its second the card's (so ASUS,
    // Lenovo, Dell and the rest count them); a board's first is the processor's, and the
    // card's is the one on the card itself.
    for (const Fan &f : std::as_const(fans)) {
        if (m_cpuFan.isEmpty() && f.label.contains(QLatin1String("cpu")))
            m_cpuFan = f.path;
        if (m_gpuFan.isEmpty() && (f.label.contains(QLatin1String("gpu")) || f.label.contains(QLatin1String("vga"))))
            m_gpuFan = f.path;
    }
    QStringList plain; // (not the card's own)
    for (const Fan &f : std::as_const(fans))
        if (f.chip != QLatin1String("card") && f.path != m_cpuFan && f.path != m_gpuFan)
            plain.append(f.path);
    if (m_cpuFan.isEmpty())
        m_cpuFan = plain.isEmpty() ? QString() : plain.takeFirst();
    if (m_gpuFan.isEmpty()) {
        for (const Fan &f : std::as_const(fans))
            if (f.chip == QLatin1String("card")) { m_gpuFan = f.path; break; }
    }
    static const QStringList laptops {QStringLiteral("asus"), QStringLiteral("thinkpad"), QStringLiteral("dell_smm"), QStringLiteral("hp"),
                                      QStringLiteral("legion_hwmon"), QStringLiteral("ideapad"), QStringLiteral("msi_ec"), QStringLiteral("acer"),
                                      QStringLiteral("surface_fan"), QStringLiteral("system76_acpi"), QStringLiteral("tuxedo"), QStringLiteral("applesmc")};
    if (m_gpuFan.isEmpty() && !plain.isEmpty() && !m_card.isEmpty()) {
        for (const Fan &f : std::as_const(fans))
            if (f.path == plain.first() && laptops.contains(f.chip)) { m_gpuFan = f.path; break; }
    }
}

// NVIDIA's own library, where its driver is installed (the kernel tells nothing of such
// a card). Only the name the driver itself installs is asked for, from the system's
// library folders.
void Reader::readNvidia(Machine &m)
{
    if (!m_nvmlTried) {
        m_nvmlTried = true;
        auto *lib = new QLibrary(QStringLiteral("libnvidia-ml.so.1"));
        const auto init = reinterpret_cast<int (*)()>(lib->resolve("nvmlInit_v2"));
        const auto card = reinterpret_cast<int (*)(unsigned, void **)>(lib->resolve("nvmlDeviceGetHandleByIndex_v2"));
        void *first = nullptr;
        if (init && card && init() == 0 && card(0, &first) == 0 && first) {
            m_nvml = lib;
            m_nvmlCard = first;
            char name[96] = {0};
            const auto named = reinterpret_cast<int (*)(void *, char *, unsigned)>(lib->resolve("nvmlDeviceGetName"));
            if (named && named(first, name, sizeof name - 1) == 0)
                m_cardName = shortPartName(QString::fromLatin1(name));
        } else {
            lib->unload();
            delete lib;
        }
    }
    if (!m_nvml)
        return;
    const auto one = [this](const char *fn) -> qint64 {
        const auto f = reinterpret_cast<int (*)(void *, unsigned *)>(m_nvml->resolve(fn));
        unsigned v = 0;
        return f && f(m_nvmlCard, &v) == 0 ? qint64(v) : -1;
    };
    struct { unsigned gpu, memory; } use {0, 0};
    const auto busy = reinterpret_cast<int (*)(void *, void *)>(m_nvml->resolve("nvmlDeviceGetUtilizationRates"));
    if (busy && busy(m_nvmlCard, &use) == 0)
        m.gpuLoad = qBound(0.0, use.gpu / 100.0, 1.0);
    unsigned t = 0;
    const auto temp = reinterpret_cast<int (*)(void *, int, unsigned *)>(m_nvml->resolve("nvmlDeviceGetTemperature"));
    if (temp && temp(m_nvmlCard, 0, &t) == 0 && t > 0 && t < 130)
        m.gpuTemp = int(t);
    unsigned mhz = 0;
    const auto clock = reinterpret_cast<int (*)(void *, int, unsigned *)>(m_nvml->resolve("nvmlDeviceGetClockInfo"));
    if (clock && clock(m_nvmlCard, 0, &mhz) == 0 && mhz > 0)
        m.gpuMhz = int(mhz);
    const qint64 mw = one("nvmlDeviceGetPowerUsage"), cap = one("nvmlDeviceGetEnforcedPowerLimit");
    m.gpuWatts = mw >= 0 ? mw / 1000.0 : -1;
    m.gpuWattsMax = cap > 0 ? cap / 1000.0 : -1;
    struct { quint64 total, free, used; } mem {0, 0, 0};
    const auto room = reinterpret_cast<int (*)(void *, void *)>(m_nvml->resolve("nvmlDeviceGetMemoryInfo"));
    if (room && room(m_nvmlCard, &mem) == 0 && mem.total > 0) {
        m.gpuMemUsed = int(mem.used >> 20);
        m.gpuMemTotal = int(mem.total >> 20);
    }
}

Machine Reader::read()
{
    // (a sensor's driver can be loaded after we started: looked for again now and then
    // while something is still missing)
    if (!m_looked || (++m_age >= 40 && (m_cpuTemp.isEmpty() || m_cpuFan.isEmpty()))) {
        m_age = 0;
        look();
    }
    Machine m;
    const auto degrees = [](const QString &file) { const qint64 v = figure(file); return v > 1000 && v < 130000 ? int((v + 500) / 1000) : -1; };
    const auto turns = [](const QString &file) { const qint64 v = figure(file); return v >= 0 && v < 20000 ? int(v) : -1; };
    m.cpuTemp = degrees(m_cpuTemp);
    m.cpuFan = turns(m_cpuFan);
    m.gpuFan = turns(m_gpuFan);
    // the processor's clock: its cores' together, as the system's own monitor shows it
    qint64 sum = 0;
    int cores = 0;
    for (const QString &file : std::as_const(m_clocks)) {
        const qint64 khz = figure(file);
        if (khz > 0) { sum += khz; ++cores; }
    }
    if (cores > 0)
        m.cpuMhz = int(sum / cores / 1000);

    if (m_card.isEmpty())
        return m;
    m.hasCard = true;
    if (!m_cardMon.isEmpty()) {
        m.gpuTemp = degrees(m_cardMon + QStringLiteral("/temp1_input"));
        qint64 uw = figure(m_cardMon + QStringLiteral("/power1_average"));
        if (uw < 0)
            uw = figure(m_cardMon + QStringLiteral("/power1_input"));
        if (uw >= 0)
            m.gpuWatts = uw / 1e6;
        const qint64 cap = figure(m_cardMon + QStringLiteral("/power1_cap"));
        if (cap > 0)
            m.gpuWattsMax = cap / 1e6;
        const qint64 hz = figure(m_cardMon + QStringLiteral("/freq1_input"));
        if (hz > 0)
            m.gpuMhz = int(hz / 1000000);
    }
    if (m_vendor == Nvidia) {
        readNvidia(m);
    } else if (m_vendor == Amd) {
        const qint64 busy = figure(m_card + QStringLiteral("/device/gpu_busy_percent"));
        if (busy >= 0)
            m.gpuLoad = qBound(0.0, busy / 100.0, 1.0);
        const qint64 used = figure(m_card + QStringLiteral("/device/mem_info_vram_used")), total = figure(m_card + QStringLiteral("/device/mem_info_vram_total"));
        if (used >= 0 && total > 0) {
            m.gpuMemUsed = int(used >> 20);
            m.gpuMemTotal = int(total >> 20);
        }
    } else if (m_vendor == Intel) {
        // Its load is not told, but how long it has slept is: what is left of the time is work.
        const qint64 slept = figure(m_sleep), now = QDateTime::currentMSecsSinceEpoch();
        if (slept >= 0 && m_sleptMs >= 0 && now > m_sleptAt + 200 && slept >= m_sleptMs)
            m.gpuLoad = qBound(0.0, 1.0 - double(slept - m_sleptMs) / double(now - m_sleptAt), 1.0);
        if (slept >= 0 && (m_sleptMs < 0 || now > m_sleptAt + 200)) {
            m_sleptMs = slept;
            m_sleptAt = now;
        }
        for (const char *file : {"/gt_act_freq_mhz", "/gt_cur_freq_mhz", "/device/tile0/gt0/freq0/act_freq"}) {
            const qint64 mhz = figure(m_card + QLatin1String(file));
            if (mhz > 0) { m.gpuMhz = int(mhz); break; }
        }
    }
    m.gpuName = m_cardName;
    return m;
}

} // namespace kisel::linuxmon
