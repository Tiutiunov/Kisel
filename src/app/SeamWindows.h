#pragma once

#include <QHash>
#include <QObject>
#include <QString>

class QQuickView;
class QScreen;

namespace kisel {

// One drawing of the mascot's state for a seam window (what Seam.qml binds to).
class SeamState : public QObject
{
    Q_OBJECT
    Q_PROPERTY(qreal cx MEMBER cx NOTIFY changed)
    Q_PROPERTY(qreal cy MEMBER cy NOTIFY changed)
    Q_PROPERTY(qreal size MEMBER size NOTIFY changed)
    Q_PROPERTY(qreal vx MEMBER vx NOTIFY changed)
    Q_PROPERTY(qreal vy MEMBER vy NOTIFY changed)
    Q_PROPERTY(QString mood MEMBER mood NOTIFY changed)
public:
    qreal cx = 0, cy = 0, size = 120, vx = 0, vy = 0;
    QString mood = QStringLiteral("idle");
signals:
    void changed();
};

// While Kisel is carried across the seam between two monitors it is drawn on both,
// each part clipped at the seam, from one shared position (motion.md, "Crossing
// between monitors"). A layer-shell surface belongs to one output, so every output
// the mascot touches gets a transparent, input-less surface of its own that exists
// only while it is needed. The island's own surface draws the mascot on the output
// it lives on.
class SeamWindows : public QObject
{
    Q_OBJECT
public:
    explicit SeamWindows(QObject *parent = nullptr) : QObject(parent) {}
    ~SeamWindows() override;

    // Draw the mascot centred at (cx, cy) in `screen`'s own coordinates.
    Q_INVOKABLE void show(const QString &screen, qreal cx, qreal cy, qreal size, qreal vx, qreal vy, const QString &mood);
    Q_INVOKABLE void hideScreen(const QString &screen);
    Q_INVOKABLE void hideAll();

private:
    struct Entry {
        QQuickView *view = nullptr;
        SeamState *state = nullptr;
    };
    Entry &entryFor(QScreen *screen);
    QHash<QString, Entry> m_entries;
};

} // namespace kisel
