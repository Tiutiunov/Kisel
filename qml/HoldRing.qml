// The hold progress: a 2 px kisel ring that draws itself clockwise around the
// mascot over 350 ms (OutQuad). Letting go early cancels it with a small recoil;
// at 350 ms it pops (scale 1.4, fade 200 ms). With reduce motion the ring still
// fills: it is progress, not decoration.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property real size: 44
    property real progress: 0     // 0..1
    property bool popped: false

    width: size; height: size
    opacity: popped ? 0 : (progress > 0 ? 1 : 0)
    scale: popped && !Theme.reduced ? 1.4 : 1
    visible: opacity > 0.01
    Behavior on opacity { enabled: root.popped; NumberAnimation { duration: 200 } }
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.kisel
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.width / 2 - 1; radiusY: root.height / 2 - 1
                startAngle: -90                        // from the top...
                sweepAngle: 360 * root.progress        // ...clockwise
            }
        }
    }
}
