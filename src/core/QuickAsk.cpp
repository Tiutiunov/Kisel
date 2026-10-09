#include "QuickAsk.h"

#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace kisel {

namespace {
constexpr int kTurnsKept = 12;     // of the talk so far, sent along with a question
constexpr int kTurnChars = 4000;
constexpr int kLimitMs = 180000;
}

QuickAsk::QuickAsk(QObject *parent) : QObject(parent)
{
    m_limit.setSingleShot(true);
    m_limit.setInterval(kLimitMs);
    connect(&m_limit, &QTimer::timeout, this, [this] { m_cancelled = true; m_proc.kill(); fail(QStringLiteral("It took too long")); });
    m_tell.setSingleShot(true);
    m_tell.setInterval(70);
    connect(&m_tell, &QTimer::timeout, this, [this] { if (!m_done && !m_soFar.trimmed().isEmpty()) emit partial(m_soFar); });
    connect(&m_proc, &QProcess::readyReadStandardOutput, this, &QuickAsk::read);
    connect(&m_proc, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
        m_limit.stop();
        read();
        if (m_cancelled || m_done) {
            emit changed();
            return;
        }
        // (it ended without saying so: what there is of an answer is the answer)
        if (!m_soFar.trimmed().isEmpty()) {
            m_done = true;
            emit changed();
            emit answered(m_soFar.trimmed());
        } else {
            fail(QStringLiteral("Claude Code gave no answer"));
        }
    });
    connect(&m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_limit.stop();
            fail(QStringLiteral("noclaude"));
        }
    });
}

QString QuickAsk::compose(const QVariantList &turns, const QString &question)
{
    QString out;
    const int from = qMax(0, int(turns.size()) - kTurnsKept);
    for (int i = from; i < turns.size(); ++i) {
        const QVariantMap t = turns.at(i).toMap();
        const QString text = t.value("text").toString().trimmed().left(kTurnChars);
        if (text.isEmpty())
            continue;
        out += (t.value("role").toString() == QLatin1String("user") ? QStringLiteral("User: ") : QStringLiteral("You: ")) + text + QStringLiteral("\n\n");
    }
    if (!out.isEmpty())
        out = QStringLiteral("Earlier in this talk:\n\n") + out + QStringLiteral("Now the user asks:\n\n");
    return out + question.trimmed();
}

QStringList QuickAsk::arguments(const QString &model, const QString &effort)
{
    QStringList a {QStringLiteral("-p"), QStringLiteral("--output-format"), QStringLiteral("stream-json"),
                   QStringLiteral("--include-partial-messages"), QStringLiteral("--verbose"),
                   QStringLiteral("--no-session-persistence"), QStringLiteral("--setting-sources"), QStringLiteral("project,local"),
                   QStringLiteral("--strict-mcp-config"),
                   // (the web, to look things up, and nothing else: no files, no commands)
                   QStringLiteral("--tools"), QStringLiteral("WebSearch,WebFetch"),
                   QStringLiteral("--allowedTools"), QStringLiteral("WebSearch,WebFetch"),
                   // (added to Claude Code's own prompt, not put in its place: without that one it does not know it can search)
                   QStringLiteral("--append-system-prompt"),
                   QStringLiteral("You are answering a quick question in a small chat window, outside any project. Speed matters most: answer at once, "
                                  "briefly, with no preamble and no closing remarks. "
                                  "The window renders Markdown handsomely, so shape the answer for the eye: the answer itself first, in one line with the "
                                  "key words in **bold**; then, only where it helps, a short list, a small table for a comparison (four columns at most), "
                                  "a fenced block for code or a command, and a line starting with > for a tip or a warning. Use ## headings only when the "
                                  "answer has several parts. No emoji. "
                                  "Answer in the language the question is written in. A quick question is typed fast: if a name or a word looks "
                                  "misspelled or oddly transliterated, take it for the nearest real one and answer about that, saying which you took, "
                                  "rather than asking back. "
                                  "You can search and read the web when the answer needs it; you have no other tools.")};
    // (an alias of Claude Code's own, nothing else: it goes onto a command line)
    static const QStringList known {QStringLiteral("haiku"), QStringLiteral("sonnet"), QStringLiteral("opus"), QStringLiteral("fable")};
    if (known.contains(model))
        a << QStringLiteral("--model") << model;
    static const QStringList levels {QStringLiteral("low"), QStringLiteral("medium"), QStringLiteral("high"), QStringLiteral("xhigh"), QStringLiteral("max")};
    if (levels.contains(effort))
        a << QStringLiteral("--effort") << effort;
    return a;
}

bool QuickAsk::feed(const QByteArray &line, QString *delta, bool *looking, QString *answer, QString *error)
{
    const QJsonObject o = QJsonDocument::fromJson(line).object();
    const QString type = o.value("type").toString();
    if (type == QLatin1String("result"))
        return parse(line, answer, error) || !error->isEmpty();
    if (type != QLatin1String("stream_event"))
        return false;
    const QJsonObject ev = o.value("event").toObject();
    const QString kind = ev.value("type").toString();
    if (kind == QLatin1String("content_block_delta")) {
        const QJsonObject d = ev.value("delta").toObject();
        if (d.value("type").toString() == QLatin1String("text_delta"))
            *delta = d.value("text").toString();
    } else if (kind == QLatin1String("content_block_start")) {
        const QString block = ev.value("content_block").toObject().value("type").toString();
        if (block.contains(QLatin1String("tool_use")))
            *looking = true;
    }
    return false;
}

void QuickAsk::read()
{
    m_buf += m_proc.readAllStandardOutput();
    for (;;) {
        const int nl = m_buf.indexOf('\n');
        if (nl < 0)
            break;
        const QByteArray line = m_buf.left(nl).trimmed();
        m_buf.remove(0, nl + 1);
        if (line.isEmpty() || m_done || m_cancelled)
            continue;
        QString delta, answer, error;
        bool look = false;
        if (feed(line, &delta, &look, &answer, &error)) {
            m_done = true;
            m_tell.stop();
            if (!answer.isEmpty()) {
                emit changed();
                emit answered(answer);
            } else {
                fail(error);
            }
            continue;
        }
        if (look) { // (what it said before going to look was a remark, not the answer)
            m_soFar.clear();
            setPhase(QStringLiteral("search"));
            emit looking();
        }
        if (!delta.isEmpty()) {
            setPhase(QStringLiteral("write"));
            m_soFar += delta;
            if (!m_tell.isActive())
                m_tell.start();
        }
    }
}

bool QuickAsk::parse(const QByteArray &out, QString *answer, QString *error)
{
    const int at = out.indexOf('{');
    const QJsonObject o = at < 0 ? QJsonObject() : QJsonDocument::fromJson(out.mid(at)).object();
    const QString result = o.value("result").toString().trimmed();
    if (o.isEmpty() || result.isEmpty()) {
        *error = QStringLiteral("Claude Code gave no answer");
        return false;
    }
    if (o.value("is_error").toBool()) {
        *error = result.contains(QLatin1String("Not logged in"), Qt::CaseInsensitive) ? QStringLiteral("login") : result.left(200);
        return false;
    }
    *answer = result;
    return true;
}

void QuickAsk::fail(const QString &why)
{
    m_error = why;
    emit changed();
}

void QuickAsk::ask(const QVariantList &turns, const QString &question, const QString &model, const QString &effort)
{
    if (busy() || question.trimmed().isEmpty())
        return;
    m_error.clear();
    m_cancelled = false;
    m_done = false;
    m_soFar.clear();
    m_buf.clear();
    m_phase = QStringLiteral("wait");
    // KISEL_DEMO_QUICK=1: an answer of its own making after a moment, with no Claude Code (development)
    if (qEnvironmentVariableIsSet("KISEL_DEMO_QUICK")) {
        const QString all = QStringLiteral("**Qt 6.12** is the newest stable release.\n\n## What to pick\n\n"
                                         "| Version | Kind | Until |\n| --- | --- | --- |\n| 6.12 | newest | 2027 |\n| 6.8 | long-term | 2029 |\n\n"
                                         "- `6.12` for new work\n- `6.8` if you need **long support**\n\n"
                                         "1. Open the installer\n2. Tick the version\n\n"
                                         "```powershell\nwinget install Qt.OnlineInstaller\n```\n\n"
                                         "> Keep one kit per project: mixing them breaks builds.");
        // (KISEL_DEMO_QUICK=search: it stays at the looking-up; =write: at the writing)
        const QString hold = qEnvironmentVariable("KISEL_DEMO_QUICK");
        m_demoPhase = QStringLiteral("search");
        emit changed();
        if (hold == QLatin1String("search"))
            return;
        for (int n = 1; n <= 12; ++n)
            QTimer::singleShot(300 + n * 120, this, [this, all, n, hold] {
                m_demoPhase = n < 12 || hold == QLatin1String("write") ? QStringLiteral("write") : QString();
                emit changed();
                if (n < 12) emit partial(all.left(all.size() * n / 12)); else if (hold != QLatin1String("write")) emit answered(all);
            });
        return;
    }
    const QString dir = QDir::tempPath() + QStringLiteral("/kisel-quick"); // (an empty folder: no project, no CLAUDE.md)
    QDir().mkpath(dir);
    m_proc.setWorkingDirectory(dir);
    m_proc.setProcessChannelMode(QProcess::SeparateChannels);
    const QStringList args = arguments(model, effort);
#ifdef Q_OS_WIN
    // (npm installs `claude` as a .cmd: that is run by the command interpreter, not by itself)
    m_proc.start(QStringLiteral("cmd.exe"), QStringList {QStringLiteral("/c"), QStringLiteral("claude")} + args);
#else
    m_proc.start(QStringLiteral("claude"), args);
#endif
    m_proc.write(compose(turns, question).toUtf8());
    m_proc.closeWriteChannel();
    m_limit.start();
    emit changed();
}

void QuickAsk::cancel()
{
    if (!busy())
        return;
    m_cancelled = true;
    m_limit.stop();
    m_proc.kill();
}

} // namespace kisel
