#include "HookServer.h"

#include <QJsonDocument>

#include <sys/socket.h>
#include <unistd.h>

namespace kisel {

namespace {
constexpr qsizetype kMaxPayload = 1 << 20;

// True when the process on the other end runs as the same user. A socket in a
// 0700 runtime dir already keeps strangers out; this is the belt to that brace.
bool sameUser(QLocalSocket *s)
{
    ucred cred {};
    socklen_t len = sizeof cred;
    if (getsockopt(int(s->socketDescriptor()), SOL_SOCKET, SO_PEERCRED, &cred, &len) != 0)
        return false;
    return cred.uid == getuid();
}
} // namespace

HookConnection::HookConnection(QLocalSocket *socket, QObject *parent)
    : QObject(parent)
    , m_socket(socket)
{
    m_socket->setParent(this);
    connect(m_socket, &QLocalSocket::readyRead, this, &HookConnection::onReadyRead);
    connect(m_socket, &QLocalSocket::disconnected, this, [this] {
        if (!m_answered)
            emit gone();
        deleteLater();
    });
}

void HookConnection::onReadyRead()
{
    if (m_parsed) { // anything after the first line is ignored
        m_socket->readAll();
        return;
    }
    m_buf += m_socket->readAll();
    if (m_buf.size() > kMaxPayload) {
        m_socket->abort();
        return;
    }
    const qsizetype nl = m_buf.indexOf('\n');
    if (nl < 0)
        return;

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(m_buf.left(nl), &err);
    m_parsed = true;
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        m_socket->disconnectFromServer();
        return;
    }
    m_payload = doc.object();
    emit parsed(this);
    if (!waitsForAnswer())
        m_socket->disconnectFromServer();
}

void HookConnection::answer(const QString &decision)
{
    if (m_answered || m_socket->state() != QLocalSocket::ConnectedState)
        return;
    m_answered = true;
    m_socket->write(decision.toUtf8() + '\n');
    m_socket->flush();
    m_socket->disconnectFromServer();
}

void HookConnection::release()
{
    m_answered = true;
    m_socket->disconnectFromServer();
}

HookServer::HookServer(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QLocalServer::newConnection, this, &HookServer::onNewConnection);
}

bool HookServer::start(const QString &socketPath)
{
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketPath); // a stale file from a crash
    return m_server.listen(socketPath);
}

void HookServer::onNewConnection()
{
    while (QLocalSocket *s = m_server.nextPendingConnection()) {
        if (!sameUser(s)) {
            s->abort();
            s->deleteLater();
            continue;
        }
        auto *conn = new HookConnection(s, this);
        connect(conn, &HookConnection::parsed, this, &HookServer::eventReceived);
    }
}

} // namespace kisel
