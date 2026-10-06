// Rin's sign: a little placard on a stick with the name of the program a notification
// came from, which she waves until it has been looked at. (How many, if more than one,
// in a red dot on its corner.)
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool on: false
    property bool still: false   // tucked away: nothing moves
    property string app: ""
    property int count: 1
    property real maxText: 84
    readonly property real fullW: board.width + 4

    width: fullW; height: 26
    // it comes up out of the bar and goes back down
    property real up: on ? 1 : 0
    Behavior on up { NumberAnimation { duration: Theme.reduced ? 0 : 380; easing.type: root.on ? Easing.OutBack : Easing.InCubic } }
    opacity: Math.min(1, up * 2)
    visible: up > 0.01

    Item {
        id: swing
        width: parent.width; height: parent.height
        y: 14 * (1 - root.up)
        transformOrigin: Item.BottomLeft
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
            x: 5; y: board.y + board.height - 2
            width: 3; height: parent.height - y + 2
            radius: 1.5
            color: "#C98A3A"
        }
        Rectangle { // the placard
            id: board
            y: 2
            width: label.width + 12; height: 16
            radius: 5
            color: "#FFD24A"
            border.width: 1.5; border.color: "#FFFFFF"
            Text {
                id: label
                anchors.centerIn: parent
                width: Math.min(implicitWidth, root.maxText)
                elide: Text.ElideRight
                text: root.app !== "" ? root.app : "New"
                color: "#3A2A08"
                font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
            }
        }
        Rectangle { // how many
            visible: root.count > 1
            x: board.width - 7; y: -2
            width: Math.max(11, num.implicitWidth + 5); height: 11; radius: 5.5
            color: "#E0405A"
            border.width: 1; border.color: "#FFFFFF"
            Text {
                id: num
                anchors.centerIn: parent
                text: root.count > 9 ? "9+" : root.count
                color: "#FFFFFF"
                font.family: Theme.sans; font.pixelSize: 7; font.weight: Font.ExtraBold
            }
        }
    }
}
