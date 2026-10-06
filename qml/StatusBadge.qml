// The 20 px disc at the mascot's top-left: info (think/work), amber (alert),
// mint (done), danger (failed). Pops in with OutBack, colour crossfades.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string kind: "none" // none | think | work | alert | happy | sad

    readonly property bool shown: kind !== "none"
    readonly property color fill: kind === "alert" ? Theme.badgeAmber
                                : kind === "happy" ? Theme.badgeMint
                                : kind === "sad" ? Theme.badgeDanger
                                : Theme.badgeInfo
    width: 20
    height: 20
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }

    // 2 px ring in the island's ground colour
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.fill
        border.width: 2
        border.color: Theme.surface0
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    // think: three dots pulsing in a wave, one cycle per 1200 ms
    Row {
        anchors.centerIn: parent
        spacing: 2
        visible: root.kind === "think"
        Repeater {
            model: 3
            Rectangle {
                id: dot
                required property int index
                width: 3; height: 3; radius: 1.5
                color: Theme.mascotEye
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.kind === "think" && !Theme.reduced
                    PauseAnimation { duration: dot.index * 400 }
                    NumberAnimation { to: 1; duration: 200; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.3; duration: 200; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: (2 - dot.index) * 400 }
                }
            }
        }
    }

    Spinner {
        anchors.centerIn: parent
        size: 12
        color: Theme.mascotEye
        visible: root.kind === "work"
    }

    Text {
        anchors.centerIn: parent
        visible: root.kind === "alert"
        text: "!"
        color: Theme.mascotEye
        font.family: Theme.sans
        font.weight: Font.ExtraBold
        font.pixelSize: 13
    }
    Icon { anchors.centerIn: parent; size: 13; name: "check"; color: Theme.mascotEye; visible: root.kind === "happy" }
    Icon { anchors.centerIn: parent; size: 12; name: "cross"; color: Theme.mascotEye; visible: root.kind === "sad" }
}
