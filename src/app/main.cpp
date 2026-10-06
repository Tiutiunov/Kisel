#include "AgentHub.h"
#include "Displays.h"
#include "GitHubClient.h"
#include "ChatClient.h"
#include "HookInstaller.h"
#include "IslandWindow.h"
#include "Launcher.h"
#include "Paths.h"
#include "Preferences.h"
#include "Secrets.h"
#include "Sounds.h"
#include "Tray.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QJsonArray>
#include <QJsonObject>
#include <QLocalSocket>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
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
    if (qEnvironmentVariableIntValue("KISEL_DEMO_DONE") > 0)
        ev(qEnvironmentVariableIntValue("KISEL_DEMO_DONE"), base("Stop"));
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
    cli.addOption({"grab", "Save a screenshot of the island to <file> and quit (development).", "file"});
    cli.process(app);

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
    hooks.ensureRelay(QCoreApplication::applicationDirPath() + QStringLiteral("/" KISEL_HOOK_BASENAME));

    // A grab run must never take over the real socket.
    const QString socket = cli.isSet("grab") ? QStringLiteral("/tmp/kisel-grab-%1.sock").arg(getpid()) : paths::socketPath();
    if (!hub.start(socket))
        qWarning("Could not listen on %s; hooks will not reach Kisel.", qPrintable(socket));

    QQuickView view;
    IslandWindow shell(&view);
    Displays displays(&shell, &prefs);
    Sounds sounds(&prefs);
    Launcher launcher;
    GitHubClient github(&secrets);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Hub", &hub);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Prefs", &prefs);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Hooks", &hooks);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Chat", &chat);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Vault", &secrets);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Shell", &shell);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Displays", &displays);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Sounds", &sounds);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "Launcher", &launcher);
    qmlRegisterSingletonInstance("Kisel.Core", 1, 0, "GitHub", &github);

    view.loadFromModule("Kisel", "Main");
    if (view.status() != QQuickView::Ready)
        return 1;
    QQuickItem *root = view.rootObject();
    QObject::connect(&shell, &IslandWindow::quitRequested, &app, &QApplication::quit);
    displays.applyInitial();
    shell.show();

    Tray tray;
    QObject::connect(&tray, &Tray::openRequested, root, [root] { QMetaObject::invokeMethod(root, "openIsland", Q_ARG(QVariant, "home")); });
    QObject::connect(&tray, &Tray::settingsRequested, root, [root] { QMetaObject::invokeMethod(root, "openIsland", Q_ARG(QVariant, "settings")); });
    QObject::connect(&tray, &Tray::quitRequested, &app, &QApplication::quit);

    if (cli.isSet("demo") || cli.isSet("grab"))
        runDemo(hub);
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
