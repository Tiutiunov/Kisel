#pragma once

#include <QAnimationDriver>
#include <QTimer>

namespace kisel {

// How often the interface's animations move on.
//
// Left to itself Qt Quick steps every animation once for every frame the monitor shows:
// 144 or 165 times a second on a fast one. For a bar a few dozen pixels high, with a
// record turning in it or a sign being waved, that is a tenth of a processor spent on
// motion nobody can tell from forty steps a second.
//
// So Kisel drives the animations itself, off a timer: `rate` steps a second (QML sets
// it: 60 while the card is open or something is being moved, 40 in the bar). When no
// animation is running the timer stands still and nothing is drawn at all.
//
// It has to be installed before the first window is made (see main.cpp): Qt Quick then
// finds a driver already there and leaves the timing to it.
class Ticker : public QAnimationDriver
{
    Q_OBJECT
    Q_PROPERTY(int rate READ rate WRITE setRate NOTIFY rateChanged)

public:
    explicit Ticker(QObject *parent = nullptr)
        : QAnimationDriver(parent)
    {
        m_timer.setTimerType(Qt::PreciseTimer);
        m_timer.setInterval(1000 / m_rate);
        connect(&m_timer, &QTimer::timeout, this, [this] { advance(); });
    }

    int rate() const { return m_rate; }
    void setRate(int hz)
    {
        hz = qBound(10, hz, 120);
        if (hz == m_rate)
            return;
        m_rate = hz;
        m_timer.setInterval(1000 / m_rate);
        emit rateChanged();
    }

signals:
    void rateChanged();

protected:
    void start() override
    {
        QAnimationDriver::start();
        m_timer.start();
    }
    void stop() override
    {
        m_timer.stop();
        QAnimationDriver::stop();
    }

private:
    QTimer m_timer;
    int m_rate = 60;
};

} // namespace kisel
