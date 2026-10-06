pragma Singleton
// Shared helpers for the transitions in motion.md ("Island size to size").
import QtQuick

QtObject {
    // How far block `i` of a view has risen, 0..1, `age` ms after the view was
    // shown: blocks start 40 ms apart and rise 8 px over 320 ms (OutCubic).
    // With "reduce motion" there is no staggering, only the 140 ms cross-fade.
    function rise(age, i) {
        if (Theme.reduced) return 1
        const x = Math.max(0, Math.min(1, (age - 40 * i) / 320))
        return 1 - Math.pow(1 - x, 3)
    }
    // and the offset that goes with it
    function lift(age, i) { return Theme.reduced ? 0 : (1 - rise(age, i)) * 8 }
}
