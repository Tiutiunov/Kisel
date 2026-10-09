#include "PromptRelay.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>

namespace kisel {

namespace {
constexpr int kHistoryLines = 200;       // of one project
constexpr int kHistoryChars = 4000;      // of one line
constexpr int kHistoryBytes = 200 * 1024; // of one project, before packing
constexpr qint64 kFreshMs = 7000;      // a heartbeat older than this: nobody is listening
constexpr qint64 kStaleMs = 10 * 60000; // a prompt nobody took in ten minutes is withdrawn
constexpr qint64 kOldReplyMs = 2 * 60000; // a reply written while Kisel was not looking is not news
constexpr qint64 kReplyMax = 64 * 1024;
}

PromptRelay::PromptRelay(const QString &root, QObject *parent) : QObject(parent), m_root(root)
{
    m_timer.setInterval(1000);
    connect(&m_timer, &QTimer::timeout, this, &PromptRelay::scan);
    m_timer.start(); // (from the start: a mod may be beating in a folder Kisel has not been told of, see `best`)
}

// (a key may be a path: its file is named by a digest of it)
QString PromptRelay::historyFile(const QString &key) const
{
    const QByteArray name = QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex().left(24);
    return QDir::cleanPath(m_root + QStringLiteral("/../history/")) + QLatin1Char('/') + QString::fromLatin1(name) + QStringLiteral(".json");
}

QString PromptRelay::home(const QString &cwd) const
{
    if (cwd.isEmpty())
        return cwd;
    const bool back = cwd.contains(QLatin1Char('\\'));
    QString best = cwd, at = QDir::fromNativeSeparators(cwd);
    for (int i = 0; i < 12; ++i) {
        const QString key = back ? QDir::toNativeSeparators(at) : at;
        if (QFileInfo::exists(historyFile(key)))
            best = key;
        const int cut = at.lastIndexOf(QLatin1Char('/'));
        if (cut <= 2) // (not the drive, nor the root: nobody's project)
            break;
        at.truncate(cut);
    }
    return best;
}

QVariantList PromptRelay::history(const QString &key) const
{
    QFile f(historyFile(key));
    if (key.isEmpty() || !f.open(QIODevice::ReadOnly) || f.size() > 8 * 1024 * 1024)
        return {};
    QVariantList out;
    for (const QJsonValue &v : QJsonDocument::fromJson(qUncompress(f.readAll())).array()) {
        const QJsonObject o = v.toObject();
        const QString role = o.value("role").toString();
        if (role != QLatin1String("user") && role != QLatin1String("assistant"))
            continue;
        out.append(QVariantMap {{"role", role}, {"text", o.value("text").toString().left(kHistoryChars)}, {"time", o.value("time").toString().left(16)}});
    }
    return out;
}

void PromptRelay::remember(const QString &key, const QString &role, const QString &text)
{
    if (key.isEmpty() || text.trimmed().isEmpty() || (role != QLatin1String("user") && role != QLatin1String("assistant")))
        return;
    QJsonArray all;
    for (const QVariant &v : history(key))
        all.append(QJsonObject::fromVariantMap(v.toMap()));
    const QString body = text.trimmed();
    all.append(QJsonObject {{"role", role}, {"text", body.size() > kHistoryChars ? body.left(kHistoryChars) + QChar(0x2026) : body},
                            {"time", QDateTime::currentDateTime().toString(QStringLiteral("dd.MM hh:mm"))}});
    while (all.size() > kHistoryLines)
        all.removeFirst();
    QByteArray json = QJsonDocument(all).toJson(QJsonDocument::Compact);
    while (json.size() > kHistoryBytes && all.size() > 1) { // (the oldest go first)
        all.removeFirst();
        json = QJsonDocument(all).toJson(QJsonDocument::Compact);
    }
    const QString path = historyFile(key);
    if (!QDir().mkpath(QFileInfo(path).path()))
        return;
    QSaveFile out(path);
    if (out.open(QIODevice::WriteOnly)) {
        out.write(qCompress(json, 9));
        out.commit();
    }
}

void PromptRelay::forget(const QString &key)
{
    if (!key.isEmpty())
        QFile::remove(historyFile(key));
}

QString PromptRelay::best(const QString &session) const
{
    if (m_live.contains(session) || m_live.isEmpty())
        return session;
    QString newest;
    QDateTime at;
    for (const QString &s : m_live) {
        const QDateTime t = QFileInfo(folder(s) + QStringLiteral("/alive")).lastModified();
        if (newest.isEmpty() || t > at) {
            newest = s;
            at = t;
        }
    }
    return newest;
}

// (a session id becomes a folder name: nothing that could climb out of the inbox)
bool PromptRelay::safeId(const QString &session)
{
    static const QRegularExpression ok(QStringLiteral("^[A-Za-z0-9_-]{1,80}$"));
    return ok.match(session).hasMatch();
}

QString PromptRelay::folder(const QString &session) const
{
    return m_root + QLatin1Char('/') + session;
}

void PromptRelay::watch(const QString &session)
{
    if (!safeId(session) || m_watched.contains(session))
        return;
    if (!QDir().mkpath(folder(session)))
        return;
    m_watched.append(session);
    if (!m_timer.isActive())
        m_timer.start();
    scan();
}

bool PromptRelay::send(const QString &session, const QString &text)
{
    const QString body = text.trimmed();
    if (body.isEmpty() || !safeId(session) || !m_live.contains(session))
        return false;
    const QString name = QStringLiteral("%1-%2.prompt").arg(QDateTime::currentMSecsSinceEpoch()).arg(m_next++);
    QSaveFile out(folder(session) + QLatin1Char('/') + name); // (whole or not at all: the mod never reads half a prompt)
    if (!out.open(QIODevice::WriteOnly))
        return false;
    out.write(body.toUtf8());
    if (!out.commit())
        return false;
    scan();
    return true;
}

// (Written by a mod, so read as anything from outside is: only the fields named, only
// numbers in range, a handful of entries at most.)
QVariantList PromptRelay::parseLimits(const QByteArray &json)
{
    QVariantList out;
    const QJsonObject root = QJsonDocument::fromJson(json).object();
    auto add = [&out](const QString &kind, const QJsonValue &used, const QString &resetsAt) {
        if (kind.isEmpty() || kind.size() > 40 || !used.isDouble() || out.size() >= 6)
            return;
        out.append(QVariantMap {{"kind", kind}, {"used", qBound(0.0, used.toDouble(), 100.0)}, {"resetsAt", resetsAt.left(40)}});
    };
    for (const QJsonValue &v : root.value("limits").toArray()) {
        const QJsonObject o = v.toObject();
        add(o.value("kind").toString(), o.value("used"), o.value("resetsAt").toString());
    }
    if (root.value("context").isObject()) {
        const QJsonObject c = root.value("context").toObject();
        const int before = out.size();
        add(QStringLiteral("context"), c.value("used"), QString());
        if (out.size() > before) { // (how many tokens of how many: shown beside the percent)
            QVariantMap m = out.last().toMap();
            m.insert("tokens", qBound(0.0, c.value("tokens").toDouble(), 1e9));
            m.insert("window", qBound(0.0, c.value("window").toDouble(), 1e9));
            out.last() = m;
        }
    }
    return out;
}

// (a model's id: letters, digits and a few marks, and short; anything else is not shown)
QString PromptRelay::parseModel(const QByteArray &json)
{
    const QString m = QJsonDocument::fromJson(json).object().value("model").toString();
    static const QRegularExpression ok(QStringLiteral("^[A-Za-z0-9._:\\[\\]@/-]{1,60}$"));
    return ok.match(m).hasMatch() ? m : QString();
}

void PromptRelay::scan()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QStringList live, waiting, took;
    QList<QPair<QString, QString>> said;
    bool limitsMoved = false;
    // (a folder with a fresh heartbeat is a session to watch, whether or not Kisel was told its name)
    for (const QFileInfo &d : QDir(m_root).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (m_watched.size() >= 32 || m_watched.contains(d.fileName()) || !safeId(d.fileName()))
            continue;
        const QFileInfo beat(d.filePath() + QStringLiteral("/alive"));
        if (beat.exists() && now - beat.lastModified().toMSecsSinceEpoch() < kFreshMs)
            m_watched.append(d.fileName());
    }
    for (const QString &session : std::as_const(m_watched)) {
        const QDir dir(folder(session));
        const QFileInfo beat(dir.filePath(QStringLiteral("alive")));
        if (beat.exists() && now - beat.lastModified().toMSecsSinceEpoch() < kFreshMs)
            live.append(session);
        // (their names begin with the time they were written: in order)
        for (const QFileInfo &f : dir.entryInfoList({QStringLiteral("*.reply")}, QDir::Files, QDir::Name)) {
            if (now - f.lastModified().toMSecsSinceEpoch() < kOldReplyMs && f.size() <= kReplyMax) {
                QFile in(f.filePath());
                if (!in.open(QIODevice::ReadOnly))
                    continue; // still being written: next time
                const QString text = QString::fromUtf8(in.readAll()).trimmed();
                in.close();
                if (!text.isEmpty())
                    said.append({session, text});
            }
            QFile::remove(f.filePath());
        }
        const QFileInfo lim(dir.filePath(QStringLiteral("limits")));
        if (lim.exists() && lim.size() < 8192) {
            const qint64 at = lim.lastModified().toMSecsSinceEpoch();
            if (m_limitsRead.value(session) != at) {
                QFile f(lim.filePath());
                if (f.open(QIODevice::ReadOnly)) {
                    m_limitsRead[session] = at;
                    const QByteArray json = f.readAll();
                    const QVariantList parsed = parseLimits(json);
                    const QString model = parseModel(json);
                    if (parsed != m_limits.value(session) || model != m_models.value(session)) {
                        m_limits[session] = parsed;
                        m_models[session] = model;
                        limitsMoved = true;
                    }
                }
            }
        }
        bool pending = false;
        for (const QFileInfo &f : dir.entryInfoList({QStringLiteral("*.prompt")}, QDir::Files)) {
            const QString receipt = dir.filePath(f.completeBaseName() + QStringLiteral(".taken"));
            if (QFile::exists(receipt)) {
                QFile::remove(f.filePath());
                QFile::remove(receipt);
                took.append(session);
            } else if (now - f.lastModified().toMSecsSinceEpoch() > kStaleMs) {
                QFile::remove(f.filePath()); // (never delivered: it must not arrive out of the blue later)
            } else {
                pending = true;
            }
        }
        if (pending)
            waiting.append(session);
    }
    if (live != m_live || waiting != m_waiting || limitsMoved) {
        m_live = live;
        m_waiting = waiting;
        emit changed();
    }
    for (const QString &session : std::as_const(took))
        emit taken(session);
    for (const auto &r : std::as_const(said))
        emit reply(r.first, r.second);
}

} // namespace kisel
