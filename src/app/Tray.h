#pragma once

#include <QObject>

namespace kisel {

// Tray icon (StatusNotifierItem: native on Plasma). The island is the whole UI;
// the tray only offers Open, Settings, Pause and Quit.
class Tray : public QObject
{
    Q_OBJECT
public:
    explicit Tray(QObject *parent = nullptr);

signals:
    void openRequested();
    void settingsRequested();
    void quitRequested();
};

} // namespace kisel
