// Home: the newest session (or an empty state that says what Kisel is waiting
// for) above four launch tiles. Behind it, quiet shapes drift; when Kisel
// sleeps, the night sky takes over (HomeBackdrop, owned by the Island).
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    signal go(string view)

    readonly property var s: Hub.session
    readonly property bool hasSession: !!s.id

    width: 494
    opacity: active ? 1 : 0
    visible: opacity > 0
    enabled: active
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

    Repeater { id: counter; model: Hub.sessions; delegate: Item {} } // only counts

    // ---- top row: newest session, or "ready and listening" ----
    Rectangle {
        id: sessionTile
        visible: root.hasSession
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

    // empty: the dot wave is Kisel's "ready and listening" mark
    Row {
        id: empty
        visible: !root.hasSession
        width: parent.width
        height: 40
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
            width: parent.width - 60 - connect.width - 2 * Theme.space3
            Text {
                text: Hooks.installed ? "Waiting for Claude Code" : "Claude Code isn't connected"
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.ExtraBold
            }
            Text {
                text: Hooks.installed ? (Hub.serverUp ? "Start a session and it shows up here" : "Can't listen for hooks right now")
                                      : "Connect it to see sessions and answer permissions here"
                elide: Text.ElideRight
                width: parent.width
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }
        KButton {
            id: connect
            anchors.verticalCenter: parent.verticalCenter
            visible: !Hooks.installed
            variant: "primary"
            text: "Connect"
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
    function pulseConnect() { if (!Hooks.installed) connect.pulseTwice() }

    // ---- launch tiles ----
    Row {
        y: parent.height - 84
        spacing: Theme.space2
        LaunchTile { label: "Claude"; icon: "chat"; glyph: Theme.kisel; onClicked: root.go("chat") }
        LaunchTile { label: "Terminal"; icon: "terminal"; glyph: Theme.mint; onClicked: Launcher.openTerminal(root.s.cwd || "") }
        LaunchTile { label: "GitHub"; icon: "github"; glyph: Theme.amber; onClicked: root.go("github") }
        LaunchTile { label: "Files"; icon: "folder"; glyph: Theme.info; onClicked: Launcher.openFiles(root.s.cwd || "") }
    }
}
