// Teto's gauges in the collapsed bar: the processor, the graphics card and the memory as
// short candy canes with their figures. Nothing here moves by itself: the canes only
// grow and shrink with what they measure (and the gauges and the news trade places). They slide in
// from the right like Zundamon's player, and turn red where something is too full. A small
// red key at the end cleans the memory, and for a few seconds after a clean the gauges
// give way to what was freed.
import QtQuick
import Kisel.Core

Row {
    id: root
    property bool on: false
    property real room: 174 // the width it may take

    function heat(v) { return v > 0.9 ? "#E0405A" : v > 0.7 ? "#FFE08A" : "#B9DC6B" }

    height: 24
    spacing: 6
    readonly property int meters: Sys.hasGpu ? 3 : 2
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    transform: Translate { x: root.on ? 0 : 18; Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }

    // The gauges and the news of a clean share one place and trade it: the gauges lift
    // away and fade as the news rises into their place with its star popping, and back.
    readonly property bool said: Sys.justCleaned
    property real told: said ? 1 : 0
    Behavior on told { NumberAnimation { duration: Theme.reduced ? 0 : 460; easing.type: Easing.InOutCubic } }
    readonly property real keyW: Sys.canClean ? 18 + spacing : 0
    Item {
        width: root.room - root.keyW; height: 24
        Row { // the gauges
            spacing: root.spacing
            y: -9 * root.told
            opacity: 1 - Math.min(1, root.told * 2) // (gone before the news shows)
            visible: opacity > 0.01
            Meter { name: "CPU"; value: Sys.cpu }
            Meter { visible: Sys.hasGpu; name: "GPU"; value: Sys.gpu }
            Meter { name: Tr.t("RAM"); value: Sys.mem }
        }
        Row { // the news of a clean, in the gauges' place
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 + 9 * (1 - root.told)
            spacing: 5
            opacity: Math.max(0, root.told * 2 - 1)
            visible: opacity > 0.01
            Spark {
                anchors.verticalCenter: parent.verticalCenter
                size: 11; tint: "#FFE08A"
                scale: root.said ? 1 : 0
                Behavior on scale { NumberAnimation { duration: Theme.reduced ? 0 : 520; easing.type: Easing.OutBack; easing.overshoot: 3 } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Sys.freedGb >= 0.05 ? Tr.t("Freed ") + Sys.freedGb.toFixed(1) + Tr.t(" GB") : Tr.t("Already tidy")
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
            }
        }
    }

    Item { // the Clean key: a red key with a broom on it
        visible: Sys.canClean
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 22
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: Sys.cleaning ? Theme.surface3 : cleanArea.containsMouse ? "#F0566E" : "#E0405A"
            border.width: 1.5; border.color: "#FFFFFF"
        }
        BroomGlyph { anchors.centerIn: parent; size: 12; opacity: Sys.cleaning ? 0.5 : 1 }
        scale: cleanArea.pressed ? 0.9 : 1
        MouseArea {
            id: cleanArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // (a MouseArea, so the click stays here and does not open the card)
            onClicked: { Hub.poke(); Sys.clean() }
        }
    }

    // One gauge: a striped candy cane in a white-edged tube; past 90 % the tube and the
    // figure turn red.
    component Meter: Item {
        id: meter
        property string name: ""
        property real value: 0
        readonly property bool hot: value > 0.9
        width: Math.floor((root.room - root.keyW - root.spacing * (root.meters - 1)) / root.meters)
        height: 24
        Text {
            y: 1
            text: meter.name
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 8; font.weight: Font.ExtraBold
        }
        Text {
            anchors.right: parent.right
            y: -2
            text: Math.round(meter.value * 100) + "%"
            color: meter.hot ? "#FF8FA0" : Theme.ink
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
        Rectangle {
            id: tube
            y: 12
            width: parent.width; height: 11; radius: 5.5
            color: "#2b2430"
            border.width: 1.5
            border.color: meter.hot ? "#E0405A" : "#FFFFFF"
            Item {
                id: cane
                x: 2.5; y: 2.5
                height: 6
                width: Math.max(6, (tube.width - 5) * Math.min(1, meter.value))
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                clip: true
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: root.heat(meter.value)
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
                Row {
                    x: -16
                    y: -5
                    spacing: 4
                    Repeater {
                        model: Math.ceil(tube.width / 8) + 4
                        Rectangle { width: 4; height: 16; rotation: 30; color: "#FFFFFF"; opacity: 0.38 }
                    }
                }
            }
        }
    }
}
