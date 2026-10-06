// Rin's sign: a little placard on a stick with the name of the program a notification
// came from, which she waves until it has been looked at. (How many, if more than one,
// in a red dot on its corner.) With notifications from several programs the placard
// turns over every few seconds and shows them one after another, each with its own count. It is held up out of the bar, past its free edge, so the
// bar's own contents stay where they are: above a bar on the bottom of the screen, and
// hanging below one on the top (`flip`).
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool on: false
    property bool still: false   // tucked away: nothing moves
    property string app: ""
    property int count: 1
    property var apps: []        // every program with one waiting, newest first
    property var counts: []      // ...and how many each has
    property int turn: 0
    readonly property bool many: apps.length > 1
    readonly property string shownApp: many ? apps[turn % apps.length] : app
    readonly property int shownCount: many ? (counts[turn % apps.length] || 1) : count
    onAppsChanged: turn = 0 // (the newest first)
    Timer { interval: 2600; repeat: true; running: root.on && root.many && !root.still; onTriggered: Theme.reduced ? root.turn++ : turnOver.restart() }
    SequentialAnimation {
        id: turnOver
        NumberAnimation { target: flipScale; property: "xScale"; to: 0; duration: 130; easing.type: Easing.InQuad }
        ScriptAction { script: root.turn++ }
        NumberAnimation { target: flipScale; property: "xScale"; to: 1; duration: 200; easing.type: Easing.OutBack }
    }
    property real maxText: 84
    property bool flip: false    // hangs down instead of standing up
    readonly property real fullW: board.width + 4

    width: fullW; height: 30
    // it comes up out of the bar and goes back down
    property real up: on ? 1 : 0
    Behavior on up { NumberAnimation { duration: Theme.reduced ? 0 : 380; easing.type: root.on ? Easing.OutBack : Easing.InCubic } }
    opacity: Math.min(1, up * 2)
    visible: up > 0.01

    Item {
        id: swing
        width: parent.width; height: parent.height
        y: (root.flip ? -14 : 14) * (1 - root.up)
        transformOrigin: root.flip ? Item.TopLeft : Item.BottomLeft
        SequentialAnimation on rotation {
            running: root.on && !root.still && !Theme.reduced
            loops: Animation.Infinite
            NumberAnimation { to: 5; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: -4; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: 5; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: -4; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 260; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 1500 }
        }
        Rectangle { // the stick
            x: 5; y: root.flip ? 0 : board.y + board.height - 2
            width: 3; height: root.flip ? board.y + 2 : parent.height - y
            radius: 1.5
            color: "#C98A3A"
        }
        Rectangle { // the placard
            id: board
            y: root.flip ? parent.height - height - 2 : 2
            width: label.width + 12; height: 16
            radius: 5
            color: "#FFD24A"
            border.width: 1.5; border.color: "#FFFFFF"
            transform: Scale { id: flipScale; origin.x: board.width / 2 }
            Text {
                id: label
                anchors.centerIn: parent
                width: Math.min(implicitWidth, root.maxText)
                elide: Text.ElideRight
                text: root.shownApp !== "" ? root.shownApp : "New"
                color: "#3A2A08"
                font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
            }
        }
        Rectangle { // how many
            visible: root.shownCount > 1
            x: board.width - 7; y: board.y - 4
            width: Math.max(11, num.implicitWidth + 5); height: 11; radius: 5.5
            color: "#E0405A"
            border.width: 1; border.color: "#FFFFFF"
            Text {
                id: num
                anchors.centerIn: parent
                text: root.shownCount > 9 ? "9+" : root.shownCount
                color: "#FFFFFF"
                font.family: Theme.sans; font.pixelSize: 7; font.weight: Font.ExtraBold
            }
        }
    }
}
