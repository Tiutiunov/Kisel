// "Thinking": three dots in `info` pulsing in a wave, 1200 ms loop. Still dots
// at 100 / 65 / 35 percent with reduce motion.
import QtQuick

Row {
    id: root
    property bool running: true
    property color ink: Theme.info
    spacing: 4
    height: 5
    Repeater {
        model: 3
        Rectangle {
            id: dot
            required property int index
            width: 5; height: 5; radius: 2.5
            color: root.ink
            opacity: [1, 0.65, 0.35][index]
            SequentialAnimation on opacity {
                running: root.running && !Theme.reduced
                loops: Animation.Infinite
                PauseAnimation { duration: dot.index * 400 }
                NumberAnimation { to: 1; duration: 200; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.3; duration: 200; easing.type: Easing.InOutSine }
                PauseAnimation { duration: (2 - dot.index) * 400 }
            }
        }
    }
}
