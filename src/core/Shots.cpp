#include "Shots.h"

#include <QBuffer>
#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QMimeData>
#include <QSaveFile>

namespace kisel {

namespace {
constexpr int kSide = 1920;                    // longest side: Claude scales larger ones down itself
constexpr qint64 kPngMax = 3 * 1024 * 1024;    // a heavier PNG is a photo: JPEG says it smaller
constexpr qint64 kFileMax = 40 * 1024 * 1024;  // a dropped file larger than this is not read
constexpr int kKeepDays = 7;
}

Shots::Shots(QObject *parent) : QObject(parent)
{
    prune();
}

QString Shots::folder()
{
    return QDir::homePath() + QStringLiteral("/.kisel/shots");
}

bool Shots::clipboardHasImage() const
{
    const QMimeData *m = QGuiApplication::clipboard()->mimeData();
    return m && m->hasImage();
}

QString Shots::fromClipboard()
{
    if (!clipboardHasImage())
        return QString();
    return save(QGuiApplication::clipboard()->image());
}

bool Shots::isImage(const QUrl &url)
{
    if (!url.isLocalFile())
        return false;
    const QString path = url.toLocalFile();
    if (QFileInfo(path).size() > kFileMax)
        return false;
    QImageReader r(path);
    return r.canRead();
}

QString Shots::fromUrl(const QUrl &url)
{
    if (!isImage(url))
        return QString();
    QImageReader r(url.toLocalFile());
    r.setAutoTransform(true); // (a photo from a phone stands as it was taken)
    return save(r.read());
}

QString Shots::localPath(const QString &url)
{
    return QDir::toNativeSeparators(QUrl(url).toLocalFile());
}

QByteArray Shots::encode(const QImage &image, QString *mediaType)
{
    if (image.isNull())
        return QByteArray();
    QImage im = image;
    if (qMax(im.width(), im.height()) > kSide)
        im = im.scaled(kSide, kSide, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    QByteArray bytes;
    QBuffer buf(&bytes);
    buf.open(QIODevice::WriteOnly);
    im.save(&buf, "PNG");
    if (bytes.size() <= kPngMax) {
        *mediaType = QStringLiteral("image/png");
        return bytes;
    }
    bytes.clear();
    buf.seek(0);
    im.convertToFormat(QImage::Format_RGB32).save(&buf, "JPEG", 85);
    *mediaType = QStringLiteral("image/jpeg");
    return bytes;
}

QString Shots::save(const QImage &image)
{
    QString type;
    const QByteArray bytes = encode(image, &type);
    if (bytes.isEmpty())
        return QString();
    QDir().mkpath(folder());
    const QString name = QStringLiteral("%1.%2").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss-zzz")),
                                                     type == QLatin1String("image/png") ? QStringLiteral("png") : QStringLiteral("jpg"));
    QSaveFile f(folder() + QLatin1Char('/') + name);
    if (!f.open(QIODevice::WriteOnly) || f.write(bytes) != bytes.size() || !f.commit())
        return QString();
    return QUrl::fromLocalFile(folder() + QLatin1Char('/') + name).toString();
}

// (a week is long enough for a session to have looked at one; the folder does not grow for ever)
void Shots::prune()
{
    const QDateTime before = QDateTime::currentDateTime().addDays(-kKeepDays);
    QDir dir(folder());
    for (const QFileInfo &f : dir.entryInfoList({QStringLiteral("*.png"), QStringLiteral("*.jpg")}, QDir::Files))
        if (f.lastModified() < before)
            QFile::remove(f.filePath());
}

} // namespace kisel
