// The 20 px disc at the mascot's top-left: info (think/work), amber (alert),
// mint (done), danger (failed). Pops in with OutBack, colour crossfades.
//
// Changing between two badges of different colour families is a quick out and
// in: the old one scales to 0 in 120 ms, the new one pops in. think <-> work
// share the info colour, so only the glyph cross-fades (no pop out and in).
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string kind: "none" // none | think | work | alert | happy | sad

    // what is drawn right now; `kind` is where it is heading
    property string shownKind: "none"
    readonly property bool shown: shownKind !== "none"
    readonly property color fill: shownKind === "alert" ? Theme.badgeAmber
                                : shownKind === "happy" ? Theme.badgeMint
                                : shownKind === "sad" ? Theme.badgeDanger
                                : Theme.badgeInfo
    function family(k) { return k === "think" || k === "work" ? "info" : k }

    onKindChanged: {
        if (kind === shownKind) return
        if (shownKind === "none" || kind === "none") {
            // appear, or leave: scale and fade, no swap
            if (kind !== "none") shownKind = kind
            else outTimer.restart()
        } else if (family(kind) === family(shownKind)) {
            shownKind = kind // glyph cross-fade only
        } else {
            swapAnim.restart()
        }
    }
    Timer { id: outTimer; interval: 120; onTriggered: if (root.kind === "none") root.shownKind = "none" }
    SequentialAnimation {
        id: swapAnim
        // the new badge pops in 120 ms after the old one shrinks away
        ScriptAction { script: root.popped = false }
        PauseAnimation { duration: 120 }
        ScriptAction { script: { root.shownKind = root.kind; root.popped = true } }
    }
    property bool popped: true
    Component.onCompleted: if (kind !== "none") shownKind = kind

    width: 20
    height: 20
    readonly property bool visibleNow: kind !== "none" && popped
    opacity: visibleNow ? 1 : 0
    scale: visibleNow ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    Behavior on scale { NumberAnimation { duration: shown && visibleNow ? 220 : 120; easing.type: visibleNow && !Theme.reduced ? Easing.OutBack : Easing.InQuad } }

    // 2 px ring in the island's ground colour
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.fill
        border.width: 2
        border.color: Theme.surface0
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    // glyphs cross-fade (think -> work does not pop out and in)
    Row {
        anchors.centerIn: parent
        spacing: 2
        opacity: root.shownKind === "think" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        visible: opacity > 0.01
        Repeater {
            model: 3
            Rectangle {
                id: dot
                required property int index
                width: 3; height: 3; radius: 1.5
                color: Theme.mascotEye
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.shownKind === "think" && !Theme.reduced
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
        opacity: root.shownKind === "work" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        visible: opacity > 0.01
    }

    Text {
        anchors.centerIn: parent
        opacity: root.shownKind === "alert" ? 1 : 0
        visible: opacity > 0.01
        text: "!"
        color: Theme.mascotEye
        font.family: Theme.sans
        font.weight: Font.ExtraBold
        font.pixelSize: 13
    }
    Icon { anchors.centerIn: parent; size: 13; name: "check"; color: Theme.mascotEye; opacity: root.shownKind === "happy" ? 1 : 0; visible: opacity > 0.01 }
    Icon { anchors.centerIn: parent; size: 12; name: "cross"; color: Theme.mascotEye; opacity: root.shownKind === "sad" ? 1 : 0; visible: opacity > 0.01 }
}
