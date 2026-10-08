#pragma once

#include <QObject>
#include <QProcess>
#include <QHash>
#include <QStringList>

namespace kisel {

// Installs Kisel's two Claude Code plugins ("mods") for the user: kisel-prompts, which
// joins a session to Kisel's chat (see PromptRelay), and cache-band. They ship with
// Kisel, in <install>/mods, which is a Claude Code marketplace of its own.
//
// Kisel never edits Claude Code's files for this. It runs Claude Code's own command
// line, the same three commands a person would type, and only on a click:
//
//   claude plugin marketplace add <install>/mods
//   claude plugin install kisel-prompts@kisel --scope user
//   claude plugin install cache-band@kisel --scope user
//
// `commands` is that list as shown in Settings before the click. The plugins load in
// sessions started afterwards.
class ModInstaller : public QObject
{
    Q_OBJECT
    // checking | noclaude (no `claude` to run) | nomods (this build ships none) | none |
    // partial | installed | outdated (Claude Code keeps an older copy than this Kisel ships) |
    // working | failed
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)       // the last line of a failed command
    Q_PROPERTY(QStringList commands READ commands CONSTANT)

public:
    explicit ModInstaller(const QString &modsDir, QObject *parent = nullptr);

    QString state() const { return m_state; }
    QString detail() const { return m_detail; }
    QStringList commands() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install();
    Q_INVOKABLE void remove();
    // Claude Code keeps its own copy of an installed plugin, taken when it was installed:
    // a newer Kisel brings newer mods, and this hands them over.
    Q_INVOKABLE void update();

    // Pure, unit-tested: what `claude plugin list --json` says about our two.
    // (`shipped`: the version of each that this Kisel carries; none given, versions are not compared)
    static QString stateFromList(const QByteArray &json, const QHash<QString, QString> &shipped = {});
    QHash<QString, QString> shipped() const;
    static const QStringList &names();

signals:
    void changed();

private:
    void set(const QString &state, const QString &detail = QString());
    void run(const QList<QStringList> &steps, bool thenRefresh);
    void next();

    QString m_dir, m_state = QStringLiteral("checking"), m_detail;
    QProcess m_proc;
    QList<QStringList> m_steps;
    bool m_listing = false, m_tolerant = false;
};

} // namespace kisel
