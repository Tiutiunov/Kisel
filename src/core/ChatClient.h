#pragma once

#include "Preferences.h"
#include "Secrets.h"

#include <QAbstractListModel>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QUrl>

namespace kisel {

class ChatModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles { RoleRole = Qt::UserRole + 1, TextRole, FileRole, TimeRole };
    struct Msg { QString role, text, file, time; };

    explicit ChatModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_msgs.size()); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void append(const Msg &m);
    void appendToLast(const QString &text);
    void clear();
    const QList<Msg> &messages() const { return m_msgs; }

private:
    QList<Msg> m_msgs;
};

// Chat with Claude from the island: Anthropic Messages API, streamed.
// Text shows exactly as it streams (no typewriter), per motion.md.
class ChatClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *messages READ messages CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString attachedName READ attachedName NOTIFY attachmentChanged)
    Q_PROPERTY(QString model READ model NOTIFY modelChanged)

public:
    ChatClient(Preferences *prefs, Secrets *secrets, QObject *parent = nullptr);

    QObject *messages() { return &m_model; }
    bool busy() const { return m_reply != nullptr; }
    QString error() const { return m_error; }
    QString attachedName() const { return m_attachName; }
    QString model() const { return m_prefs->model(); }

    Q_INVOKABLE void send(const QString &text);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void clear();
    // A dropped file. Text files up to 200 KB are inlined into the next message.
    Q_INVOKABLE bool attach(const QUrl &file);
    Q_INVOKABLE void detach();

    // Pure, unit-tested: one Server-Sent-Events data line -> text delta / error.
    static bool parseSseLine(const QByteArray &line, QString *delta, QString *error, bool *done);

signals:
    void busyChanged();
    void errorChanged();
    void attachmentChanged();
    void modelChanged();
    void replyStarted();
    void replyFinished();

private:
    void fail(const QString &message);
    void finish();
    QJsonArray history() const;

    Preferences *m_prefs;
    Secrets *m_secrets;
    QNetworkAccessManager m_net;
    ChatModel m_model;
    QPointer<QNetworkReply> m_reply;
    QByteArray m_buf;
    QString m_error;
    QString m_attachName, m_attachText;
};

} // namespace kisel
