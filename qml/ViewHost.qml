// Hosts one view of the island and owns how it appears and disappears.
//
//  * leaving: the old content fades out in 100 ms, at once;
//  * entering: after `enterDelay` (60 ms when the card grows, so text never clips; about
//    180 ms when it shrinks, once the card is 80 percent of the way) it fades in over
//    140 ms and its blocks rise 8 px, staggered 30 ms (see Motion.rise and `age`);
//  * same height: a plain 140 ms cross-fade, no rise.
import QtQuick

Item {
    id: host
    property bool active: false
    property int enterDelay: 60
    property bool rises: true
    // ms since the content was shown; views stagger their blocks from it
    property real age: 800
    default property alias content: holder.data

    width: 494
    height: holder.childrenRect.height

    property bool shown: false
    onActiveChanged: {
        if (active) {
            enterTimer.interval = Math.max(1, enterDelay)
            enterTimer.restart()
        } else {
            enterTimer.stop()
            shown = false
        }
    }
    Timer {
        id: enterTimer
        onTriggered: {
            host.age = 0
            host.shown = host.active
            if (host.rises && !Theme.reduced) ageAnim.restart(); else host.age = 800
        }
    }
    NumberAnimation { id: ageAnim; target: host; property: "age"; from: 0; to: 800; duration: 800 }

    opacity: shown ? 1 : 0
    visible: opacity > 0.001
    enabled: active && shown
    Behavior on opacity { NumberAnimation { duration: host.shown ? 140 : 100 } }

    Item { id: holder; width: parent.width }
}
