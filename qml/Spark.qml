// A four-pointed star, for whatever twinkles.
import QtQuick

Canvas {
    id: spark
    property real size: 10
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
        const g = getContext("2d"), s = size, c = s / 2
        g.reset(); g.fillStyle = tint
        g.beginPath(); g.moveTo(c, 0)
        g.quadraticCurveTo(c, c, s, c); g.quadraticCurveTo(c, c, c, s)
        g.quadraticCurveTo(c, c, 0, c); g.quadraticCurveTo(c, c, c, 0)
        g.fill()
    }
}
