// The island: a dark pill flush with the top edge that grows into a card, or
// (floating) a mascot that lives free on the desktop and opens its card in
// place. Sizes, timings and behaviour follow motion.md.
//
//   docked   collapsed 204x40 -> home 660x200 | session 300 | permission 236/310/290
//            | github 276 | chat 412 | settings 440. Opens on hover (280 ms OutCubic),
//            closes 600 ms after the pointer leaves unless something holds it open.
//   floating the mascot (120 px) is the whole window; click opens the card where it
//            stands, click again or the close icon closes it. Drag > 36 px out of the
//            island floats it; within 20 px of the top edge docks it again. While idle
//            it wanders: every 18-48 s it walks up to 260 px sideways.
import QtQuick
import Kisel.Core

Item {
    id: root

    property string view: "home"
    property bool expanded: false
    property bool autoOpened: false   // opened by an event, not by the pointer
    property bool dropActive: false   // a file is being dragged over
    property bool dropHappy: false
    property bool introActive: false  // the first-launch sequence is running
    readonly property bool floating: Shell.floating

    function showToast(text) { toast.show(text) }

    // ---- geometry --------------------------------------------------------------
    readonly property int viewHeight: {
        switch (view) {
        case "session": return 300
        case "permission": return Hub.permission.kind === "diff" ? 310 : Hub.permission.kind === "question" ? 290 : 236
        case "github": return 276
        case "chat": return 412
        case "settings": return 440
        default: return 200
        }
    }
    readonly property real closedW: floating ? 120 : 204
    readonly property real closedH: floating ? 120 : 40
    readonly property real cardW: expanded ? 660 : closedW
    readonly property real cardH: expanded ? viewHeight : closedH
    readonly property real radius: Math.min(26, cardH / 2)
    property real animW: cardW
    property real animH: cardH
    Behavior on animW { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
    Behavior on animH { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }

    // ---- behaviour -------------------------------------------------------------
    readonly property bool typing: chatView.inputFocus || settingsView.inputFocus
    readonly property bool holdOpen: Hub.pendingCount > 0 || dropActive || peek.running || typing || dragArea.dragging
    readonly property bool wantsKeys: expanded && (view === "chat" || view === "settings" || view === "permission")
    onWantsKeysChanged: Shell.setKeyboard(wantsKeys)
    onHoldOpenChanged: if (!holdOpen && !hover.hovered) closeTimer.restart()

    function openIsland(v) {
        view = v || "home"
        autoOpened = false
        open()
    }
    function open() {
        closeTimer.stop()
        stopWander()
        if (!expanded) {
            expanded = true
            Sfx.play("open")
        }
    }
    // closes if nothing holds it open (the timer, the hover rules)
    function collapse() {
        if (!expanded || holdOpen)
            return
        collapseNow()
    }
    // an explicit close: the close icon, a click on the floating mascot, Escape
    function collapseNow() {
        if (!expanded)
            return
        expanded = false
        view = Hub.pendingCount > 0 ? "permission" : "home"
        Sfx.play("close")
    }
    function afterAnswer() {
        if (Hub.pendingCount === 0) {
            view = "home"
            if (!hover.hovered || floating)
                closeTimer.restart()
        }
    }
    function toggleView(v) { view = view === v ? "home" : v }

    Timer {
        id: closeTimer
        interval: 600
        onTriggered: {
            // floating: only an island that opened by itself closes by itself
            if (root.floating) { if (root.autoOpened) root.collapse() }
            else if (!hover.hovered) root.collapse()
        }
    }
    Timer { id: peek; interval: 4500; onTriggered: if (!hover.hovered || root.floating) root.collapse() }
    Timer { id: dropHappyTimer; interval: 1500; onTriggered: root.dropHappy = false }

    Connections {
        target: Hub
        function onPermissionArrived() {
            Sfx.play("alert")
            root.autoOpened = !root.expanded
            root.view = "permission"
            root.open()
        }
        function onPermissionAnswered(decision) {
            if (decision === "allow" || decision === "always") Sfx.play("click")
            else if (decision === "deny") Sfx.play("deny")
            root.afterAnswer()
        }
        function onPermissionCleared() { root.afterAnswer() }
        function onTaskFinished() {
            Sfx.play("done")
            burst.fire(mascot.x + mascot.width / 2, mascot.y + mascot.height * 0.55, mascot.width)
            if (!root.expanded) {
                root.view = "session"
                root.autoOpened = true
                root.open()
                peek.restart() // peek for 4.5 s, then close unless the pointer is on it
            }
        }
        function onToolFailed() { Sfx.play("deny") }
        function onActivity() { root.stopWander() }
    }

    // ---- moved to another monitor: arrive with a hop ---------------------------
    Connections {
        target: Displays
        function onMoved() { arriveTimer.restart() }
    }
    Timer {
        id: arriveTimer
        interval: 350
        onTriggered: { mascot.jump(1.0); Sfx.play("done"); root.updateHit() }
    }

    // ---- first launch (motion.md, "First launch") ------------------------------
    // 0 ms the shapes drop in and converge (FirstLaunch); 1320 the empty pill
    // slides down; 1900 one blink; 2300 the island opens to Home; 2600 the
    // mascot jumps with sparkles; 2900 the Connect button pulses twice; 5700 the
    // island closes again.
    property real introY: 0
    function runIntro() {
        introActive = true
        introY = -44
        firstLaunch.play()
        introAnim.restart()
    }
    FirstLaunch {
        id: firstLaunch
        z: 20
        onLanded: Sfx.play("open")
        onConverging: pillSlide.restart()
        onFinished: root.introActive = false
    }
    NumberAnimation { id: pillSlide; target: root; property: "introY"; to: 0; duration: 260; easing.type: Easing.OutBack }
    SequentialAnimation {
        id: introAnim
        PauseAnimation { duration: 1900 }
        ScriptAction { script: mascot.blinkNow() }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { root.view = "home"; root.autoOpened = true; root.open() } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: mascot.celebrate(0.6) }
        PauseAnimation { duration: 300 }
        ScriptAction { script: homeView.pulseConnect() }
        PauseAnimation { duration: 2800 }
        ScriptAction { script: if (!hover.hovered && !root.holdOpen) root.collapseNow() }
    }

    Component.onCompleted: {
        if (!Prefs.firstRunDone) {
            Prefs.firstRunDone = true
            runIntro()
        }
        if (Prefs.floating && !introActive)
            Shell.restoreFloat(Prefs.floatX, Prefs.floatY)
        updateHit()
    }

    function updateHit() { Shell.setHitRect(card.x, body.y + card.y, card.width, card.height) }

    // ---- floating: where the surface sits ---------------------------------------
    property point homePos: Qt.point(0, 0)
    ParallelAnimation {
        id: fitAnim
        property real toX: 0
        property real toY: 0
        NumberAnimation { target: Shell; property: "floatX"; to: fitAnim.toX; duration: Theme.tBase; easing.type: Easing.OutCubic }
        NumberAnimation { target: Shell; property: "floatY"; to: fitAnim.toY; duration: Theme.tBase; easing.type: Easing.OutCubic }
    }
    onExpandedChanged: {
        if (!floating) return
        if (expanded) { // slide so the whole card stays on screen
            homePos = Qt.point(Shell.floatX, Shell.floatY)
            const p = Shell.fitOpen()
            fitAnim.toX = p.x; fitAnim.toY = p.y
            fitAnim.restart()
        } else { // and slide back to where the mascot was left
            fitAnim.toX = homePos.x; fitAnim.toY = homePos.y
            fitAnim.restart()
        }
    }
    onFloatingChanged: {
        Prefs.floating = floating
        if (floating) { closeTimer.stop(); wanderTimer.restart() } else stopWander()
    }

    // ---- wandering --------------------------------------------------------------
    property bool walking: false
    property int walkDir: 1
    function stopWander() {
        if (!walking) return
        wanderAnim.stop()
        walking = false
    }
    function startWander() {
        if (!floating || expanded || dragArea.dragging || Hub.mood !== "idle")
            return
        const want = Shell.floatX + (Math.random() * 2 - 1) * 260
        const target = Shell.clampMascot(want, Shell.floatY)
        const dx = target.x - Shell.floatX
        if (Math.abs(dx) < 30)
            return
        walkDir = dx > 0 ? 1 : -1
        wanderAnim.from = Shell.floatX
        wanderAnim.to = target.x
        wanderAnim.duration = Math.abs(dx) * 9 // 9 ms per pixel
        walking = true
        wanderAnim.start()
    }
    NumberAnimation {
        id: wanderAnim
        target: Shell
        property: "floatX"
        easing.type: Easing.InOutSine
        onFinished: { root.walking = false; Prefs.floatX = Shell.floatX }
    }
    Timer {
        id: wanderTimer
        interval: 18000 + Math.random() * 30000
        running: root.floating && !root.expanded && !Theme.reduced
        repeat: true
        onTriggered: { interval = 18000 + Math.random() * 30000; root.startWander() }
    }

    // ---- everything below hangs from `body`, which the first launch slides ---------
    Item {
        id: body
        width: root.width
        height: root.height
        y: root.introY

        // soft shadow: three stacked rounded rectangles, no blur
        Repeater {
            model: [{ dy: 3, a: 0.12 }, { dy: 8, a: 0.095 }, { dy: 13, a: 0.07 }]
            Rectangle {
                required property var modelData
                x: card.x
                y: root.floating ? card.y : -root.radius
                width: card.width
                height: card.height + (root.floating ? 0 : root.radius) + modelData.dy
                radius: root.radius
                color: "black"
                opacity: root.floating && !root.expanded ? 0 : modelData.a
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
            }
        }

        // an amber tab hangs under the card while a request waits
        AttentionTab {
            anchorX: mascot.x + mascot.width / 2
            cardBottom: card.y + card.height
            waiting: root.floating && !root.expanded ? 0 : Hub.pendingCount
        }

        // ---- the card ---------------------------------------------------------
        Item {
            id: card
            x: (root.width - width) / 2
            y: root.floating ? 8 : 0
            width: root.animW
            height: root.animH
            clip: true // docked: the top corners sit above the screen, only the bottom is rounded
            onXChanged: root.updateHit()
            onYChanged: root.updateHit()
            onWidthChanged: root.updateHit()
            onHeightChanged: root.updateHit()

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    Hub.poke()
                    if (root.floating) return // floating opens and closes by click
                    if (hovered) {
                        closeTimer.stop()
                        if (!root.expanded) {
                            root.autoOpened = false
                            root.open()
                        }
                    } else {
                        closeTimer.restart()
                    }
                }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: (drag) => {
                    root.dropActive = true
                    root.view = "chat"
                    root.open()
                }
                onExited: root.dropActive = false
                onDropped: (drop) => {
                    root.dropActive = false
                    if (drop.hasUrls && Chat.attach(drop.urls[0])) {
                        root.dropHappy = true
                        dropHappyTimer.restart()
                        Sfx.play("click")
                    }
                }
            }

            // the surface: black pill collapsed, surface-0 with a hairline expanded
            Rectangle {
                y: root.floating ? 0 : -root.radius
                width: parent.width
                height: parent.height + (root.floating ? 0 : root.radius)
                radius: root.radius
                color: root.expanded ? Theme.surface0 : "#000000"
                Behavior on color { ColorAnimation { duration: Theme.tBase } }
                opacity: root.floating && !root.expanded ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                border.width: root.expanded ? 1 : 0
                border.color: Theme.line
            }

            // behind everything: quiet drifting shapes, or the night sky
            HomeBackdrop {
                anchors.fill: parent
                show: root.expanded && root.view === "home"
                quiet: !Hub.session.id && Hub.mood !== "sleep"
                asleep: Hub.mood === "sleep"
            }

            // collapsed (docked): the mascot, a status dot and one word
            Rectangle {
                x: 48; y: 16; width: 8; height: 8; radius: 4
                opacity: root.expanded || root.floating ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                color: Hub.mood === "alert" ? Theme.amber : Hub.mood === "happy" ? Theme.mint
                     : Hub.mood === "sad" ? Theme.danger : (Hub.mood === "work" || Hub.mood === "think") ? Theme.info
                     : Theme.inkFaint
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            Text {
                x: 62
                y: 12
                width: parent.width - 72
                opacity: root.expanded || root.floating ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                text: Hub.statusLine
                elide: Text.ElideRight
                color: Hub.mood === "alert" ? Theme.amber : Theme.ink
                font.family: Theme.sans
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            // header: wordmark, title, icon buttons
            Item {
                id: header
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                width: parent.width
                height: 48

                Row {
                    x: 14; y: 12
                    spacing: Theme.space2
                    Image {
                        source: "resources/logo/kisel-mark.svg"
                        width: 24; height: 24
                        sourceSize: Qt.size(48, 48)
                    }
                    Text {
                        text: "Kisel"
                        color: Theme.ink
                        font.family: Theme.display
                        font.weight: Font.Bold
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    TapHandler { onTapped: root.view = "home" }
                }
                Text {
                    x: 150; y: 12
                    width: 330
                    height: 24
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    text: root.view === "session" ? (Hub.session.name || "Session")
                        : root.view === "permission" ? (Hub.permission.kind === "question" ? "Question" : "Permission")
                        : root.view === "chat" ? "Chat"
                        : root.view === "github" ? "GitHub"
                        : root.view === "settings" ? "Settings" : ""
                    color: Theme.ink
                    font.family: Theme.display
                    font.weight: Font.DemiBold
                    font.pixelSize: 20
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    y: 8
                    spacing: 2
                    IconBtn { icon: Prefs.soundOn ? "sound" : "mute"; label: Prefs.soundOn ? "Mute sounds" : "Unmute sounds"; onClicked: Prefs.soundOn = !Prefs.soundOn }
                    IconBtn { icon: "chat"; label: "Chat"; active: root.view === "chat"; onClicked: root.toggleView("chat") }
                    IconBtn { icon: "gear"; label: "Settings"; active: root.view === "settings"; onClicked: root.toggleView("settings") }
                    IconBtn { visible: root.floating; icon: "up"; label: "Close"; onClicked: root.collapseNow() }
                }
            }

            // views cross-fade in 140 ms, no sliding
            Item {
                x: 150; y: 48
                width: 494
                height: root.viewHeight - 62

                HomeView {
                    id: homeView
                    active: root.expanded && root.view === "home"
                    height: 200 - 62
                    onGo: (v) => root.view = v
                }
                SessionView {
                    active: root.expanded && root.view === "session"
                    height: 300 - 62
                }
                PermissionView {
                    active: root.expanded && root.view === "permission"
                    height: root.viewHeight - 62
                }
                GitHubView {
                    active: root.expanded && root.view === "github"
                    height: 276 - 62
                }
                ChatView {
                    id: chatView
                    active: root.expanded && root.view === "chat"
                    dropActive: root.dropActive
                    height: 412 - 62
                }
                SettingsView {
                    id: settingsView
                    active: root.expanded && root.view === "settings"
                    height: 440 - 62
                    onToast: (text) => root.showToast(text)
                }
            }

            Toast {
                id: toast
                x: (parent.width - width) / 2
                baseY: parent.height - 44
                z: 5
            }
        }

        // ---- the one mascot: it glides between slots, it is never swapped -----------
        Mascot {
            id: mascot
            readonly property int slot: !root.expanded ? (root.floating ? 120 : 30)
                : ({ home: 110, session: 88, permission: 88, github: 88, chat: 64, settings: 64 })[root.view]
            property real slotX: root.expanded ? 14 + (132 - slot) / 2 : (root.floating ? 0 : 10)
            property real slotY: root.expanded ? 48 : (root.floating ? 0 : 8)
            size: slot
            x: card.x + slotX
            y: card.y + slotY
            Behavior on size { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
            Behavior on slotX { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
            Behavior on slotY { NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
            skin: root.expanded && root.view === "github" ? "github" : ""
            walkDir: root.walkDir
            mood: root.dropActive ? "wow" : root.dropHappy ? "happy" : root.walking ? "walk" : Hub.mood
            looking: hover.hovered
            lookAt: mascot.mapFromItem(card, hover.point.position.x, hover.point.position.y)
        }

        // Drag the mascot: out of the island to float it, around the desktop to move it,
        // to the top edge to dock it. A plain click opens or closes the card.
        MouseArea {
            id: dragArea
            x: mascot.x; y: mascot.y
            width: mascot.width; height: mascot.height
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            property point press
            property point anchorPt: Qt.point(0, 0) // where the pointer should sit in the surface while dragging
            property bool dragging: false
            property bool docked: false

            function rootPoint(m) { return mapToItem(root, m.x, m.y) }
            onPressed: (m) => {
                root.stopWander()
                press = rootPoint(m)
                dragging = false
                docked = false
            }
            onPositionChanged: (m) => {
                if (!pressed || docked) return
                const cur = rootPoint(m)
                if (!dragging) {
                    // docked: pull > 36 px away from the island; floating: a 6 px slop
                    const dist = Math.hypot(cur.x - press.x, cur.y - press.y)
                    if (dist < (root.floating ? 6 : 36)) return
                    dragging = true
                    if (!root.floating) {
                        root.expanded = false
                        Shell.beginFloat(cur.x, cur.y)
                    }
                    anchorPt = Qt.point(354, 68) // the mascot's centre in the floating surface
                }
                // The compositor applies the new position a frame later, so close only
                // part of the gap each time: the mascot trails the pointer a little, like jelly.
                Shell.moveBy((cur.x - anchorPt.x) * 0.6, (cur.y - anchorPt.y) * 0.6)
                // within 20 px of the top edge: dock
                if (Shell.floatY + 8 < 20) {
                    Shell.dock()
                    docked = true
                    dragging = false
                }
            }
            onReleased: {
                if (dragging) {
                    Prefs.floatX = Shell.floatX
                    Prefs.floatY = Shell.floatY
                } else if (!docked) {
                    // a click: squash, sound, and open/close
                    mascot.poke()
                    Hub.poke()
                    if (root.floating) {
                        if (root.expanded) root.collapseNow()
                        else { root.autoOpened = false; root.open() }
                    } else if (!root.expanded) {
                        root.open()
                    }
                }
                dragging = false
            }
        }

        DoneBurst { id: burst; anchors.fill: parent; z: 10 }
    }

    Keys.onEscapePressed: { closeTimer.stop(); root.collapseNow() }

    component IconBtn: FocusScope {
        id: btn
        property string icon: ""
        property string label: ""
        property bool active: false
        signal clicked()
        width: 32; height: 32
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: tap.pressed || btn.active || bh.hovered ? Theme.surface3 : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.tHover } }
            border.width: btn.activeFocus ? 2 : 0
            border.color: Theme.kisel
            scale: tap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: Theme.tPress } }
            Icon {
                anchors.centerIn: parent
                size: 20
                name: btn.icon
                color: bh.hovered || btn.active ? Theme.ink : Theme.inkMuted
            }
        }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: btn.clicked() }
        Keys.onReturnPressed: btn.clicked()
        Keys.onSpacePressed: btn.clicked()
    }
}
