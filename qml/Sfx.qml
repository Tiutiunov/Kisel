pragma Singleton
// Short synthesised bloops (scripts/gen_sounds.py), played by the C++ Sounds
// object through the desktop's sound server. 55 % volume, 25 % for hover,
// never overlapping themselves; Prefs.soundOn mutes all of them.
import QtQuick
import Kisel.Core

QtObject {
    function play(name) { Sounds.play(name) }
}
