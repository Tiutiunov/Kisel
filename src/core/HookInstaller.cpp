#include "HookInstaller.h"

#include "Paths.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLibraryInfo>
#include <QSaveFile>

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
    emit changed();
    return true;
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
