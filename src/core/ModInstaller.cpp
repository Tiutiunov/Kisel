#include "ModInstaller.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace kisel {

namespace {
const QString kMarket = QStringLiteral("kisel");
}

const QStringList &ModInstaller::names()
{
    static const QStringList n {QStringLiteral("kisel-prompts")};
    return n;
}

QStringList ModInstaller::retiredIn(const QByteArray &json)
{
    static const QStringList gone {QStringLiteral("cache-band")};
    const QJsonDocument doc = QJsonDocument::fromJson(json.mid(qMax(0, int(json.indexOf('[')))));
    QStringList found;
    for (const QJsonValue &v : doc.array())
        for (const QString &n : gone)
            if (v.toObject().value("id").toString() == n + QLatin1Char('@') + kMarket)
                found.append(n);
    return found;
}

void ModInstaller::retire()
{
    if (m_proc.state() != QProcess::NotRunning || QStandardPaths::findExecutable(QStringLiteral("claude")).isEmpty())
        return;
    m_retiring = true;
    m_listing = true;
    m_steps = {{QStringLiteral("plugin"), QStringLiteral("list"), QStringLiteral("--json")}};
    next();
}

ModInstaller::ModInstaller(const QString &modsDir, QObject *parent)
    : QObject(parent), m_dir(QDir::toNativeSeparators(QDir::cleanPath(modsDir)))
{
    m_proc.setProcessChannelMode(QProcess::MergedChannels);
    connect(&m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const QByteArray out = m_proc.readAll();
        if (m_listing && m_retiring) {
            m_listing = false;
            m_retiring = false;
            m_steps.clear();
            if (status == QProcess::NormalExit && code == 0)
                for (const QString &n : retiredIn(out))
                    m_steps.append({QStringLiteral("plugin"), QStringLiteral("uninstall"), n + QLatin1Char('@') + kMarket});
            next(); // (quietly: nothing in Settings changes for it)
            return;
        }
        if (m_listing) {
            m_listing = false;
            set(status == QProcess::NormalExit && code == 0 ? stateFromList(out, shipped()) : QStringLiteral("noclaude"));
            return;
        }
        // (adding a marketplace that is there already is not a failure: `m_tolerant`)
        if ((status != QProcess::NormalExit || code != 0) && !m_tolerant) {
            m_steps.clear();
            const QList<QByteArray> lines = out.trimmed().split('\n');
            set(QStringLiteral("failed"), QString::fromUtf8(lines.isEmpty() ? QByteArray() : lines.last()).trimmed().left(160));
            return;
        }
        next();
    });
    connect(&m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        m_steps.clear();
        m_listing = false;
        if (m_retiring) {
            m_retiring = false;
            return;
        }
        set(QStringLiteral("noclaude"));
    });
}

QStringList ModInstaller::commands() const
{
    QStringList c {QStringLiteral("claude plugin marketplace add \"%1\"").arg(m_dir)};
    for (const QString &n : names())
        c.append(QStringLiteral("claude plugin install %1@%2 --scope user").arg(n, kMarket));
    return c;
}

QHash<QString, QString> ModInstaller::shipped() const
{
    QHash<QString, QString> v;
    for (const QString &n : names()) {
        QFile f(m_dir + QLatin1Char('/') + n + QStringLiteral("/.claude-plugin/plugin.json"));
        if (f.open(QIODevice::ReadOnly))
            v.insert(n, QJsonDocument::fromJson(f.readAll()).object().value("version").toString());
    }
    return v;
}

QString ModInstaller::stateFromList(const QByteArray &json, const QHash<QString, QString> &shipped)
{
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json.mid(qMax(0, int(json.indexOf('[')))), &err);
    if (!doc.isArray())
        return QStringLiteral("none"); // (nothing installed prints no list at all)
    int have = 0;
    bool old = false;
    for (const QString &n : names()) {
        const QString id = n + QLatin1Char('@') + kMarket;
        for (const QJsonValue &v : doc.array())
            if (v.toObject().value("id").toString() == id && v.toObject().value("enabled").toBool(true)) {
                ++have;
                const QString want = shipped.value(n);
                if (!want.isEmpty() && v.toObject().value("version").toString() != want)
                    old = true;
                break;
            }
    }
    if (have == names().size())
        return old ? QStringLiteral("outdated") : QStringLiteral("installed");
    return have > 0 ? QStringLiteral("partial") : QStringLiteral("none");
}

void ModInstaller::set(const QString &state, const QString &detail)
{
    if (state == m_state && detail == m_detail)
        return;
    m_state = state;
    m_detail = detail;
    emit changed();
}

void ModInstaller::refresh()
{
    if (m_proc.state() != QProcess::NotRunning)
        return;
    if (!QFileInfo::exists(m_dir + QStringLiteral("/.claude-plugin/marketplace.json"))) {
        set(QStringLiteral("nomods"));
        return;
    }
    if (QStandardPaths::findExecutable(QStringLiteral("claude")).isEmpty()) {
        set(QStringLiteral("noclaude"));
        return;
    }
    m_listing = true;
    m_steps = {{QStringLiteral("plugin"), QStringLiteral("list"), QStringLiteral("--json")}};
    next();
}

void ModInstaller::run(const QList<QStringList> &steps, bool)
{
    if (m_proc.state() != QProcess::NotRunning)
        return;
    m_steps = steps;
    set(QStringLiteral("working"));
    next();
}

void ModInstaller::next()
{
    if (m_steps.isEmpty()) {
        if (m_state == QLatin1String("working")) {
            m_state = QStringLiteral("checking"); // (and see what came of it)
            refresh();
        }
        return;
    }
    const QStringList args = m_steps.takeFirst();
    m_tolerant = args.contains(QStringLiteral("marketplace")) || args.contains(QStringLiteral("update"))
              || (args.contains(QStringLiteral("uninstall")) && m_state != QLatin1String("working")); // (a retiring that fails is let be)
#ifdef Q_OS_WIN
    // (npm installs `claude` as a .cmd: that is run by the command interpreter, not by itself)
    m_proc.start(QStringLiteral("cmd.exe"), QStringList {QStringLiteral("/c"), QStringLiteral("claude")} + args);
#else
    m_proc.start(QStringLiteral("claude"), args);
#endif
}

void ModInstaller::install()
{
    QList<QStringList> steps {{QStringLiteral("plugin"), QStringLiteral("marketplace"), QStringLiteral("add"), m_dir}};
    for (const QString &n : names())
        steps.append({QStringLiteral("plugin"), QStringLiteral("install"), n + QLatin1Char('@') + kMarket, QStringLiteral("--scope"), QStringLiteral("user")});
    run(steps, true);
}

void ModInstaller::update()
{
    QList<QStringList> steps {{QStringLiteral("plugin"), QStringLiteral("marketplace"), QStringLiteral("update"), kMarket}};
    for (const QString &n : names())
        steps.append({QStringLiteral("plugin"), QStringLiteral("update"), n + QLatin1Char('@') + kMarket});
    run(steps, true);
}

void ModInstaller::remove()
{
    QList<QStringList> steps;
    for (const QString &n : names())
        steps.append({QStringLiteral("plugin"), QStringLiteral("uninstall"), n + QLatin1Char('@') + kMarket});
    run(steps, true);
}

} // namespace kisel
