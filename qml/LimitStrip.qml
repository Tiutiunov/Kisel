// How much of the Claude allowance is used, in the open card's header while it shows
// Claude's Home: the five-hour window and the week, each a small candy cane with its
// share and when it resets. Only there once a sign-in key has been saved in Settings;
// if the figures could not be had, one quiet line says why.
import QtQuick
import Kisel.Core

Row {
    id: root
    spacing: 12
    height: 24
    visible: Limits.state !== "none"

    function heat(v) { return v > 0.9 ? "#E0405A" : v > 0.7 ? "#FFE08A" : "#39C5BB" }

    Text {
        visible: Limits.state === "error" || Limits.state === "loading"
        anchors.verticalCenter: parent.verticalCenter
        width: 260
        elide: Text.ElideRight
        text: Limits.state === "loading" ? "Asking for the limit" : "Limit: " + Limits.error
        color: Theme.inkFaint
        font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
    }
    Cane { visible: Limits.state === "ok"; name: "5 h"; value: Limits.fiveHour; note: Limits.fiveHourReset }
    Cane { visible: Limits.state === "ok"; name: "Week"; value: Limits.week; note: Limits.weekReset }

    component Cane: Item {
        id: cane
        property string name: ""
        property real value: 0
        property string note: ""
        width: 118; height: 24
        anchors.verticalCenter: parent.verticalCenter
        Text {
            y: 0
            text: cane.name
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
        }
        Text {
            anchors.right: parent.right
            y: 0
            text: Math.round(cane.value * 100) + "%" + (cane.note !== "" ? "  ·  " + cane.note : "")
            color: cane.value > 0.9 ? "#FF8FA0" : Theme.ink
            font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.ExtraBold
        }
        Rectangle {
            y: 13
            width: parent.width; height: 9; radius: 4.5
            color: "#2b2430"
            border.width: 1.5; border.color: cane.value > 0.9 ? "#E0405A" : "#FFFFFF"
            Rectangle {
                x: 2.5; y: 2.5
                height: 4; radius: 2
                width: Math.max(4, (parent.width - 5) * Math.min(1, cane.value))
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                color: root.heat(cane.value)
            }
        }
    }
}
