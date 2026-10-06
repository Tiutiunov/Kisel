// Zundamon's Home: what Spotify is playing, with previous, play or pause, and next. It
// takes the whole of Home's place (494 x 138): with her on stage the card is a player.
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    // the cover, or a quiet note where there is none
    Rectangle {
        id: cover
        y: 4
        width: 112; height: 112
        radius: Theme.radiusMd
        color: Theme.surface2
        clip: true
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        Image {
            anchors.fill: parent
            source: Media.art
            fillMode: Image.PreserveAspectCrop
            visible: Media.art !== ""
            asynchronous: true
        }
        PlayGlyph { anchors.centerIn: parent; kind: "note"; size: 40; tint: Theme.inkFaint; visible: Media.art === "" }
    }

    Column {
        x: 128; y: 6
        width: parent.width - 128
        spacing: 2
        opacity: Motion.rise(root.age, 1)
        transform: Translate { y: Motion.lift(root.age, 1) }
        Text {
            width: parent.width
            text: Media.active ? Media.title : "Nothing playing"
            elide: Text.ElideRight
            color: Theme.ink
            font.family: Theme.display; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: Media.active ? Media.artist : "Open Spotify and it shows up here"
            elide: Text.ElideRight
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }

    // how far the track has got
    Rectangle {
        x: 128; y: 58
        width: parent.width - 128; height: 4; radius: 2
        color: Theme.surface3
        opacity: Motion.rise(root.age, 2) * (Media.active ? 1 : 0.4)
        Rectangle {
            width: parent.width * Media.progress; height: 4; radius: 2
            color: Theme.mint
            Behavior on width { NumberAnimation { duration: 500 } }
        }
    }

    Row {
        x: 128; y: 74
        spacing: 8
        opacity: Motion.rise(root.age, 3) * (Media.active ? 1 : 0.4)
        transform: Translate { y: Motion.lift(root.age, 3) }
        enabled: Media.active
        PlayBtn { kind: "prev"; label: "Previous track"; onClicked: Media.previous() }
        PlayBtn { kind: Media.playing ? "pause" : "play"; label: Media.playing ? "Pause" : "Play"; strong: true; onClicked: Media.playPause() }
        PlayBtn { kind: "next"; label: "Next track"; onClicked: Media.next() }
    }

    component PlayBtn: FocusScope {
        id: btn
        property string kind: "play"
        property string label: ""
        property bool strong: false
        signal clicked()
        width: strong ? 56 : 44; height: 40
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: btn.strong ? Theme.mint : (bt.pressed || bh.hovered ? Theme.surface3 : Theme.surface2)
            opacity: btn.strong && (bt.pressed || bh.hovered) ? 0.85 : 1
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            scale: bt.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
            border.width: btn.activeFocus ? 3 : 0
            border.color: Theme.ink
            PlayGlyph { anchors.centerIn: parent; kind: btn.kind; size: 16; tint: btn.strong ? "#06281a" : Theme.ink }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
