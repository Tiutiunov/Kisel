// A 160 degree arc turning once per 800 ms, linear (motion.md: spinners).
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color color: Theme.info
    property int size: 16
    width: size
    height: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.size / 2 - 1.5
                radiusY: root.size / 2 - 1.5
                startAngle: 0
                sweepAngle: 160
            }
        }
        RotationAnimator on rotation {
            from: 0; to: 360; duration: 800
            loops: Animation.Infinite
            running: root.visible
        }
    }
}
