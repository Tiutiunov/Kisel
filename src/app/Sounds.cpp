#include "Sounds.h"

#include "Preferences.h"

#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QtEndian>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <mmsystem.h>
#endif

namespace kisel {

namespace {
double volumeFor(const QString &name) { return name == QLatin1String("hover") ? 0.25 : 0.55; }
}

#ifdef Q_OS_WIN
Sounds::Sounds(Preferences *prefs, QObject *parent)
    : QObject(parent)
    , m_prefs(prefs)
{
}

// PlaySound reads m_wavs while it plays: stop it before they go.
Sounds::~Sounds() { PlaySoundW(nullptr, nullptr, 0); }

void Sounds::play(const QString &name)
{
    if (!m_prefs->soundOn() || m_prefs->soundVolume() <= 0)
        return;
    if (m_scaledFor != m_prefs->soundVolume()) { // (the volume was moved: scale them anew)
        PlaySoundW(nullptr, nullptr, 0);
        m_wavs.clear();
        m_scaledFor = m_prefs->soundVolume();
    }
    const double volume = volumeFor(name) * m_scaledFor / 100.0;
    auto it = m_wavs.find(name);
    if (it == m_wavs.end()) {
        QFile src(QStringLiteral(":/qt/qml/Kisel/resources/sounds/%1.wav").arg(name));
        if (!src.open(QIODevice::ReadOnly))
            return;
        QByteArray wav = src.readAll();
        // PlaySound has no volume: scale the 16-bit samples of the "data" chunk.
        const qsizetype at = wav.indexOf("data");
        if (at >= 0 && at + 8 <= wav.size()) {
            const qsizetype len = qMin<qsizetype>(qFromLittleEndian<quint32>(wav.constData() + at + 4), wav.size() - at - 8);
            char *p = wav.data() + at + 8;
            for (qsizetype i = 0; i + 1 < len; i += 2)
                qToLittleEndian<qint16>(qint16(qFromLittleEndian<qint16>(p + i) * volume), p + i);
        }
        it = m_wavs.insert(name, wav);
    }
    PlaySoundW(reinterpret_cast<LPCWSTR>(it->constData()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
}
#else

Sounds::Sounds(Preferences *prefs, QObject *parent)
    : QObject(parent)
    , m_prefs(prefs)
{
    for (const char *candidate : {"paplay", "pw-play"}) {
        const QString exe = QStandardPaths::findExecutable(QString::fromLatin1(candidate));
        if (!exe.isEmpty()) {
            m_player = exe;
            break;
        }
    }
    m_dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/sounds");
}

Sounds::~Sounds() = default;

// The players need a real file: unpack the embedded WAV once into the cache.
QString Sounds::fileFor(const QString &name)
{
    const QString dest = m_dir + QLatin1Char('/') + name + QStringLiteral(".wav");
    QFile src(QStringLiteral(":/qt/qml/Kisel/resources/sounds/%1.wav").arg(name));
    if (!src.exists())
        return {};
    if (QFile::exists(dest) && QFile(dest).size() == src.size())
        return dest;
    QDir().mkpath(m_dir);
    QFile::remove(dest);
    return src.copy(dest) ? dest : QString();
}

void Sounds::play(const QString &name)
{
    if (!m_prefs->soundOn() || m_prefs->soundVolume() <= 0)
        return;
    const double volume = volumeFor(name) * m_prefs->soundVolume() / 100.0;
    if (m_player.isEmpty()) {
        if (!m_warned) {
            qWarning("No paplay or pw-play found: sounds are off.");
            m_warned = true;
        }
        return;
    }
    if (m_running.value(name)) // never overlap itself
        return;
    const QString file = fileFor(name);
    if (file.isEmpty())
        return;

    auto *p = new QProcess(this);
    QStringList args;
    if (m_player.endsWith(QLatin1String("pw-play")))
        args << QStringLiteral("--volume=%1").arg(volume) << file;
    else // paplay: 65536 = 100 %. No media.role=event: Plasma can mute that whole
         // role (notification sounds off) and the sound server remembers it.
        args << QStringLiteral("--volume=%1").arg(int(65536 * volume))
             << QStringLiteral("--client-name=Kisel") << file;
    connect(p, &QProcess::finished, this, [this, p, name] {
        m_running.remove(name);
        p->deleteLater();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, name] {
        m_running.remove(name);
        p->deleteLater();
    });
    m_running.insert(name, p);
    p->start(m_player, args);
}

#endif

} // namespace kisel
