#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>

#include <atomic>
#include <memory>

namespace kisel {

// How the computer is doing, for Teto: how busy the processor and the graphics card
// are, and how full the memory. Read every second and a half from the system's own
// counters (Windows: GetSystemTimes, the "GPU Engine" performance counters,
// GlobalMemoryStatusEx; Linux: /proc/stat and /proc/meminfo, no graphics card).
// Nothing leaves the machine.
//
// Cleaning the memory (Windows), without a window and without asking for rights:
//   - If Mem Reduct is installed and has a hotkey for cleaning, that hotkey is pressed
//     for the user, and the Mem Reduct that is already running does its full clean.
//   - Otherwise the working sets of the user's own programs are trimmed here: memory
//     they hold but are not using goes back to the system. This is the part of a clean
//     that needs no administrator.
// Mem Reduct is never started with its `-clean` switch: run that way it reports the
// result in a dialog of its own that has to be clicked away.
// What a clean freed is read off the memory figure a few seconds later.
//
// Mem Reduct also cleans by itself (on a timer, above a threshold). Those cleans are
// noticed through the time of the last clean in its settings file and announced the
// same way, unless its own "Show memory cleaning results" is off: then they pass in
// silence here too.
class SysMon : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(qreal cpu READ cpu NOTIFY changed)             // 0..1, all cores together
    Q_PROPERTY(qreal mem READ mem NOTIFY changed)             // 0..1 of physical memory in use
    Q_PROPERTY(qreal memUsedGb READ memUsedGb NOTIFY changed)
    Q_PROPERTY(qreal memTotalGb READ memTotalGb NOTIFY changed)
    Q_PROPERTY(bool hasGpu READ hasGpu NOTIFY changed)        // the system reports the graphics card's load
    Q_PROPERTY(qreal gpu READ gpu NOTIFY changed)             // 0..1: the busiest card's 3D engine
    Q_PROPERTY(QVariantList history READ history NOTIFY changed) // the last 36 readings of cpu, oldest first
    // More about the machine, read only while someone is looking (`watching`: Teto's card
    // is open). Each is -1 where this machine does not tell an ordinary program:
    //   the fans and the processor's temperature come from the laptop's own ACPI device,
    //   which so far means ASUS laptops (status queries only, nothing is ever set);
    //   the graphics card's temperature comes from NVIDIA's library where there is one;
    //   failing those, a temperature comes from Windows' own thermal zones, which any
    //   machine has (an ARM laptop among them). The fans have no such second source:
    //   Windows keeps no figure for them at all.
    // Nothing here needs administrator rights or a driver of Kisel's own. The NVIDIA card
    // of a laptop sleeps when idle and a question wakes it, which is why none is asked
    // while the card is shut.
    Q_PROPERTY(bool watching READ watching WRITE setWatching NOTIFY changed)
    Q_PROPERTY(int cpuFan READ cpuFan NOTIFY changed)   // turns a minute
    Q_PROPERTY(int gpuFan READ gpuFan NOTIFY changed)
    Q_PROPERTY(int cpuTemp READ cpuTemp NOTIFY changed) // degrees Celsius
    Q_PROPERTY(int gpuTemp READ gpuTemp NOTIFY changed)
    // What else is told, for the list a ring shows when the pointer is on it (-1 or
    // empty where it is not told). The processor's clock is Windows' own counter. The
    // graphics card's clock, memory and power are NVIDIA's (`gpuWattsMax` is the limit
    // the card is allowed, its TGP). The voltages are not here: no ordinary program
    // can read them, only a driver with the system's own rights.
    // (the names are the short ones a person uses: see PartNames.h)
    Q_PROPERTY(QString cpuName READ cpuName CONSTANT)
    Q_PROPERTY(int cpuThreads READ cpuThreads CONSTANT)
    Q_PROPERTY(int cpuMhz READ cpuMhz NOTIFY changed)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY changed)
    Q_PROPERTY(int gpuMhz READ gpuMhz NOTIFY changed)
    Q_PROPERTY(int gpuMemUsedMb READ gpuMemUsedMb NOTIFY changed)
    Q_PROPERTY(int gpuMemTotalMb READ gpuMemTotalMb NOTIFY changed)
    Q_PROPERTY(qreal gpuWatts READ gpuWatts NOTIFY changed)
    Q_PROPERTY(qreal gpuWattsMax READ gpuWattsMax NOTIFY changed)
    // The fixed drives: [{name: "C:", used: 0..1, freeGb, totalGb}], by letter
    Q_PROPERTY(QVariantList disks READ disks NOTIFY changed)
    // something is wrong enough to say so: the processor flat out for several readings, or
    // the memory nearly full (a graphics card flat out is a game running, not a worry)
    Q_PROPERTY(bool strain READ strain NOTIFY changed)
    Q_PROPERTY(QString worry READ worry NOTIFY changed)       // "" | cpu | mem
    Q_PROPERTY(bool canClean READ canClean CONSTANT)          // cleaning is possible here (Windows)
    Q_PROPERTY(bool cleaning READ cleaning NOTIFY changed)    // asked, and waiting to see what it freed
    Q_PROPERTY(bool justCleaned READ justCleaned NOTIFY changed) // for eight seconds after
    Q_PROPERTY(qreal freedGb READ freedGb NOTIFY changed)     // what the last clean freed

public:
    explicit SysMon(QObject *parent = nullptr);
    ~SysMon() override;

    bool available() const;
    qreal cpu() const { return m_cpu; }
    qreal mem() const { return m_mem; }
    qreal memUsedGb() const { return m_memUsed; }
    qreal memTotalGb() const { return m_memTotal; }
    bool hasGpu() const { return m_hasGpu; }
    qreal gpu() const { return m_gpu; }
    QVariantList history() const { return m_history; }
    bool watching() const { return m_watching; }
    void setWatching(bool on);
    int cpuFan() const { return m_cpuFan; }
    int gpuFan() const { return m_gpuFan; }
    int cpuTemp() const { return m_cpuTemp; }
    int gpuTemp() const { return m_gpuTemp; }
    QVariantList disks() const { return m_disks; }
    QString cpuName() const { return m_cpuName; }
    int cpuThreads() const { return m_cpuThreads; }
    int cpuMhz() const { return m_cpuMhz; }
    QString gpuName() const { return m_gpuName; }
    int gpuMhz() const { return m_gpuMhz; }
    int gpuMemUsedMb() const { return m_gpuMemUsed; }
    int gpuMemTotalMb() const { return m_gpuMemTotal; }
    qreal gpuWatts() const { return m_gpuWatts; }
    qreal gpuWattsMax() const { return m_gpuWattsMax; }
    bool strain() const { return !m_worry.isEmpty(); }
    QString worry() const { return m_worry; }
    bool canClean() const;
    bool cleaning() const { return m_cleaning; }
    bool justCleaned() const { return m_justCleaned; }
    qreal freedGb() const { return m_freed; }

    Q_INVOKABLE void clean();

signals:
    void changed();

private:
    void read();
    bool readCpu(quint64 &idle, quint64 &total) const;
    void readGpu();
    // What reads the fans, the temperatures and the drives, and the handles it keeps.
    // It works on a thread of the pool: NVIDIA's library takes a moment to start (it
    // wakes a sleeping card), a drive may be slow to answer, and on the interface's
    // thread either showed as a stutter when Teto's card opened.
    struct Probe;
    std::unique_ptr<Probe> m_probe;
    std::atomic<bool> m_probing {false};
    QByteArray cleanerSetting(const char *key) const;
    qint64 lastReduct() const;
    void announce(qreal freed);

    QTimer m_timer;
    quint64 m_lastIdle = 0, m_lastTotal = 0;
    qreal m_cpu = 0, m_mem = 0, m_memUsed = 0, m_memTotal = 0, m_gpu = 0;
    bool m_hasGpu = false;
    void *m_gpuQuery = nullptr, *m_gpuCounter = nullptr; // PDH handles (Windows)
    int m_hot = 0; // readings in a row with the processor above 90 %
    bool m_watching = false;
    int m_cpuFan = -1, m_gpuFan = -1, m_cpuTemp = -1, m_gpuTemp = -1;
    QVariantList m_disks;
    QString m_cpuName, m_gpuName;
    int m_cpuThreads = 0, m_cpuMhz = -1, m_gpuMhz = -1, m_gpuMemUsed = -1, m_gpuMemTotal = -1;
    qreal m_gpuWatts = -1, m_gpuWattsMax = -1;
    int m_diskAge = 0;            // readings since the drives were last asked
    QVariantList m_history;
    QString m_worry;
    QString m_cleaner; // Mem Reduct's program, or empty
    QString m_cleanerIni; // its settings file
    qint64 m_lastReduct = 0, m_iniStamp = 0;
    qreal m_recent[3] = {0, 0, 0}; // the memory in use over the last three readings
    bool m_cleaning = false, m_justCleaned = false;
    qreal m_freed = 0;
};

} // namespace kisel
