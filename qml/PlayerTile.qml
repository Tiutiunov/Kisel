// GUMI's player: what Spotify is playing, with previous, play or pause, and next.
// As tall as a launch tile (84 px), radius-md; a hairline along the bottom shows how
// far the track has got.
import QtQuick
import Kisel.Core

Item {
    id: root
    width: 270
    height: 84

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.surface2
        clip: true

        // the cover, or a quiet note where there is none
        Rectangle {
            id: cover
            x: 12; y: 12; width: 60; height: 60
            radius: Theme.radiusSm
            color: Theme.surface3
            clip: true
            Image {
                anchors.fill: parent
                source: Media.art
                fillMode: Image.PreserveAspectCrop
                visible: Media.art !== ""
                asynchronous: true
            }
            Glyph { anchors.centerIn: parent; kind: "note"; size: 24; tint: Theme.inkFaint; visible: Media.art === "" }
        }

        Column {
            x: 84; y: 11
            width: parent.width - 84 - 12
            spacing: 1
            Text {
                width: parent.width
                text: Media.active ? Media.title : "Nothing playing"
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
            }
            Text {
                width: parent.width
                text: Media.active ? Media.artist : "Open Spotify and it shows up here"
                elide: Text.ElideRight
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }

        Row {
            x: 80; y: 46
            spacing: 4
            opacity: Media.active ? 1 : 0.4
            enabled: Media.active
            PlayBtn { kind: "prev"; label: "Previous track"; onClicked: Media.previous() }
            PlayBtn { kind: Media.playing ? "pause" : "play"; label: Media.playing ? "Pause" : "Play"; strong: true; onClicked: Media.playPause() }
            PlayBtn { kind: "next"; label: "Next track"; onClicked: Media.next() }
        }

        Rectangle {
            y: parent.height - 2
            height: 2
            width: parent.width * Media.progress
            color: Theme.mint
            visible: Media.active
            Behavior on width { NumberAnimation { duration: 500 } }
        }
    }

    // the four shapes the player needs, drawn rather than taken from a font
    component Glyph: Canvas {
        id: glyph
        property string kind: "play"
        property real size: 14
        property color tint: Theme.ink
        width: size; height: size
        onKindChanged: requestPaint()
        onTintChanged: requestPaint()
        onPaint: {
            const g = getContext("2d"), s = size
            g.reset(); g.fillStyle = tint; g.strokeStyle = tint; g.lineJoin = "round"
            const tri = (x0, x1) => { g.beginPath(); g.moveTo(x0, s * 0.14); g.lineTo(x1, s * 0.5); g.lineTo(x0, s * 0.86); g.closePath(); g.fill() }
            if (kind === "play") tri(s * 0.24, s * 0.86)
            else if (kind === "pause") { g.fillRect(s * 0.2, s * 0.14, s * 0.22, s * 0.72); g.fillRect(s * 0.58, s * 0.14, s * 0.22, s * 0.72) }
            else if (kind === "next") { tri(s * 0.12, s * 0.7); g.fillRect(s * 0.72, s * 0.14, s * 0.16, s * 0.72) }
            else if (kind === "prev") { tri(s * 0.88, s * 0.3); g.fillRect(s * 0.12, s * 0.14, s * 0.16, s * 0.72) }
            else { // a note
                g.lineWidth = s * 0.1
                g.beginPath(); g.arc(s * 0.32, s * 0.74, s * 0.16, 0, 2 * Math.PI, false); g.fill()
                g.beginPath(); g.moveTo(s * 0.44, s * 0.74); g.lineTo(s * 0.44, s * 0.16); g.lineTo(s * 0.8, s * 0.28); g.stroke()
            }
        }
    }

    component PlayBtn: FocusScope {
        id: btn
        property string kind: "play"
        property string label: ""
        property bool strong: false
        signal clicked()
        width: 30; height: 28
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: btn.strong ? Theme.mint : (bt.pressed || bh.hovered ? Theme.surface3 : "transparent")
            opacity: btn.strong && (bt.pressed || bh.hovered) ? 0.85 : 1
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            scale: bt.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
            border.width: btn.activeFocus ? 2 : 0
            border.color: Theme.ink
            Glyph { anchors.centerIn: parent; kind: btn.kind; size: 14; tint: btn.strong ? "#06281a" : Theme.ink }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
