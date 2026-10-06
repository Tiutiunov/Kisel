#pragma once

#include <QObject>
#include <QString>

namespace kisel {

// What the launch tiles open: only web pages (a pull request).
class Launcher : public QObject
{
    Q_OBJECT
public:
    explicit Launcher(QObject *parent = nullptr) : QObject(parent) {}

    // Only https links, e.g. a pull request page.
    Q_INVOKABLE bool openUrl(const QString &url);

};

} // namespace kisel
