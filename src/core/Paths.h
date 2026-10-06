#pragma once
// Every path Kisel and its relay agree on. The relay (hook/main.cpp) repeats
// socketPath() by hand because it must not depend on this library: keep both
// in sync.

#include <QDir>
#include <QStandardPaths>
#include <QString>

#include <unistd.h>

namespace kisel::paths {

inline QString runtimeDir()
{
    const QString d = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!d.isEmpty() && QDir::isAbsolutePath(d))
        return d;
    return QStringLiteral("/run/user/%1").arg(getuid());
}

// $XDG_RUNTIME_DIR/kisel.sock. The directory is 0700 and ours, so nobody else
// can reach it; HookServer also checks SO_PEERCRED on every connection.
inline QString socketPath() { return runtimeDir() + QStringLiteral("/kisel.sock"); }

inline QString dataDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/kisel");
}
inline QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kisel");
}
inline QString hookBinary() { return dataDir() + QStringLiteral("/bin/" KISEL_HOOK_BASENAME); }
inline QString logFile() { return dataDir() + QStringLiteral("/kisel.log"); }

// Claude Code's user settings. CLAUDE_CONFIG_DIR is honoured like Claude Code does.
inline QString claudeSettings()
{
    const QString dir = qEnvironmentVariable("CLAUDE_CONFIG_DIR", QDir::homePath() + QStringLiteral("/.claude"));
    return dir + QStringLiteral("/settings.json");
}

} // namespace kisel::paths
