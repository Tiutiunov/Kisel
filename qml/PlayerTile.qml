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
            PlayGlyph { anchors.centerIn: parent; kind: "note"; size: 24; tint: Theme.inkFaint; visible: Media.art === "" }
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
            PlayGlyph { anchors.centerIn: parent; kind: btn.kind; size: 14; tint: btn.strong ? "#06281a" : Theme.ink }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
