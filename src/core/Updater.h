#pragma once

#include "Secrets.h"

#include <QCryptographicHash>
#include <QFile>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QUrl>

#include <functional>
#include <memory>

namespace kisel {

// Updates for the Windows build, from the releases of the repository on GitHub.
//
// Nothing here runs by itself: Kisel asks GitHub only when "Check for updates" is
// pressed in Settings, and downloads and starts the installer only when "Update" is.
// The Windows releases are the ones tagged `win-v<version>`; each carries one
// `KiselSetup-<version>.exe`. The download is checked against the size and the SHA-256
// GitHub gives for it before it is started. The repository (Tiutiunov/Kisel) is public,
// so no token is needed; if one is saved (the GitHub widget's) it is sent to the API along
// with the question, never to where the file itself is kept.
//
// The installer is started with `/SILENT /DIR=<where this copy is>`, and Kisel quits;
// the installer puts the new files in place and starts Kisel again.
class Updater : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)   // this build can update itself (Windows)
    Q_PROPERTY(QString current READ current CONSTANT)    // the version running
    Q_PROPERTY(QString latest READ latest NOTIFY changed) // the newest release seen
    // idle | checking | current (nothing newer) | found | downloading | starting | failed
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(qreal progress READ progress NOTIFY changed) // 0..1 of the download
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit Updater(Secrets *secrets, QObject *parent = nullptr);
    // For the tests: another place to ask than GitHub, and something else to do with the
    // installer than start it.
    void setApi(const QUrl &releases) { m_api = releases; }
    void setLauncher(std::function<bool(const QString &, const QStringList &)> fn) { m_launch = std::move(fn); }

    bool available() const;
    QString current() const;
    QString latest() const { return m_release.version; }
    QString state() const { return m_state; }
    qreal progress() const { return m_progress; }
    QString error() const { return m_error; }

    Q_INVOKABLE void check();
    Q_INVOKABLE void update(); // download the release found, check it, start it, quit

    struct Release {
        QString version;   // "0.2.0"
        QUrl asset;        // the installer, as the API names it
        QString name;      // its file name
        qint64 size = 0;
        QByteArray sha256; // hex, empty if GitHub gave none
    };
    // Pure and unit-tested: the body of `GET /repos/.../releases` -> the newest Windows
    // release that has an installer (false if there is none).
    static bool pick(const QByteArray &body, Release *out, QString *error);
    // <0, 0, >0 as `a` is older than, the same as, newer than `b` ("0.10.0" > "0.9.3")
    static int compare(const QString &a, const QString &b);

signals:
    void changed();

private:
    void set(const QString &state, const QString &error = {});
    void request(const QUrl &url, bool asset);
    void fetch(const QUrl &url);
    void finishDownload();

    Secrets *m_secrets;
    QUrl m_api;
    std::function<bool(const QString &, const QStringList &)> m_launch;
    QNetworkAccessManager m_net;
    QPointer<QNetworkReply> m_reply;
    Release m_release;
    QString m_state = QStringLiteral("idle");
    QString m_error;
    qreal m_progress = 0;
    std::unique_ptr<QFile> m_file;
    std::unique_ptr<QCryptographicHash> m_hash;
};

} // namespace kisel
