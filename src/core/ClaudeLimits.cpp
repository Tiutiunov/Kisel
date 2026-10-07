#include "ClaudeLimits.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace kisel {

namespace {
// what Claude's own apps ask for these figures (not a documented address)
const char *const kUrl = "https://api.anthropic.com/api/oauth/usage";

// the share used: the server gives a percentage (or, to be safe, a fraction)
qreal share(const QJsonObject &window)
{
    const qreal v = window.value(QLatin1String("utilization")).toDouble();
    return qBound<qreal>(0, v > 1 ? v / 100 : v, 1);
}

QString resetAt(const QJsonObject &window, bool withDay)
{
    const QDateTime at = QDateTime::fromString(window.value(QLatin1String("resets_at")).toString(), Qt::ISODateWithMs).toLocalTime();
    if (!at.isValid())
        return {};
    return QLocale::c().toString(at, withDay ? QStringLiteral("ddd HH:mm") : QStringLiteral("HH:mm"));
}
} // namespace

ClaudeLimits::ClaudeLimits(Secrets *secrets, QObject *parent)
    : QObject(parent)
    , m_secrets(secrets)
{
    // KISEL_DEMO_LIMIT=1: made-up figures, to look at the strip without a key (development)
    if (qEnvironmentVariableIsSet("KISEL_DEMO_LIMIT")) {
        m_state = QStringLiteral("ok");
        m_fiveHour = 0.62;
        m_week = 0.27;
        m_fiveHourReset = QStringLiteral("04:00");
        m_weekReset = QStringLiteral("Thu 09:00");
        return;
    }
    m_timer.setInterval(3 * 60 * 1000);
    connect(&m_timer, &QTimer::timeout, this, &ClaudeLimits::refresh);
    // a key saved or removed in Settings: ask at once, or forget what was known
    connect(secrets, &Secrets::changed, this, &ClaudeLimits::refresh);
    m_timer.start();
    QTimer::singleShot(1500, this, &ClaudeLimits::refresh);
}

bool ClaudeLimits::hasKey() { return m_secrets->has(QString::fromLatin1(kKey)); }

void ClaudeLimits::fail(const QString &why)
{
    m_state = QStringLiteral("error");
    m_error = why;
    emit changed();
}

void ClaudeLimits::refresh()
{
    if (m_reply)
        return;
    const QString key = m_secrets->read(QString::fromLatin1(kKey));
    if (key.isEmpty()) {
        if (m_state != QLatin1String("none")) {
            m_state = QStringLiteral("none");
            m_error.clear();
            m_fiveHour = m_week = 0;
            m_fiveHourReset.clear();
            m_weekReset.clear();
            emit changed();
        }
        return;
    }
    if (m_state == QLatin1String("none")) {
        m_state = QStringLiteral("loading");
        emit changed();
    }
    QNetworkRequest req {QUrl(QString::fromLatin1(kUrl))};
    req.setRawHeader("Authorization", "Bearer " + key.toUtf8());
    req.setRawHeader("anthropic-beta", "oauth-2025-04-20");
    req.setRawHeader("User-Agent", "Kisel");
    req.setTransferTimeout(15000);
    m_reply = m_net.get(req);
    connect(m_reply, &QNetworkReply::finished, this, [this, reply = m_reply.data()] { finished(reply); });
}

void ClaudeLimits::finished(QNetworkReply *reply)
{
    reply->deleteLater();
    m_reply.clear();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status == 401)
        return fail(QStringLiteral("The key was not accepted. It may have expired."));
    if (status == 403)
        return fail(QStringLiteral("This key is not allowed to read the limit."));
    if (status == 429)
        return fail(QStringLiteral("Asked too often. It will try again in a few minutes."));
    if (reply->error() != QNetworkReply::NoError || status != 200)
        return fail(status ? QStringLiteral("The server answered %1.").arg(status) : QStringLiteral("No answer from the server."));
    const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
    const QJsonObject five = o.value(QLatin1String("five_hour")).toObject();
    const QJsonObject week = o.value(QLatin1String("seven_day")).toObject();
    if (five.isEmpty() && week.isEmpty())
        return fail(QStringLiteral("The answer had no limits in it."));
    m_fiveHour = share(five);
    m_week = share(week);
    m_fiveHourReset = resetAt(five, false);
    m_weekReset = resetAt(week, true);
    m_state = QStringLiteral("ok");
    m_error.clear();
    emit changed();
}

} // namespace kisel
