#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariantList>

namespace kisel {

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
    Q_PROPERTY(QString settingsPath READ settingsPath CONSTANT)

public:
    explicit HookInstaller(QObject *parent = nullptr);

    bool installed() const;
    QString settingsPath() const;

    // {ok, error, backup, diff: [{kind: add|del|ctx, text}], changed}
    Q_INVOKABLE QVariantMap preview(bool install) const;
    Q_INVOKABLE bool apply(bool install);

    // Copies the bundled relay to ~/.local/share/kisel/bin so settings.json
    // never points into a build tree. Returns false if it cannot.
    bool ensureRelay(const QString &bundledPath) const;

    // Pure functions, unit-tested.
    static QJsonObject merge(const QJsonObject &settings, const QString &command, bool install);
    static QVariantList lineDiff(const QString &before, const QString &after);

signals:
    void changed();

private:
    struct Plan {
        bool ok = false;
        QString error, before, after;
    };
    Plan plan(bool install) const;
};

} // namespace kisel
