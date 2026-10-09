// Pill button, 36 px high (components/Buttons).
//   primary   = kisel fill: Allow, Send, Connect
//   secondary = surface-3: Always
//   ghost     = transparent with a 1.5 px ink-faint ring: Cancel, In terminal
//   danger    = danger fill: Deny
// Focus is a 3 px kisel ring (offset 2); disabled drops to 40 % opacity.
// Press: scale 0.96 in 80 ms. Hover: a lift in 100 ms.
//
// success(word): the "success" move from motion.md. The pill shrinks to a disc
// of its own height (220 ms OutCubic) turning mint, a check draws itself
// (180 ms), then it widens back into a pill reading `word` and holds 1.2 s.
import QtQuick
import Kisel.Core

FocusScope {
    id: root
    property string text: ""
    property string icon: ""
    property string variant: "secondary" // primary | secondary | ghost | danger
    property bool primary: false         // shorthand for variant: "primary"
    property bool danger: false          // shorthand for variant: "danger"
    signal clicked()

    readonly property string kind: primary ? "primary" : danger ? "danger" : variant

    // success state
    property bool celebrating: false
    property string successWord: ""
    property real shrink: 0 // 0 = pill, 1 = disc
    property real tick: 0   // check progress 0..1
    property bool showWord: false

    function success(word) {
        successWord = word
        celebrating = true
        showWord = false
        if (Theme.reduced) {
            shrink = 0; tick = 1; showWord = true
            holdTimer.interval = 1500; holdTimer.restart()
            return
        }
        successAnim.restart()
    }

    readonly property real pillW: row.implicitWidth + 36
    implicitWidth: celebrating ? (shrink > 0.5 && !showWord ? 36 : Math.max(36, wordRow.implicitWidth + 36)) : pillW
    implicitHeight: 36
    activeFocusOnTab: true
    enabled: !celebrating
    opacity: 1
    Accessible.role: Accessible.Button
    Accessible.name: celebrating ? successWord : text
    Accessible.onPressAction: root.clicked()

    // keeps the layout still while the visible pill morphs
    readonly property color fg: celebrating ? Theme.kiselInk
        : kind === "primary" ? Theme.kiselInk : kind === "danger" ? Theme.surface0
        : kind === "ghost" ? Theme.inkMuted : Theme.ink

    Rectangle {
        id: bg
        anchors.centerIn: parent
        height: parent.height
        width: root.celebrating ? (root.showWord ? Math.max(36, wordRow.implicitWidth + 36)
                                                  : 36 + (root.pillW - 36) * (1 - root.shrink))
                                : parent.width
        radius: Theme.radiusPill
        opacity: root.enabled || root.celebrating ? 1 : 0.4
        color: {
            if (root.celebrating) return Theme.mint
            const k = root.kind
            const pressed = tap.pressed, hov = hover.hovered
            if (k === "primary") return pressed ? Theme.kiselDeep : Theme.kisel
            if (k === "danger") return pressed ? Qt.darker(Theme.danger, 1.15) : Theme.danger
            if (k === "ghost") return pressed || hov ? Theme.surface2 : "transparent"
            return pressed || hov ? Theme.line : Theme.surface3
        }
        Behavior on color { ColorAnimation { duration: Theme.tHover } }
        scale: tap.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Theme.tPress } }
        border.width: root.kind === "ghost" && !root.celebrating ? 1.5 : 0
        border.color: Theme.inkFaint

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.space1
            visible: !root.celebrating
            Icon { visible: root.icon !== ""; name: root.icon; size: 16; color: root.fg; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: root.text
                color: root.fg
                font.family: Theme.sans
                font.pixelSize: 14
                font.weight: Font.ExtraBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            id: wordRow
            anchors.centerIn: parent
            spacing: Theme.space1
            visible: root.celebrating && root.showWord
            DrawnCheck { size: 16; progress: 1; color: Theme.kiselInk; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: root.successWord
                color: Theme.kiselInk
                font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.ExtraBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        DrawnCheck {
            anchors.centerIn: parent
            size: 18
            progress: root.tick
            color: Theme.kiselInk
            visible: root.celebrating && !root.showWord
        }
    }

    // focus ring: solid 3 px kisel, 2 px off the pill
    Rectangle {
        anchors.fill: bg
        anchors.margins: -5
        visible: root.activeFocus && !root.celebrating
        radius: Theme.radiusPill
        color: "transparent"
        border.width: 3
        border.color: Theme.kisel
        x: bg.x
    }

    SequentialAnimation {
        id: successAnim
        NumberAnimation { target: root; property: "shrink"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "tick"; from: 0; to: 1; duration: 180 }
        PauseAnimation { duration: 400 }
        ScriptAction { script: root.showWord = true }
        PauseAnimation { duration: 220 + 1200 }
        ScriptAction { script: { root.celebrating = false; root.shrink = 0; root.tick = 0; root.showWord = false } }
    }
    Timer { id: holdTimer; onTriggered: { root.celebrating = false; root.tick = 0; root.showWord = false } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered && root.enabled) Sfx.play("hover")
    }
    TapHandler { id: tap; onTapped: root.clicked() }
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
