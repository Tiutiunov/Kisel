// The shapes the players need, drawn rather than taken from a font: play, pause,
// next, prev, and a note for the cover that is not there.
import QtQuick
import Kisel.Core

Canvas {
    id: glyph
    property string kind: "play"
    property real size: 14
    property color tint: Theme.ink
    width: size; height: size
    onKindChanged: requestPaint()
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
        g.reset(); g.fillStyle = tint; g.strokeStyle = tint; g.lineJoin = "round"
        const tri = (x0, x1) => { g.beginPath(); g.moveTo(x0, s * 0.14); g.lineTo(x1, s * 0.5); g.lineTo(x0, s * 0.86); g.closePath(); g.fill() }
        if (kind === "play") tri(s * 0.24, s * 0.86)
        else if (kind === "pause") { g.fillRect(s * 0.2, s * 0.14, s * 0.22, s * 0.72); g.fillRect(s * 0.58, s * 0.14, s * 0.22, s * 0.72) }
        else if (kind === "next") { tri(s * 0.12, s * 0.7); g.fillRect(s * 0.72, s * 0.14, s * 0.16, s * 0.72) }
        else if (kind === "prev") { tri(s * 0.88, s * 0.3); g.fillRect(s * 0.12, s * 0.14, s * 0.16, s * 0.72) }
        else { // a note
            g.lineWidth = s * 0.1
            g.beginPath(); g.arc(s * 0.32, s * 0.74, s * 0.16, 0, 2 * Math.PI, false); g.fill()
            g.beginPath(); g.moveTo(s * 0.44, s * 0.74); g.lineTo(s * 0.44, s * 0.16); g.lineTo(s * 0.8, s * 0.28); g.stroke()
        }
    }
}
