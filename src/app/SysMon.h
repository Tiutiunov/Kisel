#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>

namespace kisel {

// How the computer is doing, for Teto: how busy the processor is, how full the memory,
// and the battery if there is one. Read every second and a half from the system's own
// counters (Windows: GetSystemTimes, GlobalMemoryStatusEx, GetSystemPowerStatus; Linux:
// /proc/stat and /proc/meminfo). Nothing leaves the machine.
class SysMon : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(qreal cpu READ cpu NOTIFY changed)             // 0..1, all cores together
    Q_PROPERTY(qreal mem READ mem NOTIFY changed)             // 0..1 of physical memory in use
    Q_PROPERTY(qreal memUsedGb READ memUsedGb NOTIFY changed)
    Q_PROPERTY(qreal memTotalGb READ memTotalGb NOTIFY changed)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY changed)
    Q_PROPERTY(qreal battery READ battery NOTIFY changed)     // 0..1
    Q_PROPERTY(bool charging READ charging NOTIFY changed)    // on mains
    Q_PROPERTY(QVariantList history READ history NOTIFY changed) // the last 36 readings of cpu, oldest first
    // something is wrong enough to say so: the processor flat out for several readings,
    // the memory nearly full, or the battery nearly empty and not charging
    Q_PROPERTY(bool strain READ strain NOTIFY changed)
    Q_PROPERTY(QString worry READ worry NOTIFY changed)       // "" | cpu | mem | battery

public:
    explicit SysMon(QObject *parent = nullptr);

    bool available() const;
    qreal cpu() const { return m_cpu; }
    qreal mem() const { return m_mem; }
    qreal memUsedGb() const { return m_memUsed; }
    qreal memTotalGb() const { return m_memTotal; }
    bool hasBattery() const { return m_hasBattery; }
    qreal battery() const { return m_battery; }
    bool charging() const { return m_charging; }
    QVariantList history() const { return m_history; }
    bool strain() const { return !m_worry.isEmpty(); }
    QString worry() const { return m_worry; }

signals:
    void changed();

private:
    void read();
    bool readCpu(quint64 &idle, quint64 &total) const;

    QTimer m_timer;
    quint64 m_lastIdle = 0, m_lastTotal = 0;
    qreal m_cpu = 0, m_mem = 0, m_memUsed = 0, m_memTotal = 0, m_battery = 1;
    bool m_hasBattery = false, m_charging = true;
    int m_hot = 0; // readings in a row with the processor above 90 %
    QVariantList m_history;
    QString m_worry;
};

} // namespace kisel
