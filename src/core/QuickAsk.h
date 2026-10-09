#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

namespace kisel {

// A quick question, outside any session: the chat's "Quick" talk. It is temporary: it is
// not kept on disk, and it touches no project.
//
// Kisel asks through Claude Code's own command line, as a person would for one answer:
//
//   claude -p --output-format stream-json --include-partial-messages --no-session-persistence --tools WebSearch,WebFetch ...
//
// with the question on its standard input. So it needs no API key (it is the user's own
// Claude Code sign-in) and Kisel holds no credentials. Every question is a new process
// in an empty folder of its own, with two tools and no others: it may search the web
// and read a page, to answer about today's things; it can never read or write a file or
// run anything. The user's settings are left out of it
// (`--setting-sources project,local`), so no hooks fire (Kisel would otherwise show the
// question as a session at work) and no plugins load. Nothing is saved by Claude Code
// either; what was said so far goes along with each new question as text.
//
// The answer is read as it is written (`partial`): Claude Code takes a couple of seconds
// to start and several more to finish, and waiting for the end of it felt slow.
class QuickAsk : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // Where an answer has got to: "" (none in hand) | wait (Claude Code is starting, or
    // thinking) | search (it has gone to the web) | write (its words are coming). For
    // the mascot, who looks things up and then types.
    Q_PROPERTY(QString phase READ phase NOTIFY changed)
    // "" | login (the command line is not signed in) | noclaude (no `claude` to run) | the reason, as Claude Code gave it
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // The models offered: "" is whatever Claude Code would use; the rest are its aliases for the newest of each.
    Q_PROPERTY(QStringList models READ models CONSTANT)
    // How hard it should think: "" is Claude Code's own choice; the rest are its levels.
    Q_PROPERTY(QStringList efforts READ efforts CONSTANT)

public:
    explicit QuickAsk(QObject *parent = nullptr);

    bool busy() const { return m_proc.state() != QProcess::NotRunning; }
    QString error() const { return m_error; }
    QString phase() const { return !m_demoPhase.isEmpty() ? m_demoPhase : busy() && !m_done ? m_phase : QString(); }
    QStringList models() const { return {QString(), QStringLiteral("haiku"), QStringLiteral("sonnet"), QStringLiteral("opus"), QStringLiteral("fable")}; }

    QStringList efforts() const { return {QString(), QStringLiteral("low"), QStringLiteral("medium"), QStringLiteral("high"), QStringLiteral("xhigh"), QStringLiteral("max")}; }

    // `turns`: what was said so far, [{role, text}]; `model`: one of `models`; `effort`: one of `efforts`.
    Q_INVOKABLE void ask(const QVariantList &turns, const QString &question, const QString &model, const QString &effort = QString());
    Q_INVOKABLE void cancel();

    // Pure, unit-tested.
    static QString compose(const QVariantList &turns, const QString &question);
    static QStringList arguments(const QString &model, const QString &effort = QString());
    // What `claude -p --output-format json` printed: the answer, or why there is none.
    static bool parse(const QByteArray &out, QString *answer, QString *error);
    // One line of `--output-format stream-json`: more of the answer's text (`delta`), word
    // that it has gone to look something up (`looking`), or the end of it (returns true:
    // then `answer` or `error` is set, as `parse` sets them).
    static bool feed(const QByteArray &line, QString *delta, bool *looking, QString *answer, QString *error);

signals:
    void changed();
    void answered(const QString &text);
    void partial(const QString &soFar);  // the answer as far as it has been written
    void looking();                      // it has gone to the web for something

private:
    void fail(const QString &why);

    QProcess m_proc;
    QTimer m_limit;
    void read();

    void setPhase(const QString &p) { if (p != m_phase) { m_phase = p; emit changed(); } }
    QString m_error, m_soFar, m_phase, m_demoPhase; // (`m_demoPhase`: the rehearsal's, see KISEL_DEMO_QUICK)
    QByteArray m_buf;
    QTimer m_tell; // (a burst of words is told of once: the chat lays the answer out anew each time)
    bool m_cancelled = false, m_done = false;
};

} // namespace kisel
