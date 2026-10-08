// Home. Miku's is Claude Code's, in the sticker style of the others and in her teal: a
// round light with how many sessions there are and what they are doing, two keys (the
// chat and GitHub), the newest session with its last line, and a line from Miku herself.
// Beside her line is a key: Connect while Claude Code is not connected, Open when there
// is a session to look at. Zundamon's, Teto's and Luka's Homes dissolve in over it.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    signal go(string view)

    readonly property var s: Hub.session
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

    readonly property color teal: "#39C5BB"
    readonly property color deep: "#22968E"
    readonly property string st: hasSession ? (s.state || "idle") : ""
    readonly property bool busy: st === "work" || st === "think"
    readonly property color stTint: busy ? root.teal : st === "alert" ? "#FFE08A" : st === "done" ? "#B9DC6B"
        : st === "failed" ? "#E0405A" : Qt.rgba(root.teal.r, root.teal.g, root.teal.b, 0.45)
    readonly property string stWord: !Hooks.installed ? Tr.t("Not connected") : !hasSession ? Tr.t("Listening")
        : st === "work" ? Tr.t("Working") : st === "think" ? Tr.t("Thinking") : st === "alert" ? Tr.t("Needs you")
        : st === "done" ? Tr.t("Done") : st === "failed" ? Tr.t("Failed") : Tr.t("Idle")
    readonly property string line: !Hooks.installed ? Tr.t("Claude Code is not connected yet. Shall we fix that?")
        : !Hub.serverUp ? Tr.t("I cannot listen for hooks right now. Sorry!")
        : !hasSession ? Tr.t("Ready and listening. Start a session and I will watch it.")
        : st === "think" ? Tr.t("Thinking it over. Give it a moment.")
        : st === "work" ? Tr.t("Working on it. I will tell you when it is done.")
        : st === "alert" ? Tr.t("Claude needs you. Have a look?")
        : st === "done" ? Tr.t("All done! Come and see.")
        : st === "failed" ? Tr.t("That one went wrong. Want to see why?")
        : Tr.t("Nothing is running. I am right here.")

    // ---- Miku's Home: Claude Code ----
    Item {
        id: claude
        anchors.fill: parent
        visible: root.claudeU > 0
        opacity: root.claudeU

        Row {
            id: left
            x: 8; y: 12
            spacing: 12

            // the light: how many sessions, and a ring that turns while one is busy.
            // With the account's limits known (a session reports them through the
            // kisel-prompts mod: see PromptRelay) it is three rings, one inside another,
            // each a limit in a colour of its own: the five hours outermost in pink, the
            // week in lemon, the session's context innermost in Miku's teal; any of them
            // red from 90 percent. They pour in one after another when the card shows.
            // One ring at a time has the floor: it swells, the others dim, a bead sits on
            // its tip, its percent stands in the middle, its name underneath, and under the
            // name when it starts over (the context: how many tokens of how many). The floor
            // passes on now and then, or goes to the ring under the pointer. While
            // Claude is busy a glint runs up each ring in turn, and the figure breathes.
            Item {
                id: light
                width: 86; height: 122
                opacity: Motion.rise(root.age, 0)
                transform: Translate { y: Motion.lift(root.age, 0) }
                readonly property string sid: root.s.id || ""
                property var lim: [] // [{kind, used}], the last known: they are the account's, and outlive a session
                function reread() { const l = sid !== "" ? Relay.limits(sid) : []; if (l.length > 0) lim = l }
                onSidChanged: reread()
                Component.onCompleted: reread()
                Connections { target: Relay; function onChanged() { light.reread() } }
                onLimChanged: ring.requestPaint()
                readonly property var shown: lim.slice(0, 3)
                readonly property bool rings: shown.length > 0
                readonly property var hues: ({ five_hour: "#FF9EBB", seven_day: "#FFE08A", context: "#39C5BB", spend_limit: "#B9DC6B" })
                function hue(r) { return r.used >= 90 ? "#E0405A" : (hues[r.kind] || "#B9DC6B") }
                function label(kind) { return kind === "five_hour" ? Tr.t("5 hours") : kind === "seven_day" ? Tr.t("Week") : kind === "context" ? Tr.t("Context") : kind === "spend_limit" ? Tr.t("Spend") : kind }

                // when it starts over: the hour for one that does today, the day for a later one
                function resets(r) {
                    if (!r.resetsAt) return ""
                    const d = new Date(r.resetsAt)
                    if (isNaN(d.getTime())) return ""
                    const soon = d.getTime() - Date.now() < 20 * 3600 * 1000
                    return Tr.t("until ") + (soon ? Qt.formatTime(d, "hh:mm") : Qt.formatDate(d, "d MMM"))
                }
                function brief(v) { return v >= 1e6 ? (v / 1e6).toFixed(v % 1e6 === 0 ? 0 : 1) + "M" : v >= 1000 ? Math.round(v / 1000) + "k" : Math.round(v) }
                function detail(r) { return r.kind === "context" ? (r.window > 0 ? brief(r.tokens) + " / " + brief(r.window) : "") : resets(r) }

                property int pick: 0  // the ring that has the floor
                property int was: 0   // the one that had it
                property real swell: 1 // 0..1: the floor passing from `was` to `pick`
                property real fill: 1  // 0..1: the rings pouring in
                readonly property var cur: rings ? shown[Math.min(pick, shown.length - 1)] : null
                function give(n) {
                    n = Math.max(0, Math.min(shown.length - 1, n))
                    if (n === pick)
                        return
                    was = pick; pick = n
                    if (Theme.reduced) { swell = 1; ring.requestPaint() } else swellAnim.restart()
                }
                NumberAnimation { id: swellAnim; target: light; property: "swell"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { id: fillAnim; target: light; property: "fill"; from: 0; to: 1; duration: 1100; easing.type: Easing.Linear }
                onSwellChanged: ring.requestPaint()
                onFillChanged: ring.requestPaint()
                Connections {
                    target: root
                    function onActiveChanged() { if (root.active && light.rings && !Theme.reduced) fillAnim.restart() }
                }
                Timer {
                    interval: 8000; repeat: true
                    running: root.active && claude.visible && light.shown.length > 1 && !ringHover.hovered
                    onTriggered: light.give((light.pick + 1) % light.shown.length)
                }
                Canvas {
                    id: ring
                    width: 86; height: 86
                    property real turn: 0
                    NumberAnimation on turn {
                        running: root.active && root.busy && claude.visible && !Theme.reduced
                        from: 0; to: 1; duration: light.rings ? 2200 : 1400; loops: Animation.Infinite
                    }
                    onTurnChanged: requestPaint()
                    property color tint: root.stTint
                    Behavior on tint { ColorAnimation { duration: 300 } }
                    onTintChanged: requestPaint()
                    property bool busy: root.busy
                    onBusyChanged: requestPaint()
                    function radius(n) { return 38 - n * 10 }
                    onPaint: {
                        const g = getContext("2d"), c = 43
                        g.reset()
                        g.lineCap = "round"
                        const lim = light.shown
                        if (lim.length > 0) {
                            lim.forEach((r, n) => {
                                const rad = radius(n)
                                // how much of the floor this ring holds
                                const w = n === light.pick ? light.swell : n === light.was ? 1 - light.swell : 0
                                g.globalAlpha = 1
                                g.lineWidth = 8
                                g.strokeStyle = "#2b2430"; g.beginPath(); g.arc(c, c, rad, 0, 2 * Math.PI, false); g.stroke()
                                // (each ring starts a little after the one outside it, and eases out)
                                const t = Math.max(0, Math.min(1, light.fill * 1.5 - n * 0.25)), f = 1 - Math.pow(1 - t, 3)
                                const a = Math.max(0, Math.min(1, r.used / 100)) * f
                                if (a <= 0.005)
                                    return
                                const end = -Math.PI / 2 + 2 * Math.PI * a
                                g.globalAlpha = 0.55 + 0.45 * w
                                g.lineWidth = 8 + 1.5 * w
                                g.strokeStyle = light.hue(r); g.beginPath(); g.arc(c, c, rad, -Math.PI / 2, end, false); g.stroke()
                                if (busy && a > 0.06) { // Claude at work: a glint runs up each ring, one after another
                                    const ph = (turn + n * 0.3) % 1, span = end + Math.PI / 2
                                    const head = -Math.PI / 2 + span * ph, len = Math.min(0.9, span * 0.5)
                                    g.strokeStyle = "#FFFFFF"
                                    g.lineWidth = 4
                                    for (let k = 0; k < 4; ++k) { // (brightest at its head, thinning out behind)
                                        const from = Math.max(-Math.PI / 2, head - len * (1 - k / 4))
                                        g.globalAlpha = 0.2 * Math.sin(Math.PI * ph)
                                        g.beginPath(); g.arc(c, c, rad, from, head, false); g.stroke()
                                    }
                                }
                                if (w > 0.01) { // the bead on its tip
                                    g.globalAlpha = w
                                    g.fillStyle = "#FFFFFF"
                                    g.beginPath(); g.arc(c + rad * Math.cos(end), c + rad * Math.sin(end), 2.5, 0, 2 * Math.PI, false); g.fill()
                                }
                            })
                            g.globalAlpha = 1
                            return
                        }
                        g.strokeStyle = "#FFFFFF"; g.lineWidth = 12
                        g.beginPath(); g.arc(c, c, 35, 0, 2 * Math.PI, false); g.stroke()
                        g.strokeStyle = "#2b2430"; g.lineWidth = 8
                        g.beginPath(); g.arc(c, c, 35, 0, 2 * Math.PI, false); g.stroke()
                        g.strokeStyle = tint; g.lineWidth = 8
                        const from = -Math.PI / 2 + 2 * Math.PI * turn
                        g.beginPath(); g.arc(c, c, 35, from, from + (busy ? 0.7 * Math.PI : 2 * Math.PI), false); g.stroke()
                    }
                    HoverHandler {
                        id: ringHover
                        enabled: light.rings
                        onPointChanged: {
                            if (!hovered)
                                return
                            const d = Math.hypot(point.position.x - 43, point.position.y - 43)
                            light.give(d > 33 ? 0 : d > 23 ? 1 : 2)
                        }
                    }
                }
                Text { // no limits known: how many sessions
                    visible: !light.rings
                    anchors.centerIn: ring
                    text: !Hooks.installed ? "off" : counter.count
                    color: Theme.ink
                    font.family: Theme.display; font.pixelSize: 19; font.weight: Font.Bold
                }
                Text { // the figure of the ring that has the floor
                    visible: light.rings
                    anchors.centerIn: ring
                    width: 25
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                    text: light.cur ? Math.round(light.cur.used * Math.min(1, light.fill * 1.5)) + "%" : ""
                    color: light.cur ? light.hue(light.cur) : Theme.ink
                    Behavior on color { ColorAnimation { duration: 240 } }
                    scale: (0.85 + 0.15 * light.swell) * (root.busy && !Theme.reduced ? 1 + 0.06 * Math.sin(2 * Math.PI * ring.turn) : 1)
                    font.family: Theme.display; font.pixelSize: 13; font.weight: Font.Bold
                }
                Text {
                    y: 90
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: light.cur ? light.label(light.cur.kind) : counter.count === 1 ? Tr.t("Session") : Tr.t("Sessions")
                    color: light.cur ? light.hue(light.cur) : Theme.ink
                    Behavior on color { ColorAnimation { duration: 240 } }
                    opacity: light.rings ? 0.35 + 0.65 * light.swell : 1
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
                }
                Text {
                    y: 106
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: !light.rings ? root.stWord : light.detail(light.cur) !== "" ? light.detail(light.cur)
                        : counter.count + " " + (counter.count === 1 ? Tr.t("Session") : Tr.t("Sessions")).toLowerCase()
                    opacity: light.rings ? 0.35 + 0.65 * light.swell : 1
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.DemiBold
                }
            }

            // the two keys
            Column {
                y: 2
                spacing: 8
                Key1 {
                    over: "Claude"; label: Tr.t("Chat"); icon: "chat"
                    opacity: Motion.rise(root.age, 1)
                    transform: Translate { y: Motion.lift(root.age, 1) }
                    onClicked: root.go("chat")
                }
                Key1 {
                    over: Tr.t("Repos"); label: "GitHub"; icon: "github"
                    opacity: Motion.rise(root.age, 2)
                    transform: Translate { y: Motion.lift(root.age, 2) }
                    onClicked: root.go("github")
                }
            }
        }

        Item {
            id: side
            x: left.x + left.width + 16
            y: 12
            width: parent.width - x - 6
            height: parent.height - 24

            Row {
                spacing: 6
                opacity: Motion.rise(root.age, 1)
                transform: Translate { y: Motion.lift(root.age, 1) }
                Spark { anchors.verticalCenter: parent.verticalCenter; size: 11; tint: root.teal
                    RotationAnimation on rotation { running: root.active && claude.visible && !Theme.reduced; from: 0; to: 90; duration: 3000; loops: Animation.Infinite } }
                Text {
                    width: Math.min(implicitWidth, side.width - 17)
                    elide: Text.ElideRight
                    text: root.hasSession ? root.s.name + (counter.count > 1 ? "  +" + (counter.count - 1) : "") : "Claude Code"
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                }
            }

            // the newest session's last line (or the dots: ready and listening)
            Rectangle {
                id: strip
                y: 20
                width: side.width
                height: 38
                radius: 12
                color: stripTap.pressed || stripHover.hovered && root.hasSession ? "#3a3142" : "#2b2430"
                Behavior on color { ColorAnimation { duration: Theme.tHover } }
                opacity: Motion.rise(root.age, 2)
                transform: Translate { y: Motion.lift(root.age, 2) }
                Item {
                    x: 10
                    width: 24; height: parent.height
                    Item {
                        visible: !root.hasSession
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54; height: 22
                        scale: 0.42; transformOrigin: Item.Left
                        // hooks installed but nothing heard yet: the first connection takes the jelly trio
                        JellyTrio { scale: 0.5; transformOrigin: Item.Left; running: root.active && claude.visible && !root.hasSession && Hooks.installed && !Prefs.hookSeen }
                        DotWave { running: root.active && claude.visible && !root.hasSession && !(Hooks.installed && !Prefs.hookSeen); opacity: running ? 1 : 0 }
                    }
                    Item {
                        visible: root.hasSession
                        anchors.centerIn: parent
                        width: 16; height: 16
                        Spinner { anchors.fill: parent; visible: root.busy }
                        DrawnCheck { anchors.centerIn: parent; size: 16; color: "#B9DC6B"; visible: root.st === "done" }
                        Icon { anchors.centerIn: parent; size: 14; name: "cross"; color: "#FF8FA0"; visible: root.st === "failed" }
                        Icon { anchors.centerIn: parent; size: 15; name: "bell"; color: "#FFE08A"; visible: root.st === "alert" }
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#8a8292"; visible: root.st === "idle" }
                    }
                }
                Text {
                    x: 42
                    width: parent.width - x - 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasSession ? (Tr.d(root.s.line) || root.s.cwd || "") : Hooks.installed ? Tr.t("waiting for a session") : Tr.t("not connected")
                    elide: Text.ElideRight
                    color: "#F2ECF5"
                    opacity: root.hasSession ? 1 : 0.6
                    font.family: Theme.mono; font.pixelSize: 11
                }
                HoverHandler { id: stripHover; cursorShape: root.hasSession ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { id: stripTap; enabled: root.hasSession; onTapped: root.go("session") }
            }

            // what Miku makes of it
            Rectangle {
                y: 70
                width: side.width - (key.visible ? key.width + 6 : 0)
                height: 42
                radius: 12
                readonly property color tone: root.st === "failed" ? "#E0405A" : root.st === "alert" ? "#FFE08A" : root.teal
                readonly property bool loud: root.st === "failed" || root.st === "alert"
                color: Qt.rgba(tone.r, tone.g, tone.b, loud ? 0.3 : 0.14)
                border.width: 2
                border.color: Qt.rgba(tone.r, tone.g, tone.b, loud ? 1 : 0.5)
                opacity: Motion.rise(root.age, 3)
                transform: Translate { y: Motion.lift(root.age, 3) }
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: root.line
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                    lineHeight: 14; lineHeightMode: Text.FixedHeight
                }
            }
        }

        // the key beside her line: Connect, or Open
        Rectangle {
            id: key
            readonly property bool connects: !Hooks.installed
            visible: connects || root.hasSession
            x: side.x + side.width - width
            y: side.y + 70
            width: 62; height: 42
            radius: 12
            color: keyTap.pressed ? root.deep : root.teal
            border.width: activeFocus ? 3 : 2; border.color: "#FFFFFF"
            opacity: Motion.rise(root.age, 3)
            property real pulse: 1
            scale: pulse * (keyTap.pressed ? 0.92 : keyHover.hovered ? 1.06 : 1)
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: connects ? Tr.t("Connect Claude Code") : Tr.t("Open session")
            function act() { root.go(connects ? "settings" : "session") }
            Column {
                anchors.centerIn: parent
                spacing: 0
                Icon { anchors.horizontalCenter: parent.horizontalCenter; size: 17; name: key.connects ? "plus" : "terminal"; color: "#04302c" }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: key.connects ? Tr.t("Connect") : Tr.t("Open")
                    color: "#04302c"
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
                }
            }
            // first launch: the key pulses twice (scale 1 -> 1.08 -> 1, 600 ms each, 400 ms apart)
            SequentialAnimation {
                id: pulseAnim
                NumberAnimation { target: key; property: "pulse"; to: 1.08; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { target: key; property: "pulse"; to: 1; duration: 300; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 400 }
                NumberAnimation { target: key; property: "pulse"; to: 1.08; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { target: key; property: "pulse"; to: 1; duration: 300; easing.type: Easing.InOutSine }
            }
            HoverHandler { id: keyHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Sfx.play("hover") }
            TapHandler { id: keyTap; onTapped: key.act() }
            Keys.onReturnPressed: key.act()
            Keys.onSpacePressed: key.act()
        }
    }
    function pulseConnect() { if (!Hooks.installed) pulseAnim.restart() }

    // a key: a glyph, a small word over a big one
    component Key1: FocusScope {
        id: k
        property string over: ""
        property string label: ""
        property string icon: ""       // a name from Icon.qml, or "github"
        signal clicked()
        width: 104; height: 48
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(root.teal.r, root.teal.g, root.teal.b, kt.pressed ? 0.5 : kh.hovered ? 0.32 : 0.14)
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            border.width: k.activeFocus ? 3 : 2; border.color: "#FFFFFF"
            scale: kt.pressed ? 0.94 : kh.hovered ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Item {
                x: 8; width: 24; height: parent.height
                Icon { visible: k.icon !== "github"; anchors.centerIn: parent; size: 22; name: k.icon; color: root.teal }
                GitHubMark { visible: k.icon === "github"; anchors.centerIn: parent; size: 20; color: root.teal }
            }
            Text {
                x: 38; y: 7
                text: k.over
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
            }
            Text {
                x: 38; y: 21
                text: k.label
                color: Theme.ink
                font.family: Theme.display; font.pixelSize: 14; font.weight: Font.Bold
            }
        }
        HoverHandler { id: kh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Sfx.play("hover") }
        TapHandler { id: kt; onTapped: k.clicked() }
        Keys.onReturnPressed: k.clicked()
        Keys.onSpacePressed: k.clicked()
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
