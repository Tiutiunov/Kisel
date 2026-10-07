// Luka's Home: how the connection is doing. It takes the whole of Home's place
// (494 x 138), in the sticker style of Teto's monitor and in Luka's pink.
//
// A round gauge with the ping, two tiles with what is coming in and going out, a row of
// candy bars with the last minute of pings (a lost one is a red stub), and a line from
// Luka herself, who takes it all calmly.
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    readonly property color pink: "#F5A3C0"
    readonly property color deep: "#D9779D"
    readonly property color red: "#E0405A"
    readonly property color lemon: "#FFE08A"
    readonly property color mint: "#B9DC6B"
    // how late an answer is decides its colour: quick, slowish, late
    function heat(ms) { return ms < 0 ? root.red : ms > 250 ? root.red : ms > 90 ? root.lemon : root.mint }
    // bytes a second, in words
    function speed(v) {
        return v >= 1048576 ? (v / 1048576).toFixed(v >= 10485760 ? 0 : 1) + Tr.t(" MB/s")
            : v >= 1024 ? Math.round(v / 1024) + Tr.t(" KB/s") : Tr.t("0 KB/s")
    }
    // bytes, in words
    function amount(v) {
        return v >= 1073741824 ? (v / 1073741824).toFixed(2) + Tr.t(" GB")
            : v >= 1048576 ? Math.round(v / 1048576) + Tr.t(" MB") : Math.round(v / 1024) + Tr.t(" KB")
    }

    readonly property string line: !Net.available ? Tr.t("I cannot see the connection from here.")
        : !Net.online ? Tr.t("The line is down. It will come back; they always do.")
        : Net.justBack ? Tr.t("And we are back. No need to fuss.")
        : Net.slow ? Tr.t("Answers are coming late. Something is in the way.")
        : Net.downloading ? Tr.t("Something is coming down: ") + root.amount(Net.fetched) + Tr.t(" so far. I am watching it.")
        : Net.justFetched ? Tr.t("That is the download done: ") + root.amount(Net.fetched) + Tr.t(" came in.")
        : Net.down > 5242880 ? Tr.t("A lot is coming in. Downloading something nice?")
        : Net.up > 2097152 ? Tr.t("A lot is going out. Sharing, are we?")
        : Net.ping > 90 ? Tr.t("A little slow, but steady.")
        : Tr.t("A quiet line. Just the way I like it.")

    Row {
        id: left
        x: 8; y: 12
        spacing: 12
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }

        // the ping: a white-edged ring that fills as answers get later
        Item {
            width: 78; height: 114
            Canvas {
                id: ring
                width: 78; height: 78
                property real shown: Net.online && Net.ping >= 0 ? Math.min(1, Net.ping / 300) : 1
                Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                onShownChanged: requestPaint()
                property color tint: root.heat(Net.online ? Net.ping : -1)
                onTintChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d"), c = 39
                    g.reset()
                    g.lineCap = "round"
                    g.strokeStyle = "#FFFFFF"; g.lineWidth = 12
                    g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                    g.strokeStyle = "#2b2430"; g.lineWidth = 8
                    g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                    g.strokeStyle = tint; g.lineWidth = 8
                    g.beginPath(); g.arc(c, c, 31, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.04, shown), false); g.stroke()
                }
            }
            Text {
                anchors.horizontalCenter: ring.horizontalCenter
                anchors.verticalCenter: ring.verticalCenter
                anchors.verticalCenterOffset: Net.online ? -4 : 0
                text: !Net.online ? "off" : Net.ping < 0 ? "..." : Net.ping
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 19; font.weight: Font.Bold
            }
            Text {
                visible: Net.online
                anchors.horizontalCenter: ring.horizontalCenter
                y: 46
                text: "ms"
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
            }
            Text {
                y: 82
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("Ping")
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
            }
        }

        // what is coming in, and what is going out
        Column {
            y: 2
            spacing: 8
            Flow1 { name: Net.downloading ? Tr.t("Downloading") : Tr.t("Down"); value: Net.down; downward: true; lit: Net.downloading }
            Flow1 { name: Tr.t("Up"); value: Net.up; downward: false }
        }
    }

    Item {
        id: side
        x: left.x + left.width + 16
        y: 12
        width: parent.width - x - 6
        height: parent.height - 24

        Row {
            spacing: 6
            opacity: Motion.rise(root.age, 1)
            transform: Translate { y: Motion.lift(root.age, 1) }
            Spark { anchors.verticalCenter: parent.verticalCenter; size: 11; tint: root.deep }
            Text {
                text: Tr.t("The last minute")
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }

        // the last minute of pings, one bar an answer
        Row {
            y: 20
            height: 38
            spacing: 3
            opacity: Motion.rise(root.age, 2)
            Repeater {
                model: Net.history
                Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.max(3, (side.width - 29 * 3) / 30)
                    height: modelData < 0 ? 5 : 6 + Math.min(1, modelData / 300) * 32
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    radius: width / 2
                    anchors.bottom: parent.bottom
                    color: root.heat(modelData)
                    opacity: 0.35 + 0.65 * (index / 29)
                }
            }
        }

        // what Luka makes of it
        Rectangle {
            y: 70
            width: side.width
            height: 42
            radius: 12
            readonly property color tone: Net.trouble ? root.red : root.pink
            color: Qt.rgba(tone.r, tone.g, tone.b, Net.trouble ? 0.3 : 0.14)
            border.width: 2
            border.color: Qt.rgba(tone.r, tone.g, tone.b, Net.trouble ? 1 : 0.5)
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

    // a tile: an arrow, the direction's name, the speed
    component Flow1: Rectangle {
        id: tile
        property string name: ""
        property real value: 0
        property bool downward: true
        property bool lit: false // (a download is on: the tile fills with her pink)
        width: 104; height: 48
        radius: 12
        color: Qt.rgba(root.pink.r, root.pink.g, root.pink.b, lit ? 0.5 : 0.14)
        Behavior on color { ColorAnimation { duration: 300 } }
        border.width: 2; border.color: "#FFFFFF"
        Canvas { // the arrow, drawn
            x: 10; y: 13
            width: 16; height: 22
            onPaint: {
                const g = getContext("2d")
                g.reset(); g.strokeStyle = root.pink; g.lineWidth = 3; g.lineCap = "round"; g.lineJoin = "round"
                const a = tile.downward ? 19 : 3, b = tile.downward ? 3 : 19, h = tile.downward ? 12 : 10
                g.beginPath(); g.moveTo(8, b); g.lineTo(8, a); g.stroke()
                g.beginPath(); g.moveTo(2, h); g.lineTo(8, a); g.lineTo(14, h); g.stroke()
            }
        }
        Text {
            x: 34; y: 7
            text: tile.name
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
        Text {
            x: 34; y: 21
            text: root.speed(tile.value)
            color: Theme.ink
            font.family: Theme.display; font.pixelSize: 14; font.weight: Font.Bold
        }
    }
}
