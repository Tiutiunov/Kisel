#pragma once

#include <QObject>
#include <QSettings>
#include <QStringList>
#include <QVariantMap>

namespace kisel {

// User preferences, persisted in ~/.config/kisel/kisel.conf. Nothing secret
// lives here (keys go through Secrets).
class Preferences : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool soundOn READ soundOn WRITE setSoundOn NOTIFY changed)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY changed)
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY changed) // system | dark | light
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY changed) // en | ru (English unless Russian is picked)
    Q_PROPERTY(bool updateCheck READ updateCheck WRITE setUpdateCheck NOTIFY changed) // ask GitHub for a newer version at start and once a day
    Q_PROPERTY(QString updateSeen READ updateSeen WRITE setUpdateSeen NOTIFY changed) // the version Rin has already been clicked about
    Q_PROPERTY(QString model READ model WRITE setModel NOTIFY changed)
    Q_PROPERTY(bool firstRunDone READ firstRunDone WRITE setFirstRunDone NOTIFY changed)
    Q_PROPERTY(QString screenName READ screenName WRITE setScreenName NOTIFY changed)
    Q_PROPERTY(bool floating READ floating WRITE setFloating NOTIFY changed)
    Q_PROPERTY(qreal floatX READ floatX WRITE setFloatX NOTIFY changed)
    Q_PROPERTY(qreal floatY READ floatY WRITE setFloatY NOTIFY changed)
    Q_PROPERTY(bool avoidPanels READ avoidPanels WRITE setAvoidPanels NOTIFY changed)
    Q_PROPERTY(int closeDelay READ closeDelay WRITE setCloseDelay NOTIFY changed)
    // What each character is tied to. The first: Zundamon shows and steers Spotify.
    Q_PROPERTY(bool zundaSpotify READ zundaSpotify WRITE setZundaSpotify NOTIFY changed)
    Q_PROPERTY(bool tetoSystem READ tetoSystem WRITE setTetoSystem NOTIFY changed) // Teto watches the computer
    Q_PROPERTY(bool rinNotes READ rinNotes WRITE setRinNotes NOTIFY changed)       // Rin announces notifications
    Q_PROPERTY(bool lukaNet READ lukaNet WRITE setLukaNet NOTIFY changed)          // Luka watches the connection
    Q_PROPERTY(QString character READ character WRITE setCharacter NOTIFY changed) // miku | rin | luka | zunda | teto
    // Who has which job. The jobs are known by the one who had them first: "miku" is Claude
    // Code, "rin" the notifications, "luka" the connection, "zunda" the music, "teto" the
    // computer. `faces` says who does each now, job -> character; always all five, each once.
    Q_PROPERTY(QVariantMap faces READ faces NOTIFY changed)
    Q_PROPERTY(bool hookSeen READ hookSeen NOTIFY changed)
    // What Kisel does when Claude Code's hooks are missing or broken: ask | auto | off
    Q_PROPERTY(QString hookWatch READ hookWatch WRITE setHookWatch NOTIFY changed)
    Q_PROPERTY(int alwaysCount READ alwaysCount NOTIFY changed)
    // Discord (see DiscordPresence): off unless asked for; the Application ID is public, not a secret
    Q_PROPERTY(bool discordOn READ discordOn WRITE setDiscordOn NOTIFY changed)
    Q_PROPERTY(bool discordProject READ discordProject WRITE setDiscordProject NOTIFY changed) // the session's name too
    Q_PROPERTY(QString discordAppId READ discordAppId WRITE setDiscordAppId NOTIFY changed)

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
    // Keep to the part of the screen the taskbar leaves free (where the platform has one).
    bool avoidPanels() const { return m_s.value("avoidPanels", true).toBool(); }
    // Seconds an open card waits after the pointer has left it: 0 (at once) to 10.
    int closeDelay() const { return qBound(0, m_s.value("closeDelay", 3).toInt(), 10); }
    QString character() const
    {
        const QString c = m_s.value("character", "miku").toString();
        return c == QLatin1String("gumi") ? QStringLiteral("zunda") : c; // Zundamon took GUMI's place
    }
    bool zundaSpotify() const { return m_s.value("zundaSpotify", m_s.value("gumiSpotify", true)).toBool(); }
    bool hookSeen() const { return m_s.value("hookSeen", false).toBool(); } // a hook event has reached Kisel once
    bool firstRunDone() const { return m_s.value("firstRunDone", false).toBool(); }

    void setSoundOn(bool v) { set("soundOn", v); }
    void setReduceMotion(bool v) { set("reduceMotion", v); }
    void setTheme(const QString &v) { set("theme", v); }
    QString language() const { return m_s.value("language", "en").toString(); }
    void setLanguage(const QString &v) { set("language", v); }
    bool updateCheck() const { return m_s.value("updateCheck", true).toBool(); }
    void setUpdateCheck(bool v) { set("updateCheck", v); }
    QString updateSeen() const { return m_s.value("updateSeen").toString(); }
    void setUpdateSeen(const QString &v) { set("updateSeen", v); }
    void setModel(const QString &v) { set("model", v); }
    void setScreenName(const QString &v) { set("screenName", v); }
    void setFloating(bool v) { set("floating", v); }
    void setFloatX(qreal v) { set("floatX", v); }
    void setFloatY(qreal v) { set("floatY", v); }
    void setAvoidPanels(bool v) { set("avoidPanels", v); }
    void setCloseDelay(int v) { set("closeDelay", qBound(0, v, 10)); }
    void setCharacter(const QString &v) { set("character", v); }
    void setZundaSpotify(bool v) { set("zundaSpotify", v); }
    bool tetoSystem() const { return m_s.value("tetoSystem", true).toBool(); }
    void setTetoSystem(bool v) { set("tetoSystem", v); }
    bool rinNotes() const { return m_s.value("rinNotes", true).toBool(); }
    void setRinNotes(bool v) { set("rinNotes", v); }
    bool lukaNet() const { return m_s.value("lukaNet", true).toBool(); }
    void setLukaNet(bool v) { set("lukaNet", v); }
    void setHookSeen(bool v) { set("hookSeen", v); }
    static QStringList jobs() { return {QStringLiteral("miku"), QStringLiteral("rin"), QStringLiteral("luka"), QStringLiteral("zunda"), QStringLiteral("teto")}; }
    QStringList faceList() const
    {
        QStringList f = m_s.value("faces").toStringList(), sorted = f, all = jobs();
        sorted.sort(); all.sort();
        return sorted == all ? f : jobs(); // (anything but the five, each once: as it was at first)
    }
    QVariantMap faces() const
    {
        QVariantMap m;
        const QStringList j = jobs(), f = faceList();
        for (int i = 0; i < j.size(); ++i)
            m.insert(j[i], f[i]);
        return m;
    }
    // Gives the job to that character; whoever had it takes the job she leaves.
    Q_INVOKABLE void setFace(const QString &job, const QString &character)
    {
        QStringList f = faceList();
        const int at = jobs().indexOf(job), from = f.indexOf(character);
        if (at < 0 || from < 0 || at == from)
            return;
        f.swapItemsAt(at, from);
        set("faces", f);
    }
    bool discordOn() const { return m_s.value("discordOn", false).toBool(); }
    void setDiscordOn(bool v) { set("discordOn", v); }
    bool discordProject() const { return m_s.value("discordProject", false).toBool(); }
    void setDiscordProject(bool v) { set("discordProject", v); }
    // (Kisel's own Discord application, unless the user would rather show it under another)
    QString discordAppId() const { return m_s.value("discordAppId", QStringLiteral("1557865408432701450")).toString(); }
    void setDiscordAppId(const QString &v) { set("discordAppId", v.trimmed().left(22)); }
    // ask: tell the user and let them confirm the change (default). auto: repair hooks that
    // were already connected and have gone stale, still with a dated backup; never add new
    // ones. off: only the Connect button.
    QString hookWatch() const
    {
        const QString v = m_s.value("hookWatch", "ask").toString();
        return v == QLatin1String("auto") || v == QLatin1String("off") ? v : QStringLiteral("ask");
    }
    void setHookWatch(const QString &v) { set("hookWatch", v); }
    // The user took the hooks out on purpose: do not nag about them being gone.
    bool hookRemoved() const { return m_s.value("hookRemoved", false).toBool(); }
    void setHookRemoved(bool v) { set("hookRemoved", v); }
    void setFirstRunDone(bool v) { set("firstRunDone", v); }

    // Where Kisel docks on each monitor (remembered per output name): the edge and the
    // position along it as a fraction 0..1, so it survives a change of resolution.
    // (A monitor that has no place of its own yet, or has come back under another name,
    // takes the place the bar had last: not the top centre it started from.)
    Q_INVOKABLE QString dockEdge(const QString &screen) const { return m_s.value(QStringLiteral("dock/%1/edge").arg(screen), m_s.value("lastDock/edge", "top")).toString(); }
    Q_INVOKABLE qreal dockFraction(const QString &screen) const { return m_s.value(QStringLiteral("dock/%1/frac").arg(screen), m_s.value("lastDock/frac", 0.5)).toReal(); }
    Q_INVOKABLE void setDock(const QString &screen, const QString &edge, qreal fraction)
    {
        m_s.setValue(QStringLiteral("dock/%1/edge").arg(screen), edge);
        m_s.setValue(QStringLiteral("dock/%1/frac").arg(screen), fraction);
        m_s.setValue("lastDock/edge", edge);
        m_s.setValue("lastDock/frac", fraction);
        m_s.sync(); // (written at once: the place must survive Kisel being stopped the next moment)
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
