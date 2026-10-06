#include "GitHubClient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>

namespace kisel {

namespace {
const QUrl kEndpoint(QStringLiteral("https://api.github.com/graphql"));
const QByteArray kQuery = R"(query {
  viewer {
    login
    pullRequests(first: 5, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      nodes {
        title number url isDraft reviewDecision
        repository { nameWithOwner }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
  reviews: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 1) { issueCount }
})";
} // namespace

GitHubClient::GitHubClient(Secrets *secrets, QObject *parent)
    : QObject(parent)
    , m_secrets(secrets)
{
    m_timer.setInterval(5 * 60 * 1000);
    connect(&m_timer, &QTimer::timeout, this, &GitHubClient::refresh);
    connect(secrets, &Secrets::changed, this, &GitHubClient::changed);
}

bool GitHubClient::hasToken() { return m_secrets->has(QStringLiteral("github")); }

void GitHubClient::setPolling(bool on)
{
    if (on == m_timer.isActive())
        return;
    if (on)
        m_timer.start();
    else
        m_timer.stop();
    emit changed();
}

QString GitHubClient::ciState(const QString &rollup)
{
    if (rollup == QLatin1String("SUCCESS"))
        return QStringLiteral("success");
    if (rollup == QLatin1String("FAILURE") || rollup == QLatin1String("ERROR"))
        return QStringLiteral("failure");
    if (rollup == QLatin1String("PENDING") || rollup == QLatin1String("EXPECTED"))
        return QStringLiteral("pending");
    return QStringLiteral("none");
}

bool GitHubClient::parse(const QByteArray &body, Result *out, QString *error)
{
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(body, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        *error = QStringLiteral("GitHub sent something unexpected");
        return false;
    }
    const QJsonObject root = doc.object();
    if (root.contains("errors")) {
        *error = root.value("errors").toArray().first().toObject().value("message").toString(QStringLiteral("GitHub refused the request"));
        return false;
    }
    const QJsonObject data = root.value("data").toObject();
    const QJsonObject viewer = data.value("viewer").toObject();
    if (viewer.isEmpty()) {
        *error = QStringLiteral("GitHub sent something unexpected");
        return false;
    }
    out->login = viewer.value("login").toString();
    const QJsonObject prs = viewer.value("pullRequests").toObject();
    out->open = prs.value("totalCount").toInt();
    out->reviews = data.value("reviews").toObject().value("issueCount").toInt();
    for (const QJsonValue &v : prs.value("nodes").toArray()) {
        const QJsonObject n = v.toObject();
        const QString rollup = n.value("commits").toObject().value("nodes").toArray().first().toObject()
                                   .value("commit").toObject().value("statusCheckRollup").toObject().value("state").toString();
        out->rows.append(QVariantMap {
            {"title", n.value("title").toString()},
            {"repo", n.value("repository").toObject().value("nameWithOwner").toString()},
            {"number", n.value("number").toInt()},
            {"url", n.value("url").toString()},
            {"draft", n.value("isDraft").toBool()},
            {"review", n.value("reviewDecision").toString()},
            {"ci", ciState(rollup)},
        });
    }
    return true;
}

void GitHubClient::refresh()
{
    if (m_reply)
        return;
    const QString token = m_secrets->read(QStringLiteral("github"));
    if (token.isEmpty()) {
        m_error.clear();
        emit changed();
        return;
    }
    m_error.clear();
    QNetworkRequest req(kEndpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Authorization", "bearer " + token.toUtf8());
    req.setRawHeader("User-Agent", "Kisel");
    const QByteArray body = QJsonDocument(QJsonObject {{"query", QString::fromUtf8(kQuery)}}).toJson(QJsonDocument::Compact);
    m_reply = m_net.post(req, body);
    connect(m_reply, &QNetworkReply::finished, this, [this] {
        QNetworkReply *r = m_reply;
        m_reply = nullptr;
        if (!r)
            return;
        r->deleteLater();
        const QByteArray bytes = r->readAll();
        if (r->error() != QNetworkReply::NoError && bytes.isEmpty()) {
            fail(r->errorString());
            return;
        }
        if (r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 401) {
            fail(QStringLiteral("GitHub rejected the token"));
            return;
        }
        Result res;
        QString err;
        if (!parse(bytes, &res, &err)) {
            fail(err);
            return;
        }
        const bool first = !m_loaded;
        m_login = res.login;
        m_open = res.open;
        m_reviews = res.reviews;
        m_rows = res.rows;
        m_loaded = true;
        emit changed();
        if (first)
            emit firstLoaded();
    });
    emit changed();
}

void GitHubClient::fail(const QString &message)
{
    m_error = message;
    emit changed();
}

} // namespace kisel
