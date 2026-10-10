// Unit tests for the parts that carry risk: permission summaries, "Always"
// rule keys, settings.json merging, the line diff, SSE parsing and the hook
// socket protocol end to end.
#include "AgentHub.h"
#include "ChatClient.h"
#include "GitHubClient.h"
#include "Updater.h"
#include "Preferences.h"
#include "PromptRelay.h"
#include "DiscordPresence.h"
#include "PartNames.h"
#include "HookInstaller.h"
#include "HookServer.h"
#include "ModInstaller.h"
#include "QuickAsk.h"

#include <QCryptographicHash>
#include <QJsonArray>
#include <QTcpServer>
#include <QTcpSocket>
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
    void partNamesAreCutToWhatAPersonCallsThem()
    {
        QCOMPARE(shortPartName("AMD Ryzen 5 5600H with Radeon Graphics"), QString("Ryzen 5 5600H"));
        QCOMPARE(shortPartName("12th Gen Intel(R) Core(TM) i7-12700H"), QString("Core i7-12700H"));
        QCOMPARE(shortPartName("Intel(R) Core(TM) i5-9400F CPU @ 2.90GHz"), QString("Core i5-9400F"));
        QCOMPARE(shortPartName("AMD Ryzen 7 5800X 8-Core Processor"), QString("Ryzen 7 5800X"));
        QCOMPARE(shortPartName("Intel(R) Core(TM) Ultra 7 155H"), QString("Core Ultra 7 155H"));
        QCOMPARE(shortPartName("NVIDIA GeForce RTX 3050 Laptop GPU"), QString("RTX 3050 Laptop"));
        QCOMPARE(shortPartName("NVIDIA GeForce GTX 1660 SUPER"), QString("GTX 1660 SUPER"));
        QCOMPARE(shortPartName("AMD Radeon RX 6700 XT"), QString("Radeon RX 6700 XT"));
        QCOMPARE(shortPartName("Intel(R) UHD Graphics 630"), QString("UHD Graphics 630"));
        QCOMPARE(shortPartName("  Some   Odd Chip "), QString("Some Odd Chip"));
        QCOMPARE(shortPartName("AMD"), QString("AMD")); // (nothing left of it: as it came)
    }

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

    void promptsGoOnlyToASessionThatListens()
    {
        QTemporaryDir tmp;
        PromptRelay relay(tmp.path() + "/inbox");
        const QString id = "c8e0e68b-862f-4f24-a042-2e6c86c44fdb";

        // an id is a folder name: nothing that climbs out of the inbox is one
        QVERIFY(!PromptRelay::safeId("../../x"));
        QVERIFY(!PromptRelay::safeId(""));
        QVERIFY(PromptRelay::safeId(id));
        relay.watch("../../x");
        QVERIFY(!QFileInfo::exists(tmp.path() + "/x"));

        // nobody listens yet: nothing is written
        relay.watch(id);
        QVERIFY(QFileInfo(relay.folder(id)).isDir());
        QVERIFY(!relay.send(id, "hello"));
        QCOMPARE(QDir(relay.folder(id)).entryList({"*.prompt"}).size(), 0);

        // the mod's heartbeat appears: the session is live, a prompt is written whole
        { QFile beat(relay.folder(id) + "/alive"); QVERIFY(beat.open(QIODevice::WriteOnly)); beat.write("1"); }
        relay.scan();
        QCOMPARE(relay.live(), QStringList {id});
        QVERIFY(!relay.send(id, "   "));
        QVERIFY(relay.send(id, "  привет, Claude  "));
        const QStringList prompts = QDir(relay.folder(id)).entryList({"*.prompt"});
        QCOMPARE(prompts.size(), 1);
        { QFile f(relay.folder(id) + "/" + prompts[0]); QVERIFY(f.open(QIODevice::ReadOnly)); QCOMPARE(QString::fromUtf8(f.readAll()), QString("привет, Claude")); }
        QCOMPARE(relay.waiting(), QStringList {id});

        // the mod leaves its receipt: both files go, and Kisel says so once
        QSignalSpy took(&relay, &PromptRelay::taken);
        { QFile r(relay.folder(id) + "/" + QFileInfo(prompts[0]).completeBaseName() + ".taken"); QVERIFY(r.open(QIODevice::WriteOnly)); }
        relay.scan();
        QCOMPARE(took.count(), 1);
        QCOMPARE(QDir(relay.folder(id)).entryList({"*.prompt", "*.taken"}).size(), 0);
        QVERIFY(relay.waiting().isEmpty());
    }

    void discordShowsTheStateAndNothingElse()
    {
        QVERIFY(DiscordPresence::activity("", "repo", 5, false).isEmpty()); // no session: nothing
        const QJsonObject work = DiscordPresence::activity("work", "", 1700000000, false);
        QCOMPARE(work.value("details").toString(), QString("Working with Claude Code"));
        QVERIFY(!work.contains("state")); // the project's name only when asked for
        QCOMPARE(work.value("timestamps").toObject().value("start").toDouble(), 1700000000.0);
        QCOMPARE(DiscordPresence::activity("think", "", 1, false).value("details"), work.value("details"));
        QCOMPARE(DiscordPresence::activity("alert", "", 1, false).value("details").toString(), QString("Claude is waiting for an answer"));
        QCOMPARE(DiscordPresence::activity("done", "invoice-app", 1, false).value("state").toString(), QString("invoice-app"));
        QVERIFY(!DiscordPresence::activity("work", "x", 1, false).contains("state")); // (too short for Discord)
        QVERIFY(DiscordPresence::activity("work", "", 1, true).value("details").toString() != work.value("details").toString());

        QVERIFY(DiscordPresence::validId("1234567890123456789"));
        QVERIFY(!DiscordPresence::validId(""));
        QVERIFY(!DiscordPresence::validId("12345"));
        QVERIFY(!DiscordPresence::validId("12345678901234567x"));

        // frames: op, length, json; a frame cut short waits for the rest
        QByteArray wire = DiscordPresence::frame(1, QJsonObject {{"evt", "READY"}}) + DiscordPresence::frame(3, QJsonObject {});
        QByteArray part = wire.left(10);
        int op = -1;
        QJsonObject body;
        QVERIFY(!DiscordPresence::unframe(part, op, body));
        QVERIFY(DiscordPresence::unframe(wire, op, body));
        QCOMPARE(op, 1);
        QCOMPARE(body.value("evt").toString(), QString("READY"));
        QVERIFY(DiscordPresence::unframe(wire, op, body));
        QCOMPARE(op, 3);
        QVERIFY(wire.isEmpty());
        QByteArray junk(12, char(0xff));
        QVERIFY(!DiscordPresence::unframe(junk, op, body));
        QVERIFY(junk.isEmpty());
    }

    void modsAreCountedFromClaudesOwnList()
    {
        auto entry = [](const QString &id, bool on) { return QJsonObject {{"id", id}, {"enabled", on}, {"scope", "user"}}; };
        auto list = [](const QJsonArray &a) { return QJsonDocument(a).toJson(); };
        QCOMPARE(ModInstaller::stateFromList("No plugins installed."), QString("none"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("other@elsewhere", true)})), QString("none"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("kisel-prompts@kisel", false)})), QString("none"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("kisel-prompts@kisel", true)})), QString("installed"));
        // an older copy than this Kisel carries: there, but to be updated
        auto versioned = [](const QString &id, const QString &v) { return QJsonObject {{"id", id}, {"enabled", true}, {"version", v}}; };
        const QHash<QString, QString> shipped {{"kisel-prompts", "0.1.1"}};
        QCOMPARE(ModInstaller::stateFromList(list({versioned("kisel-prompts@kisel", "0.1.0")}), shipped), QString("outdated"));
        QCOMPARE(ModInstaller::stateFromList(list({versioned("kisel-prompts@kisel", "0.1.1")}), shipped), QString("installed"));
        // (a warning line printed before the list does not hide it)
        QCOMPARE(ModInstaller::stateFromList("note: something\n" + list({entry("kisel-prompts@kisel", true)})), QString("installed"));
        // the plugin Kisel installed once and ships no more: found in the list by Kisel's own mark, and only by that
        QCOMPARE(ModInstaller::names(), QStringList {"kisel-prompts"});
        QCOMPARE(ModInstaller::retiredIn(list({entry("kisel-prompts@kisel", true), entry("cache-band@kisel", true)})), QStringList {"cache-band"});
        QCOMPARE(ModInstaller::retiredIn(list({entry("cache-band@kisel", false)})), QStringList {"cache-band"});
        QVERIFY(ModInstaller::retiredIn(list({entry("kisel-prompts@kisel", true), entry("cache-band@elsewhere", true)})).isEmpty());
        QVERIFY(ModInstaller::retiredIn("No plugins installed.").isEmpty());
    }

    void aSessionIsFoundUnderTheNameItsModUses()
    {
        // hooks call it "first", its mod beats as "second": Kisel was told only of "first"
        QTemporaryDir tmp;
        PromptRelay relay(tmp.path() + "/inbox");
        relay.watch("first");
        QCOMPARE(relay.best("first"), QString("first")); // nobody listens: as asked
        QVERIFY(QDir().mkpath(relay.folder("second")));
        { QFile f(relay.folder("second") + "/alive"); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("1"); }
        QVERIFY(QDir().mkpath(relay.folder("../bad name")));
        relay.scan();
        QCOMPARE(relay.live(), QStringList {"second"});
        QCOMPARE(relay.best("first"), QString("second"));
        QCOMPARE(relay.best(""), QString("second"));
        QVERIFY(relay.send(relay.best("first"), "hello"));
        // its own mod listening: that one, whoever else is
        { QFile f(relay.folder("first") + "/alive"); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("1"); }
        relay.scan();
        QCOMPARE(relay.best("first"), QString("first"));
    }

    void aQuickQuestionGoesOutBareAndComesBackAsText()
    {
        // only the web for tools, none of the user's hooks or plugins, nothing saved; a model only by a known alias
        const QStringList a = QuickAsk::arguments("haiku");
        QVERIFY(a.contains("-p") && a.contains("--no-session-persistence") && a.contains("--strict-mcp-config"));
        QCOMPARE(a.at(a.indexOf("--tools") + 1), QString("WebSearch,WebFetch")); // (the web, and nothing that touches the computer)
        QCOMPARE(a.at(a.indexOf("--allowedTools") + 1), QString("WebSearch,WebFetch"));
        QCOMPARE(a.at(a.indexOf("--setting-sources") + 1), QString("project,local"));
        QCOMPARE(a.at(a.indexOf("--model") + 1), QString("haiku"));
        QVERIFY(!QuickAsk::arguments("").contains("--model"));
        QVERIFY(!QuickAsk::arguments("x & calc").contains("--model"));
        const QStringList e = QuickAsk::arguments("", "medium");
        QCOMPARE(e.at(e.indexOf("--effort") + 1), QString("medium"));
        QVERIFY(!QuickAsk::arguments("opus", "").contains("--effort"));
        QVERIFY(!QuickAsk::arguments("opus", "very").contains("--effort"));

        // the talk so far goes along as text
        QCOMPARE(QuickAsk::compose({}, "  why?  "), QString("why?"));
        const QString p = QuickAsk::compose({QVariantMap {{"role", "user"}, {"text", "one"}}, QVariantMap {{"role", "assistant"}, {"text", "two"}}}, "three");
        QVERIFY(p.contains("User: one") && p.contains("You: two") && p.endsWith("three"));

        QString answer, error;
        QVERIFY(QuickAsk::parse(R"(warning line
{"type":"result","is_error":false,"result":" forty-two "})", &answer, &error));
        QCOMPARE(answer, QString("forty-two"));
        QVERIFY(!QuickAsk::parse(R"({"is_error":true,"result":"Not logged in · Please run /login"})", &answer, &error));
        QCOMPARE(error, QString("login"));
        QVERIFY(!QuickAsk::parse("nothing of the kind", &answer, &error));
        // ...and as it is written, a line at a time
        QVERIFY(a.contains("stream-json") && a.contains("--include-partial-messages"));
        QString delta, got, why;
        bool look = false;
        QVERIFY(!QuickAsk::feed(R"({"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}}})", &delta, &look, &got, &why));
        QCOMPARE(delta, QString("Hel"));
        QVERIFY(!look);
        delta.clear();
        QVERIFY(!QuickAsk::feed(R"({"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"server_tool_use","name":"web_search"}}})", &delta, &look, &got, &why));
        QVERIFY(look && delta.isEmpty());
        QVERIFY(!QuickAsk::feed(R"({"type":"system","subtype":"init"})", &delta, &look, &got, &why));
        QVERIFY(QuickAsk::feed(R"({"type":"result","is_error":false,"result":"Hello"})", &delta, &look, &got, &why));
        QCOMPARE(got, QString("Hello"));
        got.clear();
        QVERIFY(QuickAsk::feed(R"({"type":"result","is_error":true,"result":"Not logged in"})", &delta, &look, &got, &why));
        QVERIFY(got.isEmpty());
        QCOMPARE(why, QString("login"));
        QVERIFY(!QuickAsk::parse(R"({"is_error":true,"result":"Rate limited"})", &answer, &error));
        QCOMPARE(error, QString("Rate limited"));
    }

    void theChatIsKeptByProject()
    {
        QTemporaryDir tmp;
        const QString a = "C:/work/kisel", b = "C:/work/other";
        {
            PromptRelay relay(tmp.path() + "/inbox");
            QVERIFY(relay.history(a).isEmpty());
            relay.remember(a, "user", "first");
            relay.remember(a, "assistant", "second");
            relay.remember(b, "user", "elsewhere");
            relay.remember(a, "nobody", "not a speaker");
            relay.remember(a, "user", "   ");
            relay.remember("", "user", "no key");
        }
        PromptRelay again(tmp.path() + "/inbox"); // (after a restart)
        const QVariantList h = again.history(a);
        QCOMPARE(h.size(), 2);
        QCOMPARE(h[0].toMap().value("role").toString(), QString("user"));
        QCOMPARE(h[1].toMap().value("text").toString(), QString("second"));
        QCOMPARE(again.history(b).size(), 1);
        QVERIFY(!QFileInfo::exists(tmp.path() + "/inbox/C:"));
        for (int i = 0; i < 220; ++i)
            again.remember(b, "user", QString::number(i));
        QCOMPARE(again.history(b).size(), 200); // (the last two hundred)
        QCOMPARE(again.history(b).last().toMap().value("text").toString(), QString("219"));
        // a long line is cut, and the whole stays small on disk
        again.remember(a, "assistant", QString(20000, 'x'));
        QVERIFY(again.history(a).last().toMap().value("text").toString().size() <= 4001);
        qint64 bytes = 0;
        for (const QFileInfo &f : QDir(tmp.path() + "/history").entryInfoList(QDir::Files))
            bytes += f.size();
        QVERIFY(bytes < 16 * 1024);
        again.forget(a);
        QVERIFY(again.history(a).isEmpty());
        // a session that has gone into a subfolder still talks in its project's talk
        again.remember("C:/work/kisel", "user", "at the top");
        QCOMPARE(again.home("C:/work/kisel/src/core"), QString("C:/work/kisel"));
        QCOMPARE(again.home("C:/work/kisel"), QString("C:/work/kisel"));
        QCOMPARE(again.home("C:/elsewhere/app"), QString("C:/elsewhere/app"));
        again.remember("C:\\win\\proj", "user", "x");
        QCOMPARE(again.home("C:\\win\\proj\\sub"), QString("C:\\win\\proj"));
    }

    void repliesComeBackOnceAndInOrder()
    {
        QTemporaryDir tmp;
        PromptRelay relay(tmp.path() + "/inbox");
        const QString id = "abc";
        relay.watch(id);
        auto put = [&](const QString &name, const QByteArray &text) { QFile f(relay.folder(id) + "/" + name); QVERIFY(f.open(QIODevice::WriteOnly)); f.write(text); };
        put("1700000000002-1.reply", "second");
        put("1700000000001-0.reply", QString("первый").toUtf8());
        put("1700000000003-2.reply", "   ");
        QSignalSpy said(&relay, &PromptRelay::reply);
        relay.scan();
        QCOMPARE(said.count(), 2);
        QCOMPARE(said[0][1].toString(), QString("первый"));
        QCOMPARE(said[1][1].toString(), QString("second"));
        QCOMPARE(QDir(relay.folder(id)).entryList({"*.reply"}).size(), 0);
        relay.scan();
        QCOMPARE(said.count(), 2); // (not twice)
    }

    void limitsFromTheModAreReadWithCare()
    {
        const QJsonObject five {{"kind", "five_hour"}, {"used", 23.5}, {"resetsAt", "2026-10-08T23:00:00Z"}};
        const QJsonObject week {{"kind", "seven_day"}, {"used", 140}};
        const QJsonObject nameless {{"kind", ""}, {"used", 5}};
        const QJsonObject odd {{"kind", "odd"}, {"used", "lots"}};
        const QJsonObject all {{"limits", QJsonArray {five, week, nameless, odd}}, {"context", QJsonObject {{"used", 61}}}};
        const QVariantList l = PromptRelay::parseLimits(QJsonDocument(all).toJson());
        QCOMPARE(l.size(), 3);
        QCOMPARE(l[0].toMap().value("kind").toString(), QString("five_hour"));
        QCOMPARE(l[0].toMap().value("used").toDouble(), 23.5);
        QCOMPARE(l[1].toMap().value("used").toDouble(), 100.0); // (never past the ring)
        QCOMPARE(l[2].toMap().value("kind").toString(), QString("context"));
        QVERIFY(PromptRelay::parseLimits("not json").isEmpty());
        QCOMPARE(PromptRelay::parseModel(QJsonDocument(QJsonObject {{"model", "claude-opus-5-5[1m]"}}).toJson()), QString("claude-opus-5-5[1m]"));
        QVERIFY(PromptRelay::parseModel(QJsonDocument(QJsonObject {{"model", "<b>x</b>"}}).toJson()).isEmpty());
        QVERIFY(PromptRelay::parseModel(QJsonDocument(QJsonObject {{"model", 5}}).toJson()).isEmpty());

        QTemporaryDir tmp;
        PromptRelay relay(tmp.path() + "/inbox");
        const QString id = "abc";
        relay.watch(id);
        QVERIFY(relay.limits(id).isEmpty());
        { QFile f(relay.folder(id) + "/limits"); QVERIFY(f.open(QIODevice::WriteOnly)); f.write(QJsonDocument(QJsonObject {{"limits", QJsonArray {five}}}).toJson()); }
        QSignalSpy moved(&relay, &PromptRelay::changed);
        relay.scan();
        QCOMPARE(moved.count(), 1);
        QCOMPARE(relay.limits(id).size(), 1);
    }

    void healthTellsMissingFromStaleFromWhole()
    {
        const QString cmd = "/home/u/.local/share/kisel/bin/kisel-hook";
        const QJsonObject user {{"model", "x"}};
        QCOMPARE(HookInstaller::health(user, cmd), QString("none"));

        const QJsonObject whole = HookInstaller::merge(user, cmd, true);
        QCOMPARE(HookInstaller::health(whole, cmd), QString("ok"));

        // the relay moved (an update, a new install folder): same file name, other path
        QCOMPARE(HookInstaller::health(whole, "/elsewhere/kisel-hook"), QString("stale"));

        // an event lost its entry
        QJsonObject partial = whole;
        QJsonObject hooks = partial["hooks"].toObject();
        hooks.remove("Stop");
        partial["hooks"] = hooks;
        QCOMPARE(HookInstaller::health(partial, cmd), QString("stale"));

        // the user's own hooks alone are not ours
        const QJsonObject userHook {{"matcher", "Bash"}, {"hooks", QJsonArray {QJsonObject {{"type", "command"}, {"command", "/usr/bin/my-linter"}}}}};
        QCOMPARE(HookInstaller::health({{"hooks", QJsonObject {{"PreToolUse", QJsonArray {userHook}}}}}, cmd), QString("none"));

        // repairing a stale file is what install does, and it leaves a whole one
        QCOMPARE(HookInstaller::health(HookInstaller::merge(partial, cmd, true), cmd), QString("ok"));
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

    void updaterPicksTheNewestWindowsRelease()
    {
        const auto asset = [](const QString &name, int n, int size, const QString &digest = {}) {
            QJsonObject a {{"name", name}, {"url", QStringLiteral("https://api.github.com/x/%1").arg(n)}, {"size", size}};
            if (!digest.isEmpty())
                a["digest"] = digest;
            return a;
        };
        const auto release = [](const QString &tag, bool draft, const QJsonArray &assets) {
            return QJsonObject {{"tag_name", tag}, {"draft", draft}, {"assets", assets}};
        };
        const QByteArray body = QJsonDocument(QJsonArray {
            release("v9.0.0", false, {asset("kisel.tar.gz", 1, 5)}),
            release("win-v0.9.3", false, {asset("KiselSetup-0.9.3.exe", 2, 10)}),
            release("win-v0.10.0", false, {asset("notes.txt", 3, 1), asset("KiselSetup-0.10.0.exe", 4, 20, "sha256:ABCDEF")}),
            release("win-v0.11.0", true, {asset("KiselSetup-0.11.0.exe", 5, 30)}),
            release("win-v0.12.0", false, {}),
        }).toJson();
        Updater::Release r;
        QString err;
        QVERIFY(Updater::pick(body, &r, &err));
        QCOMPARE(r.version, QStringLiteral("0.10.0"));
        QCOMPARE(r.asset, QUrl(QStringLiteral("https://api.github.com/x/4")));
        QCOMPARE(r.size, 20);
        QCOMPARE(r.sha256, QByteArray("abcdef"));
        QVERIFY(Updater::compare(QStringLiteral("0.10.0"), QStringLiteral("0.9.3")) > 0);
        QVERIFY(Updater::compare(QStringLiteral("0.2"), QStringLiteral("0.2.0")) == 0);
        QVERIFY(!Updater::pick(QJsonDocument(QJsonObject {{"message", "Not Found"}}).toJson(), &r, &err));
        QCOMPARE(err, QStringLiteral("Not Found"));
        QVERIFY(!Updater::pick("[]", &r, &err));
    }
    // The whole way, against a little server that answers as GitHub does: the list of
    // releases, the redirect from the API to where the file is, the file. The installer is
    // not started: what would have been started is looked at instead.
    void updaterDownloadsChecksAndHandsOver()
    {
        const QByteArray file = QByteArray(300000, 'k') + "the end";
        const QByteArray sum = QCryptographicHash::hash(file, QCryptographicHash::Sha256).toHex();
        for (const bool honest : {true, false}) {
            QTcpServer server;
            QVERIFY(server.listen(QHostAddress::LocalHost));
            const QString base = QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort());
            QStringList asked;
            connect(&server, &QTcpServer::newConnection, &server, [&] {
                QTcpSocket *s = server.nextPendingConnection();
                connect(s, &QTcpSocket::readyRead, s, [&, s] {
                    if (!s->canReadLine())
                        return;
                    const QString path = QString::fromLatin1(s->readLine()).section(' ', 1, 1);
                    asked << path;
                    QByteArray body, head = "HTTP/1.1 200 OK\r\n";
                    if (path == "/releases") {
                        body = QJsonDocument(QJsonArray {QJsonObject {{"tag_name", "win-v9.9.9"}, {"draft", false}, {"assets", QJsonArray {QJsonObject {
                            {"name", "KiselSetup-9.9.9.exe"}, {"url", base + "/asset"}, {"size", file.size()},
                            {"digest", "sha256:" + QString::fromLatin1(honest ? sum : QByteArray(64, '0'))}}}}}}).toJson();
                    } else if (path == "/asset") {
                        head = "HTTP/1.1 302 Found\r\nLocation: " + base.toLatin1() + "/file\r\n";
                    } else {
                        body = file;
                    }
                    s->write(head + "Content-Length: " + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body);
                    s->disconnectFromHost();
                });
            });
            qputenv("KISEL_VERSION_AS", "0.0.1");
            Updater up(nullptr);
            up.setApi(QUrl(base + "/releases"));
            QString started;
            QStringList args;
            up.setLauncher([&](const QString &p, const QStringList &a) { started = p; args = a; return true; });
            up.check();
            QTRY_COMPARE(up.state(), QStringLiteral("found"));
            QCOMPARE(up.latest(), QStringLiteral("9.9.9"));
            up.update();
            QTRY_VERIFY(up.state() == QLatin1String("starting") || up.state() == QLatin1String("failed"));
            QCOMPARE(asked, (QStringList {"/releases", "/asset", "/file"}));
            if (honest) {
                QCOMPARE(up.state(), QStringLiteral("starting"));
                QVERIFY(args.contains(QStringLiteral("/SILENT")));
                QFile got(started);
                QVERIFY(got.open(QIODevice::ReadOnly));
                QCOMPARE(got.readAll(), file);
                got.remove();
            } else { // (the sum does not match what the release says: nothing is started, nothing is kept)
                QCOMPARE(up.state(), QStringLiteral("failed"));
                QVERIFY(started.isEmpty());
                QVERIFY(!QFile::exists(QDir::tempPath() + "/KiselSetup-9.9.9.exe"));
            }
            qunsetenv("KISEL_VERSION_AS");
        }
    }
    // What is set in Settings is in the file the moment it is set: a second reader, with
    // the first still alive (as when Kisel is killed, or the computer goes down), sees it.
    void preferencesAreOnDiskAtOnce()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        qputenv("KISEL_CONFIG_DIR", dir.path().toLocal8Bit());
        {
            Preferences a;
            a.setCharacter(QStringLiteral("teto"));
            a.setSoundOn(false);
            a.setCloseDelay(7);
            a.setLanguage(QStringLiteral("ru"));
            a.setScreenName(QStringLiteral("\\\\.\\DISPLAY2"));
            a.setDock(QStringLiteral("\\\\.\\DISPLAY2"), QStringLiteral("left"), 0.25);
            Preferences b; // (opened while `a` has not been closed)
            QCOMPARE(b.character(), QStringLiteral("teto"));
            QCOMPARE(b.soundOn(), false);
            QCOMPARE(b.closeDelay(), 7);
            QCOMPARE(b.language(), QStringLiteral("ru"));
            QCOMPARE(b.screenName(), QStringLiteral("\\\\.\\DISPLAY2"));
            QCOMPARE(b.dockEdge(QStringLiteral("\\\\.\\DISPLAY2")), QStringLiteral("left"));
            QCOMPARE(b.dockFraction(QStringLiteral("\\\\.\\DISPLAY2")), 0.25);
            // a monitor with no place of its own takes the last one
            QCOMPARE(b.dockEdge(QStringLiteral("another")), QStringLiteral("left"));
        }
        qunsetenv("KISEL_CONFIG_DIR");
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
