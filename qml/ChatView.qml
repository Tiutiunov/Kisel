// Chat with Claude. Text shows exactly as it streams (no typewriter). Dropping
// a file puts it above the input as a chip.
//
// The room is dressed for whoever is on stage (`who`): her colour is in the glow behind
// the messages, the sparkles, your bubbles, the edge of Claude's, the composer and the
// send button, and she sits in the empty chat waiting. Changing her changes the room.
import QtQuick
import QtQuick.Controls.Basic as C
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    property bool dropActive: false
    readonly property bool inputFocus: input.activeFocus

    // a: her colour. d: its deeper shade. on: text on it.
    property string who: "miku"
    readonly property var palettes: ({
        miku:  { name: "Miku",     a: "#39C5BB", d: "#22968E", on: "#04302c" },
        rin:   { name: "Rin",      a: "#FFD24A", d: "#E0A92E", on: "#3d2c00" },
        luka:  { name: "Luka",     a: "#F5A3C0", d: "#D9779D", on: "#4a1630" },
        zunda: { name: "Zundamon", a: "#B9DC6B", d: "#86B93F", on: "#24330a" },
        teto:  { name: "Teto",     a: "#E0405A", d: "#B02A44", on: "#FFFFFF" }
    })
    readonly property var pal: palettes[who] || palettes.miku
    readonly property color acc: pal.a
    readonly property color accDeep: pal.d
    readonly property color onAcc: pal.on
    function tinted(a) { return Qt.rgba(acc.r, acc.g, acc.b, a) }
    readonly property color wash: Qt.tint(Theme.surface2, tinted(0.1))

    width: 494
    // focus the input once the fade ends
    onActiveChanged: if (active) focusTimer.restart()
    Timer { id: focusTimer; interval: Theme.tFast; onTriggered: input.forceActiveFocus() }

    // While the Claude Code session has someone listening for prompts (the kisel-prompts
    // mod, see PromptRelay) this is where you write to it: what you send goes to that
    // session as your own prompt, and Claude answers there. It needs no API key. Without
    // a listening session the chat is the one with the API, as before.
    readonly property string sid: Hub.session.id || ""
    readonly property bool relayOn: sid !== "" && Relay.live.includes(sid)
    readonly property bool relayWaiting: Relay.waiting.includes(sid)
    onSidChanged: if (sid !== "") Relay.watch(sid)
    Component.onCompleted: if (sid !== "") Relay.watch(sid)
    ListModel { id: sent } // the talk with the session, as seen from here: {role, text, file, time}
    property string relayNote: ""
    Timer { id: relayNoteOff; interval: 4000; onTriggered: root.relayNote = "" }
    Connections {
        target: Relay
        // (what Claude says in the session comes back here, so the chat has both sides)
        function onReply(id, text) {
            if (id !== root.sid) return
            sent.append({ role: "assistant", text: text, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
            if (root.active) Sfx.play("receive")
        }
    }

    function send() {
        if (input.text.trim() === "")
            return
        if (relayOn) {
            const text = input.text.trim()
            if (!Relay.send(sid, text)) { relayNote = Tr.t("Couldn't send it"); relayNoteOff.restart(); Sfx.play("deny"); return }
            Sfx.play("send")
            sent.append({ role: "user", text: text, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
            input.text = ""
            return
        }
        if (Chat.busy)
            return
        Sfx.play("send")
        Chat.send(input.text)
        input.text = ""
    }
    Connections {
        target: Chat
        function onReplyFinished() { Sfx.play("receive") }
    }

    // What Claude writes is Markdown, and it is model output: untrusted. So everything is
    // escaped first, and then the marks that matter in a chat bubble are turned into tags
    // of our own, never the text's: code and ``` blocks in the mono face, headings and
    // **bold**, *italic*, ~~struck~~, lists with a dot, quotes, rules, and tables as rows.
    // A link keeps its words and loses its address (nothing here can be clicked), and an
    // image is only its caption: nothing is ever fetched.
    function styled(text, mine) {
        const mono = Theme.mono
        const codeInk = mine ? root.onAcc : Theme.inkMuted
        const faint = mine ? root.onAcc : Theme.inkFaint
        const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const code = (t) => "<font face=\"" + mono + "\" color=\"" + codeInk + "\">" + t + "</font>"
        // inline marks, on text already escaped; `code` is set aside first so nothing inside it is touched
        const inline = (t) => {
            const kept = []
            t = t.replace(/`([^`\n]+)`/g, (m, c) => { kept.push(code(c)); return "\u0001" + (kept.length - 1) + "\u0001" })
            t = t.replace(/!\[([^\]\n]*)\]\([^)\n]*\)/g, "$1")
            t = t.replace(/\[([^\]\n]+)\]\([^)\n]*\)/g, "$1")
            t = t.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>").replace(/__([^_\n]+)__/g, "<b>$1</b>")
            t = t.replace(/(^|[\s(])\*([^*\s][^*\n]*)\*/g, "$1<i>$2</i>").replace(/(^|[\s(])_([^_\s][^_\n]*)_(?=$|[\s).,!?:;])/g, "$1<i>$2</i>")
            t = t.replace(/~~([^~\n]+)~~/g, "<s>$1</s>")
            return t.replace(/\u0001(\d+)\u0001/g, (m, n) => kept[Number(n)])
        }
        const cells = (line) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => c.trim())
        const out = []
        const parts = text.split(/```/)
        for (let k = 0; k < parts.length; k++) {
            if (k % 2 === 1) { // inside a fence: as it is, less the language on its first line
                const body = parts[k].replace(/^[a-zA-Z0-9_+-]*\n/, "").replace(/\n+$/, "")
                out.push("<pre>" + code(esc(body)) + "</pre>")
                continue
            }
            const lines = esc(parts[k]).split("\n")
            let tableHead = true
            for (let n = 0; n < lines.length; n++) {
                const line = lines[n], trimmed = line.trim()
                if (/^\|.*\|$/.test(trimmed)) { // a table row; the row of dashes under the heading is dropped
                    if (/^\|[\s:|-]+\|$/.test(trimmed)) { tableHead = false; continue }
                    const row = cells(trimmed).map(inline).join(" <font color=\"" + faint + "\">\u00b7</font> ")
                    out.push((tableHead ? "<b>" + row + "</b>" : row) + "<br>")
                    continue
                }
                tableHead = true
                let m
                if (trimmed === "") out.push("<br>")
                else if ((m = /^#{1,6}\s+(.*)$/.exec(trimmed))) out.push("<b>" + inline(m[1]) + "</b><br>")
                else if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) out.push("<font color=\"" + faint + "\">\u2014\u2014\u2014</font><br>")
                else if ((m = /^(\s*)[-*+]\s+(.*)$/.exec(line))) out.push("&nbsp;".repeat(Math.min(8, m[1].length) + 1) + "\u2022 " + inline(m[2]) + "<br>")
                else if ((m = /^(\s*)(\d+[.)])\s+(.*)$/.exec(line))) out.push("&nbsp;".repeat(Math.min(8, m[1].length) + 1) + m[2] + " " + inline(m[3]) + "<br>")
                else if ((m = /^&gt;\s?(.*)$/.exec(trimmed))) out.push("<font color=\"" + faint + "\"><i>" + inline(m[1]) + "</i></font><br>")
                else out.push(inline(line) + "<br>")
            }
        }
        // (no blank line left at either end, and never more than one in a row)
        return out.join("").replace(/(<br>)+<pre>/g, "<pre>").replace(/<\/pre>(<br>)+/g, "</pre>") // (a block brings its own space)
            .replace(/(<br>){3,}/g, "<br><br>").replace(/^(<br>)+/, "").replace(/(<br>)+$/, "")
    }

    // her colour in the room: a soft glow in two corners, and sparkles that turn slowly.
    // (The glow is painted over the whole card, which this view sits inside at 150, 48,
    // and cut to the card's own round corners: it used to be plain discs, and showed as
    // a tinted square in the corners outside the card's outline.)
    Canvas {
        id: glow
        x: -150; y: -48
        width: 660; height: root.height + 62
        property color tint: root.acc
        onTintChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d"), w = width, h = height, r = 26
            g.reset()
            g.beginPath(); g.moveTo(r, 0); g.lineTo(w - r, 0); g.quadraticCurveTo(w, 0, w, r); g.lineTo(w, h - r); g.quadraticCurveTo(w, h, w - r, h)
            g.lineTo(r, h); g.quadraticCurveTo(0, h, 0, h - r); g.lineTo(0, r); g.quadraticCurveTo(0, 0, r, 0); g.closePath(); g.clip()
            const spot = (cx, cy, a) => {
                const gr = g.createRadialGradient(cx, cy, 30, cx, cy, 261)
                gr.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, a)); gr.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0))
                g.fillStyle = gr; g.fillRect(0, 0, w, h)
            }
            spot(150 + 30, 48 + 10, 0.24)
            spot(150 + root.width - 30, 48 + root.height - 40, 0.176)
        }
    }
    Repeater {
        model: [{ x: 18, y: 22, s: 12 }, { x: 452, y: 44, s: 9 }, { x: 398, y: 196, s: 14 }, { x: 60, y: 232, s: 8 }, { x: 250, y: 96, s: 7 }]
        Spark {
            id: mote
            required property var modelData
            required property int index
            x: modelData.x; y: modelData.y
            size: modelData.s
            tint: index % 2 ? "#FFFFFF" : root.acc
            opacity: list.count === 0 ? 0.55 : 0.16
            Behavior on opacity { NumberAnimation { duration: 400 } }
            SequentialAnimation on scale {
                running: root.active && !Theme.reduced
                loops: Animation.Infinite
                PauseAnimation { duration: mote.index * 330 }
                NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.1; duration: 700; easing.type: Easing.OutBack }
                PauseAnimation { duration: 1200 }
            }
            RotationAnimation on rotation { running: root.active && !Theme.reduced; from: 0; to: 90; duration: 6000 + mote.index * 900; loops: Animation.Infinite }
        }
    }

    // messages
    ListView {
        id: list
        width: parent.width
        height: composer.y - Theme.space2
        model: root.relayOn ? sent : Chat.messages
        spacing: Theme.space2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onCountChanged: positionViewAtEnd()
        onContentHeightChanged: if (atYEnd || Chat.busy) positionViewAtEnd()
        C.ScrollBar.vertical: C.ScrollBar { policy: C.ScrollBar.AsNeeded }

        delegate: Item {
            id: msg
            required property string role
            required property string text
            required property string file
            required property string time
            required property int index
            readonly property bool mine: role === "user"
            readonly property bool lastReply: !mine && index === list.count - 1 && !Chat.busy && text !== ""
            width: ListView.view.width
            height: bubble.height + (lastReply ? 18 : 0)

            Rectangle { visible: msg.lastReply; x: 6; y: bubble.height + 7; width: 6; height: 6; radius: 3; color: root.acc }
            Text {
                visible: msg.lastReply
                x: 17
                y: bubble.height + 2
                text: root.pal.name + " \u00b7 " + msg.time
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
            Rectangle {
                id: bubble
                // A new bubble rises 8 px while fading in over 140 ms
                x: msg.mine ? parent.width - width - 8 : 0
                width: Math.min(parent.width * 0.86, body.implicitWidth + 24)
                height: body.implicitHeight + (chip.visible ? 28 : 0) + 20
                radius: Theme.radiusMd
                // one corner is squared toward the speaker
                bottomRightRadius: msg.mine ? 4 : Theme.radiusMd
                bottomLeftRadius: msg.mine ? Theme.radiusMd : 4
                // yours is in her colour; Claude's is the surface with a breath of it and her edge
                color: msg.mine ? root.acc : root.wash
                gradient: msg.mine ? mineShade : null
                border.width: msg.mine ? 0 : 1
                border.color: root.tinted(0.3)
                Gradient {
                    id: mineShade
                    GradientStop { position: 0; color: root.acc }
                    GradientStop { position: 1; color: root.accDeep }
                }
                // a new bubble rises 8 px while fading in over 140 ms (OutCubic)
                property real appear: Theme.reduced ? 1 : 0
                opacity: appear
                transform: Translate { y: (1 - bubble.appear) * 8 }
                NumberAnimation on appear { to: 1; duration: Theme.tFast; easing.type: Easing.OutCubic; running: !Theme.reduced }

                Column {
                    x: 12; y: 10
                    width: parent.width - 24
                    spacing: 4
                    Rectangle {
                        id: chip
                        visible: msg.file !== ""
                        height: 24; width: chipText.implicitWidth + 32; radius: 12
                        color: Qt.rgba(0, 0, 0, 0.18)
                        Row { anchors.centerIn: parent; spacing: 4
                            Icon { name: "clip"; size: 14; color: msg.mine ? root.onAcc : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                            Text { id: chipText; text: msg.file; color: msg.mine ? root.onAcc : Theme.ink
                                font.family: Theme.mono; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    JellyTrio {
                        // before the first token: the waiting loader, not a bare ellipsis
                        visible: msg.text === "" && !msg.mine
                        running: visible && Chat.busy
                        height: visible ? 16 : 0
                        width: 120
                    }
                    Text {
                        id: body
                        visible: msg.text !== ""
                        width: parent.width
                        // Model output is untrusted: it is escaped first, then only
                        // `code` and ``` blocks become our own font tags. No links.
                        text: msg.text === "" ? "" : root.styled(msg.text, msg.mine)
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        color: msg.mine ? root.onAcc : Theme.ink
                        font.family: Theme.sans; font.pixelSize: 13; font.weight: msg.mine ? Font.DemiBold : Font.Medium // (Claude's is lighter, so its **bold** shows)
                        lineHeight: 18; lineHeightMode: Text.FixedHeight
                    }
                }
            }
        }

        // empty chat: ready and listening
        Column {
            visible: list.count === 0
            anchors.centerIn: parent
            spacing: Theme.space2
            // she waits here, in a ring of her colour
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76; height: 76
                Rectangle { anchors.fill: parent; radius: 38; color: root.tinted(0.14); border.width: 2; border.color: root.tinted(0.5) }
                Mascot {
                    anchors.centerIn: parent
                    size: 44
                    character: root.who
                    bench: true
                    paused: !(root.active && list.count === 0)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.relayOn ? Tr.t("Write to Claude Code") : Tr.t("Ask Claude anything")
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.relayOn ? Tr.t("It goes to your session as your own prompt") : root.pal.name + Tr.t(" is listening")
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }
    }

    // composer
    Column {
        id: composer
        y: parent.height - height
        width: parent.width
        spacing: Theme.space1

        Rectangle { // error line on diff-del-bg
            visible: Chat.error !== "" && !root.relayOn
            width: parent.width; height: 26; radius: Theme.radiusSm
            color: Theme.diffDelBg
            Row { x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.space1
                Icon { name: "cross"; size: 14; color: Theme.danger; anchors.verticalCenter: parent.verticalCenter }
                Text { width: 440; elide: Text.ElideRight; text: Tr.d(Chat.error); color: Theme.danger
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
        }
        Row {
            // (with a Claude Code session the model is named in the left column, and how a
            // message fares is said in the field itself: nothing is kept here to crowd the talk)
            visible: !root.relayOn || Chat.attachedName !== ""
            spacing: Theme.space2
            Rectangle {
                visible: !root.relayOn
                height: 20; width: modelName.implicitWidth + 18; radius: 10
                color: root.tinted(0.14)
                Text { id: modelName; anchors.centerIn: parent; text: Chat.model; color: Theme.inkMuted; font.family: Theme.mono; font.pixelSize: 11 }
            }
            Rectangle {
                visible: Chat.attachedName !== ""
                height: 20; width: attach.implicitWidth + 36; radius: 10; color: Theme.surface3
                Row { anchors.centerIn: parent; spacing: 4
                    Icon { name: "clip"; size: 12; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: attach; text: Chat.attachedName; color: Theme.ink; font.family: Theme.mono; font.pixelSize: 11 }
                    Icon { name: "cross"; size: 12; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter
                        TapHandler { onTapped: Chat.detach() } }
                }
            }
        }
        Rectangle {
            width: parent.width
            // grows with its text in 100 ms, up to 110 px
            height: Math.min(110, Math.max(40, input.contentHeight + 22))
            Behavior on height { NumberAnimation { duration: 100 } }
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

            C.ScrollView {
                anchors { left: parent.left; right: sendBtn.left; top: parent.top; bottom: parent.bottom; margins: 4; leftMargin: 12 }
                C.TextArea {
                    id: input
                    placeholderText: !root.relayOn ? Tr.t("Message Claude")
                        : root.relayNote !== "" ? root.relayNote
                        : root.relayWaiting ? Tr.t("Sent. Claude takes it when it is free.") : Tr.t("Write to Claude Code")
                    placeholderTextColor: Theme.inkFaint
                    wrapMode: TextEdit.Wrap
                    color: Theme.ink
                    selectionColor: root.acc
                    selectedTextColor: root.onAcc
                    font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    background: null
                    Keys.onPressed: (e) => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                            root.send()
                            e.accepted = true
                        }
                    }
                }
            }
            Rectangle {
                id: sendBtn
                width: 32; height: 32; radius: 16
                anchors { right: parent.right; rightMargin: 4; bottom: parent.bottom; bottomMargin: 4 }
                readonly property bool busy: Chat.busy && !root.relayOn
                color: busy ? Theme.surface3 : (sendTap.pressed ? root.accDeep : root.acc)
                border.width: busy ? 0 : 2
                border.color: "#FFFFFF"
                scale: sendTap.pressed ? 0.9 : sendHover.hovered ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Accessible.role: Accessible.Button
                Accessible.name: busy ? Tr.t("Stop") : Tr.t("Send")
                Icon { anchors.centerIn: parent; size: 18; name: sendBtn.busy ? "cross" : "send"; color: sendBtn.busy ? Theme.ink : root.onAcc }
                TapHandler { id: sendTap; onTapped: sendBtn.busy ? Chat.cancel() : root.send() }
                HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
            }
        }
    }

    // drop overlay: dark, 2 px kisel outline, one line of text
    Rectangle {
        anchors.fill: parent
        anchors.margins: -8
        radius: Theme.radiusMd
        color: Qt.rgba(0.055, 0.043, 0.051, 0.88)
        border.width: 2
        border.color: root.acc
        opacity: root.dropActive ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
        Column {
            anchors.centerIn: parent
            spacing: Theme.space3
            DotWave { anchors.horizontalCenter: parent.horizontalCenter; drop: true; running: root.dropActive }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Drop the file on me")
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.ExtraBold
            }
        }
    }
}
