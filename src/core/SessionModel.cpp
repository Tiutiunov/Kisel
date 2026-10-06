#include "SessionModel.h"

#include <QFileInfo>

namespace kisel {

QVariantMap Session::toVariant() const
{
    QVariantList stepList;
    for (const Step &s : steps)
        stepList.append(QVariantMap {{"text", s.text}, {"state", s.state}});
    return {
        {"id", id}, {"agent", agent}, {"cwd", cwd}, {"name", name}, {"state", state},
        {"line", line}, {"prompt", prompt}, {"steps", stepList}, {"file", file},
        {"diff", diff}, {"added", added}, {"removed", removed}, {"command", command},
    };
}

QVariant SessionModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const Session &s = m_items.at(index.row());
    switch (role) {
    case IdRole: return s.id;
    case NameRole: return s.name;
    case AgentRole: return s.agent;
    case StateRole: return s.state;
    case LineRole: return s.line;
    case CwdRole: return s.cwd;
    }
    return {};
}

QHash<int, QByteArray> SessionModel::roleNames() const
{
    return {{IdRole, "id"}, {NameRole, "name"}, {AgentRole, "agent"},
            {StateRole, "state"}, {LineRole, "line"}, {CwdRole, "cwd"}};
}

int SessionModel::rowOf(const QString &id) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).id == id)
            return i;
    return -1;
}

Session *SessionModel::find(const QString &id)
{
    const int r = rowOf(id);
    return r < 0 ? nullptr : &m_items[r];
}

Session &SessionModel::ensure(const QString &id, const QString &agent, const QString &cwd)
{
    if (Session *s = find(id)) {
        if (!cwd.isEmpty() && s->cwd != cwd) {
            s->cwd = cwd;
            s->name = QFileInfo(cwd).fileName();
        }
        return *s;
    }
    beginInsertRows({}, int(m_items.size()), int(m_items.size()));
    Session s;
    s.id = id;
    s.agent = agent;
    s.cwd = cwd;
    s.name = cwd.isEmpty() ? id.left(8) : QFileInfo(cwd).fileName();
    s.updated = QDateTime::currentDateTime();
    m_items.append(s);
    endInsertRows();
    return m_items.last();
}

void SessionModel::touched(const QString &id)
{
    const int r = rowOf(id);
    if (r < 0)
        return;
    m_items[r].updated = QDateTime::currentDateTime();
    emit dataChanged(index(r), index(r));
}

void SessionModel::remove(const QString &id)
{
    const int r = rowOf(id);
    if (r < 0)
        return;
    beginRemoveRows({}, r, r);
    m_items.removeAt(r);
    endRemoveRows();
}

const Session *SessionModel::latest() const
{
    const Session *best = nullptr;
    for (const Session &s : m_items)
        if (!best || s.updated >= best->updated)
            best = &s;
    return best;
}

} // namespace kisel
