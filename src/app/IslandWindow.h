#pragma once

#include <QObject>
#include <QPointF>
#include <QQuickView>
#include <QRectF>

class QScreen;

namespace kisel {

// Platform glue for the island window. Everything that differs between KDE
// Wayland, plain X11 and (later) Windows lives here and in Tray, never in QML.
//
// The window is one fixed-size, transparent surface (708 x 500) big enough for
// the largest view plus its shadow margin. The island animates inside it, and
// the input region (setMask) is kept equal to the island's shape, so every click
// outside goes to the windows underneath and the compositor never resizes a
// surface mid-animation (motion.md: "never animate the window size from inside
// a loop"). Windows has no input regions (a mask would clip the drawing too), so
// there the whole window turns input-transparent while the pointer is outside
// the island's shape. Where the surface sits is one of:
//
//   docked    flush with one edge of the output (top, bottom, left, right), the
//             pill at `along` px along that edge
//   floating  anywhere, the mascot alone (floatX, floatY = the surface origin)
//   grabbing  while the pointer is down the surface is as big as the output and
//             stays still; the island and the mascot move inside it
class IslandWindow : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool debugOn READ debugOn CONSTANT)
    Q_PROPERTY(bool canAvoidPanels READ canAvoidPanels CONSTANT)    // there is a taskbar to keep clear of
    Q_PROPERTY(bool floating READ floating NOTIFY floatingChanged)
    Q_PROPERTY(QString edge READ edge NOTIFY dockChanged)           // top | bottom | left | right
    Q_PROPERTY(qreal along READ along NOTIFY dockChanged)           // the pill's centre along the edge, output px
    Q_PROPERTY(qreal pillAlong READ pillAlong NOTIFY placementChanged) // ...and inside the surface
    Q_PROPERTY(qreal originX READ originX NOTIFY placementChanged)  // where the surface sits on the output
    Q_PROPERTY(qreal originY READ originY NOTIFY placementChanged)
    Q_PROPERTY(bool grabbing READ grabbing NOTIFY grabbingChanged)
    // The surface is currently as big as the output (during a drag).
    Q_PROPERTY(bool viewWide READ viewWide NOTIFY viewWideChanged)
    // Where the pointer is on the output, wherever that is, so the mascot can watch it.
    // Known on Windows only: Wayland tells no client where the pointer is outside its
    // own surface.
    Q_PROPERTY(bool pointerKnown READ pointerKnown CONSTANT)
    Q_PROPERTY(qreal pointerX READ pointerX NOTIFY pointerMoved)
    Q_PROPERTY(qreal pointerY READ pointerY NOTIFY pointerMoved)
    Q_PROPERTY(qreal grabX READ grabX NOTIFY placementChanged)      // the island's origin while the surface is wide
    Q_PROPERTY(qreal grabY READ grabY NOTIFY placementChanged)
    Q_PROPERTY(qreal floatX READ floatX WRITE setFloatX NOTIFY placementChanged)
    Q_PROPERTY(qreal floatY READ floatY WRITE setFloatY NOTIFY placementChanged)

public:
    static constexpr int kWidth = 708;  // 660 card + 2 x space-6
    static constexpr int kHeight = 500; // 440 tallest view + shadow
    // While floating the mascot (120 px) sits at the top of the surface:
    static constexpr int kMascotLeft = 294, kMascotTop = 8, kMascotSize = 120;
    // ...and its card opens from the same spot: 24..684 x 8..448 in the surface.
    static constexpr int kCardLeft = 24, kCardTop = 8, kCardRight = 684, kCardBottom = 448;
    // A docked pill keeps this far from the corners of the output (half the 288 px bar, and 6).
    static constexpr int kCornerKeepOut = 170;

    explicit IslandWindow(QQuickView *view, QObject *parent = nullptr);

    // Call before QGuiApplication exists.
    static void preInit();

    void show();
    QScreen *screen() const { return m_view->screen(); }
    // Re-creates the layer surface on another output (hide, retarget, show).
    void moveToScreen(QScreen *screen);

    // Called from QML as the island changes size.
    Q_INVOKABLE void setHitRect(qreal x, qreal y, qreal w, qreal h);
    Q_INVOKABLE void setKeyboard(bool wanted); // permission card or chat input focused
    Q_INVOKABLE void quit();
    // KISEL_DEBUG=1: lines from QML (pointer, drag, crossing) end up on stderr
    Q_INVOKABLE void log(const QString &text) const;

    bool debugOn() const { return qEnvironmentVariableIsSet("KISEL_DEBUG"); }
    // Windows: the taskbar is topmost as well and would cover an island docked on its
    // edge. With this on, "the output" everywhere below is the work area, the part of
    // the monitor the taskbar leaves free, so a dock on that side sits against the
    // taskbar instead of under it. Layer-shell draws over panels and needs none of it.
    bool canAvoidPanels() const;
    bool avoidPanels() const { return m_avoidPanels; }
    bool pointerKnown() const;
    qreal pointerX() const { return m_pointer.x(); }
    qreal pointerY() const { return m_pointer.y(); }
    void setAvoidPanels(bool on);
    bool floating() const { return m_floating; }
    QString edge() const { return m_edge; }
    qreal along() const { return m_along; }
    bool grabbing() const { return m_grabbing; }
    bool viewWide() const;
    qreal grabX() const { return m_grabX; }
    qreal grabY() const { return m_grabY; }
    qreal floatX() const { return m_floatX; }
    qreal floatY() const { return m_floatY; }
    void setFloatX(qreal x) { setFloatPos(x, m_floatY); }
    void setFloatY(qreal y) { setFloatPos(m_floatX, y); }
    qreal originX() const;
    qreal originY() const;
    qreal pillAlong() const;

    // ---- docking ------------------------------------------------------------
    // Dock to `edge` with the pill centred at `along` px (kept out of the corners).
    // Returns the along actually used.
    Q_INVOKABLE qreal setDock(const QString &edge, qreal along);
    Q_INVOKABLE qreal clampAlong(const QString &edge, qreal along) const;
    Q_INVOKABLE qreal edgeLength(const QString &edge) const;

    // ---- dragging -----------------------------------------------------------
    // Moving a layer surface by changing its margins is applied by the compositor
    // a frame later, while pointer events keep arriving relative to the *old*
    // position: every event then moves the surface again and it overshoots,
    // teleports, leaves the screen. So while the pointer is down the surface is
    // made as big as the output and stays still; the island and the mascot move
    // inside it by exact pointer coordinates. Plain X11 windows do the same.
    Q_INVOKABLE bool beginGrab();
    // Ends the grab and puts the surface where the state says (docked or floating).
    Q_INVOKABLE void endGrab();
    // Float with the surface origin at (x, y), kept so the mascot box is on screen.
    Q_INVOKABLE void restoreFloat(qreal x, qreal y);
    // The surface origin that puts a mascot box at (boxX, boxY) on the output.
    Q_INVOKABLE QPointF originForBox(qreal boxX, qreal boxY) const;
    // Floating on another output at the given surface origin (a drag across a seam).
    void crossTo(QScreen *screen, qreal originX, qreal originY);
    // Where the surface must sit for an open floating card to fit on screen.
    Q_INVOKABLE QPointF fitOpen() const;
    // The spot that keeps the mascot box fully on screen.
    Q_INVOKABLE QPointF clampMascot(qreal x, qreal y) const;
    Q_INVOKABLE qreal screenWidth() const;
    Q_INVOKABLE qreal screenHeight() const;

signals:
    void quitRequested();
    void floatingChanged();
    void dockChanged();
    void placementChanged();
    void grabbingChanged();
    void viewWideChanged();
    void pointerMoved();

private:
    void placeOnX11();
    void bindOutput();
    void setFloatPos(qreal x, qreal y);
    void applyPlacement();
    void applySurfaceSize(bool wide);
    QRect area() const; // the output, or its work area (see setAvoidPanels)
    bool m_avoidPanels = true;
    QPointF m_pointer;
#ifdef Q_OS_WIN
    void trackPointer();
    void applyPassThrough();
    QRectF m_hit;
    bool m_passThrough = false;
    quintptr m_lastForeground = 0; // the window that had the keyboard before the island took it
#endif
    QQuickView *m_view;
    bool m_floating = false;
    bool m_grabbing = false;
    bool m_wasWide = false;
    QString m_edge = QStringLiteral("top");
    qreal m_along = 960;
    qreal m_floatX = 0, m_floatY = 0;
    qreal m_grabX = 0, m_grabY = 0;
};

} // namespace kisel
