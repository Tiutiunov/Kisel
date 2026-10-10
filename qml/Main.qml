import QtQuick
import Kisel.Core

// The window's root. Normally the surface is the fixed one (see IslandWindow): the
// island's 708 x 500 with clear room at each side (Shell.pad) for a mascot who leans
// out of the card. While the mascot is being dragged the surface covers the whole
// output and the island stays where it was inside it.
Item {
    id: root
    width: 708 + 2 * Shell.pad
    height: 500

    // The window hops when a full-screen program comes to the front or leaves (the bar
    // goes down to the edge the taskbar held, and back). The island does not hop with
    // it: it starts where it was on the screen and glides to its new place. Going up,
    // it comes out from under the window's edge, which is where the taskbar is.
    property real glideX: 0
    property real glideY: 0
    Connections {
        target: Shell
        function onHopped(dx, dy) {
            if (Theme.reduced || Shell.viewWide) return
            glide.stop()
            root.glideX = dx; root.glideY = dy
            glide.start()
        }
    }
    ParallelAnimation {
        id: glide
        NumberAnimation { target: root; property: "glideX"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "glideY"; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }

    function openIsland(view) { island.openIsland(view) }
    function runIntro() { island.runIntro() }
    function devDock(edge, frac) { island.devDock(edge, frac) }          // development only
    function devToast(text) { island.showToast(text) }
    function devGrab() { Shell.beginGrab() }
    function devState() { return island.devState() }
    function devClose() { island.collapseNow() }                         // development only
    function devCenter() { return island.devCenter() }

    // Claude Code's hooks went missing or stale: say so; the fix itself is confirmed in Settings.
    Connections {
        target: Hooks
        function onAttention(state) {
            island.showToast(state === "stale" ? Tr.t("Claude Code hooks need repair. Open Settings.")
                                               : Tr.t("Claude Code is not connected. Open Settings."))
        }
        function onRepaired() { island.showToast(Tr.t("Claude Code hooks repaired")) }
    }

    Island {
        id: island
        width: 708
        height: 500
        x: (Shell.viewWide ? Shell.grabX : Shell.pad) + root.glideX
        y: (Shell.viewWide ? Shell.grabY : 0) + root.glideY
        focus: true
    }
}
