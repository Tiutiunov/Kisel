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

    width: pitch * 3
    height: 16
    opacity: running ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

    DotWave { visible: Theme.reduced; running: false; anchors.verticalCenter: parent.verticalCenter }

    property int turn: 0
    Timer {
        interval: 400
        repeat: true
        running: root.running && !Theme.reduced
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
            x: slot * root.pitch + (root.pitch - width) / 2
            y: (root.height - height) / 2
            width: index === 0 ? 28 : index === 1 ? 12 : 14
            height: index === 0 ? 12 : index === 1 ? 12 : 7
            scale: wrapping ? 0.6 : 1
            opacity: wrapping ? 0.4 : 1
            Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
            Behavior on scale { NumberAnimation { duration: 160 } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            onSlotChanged: wrapTimer.restart()
            Timer { id: wrapTimer; interval: 320; onTriggered: jelly.prevSlot = jelly.slot }

            Rectangle { visible: jelly.index === 0; anchors.fill: parent; radius: 6; color: Theme.kisel }
            Rectangle { visible: jelly.index === 1; anchors.fill: parent; radius: 6; color: Theme.mint }
            BrandShape { visible: jelly.index === 2; kind: "halfRound"; scale: 14 / 200; transformOrigin: Item.TopLeft }
        }
    }
}
