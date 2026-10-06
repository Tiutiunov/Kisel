import QtQuick
import Kisel.Core

// The window's root. Normally the surface is the fixed 708 x 500 one (see
// IslandWindow) and the island fills it. While the mascot is being dragged the
// surface covers the whole output and the island stays where it was inside it.
Item {
    id: root
    width: 708
    height: 500

    function openIsland(view) { island.openIsland(view) }
    function runIntro() { island.runIntro() }
    function devDock(edge, frac) { island.devDock(edge, frac) }          // development only
    function devToast(text) { island.showToast(text) }
    function devGrab() { Shell.beginGrab() }
    function devState() { return island.devState() }
    function devCenter() { return island.devCenter() }

    Island {
        id: island
        width: 708
        height: 500
        x: Shell.viewWide ? Shell.grabX : 0
        y: Shell.viewWide ? Shell.grabY : 0
        focus: true
    }
}
