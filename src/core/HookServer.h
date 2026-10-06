#pragma once

#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QObject>

namespace kisel {

// One hook event from the relay. Fire-and-forget events are closed as soon as
// they are parsed; a PermissionRequest stays open until answer() or until the
// relay goes away (the user answered in the terminal: gone() fires).
class HookConnection : public QObject
{
    Q_OBJECT
public:
    HookConnection(QLocalSocket *socket, QObject *parent);

    const QJsonObject &payload() const { return m_payload; }
    QString event() const { return m_payload.value("hook_event_name").toString(); }
    bool waitsForAnswer() const { return event() == QLatin1String("PermissionRequest"); }

    // "allow" | "deny" | "always". The relay turns these into Claude Code's
    // documented PermissionRequest output.
    void answer(const QString &decision);
    // Close without a word: the relay prints nothing and Claude Code asks in
    // the terminal, exactly as if Kisel were not installed.
    void release();

signals:
    void parsed(kisel::HookConnection *self);
    void gone(); // peer disconnected before we answered

private:
    void onReadyRead();
    QLocalSocket *m_socket;
    QByteArray m_buf;
    QJsonObject m_payload;
    bool m_parsed = false;
    bool m_answered = false;
};

class HookServer : public QObject
{
    Q_OBJECT
public:
    explicit HookServer(QObject *parent = nullptr);
    bool start(const QString &socketPath);
    QString errorString() const { return m_server.errorString(); }

signals:
    void eventReceived(kisel::HookConnection *connection);

private:
    void onNewConnection();
    QLocalServer m_server;
};

} // namespace kisel
