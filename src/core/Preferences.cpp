#include "Preferences.h"

#include "Paths.h"

namespace kisel {

Preferences::Preferences(QObject *parent)
    : QObject(parent)
    , m_s(paths::configDir() + QStringLiteral("/kisel.conf"), QSettings::IniFormat)
{
}

void Preferences::set(const char *key, const QVariant &v)
{
    if (m_s.value(key) == v)
        return;
    m_s.setValue(key, v);
    emit changed();
}

void Preferences::addAlwaysRule(const QString &key)
{
    QStringList rules = alwaysRules();
    if (rules.contains(key))
        return;
    rules.append(key);
    m_s.setValue("alwaysRules", rules);
    emit changed();
}

void Preferences::clearAlwaysRules()
{
    m_s.remove("alwaysRules");
    emit changed();
}

} // namespace kisel
