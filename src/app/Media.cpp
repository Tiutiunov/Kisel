// The WinRT headers come before any Qt header: Qt's `emit`, `signals` and `slots` are
// macros, and C++/WinRT must be parsed without them.
#ifdef _WIN32
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>
#endif

#include "Media.h"

#include <QBuffer>
#include <QImage>

#ifdef _WIN32
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#endif

namespace kisel {

#ifdef _WIN32
namespace mc = winrt::Windows::Media::Control;

struct Media::Worker
{
    enum Command { None, Toggle, Next, Previous };

    Media *owner = nullptr;
    std::thread thread;
    std::mutex mutex;
    std::condition_variable wake;
    std::atomic<bool> stop {false};
    Command pending = None;

    void post(Command c)
    {
        { std::lock_guard<std::mutex> lock(mutex); pending = c; }
        wake.notify_one();
    }

    // Spotify's session among the system's, or nothing.
    static mc::GlobalSystemMediaTransportControlsSession spotify(const mc::GlobalSystemMediaTransportControlsSessionManager &manager)
    {
        for (const auto &session : manager.GetSessions()) {
            std::wstring id {session.SourceAppUserModelId()};
            std::transform(id.begin(), id.end(), id.begin(), ::towlower);
            if (id.find(L"spotify") != std::wstring::npos)
                return session;
        }
        return nullptr;
    }

    void run()
    {
        winrt::init_apartment(); // a thread of our own, so the blocking .get() calls below are allowed
        mc::GlobalSystemMediaTransportControlsSessionManager manager {nullptr};
        try {
            manager = mc::GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
        } catch (...) {
            return; // an older Windows without the session manager: stay inactive
        }

        std::wstring track; // title and artist of the track the cover was read for
        int coverTries = 0; // Spotify publishes the cover a moment after the title
        while (!stop) {
            Command command = None;
            {
                std::unique_lock<std::mutex> lock(mutex);
                wake.wait_for(lock, std::chrono::milliseconds(500), [this] { return stop || pending != None; });
                command = pending;
                pending = None;
            }
            if (stop)
                break;

            bool active = false, playing = false, coverChanged = false;
            QString title, artist;
            QByteArray cover;
            qreal progress = 0;
            try {
                if (const auto session = spotify(manager)) {
                    if (command == Toggle) session.TryTogglePlayPauseAsync().get();
                    if (command == Next) session.TrySkipNextAsync().get();
                    if (command == Previous) session.TrySkipPreviousAsync().get();

                    using Status = mc::GlobalSystemMediaTransportControlsSessionPlaybackStatus;
                    playing = session.GetPlaybackInfo().PlaybackStatus() == Status::Playing;
                    const auto props = session.TryGetMediaPropertiesAsync().get();
                    const winrt::hstring t = props.Title(), a = props.Artist();
                    title = QString::fromWCharArray(t.c_str(), int(t.size()));
                    artist = QString::fromWCharArray(a.c_str(), int(a.size()));
                    active = !title.isEmpty();

                    // The position is only refreshed now and then; while playing it runs on from there.
                    const auto line = session.GetTimelineProperties();
                    auto at = line.Position();
                    if (playing)
                        at += winrt::clock::now() - line.LastUpdatedTime();
                    const auto length = line.EndTime() - line.StartTime();
                    if (length.count() > 0)
                        progress = qBound(0.0, double(at.count()) / double(length.count()), 1.0);

                    const std::wstring now = std::wstring(t) + L"\n" + std::wstring(a);
                    if (now != track) { track = now; coverTries = 4; coverChanged = true; }
                    if (coverTries > 0) {
                        --coverTries;
                        if (const auto ref = props.Thumbnail()) {
                            const auto stream = ref.OpenReadAsync().get();
                            const auto size = uint32_t(stream.Size());
                            if (size > 0 && size < 8u * 1024 * 1024) {
                                winrt::Windows::Storage::Streams::DataReader reader(stream);
                                reader.LoadAsync(size).get();
                                std::vector<uint8_t> bytes(size);
                                reader.ReadBytes(bytes);
                                cover = QByteArray(reinterpret_cast<const char *>(bytes.data()), int(bytes.size()));
                                coverChanged = true;
                            }
                        }
                    }
                } else if (!track.empty()) {
                    track.clear();
                    coverChanged = true;
                }
            } catch (...) {
                // Spotify went away between two calls: this round reports nothing
            }

            QMetaObject::invokeMethod(owner, [=, o = owner] { o->apply(active, playing, title, artist, progress, coverChanged, cover); },
                                      Qt::QueuedConnection);
        }
    }
};

Media::Media(QObject *parent)
    : QObject(parent)
    , m_worker(std::make_unique<Worker>())
{
    m_worker->owner = this;
    m_worker->thread = std::thread([w = m_worker.get()] { w->run(); });
}

Media::~Media()
{
    m_worker->stop = true;
    m_worker->wake.notify_one();
    if (m_worker->thread.joinable())
        m_worker->thread.join();
}

bool Media::available() const { return true; }
void Media::playPause() { m_worker->post(Worker::Toggle); }
void Media::next() { m_worker->post(Worker::Next); }
void Media::previous() { m_worker->post(Worker::Previous); }
#else
struct Media::Worker {};
Media::Media(QObject *parent) : QObject(parent) {}
Media::~Media() = default;
bool Media::available() const { return false; }
void Media::playPause() {}
void Media::next() {}
void Media::previous() {}
#endif

void Media::apply(bool active, bool playing, const QString &title, const QString &artist, qreal progress,
                  bool artChanged, const QByteArray &artBytes)
{
    bool dirty = active != m_active || playing != m_playing || title != m_title || artist != m_artist
              || qAbs(progress - m_progress) > 0.002;
    m_active = active;
    m_playing = playing;
    m_title = title;
    m_artist = artist;
    m_progress = progress;
    if (artChanged) {
        QString art;
        const QImage image = QImage::fromData(artBytes);
        if (!image.isNull()) {
            // small and square is all the player shows; QML takes it as a data: URL
            QByteArray png;
            QBuffer buffer(&png);
            buffer.open(QIODevice::WriteOnly);
            image.scaled(128, 128, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation).save(&buffer, "PNG");
            art = QStringLiteral("data:image/png;base64,") + QString::fromLatin1(png.toBase64());
        }
        // (a new track arrives with no bytes first: that clears the old cover at once)
        if (art != m_art) { m_art = art; dirty = true; }
    }
    if (dirty)
        emit changed();
}

} // namespace kisel
