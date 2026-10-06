#pragma once

#include <QObject>
#include <QString>

namespace kisel {

// API keys live in KWallet, or in the Credential Manager on Windows (Secret
// Service on other desktops is a later backend behind this same interface).
// Never on disk, never in QML: the UI can only ask whether a key exists, and
// ChatClient reads it at send time.
// Without either at build time, only the ANTHROPIC_API_KEY environment
// variable is honoured (read-only).
class Secrets : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString storeName READ storeName CONSTANT) // what the UI calls the place keys go
public:
    explicit Secrets(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE bool has(const QString &name);
    Q_INVOKABLE bool store(const QString &name, const QString &value);
    Q_INVOKABLE bool remove(const QString &name);
    QString read(const QString &name);
    QString storeName() const;

    static constexpr auto kAnthropic = "anthropic";

signals:
    void changed();
};

} // namespace kisel
