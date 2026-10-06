#include "Secrets.h"

#ifdef KISEL_WITH_KWALLET
#include <KWallet>
#include <memory>
#endif

namespace kisel {

namespace {
const QString kFolder = QStringLiteral("Kisel");

#ifdef KISEL_WITH_KWALLET
// Opened lazily: the first call may show KWallet's unlock dialog, so it must
// happen when the user did something that needs a key, never at startup.
KWallet::Wallet *wallet()
{
    static std::unique_ptr<KWallet::Wallet> w;
    if (!w || !w->isOpen()) {
        w.reset(KWallet::Wallet::openWallet(KWallet::Wallet::LocalWallet(), 0, KWallet::Wallet::Synchronous));
        if (w && !w->hasFolder(kFolder))
            w->createFolder(kFolder);
        if (w)
            w->setFolder(kFolder);
    }
    return (w && w->isOpen()) ? w.get() : nullptr;
}
#endif

QString envFallback(const QString &name)
{
    return name == QLatin1String(Secrets::kAnthropic) ? qEnvironmentVariable("ANTHROPIC_API_KEY") : QString();
}
} // namespace

bool Secrets::has(const QString &name)
{
    return !read(name).isEmpty();
}

QString Secrets::read(const QString &name)
{
#ifdef KISEL_WITH_KWALLET
    if (auto *w = wallet()) {
        QString v;
        if (w->readPassword(name, v) == 0 && !v.isEmpty())
            return v;
    }
#endif
    return envFallback(name);
}

bool Secrets::store(const QString &name, const QString &value)
{
#ifdef KISEL_WITH_KWALLET
    if (auto *w = wallet()) {
        const bool ok = w->writePassword(name, value) == 0;
        if (ok)
            emit changed();
        return ok;
    }
#else
    Q_UNUSED(name) Q_UNUSED(value)
#endif
    return false;
}

bool Secrets::remove(const QString &name)
{
#ifdef KISEL_WITH_KWALLET
    if (auto *w = wallet()) {
        const bool ok = w->removeEntry(name) == 0;
        if (ok)
            emit changed();
        return ok;
    }
#else
    Q_UNUSED(name)
#endif
    return false;
}

} // namespace kisel
