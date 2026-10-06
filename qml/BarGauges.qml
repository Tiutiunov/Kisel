// Teto's gauges in the collapsed bar: the processor and the memory as two short candy
// ribbons with their figures (and the battery's figure if there is one). They slide in
// from the right like Zundamon's player, and turn red where something is too full.
import QtQuick
import Kisel.Core

Row {
    id: root
    property bool on: false
    property real room: 174 // the width it may take

    function heat(v) { return v > 0.9 ? "#E0405A" : v > 0.7 ? "#FFE08A" : "#B9DC6B" }

    height: 24
    spacing: 8
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    transform: Translate { x: root.on ? 0 : 18; Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }

    Meter { name: "CPU"; value: Sys.cpu }
    Meter { name: "RAM"; value: Sys.mem }
    Text {
        visible: Sys.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(Sys.battery * 100) + "%"
        color: !Sys.charging && Sys.battery < 0.15 ? "#E0405A" : Theme.inkMuted
        font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
    }

    component Meter: Item {
        id: meter
        property string name: ""
        property real value: 0
        width: Math.floor((root.room - (Sys.hasBattery ? 40 : 8)) / 2)
        height: 24
        Text {
            id: label
            text: meter.name
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
        }
        Text {
            anchors.right: parent.right
            y: -1
            text: Math.round(meter.value * 100) + "%"
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
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
