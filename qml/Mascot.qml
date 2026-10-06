// The mascot: a mochi-shaped Hatsune Miku. A rounded square with teal twin tails on
// springs, a headset whose light takes the mood's colour, and two small hands in her
// detached sleeves. Drawn in code on one Canvas (see miku-mochi.html for the prototype
// this was ported from); nothing here is a bitmap.
//
// The interface is the one the island was built around: `size` is the box she is laid
// out in. At the bar's size her tails are short and she is clipped to the bar's
// thickness (nothing reaches out of the bar); as the card opens the clip relaxes, the
// tails grow to their length and the hands come out
//   detail = clamp((size - 44) / 66, 0, 1)
//
// Moods: idle think work alert wow happy sad sleep dizzy walk. The Island (via the Hub)
// decides the mood; on top of it come short emotes of her own: a wave when the card
// first opens, hearts when the pointer rests on her, a sulk after a click, a start when
// she is picked up.
import QtQuick
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
    property bool doneBadge: false        // keep the mint badge for 25 s after a task
    property bool eyesShut: false         // first launch: the eyes open with one blink when released
    property real leafScale: 1            // first launch: the tails grow from their ties
    property bool paused: false           // out of sight: nothing is simulated or painted

    // ---- dragging (motion.md, "Dragging, edges and monitors") ----------------------
    property bool dragging: false         // picked up: no ground shadow, leans, the tails trail
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

    // ---- mood, and the emote on top of it ----------------------------------------
    property bool dizzyOverride: false
    readonly property string m: dizzyOverride ? "dizzy" : mood
    property string emote: ""
    Timer { id: emoteTimer; onTriggered: root.emote = "" }
    function play(name, ms) { emote = name; emoteTimer.interval = ms; emoteTimer.restart(); if (name !== "hello") st.sqv -= 2.5 }

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

    // a wave when the card first opens, and not again for a minute
    property double wavedAt: 0
    onDetailChanged: if (detail > 0.9 && m === "idle" && emote === "" && Date.now() - wavedAt > 60000) { wavedAt = Date.now(); play("hello", 1900) }

    // the pointer resting on her for two seconds
    onLookAtChanged: stillTimer.restart()
    Timer {
        id: stillTimer
        interval: 1900
        running: root.looking && root.detail > 0.5 && !root.dragging
        onTriggered: if (root.emote === "" && (root.m === "idle" || root.m === "walk")) { root.play("love", 2400); Sfx.play("hover") }
    }

    // ---- one-shot moves the island asks for --------------------------------------
    function blinkNow() { st.blink = 1 }
    function compress() { st.sqv += 4 }
    function land() { st.sqv += 6 }
    function hang() { st.swing = 1 }
    function jump(power, force) {
        if (Theme.reduced) return
        if (!force && st.jump < 0) return
        st.jumpV = -9 * Math.sqrt(Math.max(0.1, power))
    }
    function roll(turns, ms) { if (Theme.reduced) return; st.rollT = 0; st.rollTurns = turns; st.rollMs = ms }
    function celebrate(power) { jump(power); celebrating = true; celebrateTimer.restart() }
    Timer { id: celebrateTimer; interval: 1500; onTriggered: root.celebrating = false }

    // a click is a slap: she sulks. Three within 1.7 s and her head spins.
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
            st.sqv += 9
            play("annoyed", 900)
            Sfx.play("click")
        }
        root.clicked()
    }

    // ---- what each mood and emote looks like ---------------------------------------
    readonly property var looks: ({
        idle:  { color: "#39C5BB", eyes: "normal", mouth: "smile", hands: "rest" },
        walk:  { color: "#39C5BB", eyes: "normal", mouth: "smile", hands: "rest", sway: true },
        think: { color: "#8B5CF6", eyes: "normal", mouth: "flat",  hands: "chin", badge: "dots", look: [0.6, -0.7] },
        work:  { color: "#3B9EFF", eyes: "normal", mouth: "smile", hands: "typing", badge: "dots", look: [0, 0.7] },
        alert: { color: "#F5A524", eyes: "big",    mouth: "open",  hands: "wave2", badge: "!", hop: true },
        wow:   { color: "#22D3EE", eyes: "big",    mouth: "o",     hands: "wide" },
        happy: { color: "#34D399", eyes: "happy",  mouth: "open",  hands: "cheer", fx: "spark" },
        sad:   { color: "#F4505E", eyes: "tired",  mouth: "wavy",  hands: "droop", fx: "sweat" },
        sleep: { color: "#94A3B8", eyes: "closed", mouth: "flat",  hands: "tucked", fx: "zzz", slow: true },
        dizzy: { color: "#F472B6", eyes: "spiral", mouth: "wavy",  hands: "flail", wobble: true }
    })
    readonly property var emotes: ({
        hello:     { eyes: "happy", mouth: "open",  hands: "hello" },
        love:      { eyes: "heart", mouth: "smile", hands: "heart", fx: "heart", blush: 1 },
        surprised: { eyes: "dots",  mouth: "o",     hands: "wide" },
        annoyed:   { eyes: "slit",  mouth: "flat",  hands: "hips", color: "#A855F7" }
    })
    function look() {
        const a = looks[m] || looks.idle, e = emotes[emote]
        return e ? Object.assign({}, a, e) : a
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
        cling:  t => [{ x: -0.6, y: -1.02 }, { x: 0.6, y: -1.02 }]
    })

    // ---- the simulation's state (plain JS, not bindings: it changes every frame) -----
    property var st: ({
        t: Math.random() * 10, last: 0, gx: 0, gy: 0, blink: 0, nextBlink: 2, blinks: 0,
        sq: 0, sqv: 0, jump: 0, jumpV: 0, rollT: 1, rollTurns: 1, rollMs: 950, shake: 0, swing: 0,
        lean: 0, blush: 0.4, fxClock: 0, parts: [], tails: null,
        hand: [{ x: -1.38, y: 0.52 }, { x: 1.38, y: 0.52 }]
    })

    // The canvas is as big as she ever gets (the 120 px box, with room for tails, hands
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
            scale: root.k
            antialiasing: true
            onPaint: root.paint(getContext("2d"))
        }
    }

    Timer {
        // the bar's mini has little to show: 20 frames a second are plenty there
        interval: root.detail > 0 || root.dragging ? 16 : 50
        running: root.visible && !root.paused
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
    readonly property string hair: skin === "github" ? "#8b949e" : "#39C5BB"
    readonly property string hairD: skin === "github" ? "#57606a" : "#22968E"
    readonly property string hairTop: skin === "github" ? "#b1bac4" : "#55DACF"

    function clampv(v, a, b) { return Math.max(a, Math.min(b, v)) }
    function easeOut(u) { return 1 - Math.pow(1 - clampv(u, 0, 1), 3) }
    function rgba(hex, a) {
        return "rgba(" + parseInt(hex.substr(1, 2), 16) + "," + parseInt(hex.substr(3, 2), 16) + "," + parseInt(hex.substr(5, 2), 16) + "," + a + ")"
    }

    // the body's pose this frame: centre, angle and stretch
    function pose() {
        const s = st, L = look(), R = cR, t = s.t
        let y = cY + s.jump * R * 0.1
        let x = cX + Math.sin(t * 40) * s.shake * R * 0.12
        if (L.hop && !Theme.reduced) { const u = (t * 1.25) % 1; if (u < 0.5) y -= Math.sin(u * 2 * Math.PI) * R * 0.3 }
        if (L.sway && !Theme.reduced) y -= Math.abs(Math.sin(t * 6)) * R * 0.1
        const breathe = Theme.reduced ? 0 : Math.sin(t * (L.slow ? 1.6 : 2.4)) * (L.slow ? 0.035 : 0.018)
        const speed = dragging && !Theme.reduced ? Math.min(1, Math.hypot(dragVx, dragVy) / 1000) * 0.08 : 0
        const side = Math.abs(dragVx) >= Math.abs(dragVy)
        const sx = (1 + s.sq * 0.06 - breathe * 0.6) * (1 - wallX) * (side ? 1 + speed : 1 - speed * 0.5)
        const sy = (1 - s.sq * 0.06 + breathe) * (1 - wallY) * (side ? 1 - speed * 0.5 : 1 + speed)
        const turning = s.rollT < 1 ? easeOut(s.rollT) * 2 * Math.PI * s.rollTurns : 0
        return { x: x, y: y, sx: sx, sy: sy, angle: s.lean + turning + inwardTilt * Math.PI / 180 }
    }
    function toWorld(P, lx, ly) {
        const x = lx * cR * P.sx, y = ly * cR * P.sy, c = Math.cos(P.angle), s = Math.sin(P.angle)
        return { x: P.x + x * c - y * s, y: P.y + x * s + y * c }
    }

    function step(dt) {
        const s = st, L = look(), R = cR
        s.t += dt * (L.slow ? 0.6 : 1)

        // gaze: at the pointer, at the wall's far side, or wherever the mood looks
        let tx = 0, ty = 0
        if (gazeOn) { tx = gaze.x; ty = gaze.y }
        else if (L.look) { tx = L.look[0]; ty = L.look[1] }
        else if (m === "walk") { tx = walkDir * 0.8 }
        else if (looking) { tx = Math.tanh((lookAt.x - width / 2) / (size * 0.9)); ty = Math.tanh((lookAt.y - height / 2) / (size * 0.7)) }
        if (L.eyes === "closed" || L.eyes === "spiral") { tx = 0; ty = 0.2 }
        const kk = 1 - Math.exp(-dt * 9)
        s.gx += (tx - s.gx) * kk; s.gy += (ty - s.gy) * kk

        s.nextBlink -= dt
        if (s.nextBlink <= 0) { s.blink = 1; s.blinks = Math.random() < 0.22 ? 1 : 0; s.nextBlink = 2.2 + Math.random() * 3.2 }
        if (s.blink > 0) { s.blink -= dt / 0.13; if (s.blink <= 0 && s.blinks) { s.blinks = 0; s.blink = 1 } }

        s.sqv += (-s.sq * 190 - s.sqv * 13) * dt; s.sq += s.sqv * dt
        if (s.jump < 0 || s.jumpV < 0) { s.jumpV += 38 * dt; s.jump += s.jumpV * dt; if (s.jump >= 0) { s.jump = 0; s.jumpV = 0; s.sqv += 5 } }
        if (s.rollT < 1) s.rollT = Math.min(1, s.rollT + dt * 1000 / s.rollMs)
        s.shake = Math.max(0, s.shake - dt * 2.2)
        s.swing = Math.max(0, s.swing - dt * 1.2)
        const carried = dragging ? clampv(dragVx / 40, -14, 14) * Math.PI / 180 : 0
        const want = carried + (L.wobble ? Math.sin(s.t * 3.1) * 0.12 : 0) + (L.sway ? Math.sin(s.t * 6) * 0.07 * walkDir : 0)
                   + (m === "think" ? 0.1 : 0) + Math.sin(s.t * 7) * s.swing * 0.25
        s.lean += (want - s.lean) * (1 - Math.exp(-dt * 8))
        s.blush += (((L.blush || 0.4) + (looking ? 0.15 : 0)) - s.blush) * (1 - Math.exp(-dt * 6))

        const fn = poses[dragging ? "cling" : (L.hands || "rest")] || poses.rest
        const p = fn(s.t), hk = 1 - Math.exp(-dt * 14)
        for (let i = 0; i < 2; i++) { s.hand[i].x += (p[i].x - s.hand[i].x) * hk; s.hand[i].y += (p[i].y - s.hand[i].y) * hk }

        simTails(dt)
        spawn(dt, L)
        for (const q of s.parts) { q.life += dt; q.x += q.vx * dt; q.y += q.vy * dt; q.vy += (q.g || 0) * dt; q.rot += (q.vr || 0) * dt }
        s.parts = s.parts.filter(q => q.life < q.max)
    }

    // Two chains of points on springs. The item itself is what moves on the screen while
    // she is carried, so the drag's velocity is fed in as a wind that blows them back.
    function simTails(dt) {
        const s = st, P = pose(), R = cR, n = 6
        // short tails in the bar, so that they end inside it; full length on the card
        const seg = R * 0.36 * Math.max(0.15, leafScale) * (0.42 + 0.58 * detail)
        if (!s.tails) s.tails = [{ side: -1, p: [] }, { side: 1, p: [] }]
        const wx = dragging ? clampv(-dragVx / k, -2600, 2600) : 0, wy = dragging ? clampv(-dragVy / k, -2600, 2600) : 0
        for (const T of s.tails) {
            const a = toWorld(P, T.side * 1.0, -0.74), p = T.p
            if (p.length === 0) for (let i = 0; i < n; i++) p.push({ x: a.x + T.side * i * seg * 0.35, y: a.y + i * seg * 0.93, px: a.x + T.side * i * seg * 0.35, py: a.y + i * seg * 0.93 })
            p[0].x = a.x; p[0].y = a.y
            for (let i = 1; i < n; i++) {
                const q = p[i], vx = (q.x - q.px) * 0.94, vy = (q.y - q.py) * 0.94
                q.px = q.x; q.py = q.y
                q.x += vx + (T.side * R * 5 * (1 - i / n) + wx * 0.5) * dt * dt
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
        if (fx === "" || detail < 0.5 || Theme.reduced) return
        s.fxClock -= dt; if (s.fxClock > 0) return
        const R = cR, P = pose(), r = () => Math.random() - 0.5
        const add = o => s.parts.push(Object.assign({ life: 0, rot: 0, x: P.x, y: P.y }, o))
        if (fx === "heart") { s.fxClock = 0.22; add({ type: "heart", x: P.x + r() * R * 1.6, y: P.y - R * 0.5, vx: r() * R * 0.4, vy: -R * 1.5, max: 1.3, size: R * (0.16 + Math.random() * 0.12) }) }
        if (fx === "spark") { s.fxClock = 0.09; add({ type: "spark", x: P.x + r() * R * 3, y: P.y + r() * R * 2.4, vx: 0, vy: -R * 0.3, max: 0.7, size: R * (0.1 + Math.random() * 0.14), hue: Math.random() < 0.5 ? "#34D399" : "#FFFFFF" }) }
        if (fx === "sweat") { s.fxClock = 0.5; const d = Math.random() < 0.5 ? -1 : 1; add({ type: "drop", x: P.x + d * R * 0.95, y: P.y - R * 0.55, vx: d * R * 0.5, vy: -R * 0.6, g: R * 4, max: 0.8, size: R * 0.11 }) }
        if (fx === "zzz") { s.fxClock = 0.8; add({ type: "z", x: P.x + R * 0.8, y: P.y - R * 0.8, vx: R * 0.3, vy: -R * 0.6, max: 1.9, size: R * 0.24 }) }
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
        const R = cR, rx = 1.1 * R, ry = 0.96 * R, e = 2 / 4.6 // a rounded square, not a ball
        g.beginPath()
        for (let i = 0; i <= 64; i++) {
            const a = i / 64 * 2 * Math.PI, c = Math.cos(a), s = Math.sin(a)
            const x = Math.sign(c) * Math.pow(Math.abs(c), e) * rx, y = Math.sign(s) * Math.pow(Math.abs(s), e) * ry + R * 0.04
            if (i) g.lineTo(x, y); else g.moveTo(x, y)
        }
        g.closePath()
    }

    function paint(g) {
        g.reset()
        const s = st, R = cR, L = look(), P = pose(), col = L.color, TAU = 2 * Math.PI
        if (!s.tails) return

        if (detail > 0.05) {
            const gl = g.createRadialGradient(P.x, P.y, R * 0.4, P.x, P.y, R * 2.5)
            gl.addColorStop(0, rgba(col, 0.3 * detail)); gl.addColorStop(1, rgba(col, 0))
            g.fillStyle = gl; g.fillRect(0, 0, 288, 288)
            if (!dragging) { g.fillStyle = "rgba(0,0,0," + 0.25 * detail + ")"; g.beginPath(); ell(g, cX, cY + R * 1.02, R * 0.95, R * 0.12); g.fill() }
        }

        for (const T of s.tails) paintTail(g, T)

        g.save(); g.translate(P.x, P.y); g.rotate(P.angle); g.scale(P.sx, P.sy)
        paintBody(g, L)
        g.restore()

        for (const T of s.tails) { // the ties sit on the tails' roots, over the body's corners
            const a = T.p[0]; g.save(); g.translate(a.x, a.y); g.rotate(P.angle + T.side * 0.5)
            g.fillStyle = "#1b1f25"; rr(g, -R * 0.2, -R * 0.14, R * 0.4, R * 0.28, R * 0.06); g.fill()
            g.fillStyle = "#E12885"; g.fillRect(-R * 0.2, -R * 0.03, R * 0.4, R * 0.06); g.restore()
        }

        if (detail > 0.25) { g.globalAlpha = clampv((detail - 0.25) / 0.4, 0, 1); paintHands(g, P, L); g.globalAlpha = 1 }
        paintParts(g)
        const badge = L.badge || (doneBadge ? "done" : "")
        if (badge !== "") paintBadge(g, P, badge, badge === "done" ? "#34D399" : col)
    }

    function paintTail(g, T) {
        const R = cR, p = T.p, n = p.length, W = [0.2, 0.33, 0.36, 0.32, 0.22, 0.05], Lp = [], Rp = []
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

    function paintBody(g, L) {
        const s = st, R = cR, TAU = 2 * Math.PI
        g.save(); g.translate(0, -R * 0.07); g.scale(1.07, 1.03); bodyPath(g); g.fillStyle = hairD; g.fill(); g.restore()

        bodyPath(g)
        const sk = g.createLinearGradient(R, -R, -R, R); sk.addColorStop(0, "#FFF6EE"); sk.addColorStop(1, "#E9D3C6")
        g.fillStyle = sk; g.fill()
        g.save(); bodyPath(g); g.clip()

        // outfit: grey vest, collar and the teal tie
        g.fillStyle = "#C6CFD6"; g.beginPath(); g.moveTo(-R * 1.3, R * 0.62); g.quadraticCurveTo(0, R * 0.5, R * 1.3, R * 0.62); g.lineTo(R * 1.3, R * 1.2); g.lineTo(-R * 1.3, R * 1.2); g.fill()
        g.fillStyle = hair; g.fillRect(-R * 1.3, R * 0.9, R * 2.6, R * 0.05)
        g.fillStyle = "#EEF2F5"
        g.beginPath(); g.moveTo(0, R * 0.6); g.lineTo(-R * 0.34, R * 0.56); g.lineTo(-R * 0.18, R * 0.76); g.fill()
        g.beginPath(); g.moveTo(0, R * 0.6); g.lineTo(R * 0.34, R * 0.56); g.lineTo(R * 0.18, R * 0.76); g.fill()
        g.fillStyle = skin === "github" ? "#8b949e" : "#2FB9AF"
        g.beginPath(); g.moveTo(0, R * 0.6); g.lineTo(R * 0.09, R * 0.68); g.lineTo(R * 0.13, R * 0.98); g.lineTo(-R * 0.13, R * 0.98); g.lineTo(-R * 0.09, R * 0.68); g.fill()

        // side locks in front of the ears
        for (const d of [-1, 1]) { g.fillStyle = hair; g.beginPath(); g.moveTo(d * R * 1.2, -R * 0.4); g.quadraticCurveTo(d * R * 0.86, 0, d * R * 1.0, R * 0.48); g.quadraticCurveTo(d * R * 1.12, R * 0.2, d * R * 1.2, R * 0.5); g.fill() }

        // fringe
        const hg = g.createLinearGradient(0, -R, 0, 0); hg.addColorStop(0, hairTop); hg.addColorStop(1, hair)
        g.fillStyle = hg; g.beginPath(); g.moveTo(-R * 1.3, -R * 1.1); g.lineTo(R * 1.3, -R * 1.1); g.lineTo(R * 1.3, -R * 0.12)
        const B = [[1.0, -0.04], [0.74, -0.34], [0.5, 0.0], [0.24, -0.38], [0.02, -0.03], [-0.26, -0.38], [-0.5, 0.0], [-0.74, -0.34], [-1.0, -0.04]]
        for (let i = 0; i < B.length; i++) { const p = B[i], q = B[i + 1] || [-1.3, -0.12]; g.quadraticCurveTo(p[0] * R, p[1] * R, (p[0] + q[0]) / 2 * R, (p[1] + q[1]) / 2 * R) }
        g.lineTo(-R * 1.3, -R * 0.12); g.closePath(); g.fill()
        g.strokeStyle = "rgba(255,255,255,0.4)"; g.lineWidth = R * 0.07; g.lineCap = "round"
        g.beginPath(); g.arc(0, R * 0.25, R * 0.98, -Math.PI * 0.78, -Math.PI * 0.55, false); g.stroke()
        g.beginPath(); g.arc(0, R * 0.25, R * 0.98, -Math.PI * 0.42, -Math.PI * 0.34, false); g.stroke()

        const sh = g.createRadialGradient(R * 0.2, -R * 0.2, R * 0.5, 0, 0, R * 1.35); sh.addColorStop(0, "rgba(0,0,0,0)"); sh.addColorStop(1, "rgba(0,20,30,0.2)")
        g.fillStyle = sh; g.fillRect(-R * 1.4, -R * 1.2, R * 2.8, R * 2.4)
        g.restore()

        // face
        const fx = s.gx * R * 0.15, fy = s.gy * R * 0.1
        g.fillStyle = "rgba(255,110,150," + 0.55 * s.blush + ")"
        for (const d of [-1, 1]) { g.beginPath(); ell(g, d * R * 0.72 + fx, R * 0.38 + fy, R * 0.17, R * 0.1); g.fill() }
        paintEyes(g, L, fx, fy)
        paintMouth(g, L, fx * 0.8, fy)

        // headset: the ear piece carries the mood's light, the boom ends in a pink tip
        g.fillStyle = "#1b1f25"; g.beginPath(); ell(g, -R * 1.1, R * 0.02, R * 0.14, R * 0.24); g.fill()
        g.strokeStyle = L.color; g.lineWidth = R * 0.045; g.beginPath(); ell(g, -R * 1.1, R * 0.02, R * 0.07, R * 0.15); g.stroke()
        g.strokeStyle = "#1b1f25"; g.lineWidth = R * 0.045; g.beginPath(); g.moveTo(-R * 1.08, R * 0.22); g.quadraticCurveTo(-R * 0.95, R * 0.6, -R * 0.5 + fx * 0.5, R * 0.56); g.stroke()
        g.fillStyle = "#E12885"; g.beginPath(); g.arc(-R * 0.5 + fx * 0.5, R * 0.56, R * 0.055, 0, TAU, false); g.fill()
    }

    function paintEyes(g, L, fx, fy) {
        const s = st, R = cR, t = s.t, TAU = 2 * Math.PI, INK = "#12383A"
        const type = eyesShut ? "closed" : L.eyes
        const soft = type === "normal" || type === "big" || type === "tired"
        const open = soft ? clampv(1 - Math.max(0, s.blink), 0.08, 1) : 1
        // the mini in the bar has a handful of pixels for a face: bigger, simpler eyes
        const kk = (type === "big" ? 1.2 : 1) * (looking ? 1.08 : 1) * (1 + (1 - detail) * 0.35)
        for (const d of [-1, 1]) {
            const x = d * R * 0.44 + fx, y = R * 0.1 + fy, w = R * 0.15 * kk, h = R * 0.2 * kk
            g.lineCap = "round"; g.lineJoin = "round"
            if (soft) {
                const hh = h * open * (type === "tired" ? 0.62 : 1)
                const eg = g.createLinearGradient(0, y - hh, 0, y + hh); eg.addColorStop(0, "#0B3F45"); eg.addColorStop(0.55, "#1C9C97"); eg.addColorStop(1, "#63E6DB")
                g.fillStyle = eg; g.beginPath(); ell(g, x, y, w, hh); g.fill()
                if (open > 0.5) {
                    g.fillStyle = "#062226"; g.beginPath(); ell(g, x + fx * 0.12, y, w * 0.45, hh * 0.5); g.fill()
                    g.fillStyle = "#ffffff"; g.beginPath(); g.arc(x - w * 0.35, y - hh * 0.45, w * 0.3, 0, TAU, false); g.fill()
                    g.beginPath(); g.arc(x + w * 0.4, y + hh * 0.4, w * 0.15, 0, TAU, false); g.fill()
                }
                g.strokeStyle = INK; g.lineWidth = R * 0.055; g.beginPath(); ell(g, x, y, w * 1.08, hh * 1.05, Math.PI * 1.1, Math.PI * 1.9); g.stroke()
                g.beginPath(); g.moveTo(x + d * w * 1.0, y - hh * 0.55); g.lineTo(x + d * w * 1.45, y - hh * 0.85); g.stroke()
                if (type === "tired") { g.beginPath(); g.moveTo(x - w * 1.1, y - hh * 0.9); g.lineTo(x + w * 1.1, y - hh * 0.9); g.stroke() }
                continue
            }
            g.strokeStyle = INK; g.fillStyle = INK; g.lineWidth = R * 0.07
            if (type === "happy")  { g.beginPath(); g.arc(x, y + h * 0.35, w * 1.05, Math.PI * 1.12, Math.PI * 1.88, false); g.stroke() }
            if (type === "closed") { g.beginPath(); g.arc(x, y - h * 0.3, w * 1.05, Math.PI * 0.14, Math.PI * 0.86, false); g.stroke() }
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
        const R = cR, t = st.t, x = fx, y = R * 0.46 + fy, mo = L.mouth, TAU = 2 * Math.PI
        g.strokeStyle = "#12383A"; g.fillStyle = "#7A2137"; g.lineWidth = R * 0.05; g.lineCap = "round"
        if (mo === "smile") { g.beginPath(); g.arc(x, y - R * 0.06, R * 0.13, Math.PI * 0.18, Math.PI * 0.82, false); g.stroke() }
        if (mo === "flat")  { g.beginPath(); g.moveTo(x - R * 0.08, y); g.lineTo(x + R * 0.08, y); g.stroke() }
        if (mo === "o")     { g.beginPath(); ell(g, x, y, R * 0.06, R * 0.075); g.fill() }
        if (mo === "wavy")  { g.beginPath(); for (let i = 0; i <= 12; i++) { const px = x + (i / 12 - 0.5) * R * 0.34, py = y + Math.sin(i * 1.4 + t * 6) * R * 0.03; if (i) g.lineTo(px, py); else g.moveTo(px, py) } g.stroke() }
        if (mo === "open")  {
            g.beginPath(); g.arc(x, y - R * 0.05, R * 0.14, 0, Math.PI, false); g.closePath(); g.fill()
            g.fillStyle = "#FF8FA8"; g.beginPath(); ell(g, x, y + R * 0.06, R * 0.07, R * 0.035); g.fill()
        }
    }

    function paintHands(g, P, L) {
        const s = st, R = cR, TAU = 2 * Math.PI
        for (let i = 0; i < 2; i++) {
            const h = toWorld(P, s.hand[i].x, s.hand[i].y), sh = toWorld(P, (i ? 1 : -1) * 0.9, 0.5)
            g.save(); g.translate(h.x, h.y); g.rotate(Math.atan2(h.y - sh.y, h.x - sh.x))
            // her detached sleeve: flared toward the hand, teal trim at the cuff
            g.fillStyle = "#2B3138"; g.beginPath(); g.moveTo(-R * 0.3, -R * 0.08); g.lineTo(-R * 0.03, -R * 0.15); g.lineTo(-R * 0.03, R * 0.15); g.lineTo(-R * 0.3, R * 0.08); g.closePath(); g.fill()
            g.fillStyle = hair; g.fillRect(-R * 0.08, -R * 0.15, R * 0.05, R * 0.3)
            g.fillStyle = "#E12885"; g.fillRect(-R * 0.22, -R * 0.03, R * 0.07, R * 0.06)
            const hg = g.createRadialGradient(R * 0.08, -R * 0.05, R * 0.02, R * 0.1, 0, R * 0.2); hg.addColorStop(0, "#FFF6EE"); hg.addColorStop(1, "#E9D3C6")
            g.fillStyle = hg; g.beginPath(); g.arc(R * 0.09, 0, R * 0.15, 0, TAU, false); g.fill()
            g.restore()
        }
        if (L.hands === "heart" && !dragging) { // the heart the two hands hold between them
            const c = toWorld(P, 0, 0.8); heartShape(g, c.x, c.y - R * 0.08, R * (0.2 + Math.sin(s.t * 8) * 0.02), "#FF4D6D")
        }
    }

    function paintParts(g) {
        const TAU = 2 * Math.PI
        for (const p of st.parts) {
            const u = p.life / p.max, a = u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85, sz = p.size * (0.7 + u * 0.5)
            g.save(); g.globalAlpha = clampv(a, 0, 1); g.translate(p.x, p.y); g.rotate(p.rot)
            if (p.type === "heart") heartShape(g, 0, 0, sz, "#FF4D6D")
            if (p.type === "spark") { g.fillStyle = p.hue; g.beginPath(); for (let i = 0; i < 8; i++) { const r = i % 2 ? sz * 0.25 : sz, q = i / 8 * TAU; if (i) g.lineTo(Math.cos(q) * r, Math.sin(q) * r); else g.moveTo(Math.cos(q) * r, Math.sin(q) * r) } g.closePath(); g.fill() }
            if (p.type === "drop")  { g.fillStyle = "#8FD8FF"; g.beginPath(); g.moveTo(0, -sz); g.quadraticCurveTo(sz, sz * 0.5, 0, sz); g.quadraticCurveTo(-sz, sz * 0.5, 0, -sz); g.fill() }
            if (p.type === "z")     { g.fillStyle = "#C9D4E0"; g.font = "bold " + Math.round(sz) + "px sans-serif"; g.fillText("z", 0, 0) }
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
