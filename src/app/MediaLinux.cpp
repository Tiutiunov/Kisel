// What is playing, on Plasma: MPRIS, the interface every player on the session bus
// speaks (it is what Plasma's own media applet and the keyboard's media keys use). The
// player publishes the track; we read it and ask it to play, pause or skip.
//
// Spotify is the one looked for first, as on Windows. Where it is not running, another
// music player is taken; a browser is not (a video in a tab is not the user's music).
//
// The cover comes as an address. A file is read; Spotify gives a web address on its own
// image server, and that picture is fetched from there (docs/PRIVACY.md lists it).
#include "Media.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFile>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

namespace kisel {

namespace {
const QString kPrefix = QStringLiteral("org.mpris.MediaPlayer2.");
const QString kPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString kPlayer = QStringLiteral("org.mpris.MediaPlayer2.Player");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");
constexpr qint64 kMaxCover = 8 * 1024 * 1024;

// 2 Spotify and its kin, 1 another player, 0 not a music player
int rank(const QString &service)
{
    const QString name = service.mid(kPrefix.size()).toLower();
    if (name.contains(QLatin1String("spot")))
        return 2;
    for (const char *browser : {"firefox", "chrom", "brave", "vivaldi", "opera", "edge", "librewolf", "zen", "floorp", "plasma-browser-integration",
                                "kdeconnect", "epiphany", "falkon", "qutebrowser"})
        if (name.contains(QLatin1String(browser)))
            return 0;
    return 1;
}
} // namespace

struct Media::Worker : QObject
{
    Media *owner = nullptr;
    QTimer tick;
    int age = 0;
    QString service;   // the player being read, or empty
    QString trackId;
    QString coverAt;   // the address of the cover now shown (or being fetched)
    qint64 lengthUs = 0, positionUs = 0;
    QNetworkAccessManager *net = nullptr;
    // the last state, to say again when the cover arrives after it
    bool active = false, playing = false, canSeek = false;
    QString title, artist;
    bool asking = false;

    void say(bool coverChanged, const QByteArray &cover = {})
    {
        const qreal duration = lengthUs > 0 ? lengthUs / 1e6 : 0;
        const qreal progress = lengthUs > 0 ? qBound(0.0, double(positionUs) / double(lengthUs), 1.0) : 0;
        owner->apply(active, playing, title, artist, progress, duration, coverChanged, cover, canSeek);
    }

    void gone()
    {
        service.clear();
        trackId.clear();
        lengthUs = positionUs = 0;
        const bool had = active || !coverAt.isEmpty();
        active = playing = canSeek = false;
        title.clear();
        artist.clear();
        coverAt.clear();
        if (had)
            say(true);
    }

    // which player: asked of the bus every few seconds
    void look()
    {
        QDBusConnectionInterface *bus = QDBusConnection::sessionBus().interface();
        if (!bus)
            return;
        auto *w = new QDBusPendingCallWatcher(bus->asyncCall(QStringLiteral("ListNames")), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *done) {
            done->deleteLater();
            const QDBusPendingReply<QStringList> reply = *done;
            if (reply.isError())
                return;
            QString best;
            int bestRank = 0;
            for (const QString &name : reply.value()) {
                if (!name.startsWith(kPrefix))
                    continue;
                const int r = rank(name);
                // (the one already being read is kept among its equals)
                if (r > bestRank || (r == bestRank && r > 0 && name == service)) {
                    best = name;
                    bestRank = r;
                }
            }
            if (best == service)
                return;
            if (best.isEmpty()) {
                gone();
                return;
            }
            service = best;
            read();
        });
    }

    void read()
    {
        if (service.isEmpty() || asking)
            return;
        asking = true;
        QDBusMessage ask = QDBusMessage::createMethodCall(service, kPath, kProps, QStringLiteral("GetAll"));
        ask << kPlayer;
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(ask, 1500), this);
        const QString asked = service;
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, asked](QDBusPendingCallWatcher *done) {
            done->deleteLater();
            asking = false;
            if (asked != service)
                return;
            const QDBusPendingReply<QVariantMap> reply = *done;
            if (reply.isError()) {
                gone();
                return;
            }
            const QVariantMap p = reply.value();
            const QString status = p.value(QStringLiteral("PlaybackStatus")).toString();
            const QVariantMap md = qdbus_cast<QVariantMap>(p.value(QStringLiteral("Metadata")));
            title = md.value(QStringLiteral("xesam:title")).toString().simplified();
            artist = md.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", ")).simplified();
            lengthUs = md.value(QStringLiteral("mpris:length")).toLongLong();
            positionUs = p.value(QStringLiteral("Position")).toLongLong();
            const QVariant id = md.value(QStringLiteral("mpris:trackid"));
            trackId = id.canConvert<QDBusObjectPath>() ? id.value<QDBusObjectPath>().path() : id.toString();
            canSeek = p.value(QStringLiteral("CanSeek")).toBool() && lengthUs > 0;
            playing = status == QLatin1String("Playing");
            active = !title.isEmpty() && status != QLatin1String("Stopped");
            const QString cover = active ? md.value(QStringLiteral("mpris:artUrl")).toString() : QString();
            if (cover == coverAt) {
                say(false);
                return;
            }
            coverAt = cover;
            say(true); // (the old cover goes at once; the new one follows)
            const QUrl url(cover);
            if (url.isLocalFile()) {
                QFile f(url.toLocalFile());
                if (f.size() <= kMaxCover && f.open(QIODevice::ReadOnly))
                    say(true, f.readAll());
            } else if (url.scheme() == QLatin1String("https")) {
                if (!net)
                    net = new QNetworkAccessManager(this);
                QNetworkRequest req(url);
                req.setRawHeader("User-Agent", "Kisel");
                req.setTransferTimeout(8000);
                QNetworkReply *r = net->get(req);
                connect(r, &QNetworkReply::finished, this, [this, r, cover] {
                    r->deleteLater();
                    if (cover == coverAt && r->error() == QNetworkReply::NoError && r->size() <= kMaxCover)
                        say(true, r->readAll());
                });
            }
        });
    }

    void call(const QString &method, const QVariantList &args = {})
    {
        if (service.isEmpty())
            return;
        QDBusMessage m = QDBusMessage::createMethodCall(service, kPath, kPlayer, method);
        m.setArguments(args);
        QDBusConnection::sessionBus().asyncCall(m, 1500);
        QTimer::singleShot(250, this, [this] { read(); }); // what it did, soon
    }
};

Media::Media(QObject *parent)
    : QObject(parent)
    , m_worker(std::make_unique<Worker>())
{
    Worker *w = m_worker.get();
    w->owner = this;
    if (!available())
        return;
    w->tick.setInterval(1000);
    QObject::connect(&w->tick, &QTimer::timeout, w, [w] {
        if (w->age++ % 4 == 0)
            w->look();
        w->read();
    });
    w->tick.start();
}

Media::~Media() = default;

bool Media::available() const { return QDBusConnection::sessionBus().isConnected(); }
void Media::playPause() { m_worker->call(QStringLiteral("PlayPause")); }
void Media::next() { m_worker->call(QStringLiteral("Next")); }
void Media::previous() { m_worker->call(QStringLiteral("Previous")); }

void Media::seek(qreal fraction)
{
    Worker *w = m_worker.get();
    if (w->lengthUs <= 0)
        return;
    const qint64 to = qint64(qBound(0.0, double(fraction), 1.0) * double(w->lengthUs));
    if (w->trackId.startsWith(QLatin1Char('/')))
        w->call(QStringLiteral("SetPosition"), {QVariant::fromValue(QDBusObjectPath(w->trackId)), QVariant::fromValue(to)});
    else
        w->call(QStringLiteral("Seek"), {QVariant::fromValue(to - w->positionUs)});
}

} // namespace kisel
