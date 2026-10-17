// Session: what you asked (a bubble at the top left), the steps Claude took under it,
// the file it is changing (right) with the last command under that, and, while the
// session listens, a field to write to it at the foot.
//
// The room is dressed for whoever is on stage (`who`), as the chat is: her colour is in
// the bubble, the edges, the checks and the send button.
//
// Everything here is held to its place. Text that comes from a session is one line (a
// prompt two at most) whatever newlines it has, and the steps live in a clipped well,
// the newest at its foot, the older ones fading out at its top: a long prompt or a
// heredoc once ran down over the field and out of the card.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    readonly property var s: Hub.session
    // A prompt for this session, typed here: only while the session has someone listening
    // for it (the kisel-prompts mod, see PromptRelay). The field takes the foot of the card.
    readonly property string sid: { Relay.live; return Relay.best(s.id || "") } // (as its mod names it: see Relay.best)
    readonly property bool relayOn: sid !== "" && Relay.live.includes(sid)
    readonly property bool relayWaiting: Relay.waiting.includes(sid)
    readonly property int foot: relayOn ? 48 : 0
    readonly property bool inputFocus: input.activeFocus
    onSidChanged: if (sid !== "") Relay.watch(sid)
    Component.onCompleted: if (sid !== "") Relay.watch(sid)
    property string sentNote: ""
    Timer { id: sentOff; interval: 4000; onTriggered: root.sentNote = "" }
    Connections { target: Relay; function onTaken(id) { if (id === root.sid) { root.sentNote = Tr.t("Claude Code has it"); sentOff.restart() } } }

    // a: her colour. d: its deeper shade. on: text on it. (as in the chat)
    property string who: "miku"
    readonly property var palettes: ({
        miku:  { a: "#39C5BB", d: "#22968E", on: "#04302c" },
        rin:   { a: "#FFD24A", d: "#E0A92E", on: "#3d2c00" },
        luka:  { a: "#F5A3C0", d: "#D9779D", on: "#4a1630" },
        zunda: { a: "#B9DC6B", d: "#86B93F", on: "#24330a" },
        teto:  { a: "#E0405A", d: "#B02A44", on: "#FFFFFF" }
    })
    readonly property var pal: palettes[who] || palettes.miku
    readonly property color acc: pal.a
    readonly property color accDeep: pal.d
    readonly property color accInk: pal.on
    readonly property color accText: Theme.dark ? acc : Qt.darker(pal.d, 1.5)
    function tinted(a) { return Qt.rgba(acc.r, acc.g, acc.b, a) }
    readonly property color wash: Qt.tint(Theme.surface2, tinted(0.1))
    // one line of what a session said, whatever newlines it has
    function oneLine(t) { return (t || "").replace(/\s*\n\s*/g, "  ").trim() }

    width: 494
    readonly property int body: height - foot // what the bubble, the steps and the code share
    readonly property int side: 196           // the left column's width

    // ---- what you asked ----
    Rectangle {
        id: ask
        width: root.side
        height: askText.implicitHeight + 16
        radius: 12
        bottomLeftRadius: 4
        color: Qt.tint(Theme.surface2, root.tinted(0.22))
        border.width: 1.5; border.color: root.acc
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        Text {
            id: askText
            x: 10; y: 8
            width: parent.width - 20
            text: root.s.prompt ? root.oneLine(root.s.prompt) : Tr.t("No prompt yet")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: root.s.prompt ? Theme.ink : Theme.inkFaint
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }

    // ---- the steps: a clipped well, the newest at its foot ----
    Rectangle {
        id: well
        y: ask.height + 8
        width: root.side
        height: root.body - y - (root.relayOn ? 8 : 0)
        radius: 12
        color: Theme.well
        clip: true
        opacity: Motion.rise(root.age, 1)
        Column {
            id: steps
            x: 8
            width: parent.width - 16
            // (bottom-aligned: when there are more than fit, the oldest go out at the top)
            y: Math.min(8, well.height - height - 8)
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            spacing: 2
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
            move: Transition { NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic } }
            Repeater {
                model: root.s.steps || []
                Item {
                    id: step
                    required property var modelData
                    readonly property bool running: modelData.state === "running"
                    readonly property int times: modelData.times || 1
                    width: steps.width
                    height: 20
                    Rectangle { // the running one stands on a strip of her colour
                        anchors.fill: parent
                        anchors.leftMargin: -4; anchors.rightMargin: -4
                        radius: 8
                        color: root.tinted(0.16)
                        visible: step.running
                    }
                    Item {
                        id: mark
                        width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                        Spinner { anchors.fill: parent; visible: step.running }
                        DrawnCheck { // the check draws itself in 180 ms
                            anchors.centerIn: parent; size: 15; color: root.accText
                            progress: step.modelData.state === "done" ? 1 : 0
                            Behavior on progress { NumberAnimation { duration: 180 } }
                        }
                        Icon { anchors.centerIn: parent; size: 14; name: "cross"; color: Theme.danger; visible: step.modelData.state === "failed" }
                    }
                    Text {
                        x: 22
                        width: parent.width - 22 - (count.visible ? count.width + 4 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.oneLine(Tr.d(step.modelData.text))
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        color: step.running ? Theme.ink : Theme.inkMuted
                        font.family: Theme.sans; font.pixelSize: 12
                        font.weight: step.running ? Font.ExtraBold : Font.DemiBold
                    }
                    Rectangle { // the same step again: how many times, at the end of its line
                        id: count
                        visible: step.times > 1
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: countText.implicitWidth + 10; height: 16; radius: 8
                        color: root.tinted(0.25)
                        Text { id: countText; anchors.centerIn: parent; text: "\u00d7" + step.times; color: Theme.ink
                            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                    }
                }
            }
        }
        Text { // nothing done yet
            anchors.centerIn: parent
            visible: !(root.s.steps && root.s.steps.length)
            text: root.s.state === "think" ? Tr.t("Thinking") + "…" : "—"
            color: Theme.inkFaint
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Rectangle { // the older steps fade out at the top
            width: parent.width; height: 18
            visible: steps.y < 0
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.well }
                GradientStop { position: 1; color: Qt.rgba(Theme.well.r, Theme.well.g, Theme.well.b, 0) }
            }
        }
    }

    // ---- the file it is changing ----
    readonly property int codeX: side + 10
    CodePanel {
        id: code
        opacity: Motion.rise(root.age, 1)
        transform: Translate { y: Motion.lift(root.age, 1) }
        x: root.codeX
        width: parent.width - root.codeX
        height: root.body - (terminal.visible ? terminal.height + 8 : 0) - (root.relayOn ? 8 : 0)
        color: root.wash
        border.width: 1; border.color: root.tinted(0.35)
        lines: root.s.diff || []
        modified: !!root.s.file && (root.s.added > 0 || root.s.removed > 0)
        caption: root.s.file ? root.s.file + (root.s.added || root.s.removed ? "   +" + root.s.added + " −" + root.s.removed : "") : ""
        visible: !!root.s.file
    }
    Rectangle { // nothing changed yet: the place the file will be, empty
        x: root.codeX
        width: parent.width - root.codeX
        height: code.height
        visible: !root.s.file
        radius: Theme.radiusMd
        color: "transparent"
        border.width: 1.5; border.color: root.tinted(0.3)
        opacity: Motion.rise(root.age, 1)
        Column {
            anchors.centerIn: parent
            spacing: 6
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "folder"; size: 22; color: root.accText; opacity: 0.7 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Nothing changed yet")
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }
    }

    // ---- the last command: one line, in a pill ----
    Rectangle {
        id: terminal
        visible: !!root.s.command
        x: root.codeX
        y: root.body - height - (root.relayOn ? 8 : 0)
        width: parent.width - root.codeX
        height: 30
        radius: 10
        color: Theme.well
        clip: true
        opacity: Motion.rise(root.age, 2)
        Icon { id: termIcon; x: 10; anchors.verticalCenter: parent.verticalCenter; name: "terminal"; size: 15; color: root.accText }
        Text {
            x: 32
            width: parent.width - 42
            anchors.verticalCenter: parent.verticalCenter
            // one line only: a multi-line command (a heredoc, a script) shows its first line, and
            // without the `cd <folder> &&` it so often starts with (the folder is the session's own)
            text: (root.s.command || "").split("\n")[0].replace(/^(?:\s*cd\s+(?:"[^"]*"|'[^']*'|\S+)\s*(?:&&|;)\s*)+/, "")
            textFormat: Text.PlainText
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            color: Theme.ink
            font.family: Theme.mono; font.pixelSize: 12
        }
    }

    // ---- the field, while the session listens: as the chat's ----
    Rectangle {
        id: composer
        visible: root.relayOn
        y: parent.height - height
        width: parent.width
        height: 40
        radius: 20
        color: root.wash
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? root.acc : root.tinted(0.3)
        Rectangle { // a halo in her colour while you type
            anchors.fill: parent; anchors.margins: -4
            z: -1
            radius: 24
            color: root.tinted(0.18)
            opacity: input.activeFocus ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        TextInput {
            id: input
            x: 16
            width: parent.width - 16 - sendBtn.width - 12
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: Theme.ink
            selectionColor: root.acc
            selectedTextColor: root.accInk
            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
            function go() {
                if (text.trim() === "") return
                if (Relay.send(root.sid, text)) { text = ""; Sfx.play("send") }
                else { root.sentNote = Tr.t("Couldn't send it"); sentOff.restart(); Sfx.play("deny") }
            }
            onAccepted: go()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: root.sentNote !== "" ? root.sentNote : root.relayWaiting ? Tr.t("Sent. Claude takes it when it is free.") : Tr.t("Write to Claude Code")
                color: Theme.inkFaint
                font: input.font
            }
        }
        Rectangle {
            id: sendBtn
            width: 32; height: 32; radius: 16
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            color: sendTap.pressed ? root.accDeep : root.acc
            border.width: 2; border.color: "#FFFFFF"
            scale: sendTap.pressed ? 0.9 : sendHover.hovered ? 1.1 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Accessible.role: Accessible.Button
            Accessible.name: Tr.t("Send")
            Icon { anchors.centerIn: parent; size: 18; name: "send"; color: root.accInk }
            TapHandler { id: sendTap; onTapped: input.go() }
            HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
        }
    }
}
