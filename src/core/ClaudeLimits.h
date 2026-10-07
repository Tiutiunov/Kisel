#pragma once

#include "Secrets.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QTimer>

class QNetworkReply;

namespace kisel {

// How much of the Claude subscription's allowance is used: the five-hour window and the
// week, and when each resets. Miku shows it.
//
// This needs a sign-in key for the subscription, which the user pastes into Settings
// (it comes from `claude setup-token`). It is kept where the other keys are (see
// Secrets), is never written anywhere else, and is sent to one place only: Anthropic's
// own server, to ask for these figures, every few minutes.
//
// The question it asks is not a documented one: it is what Claude's own apps ask. If the
// server stops answering it, or does not accept this kind of key for it, `state` says
// "error" and `error` says why, and nothing else is affected.
class ClaudeLimits : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasKey READ hasKey NOTIFY changed)
    Q_PROPERTY(QString state READ state NOTIFY changed)       // "none" (no key) | "loading" | "ok" | "error"
    Q_PROPERTY(QString error READ error NOTIFY changed)        // why, in words, when state is "error"
    Q_PROPERTY(qreal fiveHour READ fiveHour NOTIFY changed)    // 0..1 of the five-hour window used
    Q_PROPERTY(QString fiveHourReset READ fiveHourReset NOTIFY changed) // when it resets, "04:00" (local), or ""
    Q_PROPERTY(qreal week READ week NOTIFY changed)            // 0..1 of the week used
    Q_PROPERTY(QString weekReset READ weekReset NOTIFY changed) // "Thu 09:00", or ""

public:
    explicit ClaudeLimits(Secrets *secrets, QObject *parent = nullptr);

    bool hasKey();
    QString state() const { return m_state; }
    QString error() const { return m_error; }
    qreal fiveHour() const { return m_fiveHour; }
    QString fiveHourReset() const { return m_fiveHourReset; }
    qreal week() const { return m_week; }
    QString weekReset() const { return m_weekReset; }

    Q_INVOKABLE void refresh();

    static constexpr auto kKey = "claude-signin";

signals:
    void changed();

private:
    void finished(QNetworkReply *reply);
    void fail(const QString &why);
    Secrets *m_secrets;
    QNetworkAccessManager m_net;
    QPointer<QNetworkReply> m_reply;
    QTimer m_timer;
    QString m_state = QStringLiteral("none");
    QString m_error;
    qreal m_fiveHour = 0;
    qreal m_week = 0;
    QString m_fiveHourReset, m_weekReset;
};

} // namespace kisel
