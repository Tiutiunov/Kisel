// Slider over whole steps: the thumb follows the pointer and settles on the nearest
// step in 140 ms; the filled part of the track is kisel.
import QtQuick

FocusScope {
    id: root
    property int from: 0
    property int to: 10
    property int value: 0
    property string label: ""
    signal moved(int value)

    implicitWidth: row.implicitWidth
    implicitHeight: 28
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: label

    function set(v) {
        v = Math.max(from, Math.min(to, Math.round(v)))
        if (v === value) return
        value = v
        moved(v)
    }

    Row {
        id: row
        spacing: Theme.space3
        anchors.verticalCenter: parent.verticalCenter
        Item {
            id: track
            width: 200; height: 26
            anchors.verticalCenter: parent.verticalCenter
            readonly property real span: width - thumb.width
            Rectangle {
                y: 10; width: parent.width; height: 6; radius: 3
                color: Theme.surface3
                border.width: 1
                border.color: root.activeFocus ? Theme.kisel : Theme.line
            }
            Rectangle {
                y: 10; height: 6; radius: 3
                width: thumb.x + thumb.width / 2
                color: Theme.kisel
            }
            Rectangle {
                id: thumb
                y: 3; width: 20; height: 20; radius: 10
                x: track.span * (root.value - root.from) / Math.max(1, root.to - root.from)
                color: Theme.ink
                Behavior on x { NumberAnimation { duration: Theme.tFast; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true // the settings page scrolls; a drag here is ours
                cursorShape: Qt.PointingHandCursor
                function pick(m) { root.set(root.from + (m.x - 4 - thumb.width / 2) / track.span * (root.to - root.from)) }
                onPressed: (m) => { root.forceActiveFocus(); pick(m) }
                onPositionChanged: (m) => pick(m)
            }
        }
        Text {
            visible: root.label !== ""
            text: root.label
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Keys.onLeftPressed: set(value - 1)
    Keys.onRightPressed: set(value + 1)
}
