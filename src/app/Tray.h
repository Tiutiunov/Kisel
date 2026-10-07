#pragma once

#include <QObject>

class QAction;

namespace kisel {

// Tray icon (StatusNotifierItem: native on Plasma; QSystemTrayIcon elsewhere). The island is the whole UI;
// the tray only offers Open, Settings, Pause and Quit.
class Tray : public QObject
{
    Q_OBJECT
public:
    explicit Tray(QObject *parent = nullptr);
    void setRussian(bool on); // the menu's language

private:
    QAction *m_open = nullptr, *m_settings = nullptr, *m_quit = nullptr;

signals:
    void openRequested();
    void settingsRequested();
    void quitRequested();
};

} // namespace kisel
