// "Done" in the collapsed bar, and proud of it: a mint capsule in the middle of the bar
// that pops in, glows with two slow halos, has a light sweep across it now and then,
// and keeps throwing small stars out to both sides for as long as it is there.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool on: false
    width: row.implicitWidth + 26
    height: 24

    readonly property bool live: on && !Theme.reduced
    property real pop: on ? 1 : 0
    Behavior on pop { NumberAnimation { duration: 340; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack; easing.overshoot: 2.4 } }
    visible: pop > 0.01
    scale: pop
    opacity: Math.min(1, pop * 1.6)

    // the stars: out from the middle to both sides, growing, turning, and gone
    Repeater {
        model: 8
        Spark {
            id: star
            required property int index
            readonly property int dir: index % 2 ? 1 : -1
            readonly property real reach: root.width / 2 + 14 + (index >> 1) * 13
            readonly property real rise: ((index * 7) % 5 - 2) * 4
            property real u: 0 // 0..1 along its flight
            size: 7 + (index % 3) * 2
            tint: index % 3 === 0 ? "#FFFFFF" : index % 3 === 1 ? "#FFE08A" : Theme.mint
            x: root.width / 2 - size / 2 + dir * reach * u
            y: root.height / 2 - size / 2 + rise * u
            scale: Math.sin(Math.PI * u) * 1.2
            rotation: u * 180 * dir
            visible: root.live && u > 0
            SequentialAnimation on u {
                running: root.live
                loops: Animation.Infinite
                PauseAnimation { duration: star.index * 190 }
                NumberAnimation { from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 1520 - star.index * 190 }
            }
        }
    }

    // the glow: two halos that breathe out of step
    Repeater {
        model: 2
        Rectangle {
            id: halo
            required property int index
            anchors.centerIn: parent
            width: root.width + 6 + index * 10
            height: root.height + 4 + index * 6
            radius: height / 2
            color: Theme.mint
            opacity: 0.16
            SequentialAnimation on opacity {
                running: root.live
                loops: Animation.Infinite
                PauseAnimation { duration: halo.index * 450 }
                NumberAnimation { to: 0.42 - halo.index * 0.14; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.1; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }

    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: 12
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(Theme.mint, 1.18) }
            GradientStop { position: 1; color: Theme.mint }
        }
        // the light that sweeps across
        Rectangle {
            width: 14; height: 40
            y: -8
            rotation: 20
            color: "#FFFFFF"
            opacity: 0.55
            x: -30
            SequentialAnimation on x {
                running: root.live
                loops: Animation.Infinite
                PauseAnimation { duration: 700 }
                NumberAnimation { from: -30; to: root.width + 20; duration: 700; easing.type: Easing.InOutQuad }
                PauseAnimation { duration: 1900 }
            }
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 5
            Canvas { // a tick
                width: 12; height: 12
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    const g = getContext("2d")
                    g.reset(); g.strokeStyle = "#06281a"; g.lineWidth = 2.4; g.lineCap = "round"; g.lineJoin = "round"
                    g.beginPath(); g.moveTo(2, 6.5); g.lineTo(5, 9.5); g.lineTo(10.5, 3); g.stroke()
                }
            }
            Text {
                text: "Done"
                color: "#06281a"
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
            }
        }
    }
}
