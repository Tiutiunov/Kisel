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
    // The session to talk to when Kisel knows it as `session`: that one if its mod is
    // listening; if not, the session whose mod beat last. (Claude Code's hooks and its
    // plugins do not always call a session by the same id: one that was resumed keeps its
    // first id for the hooks and takes a new one for the plugins. Kisel hears of it under
    // one name and its mod beats under the other.) `session` itself when nobody listens.
    Q_INVOKABLE QString best(const QString &session) const;
    // The talk had from Kisel's chat, kept on disk so that it is there after a restart:
    // [{role, text, time}], oldest first. Kept small: the last 200 lines of a project and
    // no more than 200 KB of them, a long one cut to its first 4000 characters, the file
    // packed. It is read when its project is looked at, not held in memory. `key` says whose talk it
    // is; the chat keys it by the project's folder, so a new session in the same project
    // carries on where the last one stopped. It is a file beside the inbox, for this user
    // alone; nothing in it leaves the computer.
    Q_INVOKABLE QVariantList history(const QString &key) const;
    // The folder a talk is kept under when the session is in `cwd`: the highest folder
    // above it (or itself) that has a talk already, else `cwd`. A session moves about
    // inside its project (`cd` into a subfolder and back); its talk must not split in two.
    Q_INVOKABLE QString home(const QString &cwd) const;
    Q_INVOKABLE void remember(const QString &key, const QString &role, const QString &text);
    Q_INVOKABLE void forget(const QString &key);
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
    QString historyFile(const QString &key) const;
    QString m_root;
    QStringList m_watched, m_live, m_waiting;
    QHash<QString, QVariantList> m_limits;
    QHash<QString, QString> m_models;
    QHash<QString, qint64> m_limitsRead; // the file's time when it was last read
    QTimer m_timer;
    int m_next = 0;
};

} // namespace kisel
