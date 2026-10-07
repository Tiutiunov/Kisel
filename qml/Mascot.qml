// The mascots: five singers drawn by one engine after coucou's Mochi. Its flattened
// superellipse in plain cream white, which takes the mood's colour from below; two ink
// pills for eyes; and on it what makes each of them herself: her fringe, the hair that
// hangs on springs, what she wears on her head, and a headset whose light takes the
// mood's colour. Drawn in code on one Canvas; nothing here is a bitmap.
//
//   miku  twin tails; bright and earnest. Hums to herself, sulks when slapped.
//   rin   a big white bow; loud and restless. Bounces, loses her temper when slapped.
//   luka  long hair; calm and grown-up. Moves slowly, is merely unimpressed by a slap.
//   zunda Zundamon: an edamame pod at each ear; a cheeky sprite, proud of herself and
//         quick to panic when slapped.
//   teto  twin drills; smug, and flustered the moment anyone is nice to her.
//
// Every number of the drawing is in `mk` (`mkBase`, then what differs for each in
// `mks`). design/miku-editor.html is the same drawing in a browser with a slider for
// each number; what it copies out goes into `mkBase` and `mks`.
//
// `character` picks one. They share every mood and differ in looks (`chars`), in how
// fast and how high they move, and in the emotes of their own: the quirk each falls into
// when idle, what a slap does, what resting the pointer on them does, and the favourite
// thing that flies about when a task is done (leek, orange, tuna, zunda mochi, baguette).
//
// The interface is the one the island was built around: `size` is the box she is laid
// out in. At the bar's size her hair is short and she is clipped to the bar's thickness
// (nothing reaches out of the bar); as the card opens the clip relaxes, the hair grows
// to its length and the hands come out
//   detail = clamp((size - 44) / 66, 0, 1)
//
// Moods: idle think work alert wow happy sad sleep dizzy walk. The Island (via the Hub)
// decides the mood; on top of it come the short emotes.
import QtQuick
import Kisel.Core

Item {
    id: root

    property string character: "miku"
    property real size: 120
    property string mood: "idle"
    property string skin: ""           // "" or "github"
    property point lookAt: Qt.point(0, 0) // pointer in this item's coordinates
    property bool looking: false          // follow `lookAt` with the eyes
    property bool hovered: false          // the pointer is on the island: bigger eyes, a blush, an emote if it rests
    property int walkDir: 1               // -1 left, 1 right (mood walk)
    property bool celebrating: false      // sparkles and a jump without the mint badge
    property bool doneBadge: false        // keep the mint badge for 25 s after a task
    property bool eyesShut: false         // first launch: the eyes open with one blink when released
    property real leafScale: 1            // first launch: the hair grows from its roots
    property bool paused: false           // out of sight: nothing is simulated or painted
    property bool music: false            // a tune is playing: idle, she hums along
    property bool bench: false            // waiting her turn in a seat: small, cheap, but alive (see the bench timer)
    property bool instant: false          // a change of character is not played out here: whoever holds her does that
    property bool still: false            // a portrait: painted once, never animated (the bar's small ones)

    // ---- dragging (motion.md, "Dragging, edges and monitors") ----------------------
    property bool dragging: false         // picked up: no ground shadow, leans, the hair trails
    property real dragVx: 0               // px per second
    property real dragVy: 0
    property real wallX: 0                // squash across x, 0..0.18 (leaning on / pressing into a wall)
    property real wallY: 0
    Behavior on wallX { NumberAnimation { duration: root.wallX > 0 ? 120 : 380; easing.type: root.wallX > 0 ? Easing.OutCubic : Easing.OutElastic; easing.amplitude: 1.1 } }
    Behavior on wallY { NumberAnimation { duration: root.wallY > 0 ? 120 : 380; easing.type: root.wallY > 0 ? Easing.OutCubic : Easing.OutElastic; easing.amplitude: 1.1 } }
    property bool gazeOn: false           // look toward `gaze` (the screen's centre at a wall)
    property point gaze: Qt.point(0, 0)   // -1..1 on both axes
    property real inwardTilt: 0           // docked on a side: leans 8 degrees toward the screen
    signal clicked()

    width: size
    height: size

    readonly property real detail: Math.max(0, Math.min(1, (size - 44) / 66))

    // ---- who they are ----------------------------------------------------------------
    // eye: the iris from top to bottom. set / tip: the headset and its mic's tip.
    // energy: how fast she moves. bounce: how high. calm: lowered lids.
    readonly property var chars: ({
        miku: { name: "Miku", style: "twintails", energy: 1, bounce: 1, mouth: "smile", fav: "leek", slap: "annoyed", rest: "love", quirk: "hum" },
        rin:  { name: "Rin", style: "bow", energy: 1.3, bounce: 1.4, mouth: "grin", fav: "orange", slap: "angry", rest: "love", quirk: "hype" },
        luka: { name: "Luka", style: "long", energy: 0.7, bounce: 0.5, mouth: "soft", calm: true, fav: "tuna", slap: "unimpressed", rest: "fond", quirk: "cool" },
        zunda: { name: "Zundamon", style: "pods", energy: 1.2, bounce: 1.3, mouth: "smile", fav: "zunda", slap: "flustered", rest: "love", quirk: "proud" },
        teto: { name: "Teto", style: "drills", energy: 1, bounce: 0.9, mouth: "smug", fav: "bread", slap: "tsun", rest: "flustered", quirk: "smug" }
    })
    // The drawing's numbers, in body radii (names as in design/miku-editor.html): Miku's,
    // and under them what the others have of their own.
    readonly property var mkBase: ({
        rx: 1.14, ry: 0.88, exp: 3.4, bodyTop: "#FFFAF5", bodyBot: "#DDCCBF", shade: 0.2, hl: 0.55, tint: 0.62,
        ex: 0.32, ey: 0.14, ew: 0.12, eh: 0.19, ink: "#1A1412", gazeX: 0.24, gazeY: 0.15,
        cx: 0.66, cy: 0.42, cw: 0.16, ch: 0.095, cheek: "#FF7896", cheekA: 0.5,
        mouthY: 0.5, mouthRest: 0,
        hairOn: 1, hair: "#39C5BB", hairD: "#22968E", hairTop: "#55DACF", fringeY: -0.14, bangTip: -0.06, bangNotch: -0.4,
        backW: 1.07, backH: 1.04, backUp: 0.08, lock: 0.4, shine: 0.4,
        tx: 0.9, ty: -0.6, seg: 0.36, out: 5, tw: 1, tieOn: 1, tie: "#1B1F25", tieBand: "#E12885",
        setOn: 1, set: "#1B1F25", tip: "#E12885", accY: 0,
        hand: 0.17
    })
    readonly property var mks: ({
        miku: {},
        rin:  { hair: "#FFD24A", hairD: "#E0A92E", hairTop: "#FFE585", lock: 0.26, set: "#F4F6F8", tip: "#F2B705" },
        luka: { hair: "#F5A3C0", hairD: "#D9779D", hairTop: "#FFC6DA", tx: 0.92, ty: -0.2, seg: 0.38, out: 2, set: "#E3B341", tip: "#3FA7D6" },
        zunda: { hair: "#B9DC6B", hairD: "#86B93F", hairTop: "#D8EE9C", lock: 0.5, tx: 1.24, ty: -0.28, seg: 0.3, out: 16, tw: 1.15, set: "#F4F6F8", tip: "#86B93F" },
        teto: { hair: "#E0405A", hairD: "#B02A44", hairTop: "#F26A82", tx: 1.06, ty: -0.45, seg: 0.25, out: 22, tip: "#E0405A" }
    })
    readonly property var mk: Object.assign({}, mkBase, mks[shown] || {})
    // Who is drawn. It follows `character` through the change of places below, so the
    // one leaving is still herself while she goes.
    property string shown: "miku"
    readonly property var who: chars[shown] || chars.miku
    readonly property string displayName: who.name
    readonly property string hair: skin === "github" ? "#8b949e" : mk.hair
    readonly property string hairD: skin === "github" ? "#57606a" : mk.hairD
    readonly property string hairTop: skin === "github" ? "#b1bac4" : mk.hairTop

    // The hair that hangs on springs: where it is rooted (in body radii), how many links,
    // how long each, how wide along its length, and how far it is pushed outward.
    readonly property var hairs: ({
        twintails: { x: 1.0,  y: -0.74, n: 6, seg: 0.36, out: 5,  w: [0.2, 0.33, 0.36, 0.32, 0.22, 0.05] },
        long:      { x: 0.9,  y: -0.2,  n: 6, seg: 0.38, out: 2,  w: [0.3, 0.36, 0.38, 0.36, 0.3, 0.14] },
        drills:    { x: 1.06, y: -0.5,  n: 5, seg: 0.25, out: 22, w: [0.26, 0.3, 0.26, 0.2, 0.1], coil: true },
        pods:      { x: 1.02, y: -0.3,  n: 4, seg: 0.24, out: 9,  w: [0.17, 0.22, 0.2, 0.13], pod: true },
        bow: null
    })

    // (where the hair is rooted, how long, how spread and how wide it is comes from `mk`)
    function hairOf(style) {
        const H = hairs[style]
        if (!H) return H
        return { x: mk.tx, y: mk.ty, n: H.n, seg: mk.seg, out: mk.out, w: H.w.map(v => v * mk.tw), coil: H.coil, pod: H.pod }
    }

    // ---- mood, and the emote on top of it ----------------------------------------
    property bool dizzyOverride: false
    readonly property string m: dizzyOverride ? "dizzy" : mood
    property string emote: ""
    Timer { id: emoteTimer; onTriggered: root.emote = "" }
    function play(name, ms) {
        emote = name; emoteTimer.interval = ms; emoteTimer.restart()
        if (name !== "hello" && name !== "unimpressed" && name !== "cool") st.sqv -= 2.5
    }

    onMChanged: {
        emote = ""
        if (m === "happy") roll(1, 950)
        else if (m === "dizzy") roll(2, 1300)
        else if (m === "sad") st.shake = 1
        else if (m === "alert" || m === "wow") jump(0.6, true)
        st.sqv -= 3
    }
    onDraggingChanged: if (dragging) play("surprised", 900)
    onEyesShutChanged: if (!eyesShut) blinkNow()
    // Changing places. The one on stage spins away and shrinks to nothing (280 ms); the
    // new one springs up in her place with a ring of sparks in her own colour, and waves
    // if the card is open. Portraits, and "reduce motion", simply change.
    property real swap: 1 // 1 = there, 0 = gone
    onCharacterChanged: {
        if (still || Theme.reduced || instant) { shown = character; arrive(); return }
        swapAnim.restart()
    }
    function arrive() {
        st.tails = null; st.parts = []; emote = ""
        if (still) { settle(); return }
        if (Theme.reduced) return
        st.sqv -= 6
        const R = cR
        for (let i = 0; i < 12; i++) {
            const a = i / 12 * 2 * Math.PI
            st.parts.push({ type: "spark", life: 0, rot: a, x: cX + Math.cos(a) * R * 0.9, y: cY + Math.sin(a) * R * 0.9,
                            vx: Math.cos(a) * R * 2.2, vy: Math.sin(a) * R * 2.2, max: 0.55, size: R * 0.16, hue: i % 2 ? hair : "#FFFFFF" })
        }
        if (detail > 0.9) { wavedAt = Date.now(); play("hello", 1900) }
    }
    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: root; property: "swap"; to: 0; duration: 280; easing.type: Easing.InBack; easing.overshoot: 1.6 }
        ScriptAction { script: { root.shown = root.character; root.arrive() } }
        NumberAnimation { target: root; property: "swap"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }
    Component.onCompleted: { swapAnim.stop(); swap = 1; shown = character; st.tails = null; if (still) settle() }
    function settle() { for (let i = 0; i < 40; i++) step(0.016); canvas.requestPaint() }

    // a wave when the card first opens, and not again for a minute
    property double wavedAt: 0
    onDetailChanged: if (detail > 0.9 && m === "idle" && emote === "" && Date.now() - wavedAt > 60000) { wavedAt = Date.now(); play("hello", 1900) }

    // the pointer resting on her for two seconds: each takes it her own way
    onLookAtChanged: stillTimer.restart()
    Timer {
        id: stillTimer
        interval: 1900
        running: root.hovered && root.detail > 0.5 && !root.dragging && !root.still
        onTriggered: if (root.emote === "" && (root.m === "idle" || root.m === "walk")) { root.play(root.who.rest, 2400); Sfx.play("hover") }
    }
    // On the bench nobody watches the pointer; they pass the time. Every few seconds one of
    // them shows a feeling for a moment (and now and then hops with it). Each has a clock
    // of her own, so they never move as one.
    readonly property var benchEmotes: ["laugh", "hello", "love", "surprised", "hum", "smug", "cool", "hype", "unimpressed", "annoyed"]
    Timer {
        interval: 1500 + Math.random() * 5000
        running: root.bench && !root.still && !root.paused && root.visible && !Theme.reduced
        repeat: true
        onTriggered: {
            interval = 3000 + Math.random() * 6000 / root.who.energy
            if (root.emote !== "") return
            const r = Math.random()
            if (r < 0.15) { root.st.blink = 1; root.st.blinks = 1 }
            else if (r < 0.3) root.play(root.who.quirk, 1800)
            else root.play(root.benchEmotes[Math.floor(Math.random() * root.benchEmotes.length)], 1300 + Math.random() * 900)
            if (Math.random() < 0.3) root.jump(0.3, false)
        }
    }
    // left alone and idle, each falls into a habit of her own now and then
    Timer {
        interval: 9000 + Math.random() * 12000
        running: !root.still && !root.bench && !root.paused && root.visible && root.m === "idle" && root.emote === "" && !root.dragging && !Theme.reduced
        repeat: true
        onTriggered: {
            interval = 9000 + Math.random() * 12000
            root.play(root.who.quirk, 2200)
            if (root.who.quirk === "hype") root.jump(1, true)
        }
    }

    // ---- one-shot moves the island asks for --------------------------------------
    function blinkNow() { st.blink = 1 }
    function compress() { st.sqv += 4 }
    function land() { st.sqv += 6 }
    function hang() { st.swing = 1 }
    function jump(power, force) {
        if (Theme.reduced) return
        if (!force && st.jump < 0) return
        st.jumpV = -9 * Math.sqrt(Math.max(0.1, power * who.bounce))
    }
    function roll(turns, ms) { if (Theme.reduced) return; st.rollT = 0; st.rollTurns = turns; st.rollMs = ms / who.energy }
    function celebrate(power) { jump(power); celebrating = true; celebrateTimer.restart() }
    Timer { id: celebrateTimer; interval: 1500; onTriggered: root.celebrating = false }

    // A click is a slap, and each answers in character. Three within 1.7 s and any of
    // them goes dizzy.
    property var clickTimes: []
    Timer { id: dizzyTimer; interval: 3300; onTriggered: root.dizzyOverride = false }
    function poke() {
        const now = Date.now()
        clickTimes = clickTimes.filter(t => now - t < 1700).concat([now])
        if (clickTimes.length >= 3) {
            clickTimes = []
            dizzyOverride = true
            dizzyTimer.restart()
            Sfx.play("dizzy")
        } else {
            st.sqv += who.slap === "unimpressed" ? 3 : 9 // Luka barely moves
            if (who.slap === "angry") st.shake = 1
            if (who.slap === "laugh") jump(0.5, true)
            play(who.slap, who.slap === "unimpressed" ? 1400 : 900)
            Sfx.play("click")
        }
        root.clicked()
    }

    // ---- what each mood and emote looks like ---------------------------------------
    readonly property var looks: ({
        idle:  { eyes: "normal", hands: "rest" },
        walk:  { eyes: "normal", hands: "rest", sway: true },
        think: { color: "#8B5CF6", eyes: "normal", mouth: "flat",  hands: "chin", badge: "dots", look: [0.6, -0.7] },
        work:  { color: "#3B9EFF", eyes: "normal", hands: "typing", badge: "dots" },
        alert: { color: "#F5A524", eyes: "big",    mouth: "open",  hands: "wave2", badge: "!", hop: true },
        wow:   { color: "#22D3EE", eyes: "big",    mouth: "o",     hands: "wide" },
        happy: { color: "#34D399", eyes: "happy",  mouth: "open",  hands: "cheer", fx: "spark" },
        sad:   { color: "#F4505E", eyes: "tired",  mouth: "wavy",  hands: "droop", fx: "sweat" },
        sleep: { color: "#94A3B8", eyes: "closed", mouth: "flat",  hands: "tucked", fx: "zzz", slow: true },
        dizzy: { color: "#F472B6", eyes: "spiral", mouth: "wavy",  hands: "flail", wobble: true }
    })
    readonly property var emotes: ({
        hello:       { eyes: "happy", mouth: "open",  hands: "hello" },
        surprised:   { eyes: "dots",  mouth: "o",     hands: "wide" },
        // resting the pointer on her
        love:        { eyes: "heart", mouth: "smile", hands: "heart", fx: "heart", blush: 1 },
        fond:        { eyes: "happy", mouth: "soft",  hands: "rest",  fx: "heart1", blush: 0.8 },           // Luka: a quiet smile
        flustered:   { eyes: "dots",  mouth: "wavy",  hands: "wide",  fx: "sweat", blush: 1 },              // Teto: cannot take it
        // a slap
        annoyed:     { eyes: "slit",  mouth: "flat",  hands: "hips", color: "#A855F7" },                    // Miku sulks
        angry:       { eyes: "slit",  mouth: "open",  hands: "flail", color: "#F4505E", blush: 1 },         // Rin blows up
        unimpressed: { eyes: "flat",  mouth: "flat",  hands: "rest" },                                      // Luka: really?
        laugh:       { eyes: "happy", mouth: "open",  hands: "cheer" },
        proud:       { eyes: "happy", mouth: "grin",  hands: "hips" },                                      // Zundamon: look at me, nanoda
        tsun:        { eyes: "slit",  mouth: "flat",  hands: "hips", blush: 1, away: true },                // Teto: hmph
        // the idle habits
        hum:         { eyes: "happy", mouth: "sing",  hands: "rest",  fx: "note", sway: true },
        sing:        { eyes: "happy", mouth: "sing",  hands: "rest" },                                     // singing along in a dance: no swaying, the dance moves her
        hype:        { eyes: "big",   mouth: "grin",  hands: "cheer" },
        cool:        { eyes: "closed", mouth: "soft", hands: "hips" },
        stretch:     { eyes: "happy", mouth: "open",  hands: "cheer", stretch: true },
        smug:        { eyes: "smug",  mouth: "smug",  hands: "hips", spin: true },
        // the memory is being cleaned: she takes a broom to it
        sweep:       { eyes: "happy", mouth: "open",  hands: "sweep", fx: "dust", sway: true }
    })
    function look() {
        const a = looks[m] || looks.idle, e = emotes[emote] || (music && m === "idle" ? emotes.hum : null)
        const L = e ? Object.assign({}, a, e) : Object.assign({}, a)
        L.tinted = !!L.color // a mood with a colour of its own (idle has none)
        if (!L.color) L.color = hair
        if (!L.mouth) L.mouth = who.mouth
        return L
    }

    // The broom, in body radii: from the top of its stick to where the bristles begin. It
    // swings from side to side, the bristles further than the handle.
    function broomLine(t) {
        const sx = Math.sin(t * 7) * 0.45
        return { ax: 0.55 + sx * 0.6, ay: -0.5, bx: -0.45 + sx * 1.3, by: 0.78 }
    }

    // the hands' poses, in body radii from the body's centre: [left, right]
    readonly property var poses: ({
        rest:   t => [{ x: -1.38, y: 0.52 + Math.sin(t * 2) * 0.03 }, { x: 1.38, y: 0.52 + Math.sin(t * 2 + 1) * 0.03 }],
        typing: t => [{ x: -0.5, y: 0.92 + Math.max(0, Math.sin(t * 17)) * -0.16 }, { x: 0.5, y: 0.92 + Math.max(0, Math.sin(t * 17 + 2.2)) * -0.16 }],
        chin:   t => [{ x: -1.38, y: 0.52 }, { x: 0.42, y: 0.72 + Math.sin(t * 1.6) * 0.02 }],
        wave2:  t => [{ x: -1.3, y: -0.55 + Math.sin(t * 11) * 0.14 }, { x: 1.3, y: -0.55 + Math.sin(t * 11 + 1.6) * 0.14 }],
        cheer:  t => [{ x: -1.25, y: -0.98 + Math.sin(t * 9) * 0.07 }, { x: 1.25, y: -0.98 + Math.sin(t * 9 + 1) * 0.07 }],
        droop:  t => [{ x: -1.12, y: 0.8 }, { x: 1.12, y: 0.8 }],
        tucked: t => [{ x: -0.45, y: 0.86 }, { x: 0.45, y: 0.86 }],
        flail:  t => [{ x: -1.25 + Math.cos(t * 9) * 0.2, y: -0.2 + Math.sin(t * 9) * 0.4 }, { x: 1.25 + Math.cos(t * 9 + 2) * 0.2, y: -0.2 + Math.sin(t * 9 + 2) * 0.4 }],
        heart:  t => [{ x: -0.2, y: 0.82 }, { x: 0.2, y: 0.82 }],
        wide:   t => [{ x: -1.45, y: -0.15 }, { x: 1.45, y: -0.15 }],
        hips:   t => [{ x: -1.02, y: 0.6 }, { x: 1.02, y: 0.6 }],
        hello:  t => [{ x: -1.38, y: 0.52 }, { x: 1.5 + Math.sin(t * 12) * 0.16, y: -0.6 + Math.cos(t * 12) * 0.05 }],
        sweep:  t => { const b = broomLine(t); return [{ x: b.ax + (b.bx - b.ax) * 0.72, y: b.ay + (b.by - b.ay) * 0.72 }, { x: b.ax + (b.bx - b.ax) * 0.42, y: b.ay + (b.by - b.ay) * 0.42 }] }, // both on the stick
        cling:  t => [{ x: -0.6, y: -1.02 }, { x: 0.6, y: -1.02 }]
    })

    // ---- the simulation's state (plain JS, not bindings: it changes every frame) -----
    property var st: ({
        t: Math.random() * 10, last: 0, gx: 0, gy: 0, blink: 0, nextBlink: 2, blinks: 0,
        sq: 0, sqv: 0, jump: 0, jumpV: 0, rollT: 1, rollTurns: 1, rollMs: 950, shake: 0, swing: 0,
        lean: 0, blush: 0.4, fxClock: 0, parts: [], tails: null,
        hand: [{ x: -1.38, y: 0.52 }, { x: 1.38, y: 0.52 }]
    })

    // The canvas is as big as she ever gets (the 120 px box, with room for hair, hands
    // and sparks) and is scaled down to `size`; the clip grows with `detail`.
    readonly property real k: size / 120
    readonly property real spill: detail * 84
    Item {
        anchors.centerIn: parent
        // in the bar she may use the 4 px the bar keeps around her box, and no more
        width: root.size + 2 * (root.spill * root.k + 4 * (1 - root.detail))
        height: width
        clip: true
        Canvas {
            id: canvas
            width: 288; height: 288
            anchors.centerIn: parent
            scale: root.k * Math.max(0, root.swap)
            rotation: (1 - root.swap) * -70
            antialiasing: true
            onPaint: root.paint(getContext("2d"))
        }
    }

    Timer {
        // the bar's mini has little to show: 20 frames a second are plenty there
        interval: root.bench ? 66 : root.detail > 0 || root.dragging ? 16 : 50
        running: root.visible && !root.paused && !root.still
        repeat: true
        onTriggered: {
            const now = Date.now()
            const dt = Math.min(0.05, root.st.last ? (now - root.st.last) / 1000 : 0.016)
            root.st.last = now
            root.step(dt)
            canvas.requestPaint()
        }
    }

    // ---- constants of the drawing -----------------------------------------------------
    readonly property real cR: 46        // the body's radius on the canvas
    readonly property real cX: 144
    readonly property real cY: 148

    function clampv(v, a, b) { return Math.max(a, Math.min(b, v)) }
    function easeOut(u) { return 1 - Math.pow(1 - clampv(u, 0, 1), 3) }
    function rgba(hex, a) {
        return "rgba(" + parseInt(hex.substr(1, 2), 16) + "," + parseInt(hex.substr(3, 2), 16) + "," + parseInt(hex.substr(5, 2), 16) + "," + a + ")"
    }

    // the body's pose this frame: centre, angle and stretch
    function pose() {
        const s = st, L = look(), R = cR, t = s.t, B = who.bounce
        let y = cY + s.jump * R * 0.1
        let x = cX + Math.sin(t * 40) * s.shake * R * 0.12
        if (L.hop && !Theme.reduced) { const u = (t * 1.25) % 1; if (u < 0.5) y -= Math.sin(u * 2 * Math.PI) * R * 0.3 * B }
        if (L.sway && m === "walk" && !Theme.reduced) y -= Math.abs(Math.sin(t * 6)) * R * 0.1 * B
        const breathe = Theme.reduced ? 0 : Math.sin(t * (L.slow ? 1.6 : 2.4)) * (L.slow ? 0.035 : 0.018)
        const speed = dragging && !Theme.reduced ? Math.min(1, Math.hypot(dragVx, dragVy) / 1000) * 0.08 : 0
        const side = Math.abs(dragVx) >= Math.abs(dragVy)
        let sx = (1 + s.sq * 0.06 - breathe * 0.6) * (1 - wallX) * (side ? 1 + speed : 1 - speed * 0.5)
        let sy = (1 - s.sq * 0.06 + breathe) * (1 - wallY) * (side ? 1 - speed * 0.5 : 1 + speed)
        if (L.stretch) { const u = Math.abs(Math.sin(t * 2.2)); sy += u * 0.1; sx -= u * 0.05 }
        const turning = s.rollT < 1 ? easeOut(s.rollT) * 2 * Math.PI * s.rollTurns : 0
        return { x: x, y: y, sx: sx, sy: sy, angle: s.lean + turning + inwardTilt * Math.PI / 180 }
    }
    function toWorld(P, lx, ly) {
        const x = lx * cR * P.sx, y = ly * cR * P.sy, c = Math.cos(P.angle), s = Math.sin(P.angle)
        return { x: P.x + x * c - y * s, y: P.y + x * s + y * c }
    }

    function step(dt) {
        const s = st, L = look(), R = cR
        s.t += dt * who.energy * (L.slow ? 0.6 : 1)

        // Gaze. The pointer comes first, through every mood and every emote: she waves,
        // rolls, sulks and types with her eyes on it. Only where the pointer is not known
        // does the mood say where to look, and asleep she looks nowhere. (Teto, slapped,
        // makes a point of looking away.)
        let tx = 0, ty = 0
        if (gazeOn) { tx = gaze.x; ty = gaze.y }
        else if (m === "sleep") { tx = 0; ty = 0.2 }
        else if (L.away) { tx = -0.9; ty = -0.3 }
        else if (looking) { tx = Math.tanh((lookAt.x - width / 2) / 260); ty = Math.tanh((lookAt.y - height / 2) / 200) } // screen px, whatever her size
        else if (L.look) { tx = L.look[0]; ty = L.look[1] }
        else if (m === "walk") { tx = walkDir * 0.8 }
        const kk = 1 - Math.exp(-dt * 9 * who.energy)
        s.gx += (tx - s.gx) * kk; s.gy += (ty - s.gy) * kk

        s.nextBlink -= dt
        if (s.nextBlink <= 0) { s.blink = 1; s.blinks = Math.random() < 0.22 ? 1 : 0; s.nextBlink = (2.2 + Math.random() * 3.2) / who.energy }
        if (s.blink > 0) { s.blink -= dt / (who.calm ? 0.2 : 0.13); if (s.blink <= 0 && s.blinks) { s.blinks = 0; s.blink = 1 } }

        s.sqv += (-s.sq * 190 - s.sqv * 13) * dt; s.sq += s.sqv * dt
        if (s.jump < 0 || s.jumpV < 0) { s.jumpV += 38 * dt; s.jump += s.jumpV * dt; if (s.jump >= 0) { s.jump = 0; s.jumpV = 0; s.sqv += 5 } }
        if (s.rollT < 1) s.rollT = Math.min(1, s.rollT + dt * 1000 / s.rollMs)
        s.shake = Math.max(0, s.shake - dt * 2.2)
        s.swing = Math.max(0, s.swing - dt * 1.2)
        const carried = dragging ? clampv(dragVx / 40, -14, 14) * Math.PI / 180 : 0
        const want = carried + (L.wobble ? Math.sin(s.t * 3.1) * 0.12 : 0) + (L.sway ? Math.sin(s.t * (m === "walk" ? 6 : 4)) * 0.07 * (m === "walk" ? walkDir : 1) : 0)
                   + (m === "think" ? 0.1 : 0) + (emote === "cool" || emote === "tsun" ? -0.08 : 0) + Math.sin(s.t * 7) * s.swing * 0.25
        s.lean += (want - s.lean) * (1 - Math.exp(-dt * 8))
        s.blush += (((L.blush || 0.4) + (hovered ? 0.15 : 0)) - s.blush) * (1 - Math.exp(-dt * 6))

        const fn = poses[dragging ? "cling" : (L.hands || "rest")] || poses.rest
        const p = fn(s.t), hk = 1 - Math.exp(-dt * 14 * who.energy)
        for (let i = 0; i < 2; i++) { s.hand[i].x += (p[i].x - s.hand[i].x) * hk; s.hand[i].y += (p[i].y - s.hand[i].y) * hk }

        simTails(dt, L)
        spawn(dt, L)
        for (const q of s.parts) { q.life += dt; q.x += q.vx * dt; q.y += q.vy * dt; q.vy += (q.g || 0) * dt; q.rot += (q.vr || 0) * dt }
        s.parts = s.parts.filter(q => q.life < q.max)
    }

    // Chains of points on springs. The item itself is what moves on the screen while
    // she is carried, so the drag's velocity is fed in as a wind that blows them back.
    function simTails(dt, L) {
        const s = st, P = pose(), R = cR, H = hairOf(who.style)
        // (the chains are remade whenever the hair style is not the one they were made for)
        if (!s.tails || s.tailStyle !== who.style) { s.tails = H ? [{ side: -1, p: [] }, { side: 1, p: [] }] : []; s.tailStyle = who.style }
        if (!H) return
        // short hair in the bar, so that it ends inside it; full length on the card
        const seg = R * H.seg * Math.max(0.15, leafScale) * (0.42 + 0.58 * detail), n = H.n
        const wx = dragging ? clampv(-dragVx / k, -2600, 2600) : 0, wy = dragging ? clampv(-dragVy / k, -2600, 2600) : 0
        for (const T of s.tails) {
            const a = toWorld(P, T.side * H.x, H.y), p = T.p
            if (p.length === 0) for (let i = 0; i < n; i++) p.push({ x: a.x + T.side * i * seg * 0.35, y: a.y + i * seg * 0.93, px: a.x + T.side * i * seg * 0.35, py: a.y + i * seg * 0.93 })
            p[0].x = a.x; p[0].y = a.y
            for (let i = 1; i < n; i++) {
                const q = p[i], vx = (q.x - q.px) * 0.94, vy = (q.y - q.py) * 0.94
                q.px = q.x; q.py = q.y
                q.x += vx + (T.side * R * H.out * (1 - i / n) + wx * 0.5) * dt * dt
                q.y += vy + (R * 42 + wy * 0.5) * dt * dt
            }
            for (let it = 0; it < 6; it++) {
                for (let i = 1; i < n; i++) {
                    const A = p[i - 1], B = p[i], dx = B.x - A.x, dy = B.y - A.y, d = Math.hypot(dx, dy) || 1, f = (d - seg) / d
                    if (i === 1) { B.x -= dx * f; B.y -= dy * f } else { A.x += dx * f * 0.5; A.y += dy * f * 0.5; B.x -= dx * f * 0.5; B.y -= dy * f * 0.5 }
                }
                p[0].x = a.x; p[0].y = a.y
            }
        }
    }

    function spawn(dt, L) {
        const s = st
        let fx = L.fx || ""
        if (celebrating) fx = "spark"
        if (fx === "" || (detail < 0.5 && fx !== "dust") || Theme.reduced || still) return // (arrive() adds its sparks itself, at any size)
        s.fxClock -= dt; if (s.fxClock > 0) return
        const R = cR, P = pose(), r = () => Math.random() - 0.5
        const add = o => s.parts.push(Object.assign({ life: 0, rot: 0, x: P.x, y: P.y }, o))
        if (fx === "heart")  { s.fxClock = 0.22; add({ type: "heart", x: P.x + r() * R * 1.6, y: P.y - R * 0.5, vx: r() * R * 0.4, vy: -R * 1.5, max: 1.3, size: R * (0.16 + Math.random() * 0.12) }) }
        if (fx === "heart1") { s.fxClock = 0.9;  add({ type: "heart", x: P.x + R * 0.9, y: P.y - R * 0.7, vx: R * 0.15, vy: -R * 0.7, max: 1.8, size: R * 0.16 }) }
        if (fx === "note")   { s.fxClock = 0.3;  add({ type: "note", x: P.x - R * 1.1 + r() * R * 0.5, y: P.y - R * 0.7, vx: -R * 0.5 + r() * R, vy: -R * 1.4, max: 1.5, size: R * 0.26, hue: Math.random() < 0.5 ? hair : mk.tip, vr: r() }) }
        if (fx === "spark") {
            s.fxClock = 0.09
            // every fifth piece of the celebration is her favourite thing
            if (Math.random() < 0.2) add({ type: "fav", x: P.x + r() * R * 2.6, y: P.y - R * 0.4 + r() * R, vx: r() * R, vy: -R * 1.6, g: R * 3.2, max: 1.2, size: R * 0.26, vr: r() * 5 })
            else add({ type: "spark", x: P.x + r() * R * 3, y: P.y + r() * R * 2.4, vx: 0, vy: -R * 0.3, max: 0.7, size: R * (0.1 + Math.random() * 0.14), hue: Math.random() < 0.5 ? "#34D399" : "#FFFFFF" })
        }
        if (fx === "sweat")  { s.fxClock = 0.5; const d = Math.random() < 0.5 ? -1 : 1; add({ type: "drop", x: P.x + d * R * 0.95, y: P.y - R * 0.55, vx: d * R * 0.5, vy: -R * 0.6, g: R * 4, max: 0.8, size: R * 0.11 }) }
        if (fx === "dust")   { s.fxClock = 0.1; const b = broomLine(s.t), q = toWorld(P, b.bx, b.by + 0.22); add({ type: "dust", x: q.x, y: q.y, vx: r() * R * 2.4, vy: -R * (0.3 + Math.random() * 0.6), max: 0.7, size: R * (0.07 + Math.random() * 0.1) }) }
        if (fx === "zzz")    { s.fxClock = 0.8; add({ type: "z", x: P.x + R * 0.8, y: P.y - R * 0.8, vx: R * 0.3, vy: -R * 0.6, max: 1.9, size: R * 0.24 }) }
    }

    // ---- painting ---------------------------------------------------------------------
    // an ellipse (or an arc of one) with radii, as the HTML canvas has it and QML's does not
    function ell(g, x, y, rx, ry, a0, a1) {
        g.save(); g.translate(x, y); g.scale(1, ry / rx)
        g.arc(0, 0, rx, a0 === undefined ? 0 : a0, a1 === undefined ? 2 * Math.PI : a1, false)
        g.restore()
    }
    function rr(g, x, y, w, h, r) {
        g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r)
        g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath()
    }
    function heartShape(g, x, y, s, c) {
        g.fillStyle = c; g.beginPath(); g.moveTo(x, y + s * 0.9)
        g.bezierCurveTo(x - s * 1.5, y - s * 0.2, x - s * 0.7, y - s * 1.2, x, y - s * 0.4)
        g.bezierCurveTo(x + s * 0.7, y - s * 1.2, x + s * 1.5, y - s * 0.2, x, y + s * 0.9); g.fill()
    }
    function bodyPath(g) {
        // coucou's Mochi: a flattened superellipse
        const R = cR, rx = mk.rx * R, ry = mk.ry * R, e = 2 / mk.exp, dy = R * 0.06
        g.beginPath()
        for (let i = 0; i <= 64; i++) {
            const a = i / 64 * 2 * Math.PI, c = Math.cos(a), s = Math.sin(a)
            const x = Math.sign(c) * Math.pow(Math.abs(c), e) * rx, y = Math.sign(s) * Math.pow(Math.abs(s), e) * ry + dy
            if (i) g.lineTo(x, y); else g.moveTo(x, y)
        }
        g.closePath()
    }

    function paint(g) {
        g.reset()
        const s = st, R = cR, L = look(), P = pose(), col = L.color
        if (!s.tails) return

        if (detail > 0.05) {
            const gl = g.createRadialGradient(P.x, P.y, R * 0.4, P.x, P.y, R * 2.5)
            gl.addColorStop(0, rgba(col, 0.3 * detail)); gl.addColorStop(1, rgba(col, 0))
            g.fillStyle = gl; g.fillRect(0, 0, 288, 288)
            if (!dragging) { g.fillStyle = "rgba(0,0,0," + 0.25 * detail + ")"; g.beginPath(); ell(g, cX, cY + R * 1.02, R * 0.95, R * 0.12); g.fill() }
        }

        const H = hairOf(s.tailStyle)
        if (H) for (const T of s.tails) { if (T.p.length !== H.n) continue; if (H.coil) paintDrill(g, T, H, L); else if (H.pod) paintPod(g, T, H); else paintTail(g, T, H) }

        g.save(); g.translate(P.x, P.y); g.rotate(P.angle); g.scale(P.sx, P.sy)
        paintBody(g, L)
        g.restore()

        if (s.tailStyle === "twintails" && mk.tieOn) for (const T of s.tails) {
            if (!T.p.length) continue // the ties sit on the tails' roots, over the body's corners
            const a = T.p[0]; g.save(); g.translate(a.x, a.y); g.rotate(P.angle + T.side * 0.5)
            g.fillStyle = mk.tie; rr(g, -R * 0.2, -R * 0.14, R * 0.4, R * 0.28, R * 0.06); g.fill()
            g.fillStyle = mk.tieBand; g.fillRect(-R * 0.2, -R * 0.03, R * 0.4, R * 0.06); g.restore()
        }

        if (L.hands === "sweep" && !dragging) paintBroom(g, P) // (at any size: in the bar the broom is what shows she is sweeping)
        if (detail > 0.25) { g.globalAlpha = clampv((detail - 0.25) / 0.4, 0, 1); paintHands(g, P, L); g.globalAlpha = 1 }
        paintParts(g)
        const badge = L.badge || (doneBadge ? "done" : "")
        if (badge !== "") paintBadge(g, P, badge, badge === "done" ? "#34D399" : col)
    }

    // a ribbon of hair along a chain: Miku's tails, Luka's long hair
    function paintTail(g, T, H) {
        const R = cR, p = T.p, n = p.length, W = H.w, Lp = [], Rp = []
        for (let i = 0; i < n; i++) {
            const a = p[Math.max(0, i - 1)], b = p[Math.min(n - 1, i + 1)], d = Math.hypot(b.x - a.x, b.y - a.y) || 1
            const dx = (b.x - a.x) / d, dy = (b.y - a.y) / d, w = W[i] * R
            Lp.push({ x: p[i].x - dy * w, y: p[i].y + dx * w }); Rp.push({ x: p[i].x + dy * w, y: p[i].y - dx * w })
        }
        const tip = p[n - 1]
        g.beginPath(); g.moveTo(Lp[0].x, Lp[0].y)
        for (let i = 1; i < n; i++) g.quadraticCurveTo(Lp[i - 1].x, Lp[i - 1].y, (Lp[i - 1].x + Lp[i].x) / 2, (Lp[i - 1].y + Lp[i].y) / 2)
        g.quadraticCurveTo(Lp[n - 1].x, Lp[n - 1].y, tip.x, tip.y + R * 0.1)
        for (let i = n - 1; i > 0; i--) g.quadraticCurveTo(Rp[i].x, Rp[i].y, (Rp[i - 1].x + Rp[i].x) / 2, (Rp[i - 1].y + Rp[i].y) / 2)
        g.lineTo(Rp[0].x, Rp[0].y); g.closePath()
        const gr = g.createLinearGradient(p[0].x, p[0].y, tip.x, tip.y); gr.addColorStop(0, hair); gr.addColorStop(1, hairD)
        g.fillStyle = gr; g.fill()
        g.strokeStyle = "rgba(255,255,255,0.28)"; g.lineWidth = R * 0.07; g.lineCap = "round"; g.beginPath()
        g.moveTo(p[1].x + (Lp[1].x - p[1].x) * 0.4, p[1].y + (Lp[1].y - p[1].y) * 0.4)
        for (let i = 2; i < n - 1; i++) g.lineTo(p[i].x + (Lp[i].x - p[i].x) * 0.4, p[i].y + (Lp[i].y - p[i].y) * 0.4)
        g.stroke()
    }

    // Zundamon's edamame pods: the beans in a row along the chain, a shine on each
    function paintPod(g, T, H) {
        const R = cR, p = T.p, n = p.length, TAU = 2 * Math.PI
        g.fillStyle = hairD
        for (let i = 0; i < n; i++) { g.beginPath(); g.arc(p[i].x, p[i].y, H.w[i] * R, 0, TAU, false); g.fill() }
        g.fillStyle = "rgba(255,255,255,0.3)"
        for (let i = 0; i < n - 1; i++) { g.beginPath(); g.arc(p[i].x - R * 0.04, p[i].y - R * 0.05, H.w[i] * R * 0.4, 0, TAU, false); g.fill() }
    }

    // Teto's drills: coils stacked along the chain, the turns marked by a darker thread
    // that runs down them (and races when she is being smug)
    function paintDrill(g, T, H, L) {
        const R = cR, p = T.p, n = p.length, TAU = 2 * Math.PI, turn = st.t * (L.spin ? 9 : 1.2) * T.side
        for (let i = 0; i < n; i++) {
            for (let j = 0; j < 2; j++) {
                const a = p[i], b = p[Math.min(n - 1, i + 1)], u = j / 2
                const x = a.x + (b.x - a.x) * u, y = a.y + (b.y - a.y) * u
                const w = (H.w[i] + (H.w[Math.min(n - 1, i + 1)] - H.w[i]) * u) * R
                if (i === n - 1 && j) break
                g.fillStyle = hair; g.beginPath(); ell(g, x, y, w, w * 0.62); g.fill()
                const ph = (i * 2 + j) * 0.9 + turn
                g.strokeStyle = hairD; g.lineWidth = R * 0.05; g.lineCap = "round"
                g.beginPath(); ell(g, x, y, w * 0.92, w * 0.5, 0.15 * Math.PI + Math.sin(ph) * 0.5, 0.85 * Math.PI + Math.sin(ph) * 0.5); g.stroke()
            }
        }
    }

    // Coucou's Mochi under each one's own hair: cream from the top right to the bottom
    // left, the mood's colour rising from below, a soft shade at the rim and a highlight;
    // over it the back of the hair, the side locks, the fringe and what she wears on her
    // head. Every number is in `mk`.
    function paintBody(g, L) {
        const s = st, R = cR, TAU = 2 * Math.PI, T = mk, ry = R * T.ry, gh = skin === "github"
        if (T.hairOn) { // the back of the hair: the body's own shape, a little larger and higher
            g.save(); g.translate(0, -R * T.backUp); g.scale(T.backW, T.backH); bodyPath(g); g.fillStyle = hairD; g.fill(); g.restore()
        }
        bodyPath(g)
        const sk = g.createLinearGradient(R, -R, -R, R); sk.addColorStop(0, T.bodyTop); sk.addColorStop(1, T.bodyBot)
        g.fillStyle = sk; g.fill()
        g.save(); bodyPath(g); g.clip()
        if (L.tinted && !gh) {
            const tg = g.createLinearGradient(0, ry + R * 0.06, 0, -ry * 0.25)
            tg.addColorStop(0, rgba(L.color, T.tint)); tg.addColorStop(1, rgba(L.color, 0))
            g.fillStyle = tg; g.fillRect(-R * 1.5, -R * 1.3, R * 3, R * 2.7)
        }
        if (T.hairOn) {
            for (const d of [-1, 1]) { // side locks in front of the ears
                g.fillStyle = hair; g.beginPath(); g.moveTo(d * R * 1.5, -R * 0.4); g.quadraticCurveTo(d * R * (T.rx - 0.26), 0, d * R * (T.rx - 0.12), R * T.lock)
                g.quadraticCurveTo(d * R * T.rx, R * 0.2, d * R * 1.5, R * (T.lock + 0.02)); g.fill()
            }
            const hg = g.createLinearGradient(0, -R, 0, 0); hg.addColorStop(0, hairTop); hg.addColorStop(1, hair)
            g.fillStyle = hg; g.beginPath(); g.moveTo(-R * 1.5, -R * 1.3); g.lineTo(R * 1.5, -R * 1.3); g.lineTo(R * 1.5, R * T.fringeY)
            const a = T.bangTip, b = T.bangNotch
            const B = [[1.0, a - 0.02], [0.74, b + 0.04], [0.5, a + 0.02], [0.24, b], [0.02, a], [-0.26, b], [-0.5, a + 0.02], [-0.74, b + 0.04], [-1.0, a - 0.02]]
            for (let i = 0; i < B.length; i++) { const p = B[i], q = B[i + 1] || [-1.5, T.fringeY]; g.quadraticCurveTo(p[0] * R, p[1] * R, (p[0] + q[0]) / 2 * R, (p[1] + q[1]) / 2 * R) }
            g.lineTo(-R * 1.5, R * T.fringeY); g.closePath(); g.fill()
            g.strokeStyle = "rgba(255,255,255," + T.shine + ")"; g.lineWidth = R * 0.07; g.lineCap = "round"
            g.beginPath(); g.arc(0, R * 0.25, R * 0.98, -Math.PI * 0.78, -Math.PI * 0.55, false); g.stroke()
            g.beginPath(); g.arc(0, R * 0.25, R * 0.98, -Math.PI * 0.42, -Math.PI * 0.34, false); g.stroke()
        }
        if (who.style === "bow") { // Rin's two white hair clips
            const y = R * T.accY
            g.strokeStyle = "#F4F6F8"; g.lineWidth = R * 0.06; g.lineCap = "round"
            g.beginPath(); g.moveTo(R * 0.5, y - R * 0.46); g.lineTo(R * 0.74, y - R * 0.34); g.stroke()
            g.beginPath(); g.moveTo(R * 0.46, y - R * 0.34); g.lineTo(R * 0.7, y - R * 0.22); g.stroke()
        }
        if (who.style === "long") { // Luka's gold band
            g.strokeStyle = "#E3B341"; g.lineWidth = R * 0.07; g.beginPath(); g.arc(0, R * (0.3 + T.accY), R * 1.08, -Math.PI * 0.9, -Math.PI * 0.1, false); g.stroke()
        }
        const sh = g.createRadialGradient(R * 0.2, -R * 0.2, R * 0.5, 0, 0, R * 1.35); sh.addColorStop(0, "rgba(0,0,0,0)"); sh.addColorStop(1, "rgba(0,0,0," + T.shade + ")")
        g.fillStyle = sh; g.fillRect(-R * 1.5, -R * 1.3, R * 3, R * 2.7)
        const hl = g.createRadialGradient(R * 0.5, -R * 0.5, 0, R * 0.5, -R * 0.5, R * 0.6); hl.addColorStop(0, "rgba(255,255,255," + T.hl + ")"); hl.addColorStop(1, "rgba(255,255,255,0)")
        g.fillStyle = hl; g.fillRect(-R * 1.5, -R * 1.3, R * 3, R * 2.7)
        g.restore()
        if (who.style === "bow") { // Rin's bow stands on her head and flops with every bounce
            const flop = 1 - s.sq * 0.12, tilt = Math.sin(s.t * 2.4) * 0.05
            g.save(); g.translate(0, R * (-0.8 + T.accY)); g.rotate(tilt); g.scale(1, flop)
            g.fillStyle = "#FFFFFF"; g.strokeStyle = "#D8DEE4"; g.lineWidth = R * 0.03; g.lineJoin = "round"
            for (const d of [-1, 1]) {
                g.beginPath(); g.moveTo(0, 0); g.quadraticCurveTo(d * R * 0.3, -R * 0.72, d * R * 0.72, -R * 0.56)
                g.quadraticCurveTo(d * R * 0.86, -R * 0.2, d * R * 0.5, R * 0.06); g.closePath(); g.fill(); g.stroke()
            }
            g.beginPath(); ell(g, 0, -R * 0.02, R * 0.13, R * 0.11); g.fill(); g.stroke()
            g.restore()
        }

        // the face: it travels with the glance, further still in the bar's mini
        const reach = 1 + (1 - detail) * 0.6
        const fx = s.gx * R * T.gazeX * reach, fy = s.gy * R * T.gazeY * reach
        g.fillStyle = rgba(T.cheek, T.cheekA * Math.max(0.35, s.blush))
        for (const d of [-1, 1]) { g.beginPath(); ell(g, d * R * T.cx + fx, R * T.cy + fy, R * T.cw, R * T.ch); g.fill() }
        paintEyes(g, L, fx, fy)
        paintMouth(g, L, fx * 0.9, fy)

        if (T.setOn) { // headset: the ear piece carries the mood's light, the boom ends in a coloured tip
            const ex = -R * (T.rx - 0.02)
            g.fillStyle = T.set; g.beginPath(); ell(g, ex, R * 0.04, R * 0.12, R * 0.21); g.fill()
            g.strokeStyle = L.color; g.lineWidth = R * 0.045; g.beginPath(); ell(g, ex, R * 0.04, R * 0.055, R * 0.125); g.stroke()
            g.strokeStyle = T.set; g.lineCap = "round"; g.beginPath(); g.moveTo(ex + R * 0.02, R * 0.22); g.quadraticCurveTo(ex + R * 0.12, R * 0.6, -R * 0.58 + fx * 0.4, R * 0.62); g.stroke()
            g.fillStyle = T.tip; g.beginPath(); g.arc(-R * 0.58 + fx * 0.4, R * 0.62, R * 0.055, 0, TAU, false); g.fill()
        }
    }

    function paintEyes(g, L, fx, fy) {
        const s = st, R = cR, t = s.t, TAU = 2 * Math.PI, INK = mk.ink
        const type = eyesShut ? "closed" : L.eyes
        const soft = type === "normal" || type === "big" || type === "tired" || type === "smug"
        const open = soft ? clampv(1 - Math.max(0, s.blink), 0.08, 1) : 1
        // the mini in the bar has a handful of pixels for a face: bigger, simpler eyes
        const kk = (type === "big" ? 1.2 : 1) * (hovered ? 1.08 : 1) * (1 + (1 - detail) * 0.35)
        // lowered lids: Luka always, anyone tired, Teto when she is pleased with herself
        const lid = type === "tired" ? 0.62 : type === "smug" ? 0.66 : who.calm && type === "normal" ? 0.8 : 1
        for (const d of [-1, 1]) {
            const x = d * R * mk.ex + fx, y = R * mk.ey + fy, w = R * mk.ew * kk, h = R * mk.eh * kk
            g.lineCap = "round"; g.lineJoin = "round"
            if (soft) { // an ink pill; lowered lids cut its top off
                const hh = Math.max(h * open, R * 0.03)
                g.fillStyle = INK
                if (lid < 1) {
                    const slant = type === "smug" ? d * h * 0.3 : 0, top = y - hh + hh * 2 * (1 - lid)
                    g.save(); g.beginPath(); g.moveTo(x - w * 1.2, top + slant); g.lineTo(x + w * 1.2, top - slant); g.lineTo(x + w * 1.2, y + h * 1.2); g.lineTo(x - w * 1.2, y + h * 1.2); g.closePath(); g.clip()
                    rr(g, x - w, y - hh, w * 2, hh * 2, Math.min(w, hh)); g.fill(); g.restore()
                } else { rr(g, x - w, y - hh, w * 2, hh * 2, Math.min(w, hh)); g.fill() }
                continue
            }
            g.strokeStyle = INK; g.fillStyle = INK; g.lineWidth = R * 0.07
            if (type === "happy")  { g.beginPath(); g.arc(x, y + h * 0.35, w * 1.05, Math.PI * 1.12, Math.PI * 1.88, false); g.stroke() }
            if (type === "closed") { g.beginPath(); g.arc(x, y - h * 0.3, w * 1.05, Math.PI * 0.14, Math.PI * 0.86, false); g.stroke() }
            if (type === "flat")   { g.beginPath(); g.moveTo(x - w, y); g.lineTo(x + w, y); g.stroke() }
            if (type === "dots")   { g.beginPath(); g.arc(x, y, w * 0.42, 0, TAU, false); g.fill() }
            if (type === "slit")   {
                g.beginPath(); g.moveTo(x - d * w * 1.1, y + h * 0.3); g.lineTo(x + d * w * 1.1, y - h * 0.25); g.stroke()
                g.lineWidth = R * 0.05; g.beginPath(); g.moveTo(x - d * w * 1.2, y - h * 0.3); g.lineTo(x + d * w * 0.9, y - h * 0.95); g.stroke()
            }
            if (type === "spiral") {
                g.lineWidth = R * 0.045; g.beginPath()
                for (let i = 0; i < 40; i++) { const a = i / 40 * TAU * 2.2 + t * 7 * d, r = i / 40 * w * 1.25, px = x + Math.cos(a) * r, py = y + Math.sin(a) * r; if (i) g.lineTo(px, py); else g.moveTo(px, py) }
                g.stroke()
            }
            if (type === "heart") heartShape(g, x, y, w * (1.25 + Math.sin(t * 9) * 0.12), "#FF4D6D")
        }
    }

    function paintMouth(g, L, fx, fy) {
        const R = cR, t = st.t, x = fx, y = R * mk.mouthY + fy, mo = L.mouth, TAU = 2 * Math.PI
        // the face at rest is its eyes and cheeks: a mouth appears only to say something
        if (!mk.mouthRest && (mo === "smile" || mo === "soft" || mo === "flat")) return
        g.strokeStyle = mk.ink; g.fillStyle = "#7A2137"; g.lineWidth = R * 0.05; g.lineCap = "round"; g.lineJoin = "round"
        if (mo === "smile") { g.beginPath(); g.arc(x, y - R * 0.06, R * 0.13, Math.PI * 0.18, Math.PI * 0.82, false); g.stroke() }
        if (mo === "soft")  { g.beginPath(); g.arc(x, y - R * 0.1, R * 0.12, Math.PI * 0.3, Math.PI * 0.7, false); g.stroke() }      // Luka's small, even smile
        if (mo === "flat")  { g.beginPath(); g.moveTo(x - R * 0.08, y); g.lineTo(x + R * 0.08, y); g.stroke() }
        if (mo === "o")     { g.beginPath(); ell(g, x, y, R * 0.06, R * 0.075); g.fill() }
        if (mo === "wavy")  { g.beginPath(); for (let i = 0; i <= 12; i++) { const px = x + (i / 12 - 0.5) * R * 0.34, py = y + Math.sin(i * 1.4 + t * 6) * R * 0.03; if (i) g.lineTo(px, py); else g.moveTo(px, py) } g.stroke() }
        if (mo === "smug")  { // Teto's cat mouth
            g.beginPath(); g.arc(x - R * 0.07, y - R * 0.04, R * 0.07, Math.PI * 0.05, Math.PI * 0.95, false); g.stroke()
            g.beginPath(); g.arc(x + R * 0.07, y - R * 0.04, R * 0.07, Math.PI * 0.05, Math.PI * 0.95, false); g.stroke()
        }
        if (mo === "open" || mo === "grin") { // grin: Rin's, wider and with a fang
            const w = mo === "grin" ? 0.19 : 0.14
            g.beginPath(); g.arc(x, y - R * 0.05, R * w, 0, Math.PI, false); g.closePath(); g.fill()
            g.fillStyle = "#FF8FA8"; g.beginPath(); ell(g, x, y + R * (w - 0.08), R * w * 0.5, R * 0.035); g.fill()
            if (mo === "grin") { g.fillStyle = "#ffffff"; g.beginPath(); g.moveTo(x + R * 0.07, y - R * 0.05); g.lineTo(x + R * 0.13, y - R * 0.05); g.lineTo(x + R * 0.1, y + R * 0.03); g.closePath(); g.fill() }
        }
        if (mo === "sing")  { const o = 0.06 + Math.abs(Math.sin(t * 8)) * 0.09; g.beginPath(); ell(g, x, y, R * 0.1, R * o); g.fill(); g.fillStyle = "#FF8FA8"; g.beginPath(); ell(g, x, y + R * o * 0.5, R * 0.06, R * o * 0.4); g.fill() }
    }

    function paintHands(g, P, L) {
        const s = st, R = cR, TAU = 2 * Math.PI
        for (let i = 0; i < 2; i++) {
            const h = toWorld(P, s.hand[i].x, s.hand[i].y) // a plain cream paw
            g.save(); g.translate(h.x, h.y)
            const mg = g.createRadialGradient(R * 0.05, -R * 0.06, R * 0.02, 0, 0, R * (mk.hand + 0.03)); mg.addColorStop(0, mk.bodyTop); mg.addColorStop(1, mk.bodyBot)
            g.fillStyle = mg; g.beginPath(); g.arc(0, 0, R * mk.hand, 0, TAU, false); g.fill()
            g.restore()
        }
        if (L.hands === "heart" && !dragging) { // the heart the two hands hold between them
            const c = toWorld(P, 0, 0.8); heartShape(g, c.x, c.y - R * 0.08, R * (0.2 + Math.sin(s.t * 8) * 0.02), "#FF4D6D")
        }
    }

    // the broom: a wooden stick, a red band, straw bristles that flare toward the floor
    function paintBroom(g, P) {
        const R = cR, b = broomLine(st.t), A = toWorld(P, b.ax, b.ay), B = toWorld(P, b.bx, b.by)
        const len = Math.hypot(B.x - A.x, B.y - A.y) || 1, dx = (B.x - A.x) / len, dy = (B.y - A.y) / len, nx = -dy, ny = dx
        g.lineCap = "round"; g.lineJoin = "round"
        g.strokeStyle = "#B07A3C"; g.lineWidth = R * 0.1
        g.beginPath(); g.moveTo(A.x, A.y); g.lineTo(B.x, B.y); g.stroke()
        g.fillStyle = "#F2C94C"; g.strokeStyle = "#D9A93A"; g.lineWidth = R * 0.03
        g.beginPath()
        g.moveTo(B.x - nx * R * 0.13, B.y - ny * R * 0.13); g.lineTo(B.x + nx * R * 0.13, B.y + ny * R * 0.13)
        g.lineTo(B.x + dx * R * 0.34 + nx * R * 0.3, B.y + dy * R * 0.34 + ny * R * 0.3)
        g.lineTo(B.x + dx * R * 0.34 - nx * R * 0.3, B.y + dy * R * 0.34 - ny * R * 0.3)
        g.closePath(); g.fill(); g.stroke()
        g.strokeStyle = "#E0405A"; g.lineWidth = R * 0.08
        g.beginPath(); g.moveTo(B.x - nx * R * 0.14, B.y - ny * R * 0.14); g.lineTo(B.x + nx * R * 0.14, B.y + ny * R * 0.14); g.stroke()
    }

    // the favourite thing of each, about `s` across, drawn around the origin
    function paintFav(g, s) {
        const f = who.fav, TAU = 2 * Math.PI
        g.lineCap = "round"; g.lineJoin = "round"
        if (f === "leek") {
            g.strokeStyle = "#F4F7EE"; g.lineWidth = s * 0.34; g.beginPath(); g.moveTo(0, s); g.lineTo(0, 0); g.stroke()
            g.strokeStyle = "#5CB848"; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -s * 0.6); g.stroke()
            g.lineWidth = s * 0.26; g.beginPath(); g.moveTo(0, -s * 0.5); g.lineTo(-s * 0.45, -s * 1.1); g.moveTo(0, -s * 0.5); g.lineTo(s * 0.45, -s * 1.05); g.stroke()
        } else if (f === "orange") {
            g.fillStyle = "#FF9F1C"; g.beginPath(); g.arc(0, 0, s * 0.8, 0, TAU, false); g.fill()
            g.fillStyle = "rgba(255,255,255,0.45)"; g.beginPath(); g.arc(-s * 0.28, -s * 0.3, s * 0.2, 0, TAU, false); g.fill()
            g.fillStyle = "#5CB848"; g.beginPath(); ell(g, s * 0.2, -s * 0.85, s * 0.34, s * 0.16); g.fill()
        } else if (f === "tuna") {
            g.fillStyle = "#5B8FB9"; g.beginPath(); ell(g, 0, 0, s, s * 0.5); g.fill()
            g.beginPath(); g.moveTo(s * 0.8, 0); g.lineTo(s * 1.5, -s * 0.5); g.lineTo(s * 1.5, s * 0.5); g.closePath(); g.fill()
            g.fillStyle = "#DCEAF5"; g.beginPath(); ell(g, -s * 0.1, s * 0.16, s * 0.7, s * 0.2); g.fill()
            g.fillStyle = "#12383A"; g.beginPath(); g.arc(-s * 0.6, -s * 0.1, s * 0.09, 0, TAU, false); g.fill()
        } else if (f === "zunda") { // zunda mochi: a white rice cake under green bean paste
            g.fillStyle = "#F7F3EA"; g.beginPath(); ell(g, 0, s * 0.2, s * 0.9, s * 0.6); g.fill()
            g.fillStyle = "#9CCB4A"; g.beginPath(); ell(g, 0, -s * 0.15, s * 0.75, s * 0.45); g.fill()
            g.fillStyle = "rgba(255,255,255,0.4)"; g.beginPath(); g.arc(-s * 0.25, -s * 0.3, s * 0.14, 0, TAU, false); g.fill()
        } else { // Teto's baguette
            g.strokeStyle = "#D9A05B"; g.lineWidth = s * 0.6; g.beginPath(); g.moveTo(-s, s * 0.4); g.lineTo(s, -s * 0.4); g.stroke()
            g.strokeStyle = "#9A6B33"; g.lineWidth = s * 0.1
            for (const u of [-0.5, 0, 0.5]) { g.beginPath(); g.moveTo(u * s - s * 0.12, -u * s * 0.4 - s * 0.16); g.lineTo(u * s + s * 0.12, -u * s * 0.4 + s * 0.12); g.stroke() }
        }
    }

    function paintParts(g) {
        const TAU = 2 * Math.PI
        for (const p of st.parts) {
            const u = p.life / p.max, a = u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85, sz = p.size * (0.7 + u * 0.5)
            g.save(); g.globalAlpha = clampv(a, 0, 1); g.translate(p.x, p.y); g.rotate(p.rot)
            if (p.type === "heart") heartShape(g, 0, 0, sz, "#FF4D6D")
            if (p.type === "fav")   paintFav(g, p.size)
            if (p.type === "spark") { g.fillStyle = p.hue; g.beginPath(); for (let i = 0; i < 8; i++) { const r = i % 2 ? sz * 0.25 : sz, q = i / 8 * TAU; if (i) g.lineTo(Math.cos(q) * r, Math.sin(q) * r); else g.moveTo(Math.cos(q) * r, Math.sin(q) * r) } g.closePath(); g.fill() }
            if (p.type === "drop")  { g.fillStyle = "#8FD8FF"; g.beginPath(); g.moveTo(0, -sz); g.quadraticCurveTo(sz, sz * 0.5, 0, sz); g.quadraticCurveTo(-sz, sz * 0.5, 0, -sz); g.fill() }
            if (p.type === "dust")  { g.fillStyle = "#D8D2DC"; g.beginPath(); g.arc(0, 0, sz, 0, TAU, false); g.fill() }
            if (p.type === "z")     { g.fillStyle = "#C9D4E0"; g.font = "bold " + Math.round(sz) + "px sans-serif"; g.fillText("z", 0, 0) }
            if (p.type === "note")  {
                g.fillStyle = p.hue; g.strokeStyle = p.hue; g.lineWidth = sz * 0.12
                g.beginPath(); ell(g, 0, 0, sz * 0.3, sz * 0.22); g.fill()
                g.beginPath(); g.moveTo(sz * 0.26, 0); g.lineTo(sz * 0.26, -sz * 0.9); g.lineTo(sz * 0.7, -sz * 0.7); g.stroke()
            }
            g.restore()
        }
    }

    function paintBadge(g, P, b, col) {
        const R = cR, x = P.x + R * 1.0, y = P.y - R * 1.12, TAU = 2 * Math.PI
        if (b === "done") { g.fillStyle = col; g.beginPath(); g.arc(x, y, R * 0.15, 0, TAU, false); g.fill(); return }
        const w = b === "dots" ? R * 0.62 : R * 0.4
        g.fillStyle = "#ffffff"; rr(g, x - w / 2, y - R * 0.2, w, R * 0.4, R * 0.2); g.fill()
        g.fillStyle = col
        if (b === "dots") {
            for (let i = 0; i < 3; i++) { const u = Math.max(0, Math.sin(st.t * 6 - i * 0.9)); g.beginPath(); g.arc(x + (i - 1) * R * 0.16, y - u * R * 0.07, R * 0.05, 0, TAU, false); g.fill() }
        } else {
            g.font = "bold " + Math.round(R * 0.34) + "px sans-serif"; g.textAlign = "center"; g.textBaseline = "middle"; g.fillText(b, x, y + R * 0.02)
        }
    }
}
