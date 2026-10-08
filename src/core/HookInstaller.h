#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariantList>

class QFileSystemWatcher;
class QTimer;

namespace kisel {

class Preferences;

// Installs and removes Kisel's entries in Claude Code's settings.json.
//
// Rules (from the design brief): never overwrite the file blindly. preview()
// computes the exact diff and the backup path without touching anything;
// apply() takes a dated backup first and then writes. Entries that are not
// ours are never changed. Ours are recognised by the relay's file name.
//
// Known limitation: QJsonObject keeps keys sorted, so the first write may
// reorder keys in the user's file. The diff shown to the user is computed on
// the real before/after text, so that is visible before they confirm.
class HookInstaller : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installed READ installed NOTIFY changed)
    // none: no hooks of ours. ok: all of them, pointing at a relay that exists.
    // stale: some, or a wrong path (an update moved the relay, an event is missing).
    // unreadable: settings.json is not valid JSON; Kisel never touches such a file.
    Q_PROPERTY(QString health READ health NOTIFY changed)
    Q_PROPERTY(QString settingsPath READ settingsPath CONSTANT)

public:
    explicit HookInstaller(QObject *parent = nullptr);

    bool installed() const;
    QString health() const;
    QString settingsPath() const;

    // {ok, error, backup, diff: [{kind: add|del|ctx, text}], changed}
    Q_INVOKABLE QVariantMap preview(bool install) const;
    Q_INVOKABLE bool apply(bool install);

    // Copies the bundled relay to ~/.local/share/kisel/bin so settings.json
    // never points into a build tree. Returns false if it cannot.
    bool ensureRelay(const QString &bundledPath) const;

    // Keeps an eye on settings.json (on a change, and every few minutes) and acts on
    // Preferences::hookWatch. Nothing is ever written here without either the user's click
    // or, in "auto" mode, hooks that were there before and only need repairing.
    void watch(Preferences *prefs, const QString &bundledRelay);

    // Pure functions, unit-tested.
    static QString health(const QJsonObject &settings, const QString &command);
    static QJsonObject merge(const QJsonObject &settings, const QString &command, bool install);
    static QVariantList lineDiff(const QString &before, const QString &after);

signals:
    void changed();
    // The hooks need the user: state is "none" or "stale". Shown once per state per run.
    void attention(const QString &state);
    // "auto" mode repaired stale hooks (a backup was taken first).
    void repaired();

private:
    void rewatch();
    void recheck();
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_debounce = nullptr;
    Preferences *m_prefs = nullptr;
    QString m_bundled, m_notified;
    struct Plan {
        bool ok = false;
        QString error, before, after;
    };
    Plan plan(bool install) const;
};

} // namespace kisel
