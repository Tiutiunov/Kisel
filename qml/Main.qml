import QtQuick
import Kisel.Core

// The window's root: one fixed transparent surface (see IslandWindow). The
// island hangs from its top edge; the compositor centres the surface on the
// screen, and the input region is clipped to the island by Shell.setHitRect.
Item {
    id: root
    width: 708
    height: 500

    function openIsland(view) { island.openIsland(view) }

    Island {
        id: island
        anchors.fill: parent
        focus: true
    }
}
