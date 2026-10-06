#include "IslandWindow.h"

#include <QGuiApplication>
#include <QMargins>
#include <QPointF>
#include <QRegion>
#include <QScreen>

#ifdef KISEL_WITH_LAYER_SHELL
#include <LayerShellQt/Shell>
#include <LayerShellQt/Window>
#endif

namespace kisel {

namespace {
bool onWayland() { return QGuiApplication::platformName().startsWith(QLatin1String("wayland")); }
} // namespace

void IslandWindow::preInit()
{
#ifdef KISEL_WITH_LAYER_SHELL
    // Must run before the QGuiApplication is constructed. COUCOU-style opt-out
    // for compositors without layer-shell (GNOME): KISEL_LAYER_SHELL=0.
    if (qEnvironmentVariable("KISEL_LAYER_SHELL") != QLatin1String("0"))
        LayerShellQt::Shell::useLayerShell();
#endif
}

IslandWindow::IslandWindow(QQuickView *view, QObject *parent)
    : QObject(parent)
    , m_view(view)
{
    m_view->setColor(Qt::transparent);
    m_view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_view->resize(kWidth, kHeight);
    m_view->setMinimumSize(QSize(kWidth, kHeight));
    m_view->setMaximumSize(QSize(kWidth, kHeight));
    m_view->setTitle(QStringLiteral("Kisel"));

#ifdef KISEL_WITH_LAYER_SHELL
    if (onWayland() && qEnvironmentVariable("KISEL_LAYER_SHELL") != QLatin1String("0")) {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            ls->setScope(QStringLiteral("kisel"));
            ls->setLayer(LayerShellQt::Window::LayerOverlay);
            // Anchored to the top edge only: the compositor centres it horizontally.
            ls->setAnchors(LayerShellQt::Window::AnchorTop);
            // -1: sit over panels instead of pushing them aside.
            ls->setExclusiveZone(-1);
            ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            ls->setDesiredSize(QSize(kWidth, kHeight));
        }
    }
#endif
}

void IslandWindow::placeOnX11()
{
    // X11 and compositors without layer-shell: a plain frameless window at the
    // top centre of the chosen screen.
    if (!onWayland() || qEnvironmentVariable("KISEL_LAYER_SHELL") == QLatin1String("0")) {
        const QRect g = m_view->screen()->geometry();
        if (m_floating)
            m_view->setPosition(g.left() + int(m_floatX), g.top() + int(m_floatY));
        else
            m_view->setPosition(g.center().x() - kWidth / 2, g.top());
    }
}

void IslandWindow::show()
{
    placeOnX11();
    m_view->show();
}

void IslandWindow::moveToScreen(QScreen *screen)
{
    if (!screen || m_view->screen() == screen)
        return;
    // A layer surface belongs to one output for life, so moving means
    // dropping it and creating a new one on the target screen.
    const bool visible = m_view->isVisible();
    if (visible)
        m_view->hide();
    m_view->setScreen(screen);
    placeOnX11();
    if (visible)
        m_view->show();
}

qreal IslandWindow::screenWidth() const { return m_view->screen() ? m_view->screen()->geometry().width() : 1920; }
qreal IslandWindow::screenHeight() const { return m_view->screen() ? m_view->screen()->geometry().height() : 1080; }

QPointF IslandWindow::clampMascot(qreal x, qreal y) const
{
    // keep the 120 px mascot box fully on the screen
    x = qBound<qreal>(-kMascotLeft, x, screenWidth() - kMascotLeft - kMascotSize);
    y = qBound<qreal>(-kMascotTop, y, screenHeight() - kMascotTop - kMascotSize);
    return {x, y};
}

QPointF IslandWindow::fitOpen() const
{
    // keep the whole open card on screen; if the screen is too small, favour the top-left
    qreal x = qBound<qreal>(-kCardLeft, m_floatX, qMax<qreal>(-kCardLeft, screenWidth() - kCardRight));
    qreal y = qBound<qreal>(-kCardTop, m_floatY, qMax<qreal>(-kCardTop, screenHeight() - kCardBottom));
    return {x, y};
}

// Layer-shell margins are relative to the output, so one number pair places the
// surface. Re-anchoring an existing layer surface needs no re-creation.
void IslandWindow::applyPlacement()
{
#ifdef KISEL_WITH_LAYER_SHELL
    if (onWayland() && qEnvironmentVariable("KISEL_LAYER_SHELL") != QLatin1String("0")) {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            if (m_floating) {
                ls->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorLeft));
                ls->setMargins(QMargins(int(m_floatX), int(m_floatY), 0, 0));
            } else {
                ls->setAnchors(LayerShellQt::Window::AnchorTop);
                ls->setMargins(QMargins());
            }
        }
        return;
    }
#endif
    placeOnX11();
}

void IslandWindow::setFloatPos(qreal x, qreal y, bool force)
{
    if (!m_floating && !force)
        return;
    if (qFuzzyCompare(x, m_floatX) && qFuzzyCompare(y, m_floatY) && !force)
        return;
    m_floatX = x;
    m_floatY = y;
    applyPlacement();
    emit floatMoved();
}

void IslandWindow::beginFloat(qreal pointerX, qreal pointerY)
{
    if (m_floating)
        return;
    // Docked, the surface is centred on the screen's top edge, so the pointer's
    // screen position is known even though Wayland never tells us the cursor.
    const qreal originX = (screenWidth() - kWidth) / 2;
    const qreal gx = originX + pointerX, gy = pointerY;
    const QPointF p = clampMascot(gx - (kMascotLeft + kMascotSize / 2.0), gy - (kMascotTop + kMascotSize / 2.0));
    m_floating = true;
    setFloatPos(p.x(), p.y(), true);
    emit floatingChanged();
}

void IslandWindow::restoreFloat(qreal x, qreal y)
{
    const QPointF p = clampMascot(x, y);
    m_floating = true;
    setFloatPos(p.x(), p.y(), true);
    emit floatingChanged();
}

void IslandWindow::dock()
{
    if (!m_floating)
        return;
    m_floating = false;
    applyPlacement();
    emit floatingChanged();
    emit floatMoved();
}

void IslandWindow::setHitRect(qreal x, qreal y, qreal w, qreal h)
{
    // The mask doubles as the Wayland input region. A rectangle is enough: the
    // corner slivers are transparent and a click there is a harmless miss.
    if (QGuiApplication::platformName() == QLatin1String("offscreen"))
        return; // that platform plugin has no input regions
    m_view->setMask(QRegion(QRectF(x, y, w, h).toAlignedRect()));
}

void IslandWindow::setKeyboard(bool wanted)
{
#ifdef KISEL_WITH_LAYER_SHELL
    // On demand only while the island needs typing or a key answer, so it
    // never steals focus from the terminal where Claude Code runs.
    if (onWayland()) {
        if (auto *ls = LayerShellQt::Window::get(m_view))
            ls->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                : LayerShellQt::Window::KeyboardInteractivityNone);
    }
#else
    Q_UNUSED(wanted)
#endif
}

void IslandWindow::quit()
{
    emit quitRequested();
}

} // namespace kisel
