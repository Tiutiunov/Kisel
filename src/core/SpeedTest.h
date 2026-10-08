#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>

class QNetworkReply;

namespace kisel {

// How fast the connection is when it is asked to give all it has: Luka's speed test.
//
// It runs only when asked (the Test key on her card), because it spends traffic: for
// eight seconds each way it moves as much as the line will carry. The other end is
// Cloudflare's open measuring service (speed.cloudflare.com, the one their own page and
// library use): nothing is sent but the requests themselves.
//
//   ping  six empty requests; the quickest answer counts
//   down  six downloads at once for eight seconds; the first second (the ramp) is left out
//   up    six uploads at once, the same way
//
// The figures are megabits a second, as speed tests give them.
class SpeedTest : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString phase READ phase NOTIFY changed)   // "" | ping | down | up
    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(bool done READ done NOTIFY changed)         // a result is there (the last test's)
    Q_PROPERTY(bool fresh READ fresh NOTIFY changed)       // ...and it is a minute old at most
    Q_PROPERTY(bool justDone READ justDone NOTIFY changed) // ...a few seconds old: the bar says it
    Q_PROPERTY(bool busy READ busy NOTIFY changed)         // running or only just over: the line's traffic is the test's, not a download
    Q_PROPERTY(bool failed READ failed NOTIFY changed)
    Q_PROPERTY(qreal down READ down NOTIFY changed)        // Mbit/s: as it goes, then the result
    Q_PROPERTY(qreal up READ up NOTIFY changed)
    Q_PROPERTY(int ping READ ping NOTIFY changed)          // ms, -1 before it is known
    Q_PROPERTY(qreal progress READ progress NOTIFY changed) // 0..1 through the whole test
    Q_PROPERTY(QString place READ place NOTIFY changed)    // where the other end is ("WAW"), if it said

public:
    explicit SpeedTest(QObject *parent = nullptr);
    ~SpeedTest() override;

    QString phase() const { return m_phase; }
    bool running() const { return !m_phase.isEmpty(); }
    bool done() const { return m_done; }
    bool fresh() const { return m_fresh.isActive(); }
    bool justDone() const { return m_just.isActive(); }
    bool busy() const { return running() || m_cool.isActive(); }
    bool failed() const { return m_failed; }
    qreal down() const { return m_down; }
    qreal up() const { return m_up; }
    int ping() const { return m_ping; }
    qreal progress() const { return m_progress; }
    QString place() const { return m_place; }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    void rehearse(); // development: the show without the network

signals:
    void changed();
    void finished(); // a test ran to its end

private:
    void nextPing();
    void beginTransfer(const QString &phase);
    void stream();
    void tick();
    void endPhase();
    void fail();
    void finish();
    void dropReplies();

    QNetworkAccessManager m_net;
    QList<QPointer<QNetworkReply>> m_replies;
    QTimer m_tick, m_fresh, m_just, m_cool;
    QElapsedTimer m_clock;
    QByteArray m_load; // what is sent up, over and over
    QString m_phase, m_place;
    bool m_done = false, m_failed = false, m_rehearsal = false;
    qreal m_down = 0, m_up = 0, m_progress = 0;
    int m_ping = -1, m_pingsLeft = 0, m_errors = 0;
    qint64 m_bytes = 0, m_bytes0 = -1, m_t0 = 0;
};

} // namespace kisel
