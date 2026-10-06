// The permission card: tool, an amber "Needs you" tag, the command or diff,
// and Allow, Always, Deny with Allow first and focused. Kisel never answers
// for you: every decision here is an explicit click.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    readonly property var p: Hub.permission
    readonly property bool has: Hub.pendingCount > 0

    width: 494
    onActiveChanged: if (active) allowBtn.forceActiveFocus()

    // Next permission in the queue: the old card slides 24 px left and fades out (140 ms),
    // the next slides in from 24 px right and fades in (140 ms, 40 ms later). The old
    // card is a frozen copy of the page: it is frozen the moment the answer is given,
    // before the next request's data replaces it.
    Connections {
        target: Hub
        function onPermissionAnswered(decision) {
            if (!root.active || Hub.pendingCount === 0 || Theme.reduced) return
            ghost.live = false      // freeze what is on screen now
            ghost.visible = true
            ghostSlide.restart()
            pageSlide.restart()
        }
    }
    ShaderEffectSource {
        id: ghost
        sourceItem: page
        live: true
        visible: false
        width: page.width; height: page.height
        hideSource: false
        z: 2
    }
    ParallelAnimation {
        id: ghostSlide
        NumberAnimation { target: ghost; property: "x"; from: 0; to: -24; duration: 140; easing.type: Easing.OutCubic }
        NumberAnimation { target: ghost; property: "opacity"; from: 1; to: 0; duration: 140 }
        onFinished: { ghost.visible = false; ghost.x = 0; ghost.opacity = 1; ghost.live = true }
    }
    SequentialAnimation {
        id: pageSlide
        ScriptAction { script: { page.x = 24; page.opacity = 0 } }
        PauseAnimation { duration: 40 }
        ParallelAnimation {
            NumberAnimation { target: page; property: "x"; to: 0; duration: 140; easing.type: Easing.OutCubic }
            NumberAnimation { target: page; property: "opacity"; to: 1; duration: 140 }
        }
    }

    // Claude's question(s): pick answers and send them back (up to four questions,
    // single or multi-select). They go to Claude Code as the tool's answers.
    property var picks: ({})
    readonly property var questions: root.p.questions || []
    readonly property bool answered: {
        if (questions.length === 0) return false
        for (let i = 0; i < questions.length; ++i)
            if (!picks[i] || picks[i].length === 0) return false
        return true
    }
    onPChanged: picks = ({})
    function pick(qi, label, multi) {
        const next = Object.assign({}, picks)
        const cur = (next[qi] || []).slice()
        const at = cur.indexOf(label)
        if (multi) { if (at >= 0) cur.splice(at, 1); else cur.push(label); next[qi] = cur }
        else next[qi] = [label]
        picks = next
    }
    function submit() {
        const out = {}
        for (let i = 0; i < questions.length; ++i)
            out[questions[i].question] = picks[i].join(", ")
        Hub.answerQuestion(root.p.id, out)
    }

    Item {
        id: page
        width: parent.width
        height: parent.height

        Row {
            id: top
            spacing: Theme.space2
            height: 28
            Rectangle {
                height: 24; width: tag.implicitWidth + 24
                radius: Theme.radiusPill
                color: Theme.amber
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: tag
                    anchors.centerIn: parent
                    spacing: Theme.space1
                    Icon { name: "bell"; size: 14; color: Theme.surface0; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Needs you"; color: Theme.surface0; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.p.tool || ""
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.ExtraBold
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: root.p.session || ""
                    color: Theme.inkFaint
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Row {
                    visible: Hub.pendingCount > 1
                    spacing: 3
                    Text { text: "\u00b7  1 of"; color: Theme.inkFaint; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
                    RollText { text: String(Hub.pendingCount) }
                }
            }
        }

        // command or diff
        CodePanel {
            visible: root.p.kind !== "question"
            y: top.height + Theme.space2
            width: parent.width
            height: buttons.y - y - Theme.space2
            command: root.p.kind === "command" ? (root.p.summary || "") : ""
            lines: root.p.kind === "diff" ? root.p.diff : []
            caption: root.p.kind === "diff" ? (root.p.file + "   +" + root.p.added + " −" + root.p.removed) : ""
        }

        Flickable {
            id: qflick
            visible: root.p.kind === "question"
            y: top.height + Theme.space2
            width: parent.width
            height: buttons.y - y - Theme.space2
            contentHeight: qcol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: qcol
                width: qflick.width
                spacing: Theme.space3
                Repeater {
                    model: root.questions
                    Column {
                        id: q
                        required property var modelData
                        required property int index
                        width: qcol.width
                        spacing: Theme.space1
                        Text {
                            visible: q.modelData.header !== ""
                            text: q.modelData.header + (q.modelData.multi ? "  \u00b7  pick any" : "")
                            color: Theme.inkFaint
                            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: q.modelData.question
                            wrapMode: Text.Wrap
                            color: Theme.ink
                            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.space2
                            Repeater {
                                model: q.modelData.options
                                Rectangle {
                                    id: chip
                                    required property var modelData
                                    readonly property bool on: !!root.picks[q.index] && root.picks[q.index].indexOf(modelData.label) >= 0
                                    height: 30; width: lab.implicitWidth + 28
                                    radius: Theme.radiusPill
                                    color: on ? Theme.kisel : (ch.hovered ? Theme.surface3 : Theme.surface2)
                                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                                    scale: ct.pressed ? 0.96 : 1
                                    Behavior on scale { NumberAnimation { duration: Theme.tPress } }
                                    Accessible.role: q.modelData.multi ? Accessible.CheckBox : Accessible.RadioButton
                                    Accessible.name: modelData.label
                                    Accessible.checked: on
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        DrawnCheck { visible: chip.on; size: 14; color: Theme.onKisel; anchors.verticalCenter: parent.verticalCenter }
                                        Text {
                                            id: lab
                                            text: chip.modelData.label
                                            color: chip.on ? Theme.onKisel : Theme.ink
                                            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { id: ct; onTapped: root.pick(q.index, chip.modelData.label, q.modelData.multi) }
                                }
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: buttons
            y: parent.height - height
            spacing: Theme.space2
            KButton {
                id: allowBtn
                visible: root.p.kind !== "question"
                variant: "primary"; icon: "check"; text: "Allow"
                onClicked: Hub.allow(root.p.id)
            }
            KButton {
                visible: root.p.kind !== "question" && root.p.canAlways === true
                variant: "secondary"; text: "Always"
                onClicked: Hub.always(root.p.id)
            }
            KButton {
                visible: root.p.kind !== "question"
                variant: "danger"; icon: "cross"; text: "Deny"
                onClicked: Hub.deny(root.p.id)
            }
            KButton {
                visible: root.p.kind === "question"
                id: sendBtn
                variant: "primary"; icon: "send"; text: "Send answer"
                enabled: root.answered
                onClicked: root.submit()
            }
            KButton {
                visible: root.p.kind === "question"
                variant: "ghost"; icon: "terminal"; text: "Reply in terminal"
                onClicked: Hub.passToTerminal(root.p.id)
            }
            KButton {
                visible: root.p.kind !== "question"
                variant: "ghost"; icon: "terminal"; text: "In terminal"
                onClicked: Hub.passToTerminal(root.p.id)
            }
        }
    }
}
