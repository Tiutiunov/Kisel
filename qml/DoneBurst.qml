// Task done: the shape burst (plays with the happy jump and the sparkles).
//  1. A mint ring grows from the mascot's centre, scale 1 to 6 in 600 ms
//     OutCubic, fading from 50 % to 0.
//  2. Six confetti pieces leave in 520 ms OutCubic: two kisel-deep pills
//     (14 x 7), a mint and an amber disc (6), two amber half-rounds (10).
//     Each travels 36-60 px, spins 90 degrees, sags 10 px, fades over its last
//     200 ms. They leave to the sides so they never cover the face.
// Reduce motion: the pieces only cross-fade in place.
import QtQuick

Item {
    id: root
    property real size: 88
    property real cx: 0
    property real cy: 0
    property int burst: 0

    function fire(x, y, mascotSize) {
        cx = x; cy = y; size = mascotSize
        burst++
    }

    // ring
    Rectangle {
        id: ring
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: root.size * 0.5
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.mint
        opacity: 0
        scale: 1
        ParallelAnimation {
            id: ringAnim
            NumberAnimation { target: ring; property: "scale"; from: 1; to: Theme.reduced ? 1 : 6; duration: 600; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "opacity"; from: 0.5; to: 0; duration: 600; easing.type: Easing.OutCubic }
        }
    }

    // confetti: kind, size, angle (deg, 0 = right, 180 = left; up is negative y), travel, spin
    readonly property var pieces: [
        { k: "pill",  w: 14, h: 7, a: -25,  d: 52, spin: 90,  c: "deep" },
        { k: "pill",  w: 14, h: 7, a: -155, d: 46, spin: -90, c: "deep" },
        { k: "disc",  w: 6,  h: 6, a: -50,  d: 60, spin: 0,   c: "mint" },
        { k: "disc",  w: 6,  h: 6, a: -130, d: 40, spin: 0,   c: "amber" },
        { k: "half",  w: 10, h: 5, a: -10,  d: 38, spin: 90,  c: "amber" },
        { k: "half",  w: 10, h: 5, a: -170, d: 56, spin: -90, c: "amber" }
    ]

    Repeater {
        model: root.pieces
        Item {
            id: piece
            required property var modelData
            property real t: 0
            readonly property real rad: modelData.a * Math.PI / 180
            readonly property real k: root.size / 120
            x: root.cx + Math.cos(rad) * modelData.d * k * (Theme.reduced ? 0.3 : t) - width / 2
            y: root.cy + Math.sin(rad) * modelData.d * k * (Theme.reduced ? 0.3 : t) + 10 * t * t - height / 2
            width: modelData.w; height: modelData.h
            rotation: modelData.spin * t
            // fades over its last 200 ms
            opacity: t < 0.62 ? (t > 0 ? 1 : 0) : Math.max(0, 1 - (t - 0.62) / 0.38)

            Rectangle {
                visible: piece.modelData.k !== "half"
                anchors.fill: parent
                radius: Math.min(width, height) / 2
                color: piece.modelData.c === "deep" ? Theme.kiselDeep : piece.modelData.c === "mint" ? Theme.mint : Theme.amber
            }
            BrandShape { visible: piece.modelData.k === "half"; kind: "halfRound"; scale: piece.modelData.w / 200; transformOrigin: Item.TopLeft }

            NumberAnimation on t { id: tAnim; running: false; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
            Connections {
                target: root
                function onBurstChanged() { tAnim.restart() }
            }
        }
    }
    onBurstChanged: ringAnim.restart()
}
