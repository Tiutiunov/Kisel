#include "AgentHub.h"
#include "Displays.h"
#include "GitHubClient.h"
#include "Updater.h"
#include "ChatClient.h"
#include "HookInstaller.h"
#include "IslandWindow.h"
#include "Launcher.h"
#include "Media.h"
#include "NetMon.h"
#include "Notices.h"
#include "SysMon.h"
#include "Paths.h"
#include "Preferences.h"
#include "Secrets.h"
#include "SeamWindows.h"
#include "Sounds.h"
#include "Ticker.h"
#include "Tray.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QJsonArray>
#include <QJsonObject>
#include <QLocalSocket>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QMouseEvent>
#include <QtTest/QTest>
#include <QQuickView>
#include <QTimer>
#include <qqml.h>

using namespace kisel;

namespace {

// `kisel --demo` replays a short fake session so the UI can be worked on
// without Claude Code running. It uses the same entry point as the relay.
void runDemo(AgentHub &hub)
{
    auto ev = [&hub](int ms, QJsonObject o) {
        QTimer::singleShot(ms, &hub, [&hub, o] { hub.handle(o); });
    };
    const QString cwd = QStringLiteral("/home/user/projects/invoice-app");
    auto base = [&](const QString &name) {
        return QJsonObject {{"hook_event_name", name}, {"session_id", "demo"}, {"cwd", cwd}};
    };
    auto tool = [&](const QString &name, const QString &t, QJsonObject input) {
        QJsonObject o = base(name);
        o["tool_name"] = t;
        o["tool_input"] = input;
        return o;
    };
    QJsonObject prompt = base("UserPromptSubmit");
    prompt["prompt"] = "Fix the rounding in invoice totals";
    ev(1500, prompt);
    ev(3000, tool("PreToolUse", "Read", {{"file_path", cwd + "/src/invoice.ts"}}));
    ev(4200, tool("PostToolUse", "Read", {}));
    ev(4600, tool("PreToolUse", "Edit",
                  {{"file_path", cwd + "/src/invoice.ts"},
                   {"old_string", "return total / 100;"},
                   {"new_string", "return Math.round(total) / 100;"}}));
    // KISEL_DEMO_DONE=<ms> finishes the task at that time (to see the burst)
    // (and nothing is asked afterwards, so the bar's "Done" can be looked at too)
    if (qEnvironmentVariableIntValue("KISEL_DEMO_DONE") > 0) {
        ev(qEnvironmentVariableIntValue("KISEL_DEMO_DONE"), base("Stop"));
        return;
    }
    // KISEL_DEMO_ASK=1 shows a question instead of a command
    if (!qEnvironmentVariableIsSet("KISEL_DEMO_ASK"))
        ev(6000, tool("PermissionRequest", "Bash", {{"command", "npm test -- invoice"}}));
    else
        ev(6000, tool("PermissionRequest", "AskUserQuestion", {{"questions", QJsonArray {
            QJsonObject {{"question", "Which rounding should invoice totals use?"}, {"header", "Rounding"}, {"multiSelect", false},
                         {"options", QJsonArray {QJsonObject {{"label", "Half up"}}, QJsonObject {{"label", "Bankers"}}, QJsonObject {{"label", "Always down"}}}}},
            QJsonObject {{"question", "Where should it apply?"}, {"header", "Scope"}, {"multiSelect", true},
                         {"options", QJsonArray {QJsonObject {{"label", "Line items"}}, QJsonObject {{"label", "Tax"}}, QJsonObject {{"label", "Total"}}}}}}}}));
}

} // namespace

int main(int argc, char *argv[])
{
    IslandWindow::preInit();
    QQuickStyle::setStyle(QStringLiteral("Basic")); // fully custom look: no Breeze controls
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kisel"));
    app.setOrganizationName(QStringLiteral("kisel"));
    app.setApplicationVersion(QStringLiteral(KISEL_VERSION));
    app.setDesktopFileName(QStringLiteral("kisel"));
    app.setQuitOnLastWindowClosed(false);

    QCommandLineParser cli;
    cli.addHelpOption();
    cli.addVersionOption();
    cli.addOption({"demo", "Replay a fake Claude Code session."});
    cli.addOption({"open", "Open the island on a view (home, session, permission, chat, settings).", "view"});
    cli.addOption({"grab-test", "Development: enter the full-output drag surface and print its size."});
    cli.addOption({"toast-test", "Development: show a toast shortly after start."});
    cli.addOption({"dock-edge", "Development: dock on <edge>[:fraction] right after start (top, bottom, left, right).", "edge"});
    cli.addOption({"drag-test", "Development: pick up the mascot, carry it to <edge> and let go; prints the state.", "edge"});
    cli.addOption({"intro", "Play the first-launch animation now."});
    cli.addOption({"grab", "Save a screenshot of the island to <file> and quit (development).", "file"});
    cli.addOption({"scroll", "Development: with --grab, scroll Settings down by <px> first.", "px"});
    cli.addOption({"check-updates", "Ask GitHub whether a newer version is out, print the answer and quit."});
    cli.addOption({"remove-hooks", "Take Kisel's hooks out of Claude Code's settings and quit (the uninstaller does this)."});
    cli.process(app);

    if (cli.isSet("remove-hooks")) { // (through HookInstaller, as Settings does it: dated backup, atomic write)
        HookInstaller hooks;
        return hooks.apply(false) ? 0 : 1;
    }

    if (cli.isSet("check-updates")) {
        Secrets secrets;
        Updater up(&secrets);
        QObject::connect(&up, &Updater::changed, &app, [&] {
            if (up.state() == QLatin1String("checking"))
                return;
            qInfo("Kisel %s: %s %s%s", qPrintable(up.current()), qPrintable(up.state()), qPrintable(up.latest()), qPrintable(up.error()));
            app.exit(up.state() == QLatin1String("failed") ? 1 : 0);
        });
        up.check();
        return app.exec();
    }

    // One instance: if somebody already answers on the socket, that is Kisel.
    if (!cli.isSet("grab")) {
        QLocalSocket probe;
        probe.connectToServer(paths::socketPath());
        if (probe.waitForConnected(150)) {
            qInfo("Kisel is already running.");
            return 0;
        }
    }

    Preferences prefs;
    Secrets secrets;
    AgentHub hub(&prefs);
    HookInstaller hooks;
    ChatClient chat(&prefs, &secrets);

    // The relay ships next to the app; hooks point at a stable copy in the data dir.
    hooks.ensureRelay(QCoreApplication::applicationDirPath() + QLatin1Char('/') + paths::hookFileName());

    // A grab run must never take over the real socket.
    const QString socket = cli.isSet("grab") ? paths::scratchSocketPath(QCoreApplication::applicationPid()) : paths::socketPath();
    if (!hub.start(socket))
        qWarning("Could not listen on %s; hooks will not reach Kisel.", qPrintable(socket));

    // The animations' clock is Kisel's own (see Ticker.h). It goes in before the window
    // exists; a grab is rendered without one, and so is anything but Windows for now.
    Ticker ticker;
#ifdef Q_OS_WIN
    if (!cli.isSet("grab") && !qEnvironmentVariableIsSet("KISEL_NO_TICKER"))
        ticker.install();
#endif

    QQuickView view;
    IslandWindow shell(&view);
    shell.setAvoidPanels(prefs.avoidPanels());
    Displays displays(&shell, &prefs);
    QObject::connect(&prefs, &Preferences::changed, &shell, [&] {
        if (shell.avoidPanels() == prefs.avoidPanels())
            return;
        shell.setAvoidPanels(prefs.avoidPanels());
        if (!shell.floating())
            displays.applyDock(); // the same place along an edge that is now longer or shorter
    });
    Sounds sounds(&prefs);
    Launcher launcher;
    SeamWindows seams;
    GitHubClient github(&secrets);
    Updater updater(&secrets);
    // (A sign-in key for reading the Claude allowance was kept here for one version; the
    // server does not let such a key read it, so the feature is gone and so is the key.)
    if (secrets.has(QStringLiteral("claude-signin")))
        secrets.remove(QStringLiteral("claude-signin"));
    Media media;
    SysMon sysmon;
    Notices notices;
    NetMon netmon;
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Hub", &hub);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Prefs", &prefs);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Hooks", &hooks);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Chat", &chat);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Vault", &secrets);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Shell", &shell);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Displays", &displays);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Sounds", &sounds);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Launcher", &launcher);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Seams", &seams);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "GitHub", &github);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Updates", &updater);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Ticker", &ticker);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Media", &media);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Sys", &sysmon);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Notes", &notices);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Net", &netmon);

    view.loadFromModule("Kisel", "Main");
    if (view.status() != QQuickView::Ready)
        return 1;
    QQuickItem *root = view.rootObject();
    QObject::connect(&shell, &IslandWindow::quitRequested, &app, &QApplication::quit);
    displays.applyInitial();
    shell.show();

    Tray tray;
    const auto trayLanguage = [&] { tray.setRussian(prefs.language() == QLatin1String("ru")); };
    trayLanguage();
    QObject::connect(&prefs, &Preferences::changed, &tray, trayLanguage);

    // Updates: one question to GitHub a little after start and once a day (Settings can
    // switch that off). Nothing is downloaded; if a newer version is out Rin says so.
    const auto askForUpdates = [&] {
        if (updater.available() && prefs.updateCheck() && !cli.isSet("grab"))
            updater.check(true);
    };
    QTimer::singleShot(20000, &app, askForUpdates);
    QTimer daily;
    daily.setInterval(24 * 60 * 60 * 1000);
    QObject::connect(&daily, &QTimer::timeout, &app, askForUpdates);
    daily.start();
    // KISEL_DEMO_UPDATE=<ms>: as if version 9.9.9 came out at that time (development)
    if (const int at = qEnvironmentVariableIntValue("KISEL_DEMO_UPDATE"); at > 0)
        QTimer::singleShot(at, &app, [&] { updater.pretend(QStringLiteral("9.9.9")); });
    QObject::connect(&tray, &Tray::openRequested, root, [root] { QMetaObject::invokeMethod(root, "openIsland", Q_ARG(QVariant, "home")); });
    QObject::connect(&tray, &Tray::settingsRequested, root, [root] { QMetaObject::invokeMethod(root, "openIsland", Q_ARG(QVariant, "settings")); });
    QObject::connect(&tray, &Tray::quitRequested, &app, &QApplication::quit);

    if (cli.isSet("demo") || cli.isSet("grab"))
        runDemo(hub);
    if (cli.isSet("grab-test")) {
        QTimer::singleShot(700, root, [root] { QMetaObject::invokeMethod(root, "devGrab"); });
        QTimer::singleShot(1700, &app, [&view, &shell] {
            qInfo("grab-test: view %dx%d, wide=%d, grabbing=%d", view.width(), view.height(), shell.viewWide(), shell.grabbing());
            shell.endGrab();
        });
        QTimer::singleShot(2700, &app, [&view, &shell] {
            qInfo("grab-test: after release view %dx%d, wide=%d", view.width(), view.height(), shell.viewWide());
            qApp->quit();
        });
    }
    if (cli.isSet("toast-test"))
        QTimer::singleShot(900, root, [root] { QMetaObject::invokeMethod(root, "devToast", Q_ARG(QVariant, QStringLiteral("Kisel moved to HDMI-A-1"))); });
    if (cli.isSet("dock-edge")) {
        const QStringList parts = cli.value("dock-edge").split(':');
        QTimer::singleShot(150, root, [&shell, parts] {
            const QString edge = parts.value(0);
            shell.setDock(edge, parts.value(1, "0.5").toDouble() * shell.edgeLength(edge));
        });
    }
    if (cli.isSet("drag-test")) {
        // Press the mascot, hold 500 ms, carry it toward an edge, let go. Synthetic mouse
        // events through the window, so the same code runs as with a real pointer.
        const QString edge = cli.value("drag-test");
        // QTest goes through the window system interface, like a real pointer does
        auto send = [&view](QEvent::Type type, QPointF pos) {
            const QPoint p = pos.toPoint();
            if (type == QEvent::MouseButtonPress) QTest::mousePress(&view, Qt::LeftButton, {}, p, -1);
            else if (type == QEvent::MouseMove) QTest::mouseMove(&view, p, -1);
            else QTest::mouseRelease(&view, Qt::LeftButton, {}, p, -1);
        };
        auto report = [root](const char *when) {
            QVariant v;
            QMetaObject::invokeMethod(root, "devState", Q_RETURN_ARG(QVariant, v));
            qInfo("drag-test %-9s %s", when, qPrintable(v.toString()));
        };
        auto center = [root]() {
            QVariant v;
            QMetaObject::invokeMethod(root, "devCenter", Q_RETURN_ARG(QVariant, v));
            return v.toPointF();
        };
        QTimer::singleShot(1200, root, [=, &view, &shell] {
            report("start");
            const QPointF c = center();
            send(QEvent::MouseButtonPress, c);
            // 500 ms later the 350 ms hold is complete and the surface is output-sized
            QTimer::singleShot(550, &view, [=, &view, &shell] {
                report("held");
                const qreal W = shell.screenWidth(), H = shell.screenHeight();
                // the target in output coordinates, 12 px from the chosen edge
                QPointF to(W / 2, 12);
                if (edge == "bottom") to = {W / 2, H - 12};
                if (edge == "left") to = {12, H / 2};
                if (edge == "right") to = {W - 12, H / 2};
                if (edge == "float") to = {W / 2 + 90, H / 2};
                const QPointF from = c;
                const int steps = 30;
                for (int i = 1; i <= steps; ++i) {
                    QTimer::singleShot(i * 25, &view, [=, &view] {
                        const QPointF p = from + (to - from) * (qreal(i) / steps);
                        send(QEvent::MouseMove, p);
                    });
                }
                QTimer::singleShot(steps * 25 + 150, &view, [=, &view] {
                    report("carried");
                    send(QEvent::MouseButtonRelease, to);
                });
                QTimer::singleShot(steps * 25 + 1300, &view, [=] { report("dropped"); });
            });
        });
    }
    if (cli.isSet("intro"))
        QTimer::singleShot(300, root, [root] { QMetaObject::invokeMethod(root, "runIntro"); });
    if (cli.isSet("open"))
        QTimer::singleShot(400, root, [root, v = cli.value("open")] { QMetaObject::invokeMethod(root, "openIsland", Q_ARG(QVariant, v)); });
    if (cli.isSet("grab")) {
        QTimer::singleShot(qEnvironmentVariableIntValue("KISEL_GRAB_MS") ? qEnvironmentVariableIntValue("KISEL_GRAB_MS") : 7500, &app, [&view, file = cli.value("grab")] {
            view.grabWindow().save(file);
            qApp->quit();
        });
    }
    return app.exec();
}
