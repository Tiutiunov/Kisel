// Unit tests for the parts that carry risk: permission summaries, "Always"
// rule keys, settings.json merging, the line diff, SSE parsing and the hook
// socket protocol end to end.
#include "AgentHub.h"
#include "ChatClient.h"
#include "GitHubClient.h"
#include "HookInstaller.h"
#include "HookServer.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalSocket>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

using namespace kisel;

class CoreTest : public QObject
{
    Q_OBJECT

private slots:
    void ruleKeyForPlainCommandUsesFirstTwoWords()
    {
        QCOMPARE(AgentHub::ruleKey("Bash", {{"command", "npm test -- --watch"}}), QString("Bash:npm test"));
    }

    void ruleKeyForChainedCommandIsExact()
    {
        const QString cmd = "npm test && rm -rf build";
        QCOMPARE(AgentHub::ruleKey("Bash", {{"command", cmd}}), "Bash:exact:" + cmd);
        QVERIFY(AgentHub::ruleKey("Bash", {{"command", "cat a | sh"}}).startsWith("Bash:exact:"));
        QVERIFY(AgentHub::ruleKey("Bash", {{"command", "echo $(id)"}}).startsWith("Bash:exact:"));
    }

    void ruleKeyForEditIsItsDirectory()
    {
        QCOMPARE(AgentHub::ruleKey("Edit", {{"file_path", "/p/src/a.ts"}}), QString("Edit:/p/src"));
        QVERIFY(AgentHub::ruleKey("AskUserQuestion", {}).isEmpty());
    }

    void editPermissionBuildsDiff()
    {
        const QVariantMap v = AgentHub::describePermission(
            "Edit", {{"file_path", "/p/a.ts"}, {"old_string", "a\nb"}, {"new_string", "c"}});
        QCOMPARE(v["kind"].toString(), QString("diff"));
        QCOMPARE(v["removed"].toInt(), 2);
        QCOMPARE(v["added"].toInt(), 1);
        QCOMPARE(v["diff"].toList().first().toMap()["kind"].toString(), QString("del"));
    }

    void installAddsOurHooksAndKeepsTheUsers()
    {
        const QJsonObject userHook {{"matcher", "Bash"}, {"hooks", QJsonArray {QJsonObject {{"type", "command"}, {"command", "/usr/bin/my-linter"}}}}};
        const QJsonObject before {{"model", "x"}, {"hooks", QJsonObject {{"PreToolUse", QJsonArray {userHook}}}}};

        const QString cmd = "/home/u/.local/share/kisel/bin/kisel-hook";
        const QJsonObject after = HookInstaller::merge(before, cmd, true);
        const QJsonArray pre = after["hooks"].toObject()["PreToolUse"].toArray();
        QCOMPARE(pre.size(), 2);
        QCOMPARE(pre[0].toObject(), userHook);
        QVERIFY(after["hooks"].toObject().contains("PermissionRequest"));
        QCOMPARE(after["model"].toString(), QString("x"));

        // idempotent: installing twice does not duplicate
        QCOMPARE(HookInstaller::merge(after, cmd, true), after);

        // uninstall restores exactly what the user had
        QCOMPARE(HookInstaller::merge(after, cmd, false), before);
    }

    void uninstallFromEmptyLeavesNoHooksKey()
    {
        const QJsonObject installed = HookInstaller::merge({}, "kisel-hook", true);
        QVERIFY(!HookInstaller::merge(installed, "kisel-hook", false).contains("hooks"));
    }

    void lineDiffMarksOnlyChanges()
    {
        const QVariantList d = HookInstaller::lineDiff("a\nb\nc\nd\ne\nf\ng", "a\nb\nc\nX\ne\nf\ng");
        int add = 0, del = 0;
        for (const QVariant &v : d) {
            add += v.toMap()["kind"] == "add";
            del += v.toMap()["kind"] == "del";
        }
        QCOMPARE(add, 1);
        QCOMPARE(del, 1);
    }

    void questionAnswerLineCarriesTheOriginalInput()
    {
        const QJsonObject input {{"questions", QJsonArray {QJsonObject {{"question", "Which?"}}}}};
        const QByteArray line = AgentHub::questionAnswerLine(input, {{"Which?", "Half up"}});
        const QJsonObject o = QJsonDocument::fromJson(line).object();
        QCOMPARE(o["decision"].toString(), QString("allow"));
        QCOMPARE(o["updatedInput"].toObject()["answers"].toObject()["Which?"].toString(), QString("Half up"));
        QVERIFY(o["updatedInput"].toObject().contains("questions"));
        QVERIFY(!line.contains('\n')); // one line on the wire
    }

    void questionPermissionListsEveryQuestion()
    {
        const QVariantMap v = AgentHub::describePermission("AskUserQuestion", {{"questions", QJsonArray {
            QJsonObject {{"question", "A?"}, {"multiSelect", true}, {"options", QJsonArray {QJsonObject {{"label", "x"}}}}},
            QJsonObject {{"question", "B?"}, {"options", QJsonArray {QJsonObject {{"label", "y"}}}}}}}});
        QCOMPARE(v["kind"].toString(), QString("question"));
        QCOMPARE(v["questions"].toList().size(), 2);
        QVERIFY(v["questions"].toList()[0].toMap()["multi"].toBool());
    }

    void githubResponseBecomesRowsAndCounts()
    {
        const QByteArray body = R"({"data":{"viewer":{"login":"me","pullRequests":{"totalCount":7,"nodes":[
            {"title":"Fix rounding","number":12,"url":"u12","isDraft":false,"reviewDecision":"APPROVED",
             "repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
            {"title":"WIP","number":13,"url":"u13","isDraft":true,"reviewDecision":null,
             "repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}]}},
            "reviews":{"issueCount":3}}})";
        GitHubClient::Result r;
        QString err;
        QVERIFY(GitHubClient::parse(body, &r, &err));
        QCOMPARE(r.login, QString("me"));
        QCOMPARE(r.open, 7);
        QCOMPARE(r.reviews, 3);
        QCOMPARE(r.rows.size(), 2);
        QCOMPARE(r.rows[0].toMap()["ci"].toString(), QString("failure"));
        QCOMPARE(r.rows[1].toMap()["ci"].toString(), QString("none"));
        QVERIFY(r.rows[1].toMap()["draft"].toBool());
    }

    void githubErrorsAreReadable()
    {
        GitHubClient::Result r;
        QString err;
        QVERIFY(!GitHubClient::parse(R"({"errors":[{"message":"Bad credentials"}]})", &r, &err));
        QCOMPARE(err, QString("Bad credentials"));
        QVERIFY(!GitHubClient::parse("<html>", &r, &err));
    }

    void sseDeltaAndErrors()
    {
        QString delta, err;
        bool done = false;
        QVERIFY(ChatClient::parseSseLine(
            R"(data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}})", &delta, &err, &done));
        QCOMPARE(delta, QString("Hi"));
        QVERIFY(ChatClient::parseSseLine(R"(data: {"type":"message_stop"})", &delta, &err, &done));
        QVERIFY(done);
        QVERIFY(ChatClient::parseSseLine(R"(data: {"type":"error","error":{"message":"bad key"}})", &delta, &err, &done));
        QCOMPARE(err, QString("bad key"));
        QVERIFY(!ChatClient::parseSseLine("event: ping", &delta, &err, &done));
    }

    void hubTurnsEventsIntoMoodAndQueue()
    {
        Preferences prefs;
        prefs.clearAlwaysRules();
        AgentHub hub(&prefs);
        QCOMPARE(hub.mood(), QString("idle"));

        hub.handle({{"hook_event_name", "UserPromptSubmit"}, {"session_id", "s"}, {"cwd", "/p/app"}});
        QCOMPARE(hub.mood(), QString("think"));
        hub.handle({{"hook_event_name", "PreToolUse"}, {"session_id", "s"}, {"tool_name", "Edit"},
                    {"tool_input", QJsonObject {{"file_path", "/p/app/invoice.ts"}, {"old_string", "a"}, {"new_string", "b"}}}});
        QCOMPARE(hub.mood(), QString("work"));
        QCOMPARE(hub.statusLine(), QString("Edit invoice.ts"));

        QSignalSpy arrived(&hub, &AgentHub::permissionArrived);
        hub.handle({{"hook_event_name", "PermissionRequest"}, {"session_id", "s"}, {"tool_name", "Bash"},
                    {"tool_input", QJsonObject {{"command", "npm test"}}}});
        QCOMPARE(arrived.count(), 1);
        QCOMPARE(hub.mood(), QString("alert"));
        QCOMPARE(hub.pendingCount(), 1);

        hub.deny(hub.permission()["id"].toString());
        QCOMPARE(hub.pendingCount(), 0);
        QCOMPARE(hub.mood(), QString("sad")); // denied: droops for a moment

        QCOMPARE(hub.chip(), QString()); // nothing waiting, nothing done yet
        hub.handle({{"hook_event_name", "Stop"}, {"session_id", "s"}});
        QCOMPARE(hub.mood(), QString("happy"));
        QCOMPARE(hub.chip(), QString("done")); // the pill's chip stays after the mood has passed
        hub.handle({{"hook_event_name", "UserPromptSubmit"}, {"session_id", "s"}});
        QCOMPARE(hub.chip(), QString()); // new work clears it
    }

    void invalidAgentNameFallsBackToClaudeCode()
    {
        Preferences prefs;
        AgentHub hub(&prefs);
        hub.handle({{"hook_event_name", "UserPromptSubmit"}, {"session_id", "x"}, {"kisel_agent", "Bad Name!"}});
        QCOMPARE(hub.session()["agent"].toString(), QString("claude-code"));
        hub.handle({{"hook_event_name", "UserPromptSubmit"}, {"session_id", "y"}, {"kisel_agent", "my-tool"}});
        QCOMPARE(hub.session()["agent"].toString(), QString("my-tool"));
    }

    // The relay protocol over a real socket: one JSON line in, a decision line out.
    void permissionRoundTripOverTheSocket()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("k.sock");
        Preferences prefs;
        AgentHub hub(&prefs);
        QVERIFY(hub.start(path));

        QLocalSocket client;
        client.connectToServer(path);
        QVERIFY(client.waitForConnected(1000));
        QSignalSpy arrived(&hub, &AgentHub::permissionArrived);
        client.write(R"({"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}})" "\n");
        client.flush();
        QTRY_COMPARE(arrived.count(), 1);

        hub.allow(hub.permission()["id"].toString());
        QVERIFY(client.waitForReadyRead(1000));
        QCOMPARE(client.readAll().trimmed(), QByteArray("allow"));
    }

    void answeredInTerminalClearsTheCard()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("k.sock");
        Preferences prefs;
        AgentHub hub(&prefs);
        QVERIFY(hub.start(path));

        auto *client = new QLocalSocket;
        client->connectToServer(path);
        QVERIFY(client->waitForConnected(1000));
        QSignalSpy cleared(&hub, &AgentHub::permissionCleared);
        client->write(R"({"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}})" "\n");
        client->flush();
        QTRY_COMPARE(hub.pendingCount(), 1);
        client->disconnectFromServer(); // the relay was killed: Claude Code was answered elsewhere
        QTRY_COMPARE(cleared.count(), 1);
        QCOMPARE(hub.pendingCount(), 0);
        delete client;
    }
};

QTEST_MAIN(CoreTest)
#include "test_core.moc"
