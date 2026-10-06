// The 4 x 2 `line` dot grid: Kisel's "ready and listening" mark. A wave of
// opacity (0.3 to 1) sweeps the dots left to right, 900 ms loop, 120 ms offset
// per column. With reduce motion it stays a still grid.
//
// `drop: true` is the drop hint: the grid grows to 6 x 3 and pulses together
// once per second (scale 1 to 1.15 and back) in `kisel`.
import QtQuick

Item {
    id: root
    property bool running: true
    property bool drop: false
    readonly property int cols: drop ? 6 : 4
    readonly property int rows: drop ? 3 : 2

    implicitWidth: (cols - 1) * 16 + 6
    implicitHeight: (rows - 1) * 16 + 6
    width: implicitWidth
    height: implicitHeight

    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.drop && root.running && !Theme.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 1.15; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
    }

    Item {
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight
        scale: root.drop ? root.pulse : 1
        Repeater {
            model: root.cols * root.rows
            Rectangle {
                id: dot
                required property int index
                readonly property int col: index % root.cols
                readonly property int row: Math.floor(index / root.cols)
                x: col * 16; y: row * 16
                width: 6; height: 6; radius: 3
                color: root.drop ? Theme.kisel : Theme.line
                opacity: root.drop ? 1 : 0.3
                SequentialAnimation on opacity {
                    running: root.running && !root.drop && !Theme.reduced
                    loops: Animation.Infinite
                    PauseAnimation { duration: dot.col * 120 }
                    NumberAnimation { to: 1; duration: 210; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.3; duration: 210; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: Math.max(0, 900 - 420 - dot.col * 120) }
                }
            }
        }
    }
}
