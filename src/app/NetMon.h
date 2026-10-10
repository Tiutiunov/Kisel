#pragma once

#include <QObject>
#include <QVariantList>

#include <memory>

namespace kisel {

// How the connection is doing, for Luka: whether the internet answers, how long an
// answer takes (ping), and how fast data is moving in and out right now.
//
// On Windows: one small echo ("ping", 32 bytes) every two seconds to a public name
// server (1.1.1.1; nothing else is ever sent anywhere), and the byte counters of the
// network adapters that are up, read from the system. On Plasma the same: the echo goes
// through the socket Linux keeps for it, the counters come from /proc/net/dev. Elsewhere
// `available` is false and nothing happens.
//
// The measuring is done on a thread of its own; QML sees plain properties.
class NetMon : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)   // the platform can do this at all
    Q_PROPERTY(bool online READ online NOTIFY changed)      // echoes are coming back
    Q_PROPERTY(int ping READ ping NOTIFY changed)           // the last answer in ms, or -1 if none came
    Q_PROPERTY(qreal down READ down NOTIFY changed)         // bytes a second coming in
    Q_PROPERTY(qreal up READ up NOTIFY changed)             // bytes a second going out
    Q_PROPERTY(QVariantList history READ history NOTIFY changed) // the last minute of pings, ms (-1: lost)
    Q_PROPERTY(bool slow READ slow NOTIFY changed)          // answers are coming, but late (over 250 ms, three in a row)
    Q_PROPERTY(bool trouble READ trouble NOTIFY changed)    // offline or slow: Luka has something to say
    Q_PROPERTY(bool justBack READ justBack NOTIFY changed)  // the connection has just come back (for a few seconds)
    // Something is being downloaded: a lot has been coming in steadily (over 500 KB a
    // second for eight seconds; it ends after eight seconds under 100). What it is, and
    // how much of it is left, cannot be known from here: only how fast and how much so far.
    Q_PROPERTY(bool downloading READ downloading NOTIFY changed)
    Q_PROPERTY(qreal fetched READ fetched NOTIFY changed)       // bytes this download has brought in so far (or the last one did)
    Q_PROPERTY(bool justFetched READ justFetched NOTIFY changed) // a download has just ended (for a few seconds)

public:
    explicit NetMon(QObject *parent = nullptr);
    ~NetMon() override;

    bool available() const;
    bool online() const { return m_online; }
    int ping() const { return m_ping; }
    qreal down() const { return m_down; }
    qreal up() const { return m_up; }
    QVariantList history() const { return m_history; }
    bool slow() const { return m_slow; }
    bool trouble() const { return !m_online || m_slow; }
    bool justBack() const { return m_justBack; }
    bool downloading() const { return m_downloading; }
    qreal fetched() const { return m_fetched; }
    bool justFetched() const { return m_justFetched; }

signals:
    void changed();

private:
    struct Worker;
    void apply(int ping, qreal down, qreal up);
    std::unique_ptr<Worker> m_worker;
    bool m_demo = false;
    bool m_online = true; // (until the first echoes say otherwise: no false alarm at startup)
    bool m_slow = false;
    bool m_justBack = false;
    int m_ping = -1;
    int m_lost = 0;  // echoes lost in a row
    int m_late = 0;  // late answers in a row
    bool m_downloading = false;
    bool m_justFetched = false;
    int m_fast = 0;  // readings in a row with a lot coming in
    int m_idle = 0;  // readings in a row with next to nothing coming in
    qreal m_fetched = 0;
    qreal m_pending = 0; // what came in during the readings that may turn out to begin a download
    qreal m_down = 0;
    qreal m_up = 0;
    QVariantList m_history;
};

} // namespace kisel
