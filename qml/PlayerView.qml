// Zundamon's Home: what Spotify is playing. It takes the whole of Home's place
// (494 x 138): with her on stage the card is a player.
//
// A panel washed in the cover's own colours; the cover with a record that slides out
// from behind it and turns while the tune plays; the title over the artist; a row of
// bars that dance (they keep time with nothing: the system tells us what plays, not
// how it sounds); the progress with the time on both sides; previous, play or pause, next.
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    readonly property bool live: Media.active && Media.playing && visible && !Theme.reduced
    function clock(sec) {
        const s = Math.max(0, Math.floor(sec))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    // ---- the panel: the cover, blown up until only its colours are left ----
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.surface2
        clip: true
        opacity: Motion.rise(root.age, 0)
        Image {
            anchors.fill: parent
            anchors.margins: -40
            source: Media.art
            visible: Media.art !== ""
            sourceSize: Qt.size(12, 12) // a dozen pixels stretched over the panel: a blur for free
            smooth: true
            fillMode: Image.PreserveAspectCrop
            opacity: 0.3
        }
        Rectangle { // text stays readable over any cover
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(Theme.surface2.r, Theme.surface2.g, Theme.surface2.b, 0.7) }
            }
        }
    }

    // ---- the record, behind the cover: out and turning while the tune plays ----
    Item {
        id: record
        width: 96; height: 96
        y: 21
        x: 14 + (Media.active && Media.playing ? 46 : 8)
        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        opacity: Motion.rise(root.age, 0)
        Rectangle { anchors.fill: parent; radius: 48; color: "#0d0b0c" }
        Repeater { // grooves
            model: [84, 70, 56]
            Rectangle {
                required property int modelData
                anchors.centerIn: parent
                width: modelData; height: modelData; radius: modelData / 2
                color: "transparent"; border.width: 1; border.color: "#2a2527"
            }
        }
        Rectangle { // the light the grooves catch: this is what shows the record turning
            anchors.centerIn: parent
            width: 2; height: 90; radius: 1
            gradient: Gradient {
                GradientStop { position: 0; color: "#00ffffff" }
                GradientStop { position: 0.3; color: "#40ffffff" }
                GradientStop { position: 0.5; color: "#00ffffff" }
                GradientStop { position: 0.7; color: "#40ffffff" }
                GradientStop { position: 1; color: "#00ffffff" }
            }
        }
        Rectangle { anchors.centerIn: parent; width: 34; height: 34; radius: 17; color: Theme.mint
            Rectangle { anchors.centerIn: parent; width: 14; height: 2; radius: 1; color: "#06281a"; opacity: 0.5 } }
        Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#0d0b0c" }
        RotationAnimation on rotation { running: root.live; from: 0; to: 360; duration: 3600; loops: Animation.Infinite }
    }

    // ---- the cover, or a quiet note where there is none ----
    Rectangle {
        id: cover
        x: 14; y: 17
        width: 104; height: 104
        radius: 10
        color: Theme.surface3
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

    // ---- everything right of the cover ----
    Item {
        id: side
        x: 176; y: 12
        width: parent.width - x - 14
        height: parent.height - 24

        Column {
            width: side.width - keys.width - 10
            spacing: 1
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

        Row {
            id: keys
            anchors.right: parent.right
            y: 2
            spacing: 6
            opacity: Motion.rise(root.age, 2) * (Media.active ? 1 : 0.4)
            transform: Translate { y: Motion.lift(root.age, 2) }
            enabled: Media.active
            PlayBtn { kind: "prev"; label: "Previous track"; onClicked: Media.previous() }
            PlayBtn { kind: Media.playing ? "pause" : "play"; label: Media.playing ? "Pause" : "Play"; strong: true; onClicked: Media.playPause() }
            PlayBtn { kind: "next"; label: "Next track"; onClicked: Media.next() }
        }

        // the dancing bars
        Row {
            id: bars
            y: 50
            height: 26
            spacing: 3
            opacity: Motion.rise(root.age, 3) * (Media.active ? 1 : 0.3)
            property real amp: Media.active && Media.playing ? 1 : 0
            Behavior on amp { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Repeater {
                model: Math.floor((side.width + 3) / 6)
                Rectangle {
                    id: bar
                    required property int index
                    property real level: 0.2
                    readonly property real peak: 0.35 + Math.random() * 0.65
                    readonly property int beat: 220 + Math.floor(Math.random() * 320)
                    width: 3; radius: 1.5
                    height: 3 + level * bars.amp * 23
                    anchors.bottom: parent.bottom
                    color: Theme.mint
                    opacity: 0.45 + 0.55 * level
                    SequentialAnimation on level {
                        running: root.live
                        loops: Animation.Infinite
                        NumberAnimation { to: bar.peak; duration: bar.beat; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.08 + (bar.index % 3) * 0.06; duration: bar.beat + 90; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        // how far the track has got, with a bright head, and the time on both sides
        Item {
            y: 86
            width: side.width; height: 28
            opacity: Motion.rise(root.age, 4) * (Media.active ? 1 : 0.4)
            Rectangle { width: parent.width; height: 4; radius: 2; color: Theme.ink; opacity: 0.12 }
            Rectangle {
                id: fill
                width: parent.width * Media.progress; height: 4; radius: 2
                Behavior on width { NumberAnimation { duration: 500 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#B9DC6B" }
                    GradientStop { position: 1; color: Theme.mint }
                }
            }
            Rectangle { x: fill.width - 5; y: -3; width: 10; height: 10; radius: 5; color: "#FFFFFF"
                scale: root.live ? 1 : 0.7
                Behavior on scale { NumberAnimation { duration: 200 } } }
            Text {
                y: 11
                text: root.clock(Media.position)
                visible: Media.duration > 0
                color: Theme.inkMuted
                font.family: Theme.mono; font.pixelSize: 10
            }
            Text {
                y: 11
                anchors.right: parent.right
                text: root.clock(Media.duration)
                visible: Media.duration > 0
                color: Theme.inkMuted
                font.family: Theme.mono; font.pixelSize: 10
            }
        }
    }

    component PlayBtn: FocusScope {
        id: btn
        property string kind: "play"
        property string label: ""
        property bool strong: false
        signal clicked()
        width: strong ? 46 : 34; height: 34
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 17
            color: btn.strong ? Theme.mint : (bt.pressed || bh.hovered ? Theme.surface3 : Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.08))
            opacity: btn.strong && (bt.pressed || bh.hovered) ? 0.85 : 1
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            scale: bt.pressed ? 0.92 : bh.hovered ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
            border.width: btn.activeFocus ? 3 : 0
            border.color: Theme.ink
            PlayGlyph { anchors.centerIn: parent; kind: btn.kind; size: 14; tint: btn.strong ? "#06281a" : Theme.ink }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
