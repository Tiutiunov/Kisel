#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QVariantList>
#include <QVariantMap>

namespace kisel {

struct Step {
    QString text;
    QString state; // running | done | failed
};

// One agent session as the island shows it.
struct Session {
    QString id;
    QString agent = QStringLiteral("claude-code");
    QString cwd;
    QString name;  // basename of cwd
    QString state = QStringLiteral("idle"); // idle | think | work | done | failed
    QString line;  // one-line status for tiles
    QString prompt;
    QList<Step> steps;
    QString file;                 // file in the code panel
    QVariantList diff;            // [{kind: add|del|ctx, no, text}]
    int added = 0;
    int removed = 0;
    QString command;              // last shell command
    QDateTime updated;

    QVariantMap toVariant() const;
};

class SessionModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles { IdRole = Qt::UserRole + 1, NameRole, AgentRole, StateRole, LineRole, CwdRole };

    explicit SessionModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_items.size()); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Session *find(const QString &id);
    Session &ensure(const QString &id, const QString &agent, const QString &cwd);
    void touched(const QString &id); // announce a change made through find()
    void remove(const QString &id);
    const QList<Session> &items() const { return m_items; }
    // Most recently updated session, or nullptr.
    const Session *latest() const;

private:
    int rowOf(const QString &id) const;
    QList<Session> m_items;
};

} // namespace kisel
