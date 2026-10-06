#pragma once

#include <QObject>
#include <QVariantList>

class QScreen;

namespace kisel {

class IslandWindow;
class Preferences;

// Which monitor the island lives on. By default it follows the primary monitor.
// A monitor picked in Settings (by output name: DP-1, HDMI-A-1...) holds for the
// running session: if it is unplugged Kisel falls back to the primary one and
// returns when it is back, and every new start begins on the primary again.
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
    // The monitor whose area holds the compositor point (x, y), or "".
    Q_INVOKABLE QString screenAt(qreal x, qreal y) const;
    // A drag crossed a seam: float on `name` with the mascot box's top-left at (boxX, boxY)
    // in that monitor's own coordinates.
    Q_INVOKABLE void crossTo(const QString &name, qreal boxX, qreal boxY);
    // Dock on this monitor where it was docked last time (or top centre).
    void applyDock();
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
