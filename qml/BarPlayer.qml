// Zundamon's player in the collapsed bar, in the sticker style of the big one
// (PlayerView): the cover as a tiny sticker with a white edge, a record that slides out
// from behind it and turns while the tune plays, a sparkle; the title (it scrolls when
// it does not fit) over the artist; and three round keys, the middle one a pink sweet.
// It slides in from the right when the tune starts, and out when it stops.
import QtQuick
import Kisel.Core

Row {
    id: root
    property bool on: false
    property bool still: false // tucked away: nothing moves
    property real room: 174    // the width it may take
    readonly property bool live: on && Media.playing && !Theme.reduced && !still

    height: 24
    spacing: 6
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    transform: Translate { x: root.on ? 0 : 6; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } } // (a small step as it fades, no more: three of these change places in one spot)

    Item {
        width: 30; height: 24
        anchors.verticalCenter: parent.verticalCenter
        Item { // the record
            width: 18; height: 18
            y: 3
            x: root.live ? 12 : 3
            Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
            Rectangle { anchors.fill: parent; radius: 9; color: "#2b2430"; border.width: 1; border.color: "#FFFFFF" }
            Rectangle { // the light the grooves catch: it shows the turning
                anchors.centerIn: parent
                width: 2; height: 15; radius: 1
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00ffffff" }
                    GradientStop { position: 0.3; color: "#70ffffff" }
                    GradientStop { position: 0.5; color: "#00ffffff" }
                    GradientStop { position: 0.7; color: "#70ffffff" }
                    GradientStop { position: 1; color: "#00ffffff" }
                }
            }
            Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: "#FF9EBB" }
            RotationAnimation on rotation { running: root.live; from: 0; to: 360; duration: 3000; loops: Animation.Infinite }
        }
        Item { // the cover, a sticker a little askew
            width: 20; height: 20
            y: 2
            rotation: -5
            Rectangle { anchors.fill: parent; radius: 4; color: "#FFFFFF" }
            Rectangle {
                anchors.fill: parent; anchors.margins: 2
                color: Theme.surface3
                clip: true
                Image { anchors.fill: parent; source: Media.art; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectCrop; visible: Media.art !== ""; asynchronous: true }
                PlayGlyph { anchors.centerIn: parent; kind: "note"; size: 10; tint: Theme.inkFaint; visible: Media.art === "" }
            }
        }
        Spark {
            x: 23; y: -2
            size: 7
            tint: "#FFE08A"
            opacity: root.live ? 1 : 0.3
            SequentialAnimation on scale {
                running: root.live
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 520; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.15; duration: 520; easing.type: Easing.OutBack }
                PauseAnimation { duration: 700 }
            }
        }
    }

    Item {
        id: tune
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(30, root.room - 30 - keys.width - 2 * root.spacing)
        height: 24
        clip: true
        Text {
            id: title
            y: -1
            text: Media.title
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
            readonly property real over: Math.max(0, implicitWidth - tune.width)
            onTextChanged: x = 0
            SequentialAnimation on x {
                running: title.over > 0 && root.on && !Theme.reduced && !root.still
                loops: Animation.Infinite
                PauseAnimation { duration: 1800 }
                NumberAnimation { to: -title.over; duration: 400 + title.over * 40 }
                PauseAnimation { duration: 1800 }
                NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutCubic }
            }
        }
        Row {
            y: 13
            spacing: 3
            PlayGlyph { anchors.verticalCenter: parent.verticalCenter; kind: "note"; size: 8; tint: "#FF9EBB" }
            Text {
                width: tune.width - 11
                text: Media.artist
                elide: Text.ElideRight
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.DemiBold
            }
        }
    }

    Row {
        id: keys
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Key { anchors.verticalCenter: parent.verticalCenter; kind: "prev"; onClicked: Media.previous() }
        Key { kind: Media.playing ? "pause" : "play"; strong: true; onClicked: Media.playPause() }
        Key { anchors.verticalCenter: parent.verticalCenter; kind: "next"; onClicked: Media.next() }
    }

    // a round key; the strong one is a pink sweet with a white edge
    component Key: Item {
        id: key
        property string kind: "play"
        property bool strong: false
        signal clicked()
        width: strong ? 20 : 16; height: width
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: key.strong ? "#FF9EBB" : Theme.surface3
            opacity: key.strong || area.containsMouse ? 1 : 0
            border.width: key.strong ? 1.5 : 0
            border.color: "#FFFFFF"
            Behavior on opacity { NumberAnimation { duration: Theme.tHover } }
        }
        PlayGlyph { anchors.centerIn: parent; kind: key.kind; size: key.strong ? 8 : 9; tint: key.strong ? "#5a1f33" : Theme.ink }
        scale: area.pressed ? 0.85 : area.containsMouse ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // (a MouseArea, so the click stays here and does not open the card)
            onClicked: { Hub.poke(); key.clicked() }
        }
    }
}
