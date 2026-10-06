// Teto's Home: how the computer is doing. It takes the whole of Home's place
// (494 x 138), in the sticker style of Zundamon's player and in Teto's red.
//
// Round gauges with a white edge for the processor, the memory and (if there is one)
// the battery; a row of candy bars with the processor's last minute; and a line from
// Teto herself, who has an opinion about all of it.
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    readonly property color red: "#E0405A"
    readonly property color pink: "#FF9EBB"
    readonly property color lemon: "#FFE08A"
    function pct(v) { return Math.round(v * 100) + "%" }
    // how full a gauge is decides its colour: calm, busy, too much
    function heat(v) { return v > 0.9 ? root.red : v > 0.7 ? root.lemon : "#B9DC6B" }

    readonly property string line: !Sys.available ? "I cannot see this machine from here."
        : Sys.worry === "battery" ? "The battery is nearly flat. Plug it in. Now."
        : Sys.worry === "mem" ? "The memory is full. Close something, will you?"
        : Sys.worry === "cpu" ? "The processor is flat out. What are you running?"
        : Sys.cpu > 0.6 ? "Busy, but nothing I cannot handle."
        : Sys.mem > 0.8 ? "A lot is open. Not that I am counting."
        : "All quiet. Thanks to me, obviously."

    Row {
        id: gauges
        x: 8; y: 12
        spacing: 14
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        Gauge { value: Sys.cpu; name: "CPU" }
        Gauge { value: Sys.mem; name: "Memory"; note: Sys.memUsedGb.toFixed(1) + " / " + Math.round(Sys.memTotalGb) + " GB" }
        Gauge { visible: Sys.hasBattery; value: Sys.battery; name: Sys.charging ? "Charging" : "Battery"; calm: true }
    }

    Item {
        id: side
        x: gauges.x + gauges.width + 18
        y: 12
        width: parent.width - x - 6
        height: parent.height - 24

        Row {
            spacing: 6
            opacity: Motion.rise(root.age, 1)
            transform: Translate { y: Motion.lift(root.age, 1) }
            Spark { anchors.verticalCenter: parent.verticalCenter; size: 11; tint: root.red
                RotationAnimation on rotation { running: root.visible && !Theme.reduced; from: 0; to: 90; duration: 3000; loops: Animation.Infinite } }
            Text {
                text: "The last minute"
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }

        // the processor's last minute, one bar a reading
        Row {
            id: bars
            y: 20
            height: 38
            spacing: 2
            opacity: Motion.rise(root.age, 2)
            Repeater {
                model: Sys.history
                Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.max(2, (side.width - 35 * 2) / 36)
                    height: 4 + modelData * 34
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    radius: width / 2
                    anchors.bottom: parent.bottom
                    color: root.heat(modelData)
                    opacity: 0.35 + 0.65 * (index / 35)
                }
            }
        }

        // what Teto makes of it
        Rectangle {
            y: 70
            width: side.width
            height: 42
            radius: 12
            color: Qt.rgba(root.red.r, root.red.g, root.red.b, Sys.strain ? 0.3 : 0.14)
            border.width: 2
            border.color: Qt.rgba(root.red.r, root.red.g, root.red.b, Sys.strain ? 1 : 0.45)
            opacity: Motion.rise(root.age, 3)
            transform: Translate { y: Motion.lift(root.age, 3) }
            Text {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                text: root.line
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                lineHeight: 14; lineHeightMode: Text.FixedHeight
            }
        }
    }

    // a round gauge: a white-edged disc, a ring that fills, the figure in the middle
    component Gauge: Item {
        id: gauge
        property real value: 0
        property string name: ""
        property string note: ""
        property bool calm: false // a full battery is good news: it is not coloured by how full it is
        width: 78; height: 114
        Canvas {
            id: ring
            width: 78; height: 78
            property real shown: gauge.value
            Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onShownChanged: requestPaint()
            property color tint: gauge.calm ? (gauge.value < 0.15 ? root.red : gauge.value < 0.3 ? root.lemon : "#B9DC6B") : root.heat(gauge.value)
            onTintChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"), c = 39
                g.reset()
                g.lineCap = "round"
                g.strokeStyle = "#FFFFFF"; g.lineWidth = 12
                g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                g.strokeStyle = "#2b2430"; g.lineWidth = 8
                g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                if (shown > 0.005) {
                    g.strokeStyle = tint; g.lineWidth = 8
                    g.beginPath(); g.arc(c, c, 31, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, shown), false); g.stroke()
                }
            }
        }
        Text {
            anchors.horizontalCenter: ring.horizontalCenter
            anchors.verticalCenter: ring.verticalCenter
            text: root.pct(gauge.value)
            color: Theme.ink
            font.family: Theme.display; font.pixelSize: 17; font.weight: Font.Bold
        }
        Text {
            y: 82
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: gauge.name
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
        }
        Text {
            y: 98
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: gauge.note
            visible: gauge.note !== ""
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.DemiBold
        }
    }
}
