#include "Secrets.h"

#ifdef KISEL_WITH_KWALLET
#include <KWallet>
#include <QElapsedTimer>
#include <memory>
#endif
#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <wincred.h>
#endif

namespace kisel {

namespace {
const QString kFolder = QStringLiteral("Kisel");

#ifdef KISEL_WITH_KWALLET
// Opened lazily: the first call may show KWallet's unlock dialog, so it must
// happen when the user did something that needs a key, never at startup.
//
// Reading is asked for at any time (is there a key? the interface wants to know when it
// draws), so reading alone never brings the dialog up for nothing: a wallet that has no
// folder of ours has no key of ours, which KWallet tells without opening it; and a
// wallet the user would not open just now is not asked for again for five minutes.
// Storing a key is the user's own doing and always asks.
KWallet::Wallet *wallet(bool storing = false)
{
    static std::unique_ptr<KWallet::Wallet> w;
    static QElapsedTimer refused;
    if (w && w->isOpen())
        return w.get();
    if (!storing) {
        if (KWallet::Wallet::folderDoesNotExist(KWallet::Wallet::LocalWallet(), kFolder))
            return nullptr;
        if (refused.isValid() && refused.elapsed() < 5 * 60 * 1000)
            return nullptr;
    }
    w.reset(KWallet::Wallet::openWallet(KWallet::Wallet::LocalWallet(), 0, KWallet::Wallet::Synchronous));
    if (!w || !w->isOpen()) {
        refused.start();
        return nullptr;
    }
    refused.invalidate();
    if (!w->hasFolder(kFolder)) {
        if (!storing) // (nothing of ours after all)
            return nullptr;
        w->createFolder(kFolder);
    }
    w->setFolder(kFolder);
    return w.get();
}
#endif

#ifdef Q_OS_WIN
// One generic credential per key, "Kisel/<name>", in the user's own vault.
std::wstring target(const QString &name) { return (kFolder + QLatin1Char('/') + name).toStdWString(); }
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

QString Secrets::storeName() const
{
#ifdef Q_OS_WIN
    return QStringLiteral("Credential Manager");
#else
    return QStringLiteral("KWallet");
#endif
}

QString Secrets::read(const QString &name)
{
#ifdef Q_OS_WIN
    PCREDENTIALW cred = nullptr;
    if (CredReadW(target(name).c_str(), CRED_TYPE_GENERIC, 0, &cred)) {
        const QString v = QString::fromUtf8(reinterpret_cast<const char *>(cred->CredentialBlob), cred->CredentialBlobSize);
        CredFree(cred);
        if (!v.isEmpty())
            return v;
    }
#endif
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
    if (auto *w = wallet(true)) {
        const bool ok = w->writePassword(name, value) == 0;
        if (ok)
            emit changed();
        return ok;
    }
#elif defined(Q_OS_WIN)
    const std::wstring t = target(name);
    QByteArray blob = value.toUtf8();
    wchar_t user[] = L"kisel";
    CREDENTIALW cred {};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = const_cast<LPWSTR>(t.c_str());
    cred.UserName = user;
    cred.CredentialBlobSize = DWORD(blob.size());
    cred.CredentialBlob = reinterpret_cast<LPBYTE>(blob.data());
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE; // this user on this machine; never roams
    if (CredWriteW(&cred, 0)) {
        emit changed();
        return true;
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
#elif defined(Q_OS_WIN)
    if (CredDeleteW(target(name).c_str(), CRED_TYPE_GENERIC, 0)) {
        emit changed();
        return true;
    }
#else
    Q_UNUSED(name)
#endif
    return false;
}

} // namespace kisel
