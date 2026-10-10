#pragma once

#include <QObject>
#include <QString>

#include <memory>

namespace kisel {

// What Spotify is playing, and its three buttons. On Windows this is the system's own
// media session (the one behind the volume flyout and the keyboard's media keys), so
// there is no sign-in, no key and no network call: Spotify publishes the track, we
// read it and ask it to play, pause or skip. On Plasma it is MPRIS on the session bus
// (MediaLinux.cpp): the same, save that the cover comes as an address and is fetched.
// Elsewhere `available` is false and nothing happens.
//
// On Windows the session is read on a thread of its own; QML sees plain properties.
class Media : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)     // the platform can do this at all
    Q_PROPERTY(bool active READ active NOTIFY changed)       // Spotify is running and has a track
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString art READ art NOTIFY changed)          // the cover as a data: URL, or ""
    Q_PROPERTY(qreal progress READ progress NOTIFY changed)  // 0..1 through the track
    Q_PROPERTY(qreal position READ position NOTIFY changed)  // seconds into the track
    Q_PROPERTY(qreal duration READ duration NOTIFY changed)  // its length in seconds, 0 if unknown
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY changed)     // the player lets the position be set

public:
    explicit Media(QObject *parent = nullptr);
    ~Media() override;

    bool available() const;
    bool active() const { return m_active; }
    bool playing() const { return m_playing; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString art() const { return m_art; }
    qreal progress() const { return m_progress; }
    qreal position() const { return m_progress * m_duration; }
    qreal duration() const { return m_duration; }
    bool canSeek() const { return m_canSeek; }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(qreal fraction); // 0..1 through the track

signals:
    void changed();

private:
    struct Worker;
    void apply(bool active, bool playing, const QString &title, const QString &artist, qreal progress, qreal duration,
               bool artChanged, const QByteArray &artBytes, bool canSeek = false);
    std::unique_ptr<Worker> m_worker;
    bool m_active = false;
    bool m_playing = false;
    QString m_title, m_artist, m_art;
    qreal m_progress = 0;
    qreal m_duration = 0;
    bool m_canSeek = false;
};

} // namespace kisel
