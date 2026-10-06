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
    // Hot-plug: a monitor appears or goes away, or the primary changes.
    connect(qApp, &QGuiApplication::screenAdded, this, [this] { reconcile(); });
    connect(qApp, &QGuiApplication::screenRemoved, this, [this] { reconcile(); });
    connect(qApp, &QGuiApplication::primaryScreenChanged, this, [this] { reconcile(); });
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

void Displays::applyInitial()
{
    m_window->moveToScreen(target());
    emit changed();
}

void Displays::reconcile()
{
    QScreen *t = target();
    const bool moved = t && t != m_window->screen();
    if (moved) {
        m_window->moveToScreen(t);
        // the island re-appears on the new output a moment later
        QMetaObject::invokeMethod(this, &Displays::moved, Qt::QueuedConnection);
    }
    emit changed();
}

} // namespace kisel
