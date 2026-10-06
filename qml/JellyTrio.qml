// Waiting: the jelly trio. A loader for waits with no known end (the chat
// before its first token, the GitHub widget while loading, the first hook
// connection). A kisel pill (28 x 12), a mint disc (12) and an amber half-round
// (14 x 7) sit in a row; every 400 ms they shuffle one slot to the right, each
// moving 40 px in 320 ms OutBack; the last wraps through the back of the row
// (scale 0.6, opacity 0.4). One loop is 1200 ms. Fades out in 140 ms when
// content arrives. Reduce motion: a still dot grid instead.
import QtQuick

Item {
    id: root
    property bool running: true
    readonly property int pitch: 40
    // The wait ended. The three pills move toward each other and merge into one in
    // 180 ms (OutBack), which becomes the mint disc and the check; if the wait ended
    // in an error it turns into a danger pill that shakes twice, then fades.
    property string outcome: ""       // "", ok, fail
    readonly property bool resolving: outcome !== ""
    function resolve(ok) {
        outcome = ok ? "ok" : "fail"
        resolveAnim.restart()
    }
    function reset() { outcome = ""; merged = 0; result = 0 }
    property real merged: 0           // 0 = in the row, 1 = one pill
    property real result: 0           // 0..1: the disc and check (or the danger pill) take over
    property real shakeX: 0
    signal resolved()
    SequentialAnimation {
        id: resolveAnim
        NumberAnimation { target: root; property: "merged"; to: 1; duration: Theme.reduced ? 140 : 180; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack }
        NumberAnimation { target: root; property: "result"; to: 1; duration: 140 }
        // the failure shakes twice
        SequentialAnimation {
            loops: 1
            PropertyAction { target: root; property: "shakeX"; value: 0 }
            NumberAnimation { target: root; property: "shakeX"; to: root.outcome === "fail" && !Theme.reduced ? 4 : 0; duration: 50 }
            NumberAnimation { target: root; property: "shakeX"; to: root.outcome === "fail" && !Theme.reduced ? -4 : 0; duration: 100 }
            NumberAnimation { target: root; property: "shakeX"; to: root.outcome === "fail" && !Theme.reduced ? 4 : 0; duration: 100 }
            NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 50 }
        }
        PauseAnimation { duration: 500 }
        ScriptAction { script: root.resolved() }
    }

    width: pitch * 3
    height: 16
    opacity: (running || resolving) ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

    DotWave { visible: Theme.reduced; running: false; anchors.verticalCenter: parent.verticalCenter }

    function mix(a, b, u) { return a + (b - a) * u }
    property int turn: 0
    Timer {
        interval: 400
        repeat: true
        running: root.running && !root.resolving && !Theme.reduced
        onTriggered: root.turn++
    }

    Repeater {
        model: Theme.reduced ? 0 : 3
        Item {
            id: jelly
            required property int index
            // shape i starts in slot i; every tick it moves one slot right and wraps
            readonly property int slot: (index + root.turn) % 3
            property int prevSlot: slot
            readonly property bool wrapping: slot < prevSlot
            x: (root.merged > 0 ? root.mix(slot * root.pitch + (root.pitch - width) / 2, (root.width - width) / 2, root.merged)
                                : slot * root.pitch + (root.pitch - width) / 2)
            y: (root.height - height) / 2
            width: index === 0 ? 28 : index === 1 ? 12 : 14
            height: index === 0 ? 12 : index === 1 ? 12 : 7
            scale: wrapping ? 0.6 : 1
            opacity: (wrapping ? 0.4 : 1) * (1 - root.result)
            Behavior on x { enabled: root.merged === 0; NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
            Behavior on scale { NumberAnimation { duration: 160 } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            onSlotChanged: wrapTimer.restart()
            Timer { id: wrapTimer; interval: 320; onTriggered: jelly.prevSlot = jelly.slot }

            Rectangle { visible: jelly.index === 0; anchors.fill: parent; radius: 6; color: Theme.kisel }
            Rectangle { visible: jelly.index === 1; anchors.fill: parent; radius: 6; color: Theme.mint }
            BrandShape { visible: jelly.index === 2; kind: "halfRound"; scale: 14 / 200; transformOrigin: Item.TopLeft }
        }
    }

    // the mint disc and its check (success), or the danger pill (failure)
    Item {
        anchors.centerIn: parent
        opacity: root.result
        visible: opacity > 0.01
        transform: Translate { x: root.shakeX }
        Rectangle {
            visible: root.outcome === "ok"
            anchors.centerIn: parent
            width: 16; height: 16; radius: 8
            color: Theme.mint
            DrawnCheck { anchors.centerIn: parent; size: 12; progress: root.result; color: Theme.surface0 }
        }
        Rectangle {
            visible: root.outcome === "fail"
            anchors.centerIn: parent
            width: 34; height: 14; radius: 7
            color: Theme.danger
        }
    }
}
