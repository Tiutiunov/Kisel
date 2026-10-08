#include "SpeedTest.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QUrl>

#include <memory>

namespace kisel {

namespace {
const QString kDown = QStringLiteral("https://speed.cloudflare.com/__down?bytes=%1");
const QUrl kUp(QStringLiteral("https://speed.cloudflare.com/__up"));
constexpr int kPings = 6;
constexpr int kStreams = 6; // (as many as Qt opens to one host at a time)
constexpr int kSpanMs = 8000;  // each way
constexpr int kRampMs = 1000;  // ...of which the first second is not counted
constexpr qint64 kChunkDown = 25'000'000;
constexpr int kChunkUp = 4'000'000;

QNetworkRequest request(const QUrl &url)
{
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "Kisel");
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    // Plain HTTP/1.1, a connection to each stream: over HTTP/2 Qt lets the other end send
    // only a small window at a time, and the test would measure that window, not the line.
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    return req;
}
} // namespace

SpeedTest::SpeedTest(QObject *parent)
    : QObject(parent)
{
    m_tick.setInterval(200);
    connect(&m_tick, &QTimer::timeout, this, &SpeedTest::tick);
    for (QTimer *t : {&m_fresh, &m_just, &m_cool}) {
        t->setSingleShot(true);
        connect(t, &QTimer::timeout, this, &SpeedTest::changed);
    }
    m_fresh.setInterval(60'000);
    m_just.setInterval(9'000);
    m_cool.setInterval(22'000);
}

SpeedTest::~SpeedTest() { dropReplies(); }

void SpeedTest::dropReplies()
{
    const auto replies = m_replies;
    m_replies.clear();
    for (const QPointer<QNetworkReply> &r : replies) {
        if (!r)
            continue;
        r->disconnect(this);
        r->abort();
        r->deleteLater();
    }
}

void SpeedTest::start()
{
    if (running())
        return;
    m_failed = false;
    m_done = false;
    m_down = m_up = 0;
    m_ping = -1;
    m_progress = 0;
    m_errors = 0;
    m_fresh.stop();
    m_just.stop();
    m_phase = QStringLiteral("ping");
    m_pingsLeft = kPings;
    emit changed();
    if (m_rehearsal) {
        m_clock.start();
        m_tick.start();
        return;
    }
    nextPing();
}

void SpeedTest::stop()
{
    if (!running())
        return;
    m_tick.stop();
    dropReplies();
    m_phase.clear();
    m_progress = 0;
    m_down = m_up = 0;
    m_ping = -1;
    m_cool.start();
    emit changed();
}

void SpeedTest::fail()
{
    m_tick.stop();
    dropReplies();
    m_phase.clear();
    m_failed = true;
    m_progress = 0;
    m_cool.start();
    emit changed();
}

void SpeedTest::finish()
{
    m_tick.stop();
    dropReplies();
    m_phase.clear();
    m_done = true;
    m_progress = 1;
    m_fresh.start();
    m_just.start();
    m_cool.start();
    emit changed();
    emit finished();
}

// One empty request, timed. The first of them also sets the connection up, so it is
// only the quickest of the six that counts.
void SpeedTest::nextPing()
{
    if (m_pingsLeft <= 0) {
        if (m_ping < 0) {
            fail();
            return;
        }
        beginTransfer(QStringLiteral("down"));
        return;
    }
    --m_pingsLeft;
    m_clock.start();
    QNetworkReply *r = m_net.get(request(QUrl(kDown.arg(0))));
    m_replies = {r};
    connect(r, &QNetworkReply::finished, this, [this, r] {
        r->deleteLater();
        m_replies.clear();
        if (m_phase != QLatin1String("ping"))
            return;
        if (r->error() == QNetworkReply::NoError) {
            const int ms = int(m_clock.elapsed());
            if (m_pingsLeft < kPings - 1) // (not the first)
                m_ping = m_ping < 0 ? ms : qMin(m_ping, ms);
            QByteArray colo = r->rawHeader("cf-meta-colo");
            if (colo.isEmpty()) // (the request's id ends in the data centre's code: "...-WAW")
                colo = r->rawHeader("cf-ray").split('-').last();
            if (!colo.isEmpty() && colo.size() <= 4)
                m_place = QString::fromLatin1(colo);
        } else if (++m_errors >= 3) {
            fail();
            return;
        }
        m_progress = 0.06 * (kPings - m_pingsLeft) / kPings;
        emit changed();
        nextPing();
    });
}

void SpeedTest::beginTransfer(const QString &phase)
{
    m_phase = phase;
    m_bytes = 0;
    m_bytes0 = -1;
    m_errors = 0;
    if (phase == QLatin1String("up") && m_load.isEmpty()) {
        // (not zeros: nothing on the way must be able to squeeze it)
        m_load.resize(kChunkUp);
        QRandomGenerator::global()->fillRange(reinterpret_cast<quint32 *>(m_load.data()), kChunkUp / 4);
    }
    m_clock.start();
    m_tick.start();
    for (int i = 0; i < kStreams; ++i)
        stream();
    emit changed();
}

// One of the four streams. When it has run through its load it starts again, until
// the phase's time is up.
void SpeedTest::stream()
{
    const bool up = m_phase == QLatin1String("up");
    QNetworkReply *r = nullptr;
    if (up) {
        QNetworkRequest req = request(kUp);
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/octet-stream");
        r = m_net.post(req, m_load);
        auto sent = std::make_shared<qint64>(0);
        connect(r, &QNetworkReply::uploadProgress, this, [this, sent](qint64 now, qint64) {
            if (now > *sent) {
                m_bytes += now - *sent;
                *sent = now;
            }
        });
    } else {
        r = m_net.get(request(QUrl(kDown.arg(kChunkDown))));
        connect(r, &QNetworkReply::readyRead, this, [this, r] { m_bytes += r->readAll().size(); });
    }
    m_replies.append(r);
    const QString phase = m_phase;
    connect(r, &QNetworkReply::finished, this, [this, r, phase] {
        r->deleteLater();
        m_replies.removeAll(r);
        if (m_phase != phase)
            return;
        if (r->error() != QNetworkReply::NoError && ++m_errors >= 6) {
            fail();
            return;
        }
        stream();
    });
}

void SpeedTest::tick()
{
    const qint64 t = m_clock.elapsed();
    if (m_rehearsal) { // (development: the same course without the network)
        const qint64 all = 1200 + 2 * 3000;
        // (KISEL_DEMO_MBPS=<n>: how fast the acted-out line is; 93.4 if not said)
        const qreal top = qEnvironmentVariableIsSet("KISEL_DEMO_MBPS") ? qEnvironmentVariable("KISEL_DEMO_MBPS").toDouble() : 93.4;
        if (t < 1200) {
            m_phase = QStringLiteral("ping");
            m_ping = 14;
        } else if (t < 4200) {
            m_phase = QStringLiteral("down");
            m_down = top * qMin(1.0, (t - 1200) / 1500.0);
        } else if (t < all) {
            m_phase = QStringLiteral("up");
            m_down = top;
            m_up = top * 0.44 * qMin(1.0, (t - 4200) / 1500.0);
        } else {
            m_up = top * 0.44;
            m_place = QStringLiteral("WAW");
            finish();
            return;
        }
        m_progress = qreal(t) / all;
        emit changed();
        return;
    }
    if (t >= kRampMs && m_bytes0 < 0) { // the count starts here
        m_bytes0 = m_bytes;
        m_t0 = t;
    }
    const qreal mbit = m_bytes0 >= 0 && t > m_t0 ? qreal(m_bytes - m_bytes0) * 8 / (qreal(t - m_t0) / 1000) / 1e6
                                                 : qreal(m_bytes) * 8 / (qMax<qint64>(t, 1) / 1000.0) / 1e6;
    const bool up = m_phase == QLatin1String("up");
    (up ? m_up : m_down) = mbit;
    m_progress = 0.06 + 0.47 * (up ? 1 : 0) + 0.47 * qMin(1.0, qreal(t) / kSpanMs);
    if (t >= 3000 && m_bytes == 0) { // nothing has moved at all
        fail();
        return;
    }
    if (t >= kSpanMs) {
        endPhase();
        return;
    }
    emit changed();
}

void SpeedTest::endPhase()
{
    m_tick.stop();
    dropReplies();
    if (m_phase == QLatin1String("down")) {
        beginTransfer(QStringLiteral("up"));
        return;
    }
    finish();
}

void SpeedTest::rehearse()
{
    m_rehearsal = true;
    start();
}

} // namespace kisel
