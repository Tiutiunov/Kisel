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
// On Windows the WAV is scaled to its volume in memory and handed to PlaySound,
// which plays one sound at a time: a new one cuts the previous short.
class Sounds : public QObject
{
    Q_OBJECT
public:
    explicit Sounds(Preferences *prefs, QObject *parent = nullptr);
    ~Sounds() override;

    Q_INVOKABLE void play(const QString &name);

private:
    Preferences *m_prefs;
#ifdef Q_OS_WIN
    QHash<QString, QByteArray> m_wavs; // scaled once; PlaySound reads them while it plays
#else
    QString fileFor(const QString &name);
    QString m_player;   // "paplay" or "pw-play"; empty = no way to play
    QString m_dir;
    QHash<QString, QProcess *> m_running;
    bool m_warned = false;
#endif
};

} // namespace kisel
