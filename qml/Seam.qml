// What a seam window shows: the mascot, at the position the island shares with it,
// clipped by the window's own bounds. No input, no card, nothing else.
import QtQuick

Item {
    Mascot {
        size: seam.size
        x: seam.cx - seam.size / 2
        y: seam.cy - seam.size / 2
        mood: seam.mood
        character: Prefs.faces[Prefs.character] || Prefs.character
        dragging: true
        dragVx: seam.vx
        dragVy: seam.vy
    }
}
