// Session: the steps Claude took (left), the file it is changing (right) and
// the last command. Pending steps are dim, the running one shows a spinner.
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
    readonly property int foot: relayOn ? 44 : 0
    readonly property bool inputFocus: promptField.inputFocus
    onSidChanged: if (sid !== "") Relay.watch(sid)
    Component.onCompleted: if (sid !== "") Relay.watch(sid)
    property string sentNote: ""
    Timer { id: sentOff; interval: 4000; onTriggered: root.sentNote = "" }
    Connections { target: Relay; function onTaken(id) { if (id === root.sid) { root.sentNote = Tr.t("Claude Code has it"); sentOff.restart() } } }

    width: 494

    KField {
        id: promptField
        visible: root.relayOn
        x: 0; y: parent.height - 36
        width: parent.width - sendKey.width - 8
        placeholder: root.sentNote !== "" ? root.sentNote : root.relayWaiting ? Tr.t("Sent. Claude takes it when it is free.") : Tr.t("Write to Claude Code")
        function go() {
            if (text.trim() === "") return
            if (Relay.send(root.sid, text)) { text = ""; Sfx.play("send") }
            else { root.sentNote = Tr.t("Couldn't send it"); sentOff.restart(); Sfx.play("deny") }
        }
        onAccepted: go()
    }
    KButton {
        id: sendKey
        visible: root.relayOn
        x: parent.width - width; y: parent.height - 36
        primary: true
        text: Tr.t("Send")
        onClicked: promptField.go()
    }

    // steps
    Column {
        id: steps
        width: 190
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        // rows that appear fade in; the rest slide to their new place in 220 ms
        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        move: Transition { NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic } }
        spacing: Theme.space1
        Text {
            width: parent.width
            text: root.s.prompt ? root.s.prompt : Tr.t("No prompt yet")
            elide: Text.ElideRight
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
        }
        Repeater {
            model: root.s.steps || []
            Row {
                id: step
                required property var modelData
                readonly property bool running: modelData.state === "running"
                spacing: Theme.space2
                height: 22
                Item {
                    width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                    Spinner { anchors.fill: parent; visible: step.running }
                    DrawnCheck { // the check draws itself in 180 ms
                        anchors.centerIn: parent; size: 16; color: Theme.kisel
                        progress: step.modelData.state === "done" ? 1 : 0
                        Behavior on progress { NumberAnimation { duration: 180 } }
                    }
                    Icon { anchors.centerIn: parent; size: 14; name: "cross"; color: Theme.danger; visible: step.modelData.state === "failed" }
                }
                Text {
                    width: 190 - 24
                    text: Tr.d(step.modelData.text)
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: step.running ? Theme.ink : Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 13
                    font.weight: step.running ? Font.ExtraBold : Font.DemiBold
                }
            }
        }
    }

    // code panel
    CodePanel {
        opacity: Motion.rise(root.age, 1)
        transform: Translate { y: Motion.lift(root.age, 1) }
        x: 202
        width: parent.width - 202
        height: (terminal.visible ? parent.height - 48 : parent.height) - root.foot
        lines: root.s.diff || []
        modified: !!root.s.file && (root.s.added > 0 || root.s.removed > 0)
        caption: root.s.file ? root.s.file + (root.s.added || root.s.removed ? "   +" + root.s.added + " −" + root.s.removed : "") : ""
        visible: !!root.s.file
    }
    Text {
        x: 202
        visible: !root.s.file
        text: Tr.t("Nothing changed yet")
        color: Theme.inkFaint
        font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
    }

    // terminal: the command, separated by a hairline
    Item {
        id: terminal
        opacity: Motion.rise(root.age, 2)
        visible: !!root.s.command
        x: 202
        y: parent.height - 40 - root.foot
        width: parent.width - 202
        height: 40
        clip: true
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Row {
            y: 10
            spacing: Theme.space2
            Icon { name: "terminal"; size: 16; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
            Text {
                width: terminal.width - 28
                // one line only: a multi-line command (a heredoc, a script) shows its first line
                text: (root.s.command || "").split("\n")[0]
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.mono; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
