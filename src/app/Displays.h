#pragma once

#include <QObject>
#include <QVariantList>

class QScreen;

namespace kisel {

class IslandWindow;
class Preferences;

// Which monitor the island lives on. The choice is remembered by the output's
// name (DP-1, HDMI-A-1...), so it survives restarts, and if that monitor is
// unplugged Kisel falls back to the primary one and returns when it is back.
class Displays : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList screens READ screens NOTIFY changed)
    Q_PROPERTY(QString current READ current NOTIFY changed) // output the island is on now
    Q_PROPERTY(QString wanted READ wanted NOTIFY changed)   // "" = whichever is primary

public:
    Displays(IslandWindow *window, Preferences *prefs, QObject *parent = nullptr);

    // [{name, label, x, y, w, h, primary}] in compositor coordinates
    QVariantList screens() const;
    QString current() const;
    QString wanted() const;

    Q_INVOKABLE void select(const QString &name); // "" = primary
    // Put the window where it belongs; call before the first show().
    void applyInitial();

signals:
    void changed();
    void moved(); // the island arrived on a different monitor: time to celebrate

private:
    QScreen *target() const;
    void reconcile();

    IslandWindow *m_window;
    Preferences *m_prefs;
};

} // namespace kisel
