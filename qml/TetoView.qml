// Teto's Home: how the computer is doing. It takes the whole of Home's place
// (494 x 138), in the sticker style of Zundamon's player and in Teto's red.
//
// Round gauges with a white edge for the processor, the graphics card and the memory; a row of candy bars with the processor's last minute; and a line from
// Teto herself, who has an opinion about all of it. The memory's ring is a key too: a
// broom sits on its rim, a click cleans the memory (see SysMon), and she reports what
// that freed.
//
// Where the machine tells (see SysMon: the fans, the temperatures), a fan turns inside
// the processor's ring and the graphics card's, as fast as the real one, with its turns
// a minute under the figure, and the temperature stands under the name. Under the row of
// bars are the drives and how full each is (two show; the rest scroll).
import QtQuick
import Kisel.Core

Item {
    id: root
    property real age: 800 // ms since shown; blocks rise from it (Motion.rise)
    width: 494
    height: 138

    readonly property color red: "#E0405A"
    readonly property color pink: "#FF9EBB"
    readonly property color lemon: "#FFE08A"
    function pct(v) { return Math.round(v * 100) + "%" }
    // room on a drive, in words
    function room(gb) { return gb >= 1000 ? (gb / 1024).toFixed(1) + Tr.t(" TB") : gb >= 10 ? Math.round(gb) + Tr.t(" GB") : gb.toFixed(1) + Tr.t(" GB") }
    // the drive with next to no room left, if there is one
    readonly property string fullDrive: { for (const d of Sys.disks) if (d.used > 0.97 || d.freeGb < 5) return d.name; return "" }
    readonly property bool hasDrives: Sys.disks.length > 0
    // The pointer on a ring: the column beside the rings gives way to all that is known
    // of that part ("" | cpu | gpu). Only what the machine tells is listed.
    property string peek: ""
    function facts(which) {
        const out = []
        const add = (k, v) => out.push({ k: k, v: v })
        if (which === "cpu") {
            add(Tr.t("Load"), root.pct(Sys.cpu))
            if (Sys.cpuMhz > 0) add(Tr.t("Frequency"), Sys.cpuMhz + Tr.t(" MHz"))
            if (Sys.cpuTemp > 0) add(Tr.t("Temperature"), Sys.cpuTemp + "°C")
            if (Sys.cpuFan >= 0) add(Tr.t("Fan"), Sys.cpuFan + Tr.t(" rpm"))
            if (Sys.cpuThreads > 0) add(Tr.t("Threads"), "" + Sys.cpuThreads)
        } else if (which === "gpu") {
            add(Tr.t("Load"), root.pct(Sys.gpu))
            if (Sys.gpuMemTotalMb > 0) add(Tr.t("Memory"), Sys.gpuMemUsedMb + " / " + Sys.gpuMemTotalMb + Tr.t(" MB"))
            if (Sys.gpuMhz > 0) add(Tr.t("Frequency"), Sys.gpuMhz + Tr.t(" MHz"))
            if (Sys.gpuTemp > 0) add(Tr.t("Temperature"), Sys.gpuTemp + "°C")
            if (Sys.gpuWatts >= 0) add(Tr.t("Power (TGP)"), Sys.gpuWatts.toFixed(Sys.gpuWatts < 10 ? 1 : 0) + (Sys.gpuWattsMax > 0 ? " / " + Math.round(Sys.gpuWattsMax) : "") + Tr.t(" W"))
            if (Sys.gpuFan >= 0) add(Tr.t("Fan"), Sys.gpuFan + Tr.t(" rpm"))
        }
        return out
    }
    function byFullness(list) { return list.slice().sort((a, b) => b.used - a.used) }
    // (the fans, the temperatures and the drives are read only while this card is looked at)
    Binding { target: Sys; property: "watching"; value: root.visible }
    // how full a gauge is decides its colour: calm, busy, too much
    function heat(v) { return v > 0.9 ? root.red : v > 0.7 ? root.lemon : "#B9DC6B" }

    readonly property string line: !Sys.available ? Tr.t("I cannot see this machine from here.")
        : Sys.cleaning ? Tr.t("Sweeping the memory. Stand back.")
        : Sys.justCleaned ? (Sys.freedGb >= 0.05 ? Tr.t("Freed ") + Sys.freedGb.toFixed(1) + Tr.t(" GB. You are welcome.") : Tr.t("Nothing much to free. It was tidy already."))
        : Sys.worry === "mem" ? Tr.t("The memory is full. Close something, will you?")
        : Sys.worry === "cpu" ? Tr.t("The processor is flat out. What are you running?")
        : Math.max(Sys.cpuTemp, Sys.gpuTemp) >= 92 ? Tr.t("It is roasting in here. Give it some air.")
        : root.fullDrive !== "" ? Tr.t("Drive ") + root.fullDrive.replace(":", "") + Tr.t(" is nearly full. Tidy up, will you?")
        : Sys.gpu > 0.85 ? Tr.t("The graphics card is flat out. Playing, are we?")
        : Sys.cpu > 0.6 ? Tr.t("Busy, but nothing I cannot handle.")
        : Sys.mem > 0.8 ? Tr.t("A lot is open. Not that I am counting.")
        : Tr.t("All quiet. Thanks to me, obviously.")

    Row {
        id: gauges
        x: 8; y: 12
        spacing: 14
        opacity: Motion.rise(root.age, 0)
        transform: Translate { y: Motion.lift(root.age, 0) }
        Gauge { part: "cpu"; value: Sys.cpu; name: "CPU"; fan: Sys.cpuFan; note: Sys.cpuTemp > 0 ? Sys.cpuTemp + "°C" : "" }
        Gauge { part: "gpu"; visible: Sys.hasGpu; value: Sys.gpu; name: "GPU"; fan: Sys.gpuFan; note: Sys.gpuTemp > 0 ? Sys.gpuTemp + "°C" : "" }
        // (the memory's ring is also the key that cleans it: what is cleaned is what it shows)
        Gauge { action: Sys.canClean; busy: Sys.cleaning; actionName: Tr.t("Clean memory"); onClicked: Sys.clean()
                value: Sys.mem; name: Tr.t("Memory"); note: Sys.memUsedGb.toFixed(1) + " / " + Math.round(Sys.memTotalGb) + Tr.t(" GB") }
    }

    // all that is known of the part the pointer is on
    Item {
        id: sheet
        x: side.x; y: side.y
        width: side.width; height: side.height
        opacity: root.peek !== "" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Theme.reduced ? 0 : 140 } }
        property string shown: root.peek !== "" ? root.peek : "cpu" // (the one last looked at stays while it fades)
        Connections { target: root; function onPeekChanged() { if (root.peek !== "") sheet.shown = root.peek } }
        Text {
            width: parent.width
            text: sheet.shown === "gpu" ? (Sys.gpuName !== "" ? Sys.gpuName : "GPU") : (Sys.cpuName !== "" ? Sys.cpuName : "CPU")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.ExtraBold
        }
        Column {
            y: 19
            width: parent.width
            spacing: 1.5
            Repeater {
                model: root.facts(sheet.shown)
                Item {
                    id: fact
                    required property var modelData
                    width: sheet.width; height: 14
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: fact.modelData.k
                        color: Theme.inkMuted
                        font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.DemiBold
                    }
                    Text {
                        x: parent.width - width
                        anchors.verticalCenter: parent.verticalCenter
                        text: fact.modelData.v
                        color: Theme.ink
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                }
            }
        }
    }

    Item {
        id: side
        x: gauges.x + gauges.width + 18
        y: 12
        width: parent.width - x - 6
        height: parent.height - 24
        opacity: root.peek !== "" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.reduced ? 0 : 140 } }

        Row {
            spacing: 6
            opacity: Motion.rise(root.age, 1)
            transform: Translate { y: Motion.lift(root.age, 1) }
            Spark { anchors.verticalCenter: parent.verticalCenter; size: 11; tint: root.red
                RotationAnimation on rotation { running: root.visible && !Theme.reduced; from: 0; to: 90; duration: 3000; loops: Animation.Infinite } }
            Text {
                text: Tr.t("The last minute")
                color: Theme.inkMuted
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }

        // the drives, and how full each is: one or two take a line each, with words; three
        // or four stand two to a line, without; more than that, and the fullest come first
        // and the rest scroll
        GridView {
            id: drives
            readonly property bool pairs: count > 2
            visible: root.hasDrives
            y: 42
            width: side.width + (pairs ? 8 : 0) // (the gap between the two of a line)
            height: 25
            clip: true
            cellWidth: pairs ? width / 2 : width
            cellHeight: 12.5
            boundsBehavior: Flickable.StopAtBounds
            opacity: Motion.rise(root.age, 2)
            model: count > 4 || Sys.disks.length > 4 ? root.byFullness(Sys.disks) : Sys.disks
            delegate: Item {
                id: drive
                required property var modelData
                width: drives.cellWidth - (drives.pairs ? 8 : 0)
                height: 10.5
                Text {
                    id: driveName
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    text: drive.modelData.name
                    textFormat: Text.PlainText
                    color: Theme.ink
                    font.family: Theme.sans; font.pixelSize: 10; font.weight: Font.ExtraBold
                }
                Rectangle {
                    x: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: driveFree.x - x - 6
                    height: 7; radius: 3.5
                    color: Theme.well
                    Rectangle {
                        width: Math.max(height, parent.width * Math.min(1, drive.modelData.used))
                        height: parent.height; radius: parent.radius
                        color: root.heat(drive.modelData.used)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    id: driveFree
                    x: drive.width - width
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.room(drive.modelData.freeGb) + (drives.pairs ? "" : Tr.t(" free"))
                    color: Theme.inkMuted
                    font.family: Theme.mono; font.pixelSize: 9
                }
            }
        }

        // the processor's last minute, one bar a reading
        Row {
            id: bars
            y: root.hasDrives ? 18 : 20
            height: root.hasDrives ? 20 : 38
            spacing: 2
            opacity: Motion.rise(root.age, 2)
            Repeater {
                model: Sys.history
                Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.max(2, (side.width - 35 * 2) / 36)
                    height: root.hasDrives ? 3 + modelData * 17 : 4 + modelData * 34
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    radius: width / 2
                    anchors.bottom: parent.bottom
                    color: root.heat(modelData)
                    opacity: 0.35 + 0.65 * (index / 35)
                }
            }
        }

        // what Teto makes of it
        Rectangle {
            id: say
            y: 70
            width: side.width
            height: 42
            radius: 12
            color: Qt.rgba(root.red.r, root.red.g, root.red.b, Sys.strain ? 0.3 : 0.14)
            border.width: 2
            border.color: Qt.rgba(root.red.r, root.red.g, root.red.b, Sys.strain ? 1 : 0.45)
            opacity: Motion.rise(root.age, 3)
            transform: Translate { y: Motion.lift(root.age, 3) }
            Text {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.topMargin: 3; anchors.bottomMargin: 3
                verticalAlignment: Text.AlignVCenter
                text: root.line
                wrapMode: Text.WordWrap
                // (a long remark, or a long language: it goes to three lines and smaller letters before it is cut)
                maximumLineCount: 3
                fontSizeMode: Text.Fit; minimumPixelSize: 9
                elide: Text.ElideRight
                color: Theme.ink
                font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }
    }

    // a round gauge: a white-edged disc, a ring that fills, the figure in the middle
    component Gauge: Item {
        id: gauge
        property real value: 0
        property string name: ""
        property string note: ""
        property int fan: -1 // turns a minute, or -1: this machine does not tell
        // A gauge can be a key as well: a broom sits on its rim, and a click on the ring does the thing.
        property string part: "" // cpu | gpu: the pointer on it lists all that is known of it (see `peek`)
        HoverHandler { enabled: gauge.part !== ""; onHoveredChanged: { if (hovered) root.peek = gauge.part; else if (root.peek === gauge.part) root.peek = "" } }
        property bool action: false
        property bool busy: false
        property string actionName: ""
        signal clicked()
        width: 78; height: 114
        activeFocusOnTab: action
        Accessible.role: action ? Accessible.Button : Accessible.Indicator
        Accessible.name: action ? actionName : name
        Keys.onReturnPressed: if (action && !busy) clicked()
        Keys.onSpacePressed: if (action && !busy) clicked()
        Item {
            id: press
            width: 78; height: 78
            HoverHandler { id: gaugeHover; enabled: gauge.action; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Sfx.play("hover") }
            TapHandler { id: gaugeTap; enabled: gauge.action && !gauge.busy; onTapped: { Sfx.play("click"); gauge.clicked() } }
        }
        Canvas {
            id: ring
            width: 78; height: 78
            scale: gaugeTap.pressed ? 0.95 : gaugeHover.hovered && !gauge.busy ? 1.05 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            property real shown: gauge.value
            Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onShownChanged: requestPaint()
            property color tint: root.heat(gauge.value)
            onTintChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"), c = 39
                g.reset()
                g.lineCap = "round"
                g.strokeStyle = "#FFFFFF"; g.lineWidth = 12
                g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                g.strokeStyle = "" + Theme.well; g.lineWidth = 8
                g.beginPath(); g.arc(c, c, 31, 0, 2 * Math.PI, false); g.stroke()
                if (shown > 0.005) {
                    g.strokeStyle = tint; g.lineWidth = 8
                    g.beginPath(); g.arc(c, c, 31, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, shown), false); g.stroke()
                }
            }
        }
        // the fan, inside the ring: three blades that turn as fast as the real one
        Item {
            id: rotor
            visible: gauge.fan >= 0
            anchors.centerIn: ring
            width: 50; height: 50
            opacity: 0.2
            Repeater {
                model: 3
                Item {
                    required property int index
                    anchors.centerIn: parent
                    width: 50; height: 50
                    rotation: index * 120
                    Rectangle { x: 21; y: 2; width: 13; height: 23; radius: 6.5; color: Theme.ink; rotation: 18; transformOrigin: Item.Bottom }
                }
            }
            Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.ink }
            RotationAnimation on rotation {
                running: root.visible && gauge.fan > 0 && !Theme.reduced
                from: 0; to: 360; loops: Animation.Infinite
                // (a real fan turns too fast to look at: a turn in 2.4 s at 1000, 0.5 s at 5000)
                duration: Math.max(350, Math.min(3000, 2400000 / Math.max(800, gauge.fan)))
            }
        }
        Text {
            anchors.horizontalCenter: ring.horizontalCenter
            anchors.verticalCenter: ring.verticalCenter
            anchors.verticalCenterOffset: gauge.fan >= 0 ? -5 : 0
            text: root.pct(gauge.value)
            color: Theme.ink
            font.family: Theme.display; font.pixelSize: 17; font.weight: Font.Bold
        }
        Text {
            visible: gauge.fan >= 0
            anchors.horizontalCenter: ring.horizontalCenter
            y: ring.y + 45
            width: 46
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 6
            text: gauge.fan + Tr.t(" rpm")
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 8; font.weight: Font.ExtraBold
        }
        // the broom on the rim
        Rectangle {
            visible: gauge.action
            x: 53; y: 53
            width: 26; height: 26; radius: 13
            color: gauge.busy ? Theme.surface3 : root.red
            Behavior on color { ColorAnimation { duration: 200 } }
            border.width: gauge.activeFocus ? 3 : 2; border.color: "#FFFFFF"
            scale: gaugeTap.pressed ? 0.9 : gaugeHover.hovered && !gauge.busy ? 1.18 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            BroomGlyph {
                anchors.centerIn: parent
                size: 13
                opacity: gauge.busy ? 0.6 : 1
                transformOrigin: Item.TopRight
                SequentialAnimation on rotation {
                    running: gauge.busy && root.visible && !Theme.reduced
                    loops: Animation.Infinite
                    NumberAnimation { from: -14; to: 14; duration: 260; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 14; to: -14; duration: 260; easing.type: Easing.InOutSine }
                    onRunningChanged: if (!running) parent.rotation = 0
                }
            }
        }
        Text {
            y: 82
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: gauge.name
            color: Theme.ink
            font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.ExtraBold
        }
        Text {
            y: 98
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: gauge.note
            visible: gauge.note !== ""
            color: Theme.inkMuted
            font.family: Theme.sans; font.pixelSize: 9; font.weight: Font.DemiBold
        }
    }
}
