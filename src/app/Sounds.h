#pragma once

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QString>

namespace kisel {

class Preferences;

// Plays the interface bloops through the desktop's own sound server
// (`paplay` speaks the PulseAudio protocol that PipeWire provides on Plasma;
// `pw-play` is the fallback). Qt Multimedia was dropped: its FFmpeg backend
// enumerates every audio device (including Bluetooth inputs) and logged an
// error per sound. One process per sound at a time, so a sound never overlaps
// itself; volumes follow motion.md (55 %, hover 25 %).
class Sounds : public QObject
{
    Q_OBJECT
public:
    explicit Sounds(Preferences *prefs, QObject *parent = nullptr);

    Q_INVOKABLE void play(const QString &name);

private:
    QString fileFor(const QString &name);
    Preferences *m_prefs;
    QString m_player;   // "paplay" or "pw-play"; empty = no way to play
    QString m_dir;
    QHash<QString, QProcess *> m_running;
    bool m_warned = false;
};

} // namespace kisel
