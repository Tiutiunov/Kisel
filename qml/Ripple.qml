// A ring, 2 px kisel-soft (or kisel), growing 24 to 56 px over 280 ms (OutCubic)
// while it fades. Fire it with go(x, y). Reduced motion: it only fades in place.
import QtQuick

Item {
    id: root
    property color color: Theme.kiselSoft
    property real cx: 0
    property real cy: 0
    property real r: 24
    property real life: 0

    function go(x, y) { cx = x; cy = y; anim.restart() }

    Rectangle {
        x: root.cx - width / 2; y: root.cy - height / 2
        width: root.r * 2; height: width; radius: root.r
        color: "transparent"
        border.width: 2
        border.color: root.color
        opacity: root.life > 0 && root.life < 1 ? 1 - root.life : 0
        visible: opacity > 0.01
    }
    NumberAnimation {
        id: anim
        target: root; property: "life"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic
    }
    onLifeChanged: r = Theme.reduced ? 24 : 24 + 32 * life
}
