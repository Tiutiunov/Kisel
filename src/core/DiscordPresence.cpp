#include "DiscordPresence.h"

#include "AgentHub.h"
#include "Preferences.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QtEndian>

namespace kisel {

namespace {
QString pipeName(int n)
{
#ifdef Q_OS_WIN
    return QStringLiteral("\\\\.\\pipe\\discord-ipc-%1").arg(n);
#else
    QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (dir.isEmpty())
        dir = QStringLiteral("/tmp");
    return dir + QStringLiteral("/discord-ipc-%1").arg(n);
#endif
}
}

bool DiscordPresence::validId(const QString &id)
{
    static const QRegularExpression ok(QStringLiteral("^[0-9]{15,22}$"));
    return ok.match(id).hasMatch();
}

QJsonObject DiscordPresence::activity(const QString &state, const QString &project, qint64 sinceSecs, bool ru)
{
    if (state.isEmpty())
        return {};
    const bool busy = state == QLatin1String("work") || state == QLatin1String("think");
    QJsonObject a;
    a.insert("details", busy ? (ru ? QStringLiteral("Работает с Claude Code") : QStringLiteral("Working with Claude Code"))
                      : state == QLatin1String("alert") ? (ru ? QStringLiteral("Claude ждёт ответа") : QStringLiteral("Claude is waiting for an answer"))
                      : (ru ? QStringLiteral("С Claude Code, перерыв") : QStringLiteral("With Claude Code, taking a break")));
    if (project.size() >= 2) // (Discord takes 2 to 128 characters)
        a.insert("state", project.left(64));
    if (sinceSecs > 0)
        a.insert("timestamps", QJsonObject {{"start", sinceSecs}});
    // (pictures uploaded to the Discord application under these names; without them there are none)
    a.insert("assets", QJsonObject {{"large_image", "kisel"}, {"large_text", "Kisel"}});
    return a;
}

QByteArray DiscordPresence::frame(int op, const QJsonObject &body)
{
    const QByteArray json = QJsonDocument(body).toJson(QJsonDocument::Compact);
    QByteArray out(8, '\0');
    qToLittleEndian<qint32>(op, out.data());
    qToLittleEndian<qint32>(qint32(json.size()), out.data() + 4);
    return out + json;
}

bool DiscordPresence::unframe(QByteArray &buf, int &op, QJsonObject &body)
{
    if (buf.size() < 8)
        return false;
    const qint32 len = qFromLittleEndian<qint32>(buf.constData() + 4);
    if (len < 0 || len > 1 << 20) { // (not a frame at all: throw it away)
        buf.clear();
        return false;
    }
    if (buf.size() < 8 + len)
        return false;
    op = qFromLittleEndian<qint32>(buf.constData());
    body = QJsonDocument::fromJson(buf.mid(8, len)).object();
    buf.remove(0, 8 + len);
    return true;
}

DiscordPresence::DiscordPresence(Preferences *prefs, AgentHub *hub, bool live, QObject *parent)
    : QObject(parent), m_prefs(prefs), m_hub(hub), m_live(live)
{
    m_retry.setInterval(20000); // Discord not running: look again now and then
    connect(&m_retry, &QTimer::timeout, this, [this] { m_pipe = 0; dial(); });
    // (Discord takes a few updates a minute: a burst of hook events becomes one)
    m_settle.setSingleShot(true);
    m_settle.setInterval(4000);
    connect(&m_settle, &QTimer::timeout, this, &DiscordPresence::push);

    connect(&m_sock, &QLocalSocket::connected, this, [this] {
        m_in.clear();
        m_sock.write(frame(0, QJsonObject {{"v", 1}, {"client_id", m_id}}));
    });
    connect(&m_sock, &QLocalSocket::readyRead, this, &DiscordPresence::read);
    connect(&m_sock, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
        if (m_ready || m_state == QLatin1String("off") || m_state == QLatin1String("noid"))
            return;
        if (++m_pipe < 10)
            QTimer::singleShot(0, this, &DiscordPresence::dial);
        else if (m_state != QLatin1String("refused"))
            set(QStringLiteral("waiting"));
    });
    connect(&m_sock, &QLocalSocket::disconnected, this, [this] {
        const bool was = m_ready;
        m_ready = false;
        m_sent = {};
        m_sentAny = false;
        if (was && m_state == QLatin1String("on")) {
            // Discord was closed or restarted: look for it again, as at the start (the
            // looking was stopped when it answered)
            set(QStringLiteral("waiting"));
            m_pipe = 0;
            m_retry.start();
        }
    });

    connect(prefs, &Preferences::changed, this, &DiscordPresence::apply);
    connect(hub, &AgentHub::sessionChanged, this, [this] { if (m_ready && !m_settle.isActive()) m_settle.start(); });
    connect(hub, &AgentHub::moodChanged, this, [this] { if (m_ready && !m_settle.isActive()) m_settle.start(); });
    QTimer::singleShot(0, this, &DiscordPresence::apply);
}

DiscordPresence::~DiscordPresence()
{
    drop();
}

void DiscordPresence::set(const QString &state)
{
    if (state == m_state)
        return;
    m_state = state;
    emit changed();
}

void DiscordPresence::drop()
{
    if (m_ready && m_sentAny) { // take the line off the profile before going
        m_sock.write(frame(1, QJsonObject {{"cmd", "SET_ACTIVITY"}, {"nonce", "kisel-clear"},
            {"args", QJsonObject {{"pid", QCoreApplication::applicationPid()}, {"activity", QJsonValue()}}}}));
        m_sock.flush();
        m_sock.waitForBytesWritten(300);
    }
    m_ready = false;
    m_sentAny = false;
    m_sent = {};
    m_sock.abort();
}

void DiscordPresence::apply()
{
    const QString id = m_prefs->discordAppId();
    if (!m_prefs->discordOn() || !m_live) {
        m_retry.stop();
        drop();
        set(QStringLiteral("off"));
        return;
    }
    if (!validId(id)) {
        m_retry.stop();
        drop();
        set(QStringLiteral("noid"));
        return;
    }
    if (id != m_id) { // another application: start over under it
        drop();
        m_id = id;
    }
    if (m_ready) {
        if (!m_settle.isActive())
            m_settle.start(300); // (the project's name was switched on or off)
        return;
    }
    if (m_state == QLatin1String("off") || m_state == QLatin1String("noid") || m_state == QLatin1String("refused"))
        set(QStringLiteral("waiting"));
    m_retry.start();
    if (m_sock.state() == QLocalSocket::UnconnectedState) {
        m_pipe = 0;
        dial();
    }
}

void DiscordPresence::dial()
{
    if (m_ready || !m_prefs->discordOn() || !validId(m_id) || m_sock.state() != QLocalSocket::UnconnectedState)
        return;
    m_sock.connectToServer(pipeName(m_pipe));
}

void DiscordPresence::read()
{
    m_in += m_sock.readAll();
    int op = 0;
    QJsonObject body;
    while (unframe(m_in, op, body)) {
        if (op == 2) { // Discord closes: it does not know this Application ID, most often
            m_retry.stop();
            m_sock.abort();
            set(QStringLiteral("refused"));
            return;
        }
        if (op == 3) { // ping
            m_sock.write(frame(4, body));
            continue;
        }
        if (op == 1 && !m_ready && body.value("evt").toString() == QLatin1String("READY")) {
            m_ready = true;
            m_retry.stop();
            set(QStringLiteral("on"));
            push();
        }
    }
}

void DiscordPresence::push()
{
    if (!m_ready)
        return;
    const QVariantMap s = m_hub->session();
    QString state = s.value("id").toString().isEmpty() ? QString() : s.value("state").toString();
    if (!s.value("id").toString().isEmpty() && state.isEmpty())
        state = QStringLiteral("idle");
    if (state.isEmpty())
        m_since = 0;
    else if (m_since == 0)
        m_since = QDateTime::currentSecsSinceEpoch();
    const QJsonObject a = activity(state, m_prefs->discordProject() ? s.value("name").toString() : QString(), m_since,
                                   m_prefs->language() == QLatin1String("ru"));
    if (m_sentAny && a == m_sent)
        return;
    m_sent = a;
    m_sentAny = true;
    m_sock.write(frame(1, QJsonObject {{"cmd", "SET_ACTIVITY"}, {"nonce", QString::number(QDateTime::currentMSecsSinceEpoch())},
        {"args", QJsonObject {{"pid", QCoreApplication::applicationPid()}, {"activity", a.isEmpty() ? QJsonValue() : QJsonValue(a)}}}}));
}

} // namespace kisel
