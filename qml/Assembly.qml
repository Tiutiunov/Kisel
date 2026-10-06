// The first launch: "the assembly" (motion.md, "The assembly"). Nothing shrinks
// away: every cover shape becomes a real part of the interface.
//
//   A  200-1100  the cover drops in (half size), staggered 60 ms, a 6 % squash on landing
//   B 1100-1600  the cover moment: hold and bob 2 px, phases offset
//   C 1600-2250  the island is born: the amber half-round flattens into the pill and
//                turns near-black; the mint disc flies into the leaf spot
//   D 2250-3200  the unfold: the island opens and the five remaining shapes fly on
//                arcs (480 ms, staggered 40 ms) and morph (360 ms OutBack):
//                big pill -> Kisel's body, soft disc -> its gloss, slab -> the hook
//                card, small pill -> the primary button, dot grid -> the launch tiles
//                (the spare dots twinkle around Kisel as sparkles)
//   E 3200-      settle: Kisel opens its eyes with one blink and jumps (0.6)
//
// Everything is a pure function of one clock, `t` (ms), so it can be skipped
// (a click snaps every shape to its final form in 120 ms) and can never be left
// at an intermediate size. With "reduce motion" it is not played at all: Home
// just fades in (Island).
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    anchors.fill: parent
    z: 20

    property real t: 0
    property bool running: false
    visible: running

    // Geometry, in surface coordinates. Island overrides these from its layout.
    property point centre: Qt.point(354, 92)               // where the cover sits
    property rect pill: Qt.rect(266, 0, 176, 44)           // the collapsed island
    property point leaf: Qt.point(305, 11)                 // the mini mascot's leaf spot
    property rect slot: Qt.rect(49, 48, 110, 110)          // Kisel's slot on Home
    property rect card: Qt.rect(174, 48, 494, 46)          // the hook card
    property rect button: Qt.rect(494, 53, 150, 36)        // its primary button
    property var tiles: []                                  // [{x, y, w, h, color}]

    // timeline
    readonly property int tBorn: 2220
    readonly property int tOpen: 2250
    readonly property int tSettle: 3200
    readonly property int tPulse: 3500
    readonly property int tClose: 6500
    readonly property int tEnd: 6600

    signal landed()
    signal born()
    signal unfold()
    signal settled()
    signal pulse()
    signal closeIsland()
    signal finished()

    // ---- the clock ----------------------------------------------------------------
    property real prevT: 0
    function crossed(x) { return prevT < x && t >= x }
    onTChanged: {
        if (!running) { prevT = t; return }
        if (crossed(460)) landed()
        if (crossed(tBorn)) born()
        if (crossed(tOpen)) unfold()
        if (crossed(tSettle)) settled()
        if (crossed(tPulse)) pulse()
        if (crossed(tClose)) closeIsland()
        if (crossed(tEnd)) { running = false; finished() }
        prevT = t
    }
    function play() {
        t = 0; prevT = -1
        running = true
        clock.from = 0; clock.to = tEnd; clock.duration = tEnd
        clock.restart()
    }
    // a click: snap every shape to its final form in 120 ms, then carry on to the end
    function skip() {
        if (!running || t >= tSettle) return
        clock.stop()
        skipAnim.from = t
        skipAnim.start()
    }
    function stop() { clock.stop(); skipAnim.stop(); running = false }
    NumberAnimation { id: clock; target: root; property: "t"; easing.type: Easing.Linear }
    NumberAnimation {
        id: skipAnim
        target: root; property: "t"; to: root.tSettle + 40; duration: 120; easing.type: Easing.OutCubic
        onFinished: { clock.from = root.t; clock.to = root.tEnd; clock.duration = root.tEnd - root.t; clock.start() }
    }

    // ---- what the real UI should show --------------------------------------------
    readonly property bool bodyArrived: t >= tSettle
    readonly property real revealCard: running ? seg(t, fs(2) + 830, 80) : 1
    readonly property real revealButton: running ? seg(t, fs(3) + 840, 200) : 1
    function revealTile(i) { return running ? seg(t, fs(4) + 480 + 80 * i, 200) : 1 }

    // ---- easing and helpers --------------------------------------------------------
    function c01(x) { return Math.max(0, Math.min(1, x)) }
    function seg(time, t0, d) { return c01((time - t0) / d) }
    function outBack(x) { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2) }
    function outCubic(x) { return 1 - Math.pow(1 - x, 3) }
    function inOutCubic(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2 }
    function mix(a, b, u) { return a + (b - a) * u }
    function mixColor(a, b, u) { return Qt.rgba(mix(a.r, b.r, u), mix(a.g, b.g, u), mix(a.b, b.b, u), mix(a.a, b.a, u)) }
    // a point on a quadratic curve whose control point sits 40 px above the straight line,
    // so the flight feels thrown, not slid
    function arc(u, a, b) {
        const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2 - 40
        const k = 1 - u
        return Qt.point(k * k * a.x + 2 * k * u * cx + u * u * b.x, k * k * a.y + 2 * k * u * cy + u * u * b.y)
    }
    function fs(k) { return tOpen + 40 * k }       // flight start of the k-th shape in phase D
    function fu(k) { return inOutCubic(seg(t, fs(k), 480)) }
    function mu(k) { return outBack(seg(t, fs(k) + 480, 360)) }

    // ---- phase A and B: the cover -----------------------------------------------
    readonly property real coverCx: 730
    readonly property real coverCy: 170
    function home(cx, cy) { return Qt.point(centre.x + (cx - coverCx) * 0.5, centre.y + (cy - coverCy) * 0.5) }
    // i: slab 0, half-round 1, big pill 2, disc 3, small pill 4, soft disc 5, dots 6
    function dropY(i) { return -60 * (1 - outBack(seg(t, 200 + 60 * i, 360))) }
    function dropOp(i) { return seg(t, 200 + 60 * i, 140) }
    function bobY(i) {
        const k = seg(t, 1100, 100) * (1 - seg(t, 1500, 100))
        return 2 * Math.sin(2 * Math.PI * (t - 1100) / 900 + i * 1.1) * k
    }
    // a 6 percent squash on landing (the slab is rigid)
    function squash(i) {
        if (i === 0) return 0
        const u = (t - (200 + 60 * i + 260)) / 120
        return u > 0 && u < 1 ? 0.06 * Math.sin(Math.PI * u) : 0
    }
    readonly property point hSlab: home(784, 244)
    readonly property point hHalf: home(860, 126)
    readonly property point hBig: home(620, 88)
    readonly property point hDisc: home(624, 212)
    readonly property point hSmall: home(532, 180)
    readonly property point hSoft: home(904, 236)
    readonly property point hDots: home(532, 252)

    // ---- slab -> the hook card -------------------------------------------------
    Rectangle {
        id: slab
        readonly property point target: Qt.point(root.card.x + root.card.width / 2, root.card.y + root.card.height / 2)
        readonly property point c: root.t < root.fs(2) ? Qt.point(root.hSlab.x, root.hSlab.y + root.dropY(0) + root.bobY(0))
                                                    : root.arc(root.fu(2), root.hSlab, target)
        readonly property real m: root.t < root.fs(2) + 480 ? 0 : root.mu(2)
        width: root.mix(72, root.card.width, m)
        height: root.mix(68, root.card.height, m)
        x: c.x - width / 2; y: c.y - height / 2
        radius: Theme.radiusMd
        color: root.mixColor(Theme.surface3, Theme.surface2, root.c01(m))
        opacity: root.dropOp(0) * (1 - root.revealCard)
        visible: opacity > 0.005
    }

    // ---- half-round -> the island pill (phase C) ---------------------------------
    Rectangle {
        id: halfRound
        readonly property real u: root.outBack(root.seg(root.t, 1600, 320))
        readonly property real x0: root.hHalf.x - 50
        readonly property real y0: root.hHalf.y - 25 + root.dropY(1) + root.bobY(1)
        x: root.mix(x0, root.pill.x, u)
        y: root.mix(y0, 0, u)
        width: root.mix(100, root.pill.width, u)
        height: root.mix(50, root.pill.height, u)
        topLeftRadius: 0; topRightRadius: 0
        bottomLeftRadius: root.mix(50, 22, u); bottomRightRadius: root.mix(50, 22, u)
        color: root.mixColor(Theme.amber, Theme.surface0, root.seg(root.t, 1760, 240))
        border.width: root.t >= 2000 ? 1 : 0
        border.color: Theme.line
        opacity: root.dropOp(1)
        visible: root.t < root.tBorn + 10 && opacity > 0.005
    }

    // ---- disc -> the status dot / the mini's leaf spot (phase C) ----------------
    Rectangle {
        readonly property real u: root.inOutCubic(root.seg(root.t, 1900, 320))
        readonly property point c: root.t < 1900 ? Qt.point(root.hDisc.x, root.hDisc.y + root.dropY(3) + root.bobY(3))
                                                 : root.arc(u, root.hDisc, root.leaf)
        readonly property real sc: root.t < 1900 ? 1 : 1 - u
        width: 56 * sc; height: width; radius: width / 2
        x: c.x - width / 2; y: c.y - height / 2
        color: Theme.mint
        opacity: root.dropOp(3)
        visible: root.t < 2230 && width > 0.5 && opacity > 0.005
    }

    // ---- big pill -> Kisel's body -----------------------------------------------
    Shape {
        id: body
        readonly property point tl0: Qt.point(root.hBig.x - 64, root.hBig.y - 64 + root.dropY(2) + root.bobY(2))
        readonly property point slotTL: Qt.point(root.slot.x, root.slot.y)
        readonly property point tl: root.t < root.fs(0) ? tl0 : root.arc(root.fu(0), tl0, slotTL)
        readonly property real sc: root.mix(1, root.slot.width / 128, root.t < root.fs(0) ? 0 : root.fu(0))
        readonly property real p: root.t < root.fs(0) + 480 ? 0 : root.mu(0)
        width: 128; height: 128
        x: tl.x; y: tl.y
        scale: sc * (1 + root.squash(2)) // a landing squash on the cover
        transformOrigin: Item.TopLeft
        opacity: root.dropOp(2)
        visible: !root.bodyArrived && opacity > 0.005
        preferredRendererType: Shape.CurveRenderer
        // the pill's outline is interpolated into the pudding silhouette (same five curves as the mark)
        readonly property var pillPts: [64,34, 104,34,124,46,124,64, 124,82,110,94,94,94, 76,94,52,94,34,94, 18,94,4,82,4,64, 4,46,24,34,64,34]
        readonly property var bodyPts: [64,24, 91,24,106,46,109,72, 111,94,117,112,100,118, 85,123,43,123,28,118, 11,112,17,94,19,72, 22,46,37,24,64,24]
        function v(i) { return pillPts[i] + (bodyPts[i] - pillPts[i]) * p }
        ShapePath {
            fillColor: Theme.kisel
            strokeColor: "transparent"
            startX: body.v(0); startY: body.v(1)
            PathCubic { control1X: body.v(2); control1Y: body.v(3); control2X: body.v(4); control2Y: body.v(5); x: body.v(6); y: body.v(7) }
            PathCubic { control1X: body.v(8); control1Y: body.v(9); control2X: body.v(10); control2Y: body.v(11); x: body.v(12); y: body.v(13) }
            PathCubic { control1X: body.v(14); control1Y: body.v(15); control2X: body.v(16); control2Y: body.v(17); x: body.v(18); y: body.v(19) }
            PathCubic { control1X: body.v(20); control1Y: body.v(21); control2X: body.v(22); control2Y: body.v(23); x: body.v(24); y: body.v(25) }
            PathCubic { control1X: body.v(26); control1Y: body.v(27); control2X: body.v(28); control2Y: body.v(29); x: body.v(30); y: body.v(31) }
        }
    }

    // ---- soft disc -> the gloss ----------------------------------------------------
    Rectangle {
        readonly property real k: root.slot.width / 128
        readonly property point target: Qt.point(root.slot.x + 45 * k, root.slot.y + 46 * k)
        readonly property point c: root.t < root.fs(1) ? Qt.point(root.hSoft.x, root.hSoft.y + root.dropY(5) + root.bobY(5))
                                                       : root.arc(root.fu(1), root.hSoft, target)
        readonly property real m: root.t < root.fs(1) + 480 ? 0 : root.mu(1)
        width: root.mix(40, 26 * k, m)
        height: root.mix(40, 14 * k, m)
        x: c.x - width / 2; y: c.y - height / 2
        radius: Math.min(width, height) / 2
        rotation: root.mix(0, -32, root.c01(m))
        color: root.mixColor(Theme.kiselSoft, "white", root.c01(m))
        opacity: root.dropOp(5) * root.mix(1, 0.44, root.c01(m))
        visible: !root.bodyArrived && opacity > 0.005
    }

    // ---- small pill -> the primary button -----------------------------------------
    Rectangle {
        readonly property point target: Qt.point(root.button.x + root.button.width / 2, root.button.y + root.button.height / 2)
        readonly property point c: root.t < root.fs(3) ? Qt.point(root.hSmall.x, root.hSmall.y + root.dropY(4) + root.bobY(4))
                                                       : root.arc(root.fu(3), root.hSmall, target)
        readonly property real m: root.t < root.fs(3) + 480 ? 0 : root.mu(3)
        width: root.mix(32, root.button.width, m)
        height: root.mix(16, root.button.height, m)
        x: c.x - width / 2; y: c.y - height / 2
        radius: height / 2
        color: root.mixColor(Theme.kiselDeep, Theme.kisel, root.c01(m))
        scale: 1 + root.squash(4)
        opacity: root.dropOp(4) * (1 - root.seg(root.t, root.fs(3) + 840, 60))
        visible: opacity > 0.005
    }

    // ---- dot grid -> the launch tiles, and sparkles around Kisel ----------------------
    Repeater {
        model: 8
        Item {
            id: dot
            required property int index
            readonly property int col: index % 4
            readonly property int row: Math.floor(index / 4)
            readonly property var tile: index < root.tiles.length ? root.tiles[index] : null
            readonly property bool isTile: tile !== null
            // the spare dots go to fixed sparkle spots around the body
            readonly property var spots: [[18, 30, 6], [108, 36, 5], [10, 68, 4], [116, 72, 5], [96, 10, 7], [60, 6, 5]]
            readonly property var spot: spots[Math.max(0, index - root.tiles.length) % spots.length]
            readonly property real k: root.slot.width / 128
            readonly property point start: Qt.point(root.hDots.x + (col - 1.5) * 8, root.hDots.y + (row - 0.5) * 8 + root.dropY(6) + root.bobY(6))
            readonly property point target: isTile ? Qt.point(tile.x + tile.w / 2, tile.y + 31)
                                                   : Qt.point(root.slot.x + spot[0] * k, root.slot.y + spot[1] * k)
            readonly property point c: root.t < root.fs(4) ? start : root.arc(root.fu(4), start, target)
            readonly property real m: root.t < root.fs(4) + 480 ? 0 : root.mu(4)
            // tile dots grow into the glyph discs; spare dots pop as sparkles then vanish
            readonly property real sparkle: isTile ? 0 : root.seg(root.t, root.fs(4) + 480 + 40 * index, 600)
            readonly property real sparkleScale: sparkle <= 0 ? 0 : sparkle < 0.37 ? 1.15 * root.outBack(sparkle / 0.37) : 1.15 * (1 - root.c01((sparkle - 0.37) / 0.63) * root.c01((sparkle - 0.37) / 0.63))
            width: isTile ? root.mix(3, 28, root.c01(m)) : 3
            height: width
            x: c.x - width / 2; y: c.y - height / 2
            opacity: root.dropOp(6)
            visible: opacity > 0.005 && (isTile ? root.t < root.fs(4) + 480 + 80 * index + 230 : (root.t < root.fs(4) + 480 || sparkle < 1))

            Rectangle { // a dot, or the glyph disc it grows into
                visible: dot.isTile || dot.sparkle <= 0
                anchors.fill: parent
                radius: width / 2
                color: dot.tile ? root.mixColor(Theme.line, dot.tile.color, root.c01(dot.m)) : Theme.line
            }
            Shape { // sparkle: a four-point star
                visible: !dot.isTile && dot.sparkle > 0
                x: dot.width / 2; y: dot.height / 2
                scale: dot.sparkleScale * dot.spot[2] / 4
                rotation: -30 + 70 * dot.sparkle
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: dot.index % 2 ? Theme.mascotLeaf : Theme.mascotTop
                    PathSvg { path: "M0 -4Q0 0 4 0Q0 0 0 4Q0 0 -4 0Q0 0 0 -4z" }
                }
            }
        }
    }
}
