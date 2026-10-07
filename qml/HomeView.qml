// Home: the newest session (or an empty state that says what Kisel is waiting
// for) above four launch tiles. Behind it, quiet shapes drift; when Kisel
// sleeps, the night sky takes over (HomeBackdrop, owned by the Island).
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    signal go(string view)

    readonly property var s: Hub.session
    // The first-launch assembly reveals the real elements one by one as the
    // flying shapes become them (1 = shown, the normal state).
    property real revealCard: 1
    property real revealButton: 1
    property var revealTiles: [1, 1, 1, 1]
    // Where the shapes should land, in this view's coordinates.
    readonly property rect hookRect: Qt.rect(0, 0, width, 46)
    readonly property rect buttonRect: Qt.rect(width - 150 - 10, 5, 150, 36)
    readonly property var tileRects: [Qt.rect(0, height - 84, 104, 84), Qt.rect(112, height - 84, 104, 84)]
    readonly property bool hasSession: !!s.id
    // Home belongs to whoever is chosen. Miku's is this one, Claude Code's; Zundamon's is her
    // Spotify player. The ones with no service of their own yet show Claude's.
    property string own: "" // whose Home this is, says the island: "" (Claude's) | zunda | teto | luka
    readonly property bool ownHome: own !== ""
    // (the one last shown stays through the dissolve back to Claude's)
    property string shownOwn: ""
    onOwnChanged: if (own !== "") shownOwn = own
    // one Home dissolves into the other: Claude's goes first, hers follows
    property real ownU: ownHome ? 1 : 0
    Behavior on ownU { NumberAnimation { duration: Theme.reduced ? 140 : 320; easing.type: Easing.InOutCubic } }
    readonly property real claudeU: Math.max(0, 1 - ownU * 2)

    width: 494

    Repeater { id: counter; model: Hub.sessions; delegate: Item {} } // only counts

    // ---- top row: newest session, or "ready and listening" ----
    Rectangle {
        id: sessionTile
        visible: root.hasSession && root.claudeU > 0
        opacity: root.revealCard * Motion.rise(root.age, 0) * root.claudeU
        transform: Translate { y: Motion.lift(root.age, 0) }
        width: parent.width
        height: 40
        radius: Theme.radiusMd
        color: tap.pressed || th.hovered ? Theme.surface3 : Theme.surface2
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
        scale: tap.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Theme.tPress } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.space3
            anchors.rightMargin: Theme.space3
            spacing: Theme.space2
            Item {
                width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                Spinner { anchors.fill: parent; visible: root.s.state === "work" || root.s.state === "think" }
                DrawnCheck { anchors.centerIn: parent; size: 16; color: Theme.mint; visible: root.s.state === "done" }
                Icon { anchors.centerIn: parent; size: 14; name: "cross"; color: Theme.danger; visible: root.s.state === "failed" }
                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.inkMuted; visible: root.s.state === "idle" }
            }
            Text {
                width: 140
                text: root.s.name + (counter.count > 1 ? "  +" + (counter.count - 1) : "")
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                width: parent.width - 140 - 16 - statePill.width - 3 * Theme.space2
                text: root.s.line || ""
                elide: Text.ElideRight
                color: Theme.inkMuted
                font.family: Theme.mono; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
            StatusPill { id: statePill; state: root.s.state || "idle"; anchors.verticalCenter: parent.verticalCenter }
        }
        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: root.go("session") }
    }

    // empty: a card with the dot wave ("ready and listening"), what Kisel waits for and,
    // while Claude Code is not connected, the primary button. The first-launch slab
    // becomes this card, the small pill becomes the button.
    Rectangle {
        id: empty
        visible: !root.hasSession && root.claudeU > 0
        opacity: root.revealCard * Motion.rise(root.age, 0) * root.claudeU
        transform: Translate { y: Motion.lift(root.age, 0) }
        width: parent.width
        height: 46
        radius: Theme.radiusMd
        color: Theme.surface2
        border.width: 1
        border.color: Theme.line

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.space3
            spacing: Theme.space3
            Item {
                width: 60; height: 24
                anchors.verticalCenter: parent.verticalCenter
                // hooks installed but nothing heard yet: the first connection takes the jelly trio
                JellyTrio { scale: 0.5; transformOrigin: Item.Left; running: root.active && empty.visible && Hooks.installed && !Prefs.hookSeen }
                DotWave { running: root.active && empty.visible && !(Hooks.installed && !Prefs.hookSeen); opacity: running ? 1 : 0 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: Hooks.installed ? "Waiting for Claude Code" : "Claude Code isn't connected"
                    color: Theme.ink
                    font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.ExtraBold
                }
                Text {
                    text: Hooks.installed ? (Hub.serverUp ? "Start a session and it shows up here" : "Can't listen for hooks right now")
                                          : "Connect it to see sessions here"
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                }
            }
        }
        // the label is revealed left to right with a 200 ms wipe
        Item {
            id: buttonClip
            visible: !Hooks.installed
            x: parent.width - 150 - 10
            y: 5
            width: 150 * root.revealButton
            height: 36
            clip: true
            KButton {
                id: connect
                variant: "primary"
                text: "Connect Claude Code"
                width: 150
                // first launch: the primary button pulses twice (scale 1 -> 1.04 -> 1, 600 ms each, 400 ms apart)
                scale: pulse
                property real pulse: 1
                function pulseTwice() { pulseAnim.restart() }
                SequentialAnimation {
                    id: pulseAnim
                    NumberAnimation { target: connect; property: "pulse"; to: 1.04; duration: 300; easing.type: Easing.InOutSine }
                    NumberAnimation { target: connect; property: "pulse"; to: 1; duration: 300; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 400 }
                    NumberAnimation { target: connect; property: "pulse"; to: 1.04; duration: 300; easing.type: Easing.InOutSine }
                    NumberAnimation { target: connect; property: "pulse"; to: 1; duration: 300; easing.type: Easing.InOutSine }
                }
                onClicked: root.go("settings")
            }
        }
    }
    function pulseConnect() { if (!Hooks.installed) connect.pulseTwice() }

    // ---- launch tiles ----
    Row {
        visible: root.claudeU > 0
        opacity: root.claudeU
        y: parent.height - 84
        spacing: Theme.space2
        LaunchTile {
            label: "Claude"; icon: "chat"; glyph: Theme.kisel
            opacity: root.revealTiles[0] * Motion.rise(root.age, 1)
            transform: Translate { y: Motion.lift(root.age, 1) }
            onClicked: root.go("chat")
        }
        LaunchTile {
            label: "GitHub"; icon: "github"; glyph: Theme.amber
            opacity: root.revealTiles[1] * Motion.rise(root.age, 2)
            transform: Translate { y: Motion.lift(root.age, 2) }
            onClicked: root.go("github")
        }
    }

    // ---- Zundamon's Home is her player ----
    PlayerView {
        visible: root.ownU > 0.01 && root.shownOwn === "zunda"
        opacity: root.ownU
        age: root.age
    }
    // ---- Teto's is how the computer is doing ----
    TetoView {
        visible: root.ownU > 0.01 && root.shownOwn === "teto"
        opacity: root.ownU
        age: root.age
    }
    // ---- Luka's is how the connection is doing ----
    LukaView {
        visible: root.ownU > 0.01 && root.shownOwn === "luka"
        opacity: root.ownU
        age: root.age
    }
}
