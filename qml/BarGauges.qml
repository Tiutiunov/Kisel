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

    // One gauge: a candy cane in a white-edged tube. The stripes run along it, the faster
    // the busier; a star rides its head; past 90 % the tube and the figure turn red.
    component Meter: Item {
        id: meter
        property string name: ""
        property real value: 0
        readonly property bool hot: value > 0.9
        width: Math.floor((root.room - (Sys.canClean ? 18 + root.spacing : 0) - root.spacing * (root.meters - 1)) / root.meters)
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
                    id: stripes
                    property real shift: 0
                    x: -16 + shift
                    y: -5
                    spacing: 4
                    Repeater {
                        model: Math.ceil(tube.width / 8) + 4
                        Rectangle { width: 4; height: 16; rotation: 30; color: "#FFFFFF"; opacity: 0.38 }
                    }
                    NumberAnimation on shift {
                        from: 0; to: 8
                        duration: Math.max(260, 1500 - meter.value * 1200)
                        loops: Animation.Infinite
                        running: root.on && !Theme.reduced
                    }
                }
            }
            Spark { // the star at the head
                size: 9
                x: cane.x + cane.width - size / 2
                y: (tube.height - size) / 2
                tint: "#FFFFFF"
                RotationAnimation on rotation { running: root.on && !Theme.reduced; from: 0; to: 90; duration: Math.max(500, 2600 - meter.value * 2000); loops: Animation.Infinite }
            }
        }
    }
}
