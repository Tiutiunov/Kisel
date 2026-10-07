// The GitHub widget (660 x 276). Opening it changes the mascot's skin (350 ms,
// done by the Island). One big number, status chips, a spinning refresh icon
// while the request runs; the jelly trio while the first load has no content.
import QtQuick
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)

    width: 494
    onActiveChanged: {
        if (!active) { contentReady = GitHub.loaded; trio.reset() }
        GitHub.polling = active
        if (active && GitHub.hasToken && (!GitHub.loaded || true))
            GitHub.refresh()
    }

    // ---- no token yet ----
    Column {
        visible: !GitHub.hasToken
        anchors.centerIn: parent
        spacing: Theme.space3
        DotWave { anchors.horizontalCenter: parent.horizontalCenter; running: root.active && !GitHub.hasToken }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Add a GitHub token")
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.ExtraBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("Settings → GitHub. A read-only personal access token is enough.")
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
        }
    }

    // ---- loading with nothing to show: the jelly trio, which merges into a check
    // (or a shaking danger pill) when the first load ends ----
    property bool contentReady: false
    JellyTrio {
        id: trio
        anchors.centerIn: parent
        running: GitHub.hasToken && GitHub.loading && !GitHub.loaded && root.active
        onResolved: { root.contentReady = true; trio.reset() }
    }
    Connections {
        target: GitHub
        function onFirstLoaded() { if (root.active && !Theme.reduced) trio.resolve(true); else root.contentReady = true }
        function onChanged() {
            // the first attempt failed: the wait ends in an error
            if (!GitHub.loading && !GitHub.loaded && GitHub.error !== "" && trio.running) trio.resolve(false)
        }
    }

    // ---- content ----
    Item {
        anchors.fill: parent
        visible: GitHub.hasToken && ((GitHub.loaded && (root.contentReady || !trio.resolving)) || GitHub.error !== "") && !(trio.resolving && trio.outcome === "ok")
        opacity: GitHub.loaded ? 1 : 0.5
        Behavior on opacity { NumberAnimation { duration: Theme.tFast } }

        // the figures: one big number per widget
        Row {
            id: figures
            opacity: Motion.rise(root.age, 0)
            transform: Translate { y: Motion.lift(root.age, 0) }
            spacing: Theme.space6
            Column {
                Text { text: GitHub.openCount; color: Theme.ink; font.family: Theme.sans; font.pixelSize: 26; font.weight: Font.ExtraBold }
                Text { text: Tr.t("open PRs"); color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
            Column {
                Text { text: GitHub.reviewCount; color: GitHub.reviewCount > 0 ? Theme.amber : Theme.ink
                    font.family: Theme.sans; font.pixelSize: 26; font.weight: Font.ExtraBold }
                Text { text: Tr.t("waiting for your review"); color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }

        // refresh: turns once per 900 ms while loading, stops where it is
        Item {
            id: refresh
            anchors.right: parent.right
            width: 32; height: 32
            Accessible.role: Accessible.Button
            Accessible.name: Tr.t("Refresh")
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
                                    text: row.modelData.draft ? Tr.t("Draft") : chip.ci === "success" ? Tr.t("Passing") : chip.ci === "failure" ? Tr.t("Failing")
                                        : chip.ci === "pending" ? Tr.t("Running") : Tr.t("No checks") }
                            }
                        }
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: rowTap; onTapped: Launcher.openUrl(row.modelData.url) }
                }
            }
            Text {
                visible: GitHub.loaded && GitHub.rows.length === 0
                text: Tr.t("No open pull requests")
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
                Text { width: 440; elide: Text.ElideRight; text: Tr.d(GitHub.error); color: Theme.danger
                    font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold }
            }
        }
    }
}
