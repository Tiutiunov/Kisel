// A broom, drawn rather than taken from a font: the sign on the keys that clean the memory.
import QtQuick

Canvas {
    id: glyph
    property real size: 14
    property color tint: "#FFFFFF"
    width: size; height: size
    onTintChanged: requestPaint()
    // It is drawn once and never again by itself, so a drawing that came too early is
    // lost for good: made over several frames (a card that is created when first shown),
    // the canvas may be asked before it can paint, and stayed blank until Kisel was
    // started anew. So it is asked again when it becomes able, when it comes into sight,
    // and once more a moment after it is made.
    onAvailableChanged: if (available) requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    Component.onCompleted: requestPaint()
    Timer { interval: 500; running: true; onTriggered: parent.requestPaint() }
    onPaint: {
        const g = getContext("2d"), s = size
        g.reset(); g.fillStyle = tint; g.strokeStyle = tint
        g.lineCap = "round"; g.lineJoin = "round"
        // the stick, from the top right down to the head
        g.lineWidth = s * 0.13
        g.beginPath(); g.moveTo(s * 0.86, s * 0.1); g.lineTo(s * 0.46, s * 0.52); g.stroke()
        // the bristles, flaring toward the bottom left
        g.beginPath()
        g.moveTo(s * 0.34, s * 0.4); g.lineTo(s * 0.6, s * 0.66)
        g.lineTo(s * 0.4, s * 0.94); g.lineTo(s * 0.06, s * 0.6)
        g.closePath(); g.fill()
    }
}
