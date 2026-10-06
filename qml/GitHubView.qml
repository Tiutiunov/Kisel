// The GitHub widget (660 x 276). Opening it changes the mascot's skin (350 ms,
// done by the Island). One big number, status chips, a spinning refresh icon
// while the request runs; the jelly trio while the first load has no content.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false

    width: 494
    opacity: active ? 1 : 0
    visible: opacity > 0
    enabled: active
    Behavior on opacity { NumberAnimation { duration: Theme.tFast } }
    onActiveChanged: {
        GitHub.polling = active
        if (active && GitHub.hasToken && (!GitHub.loaded || true))
            GitHub.refresh()
    }

    // the first successful load: the pill becomes a disc, a check draws itself
    Connections {
        target: GitHub
        function onFirstLoaded() { okPill.visible = true; okPill.success("Connected"); okHide.restart() }
    }
    Timer { id: okHide; interval: 2600; onTriggered: okPill.visible = false }
    KButton {
        id: okPill
        visible: false
        z: 3
        anchors.right: parent.right
        anchors.rightMargin: 40
        variant: "primary"
        text: "Connected"
    }

    // ---- no token yet ----
    Column {
        visible: !GitHub.hasToken
        anchors.centerIn: parent
        spacing: Theme.space3
        DotWave { anchors.horizontalCenter: parent.horizontalCenter; running: root.active && !GitHub.hasToken }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Add a GitHub token"
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.ExtraBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: "Settings → GitHub. A read-only personal access token is enough."
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
        }
    }

    // ---- loading with nothing to show ----
    JellyTrio {
        anchors.centerIn: parent
        running: GitHub.hasToken && GitHub.loading && !GitHub.loaded && root.active
    }

    // ---- content ----
    Item {
        anchors.fill: parent
        visible: GitHub.hasToken && (GitHub.loaded || GitHub.error !== "")
        opacity: GitHub.loaded ? 1 : 0.5
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

        // the figures: one big number per widget
        Row {
            id: figures
            spacing: Theme.space6
            Column {
                Text { text: GitHub.openCount; color: Theme.ink; font.family: Theme.sans; font.pixelSize: 26; font.weight: Font.ExtraBold }
                Text { text: "open PRs"; color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
            Column {
                Text { text: GitHub.reviewCount; color: GitHub.reviewCount > 0 ? Theme.amber : Theme.ink
                    font.family: Theme.sans; font.pixelSize: 26; font.weight: Font.ExtraBold }
                Text { text: "waiting for your review"; color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }

        // refresh: turns once per 900 ms while loading, stops where it is
        Item {
            id: refresh
            anchors.right: parent.right
            width: 32; height: 32
            Accessible.role: Accessible.Button
            Accessible.name: "Refresh"
            Rectangle { anchors.fill: parent; radius: 16; color: rh.hovered || rt.pressed ? Theme.surface3 : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.tHover } } }
            Icon {
                id: refreshIcon
                anchors.centerIn: parent
                size: 20
                name: "refresh"
                color: rh.hovered ? Theme.ink : Theme.inkMuted
                RotationAnimator on rotation {
                    id: spin
                    from: refreshIcon.rotation; to: refreshIcon.rotation + 360
                    duration: 900
                    loops: Animation.Infinite
                    running: GitHub.loading
                }
            }
            HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: rt; onTapped: GitHub.refresh() }
        }

        // pull requests with their CI state
        Column {
            y: figures.height + Theme.space3
            width: parent.width
            spacing: Theme.space1
            Repeater {
                model: GitHub.rows
                Rectangle {
                    id: row
                    required property var modelData
                    width: parent.width
                    height: 34
                    radius: Theme.radiusSm
                    color: rowHover.hovered || rowTap.pressed ? Theme.surface3 : Theme.surface2
                    Behavior on color { ColorAnimation { duration: Theme.tHover } }
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space2
                        Text {
                            width: parent.width - chip.width - Theme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: row.modelData.title + "  "
                            color: Theme.ink
                            font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.ExtraBold
                            Text { anchors.left: parent.left; anchors.leftMargin: parent.contentWidth; anchors.verticalCenter: parent.verticalCenter
                                visible: parent.width - parent.contentWidth > 60
                                text: row.modelData.repo + " #" + row.modelData.number; color: Theme.inkFaint
                                font.family: Theme.mono; font.pixelSize: 11 }
                        }
                        // status chip: dot plus word, never colour alone
                        Rectangle {
                            id: chip
                            anchors.verticalCenter: parent.verticalCenter
                            height: 22; width: chipRow.implicitWidth + 20; radius: 11
                            color: Theme.surface0
                            readonly property string ci: row.modelData.ci
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                                    color: chip.ci === "success" ? Theme.mint : chip.ci === "failure" ? Theme.danger
                                         : chip.ci === "pending" ? Theme.amber : Theme.inkFaint }
                                Text { anchors.verticalCenter: parent.verticalCenter; color: Theme.ink
                                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
                                    text: row.modelData.draft ? "Draft" : chip.ci === "success" ? "Passing" : chip.ci === "failure" ? "Failing"
                                        : chip.ci === "pending" ? "Running" : "No checks" }
                            }
                        }
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: rowTap; onTapped: Launcher.openUrl(row.modelData.url) }
                }
            }
            Text {
                visible: GitHub.loaded && GitHub.rows.length === 0
                text: "No open pull requests"
                color: Theme.inkFaint
                font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
            }
        }

        // error line on diff-del-bg
        Rectangle {
            visible: GitHub.error !== ""
            y: parent.height - height
            width: parent.width; height: 26; radius: Theme.radiusSm
            color: Theme.diffDelBg
            Row { x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.space1
                Icon { name: "cross"; size: 14; color: Theme.danger; anchors.verticalCenter: parent.verticalCenter }
                Text { width: 440; elide: Text.ElideRight; text: GitHub.error; color: Theme.danger
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
        }
    }
}
