#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include <memory>

namespace kisel {

// The notifications Windows shows, as far as Rin needs them: whether there is one that
// has not been looked at, how many, and which program the newest is from. Only the
// program's name is read, unless the user asks for more: with `words` on (Rin's card
// has the key; off until pressed) the title and the text are read too, for the list in
// her card. They stay in memory, a handful of the newest, and go nowhere else: not to
// disk, not to a log, not over the network.
//
// On Windows this is the system's notification listener. What was already in the
// notification centre when Kisel started is old news and is not announced. A
// notification counts as looked at when Rin's sign is clicked, when the program it came
// from is brought to the front, or when it is dismissed from the notification centre
// after lying there a while. One that vanishes within moments (a passing banner, or a
// program such as Discord withdrawing its own) has not been looked at, and stays.
//
// A click on the sign goes to the notifications: if they are all from one program,
// that program is brought up (the way its Start menu entry would); if from several,
// the notification centre opens.
//
// On Plasma the notifications are heard on the session bus as programs send them (see
// Notices.cpp): one counts as looked at when Rin's sign is clicked, or when the user
// shuts it or clicks it on the desktop. Which window is in front is not known there.
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
    Q_PROPERTY(QStringList apps READ apps NOTIFY changed)    // every program with one waiting, newest first
    Q_PROPERTY(QVariantList counts READ counts NOTIFY changed) // ...and how many each has
    // The newest few, looked at or not, newest first: [{app, title, text, at, fresh}].
    // `at`: when it came, ms since the epoch; `fresh`: not looked at yet; `title` and
    // `text` are empty unless `words` is on.
    Q_PROPERTY(QVariantList recent READ recent NOTIFY changed)
    Q_PROPERTY(bool words READ words WRITE setWords NOTIFY changed)

public:
    explicit Notices(QObject *parent = nullptr);
    ~Notices() override;

    bool available() const { return m_available; }
    bool pending() const { return m_count > 0; }
    int count() const { return m_count; }
    QString app() const { return m_app; }
    QStringList apps() const { return m_apps; }
    QVariantList counts() const { return m_counts; }
    QVariantList recent() const { return m_recent; }
    bool words() const { return m_words; }
    void setWords(bool on);

    Q_INVOKABLE void dismiss(); // they have been looked at
    Q_INVOKABLE void open();    // ...and go to them: the program they are from, or the notification centre if from several
    Q_INVOKABLE void openRecent(int index); // the program that one of `recent` is from

signals:
    void changed();

private:
    struct Worker;
    void apply(bool available, int count, const QString &app, const QStringList &apps, const QVariantList &counts,
               const QString &target, const QVariantList &recent);
    std::unique_ptr<Worker> m_worker;
    bool m_available = false;
    bool m_demo = false;
    int m_count = 0;
    QString m_app;
    QStringList m_apps;
    QVariantList m_counts;
    QVariantList m_recent;
    bool m_words = false;
    QString m_target; // the one program they are all from (its identifier in Windows), or ""
};

} // namespace kisel
