// The island: a dark pill docked to one edge of the screen that grows into a card,
// or (floating) a mascot that lives free on the desktop and opens its card in
// place. Sizes, timings and behaviour follow motion.md.
//
//   docked   on top, bottom, left or right: collapsed 184-288 x 32 (32 x 176 on the
//            sides) -> home 660x200 | session 300 | permission 236/310/290 | github
//            276 | chat 412 | settings 440. The bar's size and manners follow Coucou's
//            island: a click opens it (280 ms OutCubic), it closes 15 s after the
//            pointer leaves unless something holds it open, and after a minute with
//            nothing to show it slides into the edge; touching the edge there, or any
//            activity, brings it back.
//   floating the mascot (120 px) is the whole window; click opens the card where it
//            stands, click again or the close icon closes it. It wanders while idle.
//   picking up  hold the mascot for 350 ms: a ring fills, then Kisel is drawn out of
//            the pill on a jelly neck. Carry it anywhere; near an edge a zone shows,
//            and letting go there docks it on that edge. Letting go elsewhere drops
//            it. Walls resist; a seam between two monitors lets it move across.
import QtQuick
import Kisel.Core

Item {
    id: root

    property string view: "home"
    property bool expanded: false
    property bool autoOpened: false   // opened by an event, not by the pointer
    property bool dropActive: false   // a file is being dragged over
    property bool dropHappy: false
    readonly property bool floating: Shell.floating
    readonly property real isoX: Shell.viewWide ? Shell.grabX : Shell.originX // the island's origin on the output
    readonly property real isoY: Shell.viewWide ? Shell.grabY : Shell.originY

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
    // ---- where the island is: an edge, or floating ---------------------------------
    readonly property string edge: Shell.edge
    readonly property bool vertical: !floating && (edge === "left" || edge === "right")
    readonly property bool atBottom: !floating && edge === "bottom"
    readonly property string dockSide: floating ? "none" : edge
    // Collapsed: a 32 px bar, 184 px at rest, widening to its status (max 288); a
    // 32 x 176 one on the sides; the mascot alone (120 px) while floating.
    readonly property int pillT: 32      // the bar's thickness
    readonly property int mini: 32       // the mascot in the bar
    readonly property int pillMin: 184
    readonly property int pillMax: 288
    readonly property int labelX: 12 + mini + 10
    readonly property real pillContentW: labelX + pillRow.implicitWidth + 16
    readonly property real pillW: Math.max(pillMin, Math.min(pillMax, pillContentW))
    readonly property real closedW: floating ? 120 : (vertical ? pillT : pillW)
    readonly property real closedH: floating ? 120 : (vertical ? 176 : pillT)
    readonly property real cardW: expanded ? 660 : closedW
    readonly property real cardH: expanded ? viewHeight : closedH
    // the radius follows min(26, short side / 2), so the pill turns into a card without a jump
    readonly property real radius: Math.min(26, Math.min(animW, animH) / 2)
    // The card resizes first when it grows (content follows 60 ms behind); when it
    // shrinks the content fades first and the card follows 60 ms later.
    property real animW: closedW
    property real animH: closedH
    property bool shrinking: false
    property bool snapSize: false  // a dock changes the pill's shape at once; the card morphs instead
    readonly property int enterDelay: shrinking ? 180 : 60
    onCardHChanged: { shrinking = cardH < animH - 0.5; animH = cardH }
    onCardWChanged: animW = cardW
    Behavior on animW { enabled: !root.snapSize; SequentialAnimation { PauseAnimation { duration: root.shrinking ? 60 : 0 } NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } } }
    Behavior on animH { enabled: !root.snapSize; SequentialAnimation { PauseAnimation { duration: root.shrinking ? 60 : 0 } NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } } }

    // how far the card has opened, 0 (pill) .. 1 (card)
    readonly property real openU: Math.max(0, Math.min(1, (animW - closedW) / Math.max(1, 660 - closedW)))
    function mix(a, b, u) { return a + (b - a) * u }
    // The card's place inside the surface. Top and bottom: centred on the pill, settling to
    // the surface's centre as it opens; bottom grows upward. Left and right: flush with the
    // edge, centred on the pill along it, kept inside the surface as it opens.
    readonly property real cardX: floating ? (width - animW) / 2
        : edge === "left" ? -tuckA
        : edge === "right" ? width - animW + tuckA
        : mix(Shell.pillAlong - animW / 2, 24, openU)
    readonly property real cardY: floating ? 8
        : edge === "top" ? -tuckA
        : edge === "bottom" ? height - animH + tuckA
        : mix(Shell.pillAlong - animH / 2, Math.max(8, Math.min(height - 8 - animH, Shell.pillAlong - animH / 2)), openU)
    // the dark surface runs `radius` past the flush side, so only the inner corners are round
    readonly property real shapeX: dockSide === "left" ? -radius : 0
    readonly property real shapeY: dockSide === "top" ? -radius : 0
    readonly property real shapeW: animW + (dockSide === "left" || dockSide === "right" ? radius : 0)
    readonly property real shapeH: animH + (dockSide === "top" || dockSide === "bottom" ? radius : 0)
    // which way the soft shadow falls (away from the wall)
    readonly property point shadowDir: dockSide === "bottom" ? Qt.point(0, -1) : dockSide === "left" ? Qt.point(1, 0)
                                     : dockSide === "right" ? Qt.point(-1, 0) : Qt.point(0, 1)

    // ---- behaviour -------------------------------------------------------------
    readonly property bool typing: chatView.inputFocus || settingsView.inputFocus
    readonly property bool holdOpen: Hub.pendingCount > 0 || dropActive || peek.running || typing || dragArea.dragging
    readonly property bool wantsKeys: expanded && (view === "chat" || view === "settings" || view === "permission")
    onWantsKeysChanged: Shell.setKeyboard(wantsKeys)
    onHoldOpenChanged: if (!holdOpen && !hover.hovered) closeIn(600)

    // ---- tucked into the edge ----------------------------------------------------
    // A minute with nothing to show and the bar slides out of sight, leaving a 240 x 6
    // strip on the edge that brings it back when the pointer touches it.
    property bool tucked: false
    readonly property bool canTuck: !floating && !expanded && !mfree && !assembling && !dragArea.pressed
        && !hover.hovered && !wake.hovered && Hub.pendingCount === 0 && Hub.chip === ""
        && (Hub.mood === "idle" || Hub.mood === "sleep")
    onCanTuckChanged: if (!canTuck) tucked = false
    onTuckedChanged: updateHit()
    Timer { interval: 60000; running: root.canTuck && !root.tucked; onTriggered: root.tucked = true }
    // the bar, the mascot hanging 6 px out of it and the shadow all clear the edge
    property real tuckA: tucked ? pillT + 14 : 0
    Behavior on tuckA { NumberAnimation { duration: Theme.reduced ? 0 : 340; easing.type: Easing.InOutCubic } }
    readonly property rect wakeRect: edge === "left" ? Qt.rect(0, Shell.pillAlong - 120, 6, 240)
        : edge === "right" ? Qt.rect(width - 6, Shell.pillAlong - 120, 6, 240)
        : edge === "bottom" ? Qt.rect(Shell.pillAlong - 120, height - 6, 240, 6)
        : Qt.rect(Shell.pillAlong - 120, 0, 240, 6)

    function openIsland(v) {
        view = v || "home"
        autoOpened = false
        open()
    }
    function open() {
        closeTimer.stop()
        stopWander()
        if (!expanded) {
            if (floating) mascot.jump(0.35) // the card is pushed out from under its feet
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
                closeIn(600)
        }
    }
    function toggleView(v) { view = view === v ? "home" : v }

    // 15 s after the pointer leaves; 600 ms once an answer or a peek is over
    function closeIn(ms) { closeTimer.interval = ms; closeTimer.restart() }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: {
            // floating: only an island that opened by itself closes by itself
            if (root.floating) { if (root.autoOpened) root.collapse() }
            else if (!hover.hovered) root.collapse()
        }
    }
    Timer { id: peekDelay; interval: 300; onTriggered: { root.open(); peek.restart() } } // peek for 4.5 s, then close unless the pointer is on it
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
            const inPill = !root.expanded && !root.floating
            if (inPill) // the burst starts from the pill's "Done" chip...
                burst.fire(card.x + (root.vertical ? root.pillT / 2 : root.labelX + 28), card.y + (root.vertical ? 34 : root.pillT / 2), root.mini)
            else
                burst.fire(mascot.x + mascot.width / 2, mascot.y + mascot.height * 0.55, mascot.width)
            if (!root.expanded) {
                // ...and the peek opens at the burst's peak, so the pieces seem to push the card open
                root.view = "session"
                root.autoOpened = true
                peekDelay.restart()
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

    // ---- first launch: the assembly (motion.md, "The assembly") ----------------
    // The cover drops in, becomes the island pill and the mint disc becomes its
    // leaf spot; the island then opens while the other shapes fly to their places
    // and become Kisel's body and gloss, the hook card, its button and the tiles.
    // Everything is driven by Assembly's clock; here we only react to its beats.
    readonly property bool assembling: assembly.running
    onAssemblingChanged: updateHit()
    function runIntro() {
        if (assembling) return
        closeTimer.stop()
        expanded = false
        view = "home"
        if (Theme.reduced) {
            // "Reduce motion": no flight, no morph; Home fades in with every element in place
            autoOpened = true
            open()
            peek.interval = 3000
            peek.restart()
            return
        }
        // Where everything lands, from the real layout (Home is 660 x 200, hung at the top centre)
        const cardX = (root.width - 660) / 2
        const ox = cardX + 150, oy = 48 // Home's content origin
        const pw = pillMin // the pill at rest
        assembly.pill = Qt.rect((root.width - pw) / 2, 0, pw, pillT)
        assembly.leaf = Qt.point((root.width - pw) / 2 + 12 + 27 * mini / 44, 6 + 5 * mini / 44)
        assembly.slot = Qt.rect(cardX + 14 + (132 - 110) / 2, 48, 110, 110)
        const hr = homeView.hookRect, br = homeView.buttonRect
        assembly.card = Qt.rect(ox + hr.x, oy + hr.y, hr.width, hr.height)
        assembly.button = Qt.rect(ox + br.x, oy + br.y, br.width, br.height)
        const tr = homeView.tileRects
        assembly.tiles = [
            { x: ox + tr[0].x, y: oy + tr[0].y, w: tr[0].width, h: tr[0].height, color: Theme.kisel },
            { x: ox + tr[1].x, y: oy + tr[1].y, w: tr[1].width, h: tr[1].height, color: Theme.amber }
        ]
        mascot.eyesShut = true
        mascot.leafScale = 0
        assembly.play()
    }
    Assembly {
        id: assembly
        onLanded: Sfx.play("open")
        onBorn: { // the island is ready: the mini Kisel appears with one blink; the pill bounces 4 %
            mascot.leafScale = 1
            mascot.eyesShut = false
            mascot.blinkNow()
            pillBounce.restart()
        }
        onUnfold: { // the island opens; the flying shapes become Kisel, the card, the button and the tiles
            root.view = "home"
            root.autoOpened = true
            root.open()
            mascot.leafScale = 0
            mascot.eyesShut = true
        }
        onSettled: { // Kisel opens its eyes with one blink, the leaf grows, and it jumps (power 0.6)
            mascot.eyesShut = false
            mascot.blinkNow()
            leafGrow.restart()
            mascot.jump(0.6)
            Sfx.play("done")
        }
        onPulse: homeView.pulseConnect()
        onCloseIsland: if (!hover.hovered && !root.holdOpen) root.collapseNow()
    }
    SequentialAnimation {
        id: pillBounce
        NumberAnimation { target: card; property: "scale"; to: 1.04; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 200; easing.type: Easing.OutBack }
    }
    NumberAnimation { id: leafGrow; target: mascot; property: "leafScale"; from: 0; to: 1; duration: 240; easing.type: Easing.OutBack }
    // a click skips the sequence: every shape snaps to its final form in 120 ms
    MouseArea { anchors.fill: parent; z: 30; enabled: root.assembling; onClicked: assembly.skip() }

    Component.onCompleted: {
        if (!Prefs.firstRunDone) {
            Prefs.firstRunDone = true
            runIntro()
        }
        if (Prefs.floating && !assembling)
            Shell.restoreFloat(Prefs.floatX, Prefs.floatY)
        updateHit()
    }

    function updateHit() {
        if (tucked) { Shell.setHitRect(root.x + wakeRect.x, root.y + wakeRect.y, wakeRect.width, wakeRect.height); return }
        // while the assembly plays, the whole top of the surface takes the click that skips it
        if (assembling) { Shell.setHitRect(0, 0, root.width, 300); return }
        // the card and the mascot (which can overhang it), in the surface's coordinates
        const x0 = Math.min(card.x, mascot.x), y0 = Math.min(card.y, mascot.y)
        const x1 = Math.max(card.x + card.width, mascot.x + mascot.width)
        const y1 = Math.max(card.y + card.height, mascot.y + mascot.height)
        if (mfree) Shell.setHitRect(root.x + mascot.x, root.y + mascot.y, mascot.width, mascot.height)
        else Shell.setHitRect(root.x + x0, root.y + body.y + y0, x1 - x0, y1 - y0)
    }
    // the island moved inside a full-output surface, or the surface shrank back
    onXChanged: updateHit()
    onYChanged: updateHit()
    Connections { target: Shell; function onViewWideChanged() { root.updateHit(); root.wideChanged2() } }
    Connections { target: Shell; function onPlacementChanged() { root.updateHit() } }

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
        if (Shell.debugOn) Shell.log(Date.now() % 100000 + " expanded=" + expanded + " card=" + Math.round(card.x) + "," + Math.round(card.y) + " " + Math.round(card.width) + "x" + Math.round(card.height) + " mascot=" + Math.round(mascot.x) + "," + Math.round(mascot.y) + " size " + Math.round(mascot.width))
        if (Theme.reduced) slotFade.restart()
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
        if (Theme.reduced) slotFade.restart()
        Prefs.floating = floating
        if (floating) { closeTimer.stop(); wanderTimer.restart() } else stopWander()
    }

    // "Reduce motion": the mascot does not glide between slots, it fades between them
    property real slotDip: 1
    NumberAnimation { id: slotFade; target: root; property: "slotDip"; from: 0; to: 1; duration: Theme.tFast }
    onViewChanged: if (Theme.reduced) slotFade.restart()

    // ---- carrying Kisel (motion.md, "Dragging, edges and monitors") ------------------------
    // The mascot is drawn in one of two ways: in its slot on the card (the normal case), or
    // "free": at an exact place on the output (freeCX, freeCY, freeSize), while it is being
    // carried, arcing into a dock, or settling after a drop. Everything here is in output
    // coordinates; `isoX/isoY` turns them into the island's own.
    property bool mfree: false
    property real freeCX: 0
    property real freeCY: 0
    property real freeSize: mini
    property bool growing: false      // freeSize animates (mini -> 120 after the neck snaps)
    Behavior on freeSize { enabled: root.growing && !Theme.reduced; NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
    property bool ghost: false        // the pill has been left behind: it fades out
    property bool settling: false     // let go; waiting for the surface to shrink back
    property string zoneEdge: ""      // the edge a drop would dock to ("" = none)
    property real zoneAlong: 0
    property real zoneDist: 999
    property bool leaning: false      // within 20 px of the wall, still held
    property string crossTarget: ""   // the monitor a drop would move Kisel to
    property bool straddling: false   // the mascot touches another monitor
    property real hopOnLand: 0
    // the bounding box of every monitor, in desktop coordinates
    function desktopRect() {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const s of Displays.screens) { x0 = Math.min(x0, s.x); y0 = Math.min(y0, s.y); x1 = Math.max(x1, s.x + s.w); y1 = Math.max(y1, s.y + s.h) }
        return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
    }
    // (read again whenever the placement changes: the work area can change under us)
    readonly property real screenW: { Shell.originX; return Shell.screenWidth() }
    readonly property real screenH: { Shell.originY; return Shell.screenHeight() }

    // where the mascot's slot is on the final collapsed pill, in output coordinates
    function slotCenterFinal() {
        const e = Shell.edge
        const vert = e === "left" || e === "right"
        const cw = vert ? pillT : pillW, ch = vert ? 176 : pillT
        const cx = e === "left" ? 0 : e === "right" ? width - cw : Shell.pillAlong - cw / 2
        const cy = e === "top" ? 0 : e === "bottom" ? height - ch : Shell.pillAlong - ch / 2
        const sx = e === "left" ? 6 : e === "right" ? -6 : 12
        const sy = e === "bottom" ? -6 : vert ? 12 : 6
        return Qt.point(Shell.originX + cx + sx + mini / 2, Shell.originY + cy + sy + mini / 2)
    }
    function freeBox() { return Qt.point(freeCX - freeSize / 2, freeCY - freeSize / 2) }

    // ---- docking: along an arc (320 ms InOutCubic) into the new pill's slot, shrinking to `mini`
    property real dockT: 0
    property point dockFrom: Qt.point(0, 0)
    property point dockTo: Qt.point(0, 0)
    function startDockArc() {
        dockFrom = Qt.point(freeCX, freeCY)
        dockTo = slotCenterFinal()
        growing = false
        if (Theme.reduced) { dockT = 1; finishDockArc(); return }
        dockAnim.restart()
    }
    NumberAnimation { id: dockAnim; target: root; property: "dockT"; from: 0; to: 1; duration: 320; easing.type: Easing.InOutCubic
        onFinished: root.finishDockArc() }
    onDockTChanged: {
        if (!dockAnim.running) return
        // along a quadratic arc whose control point sits 40 px above the straight line
        const a = dockFrom, b = dockTo, t = dockT
        const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2 - 40, k = 1 - t
        freeCX = k * k * a.x + 2 * k * t * cx + t * t * b.x
        freeCY = k * k * a.y + 2 * k * t * cy + t * t * b.y
        freeSize = 120 + (mini - 120) * t   // shrinks to `mini` with `detail` falling
    }
    function finishDockArc() {
        // landing: a ripple (ring, 24 to 56 px over 280 ms) and the "click" sound
        landRipple.go(slotCenterFinal().x - isoX, slotCenterFinal().y - isoY)
        Sfx.play("click")
        arcDone = true
        tryFinishFree()
    }
    property bool arcDone: true
    // the free state ends once the surface is small again and no arc is running
    function tryFinishFree() {
        if (!mfree || dragArea.picked) return
        if (Shell.viewWide || dockAnim.running) return
        mfree = false; settling = false; ghost = false; growing = false
        snapSize = false
        mascot.land()
        if (hopOnLand > 0) { mascot.jump(hopOnLand); hopOnLand = 0 }
    }
    function wideChanged2() { if (!Shell.viewWide) tryFinishFree() }

    // ---- the dock zone and the wall -----------------------------------------------------
    // The pointer is `P` (output coordinates). Docking is allowed on all four edges of the
    // monitor; the pill keeps 120 px from the corners; within 24 px of an edge's centre it
    // snaps to the centre with a tick.
    property bool tickBrighter: false
    Timer { id: tickOff; interval: 120; onTriggered: root.tickBrighter = false }
    function updateZone(Px, Py) {
        const d = { top: Py, bottom: screenH - Py, left: Px, right: screenW - Px }
        let best = "", bd = 96
        for (const e of ["top", "bottom", "left", "right"])
            if (d[e] < bd) { bd = d[e]; best = e }
        if (best === "") { zoneEdge = ""; zoneDist = 999; leaning = false; return }
        const len = Shell.edgeLength(best)
        let along = Shell.clampAlong(best, (best === "top" || best === "bottom") ? Px : Py)
        if (Math.abs(along - len / 2) < 24) {          // the centre magnet
            if (along !== len / 2 || zoneEdge !== best) { tickBrighter = true; tickOff.restart() }
            along = len / 2
        }
        const wasLeaning = leaning
        zoneEdge = best; zoneDist = bd; zoneAlong = along
        leaning = bd < 20
        if (leaning && !wasLeaning) {                   // the magnet ring pulses at the dock spot
            const horiz = best === "top" || best === "bottom"
            magnetRipple.color = Theme.kisel
            magnetRipple.go((horiz ? along : (best === "left" ? 22 : screenW - 22)) - isoX,
                            (horiz ? (best === "top" ? 22 : screenH - 22) : along) - isoY)
        }
    }
    // pressing into a wall: squash perpendicular to it, up to 18 percent at 40 px of over-drag
    function setWall(overX, overY) {
        let wx = 0, wy = 0
        if (overX !== 0) wx = Math.min(0.18, Math.abs(overX) / 40 * 0.18)
        if (overY !== 0) wy = Math.min(0.18, Math.abs(overY) / 40 * 0.18)
        if (leaning && zoneEdge !== "") {                // leaning on the wall: 10 percent
            if (zoneEdge === "left" || zoneEdge === "right") wx = Math.max(wx, 0.10)
            else wy = Math.max(wy, 0.10)
        }
        mascot.wallX = Theme.reduced ? 0 : wx
        mascot.wallY = Theme.reduced ? 0 : wy
        mascot.gazeOn = leaning
        if (leaning) mascot.gaze = Qt.point(zoneEdge === "left" ? 1 : zoneEdge === "right" ? -1 : 0,
                                            zoneEdge === "top" ? 1 : zoneEdge === "bottom" ? -1 : 0)
    }
    function clearWall() { mascot.wallX = 0; mascot.wallY = 0; mascot.gazeOn = false }

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

    // the pill is dented toward the mascot while it is drawn out
    property real dentX: 0
    property real dentY: 0
    Behavior on dentX { NumberAnimation { duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45 } }
    Behavior on dentY { NumberAnimation { duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45 } }

    // ---- everything below hangs from `body` ------------------------------------
    Item {
        id: body
        width: root.width
        height: root.height
        y: 0

        // soft shadow: three stacked rounded rectangles, no blur
        Repeater {
            model: [{ dy: 3, a: 0.12 }, { dy: 8, a: 0.095 }, { dy: 13, a: 0.07 }]
            Rectangle {
                required property var modelData
                x: card.x + root.shapeX + root.shadowDir.x * modelData.dy
                y: card.y + root.shapeY + root.shadowDir.y * modelData.dy
                width: root.shapeW
                height: root.shapeH
                radius: root.radius
                color: "black"
                opacity: (root.floating && !root.expanded) || root.ghost || (root.assembling && assembly.t < assembly.tBorn) ? 0 : modelData.a
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
            }
        }

        // an amber tab hangs under the card (above it when docked at the bottom) while a request waits
        AttentionTab {
            anchorX: mascot.x + mascot.width / 2
            cardBottom: root.atBottom ? card.y : card.y + card.height
            dir: root.atBottom ? -1 : 1
            waiting: root.floating || root.vertical || root.ghost ? 0 : Hub.pendingCount
            merged: root.expanded
        }

        // ---- the card ---------------------------------------------------------
        Item {
            id: card
            x: root.cardX + root.dentX
            y: root.cardY + root.dentY
            width: root.animW
            height: root.animH
            clip: true // the flush side sits past the screen edge: only the inner corners are round
            // during the assembly the real card appears when the flattened half-round hands over to it;
            // after a drag the new pill morphs in (scale and fade, 240 ms OutBack)
            opacity: (root.assembling && assembly.t < assembly.tBorn) || root.ghost ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: root.ghost ? 150 : 200 } }
            transformOrigin: root.dockSide === "bottom" ? Item.Bottom : root.dockSide === "left" ? Item.Left
                           : root.dockSide === "right" ? Item.Right : Item.Top
            property real morph: 1
            scale: morph
            NumberAnimation { id: cardMorph; target: card; property: "morph"; from: 0.7; to: 1; duration: 240; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack }
            onXChanged: root.updateHit()
            onYChanged: root.updateHit()
            onWidthChanged: root.updateHit()
            onHeightChanged: root.updateHit()

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (Shell.debugOn) Shell.log(Date.now() % 100000 + " hover " + hovered + " at output " + Math.round(root.isoX + card.x + point.position.x) + "," + Math.round(root.isoY + card.y + point.position.y))
                    Hub.poke()
                    if (root.floating || root.mfree) return // floating opens and closes by click
                    // the pointer alone never opens the card: the top of a screen is where
                    // tabs and title bars live. It only keeps an open card open.
                    if (hovered) closeTimer.stop()
                    else root.closeIn(15000)
                }
            }
            // a click anywhere on the bar opens it (on the mascot: see dragArea)
            TapHandler {
                enabled: !root.expanded && !root.floating && !root.mfree && !root.assembling
                onTapped: { Hub.poke(); root.autoOpened = false; root.open() }
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

            // the surface: surface-0 with a 1 px line on every side but the flush one
            Rectangle {
                x: root.shapeX; y: root.shapeY
                width: root.shapeW; height: root.shapeH
                radius: root.radius
                color: Theme.surface0
                opacity: root.floating && !root.expanded ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
                border.width: 1
                border.color: Theme.line
            }

            // behind everything: quiet drifting shapes, or the night sky
            HomeBackdrop {
                anchors.fill: parent
                show: root.expanded && root.view === "home"
                quiet: !Hub.session.id && Hub.mood !== "sleep"
                asleep: Hub.mood === "sleep"
            }

            // collapsed, on top or bottom: the label and the state chip, right of the mini mascot.
            // On open the text slides 8 px left and fades out in 100 ms; on close it
            // slides back in from the right for the last 120 ms.
            Row {
                id: pillRow
                x: root.labelX + (root.expanded ? -8 : 0)
                Behavior on x { NumberAnimation { duration: root.expanded ? 100 : 120; easing.type: Easing.OutCubic } }
                y: (root.pillT - height) / 2
                height: 24
                spacing: 10
                opacity: root.expanded || root.floating || root.vertical ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: root.expanded ? 100 : 120 } }

                readonly property string label: Hub.chip !== "" ? ""
                    : Hub.mood === "work" ? Hub.statusLine
                    : Hub.mood === "think" ? "Thinking"
                    : (Hub.mood === "alert" || Hub.mood === "happy" || Hub.mood === "sad") ? "" : "Kisel"
                Text {
                    visible: pillRow.label !== ""
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: pillRow.label
                    // the label never pushes the pill past its widest
                    width: Math.min(implicitWidth, root.pillMax - root.labelX - 16 - (Hub.mood === "work" ? 34 : 0))
                    elide: Text.ElideRight
                    color: Hub.mood === "sleep" ? Theme.inkFaint : Theme.ink
                    Behavior on color { ColorAnimation { duration: 160 } }
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                }
                PillBars { visible: Hub.mood === "work" && Hub.chip === ""; running: visible; anchors.verticalCenter: parent.verticalCenter }
                PillDots { visible: Hub.mood === "think" && Hub.chip === ""; running: visible; anchors.verticalCenter: parent.verticalCenter }
                PillChip { id: pillChip; kind: Hub.chip }
            }

            // collapsed, on a side: the state becomes an icon-only 24 px disc under the mascot;
            // the words appear when the card opens
            PillDisc {
                x: (root.pillT - width) / 2
                y: 12 + root.mini + 8
                opacity: root.vertical && !root.expanded ? 1 : 0
                kind: Hub.chip !== "" ? Hub.chip : Hub.mood === "work" ? "work" : Hub.mood === "think" ? "think" : ""
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
                        source: "resources/logo/kisel-mini.svg"
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

                ViewHost {
                    id: hostHome
                    active: root.expanded && root.view === "home"
                    enterDelay: root.enterDelay
                    HomeView {
                        id: homeView
                        age: hostHome.age
                        revealCard: assembly.revealCard
                        revealButton: assembly.revealButton
                        revealTiles: [assembly.revealTile(0), assembly.revealTile(1), 1, 1]
                        active: root.expanded && root.view === "home"
                        height: 200 - 62
                        onGo: (v) => root.view = v
                    }
                }
                ViewHost {
                    id: hostSession
                    active: root.expanded && root.view === "session"
                    enterDelay: root.enterDelay
                    SessionView { age: hostSession.age; active: hostSession.active; height: 300 - 62 }
                }
                ViewHost {
                    id: hostPermission
                    active: root.expanded && root.view === "permission"
                    enterDelay: root.enterDelay
                    PermissionView { age: hostPermission.age; active: hostPermission.active; height: root.viewHeight - 62 }
                }
                ViewHost {
                    id: hostGitHub
                    active: root.expanded && root.view === "github"
                    enterDelay: root.enterDelay
                    GitHubView { age: hostGitHub.age; active: hostGitHub.active; height: 276 - 62 }
                }
                ViewHost {
                    id: hostChat
                    active: root.expanded && root.view === "chat"
                    enterDelay: root.enterDelay
                    rises: false
                    ChatView {
                        id: chatView
                        active: hostChat.active
                        dropActive: root.dropActive
                        height: 412 - 62
                    }
                }
                ViewHost {
                    id: hostSettings
                    active: root.expanded && root.view === "settings"
                    enterDelay: root.enterDelay
                    rises: false
                    SettingsView {
                        id: settingsView
                        active: hostSettings.active
                        height: 440 - 62
                        onToast: (text) => root.showToast(text)
                    }
                }
            }
        }

        // Notices appear beside the island, away from the screen's edge, and never on top of
        // the pill's label.
        Toast {
            id: toast
            x: root.vertical ? (root.edge === "left" ? card.x : card.x + card.width - width)
                             : card.x + (card.width - width) / 2
            baseY: root.atBottom ? card.y - 28 - (root.expanded ? 16 : 12 + 6)
                 : card.y + card.height + (root.expanded ? 16 : (root.floating ? 12 : (root.vertical ? 12 : 12 + 6 + 22)))
            z: 5
        }

        // the zone preview, while Kisel is carried near an edge (drawn in output coordinates)
        DockZone {
            x: -root.isoX; y: -root.isoY
            edge: root.zoneEdge !== "" ? root.zoneEdge : "top"
            along: root.zoneAlong
            distance: root.zoneDist
            tick: root.tickBrighter
            screenW: root.screenW; screenH: root.screenH
            active: dragArea.dragging && dragArea.snapped && root.zoneEdge !== "" && root.crossTarget === ""
        }

        // tucked away: the strip on the edge that brings the bar back
        Item {
            x: root.wakeRect.x; y: root.wakeRect.y
            width: root.wakeRect.width; height: root.wakeRect.height
            visible: root.tucked
            HoverHandler { id: wake }
        }

        // the jelly neck between the pill and the mascot while it is drawn out
        Neck {
            id: neck
            z: 1
            active: dragArea.picked && dragArea.haveOff && !dragArea.snapped
            maxDist: 36
        }

        // ---- the one mascot: it glides between slots, it is never swapped -----------
        Mascot {
            id: mascot
            z: 2
            readonly property int slot: !root.expanded ? (root.floating ? 120 : root.mini)
                : ({ home: 110, session: 88, permission: 88, github: 88, chat: 64, settings: 64 })[root.view]
            // collapsed: 12 px from the left edge and 6 px below the pill's top, so it hangs
            // 6 px below the pill like a charm; on the other docks it overhangs 6 px toward the
            // screen (above the pill at the bottom, to the side on the sides)
            property real slotX: root.expanded ? 14 + (132 - slot) / 2
                : root.floating ? 0 : root.edge === "left" ? 6 : root.edge === "right" ? -6 : 12
            property real slotY: root.expanded ? (root.atBottom ? root.animH - slot - 12 : 48)
                : root.floating ? 0 : root.atBottom ? -6 : root.vertical ? 12 : 6
            readonly property bool gliding: !root.mfree && !Theme.reduced
            size: root.mfree ? root.freeSize : slot
            x: root.mfree ? root.freeCX - root.freeSize / 2 - root.isoX : card.x + slotX
            y: root.mfree ? root.freeCY - root.freeSize / 2 - root.isoY : card.y + slotY
            // "Reduce motion": the mascot does not glide, it fades between slots
            Behavior on size { enabled: mascot.gliding; NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
            Behavior on slotX { enabled: mascot.gliding; NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
            Behavior on slotY { enabled: mascot.gliding; NumberAnimation { duration: Theme.tBase; easing.type: Easing.OutCubic } }
            // docked on a side it leans 8 degrees toward the screen
            inwardTilt: root.vertical && !root.expanded ? (root.edge === "left" ? 8 : -8) : 0
            Behavior on inwardTilt { NumberAnimation { duration: 200 } }
            // during the assembly the mini shows only between "born" and the unfold, and the
            // real mascot takes over from the flying body when the sequence settles
            opacity: (root.assembling ? ((assembly.t >= assembly.tBorn && assembly.t < assembly.tOpen + 60) || assembly.t >= assembly.tSettle ? 1 : 0) : 1) * root.slotDip
            Behavior on opacity { NumberAnimation { duration: 120 } }
            skin: root.expanded && root.view === "github" ? "github" : ""
            walkDir: root.walkDir
            doneBadge: Hub.chip === "done"
            mood: root.dropActive ? "wow" : root.dropHappy ? "happy" : root.walking ? "walk" : Hub.mood
            looking: hover.hovered
            lookAt: mascot.mapFromItem(card, hover.point.position.x, hover.point.position.y)
        }

        // the hold ring around the mascot, and the ripples (output coordinates, island offset)
        HoldRing {
            id: ring
            size: mascot.width + 10
            x: mascot.x - 5; y: mascot.y - 5
            z: 3
            progress: dragArea.hold
        }
        Ripple { id: landRipple; anchors.fill: parent; z: 6 }
        Ripple { id: magnetRipple; anchors.fill: parent; z: 6 }
        Ripple { id: contactRipple; anchors.fill: parent; z: 6 }

        // Drag the mascot. A click shorter than 350 ms opens or closes the card; holding for
        // 350 ms picks Kisel up (a ring fills, then it is drawn out of the pill on a jelly
        // neck). Carry it anywhere; near an edge a zone appears and letting go docks it there.
        //
        // While the pointer is down the surface covers the whole output and stays still
        // (Shell.beginGrab); the mascot moves inside it by the pointer's exact position, so
        // there is no lag, no overshoot and no way to leave the screen.
        MouseArea {
            id: dragArea
            z: 4
            x: mascot.x; y: mascot.y
            width: mascot.width; height: mascot.height
            cursorShape: picked ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            property real hold: 0                 // the ring's progress, 0..1
            property bool picked: false           // the 350 ms are up and Kisel is in the hand
            property bool haveOff: false          // the first output-sized event has arrived
            property bool snapped: true           // the neck has snapped (or there never was one)
            property bool moved: false
            property point offC: Qt.point(0, 0)   // pointer minus the mascot's centre, output coordinates
            property point pressOff: Qt.point(0, 0) // the same, as it was when the button went down
            property real catchUp: 1              // 0..1: Kisel eases onto the pointer after a late pick-up
            property point pressPt: Qt.point(0, 0)
            property point lastC: Qt.point(0, 0)
            property double lastT: 0
            property real vx: 0
            property real vy: 0
            property point tC: Qt.point(0, 0)     // where the pointer wants the centre (unclamped)
            readonly property bool dragging: picked && haveOff

            function rootPoint(m) { return mapToItem(root, m.x, m.y) }
            function scenePoint(m) { return mapToItem(null, m.x, m.y) }
            function geom(name) {
                for (const s of Displays.screens) if (s.name === name) return s
                return { x: 0, y: 0, w: root.screenW, h: root.screenH }
            }

            NumberAnimation { id: holdAnim; target: dragArea; property: "hold"; from: 0; to: 1; duration: 350; easing.type: Easing.OutQuad
                onFinished: if (dragArea.pressed) dragArea.pickUp() }
            Timer { id: stillTimer; interval: 90; onTriggered: { mascot.dragVx = 0; mascot.dragVy = 0; dragArea.vx = 0; dragArea.vy = 0 } }
            Timer { id: settleGuard; interval: 700; onTriggered: root.tryFinishFree() }

            function pickUp() {
                picked = true; haveOff = false
                snapped = root.floating // from a pill the neck must snap first
                ring.popped = true
                mascot.dragging = true
                if (root.expanded) root.collapseNow() // the card, if open, closes (200 ms)
                Shell.beginGrab()
            }

            // the first pointer event on the output-sized surface: from here Kisel is free
            function beginFree(P) {
                const bc = Qt.point(mascot.x + mascot.width / 2 + root.isoX, mascot.y + mascot.height / 2 + root.isoY)
                // Kisel is held by the spot where the button went down, not by wherever the
                // pointer has got to during the 350 ms: if it moved, Kisel catches up
                offC = pressOff
                catchUp = Theme.reduced ? 1 : 0
                catchAnim.restart()
                bcStart = bc
                root.freeCX = bc.x; root.freeCY = bc.y; root.freeSize = mascot.size
                root.mfree = true
                haveOff = true
                lastC = bc; lastT = Date.now()
                root.crossTarget = ""
                if (root.floating) root.snapSize = false
                neck.from = Qt.point(bc.x - root.isoX, bc.y - root.isoY)
                neck.to = neck.from
            }

            property point bcStart: Qt.point(0, 0)
            NumberAnimation { id: catchAnim; target: dragArea; property: "catchUp"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }

            function carry(P) {
                if (!haveOff) { beginFree(P); return }
                const now = Date.now()
                let tcx = P.x - offC.x, tcy = P.y - offC.y
                tC = Qt.point(tcx, tcy)
                if (catchUp < 1) { // ease from where Kisel stood onto the pointer
                    tcx = bcStart.x + (tcx - bcStart.x) * catchUp
                    tcy = bcStart.y + (tcy - bcStart.y) * catchUp
                }
                if (Shell.debugOn) Shell.log("carry P=" + Math.round(P.x) + "," + Math.round(P.y) + " snapped=" + snapped)
                const dt = Math.max(1, now - lastT)
                vx = 0.55 * vx + 0.45 * (tcx - lastC.x) / dt * 1000
                vy = 0.55 * vy + 0.45 * (tcy - lastC.y) / dt * 1000
                mascot.dragVx = vx; mascot.dragVy = vy
                lastC = Qt.point(tcx, tcy); lastT = now
                stillTimer.restart()

                if (!snapped) {
                    // being drawn out of the pill: the neck stretches, the pill dents 4 px toward Kisel
                    const sc = Qt.point(neck.from.x + root.isoX, neck.from.y + root.isoY)
                    const dx = tcx - sc.x, dy = tcy - sc.y
                    const d = Math.hypot(dx, dy)
                    root.freeCX = tcx; root.freeCY = tcy
                    neck.to = Qt.point(tcx - root.isoX, tcy - root.isoY)
                    const k = d > 0 ? Math.min(1, d / 36) * 4 / d : 0
                    root.dentX = Theme.reduced ? 0 : dx * k; root.dentY = Theme.reduced ? 0 : dy * k
                    if (d >= 36) {                      // the neck snaps: two droplets fall, the pill recovers
                        snapped = true
                        neck.snap(Qt.point(sc.x - root.isoX, sc.y - root.isoY))
                        root.dentX = 0; root.dentY = 0
                        root.ghost = true               // the pill fades away behind Kisel
                        root.growing = true
                        root.freeSize = 120             // grows from `mini` to 120 along the drag
                        mascot.land()
                    }
                    return
                }

                // carried: the centre follows the pointer. Where another monitor touches this one
                // the mascot goes on across the seam (drawn on both monitors, clipped at the
                // seam); everywhere else the edge of the desktop is a wall.
                const half = root.freeSize / 2
                const g = geom(Displays.current)
                const gcx = g.x + tcx, gcy = g.y + tcy             // the centre on the whole desktop
                const here = Displays.screenAt(gcx, gcy)           // the monitor under the centre ("" in a gap)
                let Cx, Cy
                if (here !== "") {
                    const U = root.desktopRect()
                    Cx = Math.max(U.x + half, Math.min(U.x + U.w - half, gcx)) - g.x
                    Cy = Math.max(U.y + half, Math.min(U.y + U.h - half, gcy)) - g.y
                } else {
                    Cx = Math.max(half, Math.min(root.screenW - half, tcx))
                    Cy = Math.max(half, Math.min(root.screenH - half, tcy))
                }
                root.freeCX = Cx; root.freeCY = Cy
                const overX = tcx - Cx, overY = tcy - Cy

                // draw the mascot on every other monitor its box touches
                let straddling = false
                for (const s of Displays.screens) {
                    if (s.name === Displays.current) continue
                    const gx = g.x + Cx, gy = g.y + Cy
                    const touches = gx + half > s.x && gx - half < s.x + s.w && gy + half > s.y && gy - half < s.y + s.h
                    if (touches) {
                        straddling = true
                        Seams.show(s.name, gx - s.x, gy - s.y, root.freeSize, vx, vy, Hub.mood)
                    } else {
                        Seams.hideScreen(s.name)
                    }
                }
                const crossing = here !== "" && here !== Displays.current
                if (Shell.debugOn) Shell.log("carry C=" + Math.round(Cx) + "," + Math.round(Cy) + " here=" + here + " straddling=" + straddling + " cross=" + crossing)
                if (straddling && !root.straddling) contactRipple.go(Cx - root.isoX, Cy - root.isoY) // contact: a ripple
                root.straddling = straddling
                root.crossTarget = crossing ? here : ""

                if (straddling) { root.zoneEdge = ""; root.zoneDist = 999; root.leaning = false }
                else root.updateZone(P.x, P.y)
                root.setWall(overX, overY)
            }

            function springBack() {
                // let go before the neck snapped: Kisel springs back into the pill
                springFrom = Qt.point(root.freeCX, root.freeCY)
                springTo = Qt.point(neck.from.x + root.isoX, neck.from.y + root.isoY)
                springAnim.restart()
                root.dentX = 0; root.dentY = 0
            }

            function release() {
                Seams.hideAll()
                root.straddling = false
                if (Shell.debugOn) Shell.log("release picked=" + picked + " haveOff=" + haveOff + " snapped=" + snapped + " cross=" + root.crossTarget + " zone=" + root.zoneEdge)
                const had = haveOff
                mascot.dragging = false
                mascot.dragVx = 0; mascot.dragVy = 0; vx = 0; vy = 0; stillTimer.stop()
                root.clearWall()
                root.leaning = false
                if (!had) {                         // held and let go in place
                    picked = false
                    Shell.endGrab()
                    mascot.land()
                    return
                }
                if (!snapped) { picked = false; springBack(); return }

                const wasZone = root.zoneEdge !== "" && root.zoneDist < 20 && root.crossTarget === ""
                if (root.crossTarget !== "") {
                    // across the seam: float on the other monitor, where the pointer is
                    const g = geom(Displays.current), tg = geom(root.crossTarget)
                    const cx = g.x + tC.x - tg.x, cy = g.y + tC.y - tg.y
                    root.snapSize = true
                    root.settling = true
                    picked = false
                    Displays.crossTo(root.crossTarget, cx - 60, cy - 60)
                    root.hopOnLand = 0.25                   // it settles on the new monitor with a small hop
                    Prefs.floating = true; Prefs.floatX = Shell.floatX; Prefs.floatY = Shell.floatY
                    root.crossTarget = ""
                    settleGuard.restart()
                } else if (wasZone) {
                    const used = Shell.setDock(root.zoneEdge, root.zoneAlong)
                    Prefs.floating = false
                    Prefs.setDock(Displays.current, root.zoneEdge, used / Shell.edgeLength(root.zoneEdge))
                    root.snapSize = true
                    root.settling = true
                    root.arcDone = false
                    picked = false
                    Shell.endGrab()
                    root.startDockArc()
                    settleGuard.restart()
                } else {
                    // dropped in the open: it lands where it is
                    root.snapSize = true
                    root.settling = true
                    Shell.restoreFloat(root.freeCX - 60 - 294, root.freeCY - 60 - 8)
                    Prefs.floating = true; Prefs.floatX = Shell.floatX; Prefs.floatY = Shell.floatY
                    picked = false
                    Shell.endGrab()
                    settleGuard.restart()
                }
                root.zoneEdge = ""; root.zoneDist = 999
            }

            // the spring back into the pill (380 ms OutElastic)
            property real springT: 0
            property point springFrom: Qt.point(0, 0)
            property point springTo: Qt.point(0, 0)
            NumberAnimation { id: springAnim; target: dragArea; property: "springT"; from: 0; to: 1; duration: 380
                easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45
                onFinished: { Shell.endGrab(); root.tryFinishFree() } }
            onSpringTChanged: {
                if (!springAnim.running) return
                root.freeCX = springFrom.x + (springTo.x - springFrom.x) * springT
                root.freeCY = springFrom.y + (springTo.y - springFrom.y) * springT
                root.freeSize = root.mini
            }

            onPressed: (m) => {
                if (Shell.debugOn) Shell.log(Date.now() % 100000 + " press at " + Math.round(m.x) + "," + Math.round(m.y))
                if (root.walking) mascot.hang() // picked up mid-walk: the body hangs and sways
                root.stopWander()
                if (root.dockT > 0 && dockAnim.running) return
                pressPt = rootPoint(m)
                pressOff = Qt.point(m.x - width / 2, m.y - height / 2)
                picked = false; haveOff = false; moved = false
                ring.popped = false
                hold = 0
                mascot.compress()                  // press compression, 70 ms
                holdAnim.restart()
            }
            onPositionChanged: (m) => {
                if (!pressed) return
                if (!picked) {
                    const c = rootPoint(m)
                    if (Math.hypot(c.x - pressPt.x, c.y - pressPt.y) > 8) moved = true
                    return
                }
                if (!Shell.viewWide) return         // wait for the compositor to give us the whole output
                carry(scenePoint(m))
            }
            function finishPress(clicked) {
                holdAnim.stop()
                if (picked) { release(); return }
                const progressed = hold
                hold = 0
                if (clicked && !moved && root.dockT === 0) {
                    // a click: squash, sound, and open/close
                    mascot.poke()
                    Hub.poke()
                    if (root.floating) {
                        if (root.expanded) root.collapseNow()
                        else { root.autoOpened = false; root.open() }
                    } else if (!root.expanded) {
                        root.open()
                    } else if (Hub.pendingCount === 0) {
                        root.collapseNow()         // docked and open: a click on Kisel puts the card away
                    }
                } else if (progressed > 0.1) {
                    mascot.land()                  // a hold let go early: a small recoil
                }
            }
            onReleased: finishPress(true)
            onCanceled: finishPress(false)
        }

        DoneBurst { id: burst; anchors.fill: parent; z: 10 }
    }

    // ---- development helpers (kisel --drag-test, --dock-edge) ---------------------------
    function devState() {
        return "edge=" + Shell.edge + " floating=" + floating + " wide=" + Shell.viewWide + " mfree=" + mfree
             + " picked=" + dragArea.picked + " snapped=" + dragArea.snapped + " zone=" + zoneEdge
             + " dist=" + Math.round(zoneDist) + " cross=" + crossTarget
             + " origin=" + Math.round(Shell.originX) + "," + Math.round(Shell.originY)
    }
    function devCenter() { return Qt.point(mascot.x + mascot.width / 2, mascot.y + mascot.height / 2) }
    function devDock(edge, frac) { Shell.setDock(edge, frac * Shell.edgeLength(edge)); updateHit() }

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
