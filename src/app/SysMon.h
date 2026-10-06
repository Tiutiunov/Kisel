#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>

namespace kisel {

// How the computer is doing, for Teto: how busy the processor and the graphics card
// are, and how full the memory. Read every second and a half from the system's own
// counters (Windows: GetSystemTimes, the "GPU Engine" performance counters,
// GlobalMemoryStatusEx; Linux: /proc/stat and /proc/meminfo, no graphics card).
// Nothing leaves the machine.
//
// Cleaning the memory is not ours to do: it needs rights this program does not ask for.
// Where Mem Reduct is installed (Windows), `clean()` asks it to, by starting it with its
// own `-clean` switch; Windows may ask the user to allow that. What it freed is read off
// the memory figure a few seconds later.
//
// Mem Reduct also cleans by itself (on a timer, above a threshold, by hotkey). Those
// cleans are noticed too: it keeps the time of its last clean in its settings file, and
// when that moves, what was freed is announced here the same way. Its own setting
// "Show memory cleaning results" is honoured: with that off, the cleans it does by
// itself pass in silence here too, and only a clean asked for from here is reported.
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
    // something is wrong enough to say so: the processor flat out for several readings, or
    // the memory nearly full (a graphics card flat out is a game running, not a worry)
    Q_PROPERTY(bool strain READ strain NOTIFY changed)
    Q_PROPERTY(QString worry READ worry NOTIFY changed)       // "" | cpu | mem
    Q_PROPERTY(bool canClean READ canClean CONSTANT)          // Mem Reduct is installed
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
    bool strain() const { return !m_worry.isEmpty(); }
    QString worry() const { return m_worry; }
    bool canClean() const { return !m_cleaner.isEmpty(); }
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
    QByteArray cleanerSetting(const char *key) const;
    qint64 lastReduct() const;
    void announce(qreal freed);

    QTimer m_timer;
    quint64 m_lastIdle = 0, m_lastTotal = 0;
    qreal m_cpu = 0, m_mem = 0, m_memUsed = 0, m_memTotal = 0, m_gpu = 0;
    bool m_hasGpu = false;
    void *m_gpuQuery = nullptr, *m_gpuCounter = nullptr; // PDH handles (Windows)
    int m_hot = 0; // readings in a row with the processor above 90 %
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
