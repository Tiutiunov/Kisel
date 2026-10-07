#include "Displays.h"

#include "IslandWindow.h"
#include "Preferences.h"

#include <QGuiApplication>
#include <QScreen>

namespace kisel {

Displays::Displays(IslandWindow *window, Preferences *prefs, QObject *parent)
    : QObject(parent)
    , m_window(window)
    , m_prefs(prefs)
{
    // Every start follows the primary monitor (the one KDE ranks first). A monitor
    // picked in Settings holds for this session only, so a stale choice can never
    // leave Kisel on a screen the user no longer expects.
    m_prefs->setScreenName(QString());

    // Hot-plug: a monitor appears or goes away, or the primary changes.
    connect(qApp, &QGuiApplication::screenAdded, this, [this] { reconcile(); });
    connect(qApp, &QGuiApplication::screenRemoved, this, [this] { reconcile(); });
    connect(qApp, &QGuiApplication::primaryScreenChanged, this, [this] { reconcile(); });
    // (...or Windows has put the window on another monitor by itself: back it goes)
    connect(m_window, &IslandWindow::screenStrayed, this, [this] { reconcile(); });
}

QString Displays::wanted() const { return m_prefs->screenName(); }

QString Displays::current() const
{
    const QScreen *s = m_window->screen();
    return s ? s->name() : QString();
}

QScreen *Displays::target() const
{
    const QString name = wanted();
    if (!name.isEmpty())
        for (QScreen *s : QGuiApplication::screens())
            if (s->name() == name)
                return s;
    return QGuiApplication::primaryScreen();
}

QVariantList Displays::screens() const
{
    QVariantList out;
    for (QScreen *s : QGuiApplication::screens()) {
        const QRect g = s->geometry();
        const QString maker = (s->manufacturer() + QLatin1Char(' ') + s->model()).trimmed();
        out.append(QVariantMap {
            {"name", s->name()},
            {"label", maker.isEmpty() ? s->name() : maker},
            {"x", g.x()}, {"y", g.y()}, {"w", g.width()}, {"h", g.height()},
            {"primary", s == QGuiApplication::primaryScreen()},
        });
    }
    return out;
}

void Displays::select(const QString &name)
{
    m_prefs->setScreenName(name); // "" = primary, follows the system
    reconcile();
}

void Displays::applyDock()
{
    const QString name = current();
    const QString edge = m_prefs->dockEdge(name);
    const qreal frac = m_prefs->dockFraction(name);
    m_window->setDock(edge, frac * m_window->edgeLength(edge));
}

void Displays::applyInitial()
{
    if (qEnvironmentVariableIsSet("KISEL_DEBUG"))
        qInfo("displays: target=%s window-screen=%s primary=%s", qPrintable(target()->name()), qPrintable(current()), qPrintable(QGuiApplication::primaryScreen()->name()));
    m_window->moveToScreen(target());
    // (the island no longer leaves its edge: one that was left floating docks again)
    if (m_prefs->floating())
        m_prefs->setFloating(false);
    applyDock();
    emit changed();
}

QString Displays::screenAt(qreal x, qreal y) const
{
    for (QScreen *s : QGuiApplication::screens())
        if (s->geometry().contains(QPointF(x, y).toPoint()))
            return s->name();
    return {};
}

void Displays::crossTo(const QString &name, qreal boxX, qreal boxY)
{
    for (QScreen *s : QGuiApplication::screens()) {
        if (s->name() != name)
            continue;
        const QPointF o = m_window->originForBox(boxX, boxY);
        m_window->crossTo(s, o.x(), o.y());
        emit changed();
        return;
    }
}

void Displays::reconcile()
{
    QScreen *t = target();
    const bool moved = t && t != m_window->screen();
    if (moved) {
        m_window->moveToScreen(t);
        if (!m_window->floating())
            applyDock(); // docked where it was last time on this monitor
        // the island re-appears on the new output a moment later
        QMetaObject::invokeMethod(this, &Displays::moved, Qt::QueuedConnection);
    }
    emit changed();
}

} // namespace kisel
