#pragma once

#include <QObject>
#include <QQuickView>
#include <QRectF>

class QScreen;

namespace kisel {

// Platform glue for the island window. Everything that differs between KDE
// Wayland, plain X11 and (later) Windows lives here and in Tray, never in QML.
//
// The window is one fixed-size, transparent surface big enough for the largest
// view plus its shadow margin. The island animates inside it, and the input
// region (setMask) is kept equal to the island's shape, so every click outside
// goes to the windows underneath and the compositor never resizes a surface
// mid-animation (motion.md: "never animate the window size from inside a loop").
class IslandWindow : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool floating READ floating NOTIFY floatingChanged)
    Q_PROPERTY(qreal floatX READ floatX WRITE setFloatX NOTIFY floatMoved)
    Q_PROPERTY(qreal floatY READ floatY WRITE setFloatY NOTIFY floatMoved)

public:
    static constexpr int kWidth = 708;  // 660 card + 2 x space-6
    static constexpr int kHeight = 500; // 440 tallest view + shadow
    // While floating the mascot (120 px) sits at the top of the surface:
    static constexpr int kMascotLeft = 294, kMascotTop = 8, kMascotSize = 120;
    // ...and its card opens from the same spot: 24..684 x 8..448 in the surface.
    static constexpr int kCardLeft = 24, kCardTop = 8, kCardRight = 684, kCardBottom = 448;

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

    // ---- floating mascot --------------------------------------------------
    // Docked, the surface is anchored to the top edge and centred. Floating, it
    // is anchored top+left and moved with layer-shell margins; (floatX, floatY)
    // is the surface origin relative to the screen's top-left corner.
    bool floating() const { return m_floating; }
    qreal floatX() const { return m_floatX; }
    qreal floatY() const { return m_floatY; }
    void setFloatX(qreal x) { setFloatPos(x, m_floatY, false); }
    void setFloatY(qreal y) { setFloatPos(m_floatX, y, false); }
    // The pointer (in surface coordinates) pulled the mascot out of the island:
    // float it so the mascot is centred under the pointer.
    Q_INVOKABLE void beginFloat(qreal pointerX, qreal pointerY);
    Q_INVOKABLE void restoreFloat(qreal x, qreal y);
    Q_INVOKABLE void dock();
    Q_INVOKABLE void moveBy(qreal dx, qreal dy) { setFloatPos(m_floatX + dx, m_floatY + dy, false); }
    // Where the surface must sit for the open card to fit on screen.
    Q_INVOKABLE QPointF fitOpen() const;
    // The spot that keeps the mascot box fully on screen.
    Q_INVOKABLE QPointF clampMascot(qreal x, qreal y) const;
    Q_INVOKABLE qreal screenWidth() const;
    Q_INVOKABLE qreal screenHeight() const;

signals:
    void quitRequested();
    void floatingChanged();
    void floatMoved();

private:
    void placeOnX11();
    void setFloatPos(qreal x, qreal y, bool force);
    void applyPlacement();
    QQuickView *m_view;
    bool m_floating = false;
    qreal m_floatX = 0, m_floatY = 0;
};

} // namespace kisel
