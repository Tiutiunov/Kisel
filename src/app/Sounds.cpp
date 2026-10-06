#include "Sounds.h"

#include "Preferences.h"

#include <QDir>
#include <QFile>
#include <QStandardPaths>

namespace kisel {

namespace {
double volumeFor(const QString &name) { return name == QLatin1String("hover") ? 0.25 : 0.55; }
}

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
    if (!m_prefs->soundOn())
        return;
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
        args << QStringLiteral("--volume=%1").arg(volumeFor(name)) << file;
    else // paplay: 65536 = 100 %. No media.role=event: Plasma can mute that whole
         // role (notification sounds off) and the sound server remembers it.
        args << QStringLiteral("--volume=%1").arg(int(65536 * volumeFor(name)))
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

} // namespace kisel
