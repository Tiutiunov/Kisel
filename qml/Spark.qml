// A four-pointed star, for whatever twinkles.
import QtQuick

Canvas {
    id: spark
    property real size: 10
    property color tint: "#FFFFFF"
    width: size; height: size
    onTintChanged: requestPaint()
    onPaint: {
        const g = getContext("2d"), s = size, c = s / 2
        g.reset(); g.fillStyle = tint
        g.beginPath(); g.moveTo(c, 0)
        g.quadraticCurveTo(c, c, s, c); g.quadraticCurveTo(c, c, c, s)
        g.quadraticCurveTo(c, c, 0, c); g.quadraticCurveTo(c, c, c, 0)
        g.fill()
    }
}
