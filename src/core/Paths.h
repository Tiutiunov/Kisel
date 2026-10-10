#pragma once
// Every path Kisel and its relay agree on. The relay (hook/main.cpp) repeats
// socketPath() by hand because it must not depend on this library: keep both
// in sync.

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QString>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <sddl.h>
#else
#include <unistd.h>
#endif

namespace kisel::paths {

#ifdef Q_OS_WIN
// The current user's SID as text ("S-1-5-21-..."), empty on failure.
inline QString userSid()
{
    QString out;
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return out;
    BYTE buf[256];
    DWORD len = 0;
    if (GetTokenInformation(token, TokenUser, buf, sizeof buf, &len)) {
        LPWSTR text = nullptr;
        if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER *>(buf)->User.Sid, &text)) {
            out = QString::fromWCharArray(text);
            LocalFree(text);
        }
    }
    CloseHandle(token);
    return out;
}

// \\.\pipe\kisel-<SID>: one pipe per user. QLocalServer's UserAccessOption
// closes it to everyone else, and both ends check the peer's user as well.
inline QString socketPath() { return QStringLiteral("kisel-") + userSid(); }
// A socket of its own for runs that must not take over the real one (--grab).
inline QString scratchSocketPath(qint64 pid) { return QStringLiteral("kisel-grab-%1").arg(pid); }
#else
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
// A socket of its own for runs that must not take over the real one (--grab).
inline QString scratchSocketPath(qint64 pid) { return QStringLiteral("/tmp/kisel-grab-%1.sock").arg(pid); }
#endif

// The file that starts Kisel. Run from an AppImage, the program itself sits in a folder
// that is there only while it runs, under another name each time: what starts Kisel then
// is the AppImage, which says where it is in APPIMAGE.
inline QString appImage()
{
#ifdef Q_OS_LINUX
    const QString file = qEnvironmentVariable("APPIMAGE");
    if (!file.isEmpty() && QFileInfo(file).isFile())
        return file;
#endif
    return {};
}
inline QString selfPath()
{
    const QString image = appImage();
    return image.isEmpty() ? QCoreApplication::applicationFilePath() : image;
}

inline QString dataDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/kisel");
}
// The folder Kisel and its Claude Code mod share (see PromptRelay). On Windows it is in
// the home folder, not under AppData: the Claude desktop app is a packaged app, and
// Windows keeps what such an app (and the Claude Code it runs) writes under AppData in a
// private copy that Kisel never sees. The home folder is the same for both.
// (mods/kisel-prompts/hooks/inbox.ts names the same folder: keep the two in step.)
// (On Plasma it is the same folder for the same reason of keeping the two in step: the
// mod names one place, whatever the system.)
inline QString inboxDir()
{
    return QDir::homePath() + QStringLiteral("/.kisel/inbox");
}
inline QString configDir()
{
    // (development: KISEL_CONFIG_DIR points the settings at a scratch folder, so a trial
    // run can be given any settings without touching the real ones)
    const QByteArray scratch = qgetenv("KISEL_CONFIG_DIR");
    if (!scratch.isEmpty())
        return QString::fromLocal8Bit(scratch);
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kisel");
}
#ifdef Q_OS_WIN
inline QString hookFileName() { return QStringLiteral(KISEL_HOOK_BASENAME ".exe"); }
#else
inline QString hookFileName() { return QStringLiteral(KISEL_HOOK_BASENAME); }
#endif
inline QString hookBinary() { return dataDir() + QStringLiteral("/bin/") + hookFileName(); }
inline QString logFile() { return dataDir() + QStringLiteral("/kisel.log"); }

// Claude Code's user settings. CLAUDE_CONFIG_DIR is honoured like Claude Code does.
inline QString claudeSettings()
{
    const QString dir = qEnvironmentVariable("CLAUDE_CONFIG_DIR", QDir::homePath() + QStringLiteral("/.claude"));
    return dir + QStringLiteral("/settings.json");
}

} // namespace kisel::paths
