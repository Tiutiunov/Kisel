#pragma once

#include <QObject>
#include <QSettings>
#include <QStringList>

namespace kisel {

// User preferences, persisted in ~/.config/kisel/kisel.conf. Nothing secret
// lives here (keys go through Secrets).
class Preferences : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool soundOn READ soundOn WRITE setSoundOn NOTIFY changed)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY changed)
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY changed) // system | dark | light
    Q_PROPERTY(QString model READ model WRITE setModel NOTIFY changed)
    Q_PROPERTY(bool firstRunDone READ firstRunDone WRITE setFirstRunDone NOTIFY changed)
    Q_PROPERTY(QString screenName READ screenName WRITE setScreenName NOTIFY changed)
    Q_PROPERTY(bool floating READ floating WRITE setFloating NOTIFY changed)
    Q_PROPERTY(qreal floatX READ floatX WRITE setFloatX NOTIFY changed)
    Q_PROPERTY(qreal floatY READ floatY WRITE setFloatY NOTIFY changed)
    Q_PROPERTY(bool hookSeen READ hookSeen NOTIFY changed)
    Q_PROPERTY(int alwaysCount READ alwaysCount NOTIFY changed)

public:
    explicit Preferences(QObject *parent = nullptr);

    bool soundOn() const { return m_s.value("soundOn", true).toBool(); }
    bool reduceMotion() const { return m_s.value("reduceMotion", false).toBool(); }
    QString theme() const { return m_s.value("theme", "system").toString(); }
    QString model() const { return m_s.value("model", "claude-sonnet-5-5").toString(); }
    QString screenName() const { return m_s.value("screenName").toString(); } // "" = primary
    bool floating() const { return m_s.value("floating", false).toBool(); }
    qreal floatX() const { return m_s.value("floatX", 0).toReal(); }
    qreal floatY() const { return m_s.value("floatY", 0).toReal(); }
    bool hookSeen() const { return m_s.value("hookSeen", false).toBool(); } // a hook event has reached Kisel once
    bool firstRunDone() const { return m_s.value("firstRunDone", false).toBool(); }

    void setSoundOn(bool v) { set("soundOn", v); }
    void setReduceMotion(bool v) { set("reduceMotion", v); }
    void setTheme(const QString &v) { set("theme", v); }
    void setModel(const QString &v) { set("model", v); }
    void setScreenName(const QString &v) { set("screenName", v); }
    void setFloating(bool v) { set("floating", v); }
    void setFloatX(qreal v) { set("floatX", v); }
    void setFloatY(qreal v) { set("floatY", v); }
    void setHookSeen(bool v) { set("hookSeen", v); }
    void setFirstRunDone(bool v) { set("firstRunDone", v); }

    // Where Kisel docks on each monitor (remembered per output name): the edge and the
    // position along it as a fraction 0..1, so it survives a change of resolution.
    Q_INVOKABLE QString dockEdge(const QString &screen) const { return m_s.value(QStringLiteral("dock/%1/edge").arg(screen), "top").toString(); }
    Q_INVOKABLE qreal dockFraction(const QString &screen) const { return m_s.value(QStringLiteral("dock/%1/frac").arg(screen), 0.5).toReal(); }
    Q_INVOKABLE void setDock(const QString &screen, const QString &edge, qreal fraction)
    {
        m_s.setValue(QStringLiteral("dock/%1/edge").arg(screen), edge);
        m_s.setValue(QStringLiteral("dock/%1/frac").arg(screen), fraction);
    }

    // "Always" answers the user gave to permission cards. Each is an explicit
    // click on a specific pattern (see AgentHub::ruleKey).
    QStringList alwaysRules() const { return m_s.value("alwaysRules").toStringList(); }
    int alwaysCount() const { return alwaysRules().size(); }
    void addAlwaysRule(const QString &key);
    Q_INVOKABLE void clearAlwaysRules();

signals:
    void changed();

private:
    void set(const char *key, const QVariant &v);
    QSettings m_s;
};

} // namespace kisel
