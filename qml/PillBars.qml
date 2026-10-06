// "Working": three bars in `info` rising and falling in a wave, 700 ms loop,
// 100 ms offset. Still bars with reduce motion.
import QtQuick

Row {
    id: root
    property bool running: true
    property color ink: Theme.info
    spacing: 3
    height: 14
    Repeater {
        model: 3
        Rectangle {
            id: bar
            required property int index
            width: 3; radius: 2
            anchors.bottom: parent.bottom
            color: root.ink
            height: [6, 12, 8][index]
            SequentialAnimation on height {
                running: root.running && !Theme.reduced
                loops: Animation.Infinite
                PauseAnimation { duration: bar.index * 100 }
                NumberAnimation { to: 13; duration: 200; easing.type: Easing.InOutSine }
                NumberAnimation { to: 5; duration: 250; easing.type: Easing.InOutSine }
                PauseAnimation { duration: Math.max(0, 250 - bar.index * 100) }
            }
        }
    }
}
