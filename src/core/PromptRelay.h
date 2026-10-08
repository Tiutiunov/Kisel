#pragma once

#include <QObject>
#include <QHash>
#include <QStringList>
#include <QVariantList>
#include <QTimer>

namespace kisel {

// Prompts typed in Kisel for a Claude Code session. Claude Code has no door for them of
// its own; a small mod running inside the session (mods/kisel-prompts) keeps one: a
// folder per session under <data>/inbox/<session id>/, which is all the two share.
//
//   alive        the mod's heartbeat: the time it last looked, rewritten every two seconds
//   <n>.prompt   one prompt, written here whole (a temporary file renamed into place)
//   <n>.taken    written by the mod once it has handed the prompt to the session
//   <n>.reply    written by the mod: something Claude said in the session, for the chat
//   limits       what the session knows of the account's limits, as JSON, rewritten by the
//                mod when it changes: {"model","limits":[{"kind","used","resetsAt"}],"context":{"used"}}
//
// Kisel only ever writes what the user typed and pressed Send on, and removes a prompt
// and its receipt once it has seen the receipt. A session nobody listens to gets nothing:
// `live` names the sessions whose heartbeat is fresh, and the field shows only for those.
class PromptRelay : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList live READ live NOTIFY changed)       // sessions with a listening mod
    Q_PROPERTY(QStringList waiting READ waiting NOTIFY changed) // sessions with a prompt not yet taken

public:
    explicit PromptRelay(const QString &root, QObject *parent = nullptr);

    QStringList live() const { return m_live; }
    QStringList waiting() const { return m_waiting; }

    // Kisel has seen this session: make its folder, so the mod has somewhere to beat.
    Q_INVOKABLE void watch(const QString &session);
    // False when there is nothing to send, nobody listening, or the file cannot be written.
    Q_INVOKABLE bool send(const QString &session, const QString &text);
    // The session's limits as the mod last reported them: [{kind, used (0..100), resetsAt}],
    // the context window last, as kind "context". Empty when it has reported none.
    Q_INVOKABLE QVariantList limits(const QString &session) const { return m_limits.value(session); }
    static QVariantList parseLimits(const QByteArray &json);
    // The model the session runs on, as it names it ("" until the mod has said).
    Q_INVOKABLE QString model(const QString &session) const { return m_models.value(session); }
    static QString parseModel(const QByteArray &json);

    QString folder(const QString &session) const;
    static bool safeId(const QString &session);
    void scan();

signals:
    void changed();
    void taken(const QString &session);
    // Claude said this in the session (model output: plain text, to be shown as such).
    void reply(const QString &session, const QString &text);

private:
    QString m_root;
    QStringList m_watched, m_live, m_waiting;
    QHash<QString, QVariantList> m_limits;
    QHash<QString, QString> m_models;
    QHash<QString, qint64> m_limitsRead; // the file's time when it was last read
    QTimer m_timer;
    int m_next = 0;
};

} // namespace kisel
