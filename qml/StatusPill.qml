// components/StatusBadges: a dot plus a word for Idle, Working, Needs you,
// Done, Failed. Colour never stands alone.
import QtQuick

Rectangle {
    id: root
    property string state: "idle" // idle | work | think | alert | done | failed

    readonly property string word: state === "work" ? Tr.t("Working") : state === "think" ? Tr.t("Thinking")
        : state === "alert" ? Tr.t("Needs you") : state === "done" ? Tr.t("Done") : state === "failed" ? Tr.t("Failed") : Tr.t("Idle")
    readonly property color dot: state === "work" || state === "think" ? Theme.info
        : state === "alert" ? Theme.amber : state === "done" ? Theme.mint
        : state === "failed" ? Theme.danger : Theme.inkFaint

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 24
    radius: Theme.radiusPill
    color: Theme.surface2

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle { width: 8; height: 8; radius: 4; color: root.dot; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: root.word
            color: Theme.ink
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
        }
    }
}
