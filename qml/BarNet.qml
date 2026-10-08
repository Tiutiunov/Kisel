// Luka's readings in the collapsed bar: the ping with a light that says how the line is,
// and what is coming in and going out. Nothing here moves by itself. When the line is
// down the readings give way to the news of it, and for a few seconds after it comes
// back, to that. While something is being downloaded the incoming speed sits in a pink
// capsule with how much has come in so far, and the outgoing one steps aside; when the
// download ends the bar says so for a few seconds. They slide in from the right like
// Teto's gauges.
import QtQuick
import Kisel.Core

Row {
    id: root
    property bool on: false
    property real room: 174 // the width it may take

    function heat(ms) { return ms < 0 ? "#E0405A" : ms > 250 ? "#E0405A" : ms > 90 ? "#FFE08A" : "#B9DC6B" }
    function speed(v) {
        return v >= 1048576 ? (v / 1048576).toFixed(v >= 10485760 ? 0 : 1) + Tr.t(" MB/s")
            : v >= 1024 ? Math.round(v / 1024) + Tr.t(" KB/s") : Tr.t("0 KB/s")
    }

    height: 24
    spacing: 6
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    transform: Translate { x: root.on ? 0 : 18; Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }

    function amount(v) {
        return v >= 1073741824 ? (v / 1073741824).toFixed(2) + Tr.t(" GB")
            : v >= 1048576 ? Math.round(v / 1048576) + Tr.t(" MB") : Math.round(v / 1024) + Tr.t(" KB")
    }
    function mbps(v) { return (v >= 100 ? Math.round(v) : v.toFixed(1)) + Tr.t(" Mbps") }
    // (the speed test: its figure as it runs, then its result for a few seconds; what it
    // moves is not a download to announce)
    readonly property bool testing: Speed.running
    readonly property bool testNews: Net.online && !Net.justBack && Speed.justDone && !testing
    readonly property bool fetchNews: Net.online && !Net.justBack && Net.justFetched && !Net.downloading && !Speed.busy
    readonly property bool news: !Net.online || Net.justBack || fetchNews || testNews

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
            text: !Net.online ? Tr.t("No connection") : Net.justBack ? Tr.t("Back online")
                : root.testNews ? Math.round(Speed.down) + " / " + Math.round(Speed.up) + Tr.t(" Mbps")
                : root.fetchNews ? Tr.t("Downloaded ") + root.amount(Net.fetched) : Net.ping < 0 ? "..." : Net.ping + " ms"
            color: !Net.online ? "#FF8FA0" : Theme.ink
            font.family: Theme.sans; font.pixelSize: root.news ? 13 : 12; font.weight: Font.ExtraBold
        }
    }
    Reading { visible: !root.news && !root.testing && !(Net.downloading && !Speed.busy); downward: true; value: Net.down }
    Reading { visible: !root.news && !root.testing && !(Net.downloading && !Speed.busy); downward: false; value: Net.up }
    // the speed test as it runs: which way, and how fast so far
    Rectangle {
        visible: !root.news && root.testing
        anchors.verticalCenter: parent.verticalCenter
        width: testText.width + 16; height: 20
        radius: 10
        color: "#F5A3C0"
        border.width: 1.5; border.color: "#FFFFFF"
        Text {
            id: testText
            anchors.centerIn: parent
            text: Speed.phase === "ping" ? Tr.t("Testing") : (Speed.phase === "down" ? Tr.t("Down ") + root.mbps(Speed.down) : Tr.t("Up ") + root.mbps(Speed.up))
            color: "#4a1730"
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
    }
    // a download: the speed and how much so far, in a capsule of their own
    Rectangle {
        visible: !root.news && Net.downloading && !Speed.busy && !root.testing
        anchors.verticalCenter: parent.verticalCenter
        width: fetchRow.width + 14; height: 20
        radius: 10
        color: "#F5A3C0"
        border.width: 1.5; border.color: "#FFFFFF"
        Row {
            id: fetchRow
            anchors.centerIn: parent
            spacing: 4
            Canvas {
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 11
                onPaint: {
                    const g = getContext("2d")
                    g.reset(); g.strokeStyle = "#4a1730"; g.lineWidth = 2; g.lineCap = "round"; g.lineJoin = "round"
                    g.beginPath(); g.moveTo(4, 1.5); g.lineTo(4, 9.5); g.stroke()
                    g.beginPath(); g.moveTo(1, 6); g.lineTo(4, 9.5); g.lineTo(7, 6); g.stroke()
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.speed(Net.down) + "  \u00B7  " + root.amount(Net.fetched)
                color: "#4a1730"
                font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
            }
        }
    }

    // (The key itself stands at the bar's far end, before the bench, so it does not move as the readings change: see Island.qml.)
    // The Test key, as on her card: measures the line without opening it; again to stop.
    // (Pink with two arrows; while the test runs it is dark and shows a stop. How far the test has got is the bar's to show: it fills.)
    component TestKey: Item {
        id: key
        width: 20; height: 20
        opacity: Net.online ? 1 : 0.4
        Rectangle {
            id: face
            anchors.fill: parent
            radius: 6
            color: Speed.running ? Theme.surface3 : keyArea.containsMouse ? "#FFB7D0" : "#F5A3C0"
            border.width: 1.5; border.color: "#FFFFFF"
            Behavior on color { ColorAnimation { duration: 160 } }
            Rectangle { visible: Speed.running; anchors.centerIn: parent; width: 7; height: 7; radius: 1.5; color: Theme.ink }
            Canvas { // two arrows, down and up
                visible: !Speed.running
                anchors.centerIn: parent
                width: 13; height: 11
                onPaint: {
                    const g = getContext("2d")
                    g.reset(); g.strokeStyle = "#4a1730"; g.lineWidth = 1.8; g.lineCap = "round"; g.lineJoin = "round"
                    g.beginPath(); g.moveTo(3.5, 1.5); g.lineTo(3.5, 9.5); g.stroke()
                    g.beginPath(); g.moveTo(1, 6.5); g.lineTo(3.5, 9.5); g.lineTo(6, 6.5); g.stroke()
                    g.beginPath(); g.moveTo(9.5, 9.5); g.lineTo(9.5, 1.5); g.stroke()
                    g.beginPath(); g.moveTo(7, 4.5); g.lineTo(9.5, 1.5); g.lineTo(12, 4.5); g.stroke()
                }
            }
        }
        scale: keyArea.pressed ? 0.9 : 1
        MouseArea {
            id: keyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // (a MouseArea, so the click stays here and does not open the card)
            onClicked: { Hub.poke(); if (!Net.online) return; Sfx.play("click"); if (Speed.running) Speed.stop(); else Speed.start() }
        }
    }

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
            width: 40 // (steady: the figures change, the bar does not jiggle; a long figure is set a little smaller)
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 8
            text: root.speed(reading.value)
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
    }
}
