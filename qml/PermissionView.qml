// The permission card: tool, a lemon "Needs you" tag, the command or diff,
// and Allow, Always, Deny with Allow first and focused. Kisel never answers
// for you: every decision here is an explicit click.
// In the sticker style of the Homes: keys with a white edge, Miku's teal for yes,
// Teto's red for no, lemon for what is waiting.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    readonly property var p: Hub.permission
    readonly property bool has: Hub.pendingCount > 0

    readonly property color teal: "#39C5BB"
    readonly property color deep: "#22968E"
    readonly property color red: "#E0405A"
    readonly property color lemon: "#FFE08A"

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
                height: 24; width: tag.implicitWidth + 22
                radius: 12
                color: root.lemon
                border.width: 2; border.color: "#FFFFFF"
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: tag
                    anchors.centerIn: parent
                    spacing: Theme.space1
                    Icon { name: "bell"; size: 14; color: "#3d2c00"; anchors.verticalCenter: parent.verticalCenter
                        // the bell rings: a short swing now and then
                        transformOrigin: Item.Top
                        SequentialAnimation on rotation {
                            running: root.active && !Theme.reduced
                            loops: Animation.Infinite
                            NumberAnimation { to: 16; duration: 90 }
                            NumberAnimation { to: -14; duration: 160 }
                            NumberAnimation { to: 9; duration: 140 }
                            NumberAnimation { to: 0; duration: 120 }
                            PauseAnimation { duration: 2200 }
                        }
                    }
                    Text { text: Tr.t("Needs you"); color: "#3d2c00"; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.p.tool || ""
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 16; font.weight: Font.Bold
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
                    Text { text: Tr.t("\u00b7  1 of"); color: Theme.inkFaint; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
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
            radius: 12
            border.width: 2
            border.color: Qt.rgba(root.lemon.r, root.lemon.g, root.lemon.b, 0.55)
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
                            text: q.modelData.header + (q.modelData.multi ? Tr.t("  \u00b7  pick any") : "")
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
                                    height: 30; width: chipRow.implicitWidth + 26
                                    radius: 10
                                    color: on ? root.teal : Qt.rgba(root.teal.r, root.teal.g, root.teal.b, ch.hovered ? 0.32 : 0.14)
                                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                                    border.width: 2; border.color: "#FFFFFF"
                                    scale: ct.pressed ? 0.94 : ch.hovered ? 1.05 : 1
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                    Accessible.role: q.modelData.multi ? Accessible.CheckBox : Accessible.RadioButton
                                    Accessible.name: modelData.label
                                    Accessible.checked: on
                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        DrawnCheck { visible: chip.on; size: 14; color: "#04302c"; anchors.verticalCenter: parent.verticalCenter }
                                        Text {
                                            id: lab
                                            text: chip.modelData.label
                                            color: chip.on ? "#04302c" : Theme.ink
                                            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
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
            Key {
                id: allowBtn
                visible: root.p.kind !== "question"
                kind: "yes"; icon: "check"; text: Tr.t("Allow")
                onClicked: Hub.allow(root.p.id)
            }
            Key {
                visible: root.p.kind !== "question" && root.p.canAlways === true
                kind: "soft"; text: Tr.t("Always")
                onClicked: Hub.always(root.p.id)
            }
            Key {
                visible: root.p.kind !== "question"
                kind: "no"; icon: "cross"; text: Tr.t("Deny")
                onClicked: Hub.deny(root.p.id)
            }
            Key {
                visible: root.p.kind === "question"
                id: sendBtn
                kind: "yes"; icon: "send"; text: Tr.t("Send answer")
                enabled: root.answered
                onClicked: root.submit()
            }
            Key {
                visible: root.p.kind === "question"
                kind: "plain"; icon: "terminal"; text: Tr.t("Reply in terminal")
                onClicked: Hub.passToTerminal(root.p.id)
            }
            Key {
                visible: root.p.kind !== "question"
                kind: "plain"; icon: "terminal"; text: Tr.t("In terminal")
                onClicked: Hub.passToTerminal(root.p.id)
            }
        }
    }

    // a key: yes (teal), no (red), soft (a teal wash), plain (only the edge)
    component Key: FocusScope {
        id: k
        property string text: ""
        property string icon: ""
        property string kind: "soft"
        signal clicked()
        readonly property color fg: kind === "yes" ? "#04302c" : kind === "no" ? "#FFFFFF" : Theme.ink
        implicitWidth: keyRow.implicitWidth + 30
        implicitHeight: 36
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: k.clicked()
        Rectangle {
            id: face
            anchors.fill: parent
            radius: 12
            opacity: k.enabled ? 1 : 0.4
            color: k.kind === "yes" ? (kt.pressed ? root.deep : root.teal)
                : k.kind === "no" ? (kt.pressed ? Qt.darker(root.red, 1.2) : root.red)
                : k.kind === "soft" ? Qt.rgba(root.teal.r, root.teal.g, root.teal.b, kt.pressed ? 0.5 : kh.hovered ? 0.32 : 0.14)
                : Qt.rgba(root.teal.r, root.teal.g, root.teal.b, kt.pressed ? 0.3 : kh.hovered ? 0.16 : 0)
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            border.width: 2
            border.color: k.kind === "plain" ? Theme.inkFaint : "#FFFFFF"
            scale: kt.pressed ? 0.94 : kh.hovered && k.enabled ? 1.05 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Row {
                id: keyRow
                anchors.centerIn: parent
                spacing: Theme.space1
                Icon { visible: k.icon !== ""; name: k.icon; size: 16; color: k.fg; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: k.text
                    color: k.fg
                    font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.ExtraBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        // focus: a lemon ring just off the key
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            visible: k.activeFocus
            radius: 16
            color: "transparent"
            border.width: 2
            border.color: root.lemon
        }
        HoverHandler { id: kh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered && k.enabled) Sfx.play("hover") }
        TapHandler { id: kt; onTapped: k.clicked() }
        Keys.onReturnPressed: k.clicked()
        Keys.onSpacePressed: k.clicked()
    }
}
