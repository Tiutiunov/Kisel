// The collapsed bar on a side edge: what the bar says along the top or the bottom, stood
// on end under those at its head. Claude's state is a disc with its words running up the
// bar; Zundamon's player is the cover over three keys; Teto's gauges and Luka's readings
// are figures one under another. One of them shows at a time, as in the lying bar, and
// they trade places by fading.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool on: false
    property string chip: ""    // the disc: "" | work | think | needs | done | failed
    property string label: ""   // the words under it
    property bool faint: false
    property bool player: false
    property bool gauges: false
    property bool net: false
    property bool still: false  // tucked away: nothing moves
    width: 32

    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 120 } }

    readonly property bool own: player || gauges || net

    // ---- Claude: the disc, and the words reading up the bar --------------------------
    PillDisc {
        id: disc
        x: (root.width - width) / 2
        kind: root.own ? "" : root.chip
    }
    Item {
        id: words
        readonly property real lead: disc.kind !== "" ? 30 : 0
        y: lead
        width: root.width
        height: root.height - lead
        opacity: root.own || root.label === "" ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            width: words.height
            rotation: -90
            horizontalAlignment: Text.AlignRight // (the words start at the head's end)
            text: root.label
            elide: Text.ElideRight
            color: root.faint ? Theme.inkFaint : Theme.ink
            Behavior on color { ColorAnimation { duration: 160 } }
            font.family: Theme.sans
            font.pixelSize: 13
            font.weight: Font.ExtraBold
        }
    }

    // ---- Zundamon: the cover, and the keys under it ----------------------------------
    Column {
        id: tune
        width: root.width
        spacing: 3
        opacity: root.player ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        readonly property bool live: root.on && root.player && Media.playing && !Theme.reduced && !root.still
        Item {
            width: 22; height: 26
            anchors.horizontalCenter: parent.horizontalCenter
            Item {
                width: 22; height: 22
                rotation: -5
                Rectangle { anchors.fill: parent; radius: 4; color: "#FFFFFF" }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 2
                    color: Theme.surface3
                    clip: true
                    Image { anchors.fill: parent; source: Media.art; fillMode: Image.PreserveAspectCrop; visible: Media.art !== ""; asynchronous: true }
                    PlayGlyph { anchors.centerIn: parent; kind: "note"; size: 10; tint: Theme.inkFaint; visible: Media.art === "" }
                }
            }
            Spark {
                x: 17; y: -4
                size: 7
                tint: "#FFE08A"
                opacity: tune.live ? 1 : 0.3
                SequentialAnimation on scale {
                    running: tune.live
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.15; duration: 520; easing.type: Easing.OutBack }
                    PauseAnimation { duration: 700 }
                }
            }
        }
        BarPlayer.Key { anchors.horizontalCenter: parent.horizontalCenter; kind: "prev"; rotation: 90; onClicked: Media.previous() }
        BarPlayer.Key { anchors.horizontalCenter: parent.horizontalCenter; kind: Media.playing ? "pause" : "play"; strong: true; onClicked: Media.playPause() }
        BarPlayer.Key { anchors.horizontalCenter: parent.horizontalCenter; kind: "next"; rotation: 90; onClicked: Media.next() }
    }

    // ---- Teto: the gauges as figures, and the Clean key ------------------------------
    Column {
        width: root.width
        spacing: 4
        opacity: root.gauges ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Meter { name: "CPU"; value: Sys.cpu }
        Meter { visible: Sys.hasGpu; name: "GPU"; value: Sys.gpu }
        Meter { name: Tr.t("RAM"); value: Sys.mem }
        Item {
            visible: Sys.canClean
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20; height: 24
            Rectangle {
                y: 3
                width: 20; height: 20
                radius: 6
                color: Sys.cleaning ? Theme.surface3 : cleanArea.containsMouse ? "#F0566E" : "#E0405A"
                border.width: 1.5; border.color: "#FFFFFF"
                scale: cleanArea.pressed ? 0.9 : 1
                BroomGlyph { anchors.centerIn: parent; size: 12; opacity: Sys.cleaning ? 0.5 : 1 }
            }
            MouseArea {
                id: cleanArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // (a MouseArea, so the click stays here and does not open the card)
                onClicked: { Hub.poke(); Sys.clean() }
            }
        }
    }

    // ---- Luka: the light and the ping, then what comes in and what goes out ------------
    Column {
        id: line
        width: root.width
        spacing: 5
        opacity: root.net ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        function heat(ms) { return ms < 0 ? "#E0405A" : ms > 250 ? "#E0405A" : ms > 90 ? "#FFE08A" : "#B9DC6B" }
        // (no room for units here: "1.2M" a second, "340K")
        function speed(v) { return v >= 1048576 ? (v / 1048576).toFixed(v >= 10485760 ? 0 : 1) + "M" : v >= 1024 ? Math.round(v / 1024) + "K" : "0" }
        function mbps(v) { return v <= 0 ? "..." : v >= 100 ? Math.round(v) : v.toFixed(1) }
        // (the speed test: its figures as it runs, then its result for a few seconds, in pink)
        readonly property bool test: Net.online && (Speed.running || Speed.justDone)
        Column {
            width: parent.width
            spacing: 2
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 9; height: 9; radius: 4.5
                color: line.heat(Net.online ? Net.ping : -1)
                border.width: 1.5; border.color: "#FFFFFF"
            }
            Figure { text: !Net.online ? "–" : Net.ping < 0 ? "..." : Net.ping; color: !Net.online ? "#FF8FA0" : Theme.ink }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ms"
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 8; font.weight: Font.ExtraBold
            }
        }
        Reading { downward: true; text: line.test ? line.mbps(Speed.down) : line.speed(Net.down) }
        Reading { downward: false; text: line.test ? line.mbps(Speed.up) : line.speed(Net.up) }
        BarNet.TestKey { anchors.horizontalCenter: parent.horizontalCenter; visible: Net.online || Speed.running }
    }

    // a figure that never grows wider than the bar
    component Figure: Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 28
        horizontalAlignment: Text.AlignHCenter
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 7
        color: Theme.ink
        font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
    }

    // one gauge: its name, its figure, and a short cane that fills with it
    component Meter: Column {
        id: meter
        property string name: ""
        property real value: 0
        readonly property bool hot: value > 0.9
        width: parent.width
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: meter.name
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 8; font.weight: Font.ExtraBold
        }
        Figure { text: Math.round(meter.value * 100); color: meter.hot ? "#FF8FA0" : Theme.ink }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 22; height: 5; radius: 2.5
            color: "#2b2430"
            border.width: 1
            border.color: meter.hot ? "#E0405A" : "#FFFFFF"
            Rectangle {
                x: 1; y: 1
                height: 3; radius: 1.5
                width: Math.max(3, 20 * Math.min(1, meter.value))
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                color: meter.value > 0.9 ? "#E0405A" : meter.value > 0.7 ? "#FFE08A" : "#B9DC6B"
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    // an arrow over a speed
    component Reading: Column {
        id: reading
        property bool downward: true
        property string text: ""
        width: parent.width
        spacing: 1
        Canvas {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 8; height: 11
            onPaint: {
                const g = getContext("2d")
                g.reset(); g.strokeStyle = "#F5A3C0"; g.lineWidth = 2; g.lineCap = "round"; g.lineJoin = "round"
                const a = reading.downward ? 9.5 : 1.5, b = reading.downward ? 1.5 : 9.5, h = reading.downward ? 6 : 5
                g.beginPath(); g.moveTo(4, b); g.lineTo(4, a); g.stroke()
                g.beginPath(); g.moveTo(1, h); g.lineTo(4, a); g.lineTo(7, h); g.stroke()
            }
        }
        Figure { text: reading.text; color: line.test ? "#F5A3C0" : Theme.ink }
    }
}
