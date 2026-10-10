#include "Updater.h"

#include "Paths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

#include <cstdio>

namespace kisel {

namespace {
const QUrl kReleases(QStringLiteral("https://api.github.com/repos/Tiutiunov/Kisel/releases?per_page=30"));
const QLatin1String kTagPrefix("win-v");
constexpr qint64 kMaxInstaller = 400ll * 1024 * 1024; // nothing of ours is near this
} // namespace

Updater::Updater(Secrets *secrets, QObject *parent)
    : QObject(parent)
    , m_secrets(secrets)
    , m_api(kReleases)
{
}

// Windows: always (the installer puts the new files in). Plasma: where Kisel runs from an
// AppImage that it may write over: the new file takes the old one's place. A Kisel that
// a package installed is updated by its package.
bool Updater::available() const
{
#ifdef Q_OS_WIN
    return true;
#else
    const QString image = paths::appImage();
    return !image.isEmpty() && QFileInfo(QFileInfo(image).absolutePath()).isWritable() && QFileInfo(image).isWritable();
#endif
}

QString Updater::current() const
{
    // KISEL_VERSION_AS=<version>: pretend to be that version (development: to see an update offered)
    const QString as = qEnvironmentVariable("KISEL_VERSION_AS");
    return as.isEmpty() ? QStringLiteral(KISEL_VERSION) : as;
}

int Updater::compare(const QString &a, const QString &b)
{
    const QStringList x = a.split(QLatin1Char('.')), y = b.split(QLatin1Char('.'));
    for (int i = 0; i < qMax(x.size(), y.size()); ++i) {
        const int p = i < x.size() ? x.at(i).toInt() : 0, q = i < y.size() ? y.at(i).toInt() : 0;
        if (p != q)
            return p < q ? -1 : 1;
    }
    return 0;
}

bool Updater::pick(const QByteArray &body, Release *out, QString *error, bool appImage)
{
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isArray()) {
        *error = doc.isObject() ? doc.object().value("message").toString(QStringLiteral("GitHub refused the request"))
                                : QStringLiteral("GitHub sent something unexpected");
        return false;
    }
    bool found = false;
    for (const QJsonValue &v : doc.array()) {
        const QJsonObject r = v.toObject();
        const QString tag = r.value("tag_name").toString();
        if (!tag.startsWith(kTagPrefix) || r.value("draft").toBool())
            continue;
        const QString version = tag.mid(kTagPrefix.size());
        if (found && compare(version, out->version) <= 0)
            continue;
        for (const QJsonValue &av : r.value("assets").toArray()) {
            const QJsonObject a = av.toObject();
            const QString name = a.value("name").toString();
            if (appImage ? !name.startsWith(QLatin1String("Kisel-")) || !name.endsWith(QLatin1String("-x86_64.AppImage"))
                         : !name.startsWith(QLatin1String("KiselSetup")) || !name.endsWith(QLatin1String(".exe")))
                continue;
            out->version = version;
            out->name = name;
            out->asset = QUrl(a.value("url").toString());
            out->size = qint64(a.value("size").toDouble());
            const QString digest = a.value("digest").toString(); // "sha256:<hex>"
            out->sha256 = digest.startsWith(QLatin1String("sha256:")) ? digest.mid(7).toLatin1().toLower() : QByteArray();
            found = true;
            break;
        }
    }
    if (!found)
        *error = appImage ? QStringLiteral("There is no release for Plasma yet") : QStringLiteral("There is no Windows release yet");
    return found;
}

void Updater::set(const QString &state, const QString &error)
{
    m_state = state;
    m_error = error;
    emit changed();
}

// One request to GitHub's API. With a token saved it goes along (a private repository
// cannot be read without one). For the installer the API answers with a redirect to
// where the file is; that address is fetched without the token (see `fetch`).
void Updater::request(const QUrl &url, bool asset)
{
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "Kisel");
    req.setRawHeader("X-GitHub-Api-Version", "2022-11-28");
    req.setRawHeader("Accept", asset ? "application/octet-stream" : "application/vnd.github+json");
    const QString token = m_secrets ? m_secrets->read(QStringLiteral("github")) : QString();
    if (!token.isEmpty())
        req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    m_reply = m_net.get(req);
}

// a check that failed: said in Settings if it was asked for there, passed over if not
void Updater::fail(const QString &error)
{
    if (m_quiet)
        set(m_state == QLatin1String("checking") ? QStringLiteral("idle") : m_state);
    else
        set(QStringLiteral("failed"), error);
}

void Updater::pretend(const QString &version)
{
    m_release = Release();
    m_release.version = version;
    set(QStringLiteral("found"));
}

void Updater::check(bool quiet)
{
    if (m_reply || m_state == QLatin1String("downloading") || m_state == QLatin1String("starting"))
        return;
    m_quiet = quiet;
    if (quiet && m_state == QLatin1String("found")) // (already known: nothing to ask again today)
        return;
    set(quiet ? m_state : QStringLiteral("checking"));
    request(m_api, false);
    connect(m_reply, &QNetworkReply::finished, this, [this] {
        QNetworkReply *r = m_reply;
        m_reply = nullptr;
        if (!r)
            return;
        r->deleteLater();
        const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = r->readAll();
        if (status == 401) {
            fail( QStringLiteral("GitHub rejected the token"));
            return;
        }
        if (status == 404 || status == 403) {
            fail( QStringLiteral("GitHub does not show the releases just now. Try again in a while."));
            return;
        }
        if (status != 200) {
            fail( status == 0 ? r->errorString() : QStringLiteral("GitHub answered %1").arg(status));
            return;
        }
        Release rel;
        QString err;
        if (!pick(body, &rel, &err, !paths::appImage().isEmpty())) {
            fail( err);
            return;
        }
        m_release = rel;
        set(compare(rel.version, current()) > 0 ? QStringLiteral("found") : QStringLiteral("current"));
    });
}

void Updater::update()
{
    if (m_reply || m_state != QLatin1String("found") || !m_release.asset.isValid())
        return;
    if (m_release.asset.scheme() != m_api.scheme() || m_release.asset.host() != m_api.host()
        || m_release.size <= 0 || m_release.size > kMaxInstaller) {
        set(QStringLiteral("failed"), QStringLiteral("The release does not look right"));
        return;
    }
    m_progress = 0;
    set(QStringLiteral("downloading"));
    request(m_release.asset, true);
    connect(m_reply, &QNetworkReply::finished, this, [this] {
        QNetworkReply *r = m_reply;
        m_reply = nullptr;
        if (!r)
            return;
        r->deleteLater();
        const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QUrl to = r->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
        if ((status == 302 || status == 301 || status == 307) && to.isValid() && to.scheme() == m_api.scheme()) {
            fetch(to);
            return;
        }
        set(QStringLiteral("failed"), status == 0 ? r->errorString() : QStringLiteral("GitHub answered %1 for the installer").arg(status));
    });
}

// The file itself, from where GitHub keeps it: no token goes there.
void Updater::fetch(const QUrl &url)
{
    // (an AppImage: beside the one that is running, so that it can take its place in one move)
    const QString image = paths::appImage();
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    m_file = std::make_unique<QFile>(image.isEmpty() ? dir + QStringLiteral("/KiselSetup-%1.exe").arg(m_release.version)
                                                     : QFileInfo(image).absolutePath() + QStringLiteral("/.kisel-%1.part").arg(m_release.version));
    if (!m_file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        m_file.reset();
        set(QStringLiteral("failed"), QStringLiteral("Could not write to the temporary folder"));
        return;
    }
    m_hash = std::make_unique<QCryptographicHash>(QCryptographicHash::Sha256);
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "Kisel");
    m_reply = m_net.get(req);
    connect(m_reply, &QNetworkReply::readyRead, this, [this] {
        if (!m_reply || !m_file)
            return;
        const QByteArray chunk = m_reply->readAll();
        m_hash->addData(chunk);
        m_file->write(chunk);
        if (m_file->size() > m_release.size) { // more than was promised: not our file
            m_reply->abort();
            return;
        }
        m_progress = qreal(m_file->size()) / qreal(m_release.size);
        emit changed();
    });
    connect(m_reply, &QNetworkReply::finished, this, [this] {
        QNetworkReply *r = m_reply;
        m_reply = nullptr;
        if (!r)
            return;
        r->deleteLater();
        if (m_file) {
            const QByteArray rest = r->readAll();
            m_hash->addData(rest);
            m_file->write(rest);
        }
        if (r->error() != QNetworkReply::NoError) {
            if (m_file)
                m_file->remove();
            m_file.reset();
            set(QStringLiteral("failed"), r->errorString());
            return;
        }
        finishDownload();
    });
}

void Updater::finishDownload()
{
    const QString path = m_file->fileName();
    const qint64 size = m_file->size();
    m_file->close();
    const QByteArray sum = m_hash->result().toHex().toLower();
    if (size != m_release.size || (!m_release.sha256.isEmpty() && sum != m_release.sha256)) {
        m_file->remove();
        m_file.reset();
        set(QStringLiteral("failed"), QStringLiteral("The download does not match the release. Nothing was installed."));
        return;
    }
    m_file.reset();

    // An AppImage is the whole of Kisel in one file: the new one is put where the old one
    // is (the one running goes on from what it has open), and started.
    if (const QString image = paths::appImage(); !image.isEmpty() && !m_launch) {
        QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner | QFileDevice::ReadGroup
                                        | QFileDevice::ExeGroup | QFileDevice::ReadOther | QFileDevice::ExeOther);
        if (::rename(QFile::encodeName(path).constData(), QFile::encodeName(image).constData()) != 0) {
            QFile::remove(path);
            set(QStringLiteral("failed"), QStringLiteral("Could not put the new version in place"));
            return;
        }
        if (!QProcess::startDetached(image, {QStringLiteral("--restarted"), QStringLiteral("0"), QStringLiteral("--no-hello")})) {
            set(QStringLiteral("failed"), QStringLiteral("The new version is in place, but could not be started. Start Kisel again."));
            return;
        }
        m_progress = 1;
        set(QStringLiteral("starting"));
        QTimer::singleShot(400, qApp, &QCoreApplication::quit);
        return;
    }

    // The installer puts the new files where this copy is (<prefix>/bin/kisel.exe), and
    // starts Kisel again when it is done.
    QStringList args {QStringLiteral("/SILENT")};
    const QDir bin(QCoreApplication::applicationDirPath());
    if (bin.dirName().compare(QLatin1String("bin"), Qt::CaseInsensitive) == 0)
        args << QStringLiteral("/DIR=") + QDir::toNativeSeparators(QDir::cleanPath(bin.absoluteFilePath(QStringLiteral(".."))));
    const bool started = m_launch ? m_launch(path, args) : QProcess::startDetached(QDir::toNativeSeparators(path), args);
    if (!started) {
        set(QStringLiteral("failed"), QStringLiteral("Could not start the installer"));
        return;
    }
    m_progress = 1;
    set(QStringLiteral("starting"));
    if (!m_launch)
        QTimer::singleShot(400, qApp, &QCoreApplication::quit);
}

} // namespace kisel
