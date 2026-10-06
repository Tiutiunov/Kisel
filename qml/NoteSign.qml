// Rin's sign: a little placard on a stick with the name of the program a notification
// came from, which she waves until it has been looked at. (How many, if more than one,
// in a red dot on its corner.) With notifications from several programs the placard
// turns over every few seconds and shows them one after another, each with its own count.
//
// It is a sticker like the rest of the bar's sweets, and makes a show of itself: it
// glows with two halos that breathe out of step, a light sweeps across it now and then,
// a small star twinkles on its corner, and whenever there is news (it comes up, another
// notification arrives, it turns over to the next program) stars burst out of it and
// the count pops. It is held up out of the bar, past its free edge, so the
// bar's own contents stay where they are: above a bar on the bottom of the screen, and
// hanging below one on the top (`flip`).
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool on: false
    property bool still: false   // tucked away: nothing moves
    property string app: ""
    property int count: 1
    property var apps: []        // every program with one waiting, newest first
    property var counts: []      // ...and how many each has
    property int turn: 0
    readonly property bool many: apps.length > 1
    readonly property string shownApp: (many ? apps[turn % apps.length] : app) || ""
    readonly property int shownCount: many ? (counts[turn % apps.length] || 1) : count
    onAppsChanged: turn = 0 // (the newest first)
    Timer { interval: 2600; repeat: true; running: root.on && root.many && !root.still; onTriggered: Theme.reduced ? root.turn++ : turnOver.restart() }
    SequentialAnimation {
        id: turnOver
        NumberAnimation { target: flipScale; property: "xScale"; to: 0; duration: 130; easing.type: Easing.InQuad }
        ScriptAction { script: { root.turn++; root.cheer(0.6) } }
        NumberAnimation { target: flipScale; property: "xScale"; to: 1; duration: 200; easing.type: Easing.OutBack }
    }
    // the burst: `burstU` runs 0..1 and every star rides it; `burstK` is how far they go
    property real burstU: 0
    property real burstK: 1
    function cheer(k) { if (Theme.reduced || still) return; burstK = k; burst.restart(); badgePop.restart() }
    NumberAnimation { id: burst; target: root; property: "burstU"; from: 0; to: 1; duration: 720; easing.type: Easing.OutCubic }
    onOnChanged: if (on) cheerSoon.restart()
    Timer { id: cheerSoon; interval: 260; onTriggered: root.cheer(1) } // (once it is up)
    property int lastCount: 0
    onCountChanged: { if (on && count > lastCount && lastCount > 0) cheer(1); lastCount = count }
    property real maxText: 84
    property bool flip: false    // hangs down instead of standing up
    readonly property real fullW: plate.width + 4

    width: fullW; height: 30
    // it comes up out of the bar and goes back down
    property real up: on ? 1 : 0
    Behavior on up { NumberAnimation { duration: Theme.reduced ? 0 : 380; easing.type: root.on ? Easing.OutBack : Easing.InCubic } }
    opacity: Math.min(1, up * 2)
    visible: up > 0.01

    Item {
        id: swing
        width: parent.width; height: parent.height
        y: (root.flip ? -14 : 14) * (1 - root.up)
        transformOrigin: root.flip ? Item.TopLeft : Item.BottomLeft
        SequentialAnimation on rotation {
            running: root.on && !root.still && !Theme.reduced
            loops: Animation.Infinite
            NumberAnimation { to: 5; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: -4; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: 5; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: -4; duration: 330; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 260; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 1500 }
        }
        Rectangle { // the stick
            x: 5; y: root.flip ? 0 : plate.y + plate.height - 2
            width: 3; height: root.flip ? plate.y + 2 : parent.height - y
            radius: 1.5
            color: "#C98A3A"
        }
        Item { // the placard, with its glow
            id: plate
            y: root.flip ? parent.height - height - 2 : 2
            width: label.width + 12; height: 16
            transform: Scale { id: flipScale; origin.x: plate.width / 2 }
            Repeater { // the glow: two halos that breathe out of step
                model: 2
                Rectangle {
                    id: halo
                    required property int index
                    anchors.centerIn: parent
                    width: plate.width + 5 + index * 7
                    height: plate.height + 4 + index * 5
                    radius: 7 + index * 2
                    color: "#FFD24A"
                    opacity: 0.14
                    SequentialAnimation on opacity {
                        running: root.on && !root.still && !Theme.reduced
                        loops: Animation.Infinite
                        PauseAnimation { duration: halo.index * 450 }
                        NumberAnimation { to: 0.44 - halo.index * 0.16; duration: 850; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.08; duration: 850; easing.type: Easing.InOutSine }
                    }
                }
            }
            Rectangle {
                id: board
                anchors.fill: parent
                radius: 5
                clip: true
                gradient: Gradient {
                    GradientStop { position: 0; color: "#FFE585" }
                    GradientStop { position: 1; color: "#FFC93A" }
                }
                Rectangle { // the light that sweeps across
                    width: 9; height: 34
                    y: -9
                    rotation: 20
                    color: "#FFFFFF"
                    opacity: 0.6
                    x: -24
                    SequentialAnimation on x {
                        running: root.on && !root.still && !Theme.reduced
                        loops: Animation.Infinite
                        PauseAnimation { duration: 900 }
                        NumberAnimation { from: -24; to: plate.width + 16; duration: 620; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 2100 }
                    }
                }
                Text {
                    id: label
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, root.maxText)
                    elide: Text.ElideRight
                    text: root.shownApp !== "" ? root.shownApp : "New"
                    color: "#3A2A08"
                    font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
                }
            }
            Rectangle { anchors.fill: parent; radius: 5; color: "transparent"; border.width: 1.5; border.color: "#FFFFFF" } // the sticker's white edge
            Spark { // a star that twinkles on its corner
                x: -size / 2 + 1; y: -size / 2 + 1
                size: 8; tint: "#FFFFFF"
                SequentialAnimation on scale {
                    running: root.on && !root.still && !Theme.reduced
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.25; duration: 420; easing.type: Easing.OutBack }
                    NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 700 }
                }
                RotationAnimation on rotation { running: root.on && !root.still && !Theme.reduced; from: 0; to: 90; duration: 1640; loops: Animation.Infinite }
            }
            Repeater { // the burst: stars out in every direction, growing, turning, and gone
                model: 8
                Spark {
                    id: star
                    required property int index
                    readonly property real a: (index * 45 + 20) * Math.PI / 180
                    readonly property real reach: (plate.width / 2 + 10 + (index % 3) * 5) * root.burstK
                    readonly property real lift: (plate.height / 2 + 9 + (index % 2) * 5) * root.burstK
                    size: 6 + (index % 3) * 2
                    tint: index % 3 === 0 ? "#FFFFFF" : index % 3 === 1 ? "#FFE08A" : "#FF9EBB"
                    x: plate.width / 2 - size / 2 + Math.cos(a) * reach * root.burstU
                    y: plate.height / 2 - size / 2 + Math.sin(a) * lift * root.burstU
                    scale: Math.sin(Math.PI * root.burstU) * 1.25
                    rotation: root.burstU * 180 * (index % 2 ? 1 : -1)
                    visible: root.burstU > 0 && root.burstU < 1
                }
            }
        }
        Rectangle { // how many
            visible: root.shownCount > 1
            id: badge
            x: plate.width - 7; y: plate.y - 4
            width: Math.max(11, num.implicitWidth + 5); height: 11; radius: 5.5
            color: "#E0405A"
            border.width: 1; border.color: "#FFFFFF"
            SequentialAnimation {
                id: badgePop
                NumberAnimation { target: badge; property: "scale"; to: 1.5; duration: 130; easing.type: Easing.OutQuad }
                NumberAnimation { target: badge; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
            }
            Text {
                id: num
                anchors.centerIn: parent
                text: root.shownCount > 9 ? "9+" : root.shownCount
                color: "#FFFFFF"
                font.family: Theme.sans; font.pixelSize: 7; font.weight: Font.ExtraBold
            }
        }
    }
}
