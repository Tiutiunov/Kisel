#pragma once

#include <QObject>
#include <QString>

#include <memory>

namespace kisel {

// The notifications Windows shows, as far as Rin needs them: whether there is one that
// has not been looked at, how many, and which program the newest is from. Only the
// program's name is read; the notification's words are never touched.
//
// On Windows this is the system's notification listener. What was already in the
// notification centre when Kisel started is old news and is not announced. A
// notification counts as looked at when it leaves the notification centre (opened,
// dismissed, or it was a passing banner that is gone), or when Rin's sign is clicked.
// Elsewhere `available` is false and nothing happens.
//
// The listener is read on a thread of its own; QML sees plain properties.
class Notices : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed) // the platform can do this and the user allows it
    Q_PROPERTY(bool pending READ pending NOTIFY changed)     // there is one not looked at yet
    Q_PROPERTY(int count READ count NOTIFY changed)          // how many
    Q_PROPERTY(QString app READ app NOTIFY changed)          // the program the newest is from

public:
    explicit Notices(QObject *parent = nullptr);
    ~Notices() override;

    bool available() const { return m_available; }
    bool pending() const { return m_count > 0; }
    int count() const { return m_count; }
    QString app() const { return m_app; }

    Q_INVOKABLE void dismiss(); // they have been looked at
    Q_INVOKABLE void open();    // ...and show the notification centre

signals:
    void changed();

private:
    struct Worker;
    void apply(bool available, int count, const QString &app);
    std::unique_ptr<Worker> m_worker;
    bool m_available = false;
    bool m_demo = false;
    int m_count = 0;
    QString m_app;
};

} // namespace kisel
