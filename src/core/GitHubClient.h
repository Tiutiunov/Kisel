#pragma once

#include "Secrets.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>

namespace kisel {

// The GitHub widget's data: your open pull requests (with CI state), how many
// reviews are waiting for you. One GraphQL request with a personal access token
// from KWallet; read-only, nothing else is ever called. Refreshes every five
// minutes while the widget is open.
class GitHubClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(bool loaded READ loaded NOTIFY changed)
    Q_PROPERTY(bool hasToken READ hasToken NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString login READ login NOTIFY changed)
    Q_PROPERTY(int openCount READ openCount NOTIFY changed)
    Q_PROPERTY(int reviewCount READ reviewCount NOTIFY changed)
    Q_PROPERTY(QVariantList rows READ rows NOTIFY changed)
    Q_PROPERTY(bool polling READ polling WRITE setPolling NOTIFY changed)

public:
    GitHubClient(Secrets *secrets, QObject *parent = nullptr);

    bool loading() const { return m_reply != nullptr; }
    bool loaded() const { return m_loaded; }
    bool hasToken();
    QString error() const { return m_error; }
    QString login() const { return m_login; }
    int openCount() const { return m_open; }
    int reviewCount() const { return m_reviews; }
    QVariantList rows() const { return m_rows; }
    bool polling() const { return m_timer.isActive(); }
    void setPolling(bool on);

    Q_INVOKABLE void refresh();

    struct Result {
        QString login;
        int open = 0, reviews = 0;
        QVariantList rows;
    };
    // Pure and unit-tested: the GraphQL response body -> Result or an error message.
    static bool parse(const QByteArray &body, Result *out, QString *error);
    static QString ciState(const QString &rollup);

signals:
    void changed();
    void firstLoaded(); // the first successful load: the widget does its success move

private:
    void fail(const QString &message);

    Secrets *m_secrets;
    QNetworkAccessManager m_net;
    QPointer<QNetworkReply> m_reply;
    QTimer m_timer;
    bool m_loaded = false;
    QString m_error, m_login;
    int m_open = 0, m_reviews = 0;
    QVariantList m_rows;
};

} // namespace kisel
