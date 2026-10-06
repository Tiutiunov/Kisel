#include "Launcher.h"

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

namespace kisel {

QString Launcher::existingDir(const QString &dir)
{
    return !dir.isEmpty() && QFileInfo(dir).isDir() ? dir : QDir::homePath();
}

bool Launcher::openTerminal(const QString &dir)
{
    const QString wd = existingDir(dir);
    struct Candidate { const char *exe; QStringList args; };
    const Candidate candidates[] = {
        {"konsole", {QStringLiteral("--workdir"), wd}},
        {"xdg-terminal-exec", {}},
        {"x-terminal-emulator", {}},
    };
    for (const Candidate &c : candidates) {
        const QString exe = QStandardPaths::findExecutable(QString::fromLatin1(c.exe));
        if (!exe.isEmpty())
            return QProcess::startDetached(exe, c.args, wd);
    }
    return false;
}

bool Launcher::openFiles(const QString &dir)
{
    return QDesktopServices::openUrl(QUrl::fromLocalFile(existingDir(dir)));
}

bool Launcher::openUrl(const QString &url)
{
    const QUrl u(url);
    // Never launch anything but a web page: the string may come from an API.
    if (u.scheme() != QLatin1String("https") || u.host().isEmpty())
        return false;
    return QDesktopServices::openUrl(u);
}

} // namespace kisel
