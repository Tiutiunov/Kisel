// Teto's Home: how the computer is doing. It takes the whole of Home's place
// (494 x 138), in the sticker style of Zundamon's player and in Teto's red.
//
// Round gauges with a white edge for the processor, the graphics card and the memory; a row of candy bars with the processor's last minute; and a line from
// Teto herself, who has an opinion about all of it. Where Mem Reduct is installed there
// is a Clean key beside her line: it has Mem Reduct clean the memory, and she reports
// what that freed.
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
        : Sys.cleaning ? "Sweeping the memory. Stand back."
        : Sys.justCleaned ? (Sys.freedGb >= 0.05 ? "Freed " + Sys.freedGb.toFixed(1) + " GB. You are welcome." : "Nothing much to free. It was tidy already.")
        : Sys.worry === "mem" ? "The memory is full. Close something, will you?"
        : Sys.worry === "cpu" ? "The processor is flat out. What are you running?"
        : Sys.gpu > 0.85 ? "The graphics card is flat out. Playing, are we?"
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
        Gauge { visible: Sys.hasGpu; value: Sys.gpu; name: "GPU" }
        Gauge { value: Sys.mem; name: "Memory"; note: Sys.memUsedGb.toFixed(1) + " / " + Math.round(Sys.memTotalGb) + " GB" }
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
            id: say
            y: 70
            width: side.width - (cleanKey.visible ? cleanKey.width + 6 : 0)
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

    // the Clean key: Mem Reduct does the cleaning
    Rectangle {
        id: cleanKey
        visible: Sys.canClean
        x: side.x + side.width - width
        y: side.y + 70
        width: 62; height: 42
        radius: 12
        color: Sys.cleaning ? Theme.surface3 : root.red
        border.width: 2; border.color: "#FFFFFF"
        opacity: Motion.rise(root.age, 3)
        scale: cleanTap.pressed ? 0.92 : cleanHover.hovered && !Sys.cleaning ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Clean memory"
        Column {
            anchors.centerIn: parent
            spacing: 1
            BroomGlyph { anchors.horizontalCenter: parent.horizontalCenter; size: 15; opacity: Sys.cleaning ? 0.5 : 1 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Clean"
                color: "#FFFFFF"
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
            }
        }
        HoverHandler { id: cleanHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: cleanTap; onTapped: Sys.clean() }
        Keys.onReturnPressed: Sys.clean()
        Keys.onSpacePressed: Sys.clean()
    }

    // a round gauge: a white-edged disc, a ring that fills, the figure in the middle
    component Gauge: Item {
        id: gauge
        property real value: 0
        property string name: ""
        property string note: ""
        width: 78; height: 114
        Canvas {
            id: ring
            width: 78; height: 78
            property real shown: gauge.value
            Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onShownChanged: requestPaint()
            property color tint: root.heat(gauge.value)
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
