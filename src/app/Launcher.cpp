#include "Launcher.h"

#include <QDesktopServices>
#include <QUrl>

namespace kisel {

bool Launcher::openUrl(const QString &url)
{
    const QUrl u(url);
    // Never launch anything but a web page: the string may come from an API.
    if (u.scheme() != QLatin1String("https") || u.host().isEmpty())
        return false;
    return QDesktopServices::openUrl(u);
}

} // namespace kisel
