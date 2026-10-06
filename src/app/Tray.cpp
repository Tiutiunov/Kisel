#include "Tray.h"

#include <QAction>
#include <QMenu>
#include <QIcon>

#ifdef KISEL_WITH_SNI
#include <KStatusNotifierItem>
#else
#include <QSystemTrayIcon>
#endif

namespace kisel {

Tray::Tray(QObject *parent)
    : QObject(parent)
{
#ifdef KISEL_WITH_SNI
    auto *item = new KStatusNotifierItem(QStringLiteral("kisel"), this);
    item->setCategory(KStatusNotifierItem::ApplicationStatus);
    item->setTitle(QStringLiteral("Kisel"));
    item->setIconByPixmap(QIcon(QStringLiteral(":/qt/qml/Kisel/resources/logo/miku-mini.svg")));
    item->setStatus(KStatusNotifierItem::Active);

    auto *menu = new QMenu;
    menu->addAction(QStringLiteral("Open"), this, &Tray::openRequested);
    menu->addAction(QStringLiteral("Settings…"), this, &Tray::settingsRequested);
    menu->addSeparator();
    menu->addAction(QStringLiteral("Quit"), this, &Tray::quitRequested);
    item->setContextMenu(menu);
    connect(item, &KStatusNotifierItem::activateRequested, this, &Tray::openRequested);
#else
    // Windows, and desktops without StatusNotifierItem: the plain system tray.
    if (!QSystemTrayIcon::isSystemTrayAvailable())
        return;
    auto *item = new QSystemTrayIcon(QIcon(QStringLiteral(":/qt/qml/Kisel/resources/logo/miku-mini.svg")), this);
    item->setToolTip(QStringLiteral("Kisel"));

    auto *menu = new QMenu;
    menu->addAction(QStringLiteral("Open"), this, &Tray::openRequested);
    menu->addAction(QStringLiteral("Settings…"), this, &Tray::settingsRequested);
    menu->addSeparator();
    menu->addAction(QStringLiteral("Quit"), this, &Tray::quitRequested);
    item->setContextMenu(menu);
    connect(item, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason why) {
        if (why == QSystemTrayIcon::Trigger)
            emit openRequested();
    });
    item->show();
#endif
}

} // namespace kisel
