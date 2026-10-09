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
    readonly property color accInk: pal.on
    readonly property color accText: Theme.dark ? acc : Qt.darker(pal.d, 1.5) // (the accent as ink: deep enough to read on the light card)
    function tinted(a) { return Qt.rgba(acc.r, acc.g, acc.b, a) }
    readonly property color wash: Qt.tint(Theme.surface2, tinted(0.1))
    readonly property color mineFill: Qt.tint(Theme.surface2, tinted(0.3))

    width: 494
    // focus the input once the fade ends
    onActiveChanged: if (active) focusTimer.restart()
    Timer { id: focusTimer; interval: Theme.tFast; onTriggered: input.forceActiveFocus() }

    // While the Claude Code session has someone listening for prompts (the kisel-prompts
    // mod, see PromptRelay) this is where you write to it: what you send goes to that
    // session as your own prompt, and Claude answers there. It needs no API key. Without
    // a listening session the chat is the one with the API, as before.
    // Which session: the newest one, unless another was picked from the row of projects
    // above the talk (`picked`, by the id the hooks know it by; it stands while that
    // session lives). Each project has a talk of its own, kept on disk by its folder
    // (`key`), so it is there after a restart and carries on in a new session there.
    property string picked: ""
    property bool live: false // false while a talk is being read back: nothing makes an entrance then
    Timer { id: liveSoon; interval: 400; onTriggered: root.live = true }
    onPickedChanged: { live = false; liveSoon.restart() }
    // "quick" is the talk outside any session: a question answered by a `claude -p` of its
    // own (see QuickAsk). It is there after a restart, in the same small store as the
    // projects' talks, until it is started over with the key beside the models.
    readonly property string quickKey: "kisel:quick"
    readonly property bool quick: picked === "quick"
    ListModel { id: quickTalk }
    function quickTurns() { const out = []; for (let i = 0; i < quickTalk.count; ++i) out.push({ role: quickTalk.get(i).role, text: quickTalk.get(i).text }); return out }
    function modelName(m) { return m === "" ? Tr.t("Auto") : m.charAt(0).toUpperCase() + m.slice(1) }
    function effortName(e) { return e === "" ? Tr.t("Auto") : e === "low" ? Tr.t("Low") : e === "medium" ? Tr.t("Medium") : e === "high" ? Tr.t("High") : e === "xhigh" ? Tr.t("Higher") : Tr.t("Max") }
    Connections {
        target: Quick
        // (the answer comes as it is written: one bubble, growing; its last word is the whole of it)
        function onPartial(soFar) {
            if (root.quickDraft < 0 || root.quickDraft >= quickTalk.count) {
                quickTalk.append({ role: "assistant", text: soFar, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
                root.quickDraft = quickTalk.count - 1
            } else quickTalk.setProperty(root.quickDraft, "text", soFar)
            root.quickLooking = false
        }
        function onLooking() {
            root.quickLooking = true
            if (root.quickDraft >= 0 && root.quickDraft < quickTalk.count) { quickTalk.remove(root.quickDraft); root.quickDraft = -1 } // (a remark before it went to look)
        }
        function onAnswered(text) {
            Relay.remember(root.quickKey, "assistant", text)
            if (root.quickDraft >= 0 && root.quickDraft < quickTalk.count) quickTalk.setProperty(root.quickDraft, "text", text)
            else quickTalk.append({ role: "assistant", text: text, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
            root.quickDraft = -1; root.quickLooking = false
            if (root.active) Sfx.play("receive")
        }
        function onChanged() { if (!Quick.busy) { root.quickDraft = -1; root.quickLooking = false } }
    }
    property int quickDraft: -1        // the bubble an answer is growing in
    property bool quickLooking: false  // it has gone to the web
    readonly property string quickError: Quick.error === "" ? "" : Quick.error === "login" ? Tr.t("The claude command is not signed in. Open a terminal, run claude, then /login.")
        : Quick.error === "noclaude" ? Tr.t("Claude Code was not found") : Tr.d(Quick.error)
    readonly property var all: { // [{id, name, cwd}], as Hub lists them
        const out = []
        for (let i = 0; i < roster.count; ++i) { const it = roster.itemAt(i); if (it) out.push({ id: it.sessionId, name: it.sessionName, cwd: it.sessionCwd }) }
        return out
    }
    Repeater {
        id: roster
        model: Hub.sessions
        Item { required property string id; required property string name; required property string cwd
               readonly property string sessionId: id; readonly property string sessionName: name; readonly property string sessionCwd: cwd }
    }
    readonly property var cur: {
        const hit = all.find(s => s.id === picked)
        if (hit) return hit
        return Hub.session.id ? { id: Hub.session.id, name: Hub.session.name || "", cwd: Hub.session.cwd || "" } : { id: "", name: "", cwd: "" }
    }
    // (by the folder the session was first seen in, or one above it that has a talk
    // already: a session wanders inside its project, and its talk must stay one)
    property var homes: ({})
    function homeFor(id, cwd) {
        if (cwd === "") return ""
        if (homes[id] === undefined) homes[id] = Relay.home(cwd)
        return homes[id]
    }
    readonly property string key: cur.cwd !== "" ? homeFor(cur.id, cur.cwd) : cur.name !== "" ? cur.name : sid
    // (A session Kisel has not heard from yet is known only by its id: what was said
    // meanwhile is filed under that, and moves to the project's talk once it is known.)
    property string lastKey: ""
    property bool lastBare: false
    onKeyChanged: {
        if (lastBare && lastKey !== "" && lastKey !== key && cur.cwd !== "") {
            for (const m of Relay.history(lastKey)) Relay.remember(key, m.role, m.text)
            Relay.forget(lastKey)
        }
        lastKey = key; lastBare = cur.cwd === "" && cur.name === ""
        reload()
    }
    function reload() {
        live = false; liveSoon.restart()
        sent.clear()
        for (const m of Relay.history(key)) sent.append({ role: m.role, text: m.text, file: "", time: m.time })
    }
    // (whose talk a reply belongs to, when it is not the one on show: by the session it came from)
    function keyOf(session) {
        for (const s of all) if (Relay.best(s.id) === session) return s.cwd !== "" ? homeFor(s.id, s.cwd) : s.name
        return session
    }
    // (the session as its mod names it, which is not always how the hooks do: see Relay.best)
    readonly property string sid: { Relay.live; return Relay.best(cur.id) }
    readonly property bool relayOn: sid !== "" && Relay.live.includes(sid)
    readonly property bool relayWaiting: Relay.waiting.includes(sid)
    onSidChanged: if (sid !== "") Relay.watch(sid)
    Component.onCompleted: {
        if (sid !== "") Relay.watch(sid)
        reload()
        for (const m of Relay.history(quickKey)) quickTalk.append({ role: m.role, text: m.text, file: "", time: m.time })
    }
    ListModel { id: sent } // the talk with the session, as seen from here: {role, text, file, time}
    property string relayNote: ""
    Timer { id: relayNoteOff; interval: 4000; onTriggered: root.relayNote = "" }
    Connections {
        target: Relay
        // (what Claude says in the session comes back here, so the chat has both sides)
        function onReply(id, text) {
            if (id !== root.sid) { Relay.remember(root.keyOf(id), "assistant", text); return } // (kept for when its project is looked at)
            Relay.remember(root.key, "assistant", text)
            sent.append({ role: "assistant", text: text, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
            if (root.active) Sfx.play("receive")
        }
    }

    // What you write to a session in Claude Code itself is yours in this talk too. (What
    // was sent from here comes round the same way, as the prompt it became: that one is
    // here already, and is known by its words for a minute.)
    property var justSent: []
    Connections {
        target: Hub
        function onPrompted(session, cwd, name, text) {
            const body = text.trim()
            if (body === "") return
            const now = Date.now()
            root.justSent = root.justSent.filter(s => now - s.at < 60000)
            const i = root.justSent.findIndex(s => s.text === body)
            if (i >= 0) { const left = root.justSent.slice(); left.splice(i, 1); root.justSent = left; return }
            const k = cwd !== "" ? root.homeFor(session, cwd) : name !== "" ? name : session
            Relay.remember(k, "user", body)
            if (k === root.key) sent.append({ role: "user", text: body, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
        }
    }

    function send() {
        if (input.text.trim() === "")
            return
        if (quick) {
            if (Quick.busy) return
            const q = input.text.trim()
            quickDraft = -1; quickLooking = false
            Quick.ask(quickTurns(), q, Prefs.quickModel, Prefs.quickEffort)
            Sfx.play("send")
            Relay.remember(quickKey, "user", q)
            quickTalk.append({ role: "user", text: q, file: "", time: Qt.formatTime(new Date(), "hh:mm") })
            input.text = ""
            return
        }
        if (relayOn) {
            const text = input.text.trim()
            if (!Relay.send(sid, text)) { relayNote = Tr.t("Couldn't send it"); relayNoteOff.restart(); Sfx.play("deny"); return }
            Sfx.play("send")
            justSent = justSent.concat([{ text: text, at: Date.now() }])
            Relay.remember(key, "user", text)
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
    // An answer as blocks, each drawn in its own way (see the bubble): a heading, a
    // paragraph, a list item, a quote (a note set apart), a fence of code, a table, a rule.
    // The same rule as below holds: the text is escaped first and only our own tags are
    // added; code is shown as plain text; nothing is fetched and nothing can be clicked.
    function escHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function inlineMd(t) { // (on text already escaped)
        const kept = []
        t = t.replace(/`([^`\n]+)`/g, (m, c) => { kept.push("<font face=\"" + Theme.mono + "\" color=\"" + root.accText + "\">" + c + "</font>"); return "\u0001" + (kept.length - 1) + "\u0001" })
        t = t.replace(/!\[([^\]\n]*)\]\([^)\n]*\)/g, "$1")
        t = t.replace(/\[([^\]\n]+)\]\([^)\n]*\)/g, "$1")
        t = t.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>").replace(/__([^_\n]+)__/g, "<b>$1</b>")
        t = t.replace(/(^|[\s(])\*([^*\s][^*\n]*)\*/g, "$1<i>$2</i>").replace(/(^|[\s(])_([^_\s][^_\n]*)_(?=$|[\s).,!?:;])/g, "$1<i>$2</i>")
        t = t.replace(/~~([^~\n]+)~~/g, "<s>$1</s>")
        return t.replace(/\u0001(\d+)\u0001/g, (m, n) => kept[Number(n)])
    }
    function blocks(text) {
        const out = []
        const cells = (line) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => inlineMd(escHtml(c.trim())))
        const parts = text.split(/```/)
        for (let k = 0; k < parts.length; k++) {
            if (k % 2 === 1) { // inside a fence: as it is; its first line may name the language
                const m = /^([a-zA-Z0-9_+#-]*)\n/.exec(parts[k])
                const body = parts[k].replace(/^[a-zA-Z0-9_+#-]*\n/, "").replace(/\n+$/, "")
                if (body !== "") out.push({ k: "code", text: body, lang: m ? m[1] : "" })
                continue
            }
            const lines = parts[k].split("\n")
            let para = [], table = null
            const flush = () => {
                if (para.length) { out.push({ k: "p", html: para.map(l => inlineMd(escHtml(l))).join("<br>") }); para = [] }
                if (table) { if (table.rows.length || table.head.length) out.push(table); table = null }
            }
            for (const line of lines) {
                const t = line.trim()
                let m
                if (/^\|.*\|$/.test(t)) {
                    if (para.length) flush()
                    if (/^\|[\s:|-]+\|$/.test(t)) continue // (the row of dashes under the heading)
                    if (!table) table = { k: "table", head: cells(t), rows: [] }
                    else if (table.rows.length < 24) table.rows.push(cells(t))
                    continue
                }
                if (table) flush()
                if (t === "") flush()
                else if ((m = /^(#{1,6})\s+(.*)$/.exec(t))) { flush(); out.push({ k: "h", html: inlineMd(escHtml(m[2])), level: m[1].length }) }
                else if (/^(-{3,}|\*{3,}|_{3,})$/.test(t)) { flush(); out.push({ k: "rule" }) }
                else if ((m = /^(\s*)[-*+]\s+(.*)$/.exec(line))) { flush(); out.push({ k: "li", html: inlineMd(escHtml(m[2])), num: "", indent: Math.min(3, Math.floor(m[1].length / 2)) }) }
                else if ((m = /^(\s*)(\d+)[.)]\s+(.*)$/.exec(line))) { flush(); out.push({ k: "li", html: inlineMd(escHtml(m[3])), num: m[2], indent: Math.min(3, Math.floor(m[1].length / 2)) }) }
                else if ((m = /^>\s?(.*)$/.exec(t))) {
                    if (para.length || table) flush()
                    const last = out[out.length - 1]
                    if (last && last.k === "quote" && last.open) last.html += "<br>" + inlineMd(escHtml(m[1]))
                    else out.push({ k: "quote", html: inlineMd(escHtml(m[1])), open: true })
                    continue
                }
                else para.push(line)
                const tail = out[out.length - 1]
                if (tail && tail.k === "quote") tail.open = false
            }
            flush()
        }
        return out.slice(0, 80)
    }

    function styled(text, mine) {
        const mono = Theme.mono
        const codeInk = Theme.inkMuted
        const faint = Theme.inkFaint
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

    // whose talk this is: the projects with a session open, the one in hand lit; a click
    // on another takes the chat to it
    Flickable {
        id: projects
        width: parent.width - (modelRow.visible ? modelRow.width + 8 : 0)
        height: 24
        contentWidth: projectRow.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Row {
            id: projectRow
            spacing: 6
            Rectangle { // the quick talk
                id: quickTag
                width: quickTagText.implicitWidth + 18; height: 22; radius: 11
                color: root.quick ? root.tinted(0.3) : quickTagHover.hovered ? Theme.surface3 : Theme.veil
                border.width: root.quick ? 1.5 : 0; border.color: root.acc
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                activeFocusOnTab: true
                Accessible.role: Accessible.PageTab
                Accessible.name: Tr.t("Quick question")
                Accessible.selected: root.quick
                Text {
                    id: quickTagText
                    anchors.centerIn: parent
                    text: Tr.t("Quick question")
                    color: root.quick ? Theme.ink : Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
                }
                HoverHandler { id: quickTagHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Sfx.play("click"); root.picked = "quick" } }
                Keys.onReturnPressed: root.picked = "quick"
                Keys.onSpacePressed: root.picked = "quick"
            }
            Repeater {
                model: root.all
                Rectangle {
                    id: tag
                    required property var modelData
                    readonly property bool on: !root.quick && modelData.id === root.cur.id
                    readonly property bool live: { Relay.live; return Relay.live.includes(Relay.best(modelData.id)) }
                    width: tagRow.width + 18; height: 22; radius: 11
                    color: on ? root.tinted(0.3) : tagHover.hovered ? Theme.surface3 : Theme.veil
                    border.width: on ? 1.5 : 0; border.color: root.acc
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                    activeFocusOnTab: true
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.name
                    Accessible.selected: on
                    Row {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: tag.live ? root.acc : Theme.inkFaint }
                        Text {
                            text: tag.modelData.name !== "" ? tag.modelData.name : Tr.t("Session")
                            color: tag.on ? Theme.ink : Theme.inkMuted
                            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
                        }
                    }
                    HoverHandler { id: tagHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { Sfx.play("click"); root.picked = tag.modelData.id } }
                    Keys.onReturnPressed: root.picked = modelData.id
                    Keys.onSpacePressed: root.picked = modelData.id
                }
            }
        }
    }

    // the quick talk's model, and a key that starts it over
    Row {
        id: modelRow
        visible: root.quick
        anchors.right: parent.right
        height: 24
        spacing: 4
        Repeater {
            model: Quick.models
            Rectangle {
                id: pick
                required property string modelData
                readonly property bool on: Prefs.quickModel === modelData
                anchors.verticalCenter: parent.verticalCenter
                width: pickText.implicitWidth + 12; height: 20; radius: 10
                color: on ? root.acc : pickHover.hovered ? Theme.surface3 : Theme.veil
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.modelName(modelData)
                Accessible.checked: on
                Text { id: pickText; anchors.centerIn: parent; text: root.modelName(pick.modelData); color: pick.on ? root.accInk : Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                HoverHandler { id: pickHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Sfx.play("click"); Prefs.quickModel = pick.modelData } }
                Keys.onReturnPressed: Prefs.quickModel = modelData
                Keys.onSpacePressed: Prefs.quickModel = modelData
            }
        }
        Rectangle {
            visible: quickTalk.count > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: clearHover.hovered ? Theme.surface3 : Theme.veil
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Tr.t("Start over")
            Icon { anchors.centerIn: parent; name: "cross"; size: 12; color: Theme.inkMuted }
            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { Sfx.play("click"); Quick.cancel(); quickTalk.clear(); Relay.forget(root.quickKey) } }
            Keys.onReturnPressed: { Quick.cancel(); quickTalk.clear(); Relay.forget(root.quickKey) }
        }
    }

    // ...and how hard it should think, under the models
    Row {
        id: effortRow
        visible: root.quick
        anchors.right: parent.right
        y: 26
        height: 22
        spacing: 4
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Tr.t("Effort")
            color: Theme.inkFaint
            font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
        }
        Repeater {
            model: Quick.efforts
            Rectangle {
                id: level
                required property string modelData
                readonly property bool on: Prefs.quickEffort === modelData
                anchors.verticalCenter: parent.verticalCenter
                width: levelText.implicitWidth + 12; height: 20; radius: 10
                color: on ? root.acc : levelHover.hovered ? Theme.surface3 : Theme.veil
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.effortName(modelData)
                Accessible.checked: on
                Text { id: levelText; anchors.centerIn: parent; text: root.effortName(level.modelData); color: level.on ? root.accInk : Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                HoverHandler { id: levelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Sfx.play("click"); Prefs.quickEffort = level.modelData } }
                Keys.onReturnPressed: Prefs.quickEffort = modelData
                Keys.onSpacePressed: Prefs.quickEffort = modelData
            }
        }
    }

    // messages
    ListView {
        id: list
        y: projects.height + Theme.space2 + (root.quick ? 24 : 0)
        width: parent.width
        height: composer.y - Theme.space2 - y
        model: root.quick ? quickTalk : root.relayOn || sent.count > 0 ? sent : Chat.messages
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
            property bool fresh: false // (a bubble made while the talk is live, at its end: its blocks make an entrance)
            property int shown: 0      // how many of its blocks have made theirs (it may be growing as it is written)
            Component.onCompleted: fresh = root.live && index >= list.count - 1
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
                // Claude's is the surface with a breath of her colour and her edge; yours is dark
                // with more of that colour in it and a bright edge of it, the words light in
                // both. (Yours was filled with her colour and written in dark ink: hard to read.)
                color: msg.mine ? root.mineFill : root.wash
                border.width: msg.mine ? 1.5 : 1
                border.color: msg.mine ? root.acc : root.tinted(0.3)
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
                            Icon { name: "clip"; size: 14; color: Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                            Text { id: chipText; text: msg.file; color: Theme.ink
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
                    Item {
                        id: body
                        visible: msg.text !== ""
                        width: parent.width
                        readonly property real maxW: list.width * 0.86 - 24
                        implicitWidth: msg.mine ? plain.implicitWidth : rich.natural
                        implicitHeight: msg.mine ? plain.implicitHeight : rich.height
                        height: implicitHeight
                        Text { // yours: as written
                            id: plain
                            visible: msg.mine
                            width: parent.width
                            text: msg.mine && msg.text !== "" ? root.styled(msg.text, true) : ""
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            color: Theme.ink
                            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                            lineHeight: 18; lineHeightMode: Text.FixedHeight
                        }
                        // Claude's: block by block, each in a dress of its own, and a new answer's
                        // blocks arriving one after another (45 ms apart, rising 6 px as they fade in).
                        // (Model output is untrusted: `blocks` escapes it first; code is plain text.)
                        Column {
                            id: rich
                            visible: !msg.mine
                            width: parent.width
                            spacing: 5
                            readonly property var parts: msg.mine || msg.text === "" ? [] : root.blocks(msg.text)
                            onPartsChanged: Qt.callLater(() => { msg.shown = rich.parts.length })
                            readonly property real natural: {
                                let w = 0
                                for (let i = 0; i < reps.count; ++i) { const it = reps.itemAt(i); if (it) w = Math.max(w, it.natural) }
                                return w
                            }
                            Repeater {
                                id: reps
                                model: rich.parts
                                Item {
                                    id: blk
                                    required property var modelData
                                    required property int index
                                    readonly property string k: modelData.k
                                    readonly property bool texty: k === "p" || k === "h" || k === "li" || k === "quote"
                                    readonly property real lead: k === "li" ? 15 + modelData.indent * 12 : k === "h" ? 10 : k === "quote" ? 12 : 0
                                    readonly property real natural: texty ? Math.min(body.maxW, line.implicitWidth + lead + (k === "quote" ? 10 : 0)) : body.maxW
                                    width: rich.width
                                    height: k === "table" ? grid.height : k === "code" ? codeBox.height : k === "rule" ? 9
                                          : line.implicitHeight + (k === "quote" ? 10 : 0) + (k === "h" && index > 0 ? 4 : 0)
                                    // the entrance
                                    property bool lively: false
                                    property int turn: 0
                                    Component.onCompleted: { turn = Math.max(0, index - msg.shown); lively = msg.fresh && !Theme.reduced && index >= msg.shown }
                                    opacity: lively ? 0 : 1
                                    transform: Translate { id: rise; y: blk.lively ? 6 : 0 }
                                    SequentialAnimation {
                                        running: blk.lively
                                        PauseAnimation { duration: 30 + blk.turn * 45 }
                                        ParallelAnimation {
                                            NumberAnimation { target: blk; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: rise; property: "y"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: mark; property: "scale"; from: 0; to: 1; duration: 260; easing.type: Easing.OutBack }
                                        }
                                    }

                                    // a quote: a note set apart, on a tint of her colour
                                    Rectangle {
                                        visible: blk.k === "quote"
                                        width: Math.min(blk.width, blk.natural); height: blk.height; radius: 7
                                        color: root.tinted(0.14)
                                        Rectangle { x: 4; y: 5; width: 3; height: parent.height - 10; radius: 1.5; color: root.acc }
                                    }
                                    // the mark before it: a heading's bar, a list's dot or its number
                                    Item {
                                        id: mark
                                        visible: blk.k === "h" || blk.k === "li"
                                        x: blk.k === "li" ? blk.modelData.indent * 12 : 0
                                        y: blk.k === "h" && blk.index > 0 ? 4 : 0
                                        width: 14; height: 18
                                        Rectangle { visible: blk.k === "h"; x: 0; y: 2; width: 3.5; height: 14; radius: 1.75; color: root.acc }
                                        Rectangle { visible: blk.k === "li" && blk.modelData.num === ""; x: 3; y: 6.5; width: 5; height: 5; radius: 2.5; color: root.acc }
                                        Text { visible: blk.k === "li" && blk.modelData.num !== ""; width: 12; horizontalAlignment: Text.AlignRight; y: 0
                                            text: blk.k === "li" ? blk.modelData.num : ""; color: root.accText
                                            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold; lineHeight: 18; lineHeightMode: Text.FixedHeight }
                                    }
                                    Text {
                                        id: line
                                        visible: blk.texty
                                        x: blk.lead
                                        y: (blk.k === "quote" ? 5 : 0) + (blk.k === "h" && blk.index > 0 ? 4 : 0)
                                        width: blk.width - blk.lead - (blk.k === "quote" ? 8 : 0)
                                        text: blk.texty ? blk.modelData.html : ""
                                        textFormat: Text.StyledText
                                        wrapMode: Text.Wrap
                                        color: blk.k === "quote" ? Theme.inkMuted : Theme.ink
                                        font.family: blk.k === "h" ? Theme.display : Theme.sans
                                        font.pixelSize: blk.k === "h" ? (blk.modelData.level <= 2 ? 15 : 14) : 13
                                        font.weight: blk.k === "h" ? Font.Bold : Font.Medium
                                        lineHeight: 18; lineHeightMode: Text.FixedHeight
                                    }
                                    // code: a dark panel, its language named in the corner
                                    Rectangle {
                                        id: codeBox
                                        visible: blk.k === "code"
                                        width: blk.width; height: visible ? codeText.implicitHeight + 16 : 0
                                        radius: 8
                                        color: "#15121a"
                                        border.width: 1; border.color: root.tinted(0.35)
                                        Text {
                                            visible: blk.k === "code" && blk.modelData.lang !== ""
                                            anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 4 }
                                            text: blk.k === "code" ? blk.modelData.lang : ""
                                            color: root.acc; opacity: 0.8
                                            font.family: Theme.mono; font.pixelSize: 9
                                        }
                                        Text {
                                            id: codeText
                                            x: 10; y: 8
                                            width: parent.width - 20
                                            text: blk.k === "code" ? blk.modelData.text : ""
                                            textFormat: Text.PlainText
                                            wrapMode: Text.WrapAnywhere
                                            color: "#E8E2EE"
                                            font.family: Theme.mono; font.pixelSize: 11
                                        }
                                    }
                                    // a table: the heading on her colour, the rows banded
                                    Column {
                                        id: grid
                                        visible: blk.k === "table"
                                        width: blk.width
                                        readonly property int cols: blk.k === "table" ? Math.max(1, blk.modelData.head.length) : 1
                                        readonly property var all: blk.k === "table" ? [blk.modelData.head].concat(blk.modelData.rows) : []
                                        Repeater {
                                            model: grid.all
                                            Rectangle {
                                                id: tr
                                                required property var modelData
                                                required property int index
                                                width: grid.width; height: cellRow.height + 8
                                                radius: index === 0 || index === grid.all.length - 1 ? 6 : 0
                                                color: index === 0 ? root.tinted(0.3) : index % 2 === 0 ? Theme.veil : Theme.veilSoft
                                                Row {
                                                    id: cellRow
                                                    x: 8; y: 4
                                                    Repeater {
                                                        model: grid.cols
                                                        Text {
                                                            required property int index
                                                            width: (grid.width - 16) / grid.cols
                                                            text: tr.modelData[index] !== undefined ? tr.modelData[index] : ""
                                                            textFormat: Text.StyledText
                                                            wrapMode: Text.Wrap
                                                            rightPadding: 6
                                                            color: Theme.ink
                                                            font.family: Theme.sans; font.pixelSize: 12; font.weight: tr.index === 0 ? Font.ExtraBold : Font.Medium
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Rectangle { visible: blk.k === "rule"; y: 4; width: blk.width; height: 1; color: root.tinted(0.4) }
                                }
                            }
                        }
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
                text: root.quick ? Tr.t("A quick question") : root.relayOn ? Tr.t("Write to Claude Code") : Tr.t("Ask Claude anything")
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.quick ? Tr.t("Outside your sessions and projects.") : root.relayOn ? Tr.t("It goes to your session as your own prompt") : root.pal.name + Tr.t(" is listening")
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

        Rectangle { // error line on diff-del-bg (as tall as what it has to say: a hint may run to two lines)
            visible: root.quick ? root.quickError !== "" : Chat.error !== "" && !root.relayOn
            width: parent.width; height: Math.max(26, errText.implicitHeight + 10); radius: Theme.radiusSm
            color: Theme.diffDelBg
            Icon { x: 8; y: 6; name: "cross"; size: 14; color: Theme.danger }
            Text { id: errText; x: 28; y: 5; width: parent.width - 36; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                text: root.quick ? root.quickError : Tr.d(Chat.error); color: Theme.danger
                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
        Row {
            // (with a Claude Code session the model is named in the left column, and how a
            // message fares is said in the field itself: nothing is kept here to crowd the talk)
            visible: !root.quick && (!root.relayOn || Chat.attachedName !== "")
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
                    placeholderText: root.quick ? (Quick.phase === "search" ? Tr.t("Looking it up...") : Quick.phase !== "" ? Tr.t("Claude is answering...") : Tr.t("Ask a quick question"))
                        : !root.relayOn ? Tr.t("Message Claude")
                        : root.relayNote !== "" ? root.relayNote
                        : root.relayWaiting ? Tr.t("Sent. Claude takes it when it is free.") : Tr.t("Write to Claude Code")
                    placeholderTextColor: Theme.inkFaint
                    wrapMode: TextEdit.Wrap
                    color: Theme.ink
                    selectionColor: root.acc
                    selectedTextColor: root.accInk
                    font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                    background: null
                    // (one line stands in the middle of the field: the style's own padding set it low)
                    topPadding: Math.max(4, Math.round((Math.max(32, contentHeight + 14) - contentHeight) / 2)); bottomPadding: 4
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
                readonly property bool busy: root.quick ? Quick.busy : Chat.busy && !root.relayOn
                color: busy ? Theme.surface3 : (sendTap.pressed ? root.accDeep : root.acc)
                border.width: busy ? 0 : 2
                border.color: "#FFFFFF"
                scale: sendTap.pressed ? 0.9 : sendHover.hovered ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Accessible.role: Accessible.Button
                Accessible.name: busy ? Tr.t("Stop") : Tr.t("Send")
                Icon { anchors.centerIn: parent; size: 18; name: sendBtn.busy ? "cross" : "send"; color: sendBtn.busy ? Theme.ink : root.accInk }
                TapHandler { id: sendTap; onTapped: sendBtn.busy ? (root.quick ? Quick.cancel() : Chat.cancel()) : root.send() }
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
