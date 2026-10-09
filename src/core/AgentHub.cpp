#include "AgentHub.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>

namespace kisel {

namespace {
constexpr int kMaxSteps = 8;
constexpr int kMaxDiffLines = 40;
constexpr int kSleepAfterMs = 60'000;
constexpr int kHappyMs = 3500;
constexpr int kSadMs = 2600;

QString baseName(const QString &path) { return QFileInfo(path).fileName(); }

QString clip(QString s, int n)
{
    s = s.section('\n', 0, 0).simplified();
    return s.size() > n ? s.left(n - 1) + QChar(0x2026) : s;
}

void appendDiff(QVariantList &out, int &added, int &removed, const QString &oldText, const QString &newText)
{
    int no = 1;
    for (const QString &l : oldText.split('\n', Qt::KeepEmptyParts)) {
        if (oldText.isEmpty() || out.size() >= kMaxDiffLines)
            break;
        out.append(QVariantMap {{"kind", "del"}, {"no", no++}, {"text", l}});
        ++removed;
    }
    no = 1;
    for (const QString &l : newText.split('\n', Qt::KeepEmptyParts)) {
        if (newText.isEmpty() || out.size() >= 2 * kMaxDiffLines)
            break;
        out.append(QVariantMap {{"kind", "add"}, {"no", no++}, {"text", l}});
        ++added;
    }
}
} // namespace

AgentHub::AgentHub(Preferences *prefs, QObject *parent)
    : QObject(parent)
    , m_prefs(prefs)
    , m_server(this)
    , m_sessions(this)
{
    connect(&m_server, &HookServer::eventReceived, this, &AgentHub::onEvent);
    m_sleepTimer.setSingleShot(true);
    m_sleepTimer.setInterval(kSleepAfterMs);
    connect(&m_sleepTimer, &QTimer::timeout, this, [this] {
        m_asleep = true;
        recompute();
    });
    m_sleepTimer.start();

    m_chipTimer.setSingleShot(true);
    m_chipTimer.setInterval(25'000);
    connect(&m_chipTimer, &QTimer::timeout, this, [this] {
        m_chipBase.clear();
        recompute();
    });
}

bool AgentHub::start(const QString &socketPath)
{
    m_serverUp = m_server.start(socketPath);
    return m_serverUp;
}

QVariantMap AgentHub::session() const
{
    const Session *s = m_sessions.latest();
    return s ? s->toVariant() : QVariantMap();
}

void AgentHub::poke()
{
    m_asleep = false;
    m_sleepTimer.start();
    recompute();
}

void AgentHub::onEvent(HookConnection *conn)
{
    handle(conn->payload(), conn);
}

// ---- permission summaries ----------------------------------------------------

QString AgentHub::ruleKey(const QString &tool, const QJsonObject &input)
{
    if (tool == QLatin1String("Bash")) {
        const QString cmd = input.value("command").toString().trimmed();
        if (cmd.isEmpty())
            return {};
        // Anything that chains, pipes, substitutes or redirects is remembered
        // only as that exact command.
        static const QRegularExpression meta(QStringLiteral("[;|&`$()<>\\n]"));
        if (meta.match(cmd).hasMatch())
            return QStringLiteral("Bash:exact:") + cmd;
        const QStringList t = cmd.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
        return QStringLiteral("Bash:") + t.mid(0, 2).join(' ');
    }
    const QString file = input.value("file_path").toString();
    if (!file.isEmpty() && (tool == "Edit" || tool == "MultiEdit" || tool == "Write"))
        return tool + ':' + QFileInfo(file).path();
    return {};
}

QVariantMap AgentHub::describePermission(const QString &tool, const QJsonObject &input)
{
    QVariantMap v {{"tool", tool}, {"kind", "command"}, {"file", ""}, {"summary", ""},
                   {"diff", QVariantList()}, {"added", 0}, {"removed", 0},
                   {"question", ""}, {"options", QVariantList()}};

    if (tool == QLatin1String("Bash")) {
        v["summary"] = input.value("command").toString();
    } else if (tool == "Edit" || tool == "MultiEdit" || tool == "Write") {
        QVariantList diff;
        int add = 0, del = 0;
        if (tool == "Edit") {
            appendDiff(diff, add, del, input.value("old_string").toString(), input.value("new_string").toString());
        } else if (tool == "MultiEdit") {
            for (const QJsonValue &e : input.value("edits").toArray())
                appendDiff(diff, add, del, e.toObject().value("old_string").toString(),
                           e.toObject().value("new_string").toString());
        } else {
            appendDiff(diff, add, del, QString(), input.value("content").toString());
        }
        v["kind"] = "diff";
        v["file"] = input.value("file_path").toString();
        v["diff"] = diff;
        v["added"] = add;
        v["removed"] = del;
    } else if (tool == QLatin1String("AskUserQuestion")) {
        // Up to four questions, each single or multi-select.
        v["kind"] = "question";
        QVariantList questions;
        for (const QJsonValue &qv : input.value("questions").toArray()) {
            const QJsonObject q = qv.toObject();
            QVariantList options;
            for (const QJsonValue &o : q.value("options").toArray())
                options.append(QVariantMap {{"label", o.toObject().value("label").toString()},
                                            {"description", o.toObject().value("description").toString()}});
            questions.append(QVariantMap {{"question", q.value("question").toString()},
                                          {"header", q.value("header").toString()},
                                          {"multi", q.value("multiSelect").toBool()},
                                          {"options", options}});
        }
        v["questions"] = questions;
        v["question"] = questions.isEmpty() ? QString() : questions.first().toMap().value("question").toString();
    } else {
        v["summary"] = QString::fromUtf8(QJsonDocument(input).toJson(QJsonDocument::Compact));
    }
    return v;
}

// ---- events -------------------------------------------------------------------

QString AgentHub::stepLabel(const QString &tool, const QJsonObject &input)
{
    if (tool == "Bash")
        return QStringLiteral("Run ") + clip(input.value("command").toString(), 44);
    if (tool == "Edit" || tool == "MultiEdit" || tool == "Write")
        return QStringLiteral("Edit ") + baseName(input.value("file_path").toString());
    if (tool == "Read")
        return QStringLiteral("Read ") + baseName(input.value("file_path").toString());
    if (tool == "Grep" || tool == "Glob")
        return QStringLiteral("Search ") + clip(input.value("pattern").toString(), 40);
    return tool.isEmpty() ? QStringLiteral("Working") : tool;
}

void AgentHub::applyToolDiff(Session &s, const QString &tool, const QJsonObject &input)
{
    if (tool == "Bash") {
        s.command = input.value("command").toString();
    } else if (tool == "Edit" || tool == "MultiEdit" || tool == "Write") {
        const QVariantMap d = describePermission(tool, input);
        s.file = d.value("file").toString();
        s.diff = d.value("diff").toList();
        s.added = d.value("added").toInt();
        s.removed = d.value("removed").toInt();
    }
}

void AgentHub::closeRunningSteps(Session &s, const QString &state)
{
    for (Step &st : s.steps)
        if (st.state == QLatin1String("running"))
            st.state = state;
}

void AgentHub::handle(const QJsonObject &p, HookConnection *conn)
{
    const QString ev = p.value("hook_event_name").toString();
    QString sid = p.value("session_id").toString();
    if (sid.isEmpty())
        sid = QStringLiteral("default");
    static const QRegularExpression agentOk(QStringLiteral("^[a-z0-9-]{1,24}$"));
    QString agent = p.value("kisel_agent").toString();
    if (!agentOk.match(agent).hasMatch())
        agent = QStringLiteral("claude-code");
    const QString tool = p.value("tool_name").toString();
    const QJsonObject input = p.value("tool_input").toObject();

    if (qEnvironmentVariableIsSet("KISEL_DEBUG"))
        qInfo("hook: %s session=%s tool=%s", qPrintable(ev), qPrintable(sid), qPrintable(tool));

    m_asleep = false;
    m_sleepTimer.start();
    if (!m_prefs->hookSeen())
        m_prefs->setHookSeen(true); // the first connection is done: Home stops showing the trio
    emit activity();

    if (ev == QLatin1String("SessionEnd")) {
        m_sessions.remove(sid);
        emit sessionChanged();
        recompute();
        return;
    }

    Session &s = m_sessions.ensure(sid, agent, p.value("cwd").toString());

    if (ev == QLatin1String("UserPromptSubmit") || ev == QLatin1String("PreToolUse")) {
        m_chipBase.clear(); // new work: the old Done / Failed chip goes away
        m_chipTimer.stop();
    }

    if (ev == QLatin1String("UserPromptSubmit")) {
        s.state = QStringLiteral("think");
        s.line = QStringLiteral("Thinking") + QChar(0x2026);
        s.prompt = p.value("prompt").toString();
        emit prompted(s.id, s.cwd, s.name, s.prompt);
        s.steps.clear();
        s.file.clear();
        s.diff.clear();
        s.command.clear();
        s.added = s.removed = 0;
    } else if (ev == QLatin1String("PreToolUse")) {
        closeRunningSteps(s, "done");
        s.state = QStringLiteral("work");
        s.line = stepLabel(tool, input);
        s.steps.append({s.line, QStringLiteral("running")});
        while (s.steps.size() > kMaxSteps)
            s.steps.removeFirst();
        applyToolDiff(s, tool, input);
    } else if (ev == QLatin1String("PostToolUse")) {
        closeRunningSteps(s, "done");
        s.state = QStringLiteral("think"); // Claude decides the next move
        s.line = QStringLiteral("Thinking") + QChar(0x2026);
    } else if (ev == QLatin1String("PostToolUseFailure")) {
        closeRunningSteps(s, "failed");
        s.state = QStringLiteral("failed");
        m_chipBase = QStringLiteral("failed");
        m_chipTimer.start();
        emit toolFailed();
        setOverride("sad", kSadMs);
    } else if (ev == QLatin1String("Stop")) {
        closeRunningSteps(s, "done");
        s.state = QStringLiteral("done");
        s.line = QStringLiteral("Done");
        m_chipBase = QStringLiteral("done");
        m_chipTimer.start();
        emit taskFinished();
        setOverride("happy", kHappyMs);
    } else if (ev == QLatin1String("PermissionRequest")) {
        Pending pd;
        pd.id = QString::number(m_nextId++);
        pd.conn = conn;
        pd.sessionId = sid;
        pd.tool = tool;
        pd.input = input;
        pd.key = ruleKey(tool, input);

        if (!pd.key.isEmpty() && m_prefs->alwaysRules().contains(pd.key)) {
            // The user clicked "Always" on this exact pattern earlier.
            if (conn)
                conn->answer(QStringLiteral("allow"));
            s.steps.append({QStringLiteral("Allowed ") + stepLabel(tool, input), QStringLiteral("done")});
        } else {
            pd.view = describePermission(tool, input);
            pd.view["id"] = pd.id;
            pd.view["session"] = s.name;
            pd.view["cwd"] = s.cwd;
            pd.view["canAlways"] = !pd.key.isEmpty();
            m_queue.append(pd);
            if (conn)
                connect(conn, &HookConnection::gone, this, [this, id = pd.id] {
                    // Answered in the terminal: the card just disappears.
                    for (qsizetype i = 0; i < m_queue.size(); ++i) {
                        if (m_queue[i].id == id) {
                            m_queue.removeAt(i);
                            emit permissionCleared();
                            emit permissionChanged();
                            recompute();
                            return;
                        }
                    }
                });
            emit permissionChanged();
            emit permissionArrived();
        }
    }

    m_sessions.touched(sid);
    emit sessionChanged();
    recompute();
}

void AgentHub::answer(const QString &id, const QString &decision)
{
    for (qsizetype i = 0; i < m_queue.size(); ++i) {
        if (m_queue[i].id != id)
            continue;
        Pending pd = m_queue.takeAt(i);
        if (decision == QLatin1String("always") && !pd.key.isEmpty())
            m_prefs->addAlwaysRule(pd.key);
        if (pd.conn)
            pd.conn->answer(decision);
        if (decision == QLatin1String("deny"))
            setOverride("sad", kSadMs);
        emit permissionAnswered(decision);
        emit permissionChanged();
        recompute();
        return;
    }
}

QByteArray AgentHub::questionAnswerLine(const QJsonObject &input, const QVariantMap &answers)
{
    QJsonObject ans;
    for (auto it = answers.cbegin(); it != answers.cend(); ++it)
        ans[it.key()] = it.value().toString();
    QJsonObject updated = input;
    updated["answers"] = ans;
    const QJsonObject line {{"decision", "allow"}, {"updatedInput", updated}};
    return QJsonDocument(line).toJson(QJsonDocument::Compact);
}

void AgentHub::answerQuestion(const QString &id, const QVariantMap &answers)
{
    for (qsizetype i = 0; i < m_queue.size(); ++i) {
        if (m_queue[i].id != id)
            continue;
        Pending pd = m_queue.takeAt(i);
        if (pd.conn)
            pd.conn->answer(QString::fromUtf8(questionAnswerLine(pd.input, answers)));
        emit permissionAnswered(QStringLiteral("allow"));
        emit permissionChanged();
        recompute();
        return;
    }
}

void AgentHub::passToTerminal(const QString &id)
{
    for (qsizetype i = 0; i < m_queue.size(); ++i) {
        if (m_queue[i].id != id)
            continue;
        Pending pd = m_queue.takeAt(i);
        if (pd.conn)
            pd.conn->release(); // silence: Claude Code asks in the terminal
        emit permissionAnswered(QStringLiteral("terminal"));
        emit permissionChanged();
        recompute();
        return;
    }
}

// ---- mood ----------------------------------------------------------------------

void AgentHub::setOverride(const QString &mood, int ms)
{
    m_override = mood;
    const int gen = ++m_overrideGen;
    QTimer::singleShot(ms, this, [this, gen] {
        if (gen != m_overrideGen)
            return;
        m_override.clear();
        recompute();
    });
}

void AgentHub::recompute()
{
    QString mood, line;
    if (!m_queue.isEmpty()) {
        mood = QStringLiteral("alert");
        line = QStringLiteral("Waiting for you");
    } else if (!m_override.isEmpty()) {
        mood = m_override;
        line = mood == QLatin1String("happy") ? QStringLiteral("Done") : QStringLiteral("Failed");
    } else {
        const Session *latest = nullptr;
        for (const Session &s : m_sessions.items()) {
            if ((s.state == "work" || s.state == "think") && (!latest || s.updated >= latest->updated))
                latest = &s;
        }
        if (latest) {
            mood = latest->state;
            line = latest->line;
        } else if (m_asleep) {
            mood = QStringLiteral("sleep");
            line = QStringLiteral("Kisel");
        } else {
            mood = QStringLiteral("idle");
            line = QStringLiteral("Kisel");
        }
    }
    const QString chip = !m_queue.isEmpty() ? QStringLiteral("needs") : m_chipBase;
    if (mood == m_mood && line == m_statusLine && chip == m_chip)
        return;
    m_mood = mood;
    m_statusLine = line;
    m_chip = chip;
    emit moodChanged();
}

} // namespace kisel
