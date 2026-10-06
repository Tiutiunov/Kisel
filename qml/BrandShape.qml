// The cover's seven shapes (motion.md, "Brand shapes in motion"). Only these
// shapes, in these token colours, at these proportions; no gradients, shadows
// or outlines. They show through code (not the SVG files) so they follow the theme.
//
//   bigPill    240 x 120  kisel        the hero
//   halfRound  200 x 100  amber        a disc cut at its centre; attention
//   disc       112 x 112  mint         success
//   slab       144 x 136  surface-3    a surface
//   smallPill   64 x  32  kisel-deep   confetti, progress tip
//   softDisc    80 x  80  kisel-soft   confetti, ripple
//   dotGrid     4 x 2 dots, 16 px pitch, `line`
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string kind: "bigPill"

    readonly property var natural: ({
        bigPill: Qt.size(240, 120), halfRound: Qt.size(200, 100), disc: Qt.size(112, 112),
        slab: Qt.size(144, 136), smallPill: Qt.size(64, 32), softDisc: Qt.size(80, 80), dotGrid: Qt.size(54, 22)
    })
    width: natural[kind].width
    height: natural[kind].height
    transformOrigin: Item.Center

    Rectangle {
        visible: root.kind === "bigPill" || root.kind === "smallPill" || root.kind === "disc" || root.kind === "softDisc" || root.kind === "slab"
        anchors.fill: parent
        radius: root.kind === "slab" ? Theme.radiusMd : Math.min(width, height) / 2
        color: root.kind === "bigPill" ? Theme.kisel
             : root.kind === "smallPill" ? Theme.kiselDeep
             : root.kind === "disc" ? Theme.mint
             : root.kind === "softDisc" ? Theme.kiselSoft
             : Theme.surface3
    }

    // half-round: flat edge on top, dome below
    Shape {
        visible: root.kind === "halfRound"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: Theme.amber
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathArc { x: 0; y: 0; radiusX: root.width / 2; radiusY: root.height; direction: PathArc.Clockwise }
        }
    }

    Repeater {
        model: root.kind === "dotGrid" ? 8 : 0
        Rectangle {
            required property int index
            x: (index % 4) * 16; y: Math.floor(index / 4) * 16
            width: 6; height: 6; radius: 3
            color: Theme.line
        }
    }
}
