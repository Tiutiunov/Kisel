#include "IslandWindow.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QSettings>
#include <QStandardPaths>
#include <QMargins>
#include <QQmlEngine>
#include <QQuickItem>
#include <QRegion>
#include <QScreen>

#ifdef Q_OS_WIN
#include <QCursor>
#include <QTimer>
#include <qt_windows.h>
#include <shellapi.h>

#include <cstdio>
#include <io.h>
#endif

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
#ifdef Q_OS_WIN
    // A window-subsystem program has no stdout. Started from a terminal, borrow
    // its console so --help and the development flags can print; streams that
    // were redirected somewhere are left alone.
    if (AttachConsole(ATTACH_PARENT_PROCESS)) {
        FILE *f = nullptr;
        if (_fileno(stdout) < 0)
            freopen_s(&f, "CONOUT$", "w", stdout);
        if (_fileno(stderr) < 0)
            freopen_s(&f, "CONOUT$", "w", stderr);
    }
    QQuickWindow::setDefaultAlphaBuffer(true); // the surface is transparent around the island
#endif
}

IslandWindow::IslandWindow(QQuickView *view, QObject *parent)
    : QObject(parent)
    , m_view(view)
{
    m_view->setColor(Qt::transparent);
#ifdef Q_OS_WIN
    // Tool: no taskbar button. No focus until setKeyboard() asks for it.
    m_view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool | Qt::WindowDoesNotAcceptFocus);
    auto *poll = new QTimer(this);
    connect(poll, &QTimer::timeout, this, &IslandWindow::trackPointer);
    poll->start(33);
    // the taskbar moved, grew or started hiding itself: the work area changed under us
    // ...or the resolution did (a game, a remote session, the monitor waking up). The
    // bar goes back to the same share of its edge, whatever the edge's length is now.
    auto follow = [this](QScreen *s) {
        const auto again = [this, s] {
            if (s != m_view->screen() || m_grabbing)
                return;
            if (!m_floating)
                m_along = clampAlong(m_edge, m_frac * edgeLength(m_edge));
            applyPlacement();
            emit dockChanged();
            emit placementChanged();
        };
        connect(s, &QScreen::availableGeometryChanged, this, again);
        connect(s, &QScreen::geometryChanged, this, again);
    };
    connect(m_view, &QWindow::screenChanged, this, [this] { QMetaObject::invokeMethod(this, &IslandWindow::screenStrayed, Qt::QueuedConnection); });
    for (QScreen *s : QGuiApplication::screens())
        follow(s);
    connect(qApp, &QGuiApplication::screenAdded, this, follow);
#else
    m_view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
#endif
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

namespace {
#ifdef Q_OS_WIN
const QString kRunKey = QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run");
QString startupShortcut()
{
    return QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation) + QStringLiteral("/Startup/Kisel.lnk");
}
#else
QString autostartFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/autostart/kisel.desktop");
}
#endif
} // namespace

bool IslandWindow::autostart() const
{
#ifdef Q_OS_WIN
    return QSettings(kRunKey, QSettings::NativeFormat).contains(QStringLiteral("Kisel")) || QFile::exists(startupShortcut());
#else
    return QFile::exists(autostartFile());
#endif
}

void IslandWindow::setAutostart(bool on)
{
    if (on == autostart())
        return;
#ifdef Q_OS_WIN
    QSettings run(kRunKey, QSettings::NativeFormat);
    if (on)
        run.setValue(QStringLiteral("Kisel"), QStringLiteral("\"%1\"").arg(QDir::toNativeSeparators(QCoreApplication::applicationFilePath())));
    else {
        run.remove(QStringLiteral("Kisel"));
        QFile::remove(startupShortcut());
    }
#else
    if (on) {
        QDir().mkpath(QFileInfo(autostartFile()).absolutePath());
        QFile f(autostartFile());
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            f.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=Kisel\nExec=%1\nX-GNOME-Autostart-enabled=true\n")
                        .arg(QCoreApplication::applicationFilePath()).toUtf8());
    } else {
        QFile::remove(autostartFile());
    }
#endif
    emit autostartChanged();
}

bool IslandWindow::canAvoidPanels() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

bool IslandWindow::pointerKnown() const
{
#ifdef Q_OS_WIN
    return QGuiApplication::platformName() == QLatin1String("windows");
#else
    return false;
#endif
}

QRect IslandWindow::area() const
{
    const QScreen *s = m_view->screen();
    if (!s)
        return QRect(0, 0, 1920, 1080);
    // (under a full-screen program there is no taskbar to keep clear of)
    return m_avoidPanels && canAvoidPanels() && !m_covered ? s->availableGeometry() : s->geometry();
}

void IslandWindow::setAvoidPanels(bool on)
{
    if (on == m_avoidPanels)
        return;
    m_avoidPanels = on;
    m_along = clampAlong(m_edge, m_frac * edgeLength(m_edge));
    applyPlacement();
    emit dockChanged();
    emit placementChanged();
}

qreal IslandWindow::screenWidth() const { return area().width(); }
qreal IslandWindow::screenHeight() const { return area().height(); }
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
    const QRect g = area();
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
    const qreal len = edgeLength(m_edge);
    m_frac = len > 0 ? m_along / len : 0.5;
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
        m_view->setGeometry(area());
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
#ifdef Q_OS_WIN
    m_hit = QRectF(x, y, w, h);
    trackPointer();
#else
    m_view->setMask(QRegion(QRectF(x, y, w, h).toAlignedRect()));
#endif
}

#ifdef Q_OS_WIN
// The window style itself, not Qt::WindowTransparentForInput: going through Qt costs
// about 2 ms of the GUI thread each time, on the very frames where the pointer enters
// or leaves and an animation starts.
void IslandWindow::applyPassThrough()
{
    const HWND self = HWND(m_view->winId());
    const LONG_PTR ex = GetWindowLongPtrW(self, GWL_EXSTYLE);
    // both bits together: a layered window that draws through DirectComposition has no
    // bitmap to hit-test, so left layered it would let every click through for good
    const LONG_PTR bits = WS_EX_LAYERED | WS_EX_TRANSPARENT;
    const LONG_PTR want = m_passThrough ? (ex | bits) : (ex & ~bits);
    if (want != ex)
        SetWindowLongPtrW(self, GWL_EXSTYLE, want);
}

// An input-transparent window gets no pointer events at all, so nothing would
// tell us the pointer came back: ask where it is, 30 times a second.
// Is the window in front a full-screen one on Kisel's monitor? It covers the whole
// monitor (the taskbar's strip too) and is either bare of a title bar, as games and
// full-screen films are, or Windows itself says a full-screen program is running. The
// desktop does not count, and neither does an ordinary maximised window.
bool IslandWindow::fullScreenAbove() const
{
    const HWND self = HWND(m_view->winId());
    const HWND front = GetForegroundWindow();
    if (!front || front == self || IsIconic(front) || !IsWindowVisible(front))
        return false;
    wchar_t cls[64] = {};
    GetClassNameW(front, cls, 63);
    for (const wchar_t *shell : {L"Progman", L"WorkerW", L"Shell_TrayWnd", L"Shell_SecondaryTrayWnd", L"XamlExplorerHostIslandWindow"})
        if (wcscmp(cls, shell) == 0)
            return false;
    MONITORINFO mi = {};
    mi.cbSize = sizeof mi;
    if (!GetMonitorInfoW(MonitorFromWindow(self, MONITOR_DEFAULTTONEAREST), &mi))
        return false;
    RECT r = {};
    if (!GetWindowRect(front, &r))
        return false;
    const RECT &m = mi.rcMonitor;
    if (r.left > m.left || r.top > m.top || r.right < m.right || r.bottom < m.bottom)
        return false;
    if (!(GetWindowLongPtrW(front, GWL_STYLE) & WS_CAPTION))
        return true;
    QUERY_USER_NOTIFICATION_STATE state = QUNS_ACCEPTS_NOTIFICATIONS;
    return SUCCEEDED(SHQueryUserNotificationState(&state))
        && (state == QUNS_BUSY || state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE);
}

// Looked at once a second. Two looks in a row must agree before the bar goes down to
// the edge or comes back up, so switching windows does not make it hop.
void IslandWindow::lookForCover()
{
    const bool now = !m_grabbing && fullScreenAbove();
    if (now == m_covered) {
        m_coverCount = 0;
        return;
    }
    if (++m_coverCount < 2)
        return;
    m_coverCount = 0;
    m_covered = now;
    if (!m_floating)
        m_along = clampAlong(m_edge, m_frac * edgeLength(m_edge));
    applyPlacement();
    emit coveredChanged();
    emit dockChanged();
    emit placementChanged();
}

// Windows moves windows about by itself: when the resolution changes, when a monitor
// goes to sleep and comes back, when a full-screen program takes over. Once a second
// the bar looks at where it is and, if that is not where it was put, goes back.
void IslandWindow::keepPlace()
{
    if (m_grabbing || viewWide() || !m_view->isVisible() || !m_view->screen())
        return;
    const QPoint want(area().left() + int(originX()), area().top() + int(originY()));
    if (m_view->position() == want)
        return;
    if (!m_floating) {
        const qreal along = clampAlong(m_edge, m_frac * edgeLength(m_edge));
        if (!qFuzzyCompare(along + 1, m_along + 1)) {
            m_along = along;
            emit dockChanged();
        }
    }
    applyPlacement();
    emit placementChanged();
}

void IslandWindow::trackPointer()
{
    if (QGuiApplication::platformName() != QLatin1String("windows"))
        return;
    if (++m_polls >= 30) {
        m_polls = 0;
        lookForCover();
        keepPlace();
    }
    const HWND self = HWND(m_view->winId());
    const HWND front = GetForegroundWindow();
    if (front && front != self)
        m_lastForeground = quintptr(front);
    // A held button means a press or a drag that started on the island: it keeps
    // the pointer wherever it goes.
    // (Not "while grabbing": the greeting uses the output-sized surface with no button down.)
    const bool held = QGuiApplication::mouseButtons() != Qt::NoButton;
    const QPoint cursor = QCursor::pos();
    const QPointF onOutput = cursor - area().topLeft();
    if (onOutput != m_pointer) {
        m_pointer = onOutput;
        emit pointerMoved();
    }
    const bool pass = !held && !m_hit.contains(m_view->mapFromGlobal(cursor));
    if (pass == m_passThrough)
        return;
    m_passThrough = pass;
    applyPassThrough();
}
#endif

void IslandWindow::setKeyboard(bool wanted)
{
#ifdef Q_OS_WIN
    // A click focuses the island only while it needs typing or a key answer.
    // When that ends the keyboard goes back to the window it was taken from,
    // usually the terminal where Claude Code runs.
    if (QGuiApplication::platformName() != QLatin1String("windows"))
        return;
    m_view->setFlag(Qt::WindowDoesNotAcceptFocus, !wanted);
    applyPassThrough(); // Qt has just rewritten the window's styles
    if (!wanted && m_lastForeground && GetForegroundWindow() == HWND(m_view->winId()))
        SetForegroundWindow(HWND(m_lastForeground));
#endif
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

void IslandWindow::rest()
{
    if (QQmlEngine *engine = qmlEngine(m_view->rootObject())) {
        engine->collectGarbage();
        engine->trimComponentCache();
    }
    m_view->releaseResources(); // (textures and caches the scene is not showing)
#ifdef Q_OS_WIN
    // The pages nothing has touched for a while leave the working set; any that are
    // needed again simply come back.
    SetProcessWorkingSetSize(GetCurrentProcess(), SIZE_T(-1), SIZE_T(-1));
#endif
}

} // namespace kisel
