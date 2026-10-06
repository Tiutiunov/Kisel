#pragma once

#include "HookServer.h"
#include "Preferences.h"
#include "SessionModel.h"

#include <QPointer>
#include <QTimer>

namespace kisel {

// The brain. Turns hook events into: sessions, a permission queue and the
// mascot's mood. QML only reads properties and calls allow/deny/always.
//
// Mood priority (motion.md): alert (a request waits) > happy/sad (short-lived
// overrides) > think/work (a session is busy) > sleep (60 s of silence) > idle.
class AgentHub : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mood READ mood NOTIFY moodChanged)
    Q_PROPERTY(QString statusLine READ statusLine NOTIFY moodChanged)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY permissionChanged)
    Q_PROPERTY(QVariantMap permission READ permission NOTIFY permissionChanged)
    Q_PROPERTY(QVariantMap session READ session NOTIFY sessionChanged)
    Q_PROPERTY(QObject *sessions READ sessions CONSTANT)
    Q_PROPERTY(bool serverUp READ serverUp CONSTANT)

public:
    AgentHub(Preferences *prefs, QObject *parent = nullptr);

    bool start(const QString &socketPath);
    bool serverUp() const { return m_serverUp; }

    QString mood() const { return m_mood; }
    QString statusLine() const { return m_statusLine; }
    int pendingCount() const { return int(m_queue.size()); }
    QVariantMap permission() const { return m_queue.isEmpty() ? QVariantMap() : m_queue.first().view; }
    QVariantMap session() const;
    QObject *sessions() { return &m_sessions; }

    // QML
    Q_INVOKABLE void allow(const QString &id) { answer(id, QStringLiteral("allow")); }
    Q_INVOKABLE void deny(const QString &id) { answer(id, QStringLiteral("deny")); }
    Q_INVOKABLE void always(const QString &id) { answer(id, QStringLiteral("always")); }
    // "Reply in terminal": say nothing, Claude Code asks there.
    Q_INVOKABLE void passToTerminal(const QString &id);
    // answers: {"<question text>": "<label>" or "<label1>, <label2>" for multi-select}
    Q_INVOKABLE void answerQuestion(const QString &id, const QVariantMap &answers);
    Q_INVOKABLE void poke(); // pointer or click: wake up

    // Tests and the dev tool feed events through here too.
    void handle(const QJsonObject &payload, HookConnection *conn = nullptr);
    static QString ruleKey(const QString &tool, const QJsonObject &input);
    static QVariantMap describePermission(const QString &tool, const QJsonObject &input);
    // The line sent to the relay for an AskUserQuestion: allow, with the user's
    // answers added to the tool input (hookSpecificOutput.decision.updatedInput).
    static QByteArray questionAnswerLine(const QJsonObject &input, const QVariantMap &answers);

signals:
    void moodChanged();
    void permissionChanged();
    void sessionChanged();
    void activity();                       // anything happened; resets the sleep timer
    void permissionArrived();              // island should open by itself
    void permissionAnswered(const QString &decision); // allow | deny | always | terminal
    void permissionCleared();              // answered elsewhere, card just disappears
    void taskFinished();
    void toolFailed();

private:
    struct Pending {
        QString id;
        QPointer<HookConnection> conn;
        QVariantMap view;
        QString key;
        QString sessionId;
        QString tool;
        QJsonObject input;
    };

    void onEvent(HookConnection *conn);
    void answer(const QString &id, const QString &decision);
    void setOverride(const QString &mood, int ms);
    void recompute();
    static QString stepLabel(const QString &tool, const QJsonObject &input);
    void applyToolDiff(Session &s, const QString &tool, const QJsonObject &input);
    void closeRunningSteps(Session &s, const QString &state);

    Preferences *m_prefs;
    HookServer m_server;
    SessionModel m_sessions;
    QList<Pending> m_queue;
    QString m_mood = QStringLiteral("idle");
    QString m_statusLine = QStringLiteral("Kisel");
    QString m_override;
    int m_overrideGen = 0;
    bool m_asleep = false;
    bool m_serverUp = false;
    int m_nextId = 1;
    QTimer m_sleepTimer;
};

} // namespace kisel
