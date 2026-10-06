// Behind Home. Two quiet states:
//  * Quiet screen (no session, not asleep): four shapes (big pill, disc,
//    half-round, slab) drift at 6 % opacity, each moving 12 px along its own
//    slow path (6-9 s per leg, InOutSine, phases offset). The moment a session
//    starts they fade out in 280 ms.
//  * Asleep: 46 stars fade in over 600 ms and twinkle on a 5 s loop; the drift
//    gives way to the night sky.
// Reduce motion: still shapes, no twinkle.
import QtQuick

Item {
    id: root
    property bool show: false      // Home is open
    property bool quiet: false     // no session and awake
    property bool asleep: false

    clip: true

    // ---- drifting shapes ----
    Item {
        anchors.fill: parent
        opacity: root.show && root.quiet ? 0.06 : 0
        Behavior on opacity { NumberAnimation { duration: 280 } }

        Repeater {
            // Placed so that, drifting included, nothing reaches the card's rounded
            // bottom corners (x < 634, y < 190): the card clips to a rectangle only.
            model: [
                { kind: "bigPill",   x: 390, y: 24,  dx: 12,  dy: 6,   leg: 7000, phase: 0 },
                { kind: "disc",      x: 488, y: 64,  dx: -10, dy: 8,   leg: 8500, phase: 1500 },
                { kind: "halfRound", x: 290, y: 0,   dx: 12,  dy: 8,   leg: 6500, phase: 3000 },
                { kind: "slab",      x: 420, y: 40,  dx: -12, dy: -6,  leg: 9000, phase: 800 }
            ]
            BrandShape {
                id: drift
                required property var modelData
                kind: modelData.kind
                property real t: 0
                x: modelData.x + modelData.dx * t
                y: modelData.y + modelData.dy * t
                SequentialAnimation on t {
                    running: root.show && root.quiet && !Theme.reduced
                    loops: Animation.Infinite
                    PauseAnimation { duration: drift.modelData.phase % 2000 }
                    NumberAnimation { to: 1; duration: drift.modelData.leg; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: drift.modelData.leg; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // ---- night sky ----
    Item {
        anchors.fill: parent
        opacity: root.show && root.asleep ? 1 : 0
        // the stars arrive 300 ms after the eyes close, cross-fading through the drift
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: root.asleep ? 300 : 0 } NumberAnimation { duration: 600 } } }

        Repeater {
            model: 46
            Rectangle {
                id: star
                required property int index
                // a fixed scatter: a cheap deterministic hash of the index
                readonly property real rx: ((index * 7919) % 1000) / 1000
                readonly property real ry: ((index * 104729) % 997) / 997
                // inset so no star lands outside the rounded corners
                x: rx * (root.width - 56) + 28
                y: ry * (root.height - 40) + 14
                width: index % 7 === 0 ? 3 : 2
                height: width
                radius: width / 2
                color: Theme.kiselSoft
                opacity: 0.25
                SequentialAnimation on opacity {
                    running: root.show && root.asleep && !Theme.reduced
                    loops: Animation.Infinite
                    PauseAnimation { duration: (star.index * 97) % 2500 }
                    NumberAnimation { to: 0.9; duration: 1250; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.2; duration: 1250; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 2500 - (star.index * 97) % 2500 }
                }
            }
        }
    }
}
