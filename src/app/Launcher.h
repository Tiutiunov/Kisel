#pragma once

#include <QObject>
#include <QString>

namespace kisel {

// What the launch tiles do. Everything is detached: closing Kisel never
// closes a terminal or a file manager it opened.
class Launcher : public QObject
{
    Q_OBJECT
public:
    explicit Launcher(QObject *parent = nullptr) : QObject(parent) {}

    // A terminal in `dir` (the current session's folder; empty = home).
    // Konsole on Plasma, then whatever the system names as the default.
    Q_INVOKABLE bool openTerminal(const QString &dir);
    // The folder in the default file manager (Dolphin on Plasma).
    Q_INVOKABLE bool openFiles(const QString &dir);
    // Only https links, e.g. a pull request page.
    Q_INVOKABLE bool openUrl(const QString &url);

    static QString existingDir(const QString &dir);
};

} // namespace kisel
