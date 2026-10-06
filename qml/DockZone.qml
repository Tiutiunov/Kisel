// The zone preview shown while Kisel is carried near an edge (motion.md, "Edge
// zones"): a kisel-soft half-round, 200 long and 40 deep, shaped like the dock
// it will become (top: hanging down; bottom: rising up; left and right: turned
// sideways), centred on the pointer's position along the edge. As the distance
// falls from 96 to 20 px it rises from 18 to 45 percent and leans toward Kisel.
// With reduce motion it only fades.
import QtQuick

Item {
    id: root
    property string edge: "top"
    property real along: 0      // pointer position along the edge, screen px
    property real distance: 96  // pointer's distance from the edge
    property bool active: false
    property real screenW: 1920
    property real screenH: 1080
    property bool tick: false   // brightens once when it snaps to the edge's centre
    // Everything below is in screen coordinates; the host places this item at the screen's origin.

    width: screenW
    height: screenH
    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }

    readonly property real pull: Math.max(0, Math.min(1, (96 - distance) / 76))
    property real alpha: 0.18 + 0.27 * pull + (tick ? 0.15 : 0)
    Behavior on alpha { NumberAnimation { duration: 60 } }

    Item {
        id: zone
        // 200 long, 40 deep, flat side up; rotated per edge about its own centre so the flat
        // side lies on the wall, and centred on the pointer's position along the edge
        width: 200; height: 40
        readonly property bool horizontal: root.edge === "top" || root.edge === "bottom"
        readonly property real cx: horizontal ? root.along : (root.edge === "left" ? 20 : root.screenW - 20)
        readonly property real cy: horizontal ? (root.edge === "top" ? 20 : root.screenH - 20) : root.along
        // as the edge pulls the zone leans a little toward Kisel (away from the wall)
        readonly property real away: 6 * root.pull * (root.edge === "top" || root.edge === "left" ? 1 : -1)
        x: cx - width / 2 + (horizontal ? 0 : away)
        y: cy - height / 2 + (horizontal ? away : 0)
        rotation: root.edge === "top" ? 0 : root.edge === "bottom" ? 180 : root.edge === "left" ? -90 : 90
        opacity: root.alpha
        Rectangle {
            // a disc cut at its centre: the flat side sits on the edge
            anchors.fill: parent
            color: Theme.kiselSoft
            topLeftRadius: 0; topRightRadius: 0
            bottomLeftRadius: 20; bottomRightRadius: 20
        }
    }
}
