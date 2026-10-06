#include "ChatClient.h"

#include <QFile>
#include <QTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>

namespace kisel {

namespace {
constexpr qint64 kMaxAttach = 200 * 1024;
const QUrl kEndpoint(QStringLiteral("https://api.anthropic.com/v1/messages"));
const QString kSystem = QStringLiteral(
    "You are Kisel, a small desktop companion for a developer on KDE Plasma. "
    "Answer briefly and concretely. Quote commands and paths in backticks.");
} // namespace

QVariant ChatModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_msgs.size())
        return {};
    const Msg &m = m_msgs.at(index.row());
    switch (role) {
    case RoleRole: return m.role;
    case TextRole: return m.text;
    case FileRole: return m.file;
    case TimeRole: return m.time;
    }
    return {};
}

QHash<int, QByteArray> ChatModel::roleNames() const
{
    return {{RoleRole, "role"}, {TextRole, "text"}, {FileRole, "file"}, {TimeRole, "time"}};
}

void ChatModel::append(const Msg &m)
{
    beginInsertRows({}, int(m_msgs.size()), int(m_msgs.size()));
    m_msgs.append(m);
    endInsertRows();
}

void ChatModel::appendToLast(const QString &text)
{
    if (m_msgs.isEmpty())
        return;
    m_msgs.last().text += text;
    const QModelIndex i = index(int(m_msgs.size()) - 1);
    emit dataChanged(i, i, {TextRole});
}

void ChatModel::clear()
{
    beginResetModel();
    m_msgs.clear();
    endResetModel();
}

ChatClient::ChatClient(Preferences *prefs, Secrets *secrets, QObject *parent)
    : QObject(parent)
    , m_prefs(prefs)
    , m_secrets(secrets)
    , m_model(this)
{
    connect(prefs, &Preferences::changed, this, &ChatClient::modelChanged);
}

bool ChatClient::attach(const QUrl &url)
{
    const QString path = url.toLocalFile();
    QFile f(path);
    if (path.isEmpty() || !f.open(QIODevice::ReadOnly) || f.size() > kMaxAttach) {
        fail(QStringLiteral("Can't read that file (text files up to 200 KB)"));
        return false;
    }
    const QByteArray bytes = f.readAll();
    if (bytes.contains('\0')) {
        fail(QStringLiteral("That looks like a binary file"));
        return false;
    }
    m_attachName = QFileInfo(path).fileName();
    m_attachText = QString::fromUtf8(bytes);
    emit attachmentChanged();
    return true;
}

void ChatClient::detach()
{
    m_attachName.clear();
    m_attachText.clear();
    emit attachmentChanged();
}

QJsonArray ChatClient::history() const
{
    QJsonArray out;
    for (const ChatModel::Msg &m : m_model.messages()) {
        if (m.text.isEmpty())
            continue; // the empty assistant bubble we are about to fill
        out.append(QJsonObject {{"role", m.role}, {"content", m.text}});
    }
    return out;
}

void ChatClient::send(const QString &text)
{
    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty() || m_reply)
        return;

    const QString key = m_secrets->read(Secrets::kAnthropic);
    if (key.isEmpty()) {
        fail(QStringLiteral("Add your Anthropic API key in Settings"));
        return;
    }
    if (!m_error.isEmpty()) {
        m_error.clear();
        emit errorChanged();
    }

    QString content = trimmed;
    if (!m_attachText.isEmpty())
        content = QStringLiteral("File `%1`:\n```\n%2\n```\n\n%3").arg(m_attachName, m_attachText, trimmed);
    m_model.append({QStringLiteral("user"), trimmed, m_attachName, QTime::currentTime().toString("HH:mm")});
    // The API sees the inlined file; the bubble only shows the chip.
    QJsonArray msgs = history();
    msgs.removeLast();
    msgs.append(QJsonObject {{"role", "user"}, {"content", content}});
    detach();
    m_model.append({QStringLiteral("assistant"), QString(), QString(), QTime::currentTime().toString("HH:mm")});

    QNetworkRequest req(kEndpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("x-api-key", key.toUtf8());
    req.setRawHeader("anthropic-version", "2023-06-01");
    const QJsonObject body {{"model", m_prefs->model()}, {"max_tokens", 4096}, {"stream", true},
                            {"system", kSystem}, {"messages", msgs}};
    m_buf.clear();
    m_reply = m_net.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(m_reply, &QNetworkReply::readyRead, this, [this] {
        if (!m_reply)
            return;
        m_buf += m_reply->readAll();
        qsizetype nl;
        while ((nl = m_buf.indexOf('\n')) >= 0) {
            const QByteArray line = m_buf.left(nl).trimmed();
            m_buf.remove(0, nl + 1);
            QString delta, err;
            bool done = false;
            if (!parseSseLine(line, &delta, &err, &done))
                continue;
            if (!err.isEmpty()) {
                fail(err);
                return;
            }
            if (!delta.isEmpty())
                m_model.appendToLast(delta);
            if (done)
                return;
        }
    });
    connect(m_reply, &QNetworkReply::finished, this, [this] {
        QNetworkReply *r = m_reply;
        if (!r)
            return;
        if (r->error() != QNetworkReply::NoError && r->error() != QNetworkReply::OperationCanceledError) {
            // The API puts its message in the body, e.g. a bad key.
            QString msg = r->errorString();
            const QJsonObject o = QJsonDocument::fromJson(m_buf + r->readAll()).object();
            if (o.contains("error"))
                msg = o.value("error").toObject().value("message").toString(msg);
            fail(msg);
            return;
        }
        finish();
    });
    emit busyChanged();
    emit replyStarted();
}

bool ChatClient::parseSseLine(const QByteArray &line, QString *delta, QString *error, bool *done)
{
    if (!line.startsWith("data:"))
        return false;
    const QJsonObject o = QJsonDocument::fromJson(line.mid(5).trimmed()).object();
    const QString type = o.value("type").toString();
    if (type == QLatin1String("content_block_delta")) {
        const QJsonObject d = o.value("delta").toObject();
        if (d.value("type").toString() == QLatin1String("text_delta"))
            *delta = d.value("text").toString();
        return true;
    }
    if (type == QLatin1String("message_stop")) {
        *done = true;
        return true;
    }
    if (type == QLatin1String("error")) {
        *error = o.value("error").toObject().value("message").toString(QStringLiteral("The request failed"));
        return true;
    }
    return false;
}

void ChatClient::cancel()
{
    if (m_reply)
        m_reply->abort();
}

void ChatClient::clear()
{
    cancel();
    m_model.clear();
}

void ChatClient::fail(const QString &message)
{
    m_error = message;
    emit errorChanged();
    if (m_reply) {
        QNetworkReply *r = m_reply;
        m_reply = nullptr;
        r->abort();
        r->deleteLater();
        emit busyChanged();
    }
}

void ChatClient::finish()
{
    QNetworkReply *r = m_reply;
    m_reply = nullptr;
    if (r)
        r->deleteLater();
    emit busyChanged();
    emit replyFinished();
}

} // namespace kisel
