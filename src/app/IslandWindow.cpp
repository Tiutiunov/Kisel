#include "IslandWindow.h"

#include <QGuiApplication>
#include <QMargins>
#include <QRegion>
#include <QScreen>

#ifdef KISEL_WITH_LAYER_SHELL
#include <LayerShellQt/Shell>
#include <LayerShellQt/Window>
#endif

namespace kisel {

namespace {
bool onWayland() { return QGuiApplication::platformName().startsWith(QLatin1String("wayland")); }
bool useLayerShell()
{
#ifdef KISEL_WITH_LAYER_SHELL
    return onWayland() && qEnvironmentVariable("KISEL_LAYER_SHELL") != QLatin1String("0");
#else
    return false;
#endif
}
constexpr int kMaxWin = 16777215;
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
    auto wide = [this] {
        const bool w = viewWide();
        if (w != m_wasWide) { m_wasWide = w; emit viewWideChanged(); }
    };
    connect(m_view, &QWindow::widthChanged, this, wide);
    connect(m_view, &QWindow::heightChanged, this, wide);

#ifdef KISEL_WITH_LAYER_SHELL
    if (useLayerShell()) {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            ls->setScope(QStringLiteral("kisel"));
            ls->setLayer(LayerShellQt::Window::LayerOverlay);
            // -1: sit over panels instead of pushing them aside.
            ls->setExclusiveZone(-1);
            ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            ls->setDesiredSize(QSize(kWidth, kHeight));
        }
    }
#endif
    applyPlacement();
}

// ---- geometry ---------------------------------------------------------------

qreal IslandWindow::screenWidth() const { return m_view->screen() ? m_view->screen()->geometry().width() : 1920; }
qreal IslandWindow::screenHeight() const { return m_view->screen() ? m_view->screen()->geometry().height() : 1080; }
bool IslandWindow::viewWide() const { return m_view->width() > kWidth + 40 || m_view->height() > kHeight + 40; }

qreal IslandWindow::edgeLength(const QString &edge) const
{
    return (edge == QLatin1String("left") || edge == QLatin1String("right")) ? screenHeight() : screenWidth();
}

qreal IslandWindow::clampAlong(const QString &edge, qreal along) const
{
    const qreal len = edgeLength(edge);
    if (len <= 2 * kCornerKeepOut)
        return len / 2;
    return qBound<qreal>(kCornerKeepOut, along, len - kCornerKeepOut);
}

qreal IslandWindow::originX() const
{
    if (m_floating)
        return m_floatX;
    if (m_edge == QLatin1String("left"))
        return 0;
    if (m_edge == QLatin1String("right"))
        return screenWidth() - kWidth;
    return qBound<qreal>(0, m_along - kWidth / 2.0, qMax<qreal>(0, screenWidth() - kWidth));
}

qreal IslandWindow::originY() const
{
    if (m_floating)
        return m_floatY;
    if (m_edge == QLatin1String("bottom"))
        return screenHeight() - kHeight;
    if (m_edge == QLatin1String("top"))
        return 0;
    return qBound<qreal>(0, m_along - kHeight / 2.0, qMax<qreal>(0, screenHeight() - kHeight));
}

qreal IslandWindow::pillAlong() const
{
    const bool vertical = m_edge == QLatin1String("left") || m_edge == QLatin1String("right");
    return vertical ? m_along - originY() : m_along - originX();
}

QPointF IslandWindow::originForBox(qreal boxX, qreal boxY) const
{
    return {boxX - kMascotLeft, boxY - kMascotTop};
}

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

// ---- placement ----------------------------------------------------------------

void IslandWindow::placeOnX11()
{
    // X11 and compositors without layer-shell: a plain frameless window.
    if (useLayerShell() || !m_view->screen())
        return;
    const QRect g = m_view->screen()->geometry();
    m_view->setPosition(g.left() + int(originX()), g.top() + int(originY()));
}

// Layer-shell margins are relative to the output, so the anchors and one margin
// pair place the surface. Re-anchoring an existing layer surface needs no
// re-creation.
void IslandWindow::applyPlacement()
{
    if (m_grabbing)
        return; // the surface covers the output and stays still
#ifdef KISEL_WITH_LAYER_SHELL
    if (useLayerShell()) {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            using A = LayerShellQt::Window;
            if (m_floating) {
                ls->setAnchors(A::Anchors(A::AnchorTop | A::AnchorLeft));
                ls->setMargins(QMargins(int(m_floatX), int(m_floatY), 0, 0));
            } else if (m_edge == QLatin1String("top")) {
                ls->setAnchors(A::Anchors(A::AnchorTop | A::AnchorLeft));
                ls->setMargins(QMargins(int(originX()), 0, 0, 0));
            } else if (m_edge == QLatin1String("bottom")) {
                ls->setAnchors(A::Anchors(A::AnchorBottom | A::AnchorLeft));
                ls->setMargins(QMargins(int(originX()), 0, 0, 0));
            } else if (m_edge == QLatin1String("left")) {
                ls->setAnchors(A::Anchors(A::AnchorLeft | A::AnchorTop));
                ls->setMargins(QMargins(0, int(originY()), 0, 0));
            } else {
                ls->setAnchors(A::Anchors(A::AnchorRight | A::AnchorTop));
                ls->setMargins(QMargins(0, int(originY()), 0, 0));
            }
        }
        return;
    }
#endif
    placeOnX11();
}

// Tell the compositor which output the layer surface belongs to. Left to itself it
// picks the output where the pointer is, whatever QWindow::screen() says.
void IslandWindow::bindOutput()
{
#ifdef KISEL_WITH_LAYER_SHELL
    if (useLayerShell() && m_view->screen()) {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            ls->setScreen(m_view->screen());
        }
    }
#endif
}

void IslandWindow::show()
{
    bindOutput();
    placeOnX11();
    m_view->show();
}

void IslandWindow::moveToScreen(QScreen *screen)
{
    if (!screen)
        return;
    if (m_view->screen() == screen) {
        // same output as far as Qt knows, but the compositor may have put the surface elsewhere
        if (m_view->isVisible()) {
            m_view->hide();
            bindOutput();
            m_view->show();
        } else {
            bindOutput();
        }
        return;
    }
    // A layer surface belongs to one output for life, so moving means
    // dropping it and creating a new one on the target screen.
    const bool visible = m_view->isVisible();
    if (visible)
        m_view->hide();
    m_view->setScreen(screen);
    bindOutput();
    applyPlacement();
    placeOnX11();
    if (visible)
        m_view->show();
    emit placementChanged();
}

void IslandWindow::setFloatPos(qreal x, qreal y)
{
    if (qFuzzyCompare(x, m_floatX) && qFuzzyCompare(y, m_floatY))
        return;
    m_floatX = x;
    m_floatY = y;
    if (m_floating)
        applyPlacement();
    emit placementChanged();
}

qreal IslandWindow::setDock(const QString &edge, qreal along)
{
    static const QStringList ok {"top", "bottom", "left", "right"};
    m_edge = ok.contains(edge) ? edge : QStringLiteral("top");
    m_along = clampAlong(m_edge, along);
    const bool wasFloating = m_floating;
    m_floating = false;
    applyPlacement();
    if (wasFloating)
        emit floatingChanged();
    emit dockChanged();
    emit placementChanged();
    return m_along;
}

void IslandWindow::restoreFloat(qreal x, qreal y)
{
    const QPointF p = clampMascot(x, y);
    const bool was = m_floating;
    m_floating = true;
    m_floatX = p.x();
    m_floatY = p.y();
    applyPlacement();
    if (!was)
        emit floatingChanged();
    emit placementChanged();
}

// ---- dragging ---------------------------------------------------------------

void IslandWindow::applySurfaceSize(bool wide)
{
    if (wide) {
        m_view->setMinimumSize(QSize(0, 0));
        m_view->setMaximumSize(QSize(kMaxWin, kMaxWin));
    } else {
        m_view->setMinimumSize(QSize(kWidth, kHeight));
        m_view->setMaximumSize(QSize(kWidth, kHeight));
    }
#ifdef KISEL_WITH_LAYER_SHELL
    if (useLayerShell()) {
        if (auto *ls = LayerShellQt::Window::get(m_view))
            ls->setDesiredSize(wide ? QSize(0, 0) : QSize(kWidth, kHeight)); // 0 + all four anchors = fill
    }
#endif
}

bool IslandWindow::beginGrab()
{
    if (m_grabbing)
        return true;
    m_grabX = originX();
    m_grabY = originY();
    m_grabbing = true;
    applySurfaceSize(true);
#ifdef KISEL_WITH_LAYER_SHELL
    if (useLayerShell()) {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            using A = LayerShellQt::Window;
            ls->setAnchors(A::Anchors(A::AnchorTop | A::AnchorBottom | A::AnchorLeft | A::AnchorRight));
            ls->setMargins(QMargins());
        }
    } else
#endif
    if (m_view->screen()) {
        // plain windows: the window itself becomes the size of the output
        m_view->setGeometry(m_view->screen()->geometry());
    }
    emit grabbingChanged();
    emit placementChanged();
    return true;
}

void IslandWindow::endGrab()
{
    if (!m_grabbing)
        return;
    m_grabbing = false;
    applySurfaceSize(false);
    if (!useLayerShell() && m_view->screen())
        m_view->resize(kWidth, kHeight);
    applyPlacement();
    emit grabbingChanged();
    emit placementChanged();
}

void IslandWindow::crossTo(QScreen *screen, qreal ox, qreal oy)
{
    if (!screen)
        return;
    // the grab ends and the island floats on the other output
    m_grabbing = false;
    applySurfaceSize(false);
    const bool was = m_floating;
    m_floating = true;
    m_floatX = ox;
    m_floatY = oy;
    if (m_view->screen() == screen) {
        applyPlacement();
    } else {
        const bool visible = m_view->isVisible();
        if (visible)
            m_view->hide();
        m_view->setScreen(screen);
        bindOutput();
        const QPointF p = clampMascot(m_floatX, m_floatY);
        m_floatX = p.x();
        m_floatY = p.y();
        if (!useLayerShell())
            m_view->resize(kWidth, kHeight);
        applyPlacement();
        if (visible)
            m_view->show();
    }
    if (!was)
        emit floatingChanged();
    emit grabbingChanged();
    emit placementChanged();
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
    if (useLayerShell()) {
        if (auto *ls = LayerShellQt::Window::get(m_view))
            ls->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                : LayerShellQt::Window::KeyboardInteractivityNone);
    }
#else
    Q_UNUSED(wanted)
#endif
}

void IslandWindow::log(const QString &text) const
{
    static const bool on = qEnvironmentVariableIsSet("KISEL_DEBUG");
    if (on)
        qInfo("%s", qPrintable(text));
}

void IslandWindow::quit()
{
    emit quitRequested();
}

} // namespace kisel
