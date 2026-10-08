#pragma once

#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QTimer>

namespace kisel {

class AgentHub;
class Preferences;

// "Working with Claude Code" in the user's Discord profile (Rich Presence).
//
// Off unless switched on in Settings: it tells other people what the user is doing.
// It speaks only to the Discord client running on this computer, over Discord's own
// local pipe (discord-ipc-0..9); Kisel opens no network connection for it, and holds
// no Discord sign-in. What is sent: one of three fixed lines for the state of the
// newest session, since when, and the session's name if the user asked for that too
// (`discordProject`, off by default). Nothing of what Claude or the user wrote.
//
// Discord shows an activity under the name of a Discord application, so one is
// needed: its Application ID (a public number, not a secret) is kept in Preferences.
class DiscordPresence : public QObject
{
    Q_OBJECT
    // off | noid (no Application ID yet) | waiting (Discord is not running) | on | refused
    Q_PROPERTY(QString state READ state NOTIFY changed)

public:
    // (`live` false: a trial run, which must not show up in anybody's profile)
    DiscordPresence(Preferences *prefs, AgentHub *hub, bool live = true, QObject *parent = nullptr);
    ~DiscordPresence() override;

    QString state() const { return m_state; }

    // Pure, unit-tested.
    // What to show for a session in `state` (work | think | alert | done | failed | idle);
    // an empty object: nothing (no session). `project`: "" to keep it to oneself.
    static QJsonObject activity(const QString &state, const QString &project, qint64 sinceSecs, bool russian);
    static QByteArray frame(int op, const QJsonObject &body);
    // Takes one whole frame off the front of `buf`; false while there is none yet.
    static bool unframe(QByteArray &buf, int &op, QJsonObject &body);
    static bool validId(const QString &id);

signals:
    void changed();

private:
    void apply();   // the preferences changed: connect, or let go
    void dial();    // try the next pipe
    void read();
    void push();    // send what there is to show, if it differs from what was sent
    void drop();
    void set(const QString &state);

    Preferences *m_prefs;
    AgentHub *m_hub;
    QLocalSocket m_sock;
    QTimer m_retry, m_settle;
    QByteArray m_in;
    QString m_state = QStringLiteral("off"), m_id;
    QJsonObject m_sent;
    int m_pipe = 0;
    bool m_ready = false, m_sentAny = false, m_live = true;
    qint64 m_since = 0;
};

} // namespace kisel
