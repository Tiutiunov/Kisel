// A check mark that draws itself: `progress` runs 0..1 along the stroke
// (the "success" and "step done" moves, 180 ms).
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property real size: 16
    property real progress: 1
    property color color: "white"
    property real strokeWidth: 1.6

    width: size
    height: size

    // 24-unit grid: (5, 12.5) -> (9.5, 17) -> (19, 7.5)
    readonly property real l1: 6.36 // first leg
    readonly property real l2: 13.43 // second leg
    readonly property real run: progress * (l1 + l2)
    readonly property real t1: Math.min(1, run / l1)
    readonly property real t2: Math.max(0, Math.min(1, (run - l1) / l2))

    Shape {
        width: 24; height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        visible: root.progress > 0
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 5; startY: 12.5
            PathLine { x: 5 + 4.5 * root.t1; y: 12.5 + 4.5 * root.t1 }
            PathLine { x: 9.5 + 9.5 * root.t2; y: 17 - 9.5 * root.t2 }
        }
    }
}
