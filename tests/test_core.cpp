// Unit tests for the parts that carry risk: permission summaries, "Always"
// rule keys, settings.json merging, the line diff, SSE parsing and the hook
// socket protocol end to end.
#include "AgentHub.h"
#include "ChatClient.h"
#include "GitHubClient.h"
#include "Updater.h"
#include "Preferences.h"
#include "PromptRelay.h"
#include "HookInstaller.h"
#include "HookServer.h"
#include "ModInstaller.h"

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

    void modsAreCountedFromClaudesOwnList()
    {
        auto entry = [](const QString &id, bool on) { return QJsonObject {{"id", id}, {"enabled", on}, {"scope", "user"}}; };
        auto list = [](const QJsonArray &a) { return QJsonDocument(a).toJson(); };
        QCOMPARE(ModInstaller::stateFromList("No plugins installed."), QString("none"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("other@elsewhere", true)})), QString("none"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("kisel-prompts@kisel", true)})), QString("partial"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("kisel-prompts@kisel", true), entry("cache-band@kisel", false)})), QString("partial"));
        QCOMPARE(ModInstaller::stateFromList(list({entry("kisel-prompts@kisel", true), entry("cache-band@kisel", true)})), QString("installed"));
        // an older copy than this Kisel carries: both there, but to be updated
        auto versioned = [](const QString &id, const QString &v) { return QJsonObject {{"id", id}, {"enabled", true}, {"version", v}}; };
        const QHash<QString, QString> shipped {{"kisel-prompts", "0.1.1"}, {"cache-band", "0.1.0"}};
        QCOMPARE(ModInstaller::stateFromList(list({versioned("kisel-prompts@kisel", "0.1.0"), versioned("cache-band@kisel", "0.1.0")}), shipped), QString("outdated"));
        QCOMPARE(ModInstaller::stateFromList(list({versioned("kisel-prompts@kisel", "0.1.1"), versioned("cache-band@kisel", "0.1.0")}), shipped), QString("installed"));
        // (a warning line printed before the list does not hide it)
        QCOMPARE(ModInstaller::stateFromList("note: something\n" + list({entry("kisel-prompts@kisel", true), entry("cache-band@kisel", true)})), QString("installed"));
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
