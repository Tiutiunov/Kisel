#pragma once

#include <QString>
#include <QStringList>

class QLibrary;

namespace kisel::linuxmon {

// What Linux tells of the machine, to anyone who asks: /proc and /sys, and for an
// NVIDIA card its own library where the driver has put one. Nothing here needs root.
//
//   the processor   /proc/cpuinfo for its name, cpufreq for its clock
//   temperatures    hwmon: the processor's own sensor (k10temp, coretemp, ...), else the
//                   firmware's (acpitz)
//   fans            hwmon again: the laptop's driver (asus, thinkpad, dell_smm, ...) or the
//                   board's sensor chip; whichever maker it is, the kernel names them alike
//   the card        /sys/class/drm: AMD tells everything there, Intel its clock and how
//                   long it slept (the load is reckoned from that), NVIDIA nothing, so its
//                   library (libnvidia-ml) is asked
struct Machine
{
    int cpuFan = -1, gpuFan = -1, cpuTemp = -1, gpuTemp = -1;
    int cpuMhz = -1, gpuMhz = -1, gpuMemUsed = -1, gpuMemTotal = -1; // MHz, megabytes
    double gpuWatts = -1, gpuWattsMax = -1;
    double gpuLoad = -1; // 0..1, or -1 where the card does not tell
    bool hasCard = false;
    QString gpuName;
};

class Reader
{
public:
    Reader();
    ~Reader();
    Machine read();

private:
    struct Fan { QString path, label, chip; };
    void look();        // find the sensors and the card (once, and again if nothing was found)
    void lookForCard();
    void readNvidia(Machine &m);
    bool m_looked = false;
    int m_age = 0;
    QString m_cpuTemp;  // files, or empty
    QString m_cpuFan, m_gpuFan;
    QStringList m_clocks; // every core's current frequency
    // the card
    QString m_card;     // /sys/class/drm/cardN
    int m_vendor = 0;
    QString m_cardName;
    QString m_cardMon;  // its own hwmon folder, if it has one
    QString m_sleep;    // Intel: the file that counts how long the card has slept, ms
    qint64 m_sleptMs = -1, m_sleptAt = 0;
    QLibrary *m_nvml = nullptr;
    void *m_nvmlCard = nullptr;
    bool m_nvmlTried = false;
};

// The processor's name as /proc/cpuinfo spells it (empty if it does not say).
QString cpuName();

} // namespace kisel::linuxmon
