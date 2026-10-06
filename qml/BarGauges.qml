// Teto's gauges in the collapsed bar: the processor, the graphics card and the memory as
// short candy ribbons with their figures. They slide in
// from the right like Zundamon's player, and turn red where something is too full. Where
// Mem Reduct is installed a small red key at the end has it clean the memory, and for a
// few seconds after a clean (hers or one Mem Reduct did by itself) the gauges give way
// to what was freed.
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

    readonly property bool said: Sys.justCleaned
    Item { // the news of a clean, in the gauges' place
        visible: root.said
        width: news.implicitWidth; height: 24
        Row {
            id: news
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Spark {
                anchors.verticalCenter: parent.verticalCenter
                size: 11; tint: "#FFE08A"
                RotationAnimation on rotation { running: root.said && !Theme.reduced; from: 0; to: 90; duration: 1600; loops: Animation.Infinite }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Sys.freedGb >= 0.05 ? "Freed " + Sys.freedGb.toFixed(1) + " GB" : "Already tidy"
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
            }
        }
    }
    Meter { visible: !root.said; name: "CPU"; value: Sys.cpu }
    Meter { visible: Sys.hasGpu && !root.said; name: "GPU"; value: Sys.gpu }
    Meter { visible: !root.said; name: "RAM"; value: Sys.mem }

    Item { // the Clean key
        visible: Sys.canClean
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18
        Rectangle {
            anchors.fill: parent
            radius: 9
            color: Sys.cleaning ? Theme.surface3 : "#E0405A"
            border.width: 1.5; border.color: "#FFFFFF"
        }
        Spark {
            anchors.centerIn: parent
            size: 9; tint: "#FFFFFF"
            RotationAnimation on rotation { running: Sys.cleaning; from: 0; to: 360; duration: 700; loops: Animation.Infinite }
        }
        scale: cleanArea.pressed ? 0.85 : cleanArea.containsMouse ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        MouseArea {
            id: cleanArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // (a MouseArea, so the click stays here and does not open the card)
            onClicked: { Hub.poke(); Sys.clean() }
        }
    }

    component Meter: Item {
        id: meter
        property string name: ""
        property real value: 0
        width: Math.floor((root.room - (Sys.canClean ? 18 + root.spacing : 0) - root.spacing * (root.meters - 1)) / root.meters)
        height: 24
        Text {
            id: label
            y: 2
            text: meter.name
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 8; font.weight: Font.ExtraBold
        }
        Text {
            anchors.right: parent.right
            y: -1
            text: Math.round(meter.value * 100) + "%"
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
        Rectangle {
            y: 15
            width: parent.width; height: 7; radius: 3.5
            color: "#2b2430"
            border.width: 1; border.color: "#FFFFFF"
            Rectangle {
                x: 1; y: 1
                height: 5; radius: 2.5
                width: Math.max(5, (parent.width - 2) * Math.min(1, meter.value))
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                color: root.heat(meter.value)
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }
}
