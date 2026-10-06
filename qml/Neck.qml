// The jelly neck (motion.md, "Picking Kisel up"): while Kisel is drawn out of the
// pill, a neck of the same kisel colour stretches between the pill's edge and the
// mascot (a metaball: 16 px wide at the pill, falling to 3 px as the distance
// grows). At 36 px away it snaps: two droplets (kisel-soft, radii 4 and 3) fall
// 14 px and fade over 300 ms. Drawn as a tapered quad with round ends.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property point from: Qt.point(0, 0)   // on the pill (island coords)
    property point to: Qt.point(0, 0)     // the mascot's centre
    property bool active: false           // stretching
    property real maxDist: 36

    readonly property real dist: Math.hypot(to.x - from.x, to.y - from.y)
    readonly property real t: Math.max(0, Math.min(1, dist / maxDist))
    readonly property real w0: 16 - 13 * t   // 16 px at the pill down to 3 px at the snap
    readonly property real w1: Math.max(3, 18 - 12 * t)
    readonly property real ang: Math.atan2(to.y - from.y, to.x - from.x)
    readonly property point nrm: Qt.point(-Math.sin(ang), Math.cos(ang))

    visible: active && dist > 1
    Shape {
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.kisel
            strokeColor: "transparent"
            startX: root.from.x + root.nrm.x * root.w0 / 2
            startY: root.from.y + root.nrm.y * root.w0 / 2
            PathLine { x: root.to.x + root.nrm.x * root.w1 / 2; y: root.to.y + root.nrm.y * root.w1 / 2 }
            PathLine { x: root.to.x - root.nrm.x * root.w1 / 2; y: root.to.y - root.nrm.y * root.w1 / 2 }
            PathLine { x: root.from.x - root.nrm.x * root.w0 / 2; y: root.from.y - root.nrm.y * root.w0 / 2 }
        }
    }

    // droplets after the snap
    property point dropAt: Qt.point(0, 0)
    property real drop: 0   // 0..1
    function snap(at) {
        dropAt = at
        if (!Theme.reduced) dropAnim.restart()
    }
    NumberAnimation { id: dropAnim; target: root; property: "drop"; from: 0.0001; to: 1; duration: 300; easing.type: Easing.OutQuad }
    Repeater {
        model: [{ r: 4, dx: -4 }, { r: 3, dx: 5 }]
        Rectangle {
            required property var modelData
            width: modelData.r * 2; height: width; radius: modelData.r
            x: root.dropAt.x + modelData.dx - modelData.r
            y: root.dropAt.y + 14 * root.drop - modelData.r
            color: Theme.kiselSoft
            opacity: root.drop > 0 && root.drop < 1 ? 1 - root.drop : 0
            visible: opacity > 0.01
        }
    }
}
