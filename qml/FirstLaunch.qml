// First launch, step 2-3 of motion.md: the cover assembles, then converges.
//
// Seven shapes take the cover's arrangement at half size, centred on the
// island's slot. Each falls in from 60 px above with 360 ms OutBack and a 140 ms
// fade, staggered 60 ms (slab, half-round, big pill, disc, small pill, soft disc,
// dots). They hold 400 ms, then converge in reverse order, 320 ms InQuad,
// scaling to nothing toward the mascot. With reduce motion they cross-fade in
// place instead of travelling.
import QtQuick

Item {
    id: root
    property point centre: Qt.point(354, 92)   // where the cover sits
    property point target: Qt.point(277, 23)   // where they converge (the mascot)
    signal landed()        // the first shape touched down
    signal converging()    // the shapes start to leave
    signal finished()

    visible: false
    anchors.fill: parent

    // cover coordinates (a 960 x 288 layout); shapes at their centres
    readonly property var layout: [
        { kind: "slab",      cx: 784, cy: 244 },
        { kind: "halfRound", cx: 860, cy: 126 },
        { kind: "bigPill",   cx: 620, cy: 88 },
        { kind: "disc",      cx: 624, cy: 212 },
        { kind: "smallPill", cx: 532, cy: 180 },
        { kind: "softDisc",  cx: 904, cy: 236 },
        { kind: "dotGrid",   cx: 535, cy: 252 }
    ]
    // centre of the cover's used area, to centre it on the island
    readonly property real coverCx: 730
    readonly property real coverCy: 170
    readonly property real half: 0.5

    function play() {
        visible = true
        anim.restart()
    }

    Repeater {
        model: root.layout
        BrandShape {
            id: shape
            required property var modelData
            required property int index
            kind: modelData.kind
            readonly property real homeX: root.centre.x + (modelData.cx - root.coverCx) * root.half - width / 2
            readonly property real homeY: root.centre.y + (modelData.cy - root.coverCy) * root.half - height / 2
            property real drop: 1       // 1 = 60 px above, 0 = home
            property real leave: 0      // 0 = home, 1 = at the mascot, gone
            x: homeX + (root.target.x - (homeX + width / 2)) * leave
            y: homeY - 60 * drop * (Theme.reduced ? 0 : 1) + (root.target.y - (homeY + height / 2)) * leave
            scale: root.half * (1 - leave)
            opacity: 0

            // fall-in, staggered 60 ms from 200 ms
            SequentialAnimation {
                id: fall
                running: false
                PauseAnimation { duration: 200 + shape.index * 60 }
                ParallelAnimation {
                    NumberAnimation { target: shape; property: "drop"; to: 0; duration: 360; easing.type: Easing.OutBack }
                    NumberAnimation { target: shape; property: "opacity"; to: 1; duration: 140 }
                }
            }
            // converge, reverse order: the last shape to land is the first to leave
            SequentialAnimation {
                id: leaveAnim
                running: false
                PauseAnimation { duration: (root.layout.length - 1 - shape.index) * 30 }
                ParallelAnimation {
                    NumberAnimation { target: shape; property: "leave"; to: 1; duration: Theme.reduced ? 140 : 320; easing.type: Easing.InQuad }
                    NumberAnimation { target: shape; property: "opacity"; to: 0; duration: Theme.reduced ? 140 : 320; easing.type: Easing.InQuad }
                }
            }
            Connections {
                target: anim
                function onStarted() { shape.drop = 1; shape.leave = 0; shape.opacity = 0; fall.restart() }
            }
            Connections {
                target: root
                function onConverging() { leaveAnim.restart() }
            }
        }
    }

    SequentialAnimation {
        id: anim
        PauseAnimation { duration: 200 + 260 }
        ScriptAction { script: root.landed() }
        PauseAnimation { duration: 920 - 460 + 400 } // last one lands at 920 ms, hold 400 ms
        ScriptAction { script: root.converging() }
        PauseAnimation { duration: 320 + 6 * 30 }
        ScriptAction { script: { root.visible = false; root.finished() } }
    }
}
