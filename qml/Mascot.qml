// Kisel, the raspberry-jelly creature. One body drawn from vector paths and
// animated only by transforms, opacity and colour (motion.md, "The mascot").
// Geometry is the 128 x 128 logo (resources/logo/kisel-mark.svg).
//
// Moods: idle think work alert wow happy sad sleep dizzy walk.
// The Island decides the mood; clicks (and the dizzy easter egg) are handled here.
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
    signal clicked()

    width: size
    height: size

    // ---- mood resolution -------------------------------------------------------
    property bool dizzyOverride: false
    readonly property string m: dizzyOverride ? "dizzy" : mood
    readonly property bool asleep: m === "sleep"

    readonly property string eyeMode: m === "happy" ? "arch" : m === "sleep" ? "closed" : m === "dizzy" ? "spiral" : "open"
    readonly property real eyeH: m === "work" ? 0.5 : m === "sad" ? 0.82 : (m === "alert" || m === "wow") ? 1.2 : 1
    readonly property real eyeW: (m === "alert" || m === "wow") ? 1.2 : 1
    readonly property string mouthKind: ({
        idle: "smile", walk: "smile", think: "flat", sleep: "flat", work: "smirk",
        alert: "smallO", wow: "wideO", happy: "openSmile", sad: "frown", dizzy: "wavy"
    })[m]
    readonly property real tiltTarget: m === "think" ? 6 : m === "sad" ? -4 : 0
    readonly property real leafBase: m === "sad" ? 20 : m === "sleep" ? 32 : 0
    readonly property real leafSwing: m === "alert" ? 1.7 : 5
    readonly property real sag: m === "sleep" ? 0.05 : m === "sad" ? 0.035 : 0
    readonly property real cheekOp: m === "happy" ? 0.7 : 0.35
    property color haloColor: m === "alert" ? Theme.badgeAmber : m === "happy" ? Theme.badgeMint
                                     : (m === "work" || m === "think") ? Theme.badgeInfo : Theme.mascotMid
    Behavior on haloColor { ColorAnimation { duration: 300 } }
    readonly property string badgeKind: m === "think" ? "think" : m === "work" ? "work" : m === "alert" ? "alert"
                                      : m === "happy" ? "happy" : m === "sad" ? "sad" : "none"

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
    property real squash: 0      // + squashes, - stretches
    property real jumpY: 0       // px at 128 design units, up is positive
    property real hopY: 0        // work hops
    property real wobble: 0      // dizzy
    property real tilt: tiltTarget
    Behavior on tilt { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    property real sagNow: sag
    Behavior on sagNow { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    property real leafBaseNow: leafBase
    Behavior on leafBaseNow { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    property real leafWave: 0    // -1..1

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

    // ---- blink -----------------------------------------------------------------
    property real blink: 1
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: root; property: "blink"; to: 0.08; duration: 70 }
        NumberAnimation { target: root; property: "blink"; to: 1; duration: 110 }
    }
    Timer {
        id: blinkTimer
        interval: 2500
        running: !root.asleep
        repeat: true
        onTriggered: { blinkAnim.restart(); interval = 2200 + Math.random() * 3800 }
    }

    // ---- eyes follow the pointer, with a spring --------------------------------
    readonly property real wantX: m === "walk" ? 5 * walkDir : m === "think" ? 3 : looking ? Math.max(-1, Math.min(1, (lookAt.x - width / 2) / 60)) * 5 : 0
    readonly property real wantY: m === "think" ? -3 : looking ? Math.max(-1, Math.min(1, (lookAt.y - height / 2) / 60)) * 4 : 0
    property real eyeX: wantX
    property real eyeY: wantY
    Behavior on eyeX { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.05 } }
    Behavior on eyeY { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.05 } }

    // ---- one-shot moves --------------------------------------------------------
    function jump(power) {
        if (Theme.reduced) return
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

    // work: hops 5 px every 560 ms (150 up, 150 down, 260 rest)
    SequentialAnimation {
        running: root.m === "work" && !Theme.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.hopY = 0
        NumberAnimation { target: root; property: "hopY"; to: 5; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hopY"; to: 0; duration: 150; easing.type: Easing.InQuad }
        PauseAnimation { duration: 260 }
    }
    // alert: a bigger hop now and then while the request waits
    Timer {
        interval: 2200
        repeat: true
        running: root.m === "alert"
        onTriggered: root.jump(0.45)
    }
    // walk: hops of 7 px every 260 ms, tilting 5 degrees left and right
    SequentialAnimation {
        running: root.m === "walk" && !Theme.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.hopY = 0
        NumberAnimation { target: root; property: "hopY"; to: 7; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hopY"; to: 0; duration: 90; easing.type: Easing.InQuad }
        PauseAnimation { duration: 80 }
    }
    SequentialAnimation {
        running: root.m === "walk" && !Theme.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running && root.m !== "dizzy") root.wobble = 0
        NumberAnimation { target: root; property: "wobble"; to: 5; duration: 130; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "wobble"; to: -5; duration: 130; easing.type: Easing.InOutSine }
    }

    // a jump with sparkles, for moments that are happy without being "done"
    function celebrate(power) {
        jump(power)
        celebrating = true
        celebrateTimer.restart()
    }
    Timer { id: celebrateTimer; interval: 1500; onTriggered: root.celebrating = false }
    function blinkNow() { blinkAnim.restart() }

    // dizzy: wobble 10 degrees every 230 ms
    SequentialAnimation {
        running: root.m === "dizzy" && !Theme.reduced
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.wobble = 0
        NumberAnimation { target: root; property: "wobble"; to: 10; duration: 115; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "wobble"; to: -10; duration: 115; easing.type: Easing.InOutSine }
    }

    // waking up: the eyes open with a blink, no sound
    onAsleepChanged: if (!asleep) blinkNow()

    onMChanged: {
        if (m === "happy") jump(1.0)
        else if (m === "alert") jump(0.7)
        else if (m === "wow") jump(0.35)
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

        // halo: a soft glow, colour crossfades with the mood
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.asleep ? 0.15 : 0.3
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

        // ground shadow narrows and lightens with height
        Rectangle {
            readonly property real h: root.jumpY + root.hopY
            x: 26 + h * 0.4; y: 113; width: 76 - h * 0.8; height: 10; radius: 5
            color: "black"
            opacity: Math.max(0, 0.25 - h * 0.004)
        }

        Item {
            id: body
            width: 128
            height: 128
            transform: [
                Translate { y: -(root.jumpY + root.hopY) },
                Scale {
                    origin.x: 64; origin.y: 118
                    xScale: (1 - 0.02 * root.breath) * (1 + 0.16 * root.squash)
                    yScale: (1 + 0.035 * root.breath) * (1 - root.sagNow) * (1 - 0.22 * root.squash)
                },
                Rotation { origin.x: 64; origin.y: 118; angle: root.tilt + root.wobble }
            ]

            // body
            Shape {
                anchors.fill: parent
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
            // highlights
            Rectangle { x: 32; y: 39; width: 26; height: 14; radius: 7; color: "white"; opacity: 0.42; rotation: -32 }
            Rectangle { x: 33; y: 61; width: 6; height: 6; radius: 3; color: "white"; opacity: 0.35 }
            // cheeks
            Rectangle { x: 29; y: 81; width: 18; height: 10; radius: 5; color: "#ff4f74"; opacity: root.cheekOp; Behavior on opacity { NumberAnimation { duration: 200 } } }
            Rectangle { x: 81; y: 81; width: 18; height: 10; radius: 5; color: "#ff4f74"; opacity: root.cheekOp; Behavior on opacity { NumberAnimation { duration: 200 } } }

            // eyes
            Repeater {
                model: [46, 82]
                Item {
                    id: eye
                    required property int modelData
                    x: modelData + root.eyeX
                    y: 78 + root.eyeY
                    width: 0; height: 0
                    // open
                    Shape {
                        opacity: root.eyeMode === "open" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Theme.mascotEye
                            strokeColor: "transparent"
                            PathAngleArc {
                                radiusX: 6.5 * root.eyeW
                                radiusY: Math.max(0.5, 8.5 * root.eyeH * root.blink)
                                startAngle: 0; sweepAngle: 360
                            }
                        }
                        Rectangle { // catch-light
                            x: 2.5; y: -4.5; width: 4.6; height: 4.6; radius: 2.3; color: "white"
                            opacity: root.blink > 0.5 ? 1 : 0
                        }
                    }
                }
            }
            // happy "^ ^", sleep closed, dizzy spirals (drawn in body space)
            Mark { d: "M40 82q6 -10 12 0M76 82q6 -10 12 0"; on: root.eyeMode === "arch"; w: 3.2 }
            Mark { d: "M40 77q6 6 12 0M76 77q6 6 12 0"; on: root.eyeMode === "closed"; w: 2.6 }
            Repeater {
                model: [46, 82]
                Shape {
                    id: spiral
                    required property int modelData
                    x: modelData; y: 78; width: 0; height: 0
                    opacity: root.eyeMode === "spiral" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.mascotEye; strokeWidth: 2.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathSvg { path: "M0 0a1.6 1.6 0 1 1 3.2 0a3.2 3.2 0 1 1 -6.4 0a4.8 4.8 0 1 1 9.6 0" }
                    }
                    RotationAnimator on rotation { from: 0; to: 360; duration: 700; loops: Animation.Infinite; running: root.eyeMode === "spiral" }
                }
            }

            // mouths
            Mark { d: "M57 93q7 6 14 0"; on: root.mouthKind === "smile" }
            Mark { d: "M58 94h12"; on: root.mouthKind === "flat" }
            Mark { d: "M57 94q8 4 14 -2"; on: root.mouthKind === "smirk" }
            Mark { d: "M60.5 95a3.5 4.5 0 1 0 7 0a3.5 4.5 0 1 0 -7 0z"; on: root.mouthKind === "smallO"; fill: true }
            Mark { d: "M59 94a5 7 0 1 0 10 0a5 7 0 1 0 -10 0z"; on: root.mouthKind === "wideO"; fill: true }
            Mark { d: "M54 89q10 15 20 0z"; on: root.mouthKind === "openSmile"; fill: true }
            Mark { d: "M57 97q7 -6 14 0"; on: root.mouthKind === "frown" }
            Mark { d: "M54 94q3 -4 6 0t6 0t6 0"; on: root.mouthKind === "wavy"; w: 2.6 }

            // leaf: rotates about its stem, droops when sad or asleep
            Item {
                width: 128; height: 128
                transform: Rotation {
                    origin.x: 64; origin.y: 26
                    angle: root.leafBaseNow + root.leafWave * root.leafSwing
                }
                Mark { d: "M64 26c0-6 1-11 5-15"; w: 3.5; ink: root.cLeaf }
                Mark { d: "M69 11c8-12 22-8 22 3-9 3-19 1-22-3z"; fill: true; ink: root.cLeaf }
                Mark { d: "M63 17c-7-11-20-8-19 2 8 3 17 2 19-2z"; fill: true; ink: root.cLeaf2 }
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
                    running: (root.m === "happy" || root.celebrating) && !Theme.reduced
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

        // dizzy: three brand shapes orbiting the head once per 1100 ms
        Item {
            x: 64; y: 30; width: 0; height: 0
            visible: root.m === "dizzy"
            RotationAnimator on rotation { from: 0; to: 360; duration: 1100; loops: Animation.Infinite; running: root.m === "dizzy" && !Theme.reduced }
            Rectangle { x: 34; y: -3; width: 7; height: 7; radius: 3.5; color: Theme.mascotTop }                 // soft disc
            BrandShape { x: -42; y: -3; kind: "halfRound"; scale: 14 / 200; transformOrigin: Item.TopLeft } // amber half-round
            Rectangle { x: -2; y: -30; width: 10; height: 5; radius: 2.5; color: Theme.badgeMint }                // small pill
        }

        StatusBadge { x: 6; y: 12; kind: root.badgeKind }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onClicked: root.poke()
    }
}
