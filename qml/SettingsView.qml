// Settings: Claude Code connection, API key, appearance and sound, always-allow
// rules, quit. Keys go to the wallet and are never shown again.
import QtQuick
import QtQuick.Controls.Basic as C
import Kisel.Core

Item {
    id: root
    property bool active: false
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    signal toast(string text)
    readonly property bool inputFocus: keyField.inputFocus || ghField.inputFocus

    width: 494

    property var plan: null          // hooks preview being confirmed
    property bool planInstall: true
    property string note: ""
    property bool keySaved: false
    onActiveChanged: { if (active) { plan = null; note = "" } }

    Timer { id: clearPlan; interval: 2200; onTriggered: root.plan = null }
    // dock the island on `edge`, `fraction` of the way along it, and remember that for this monitor
    function place(edge, fraction) {
        const len = Shell.edgeLength(edge)
        const used = Shell.setDock(edge, fraction * len)
        Prefs.setDock(Displays.current, edge, used / len)
    }
    function startPlan(install) {
        planInstall = install
        plan = Hooks.preview(install)
    }
    function confirmPlan() {
        if (Hooks.apply(planInstall)) {
            // the pill becomes a disc, a check draws itself, then it reads "Connected"
            writeBtn.success(planInstall ? Tr.t("Connected") : Tr.t("Removed"))
            Sfx.play("done")
            clearPlan.restart()
        } else {
            note = Tr.t("Couldn't write settings.json")
        }
    }

    // (development: `--scroll <px>` with `--grab`, to look at what is further down)
    Timer {
        interval: 400
        running: Qt.application.arguments.indexOf("--scroll") > 0
        onTriggered: scroll.contentItem.contentY = Number(Qt.application.arguments[Qt.application.arguments.indexOf("--scroll") + 1])
    }
    // Rin has been clicked about an update: Settings opens at "Updates"
    function showUpdates() { toUpdates.restart() }
    Timer { id: toUpdates; interval: 380; onTriggered: scroll.contentItem.contentY = Math.max(0, updatesHead.y - 8) }
    C.ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        C.ScrollBar.vertical.policy: C.ScrollBar.AsNeeded

        Column {
            width: root.width - 12
            spacing: Theme.space3

            // ---- Claude Code ----
            Text { text: "Claude Code"; color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Row {
                spacing: Theme.space2
                Icon { name: Hooks.installed ? "check" : "cross"; size: 16
                    color: Hooks.installed ? Theme.mint : Theme.inkMuted; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.note !== "" ? root.note : Hooks.installed ? Tr.t("Connected") : Tr.t("Not connected")
                    color: Theme.ink; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                KButton {
                    visible: !root.plan
                    primary: !Hooks.installed
                    text: Hooks.installed ? Tr.t("Remove hooks") : Tr.t("Connect Claude Code")
                    onClicked: root.startPlan(!Hooks.installed)
                }
            }
            Column {
                visible: !!root.plan
                width: parent.width
                spacing: Theme.space2
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: root.plan && root.plan.ok ? Theme.inkMuted : Theme.danger
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                    text: !root.plan ? "" : !root.plan.ok ? Tr.d(root.plan.error)
                        : !root.plan.changed ? Tr.t("Nothing to change in ") + root.plan.path
                        : Tr.t("This is the exact change to ") + root.plan.path + Tr.t(". A backup is saved first as ") + root.plan.backup
                }
                CodePanel {
                    visible: !!root.plan && root.plan.ok && root.plan.changed
                    width: parent.width
                    height: 150
                    lines: root.plan && root.plan.ok ? root.plan.diff : []
                }
                Row {
                    spacing: Theme.space2
                    KButton { id: writeBtn; visible: !!root.plan && root.plan.ok && root.plan.changed; variant: "primary"; text: Tr.t("Write change"); onClicked: root.confirmPlan() }
                    KButton { variant: "ghost"; text: Tr.t("Cancel"); onClicked: root.plan = null }
                }
            }

            // ---- Claude chat ----
            Text { text: Tr.t("Chat"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Row {
                spacing: Theme.space2
                KField {
                    id: keyField
                    width: 280
                    echoMode: TextInput.Password
                    placeholder: root.keySaved ? Tr.t("Key saved in ") + Vault.storeName : Tr.t("Anthropic API key")
                    onAccepted: root.saveKey()
                }
                KButton { id: saveBtn; variant: "primary"; text: Tr.t("Save"); onClicked: root.saveKey() }
            }
            Text { text: Chat.model; color: Theme.inkFaint; font.family: Theme.mono; font.pixelSize: 11 }

            // ---- GitHub: a read-only token for the widget ----
            Text { text: "GitHub"; color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Row {
                spacing: Theme.space2
                KField {
                    id: ghField
                    width: 280
                    echoMode: TextInput.Password
                    placeholder: GitHub.hasToken ? Tr.t("Token saved in ") + Vault.storeName : Tr.t("Personal access token (read-only)")
                    onAccepted: root.saveGitHub()
                }
                KButton { id: ghSave; variant: "primary"; text: Tr.t("Save"); onClicked: root.saveGitHub() }
                KButton { visible: GitHub.hasToken; variant: "ghost"; text: Tr.t("Remove")
                    onClicked: { Vault.remove("github"); root.toast(Tr.t("GitHub token removed")) } }
            }

            // ---- screen: a little map of your monitors, tap one to move Kisel there ----
            Text { text: Tr.t("Screen"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Item {
                id: map
                width: parent.width
                height: 96
                readonly property var list: Displays.screens
                readonly property real minX: Math.min.apply(null, list.map(s => s.x))
                readonly property real minY: Math.min.apply(null, list.map(s => s.y))
                readonly property real maxX: Math.max.apply(null, list.map(s => s.x + s.w))
                readonly property real maxY: Math.max.apply(null, list.map(s => s.y + s.h))
                readonly property real k: Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY))
                // centre the whole map in the row
                readonly property real offX: (width - (maxX - minX) * k) / 2
                readonly property real offY: (height - (maxY - minY) * k) / 2

                Repeater {
                    model: map.list
                    Rectangle {
                        id: mon
                        required property var modelData
                        readonly property bool here: Displays.current === modelData.name
                        x: map.offX + (modelData.x - map.minX) * map.k
                        y: map.offY + (modelData.y - map.minY) * map.k
                        width: modelData.w * map.k - 4
                        height: modelData.h * map.k - 4
                        radius: 8
                        color: mh.hovered || tap.pressed ? Theme.surface3 : Theme.surface2
                        Behavior on color { ColorAnimation { duration: Theme.tHover } }
                        border.width: here ? 2 : 1
                        border.color: here ? Theme.kisel : Theme.line
                        scale: tap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.tPress } }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.label + (here ? Tr.t(", Kisel is here") : "")
                        Accessible.checked: here

                        // the island, drawn tiny at the top edge of the monitor it is on
                        Rectangle {
                            id: pill
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -1
                            width: mon.here ? 34 : 0
                            height: mon.here ? 9 : 0
                            radius: 4
                            color: Theme.kisel
                            Behavior on width { NumberAnimation { duration: Theme.tBase; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
                            Behavior on height { NumberAnimation { duration: Theme.tBase; easing.type: Theme.reduced ? Easing.OutCubic : Easing.OutBack } }
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(implicitWidth, mon.width - 12)
                                elide: Text.ElideRight
                                text: mon.modelData.name || mon.modelData.label
                                color: Theme.ink
                                font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(implicitWidth, mon.width - 12)
                                elide: Text.ElideRight
                                text: mon.modelData.w + "\u00d7" + mon.modelData.h
                                color: Theme.inkFaint
                                font.family: Theme.mono; font.pixelSize: 11
                            }
                        }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: tap; onTapped: { Displays.select(mon.modelData.name); root.toast(Tr.t("Kisel moved to ") + mon.modelData.name) } }
                    }
                }
            }
            Row {
                spacing: Theme.space2
                KButton {
                    visible: Displays.wanted !== ""
                    text: Tr.t("Follow primary")
                    onClicked: { Displays.select(""); root.toast(Tr.t("Following the primary monitor")) }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.inkMuted
                    font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
                    text: Displays.wanted === "" ? Tr.t("Kisel follows your primary monitor (") + Displays.current + Tr.t("), also after a restart")
                        : Tr.t("Kisel stays on ") + Displays.wanted + Tr.t(" until you restart it")
                }
            }

            // ---- who is on stage ----
            Text { text: Tr.t("Character"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Row {
                spacing: Theme.space2
                Repeater {
                    model: [{ id: "miku", name: "Miku" }, { id: "rin", name: "Rin" }, { id: "luka", name: "Luka" }, { id: "zunda", name: "Zundamon" }, { id: "teto", name: "Teto" }]
                    KButton {
                        required property var modelData
                        primary: Prefs.character === modelData.id
                        text: modelData.name
                        onClicked: Prefs.character = modelData.id
                    }
                }
            }

            KToggle { visible: Sys.available; label: Tr.t("Teto watches the computer"); checked: Prefs.tetoSystem; onToggled: (v) => Prefs.tetoSystem = v }
            KToggle { visible: Net.available; label: Tr.t("Luka watches the connection"); checked: Prefs.lukaNet; onToggled: (v) => Prefs.lukaNet = v }
            KToggle { visible: Notes.available; label: Tr.t("Rin announces notifications"); checked: Prefs.rinNotes; onToggled: (v) => Prefs.rinNotes = v }
            KToggle { visible: Media.available; label: Tr.t("Zundamon shows and steers Spotify"); checked: Prefs.zundaSpotify; onToggled: (v) => Prefs.zundaSpotify = v }

            // ---- look and sound ----
            Text { text: Tr.t("Look and sound"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            KToggle { label: Tr.t("Sounds"); checked: Prefs.soundOn; onToggled: (v) => Prefs.soundOn = v }
            KToggle { label: Tr.t("Reduce motion"); checked: Prefs.reduceMotion; onToggled: (v) => Prefs.reduceMotion = v }
            KSlider {
                from: 0; to: 10
                value: Prefs.closeDelay
                label: Prefs.closeDelay === 0 ? Tr.t("Close at once when the pointer leaves") : Tr.t("Close ") + Prefs.closeDelay + Tr.t(" s after the pointer leaves")
                onMoved: (v) => Prefs.closeDelay = v
            }
            // where the island sits: the edge, and how far along it
            Row {
                spacing: Theme.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Place")
                    color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Repeater {
                    model: [{ id: "top", name: Tr.t("Top") }, { id: "bottom", name: Tr.t("Bottom") }, { id: "left", name: Tr.t("Left") }, { id: "right", name: Tr.t("Right") }]
                    KButton {
                        required property var modelData
                        primary: Shell.edge === modelData.id
                        text: modelData.name
                        onClicked: root.place(modelData.id, Shell.along / Shell.edgeLength(Shell.edge))
                    }
                }
            }
            KSlider {
                id: alongSlider
                from: 0; to: 20
                value: Math.round(Shell.along / Shell.edgeLength(Shell.edge) * 20)
                label: value === 10 ? Tr.t("In the middle of the edge") : (Shell.edge === "left" || Shell.edge === "right" ? (value < 10 ? Tr.t("Toward the top") : Tr.t("Toward the bottom")) : (value < 10 ? Tr.t("Toward the left") : Tr.t("Toward the right")))
                onMoved: (v) => root.place(Shell.edge, v / 20)
            }
            KToggle { label: Tr.t("Start when I sign in"); checked: Shell.autostart; onToggled: (v) => Shell.autostart = v }
            KToggle { visible: Shell.canAvoidPanels; label: Tr.t("Stay clear of the taskbar"); checked: Prefs.avoidPanels; onToggled: (v) => Prefs.avoidPanels = v }
            Row {
                spacing: Theme.space2
                Repeater {
                    model: [{ id: "system", name: Tr.t("System") }, { id: "dark", name: Tr.t("Dark") }, { id: "light", name: Tr.t("Light") }]
                    KButton {
                        required property var modelData
                        primary: Prefs.theme === modelData.id
                        text: modelData.name
                        onClicked: Prefs.theme = modelData.id
                    }
                }
            }

            // ---- the interface's language ----
            Row {
                spacing: Theme.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Language")
                    color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Repeater {
                    model: [{ id: "en", name: "English" }, { id: "ru", name: "\u0420\u0443\u0441\u0441\u043a\u0438\u0439" }]
                    KButton {
                        required property var modelData
                        primary: Tr.lang === modelData.id
                        text: modelData.name
                        onClicked: Prefs.language = modelData.id
                    }
                }
            }

            // ---- updates: Kisel asks GitHub at start and once a day (one question, nothing
            // about you in it), unless that is switched off; it installs nothing by itself ----
            Text { id: updatesHead; visible: Updates.available; text: Tr.t("Updates"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Row {
                visible: Updates.available
                spacing: Theme.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 250)
                    wrapMode: Text.WordWrap
                    text: Updates.state === "checking" ? Tr.t("Asking GitHub...")
                        : Updates.state === "current" ? "Kisel " + Updates.current + Tr.t(" is the newest")
                        : Updates.state === "found" ? "Kisel " + Updates.latest + Tr.t(" is out (you have ") + Updates.current + ")"
                        : Updates.state === "downloading" ? Tr.t("Downloading ") + Updates.latest + "  " + Math.round(Updates.progress * 100) + "%"
                        : Updates.state === "starting" ? Tr.t("Installing. Kisel will be right back.")
                        : "Kisel " + Updates.current
                    color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                KButton {
                    visible: Updates.state !== "found" && Updates.state !== "downloading" && Updates.state !== "starting"
                    enabled: Updates.state !== "checking"
                    icon: "refresh"; text: Tr.t("Check for updates")
                    onClicked: Updates.check()
                }
                KButton {
                    visible: Updates.state === "found"
                    variant: "primary"; text: Tr.t("Update and restart")
                    onClicked: Updates.update()
                }
            }
            KToggle { visible: Updates.available; label: Tr.t("Check for updates by itself"); checked: Prefs.updateCheck; onToggled: (v) => Prefs.updateCheck = v }
            Rectangle { // the download, as it comes
                visible: Updates.state === "downloading"
                width: 280; height: 6; radius: 3
                color: Theme.surface3
                Rectangle { width: parent.width * Updates.progress; height: parent.height; radius: 3; color: Theme.kisel }
            }
            Text {
                visible: Updates.available && Updates.state === "failed"
                width: parent.width
                wrapMode: Text.WordWrap
                text: Tr.d(Updates.error)
                color: Theme.danger; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold
            }

            // ---- always-allow ----
            Text { text: Tr.t("Always allowed"); color: Theme.ink; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            Row {
                spacing: Theme.space2
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Prefs.alwaysCount === 0 ? Tr.t("Nothing yet. \"Always\" on a card adds a rule here.")
                                                  : Prefs.alwaysCount + (Prefs.alwaysCount === 1 ? Tr.t(" rule") : Tr.t(" rules"))
                    color: Theme.inkMuted; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                KButton { visible: Prefs.alwaysCount > 0; variant: "danger"; text: Tr.t("Clear"); onClicked: { Prefs.clearAlwaysRules(); root.toast(Tr.t("Rules cleared")) } }
            }

            KButton { text: Tr.t("Quit Kisel"); variant: "danger"; onClicked: Shell.quit() }
            Item { width: 1; height: Theme.space2 }
        }
    }

    function saveGitHub() {
        if (ghField.text.trim() === "")
            return
        if (Vault.store("github", ghField.text.trim())) {
            ghField.text = ""
            ghSave.success(Tr.t("Saved"))
            Sfx.play("done")
        } else {
            note = Tr.t("Couldn't reach ") + Vault.storeName
        }
    }

    function saveKey() {
        if (keyField.text.trim() === "")
            return
        if (Vault.store("anthropic", keyField.text.trim())) {
            keyField.text = ""
            keySaved = true
            saveBtn.success(Tr.t("Saved"))
            Sfx.play("done")
        } else {
            note = Tr.t("Couldn't reach ") + Vault.storeName
        }
    }
}
