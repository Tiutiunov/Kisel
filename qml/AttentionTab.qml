// Permission arrives: the attention tab.
//  1. A 56 x 28 amber half-round slides out from under the card's bottom edge,
//     centred under the mascot, 200 ms OutBack, travelling 16 px.
//  2. It bobs 8 px down and back three times (1200 ms InOutSine each) while the
//     request waits, then rests as a small tab. Answered: it slides back under
//     the card in 160 ms InQuad.
//  3. Extra waiting requests show as dots on its face, 4 px, surface-0.
// Place it as the card's sibling *below* it in z-order.
import QtQuick

Item {
    id: root
    property real anchorX: 0       // centre x under the mascot
    property real cardBottom: 0    // y of the card's bottom edge
    property int waiting: 0

    readonly property bool shown: waiting > 0
    property real out: 0           // 0 = hidden under the card, 16 = out
    property real bob: 0

    x: anchorX - 28
    y: cardBottom - 28 + out + bob
    width: 56
    height: 28
    visible: out > 0.01 || shown

    onShownChanged: {
        if (shown) {
            hide.stop()
            reveal.restart()
        } else {
            reveal.stop(); bobAnim.stop(); bob = 0
            hide.restart()
        }
    }

    SequentialAnimation {
        id: reveal
        NumberAnimation { target: root; property: "out"; to: 16; duration: Theme.reduced ? 140 : 200; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack }
        ScriptAction { script: if (!Theme.reduced) bobAnim.restart() }
    }
    SequentialAnimation {
        id: bobAnim
        loops: 3
        NumberAnimation { target: root; property: "bob"; to: 8; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "bob"; to: 0; duration: 600; easing.type: Easing.InOutSine }
    }
    NumberAnimation { id: hide; target: root; property: "out"; to: 0; duration: Theme.reduced ? 140 : 160; easing.type: Easing.InQuad }

    BrandShape { kind: "halfRound"; scale: 56 / 200; transformOrigin: Item.TopLeft }

    // one dot per extra request
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        spacing: 4
        Repeater {
            model: Math.max(0, root.waiting - 1)
            Rectangle { width: 4; height: 4; radius: 2; color: Theme.surface0 }
        }
    }
}
