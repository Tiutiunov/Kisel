// Zundamon's Home: what Spotify is playing. It takes the whole of Home's place
// (494 x 138): with her on stage the card is a player.
//
// Drawn like a page of a sticker album, straight on the card with no panel under it:
// the cover is a sticker with a white edge, stuck on a little askew with a strip of
// tape, a record peeping out from behind it that turns while the tune plays; sparkles
// twinkle around it; candy-coloured bars bounce (they keep time with nothing: the
// system tells us what plays, not how it sounds); the progress is a ribbon with a star
// for a head; the keys are round sweets.
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    readonly property bool live: Media.active && Media.playing && visible && !Theme.reduced
    readonly property var candy: ["#FF9EBB", "#FFE08A", "#B9DC6B", "#9CD4FF", "#C9A8FF"]
    function clock(sec) {
        const s = Math.max(0, Math.floor(sec))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    // ---- the record, behind the sticker: out and turning while the tune plays ----
    Item {
        id: record
        width: 92; height: 92
        y: 24
        x: 12 + (Media.active && Media.playing ? 52 : 12)
        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        opacity: Motion.rise(root.age, 0)
        Rectangle { anchors.fill: parent; radius: 46; color: "#2b2430"; border.width: 2; border.color: "#FFFFFF" }
        Repeater { // grooves
            model: [72, 58]
            Rectangle {
                required property int modelData
                anchors.centerIn: parent
                width: modelData; height: modelData; radius: modelData / 2
                color: "transparent"; border.width: 1; border.color: "#4a4050"
            }
        }
        Rectangle { // the light the grooves catch: this is what shows the record turning
            anchors.centerIn: parent
            width: 3; height: 84; radius: 1.5
            gradient: Gradient {
                GradientStop { position: 0; color: "#00ffffff" }
                GradientStop { position: 0.28; color: "#59ffffff" }
                GradientStop { position: 0.5; color: "#00ffffff" }
                GradientStop { position: 0.72; color: "#59ffffff" }
                GradientStop { position: 1; color: "#00ffffff" }
            }
        }
        Rectangle { anchors.centerIn: parent; width: 34; height: 34; radius: 17; color: "#FF9EBB"; border.width: 2; border.color: "#FFFFFF" }
        Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#2b2430" }
        RotationAnimation on rotation { running: root.live; from: 0; to: 360; duration: 3600; loops: Animation.Infinite }
    }

    // ---- the cover: a sticker with a white edge, a little askew, held by a strip of tape ----
    Item {
        id: sticker
        x: 12; y: 15
        width: 108; height: 108
        rotation: -4
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        Rectangle { x: 2; y: 4; width: parent.width; height: parent.height; radius: 12; color: "#000000"; opacity: 0.25 }
        Rectangle { anchors.fill: parent; radius: 12; color: "#FFFFFF" }
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            color: Theme.surface3
            clip: true
            Image {
                anchors.fill: parent
                source: Media.art
                sourceSize: Qt.size(256, 256) // (shown at a third of that: no need for the whole picture)
                fillMode: Image.PreserveAspectCrop
                visible: Media.art !== ""
                asynchronous: true
            }
            PlayGlyph { anchors.centerIn: parent; kind: "note"; size: 40; tint: Theme.inkFaint; visible: Media.art === "" }
        }
        Rectangle { // the tape
            x: 34; y: -8
            width: 40; height: 15; radius: 2
            rotation: 6
            color: "#B9DC6B"; opacity: 0.9
            Row { anchors.centerIn: parent; spacing: 5
                Repeater { model: 4; Rectangle { width: 3; height: 15; color: "#FFFFFF"; opacity: 0.35 } } }
        }
    }

    // ---- sparkles around the sticker, twinkling in turn while the tune plays ----
    Repeater {
        model: [{ x: 4, y: 6, s: 12, c: 1 }, { x: 128, y: 14, s: 9, c: 0 }, { x: 142, y: 104, s: 13, c: 3 }, { x: 2, y: 112, s: 8, c: 4 }, { x: 150, y: 58, s: 7, c: 2 }]
        Spark {
            id: twinkle
            required property var modelData
            required property int index
            x: modelData.x; y: modelData.y
            size: modelData.s
            tint: root.candy[modelData.c]
            opacity: Motion.rise(root.age, 2) * (root.live ? 1 : 0.35)
            Behavior on opacity { NumberAnimation { duration: 300 } }
            SequentialAnimation on scale {
                running: root.live
                loops: Animation.Infinite
                PauseAnimation { duration: twinkle.index * 260 }
                NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.15; duration: 520; easing.type: Easing.OutBack }
                PauseAnimation { duration: 900 - twinkle.index * 120 }
            }
            RotationAnimation on rotation { running: root.live; from: 0; to: 90; duration: 5200 + twinkle.index * 700; loops: Animation.Infinite }
        }
    }

    // ---- everything right of the sticker ----
    Item {
        id: side
        x: 184; y: 10
        width: parent.width - x - 6
        height: parent.height - 20

        Column {
            width: side.width - keys.width - 10
            spacing: 2
            opacity: Motion.rise(root.age, 1)
            transform: Translate { y: Motion.lift(root.age, 1) }
            Text {
                width: parent.width
                text: Media.active ? Media.title : Tr.t("Nothing playing")
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 19; font.weight: Font.Bold
            }
            Row {
                width: parent.width
                spacing: 5
                PlayGlyph { anchors.verticalCenter: parent.verticalCenter; kind: "note"; size: 11; tint: "#FF9EBB"; visible: Media.active }
                Text {
                    width: parent.width - 16
                    text: Media.active ? Media.artist : Tr.t("Open Spotify and it shows up here")
                    elide: Text.ElideRight
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
        }

        Row {
            id: keys
            anchors.right: parent.right
            y: 0
            spacing: 6
            opacity: Motion.rise(root.age, 2) * (Media.active ? 1 : 0.4)
            transform: Translate { y: Motion.lift(root.age, 2) }
            enabled: Media.active
            PlayBtn { anchors.verticalCenter: parent.verticalCenter; kind: "prev"; label: Tr.t("Previous track"); onClicked: Media.previous() }
            PlayBtn { kind: Media.playing ? "pause" : "play"; label: Media.playing ? Tr.t("Pause") : Tr.t("Play"); strong: true; onClicked: Media.playPause() }
            PlayBtn { anchors.verticalCenter: parent.verticalCenter; kind: "next"; label: Tr.t("Next track"); onClicked: Media.next() }
        }

        // candy bars, bouncing
        Row {
            id: bars
            y: 52
            height: 24
            spacing: 4
            opacity: Motion.rise(root.age, 3) * (Media.active ? 1 : 0.3)
            property real amp: Media.active && Media.playing ? 1 : 0
            Behavior on amp { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Repeater {
                model: Math.floor((side.width + 4) / 10)
                Rectangle {
                    id: bar
                    required property int index
                    property real level: 0.2
                    readonly property real peak: 0.4 + Math.random() * 0.6
                    readonly property int beat: 240 + Math.floor(Math.random() * 300)
                    width: 6; radius: 3
                    height: 6 + level * bars.amp * 18
                    anchors.bottom: parent.bottom
                    color: root.candy[index % root.candy.length]
                    SequentialAnimation on level {
                        running: root.live
                        loops: Animation.Infinite
                        NumberAnimation { to: bar.peak; duration: bar.beat; easing.type: Easing.OutBack }
                        NumberAnimation { to: 0.05 + (bar.index % 3) * 0.07; duration: bar.beat + 110; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        // how far the track has got: a ribbon with a star for a head, the time on both sides
        // (Where the player allows it, the ribbon is a handle as well: press or drag along
        // it and the track goes there when the button is let go. `scrub` is where the
        // star is held meanwhile, and for a moment after, until the player has caught up.)
        Item {
            id: ribbon
            y: 88
            width: side.width; height: 30
            opacity: Motion.rise(root.age, 4) * (Media.active ? 1 : 0.4)
            property real scrub: -1
            readonly property real shown: scrub >= 0 ? scrub : Media.progress
            Timer { id: scrubHold; interval: 1200; onTriggered: ribbon.scrub = -1 }
            MouseArea {
                id: scrubArea
                x: 0; y: -8
                width: parent.width; height: 24
                enabled: Media.active && Media.canSeek && Media.duration > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                function at(m) { return Math.max(0, Math.min(1, m.x / width)) }
                onPressed: (m) => { scrubHold.stop(); ribbon.scrub = at(m) }
                onPositionChanged: (m) => { if (pressed) ribbon.scrub = at(m) }
                onReleased: { Media.seek(ribbon.scrub); Sfx.play("click"); scrubHold.restart() }
                onCanceled: ribbon.scrub = -1
            }
            Rectangle { width: parent.width; height: 8; radius: 4; color: Theme.ink; opacity: 0.12 }
            Rectangle {
                id: fill
                width: Math.max(8, parent.width * ribbon.shown); height: 8; radius: 4
                Behavior on width { enabled: !scrubArea.pressed; NumberAnimation { duration: 500 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#FF9EBB" }
                    GradientStop { position: 0.6; color: "#FFE08A" }
                    GradientStop { position: 1; color: "#B9DC6B" }
                }
            }
            Spark {
                x: fill.width - 10; y: -6
                size: 20
                tint: "#FFFFFF"
                scale: scrubArea.pressed ? 1.35 : root.live ? 1 : 0.8
                Behavior on scale { NumberAnimation { duration: 200 } }
                RotationAnimation on rotation { running: root.live; from: 0; to: 90; duration: 2400; loops: Animation.Infinite }
            }
            Text {
                y: 14
                text: root.clock(ribbon.scrub >= 0 ? ribbon.scrub * Media.duration : Media.position)
                visible: Media.duration > 0
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
            Text {
                y: 14
                anchors.right: parent.right
                text: root.clock(Media.duration)
                visible: Media.duration > 0
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }
    }

    // a round sweet of a key: white edge, candy inside, a bounce under the pointer
    component PlayBtn: FocusScope {
        id: btn
        property string kind: "play"
        property string label: ""
        property bool strong: false
        signal clicked()
        width: strong ? 42 : 32; height: width
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: btn.strong ? "#FF9EBB" : (bt.pressed || bh.hovered ? Theme.surface3 : Theme.surface2)
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            border.width: btn.activeFocus ? 3 : 2
            border.color: btn.strong ? "#FFFFFF" : Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, btn.activeFocus ? 1 : 0.35)
            scale: bt.pressed ? 0.9 : bh.hovered ? 1.1 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            PlayGlyph { anchors.centerIn: parent; kind: btn.kind; size: btn.strong ? 15 : 12; tint: btn.strong ? "#5a1f33" : Theme.ink }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
