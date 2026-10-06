// Kisel, the raspberry-jelly creature. One body drawn from vector paths and
// animated only by transforms, opacity and colour (motion.md, "The mascot").
// Geometry is the 128 x 128 logo (resources/logo/kisel-mark.svg).
//
// Level of detail: one body, one silhouette, one set of eye positions at every
// size. Only the amount of detail changes, driven by
//   detail = clamp((size - 44) / 66, 0, 1)
// (0 at 44 px: flat, outlined, no cheeks; 1 from 110 px: gradient, gloss,
// cheeks, highlights). The island's pill gliding to its card therefore turns
// the mini into the full mascot continuously ("Collapsed v2").
//
// Moods: idle think work alert wow happy sad sleep dizzy walk. The Island (via
// the Hub) decides the mood. A change of mood is a *bridge*, never a cut
// ("Transitions between states"): the mood is split into parts (body, face,
// badge, leaf) that follow the new mood with their own delays, plus small
// pre-actions (startle, nod, breath-out, skid...).
import QtQuick
import QtQuick.Shapes
import Kisel.Core

Item {
    id: root

    property real size: 120
    property string mood: "idle"
    property string skin: ""           // "" or "github"
    property point lookAt: Qt.point(0, 0) // pointer in this item's coordinates
    property bool looking: false
    property int walkDir: 1               // -1 left, 1 right (mood walk)
    property bool celebrating: false      // sparkles and a jump without the mint badge
    property bool doneBadge: false        // keep the mint check badge for 25 s after a task
    property bool eyesShut: false         // first launch: the eyes open with one blink when released
    property real leafScale: 1            // first launch: the leaf grows from a point

    // ---- dragging (motion.md, "Dragging, edges and monitors") ----------------------
    property bool dragging: false         // picked up: no ground shadow, leans and stretches
    property real dragVx: 0               // px per second
    property real dragVy: 0
    property real wallX: 0                // squash across x, 0..0.18 (leaning on / pressing into a wall)
    property real wallY: 0
    Behavior on wallX { NumberAnimation { duration: root.wallX > 0 ? 120 : 380; easing.type: root.wallX > 0 ? Easing.OutCubic : Easing.OutElastic; easing.amplitude: 1.1 } }
    Behavior on wallY { NumberAnimation { duration: root.wallY > 0 ? 120 : 380; easing.type: root.wallY > 0 ? Easing.OutCubic : Easing.OutElastic; easing.amplitude: 1.1 } }
    property bool gazeOn: false           // look toward `gaze` (the screen's centre at a wall)
    property point gaze: Qt.point(0, 0)   // -1..1 on both axes
    property real inwardTilt: 0           // docked on a side: leans 8 degrees toward the screen
    // Lean toward the direction of travel by clamp(vx / 40, -14, 14) degrees, smoothed
    // over 120 ms; when it stops the tilt overshoots and settles (OutElastic, 380 ms).
    readonly property real leanTarget: dragging ? Math.max(-14, Math.min(14, dragVx / 40)) : 0
    property real leanNow: leanTarget
    Behavior on leanNow {
        NumberAnimation {
            duration: root.leanTarget === 0 ? 380 : 120
            easing.type: root.leanTarget === 0 && !Theme.reduced ? Easing.OutElastic : Easing.OutCubic
            easing.amplitude: 1.6; easing.period: 0.45
        }
    }
    // Stretch up to 8 percent along the velocity, squash across it.
    readonly property real stretchAmt: dragging && !Theme.reduced ? Math.min(1, Math.hypot(dragVx, dragVy) / 1000) * 0.08 : 0
    property real stretchNow: stretchAmt
    Behavior on stretchNow { NumberAnimation { duration: 120 } }
    readonly property bool movesSideways: Math.abs(dragVx) >= Math.abs(dragVy)
    readonly property real sx: movesSideways ? 1 + stretchNow : 1 - stretchNow * 0.5
    readonly property real sy: movesSideways ? 1 - stretchNow * 0.5 : 1 + stretchNow
    property real shadowK: dragging ? 0 : 1 // the drop shadow fades back in on landing
    Behavior on shadowK { NumberAnimation { duration: 200 } }
    // press compression (70 ms, as for a click) and the small recoil of a hold that was let go
    function compress() { jumpAnim.stop(); clickAnim.restart() }
    signal clicked()

    width: size
    height: size

    // ---- level of detail ---------------------------------------------------------
    readonly property real detail: Math.max(0, Math.min(1, (size - 44) / 66))

    // ---- mood resolution -------------------------------------------------------
    property bool dizzyOverride: false
    readonly property string m: dizzyOverride ? "dizzy" : mood
    readonly property bool asleep: m === "sleep"

    // the parts of the mood, each following `m` with its own delay
    property string bodyM: "idle"   // tilt, sag, hops
    property string faceM: "idle"   // eyes, mouth, cheeks
    property string badgeM: "none"  // the 20 px status disc
    property string leafM: "idle"   // the leaf
    property string cur: "idle"     // the last mood a transition was started for
    property bool bridging: false

    readonly property string eyeMode: faceM === "happy" ? "arch" : faceM === "sleep" ? "closed" : faceM === "dizzy" ? "spiral" : "open"
    readonly property real eyeH: faceM === "work" ? 0.5 : faceM === "sad" ? 0.82 : (faceM === "alert" || faceM === "wow") ? 1.2 : 1
    readonly property real eyeW: (faceM === "alert" || faceM === "wow") ? 1.2 : 1
    readonly property string mouthKind: ({
        idle: "smile", walk: "smile", think: "flat", sleep: "flat", work: "smirk",
        alert: "smallO", wow: "wideO", happy: "openSmile", sad: "frown", dizzy: "wavy"
    })[faceM]
    readonly property real tiltTarget: bodyM === "think" ? 6 : bodyM === "sad" ? -4 : 0
    readonly property real leafBase: leafM === "sad" ? 20 : leafM === "sleep" ? 32 : leafM === "alert" ? -10 : 0
    readonly property real leafSwing: leafM === "alert" ? 1.7 : 5
    readonly property real sag: bodyM === "sleep" ? 0.05 : bodyM === "sad" ? 0.035 : 0
    readonly property real cheekOp: faceM === "happy" ? 0.7 : 0.35
    property color haloColor: m === "alert" ? Theme.badgeAmber : m === "happy" ? Theme.badgeMint
                                     : (m === "work" || m === "think") ? Theme.badgeInfo : Theme.mascotMid
    Behavior on haloColor { ColorAnimation { duration: 300 } }
    readonly property string badgeKind: badgeM !== "none" ? badgeM : (doneBadge ? "happy" : "none")

    // ---- skins (service widgets) -----------------------------------------------
    property color cTop: skin === "github" ? "#6e7681" : Theme.mascotTop
    property color cMid: skin === "github" ? "#3d444d" : Theme.mascotMid
    property color cBot: skin === "github" ? "#21262d" : Theme.mascotBottom
    property color cLeaf: skin === "github" ? "#e6edf3" : Theme.mascotLeaf
    property color cLeaf2: skin === "github" ? "#b6bec7" : Theme.mascotLeaf2
    Behavior on cTop { ColorAnimation { duration: 350 } }
    Behavior on cMid { ColorAnimation { duration: 350 } }
    Behavior on cBot { ColorAnimation { duration: 350 } }
    Behavior on cLeaf { ColorAnimation { duration: 350 } }

    // ---- animated state --------------------------------------------------------
    property real breath: 0      // 0..1
    property real breathAmp: 1   // 1.5 for one deeper breath after happy
    property real breathExtra: 0 // the 3 % breath-out before a jump
    property real squash: 0      // + squashes, - stretches
    property real jumpY: 0       // px at 128 design units, up is positive
    property real hopY: 0        // work and walk hops
    property real nodY: 0        // the nod after an answer
    property real skidX: 0       // the skid at the end of a walk
    property real shake: 0       // wiggles (shake off, pendulum)
    property real leanExtra: 0   // the lean before a walk
    property real dizzyAmp: m === "dizzy" ? 1 : 0   // spirals, stars and wobble ease out over 400 ms
    Behavior on dizzyAmp { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    property real dizzyDriver: 0 // -1..1
    property real walkDriver: 0  // -1..1
    property real walkAmp: bodyM === "walk" ? 1 : 0
    Behavior on walkAmp { NumberAnimation { duration: 200 } }
    property real walkWarm: 0.7  // the first hop of a walk is smaller
    property real tilt: tiltTarget
    Behavior on tilt { NumberAnimation { duration: bodyM === "work" ? 180 : 300; easing.type: Easing.OutCubic } }
    property real sagNow: sag
    Behavior on sagNow { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    property real leafBaseNow: leafBase
    Behavior on leafBaseNow {
        NumberAnimation {
            duration: root.leafM === "idle" ? 300 : 450
            easing.type: root.leafM === "idle" ? Easing.OutBack : Easing.OutCubic // rises with a small overshoot
        }
    }
    property real leafWave: 0    // -1..1
    property real cheekDur: 200
    property real sparkleHold: 0 // sparkles finish their own life after happy

    SequentialAnimation on breath {
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: root.asleep ? 2200 : 1600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: root.asleep ? 2200 : 1600; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on leafWave {
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { to: -1; duration: 1300; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on dizzyDriver {
        running: root.dizzyAmp > 0.01 && !Theme.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 115; easing.type: Easing.InOutSine }
        NumberAnimation { to: -1; duration: 115; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on walkDriver {
        running: root.walkAmp > 0.01 && !Theme.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 130; easing.type: Easing.InOutSine }
        NumberAnimation { to: -1; duration: 130; easing.type: Easing.InOutSine }
    }
    // dizzy spirals and orbiting shapes decelerate smoothly: angles are integrated
    // frame by frame from a speed that follows dizzyAmp
    property real spin: 0
    property real orbit: 0
    FrameAnimation {
        running: root.dizzyAmp > 0.01 && !Theme.reduced
        onTriggered: {
            root.spin += frameTime * 360 / 0.7 * root.dizzyAmp
            root.orbit += frameTime * 360 / 1.1 * root.dizzyAmp
        }
    }

    // ---- blink -----------------------------------------------------------------
    property real blink: 1
    readonly property real blinkEff: eyesShut ? 0.08 : blink
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: root; property: "blink"; to: 0.08; duration: 70 }
        NumberAnimation { target: root; property: "blink"; to: 1; duration: 110 }
    }
    SequentialAnimation { // two slow blinks after dizzy
        id: slowBlinks
        NumberAnimation { target: root; property: "blink"; to: 0.08; duration: 160 }
        NumberAnimation { target: root; property: "blink"; to: 1; duration: 220 }
        PauseAnimation { duration: 120 }
        NumberAnimation { target: root; property: "blink"; to: 0.08; duration: 160 }
        NumberAnimation { target: root; property: "blink"; to: 1; duration: 220 }
    }
    Timer {
        id: blinkTimer
        interval: 2500
        running: !root.asleep
        repeat: true
        onTriggered: {
            interval = 2200 + Math.random() * 3800
            if (!root.bridging) blinkAnim.restart() // a blink never starts inside a mood bridge
        }
    }
    function blinkNow() { blinkAnim.restart() }

    // ---- eyes follow the pointer, with a spring --------------------------------
    readonly property real wantX: gazeOn ? gaze.x * 5 : faceM === "walk" ? 5 * walkDir : faceM === "think" ? 3 : looking ? Math.max(-1, Math.min(1, (lookAt.x - width / 2) / 60)) * 5 : 0
    readonly property real wantY: gazeOn ? gaze.y * 4 : faceM === "think" ? -3 : looking ? Math.max(-1, Math.min(1, (lookAt.y - height / 2) / 60)) * 4 : 0
    property real eyeX: wantX
    property real eyeY: wantY
    // whenever the gaze target changes the pupils move with a spring, never snap
    Behavior on eyeX { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.05 } }
    Behavior on eyeY { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.05 } }

    // ---- one-shot moves --------------------------------------------------------
    function jump(power, force) {
        if (Theme.reduced) return
        // settle gate: a one-shot that arrives while another is still landing waits
        // for it, except an alert, which cuts in
        if (!force && jumpAnim.running) return
        clickAnim.stop()
        jumpAnim.p = power
        jumpAnim.restart()
    }
    SequentialAnimation {
        id: jumpAnim
        property real p: 1
        NumberAnimation { target: root; property: "squash"; to: 0.8; duration: 90 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "squash"; to: -0.5; duration: 190; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "jumpY"; to: 24 * jumpAnim.p; duration: 190; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "squash"; to: 0; duration: 170 }
            NumberAnimation { target: root; property: "jumpY"; to: 0; duration: 170; easing.type: Easing.InQuad }
        }
        NumberAnimation { target: root; property: "squash"; to: 0.8; duration: 60 }
        NumberAnimation { target: root; property: "squash"; to: 0; duration: 380; easing.type: Easing.OutElastic; easing.amplitude: 1.1; easing.period: 0.45 }
    }
    SequentialAnimation {
        id: clickAnim
        NumberAnimation { target: root; property: "squash"; to: 0.73; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "squash"; to: 0; duration: 520; easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.4 }
    }
    // a landing after being carried: a 70 ms squash and an elastic settle, no sound
    function land() { jumpAnim.stop(); clickAnim.restart() }

    // work: hops 5 px every 560 ms (150 up, 150 down, 260 rest); 3 px-ish at the mini size
    readonly property real hopK: 1 + 0.75 * (1 - detail)
    SequentialAnimation {
        running: root.bodyM === "work" && !Theme.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.hopY = 0
        NumberAnimation { target: root; property: "hopY"; to: 5 * root.hopK; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hopY"; to: 0; duration: 150; easing.type: Easing.InQuad }
        PauseAnimation { duration: 260 }
    }
    // alert: a bigger hop now and then while the request waits
    Timer {
        interval: 2200
        repeat: true
        running: root.bodyM === "alert"
        onTriggered: root.jump(0.45)
    }
    // walk: hops of 7 px every 260 ms (the first one 70 % of that), tilting 5 degrees
    SequentialAnimation {
        running: root.bodyM === "walk" && !Theme.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.hopY = 0
        NumberAnimation { target: root; property: "hopY"; to: 7 * root.walkWarm; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hopY"; to: 0; duration: 90; easing.type: Easing.InQuad }
        PauseAnimation { duration: 80 }
    }
    Timer { id: warmTimer; interval: 300; onTriggered: root.walkWarm = 1 }

    // a jump with sparkles, for moments that are happy without being "done"
    function celebrate(power) {
        jump(power)
        celebrating = true
        celebrateTimer.restart()
    }
    Timer { id: celebrateTimer; interval: 1500; onTriggered: root.celebrating = false }
    Timer { id: sparkleHoldTimer; interval: 1100; onTriggered: root.sparkleHold = 0 }

    // ---- bridges: pre-actions ---------------------------------------------------
    SequentialAnimation {
        id: startleAnim // a 70 ms squash to 0.9, then the 17 px jump (started by bodyM)
        NumberAnimation { target: root; property: "squash"; to: 0.9; duration: 70 }
    }
    SequentialAnimation {
        id: nodAnim
        property real px: 4
        property int downMs: 110
        property int upMs: 110
        NumberAnimation { target: root; property: "nodY"; to: -nodAnim.px; duration: nodAnim.downMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "nodY"; to: 0; duration: nodAnim.upMs; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: breathOutAnim // body 3 % taller, then back, 120 ms
        NumberAnimation { target: root; property: "breathExtra"; to: 0.03; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "breathExtra"; to: 0; duration: 60; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: shakeOffAnim // two 8 degree wiggles, 140 ms each
        NumberAnimation { target: root; property: "shake"; to: 8; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "shake"; to: -8; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "shake"; to: 8; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "shake"; to: 0; duration: 70; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: pendulumAnim // carried off the ground mid-walk: the body hangs and sways, damped over 600 ms
        NumberAnimation { target: root; property: "shake"; to: 6; duration: 100; easing.type: Easing.OutSine }
        NumberAnimation { target: root; property: "shake"; to: -4.5; duration: 150; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "shake"; to: 3; duration: 150; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "shake"; to: -1.5; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "shake"; to: 0; duration: 80; easing.type: Easing.InOutSine }
    }
    function hang() { if (!Theme.reduced) pendulumAnim.restart() }
    SequentialAnimation {
        id: leanAnim // a 120 ms lean toward the walking direction before the first hop
        NumberAnimation { target: root; property: "leanExtra"; to: 4 * root.walkDir; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "leanExtra"; to: 0; duration: 200; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: skidAnim // the last hop lands, the body skids 6 px in the old direction and eases back
        NumberAnimation { target: root; property: "skidX"; to: 6 * root.walkDir; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "skidX"; to: 0; duration: 240; easing.type: Easing.OutQuad }
    }

    // ---- bridges: the plan for each pair of moods --------------------------------
    // Returns {delays per part (ms), pre-action name}. Delays count from the start of
    // the bridge. With "reduce motion" only the order of events (body, face, badge)
    // is kept, as short cross-fades.
    function plan(from, to) {
        const p = { body: 0, face: 0, badge: 0, leaf: 0, pre: "" }
        if (Theme.reduced) { p.face = 60; p.badge = 120; p.leaf = 60; return p }
        if (to === "alert") { p.pre = "startle"; p.body = 70; return p } // cuts whatever was running
        let base = 0
        if (from === "sleep") base = 140 // eyes open with one blink first
        if (from === "alert" && to === "work") {
            p.pre = "nodSmall"; p.body = 220; p.badge = 120; p.leaf = 0
        } else if (from === "alert" && to === "sad") {
            p.pre = "nodBig"; p.body = p.face = p.badge = p.leaf = 880
        } else if (to === "think" && from === "work") {
            base += root.hopY > 0.3 ? 200 : 0 // the next hop finishes its landing
        } else if (to === "think") {
            p.body = 160; p.badge = 160 // eyes flick up first, then the lean and the badge
        } else if (to === "happy") {
            base += (from === "work" && root.hopY > 0.3 ? 200 : 0) + (from === "work" || from === "think" ? 200 : 0)
            p.pre = (from === "work" || from === "think") ? "breathOut" : ""
        } else if (to === "sad") {
            p.face = 270; p.badge = 270; p.leaf = 470 // the face reacts after the body
        } else if (from === "happy") {
            p.pre = "deepBreath"
        } else if (from === "sad") {
            p.pre = "shakeOff"
        } else if (from === "dizzy") {
            p.pre = "dizzyDown"; p.face = 400; p.leaf = 200
        } else if (to === "sleep") {
            p.body = 160; p.leaf = 160 // the eyes close first
        } else if (to === "walk") {
            p.pre = "lean"; p.body = 120
        } else if (from === "walk") {
            // the last hop lands, the body skids, and the new mood begins at the skid's end
            p.pre = "skid"; p.body = p.face = p.badge = p.leaf = 240
        }
        p.body += base; p.face += base; p.badge += base; p.leaf += base
        return p
    }

    function applyPart(part, value, delay) {
        const t = ({ body: bodyT, face: faceT, badge: badgeT, leaf: leafT })[part]
        t.stop()
        if (delay <= 0) {
            if (part === "body") bodyM = value
            else if (part === "face") faceM = value
            else if (part === "badge") badgeM = ({ think: "think", work: "work", alert: "alert", happy: "happy", sad: "sad" })[value] || "none"
            else leafM = value
        } else {
            t.value = value
            t.interval = delay
            t.start()
        }
    }
    Timer { id: bodyT; property string value; onTriggered: root.bodyM = value }
    Timer { id: faceT; property string value; onTriggered: root.faceM = value }
    Timer { id: badgeT; property string value; onTriggered: root.badgeM = ({ think: "think", work: "work", alert: "alert", happy: "happy", sad: "sad" })[value] || "none" }
    Timer { id: leafT; property string value; onTriggered: root.leafM = value }
    Timer { id: bridgeEnd; onTriggered: root.bridging = false }

    function transition(from, to) {
        const p = plan(from, to)
        cur = to
        // pre-actions
        if (p.pre === "startle") {
            jumpAnim.stop(); clickAnim.stop(); hopY = 0
            startleAnim.restart()
        } else if (p.pre === "nodSmall") { nodAnim.px = 4; nodAnim.downMs = 110; nodAnim.upMs = 110; nodAnim.restart() }
        else if (p.pre === "nodBig") { nodAnim.px = 10; nodAnim.downMs = 360; nodAnim.upMs = 520; nodAnim.restart() }
        else if (p.pre === "breathOut") breathOutAnim.restart()
        else if (p.pre === "deepBreath") { breathAmp = 1.5; deepBreathTimer.restart(); cheekDur = 400; sparkleHold = 1; sparkleHoldTimer.restart() }
        else if (p.pre === "shakeOff") shakeOffAnim.restart()
        else if (p.pre === "dizzyDown") slowBlinks.restart()
        else if (p.pre === "lean") { walkWarm = 0.7; warmTimer.restart(); leanAnim.restart() }
        else if (p.pre === "skid") skidAnim.restart()

        if (from === "sleep" && to !== "alert") { faceM = "idle"; blinkAnim.restart() } // wake: eyes open first
        bridging = true
        bridgeEnd.interval = Math.max(p.body, p.face, p.badge, p.leaf) + 200
        bridgeEnd.restart()

        // the badge only changes colour family through a quick out and in (StatusBadge)
        applyPart("body", to, p.body)
        applyPart("face", to, p.face)
        applyPart("badge", to, p.badge)
        applyPart("leaf", to, p.leaf)
    }
    Timer { id: deepBreathTimer; interval: 3200; onTriggered: root.breathAmp = 1 }
    onMChanged: transition(cur, m)
    Component.onCompleted: { cur = m; bodyM = m; faceM = m; leafM = m; badgeM = ({ think: "think", work: "work", alert: "alert", happy: "happy", sad: "sad" })[m] || "none" }

    // jumps happen when the body arrives in the mood (after its bridge)
    onBodyMChanged: {
        if (bodyM === "happy") jump(1.0)
        else if (bodyM === "alert") jump(0.7, true)
        else if (bodyM === "wow") jump(0.35)
        if (bodyM !== "happy" && faceM !== "happy") cheekDur = 200
    }

    // ---- click and the dizzy egg -----------------------------------------------
    property var clickTimes: []
    Timer { id: dizzyTimer; interval: 3000; onTriggered: root.dizzyOverride = false }
    function poke() {
        const now = Date.now()
        clickTimes = clickTimes.filter(t => now - t < 2000).concat([now])
        if (clickTimes.length >= 5) {
            clickTimes = []
            dizzyOverride = true
            dizzyTimer.restart()
            Sfx.play("dizzy")
        } else {
            jumpAnim.stop()
            clickAnim.restart()
            Sfx.play("click")
        }
        root.clicked()
    }

    // ---- drawing, in the 128 x 128 logo space ----------------------------------
    // Small helper: a stroked or filled SVG path in the stage's coordinates.
    component Mark: Shape {
        id: mark
        property string d: ""
        property bool on: true
        property bool fill: false
        property color ink: Theme.mascotEye
        property real w: 3
        anchors.fill: parent
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } } // mouths cross-fade in 120 ms
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: mark.fill ? "transparent" : mark.ink
            strokeWidth: mark.w
            fillColor: mark.fill ? mark.ink : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: mark.d }
        }
    }

    Item {
        id: stage
        width: 128
        height: 128
        scale: root.size / 128
        transformOrigin: Item.TopLeft

        // halo: a soft glow, colour crossfades with the mood; gone at the mini size
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: (root.asleep ? 0.15 : 0.3) * root.detail
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: 300 } }
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: 64; centerY: 74; centerRadius: 62
                    focalX: 64; focalY: 74
                    GradientStop { position: 0; color: root.haloColor }
                    GradientStop { position: 1; color: Qt.rgba(root.haloColor.r, root.haloColor.g, root.haloColor.b, 0) }
                }
                PathSvg { path: "M2 74a62 62 0 1 0 124 0a62 62 0 1 0 -124 0z" }
            }
        }

        // ground shadow narrows and lightens with height; 25 % x detail
        Rectangle {
            readonly property real h: root.jumpY + root.hopY
            x: 26 + h * 0.4; y: 113; width: 76 - h * 0.8; height: 10; radius: 5
            color: "black"
            opacity: Math.max(0, 0.25 - h * 0.004) * root.detail * root.shadowK
        }

        Item {
            id: body
            width: 128
            height: 128
            transform: [
                Translate { x: root.skidX; y: -(root.jumpY + root.hopY) + root.nodY * -1 },
                Scale {
                    origin.x: 64; origin.y: 118
                    xScale: (1 - 0.02 * root.breath * root.breathAmp) * (1 + 0.16 * root.squash) * (1 - root.wallX) * root.sx
                    yScale: (1 + 0.035 * root.breath * root.breathAmp + root.breathExtra) * (1 - root.sagNow) * (1 - 0.22 * root.squash) * (1 - root.wallY) * root.sy
                },
                Rotation {
                    origin.x: 64; origin.y: 118
                    angle: root.tilt + root.shake + root.leanExtra + root.leanNow + root.inwardTilt + 10 * root.dizzyAmp * root.dizzyDriver + 5 * root.walkAmp * root.walkDriver
                }
            ]

            // outline ring, 4.5 px of surface-0 around the whole silhouette (fades out with detail)
            Shape {
                anchors.fill: parent
                opacity: 1 - root.detail
                visible: opacity > 0.005
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.surface0
                    strokeWidth: 9
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M64 24c27 0 42 22 45 48 2 22 8 40-9 46-15 5-57 5-72 0-17-6-11-24-9-46 3-26 18-48 45-48z" }
                }
            }
            // body: flat kisel at the mini size, the gradient fades in over it with detail
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.cMid
                    PathSvg { path: "M64 24c27 0 42 22 45 48 2 22 8 40-9 46-15 5-57 5-72 0-17-6-11-24-9-46 3-26 18-48 45-48z" }
                }
            }
            Shape {
                anchors.fill: parent
                opacity: root.detail
                visible: opacity > 0.005
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: 0; y1: 24; x2: 0; y2: 122
                        GradientStop { position: 0; color: root.cTop }
                        GradientStop { position: 0.48; color: root.cMid }
                        GradientStop { position: 1; color: root.cBot }
                    }
                    PathSvg { path: "M64 24c27 0 42 22 45 48 2 22 8 40-9 46-15 5-57 5-72 0-17-6-11-24-9-46 3-26 18-48 45-48z" }
                }
            }
            // gloss: one flat white ellipse at the mini size, the mark's gloss at full detail
            Rectangle {
                readonly property real gw: 22 + 4 * root.detail
                readonly property real gh: 12 + 2 * root.detail
                x: 44 + root.detail - gw / 2; y: 46 - gh / 2; width: gw; height: gh; radius: gh / 2
                color: "white"; opacity: 0.44; rotation: -32
            }
            Rectangle { x: 33; y: 61; width: 6; height: 6; radius: 3; color: "white"; opacity: 0.35 * root.detail }
            // cheeks (none at the mini size)
            Rectangle { x: 29; y: 81; width: 18; height: 10; radius: 5; color: "#ff4f74"; opacity: root.cheekOp * root.detail; Behavior on opacity { NumberAnimation { duration: root.cheekDur } } }
            Rectangle { x: 81; y: 81; width: 18; height: 10; radius: 5; color: "#ff4f74"; opacity: root.cheekOp * root.detail; Behavior on opacity { NumberAnimation { duration: root.cheekDur } } }

            // eyes: 16 x 20 plain at the mini size, 13 x 17 with a highlight at full detail
            Repeater {
                model: [46, 82]
                Item {
                    id: eye
                    required property int modelData
                    x: modelData + root.eyeX
                    y: 76 + 2 * root.detail + root.eyeY
                    width: 0; height: 0
                    Shape {
                        opacity: root.eyeMode === "open" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Theme.mascotEye
                            strokeColor: "transparent"
                            PathAngleArc {
                                radiusX: (8 - 1.5 * root.detail) * root.eyeW
                                radiusY: Math.max(0.5, (10 - 1.5 * root.detail) * root.eyeH * root.blinkEff)
                                startAngle: 0; sweepAngle: 360
                            }
                        }
                        Rectangle { // catch-light, fading in with detail
                            x: 2.5; y: -4.5; width: 4.6; height: 4.6; radius: 2.3; color: "white"
                            opacity: root.blinkEff > 0.5 ? root.detail : 0
                        }
                    }
                }
            }
            // happy "^ ^", sleep closed, dizzy spirals (drawn in body space)
            Mark { d: "M37 82q9-14 18 0M73 82q9-14 18 0"; on: root.eyeMode === "arch"; w: 5 - 1.8 * root.detail }
            Mark { d: "M37 78q9 9 18 0M73 78q9 9 18 0"; on: root.eyeMode === "closed"; w: 4.5 - 1.8 * root.detail }
            Repeater {
                model: [46, 82]
                Shape {
                    id: spiral
                    required property int modelData
                    x: modelData; y: 78; width: 0; height: 0
                    opacity: root.eyeMode === "spiral" ? 1 : 0
                    rotation: root.spin
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.mascotEye; strokeWidth: 2.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathSvg { path: "M0 0a1.6 1.6 0 1 1 3.2 0a3.2 3.2 0 1 1 -6.4 0a4.8 4.8 0 1 1 9.6 0" }
                    }
                }
            }

            // mouths: a 4.5 px stroke at the mini size, 3 px at full detail
            Mark { d: "M57 93q7 6 14 0"; on: root.mouthKind === "smile"; w: 4.5 - 1.5 * root.detail }
            Mark { d: "M58 94h12"; on: root.mouthKind === "flat"; w: 4.5 - 1.5 * root.detail }
            Mark { d: "M57 94q8 4 14 -2"; on: root.mouthKind === "smirk"; w: 4.5 - 1.5 * root.detail }
            Mark { d: "M60.5 95a3.5 4.5 0 1 0 7 0a3.5 4.5 0 1 0 -7 0z"; on: root.mouthKind === "smallO"; fill: true }
            Mark { d: "M59 94a5 7 0 1 0 10 0a5 7 0 1 0 -10 0z"; on: root.mouthKind === "wideO"; fill: true }
            Mark { d: "M54 89q10 15 20 0z"; on: root.mouthKind === "openSmile"; fill: true }
            Mark { d: "M57 97q7 -6 14 0"; on: root.mouthKind === "frown"; w: 4.5 - 1.5 * root.detail }
            Mark { d: "M54 94q3 -4 6 0t6 0t6 0"; on: root.mouthKind === "wavy"; w: 3.4 - 0.8 * root.detail }

            // leaf: rotates about its stem, droops when sad or asleep; the outline includes it
            Item {
                width: 128; height: 128
                transform: [
                    Scale { origin.x: 64; origin.y: 26; xScale: root.leafScale; yScale: root.leafScale },
                    Rotation {
                        origin.x: 64; origin.y: 26
                        angle: root.leafBaseNow + root.leafWave * root.leafSwing
                    }
                ]
                Shape {
                    anchors.fill: parent
                    opacity: 1 - root.detail
                    visible: opacity > 0.005
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.surface0; strokeWidth: 5; fillColor: Theme.surface0
                        joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                        PathSvg { path: "M64 26c0-6 1-11 5-15M69 11c8-12 22-8 22 3-9 3-19 1-22-3z" }
                    }
                }
                Mark { d: "M64 26c0-6 1-11 5-15"; w: 4 - 0.5 * root.detail; ink: root.cLeaf }
                Mark { d: "M69 11c8-12 22-8 22 3-9 3-19 1-22-3z"; fill: true; ink: root.cLeaf }
                Mark { d: "M63 17c-7-11-20-8-19 2 8 3 17 2 19-2z"; fill: true; ink: root.cLeaf2; on: root.detail > 0.4 }
            }
        }

        // sparkles (happy): five four-point stars, alternating soft and mint
        Repeater {
            model: [[18, 30, 6], [108, 36, 5], [10, 68, 4], [116, 72, 5], [96, 10, 7]]
            Shape {
                id: spark
                required property var modelData
                required property int index
                property real s: 0
                x: modelData[0]; y: modelData[1]
                scale: s * modelData[2] / 4
                rotation: -30 + 70 * s
                opacity: Math.min(1, s * 2)
                visible: s > 0.01
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.skin === "github" ? "#ffffff" : (spark.index % 2 ? Theme.mascotLeaf : Theme.mascotTop)
                    PathSvg { path: "M0 -4Q0 0 4 0Q0 0 0 4Q0 0 -4 0Q0 0 0 -4z" }
                }
                SequentialAnimation on s {
                    // sparkles finish their own life: they are not cut when the mood ends
                    running: (root.bodyM === "happy" || root.celebrating || root.sparkleHold > 0) && !Theme.reduced
                    loops: Animation.Infinite
                    PauseAnimation { duration: spark.index * 140 }
                    NumberAnimation { to: 1.15; duration: 220; easing.type: Easing.OutBack }
                    NumberAnimation { to: 0; duration: 380; easing.type: Easing.InQuad }
                    PauseAnimation { duration: 400 }
                    onRunningChanged: if (!running) spark.s = 0
                }
            }
        }

        // sleep: three "z" drifting up and to the right
        Repeater {
            model: 3
            Text {
                id: z
                required property int index
                text: "z"
                color: Theme.mascotTop
                font.family: Theme.display
                font.weight: Font.Bold
                font.pixelSize: 10 + 8 * t
                property real t: 0
                x: 96 + 14 * t
                y: 30 - 34 * t
                opacity: root.asleep ? Math.sin(Math.PI * t) : 0
                SequentialAnimation on t {
                    running: root.asleep && !Theme.reduced
                    loops: Animation.Infinite
                    PauseAnimation { duration: z.index * 400 }
                    NumberAnimation { from: 0; to: 1; duration: 1200 }
                }
            }
        }

        // dizzy: three brand shapes orbiting the head once per 1100 ms; they slow and fade out
        Item {
            x: 64; y: 30; width: 0; height: 0
            visible: root.dizzyAmp > 0.01
            opacity: root.dizzyAmp
            rotation: root.orbit
            Rectangle { x: 34; y: -3; width: 7; height: 7; radius: 3.5; color: Theme.mascotTop }                 // soft disc
            BrandShape { x: -42; y: -3; kind: "halfRound"; scale: 14 / 200; transformOrigin: Item.TopLeft } // amber half-round
            Rectangle { x: -2; y: -30; width: 10; height: 5; radius: 2.5; color: Theme.badgeMint }                // small pill
        }

        // the status disc is the pill's chip at the mini size: it fades in with detail
        Item {
            x: 6; y: 12; width: 20; height: 20
            opacity: root.detail
            visible: opacity > 0.01
            StatusBadge { kind: root.badgeKind }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onClicked: root.poke()
    }
}
