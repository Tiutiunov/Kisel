#include "HookInstaller.h"

#include "Paths.h"
#include "Preferences.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLibraryInfo>
#include <QSaveFile>
#include <QTimer>

namespace kisel {

namespace {
// Events Kisel listens to. PermissionRequest is the only one that waits.
const QStringList kEvents = {"SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse",
                             "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Stop"};

bool isOurs(const QJsonObject &group)
{
    for (const QJsonValue &h : group.value("hooks").toArray())
        if (h.toObject().value("command").toString().contains(QStringLiteral(KISEL_HOOK_BASENAME)))
            return true;
    return false;
}

QString quoted(const QString &p) { return p.contains(' ') ? '"' + p + '"' : p; }

QString pretty(const QJsonObject &o) { return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Indented)); }
} // namespace

HookInstaller::HookInstaller(QObject *parent) : QObject(parent) {}

QString HookInstaller::settingsPath() const { return paths::claudeSettings(); }

bool HookInstaller::installed() const
{
    QFile f(settingsPath());
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QJsonObject hooks = QJsonDocument::fromJson(f.readAll()).object().value("hooks").toObject();
    for (const QString &ev : kEvents)
        for (const QJsonValue &g : hooks.value(ev).toArray())
            if (isOurs(g.toObject()))
                return true;
    return false;
}

QString HookInstaller::health(const QJsonObject &settings, const QString &command)
{
    const QJsonObject hooks = settings.value("hooks").toObject();
    int ours = 0;
    bool whole = true;
    for (const QString &ev : kEvents) {
        int here = 0;
        for (const QJsonValue &g : hooks.value(ev).toArray()) {
            if (!isOurs(g.toObject()))
                continue;
            ++here;
            for (const QJsonValue &h : g.toObject().value("hooks").toArray())
                if (h.toObject().value("command").toString().contains(QStringLiteral(KISEL_HOOK_BASENAME))
                    && h.toObject().value("command").toString() != command)
                    whole = false; // an old path
        }
        ours += here;
        if (here != 1)
            whole = false; // an event without us, or twice
    }
    // (an entry under an event we do not use is still ours: it is stale, not absent)
    for (const QString &ev : hooks.keys())
        if (!kEvents.contains(ev))
            for (const QJsonValue &g : hooks.value(ev).toArray())
                if (isOurs(g.toObject())) {
                    ++ours;
                    whole = false;
                }
    if (ours == 0)
        return QStringLiteral("none");
    return whole ? QStringLiteral("ok") : QStringLiteral("stale");
}

QString HookInstaller::health() const
{
    QFile f(settingsPath());
    if (!f.exists())
        return QStringLiteral("none");
    if (!f.open(QIODevice::ReadOnly))
        return QStringLiteral("unreadable");
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QStringLiteral("unreadable");
    const QString h = health(doc.object(), quoted(paths::hookBinary()));
    return h == QLatin1String("ok") && !QFile::exists(paths::hookBinary()) ? QStringLiteral("stale") : h;
}

QJsonObject HookInstaller::merge(const QJsonObject &settings, const QString &command, bool install)
{
    QJsonObject out = settings;
    QJsonObject hooks = out.value("hooks").toObject();

    // Drop every entry of ours first, so install is idempotent and also
    // repairs a stale path.
    for (const QString &ev : hooks.keys()) {
        QJsonArray kept;
        for (const QJsonValue &g : hooks.value(ev).toArray())
            if (!isOurs(g.toObject()))
                kept.append(g);
        if (kept.isEmpty())
            hooks.remove(ev);
        else
            hooks[ev] = kept;
    }

    if (install) {
        for (const QString &ev : kEvents) {
            QJsonObject entry {{"type", "command"}, {"command", command}};
            // A permission card may stay on screen for a while; everything
            // else must be quick.
            entry["timeout"] = ev == QLatin1String("PermissionRequest") ? 120 : 5;
            QJsonObject group {{"matcher", "*"}, {"hooks", QJsonArray {entry}}};
            QJsonArray arr = hooks.value(ev).toArray();
            arr.append(group);
            hooks[ev] = arr;
        }
    }

    if (hooks.isEmpty())
        out.remove("hooks");
    else
        out["hooks"] = hooks;
    return out;
}

HookInstaller::Plan HookInstaller::plan(bool install) const
{
    Plan p;
    QJsonObject current;
    QFile f(settingsPath());
    if (f.exists()) {
        if (!f.open(QIODevice::ReadOnly)) {
            p.error = QStringLiteral("Cannot read %1").arg(settingsPath());
            return p;
        }
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            // Never touch a file we cannot parse.
            p.error = QStringLiteral("settings.json is not valid JSON (%1); Kisel will not change it").arg(err.errorString());
            return p;
        }
        current = doc.object();
    }
    p.before = pretty(current);
    p.after = pretty(merge(current, quoted(paths::hookBinary()), install));
    p.ok = true;
    return p;
}

QVariantMap HookInstaller::preview(bool install) const
{
    const Plan p = plan(install);
    if (!p.ok)
        return {{"ok", false}, {"error", p.error}};
    return {{"ok", true}, {"changed", p.before != p.after},
            {"diff", lineDiff(p.before, p.after)},
            {"path", settingsPath()},
            {"backup", settingsPath() + QStringLiteral(".kisel-") + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss") + ".bak"}};
}

bool HookInstaller::apply(bool install)
{
    const Plan p = plan(install);
    if (!p.ok)
        return false;
    if (p.before == p.after)
        return true;

    const QString path = settingsPath();
    QDir().mkpath(QFileInfo(path).path());
    if (QFile::exists(path)) {
        const QString backup = path + QStringLiteral(".kisel-") + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss") + ".bak";
        if (!QFile::copy(path, backup))
            return false; // no backup, no write
    }
    QSaveFile out(path); // atomic: temp file + rename
    if (!out.open(QIODevice::WriteOnly))
        return false;
    out.write(p.after.toUtf8());
    if (!out.commit())
        return false;
    if (m_prefs)
        m_prefs->setHookRemoved(!install);
    emit changed();
    return true;
}

void HookInstaller::watch(Preferences *prefs, const QString &bundledRelay)
{
    m_prefs = prefs;
    m_bundled = bundledRelay;
    m_watcher = new QFileSystemWatcher(this);
    m_debounce = new QTimer(this);
    m_debounce->setSingleShot(true);
    m_debounce->setInterval(1500); // editors write a file in several steps
    connect(m_debounce, &QTimer::timeout, this, &HookInstaller::recheck);
    auto later = [this] { rewatch(); m_debounce->start(); };
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, later);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, later);
    connect(prefs, &Preferences::changed, this, [this] { m_debounce->start(); });
    auto *poll = new QTimer(this); // for the cases a watcher misses (network drives, a replaced folder)
    poll->setInterval(10 * 60 * 1000);
    connect(poll, &QTimer::timeout, this, &HookInstaller::recheck);
    poll->start();
    rewatch();
    QTimer::singleShot(4000, this, &HookInstaller::recheck); // after the window is up, so the toast is seen
}

void HookInstaller::rewatch()
{
    const QString file = settingsPath();
    const QString dir = QFileInfo(file).path();
    if (QFileInfo::exists(file) && !m_watcher->files().contains(file))
        m_watcher->addPath(file); // (an atomic save replaces the file: it has to be added again)
    if (QFileInfo(dir).isDir() && !m_watcher->directories().contains(dir))
        m_watcher->addPath(dir);
}

void HookInstaller::recheck()
{
    emit changed(); // the health shown in Settings may have moved
    if (!m_prefs || m_prefs->hookWatch() == QLatin1String("off"))
        return;
    if (!QFile::exists(paths::hookBinary()))
        ensureRelay(m_bundled); // the usual cause of a stale path: put the relay back first
    const QString h = health();
    if (h == QLatin1String("ok") || h == QLatin1String("unreadable")) {
        m_notified.clear();
        return;
    }
    if (h == QLatin1String("stale") && m_prefs->hookWatch() == QLatin1String("auto") && apply(true)) {
        m_notified.clear();
        emit repaired();
        return;
    }
    // Hooks that are gone are news only to someone who had them working (a session has
    // come through them at least once) and did not take them out. Someone who never
    // connected Claude Code has the Connect button on Home, and is not told at every start.
    if (h == QLatin1String("none")
        && (m_prefs->hookWatch() != QLatin1String("ask") || m_prefs->hookRemoved() || !m_prefs->hookSeen()))
        return;
    if (m_notified == h)
        return;
    m_notified = h;
    emit attention(h);
}

bool HookInstaller::ensureRelay(const QString &bundledPath) const
{
    if (!QFile::exists(bundledPath))
        return false;
    const QString dest = paths::hookBinary();
    QDir().mkpath(QFileInfo(dest).path());
#ifdef Q_OS_WIN
    // No system Qt here: the relay needs its one library next to it.
    // (In a build tree it is not next to the app either, but in Qt's own bin.)
#ifdef QT_DEBUG
    const QString dll = QStringLiteral("Qt6Cored.dll");
#else
    const QString dll = QStringLiteral("Qt6Core.dll");
#endif
    QDir from = QFileInfo(bundledPath).dir();
    if (!from.exists(dll))
        from.setPath(QLibraryInfo::path(QLibraryInfo::BinariesPath));
    const QString to = QFileInfo(dest).path() + QLatin1Char('/') + dll;
    if (QFileInfo(to).size() != QFileInfo(from.filePath(dll)).size()) {
        QFile::remove(to);
        if (!QFile::copy(from.filePath(dll), to))
            return false;
    }
#endif
    // Replace only when different, and via rename so a running hook is never cut.
    QFile src(bundledPath);
    QFile cur(dest);
    if (cur.exists() && cur.size() == src.size() && QFileInfo(dest).lastModified() >= QFileInfo(bundledPath).lastModified())
        return true;
    const QString tmp = dest + QStringLiteral(".new");
    QFile::remove(tmp);
    if (!QFile::copy(bundledPath, tmp))
        return false;
    QFile::setPermissions(tmp, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QFile::remove(dest);
    return QFile::rename(tmp, dest);
}

// Plain LCS line diff with two lines of context. Settings files are tiny.
QVariantList HookInstaller::lineDiff(const QString &before, const QString &after)
{
    const QStringList a = before.split('\n'), b = after.split('\n');
    const int n = int(a.size()), m = int(b.size());
    QList<QList<int>> L(n + 1, QList<int>(m + 1, 0));
    for (int i = n - 1; i >= 0; --i)
        for (int j = m - 1; j >= 0; --j)
            L[i][j] = a[i] == b[j] ? L[i + 1][j + 1] + 1 : qMax(L[i + 1][j], L[i][j + 1]);

    struct Row { QString kind, text; };
    QList<Row> rows;
    int i = 0, j = 0;
    while (i < n && j < m) {
        if (a[i] == b[j]) { rows.append({"ctx", a[i]}); ++i; ++j; }
        else if (L[i + 1][j] >= L[i][j + 1]) rows.append({"del", a[i++]});
        else rows.append({"add", b[j++]});
    }
    while (i < n) rows.append({"del", a[i++]});
    while (j < m) rows.append({"add", b[j++]});

    QVariantList out;
    QList<bool> keep(rows.size(), false);
    for (int r = 0; r < rows.size(); ++r)
        if (rows[r].kind != "ctx")
            for (int k = qMax(0, r - 2); k <= qMin(int(rows.size()) - 1, r + 2); ++k)
                keep[k] = true;
    for (int r = 0; r < rows.size(); ++r)
        if (keep[r])
            out.append(QVariantMap {{"kind", rows[r].kind}, {"no", r + 1}, {"text", rows[r].text}});
    return out;
}

} // namespace kisel
