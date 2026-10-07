// Luka's readings in the collapsed bar: the ping with a light that says how the line is,
// and what is coming in and going out. Nothing here moves by itself. When the line is
// down the readings give way to the news of it, and for a few seconds after it comes
// back, to that. They slide in from the right like Teto's gauges.
import QtQuick
import Kisel.Core

Row {
    id: root
    property bool on: false
    property real room: 174 // the width it may take

    function heat(ms) { return ms < 0 ? "#E0405A" : ms > 250 ? "#E0405A" : ms > 90 ? "#FFE08A" : "#B9DC6B" }
    function speed(v) {
        return v >= 1048576 ? (v / 1048576).toFixed(v >= 10485760 ? 0 : 1) + " MB/s"
            : v >= 1024 ? Math.round(v / 1024) + " KB/s" : "0 KB/s"
    }

    height: 24
    spacing: 8
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    transform: Translate { x: root.on ? 0 : 18; Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }

    readonly property bool news: !Net.online || Net.justBack

    // the light, and the ping (or the news)
    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 9; height: 9; radius: 4.5
            color: root.heat(Net.online ? Net.ping : -1)
            border.width: 1.5; border.color: "#FFFFFF"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !Net.online ? "No connection" : Net.justBack ? "Back online" : Net.ping < 0 ? "..." : Net.ping + " ms"
            color: !Net.online ? "#FF8FA0" : Theme.ink
            font.family: Theme.sans; font.pixelSize: root.news ? 13 : 12; font.weight: Font.ExtraBold
        }
    }
    Reading { visible: !root.news; downward: true; value: Net.down }
    Reading { visible: !root.news; downward: false; value: Net.up }

    // an arrow and a speed
    component Reading: Row {
        id: reading
        property bool downward: true
        property real value: 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Canvas {
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 11
            onPaint: {
                const g = getContext("2d")
                g.reset(); g.strokeStyle = "#F5A3C0"; g.lineWidth = 2; g.lineCap = "round"; g.lineJoin = "round"
                const a = reading.downward ? 9.5 : 1.5, b = reading.downward ? 1.5 : 9.5, h = reading.downward ? 6 : 5
                g.beginPath(); g.moveTo(4, b); g.lineTo(4, a); g.stroke()
                g.beginPath(); g.moveTo(1, h); g.lineTo(4, a); g.lineTo(7, h); g.stroke()
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 50 // (steady: the figures change, the bar does not jiggle)
            text: root.speed(reading.value)
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
    }
}
