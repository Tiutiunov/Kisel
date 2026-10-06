#include "SeamWindows.h"

#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QScreen>

#ifdef KISEL_WITH_LAYER_SHELL
#include <LayerShellQt/Window>
#endif

namespace kisel {

namespace {
bool layerShell()
{
#ifdef KISEL_WITH_LAYER_SHELL
    return QGuiApplication::platformName().startsWith(QLatin1String("wayland"))
        && qEnvironmentVariable("KISEL_LAYER_SHELL") != QLatin1String("0");
#else
    return false;
#endif
}
} // namespace

SeamWindows::~SeamWindows()
{
    for (Entry &e : m_entries)
        delete e.view;
}

SeamWindows::Entry &SeamWindows::entryFor(QScreen *screen)
{
    Entry &e = m_entries[screen->name()];
    if (e.view)
        return e;
    e.state = new SeamState;
    e.view = new QQuickView;
    e.view->setScreen(screen);
    e.view->setColor(Qt::transparent);
    // no input at all: the pointer belongs to the island's surface, which holds the grab
    e.view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::WindowTransparentForInput
#ifdef Q_OS_WIN
                     | Qt::Tool // no taskbar button
#endif
                     );
    e.view->setResizeMode(QQuickView::SizeRootObjectToView);
    e.view->setTitle(QStringLiteral("Kisel seam"));
    e.view->engine()->rootContext()->setContextProperty(QStringLiteral("seam"), e.state);
    e.view->loadFromModule("Kisel", "Seam");
#ifdef KISEL_WITH_LAYER_SHELL
    if (layerShell()) {
        if (auto *ls = LayerShellQt::Window::get(e.view)) {
            using A = LayerShellQt::Window;
            ls->setScope(QStringLiteral("kisel-seam"));
            ls->setLayer(A::LayerOverlay);
            ls->setAnchors(A::Anchors(A::AnchorTop | A::AnchorBottom | A::AnchorLeft | A::AnchorRight));
            ls->setExclusiveZone(-1);
            ls->setKeyboardInteractivity(A::KeyboardInteractivityNone);
            ls->setDesiredSize(QSize(0, 0));
            ls->setScreen(screen);
        }
    } else
#endif
    {
        e.view->setGeometry(screen->geometry());
    }
    return e;
}

void SeamWindows::show(const QString &screenName, qreal cx, qreal cy, qreal size, qreal vx, qreal vy, const QString &mood)
{
    QScreen *screen = nullptr;
    for (QScreen *s : QGuiApplication::screens())
        if (s->name() == screenName)
            screen = s;
    if (!screen)
        return;
    Entry &e = entryFor(screen);
    e.state->cx = cx; e.state->cy = cy; e.state->size = size;
    e.state->vx = vx; e.state->vy = vy; e.state->mood = mood;
    emit e.state->changed();
    if (!e.view->isVisible())
        e.view->show();
}

void SeamWindows::hideScreen(const QString &screenName)
{
    const auto it = m_entries.constFind(screenName);
    if (it != m_entries.constEnd() && it->view && it->view->isVisible())
        it->view->hide();
}

void SeamWindows::hideAll()
{
    for (const Entry &e : std::as_const(m_entries))
        if (e.view && e.view->isVisible())
            e.view->hide();
}

} // namespace kisel
