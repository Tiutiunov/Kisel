#pragma once

#include <QImage>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>

namespace kisel {

// Pictures for the chat: a screenshot pasted from the clipboard (Win+Shift+S, Spectacle)
// or a picture file dropped on the bar. Each is saved as a file of Kisel's own in
// ~/.kisel/shots (the home folder, as the inbox is: Claude Code, run from a packaged app,
// does not see what Kisel writes under AppData), made no larger than Claude looks at
// anyway, and kept a week. What the chat holds is that file's URL.
//
// Then: a quick question sends the picture itself to Claude Code along with the words
// (QuickAsk::message); a message to a session names the file, and the session opens it.
class Shots : public QObject
{
    Q_OBJECT
public:
    explicit Shots(QObject *parent = nullptr);

    Q_INVOKABLE bool clipboardHasImage() const;
    // The picture on the clipboard, saved: its URL, or "" when there is none.
    Q_INVOKABLE QString fromClipboard();
    // A picture file (one a person dropped), saved as Kisel's own: its URL, or "" when it is no picture.
    Q_INVOKABLE QString fromUrl(const QUrl &url);
    Q_INVOKABLE static bool isImage(const QUrl &url);
    // The file behind one of these URLs, as the system writes paths (for a message to a session).
    Q_INVOKABLE static QString localPath(const QString &url);

    static QString folder();
    // At most this many pictures go with one message.
    static constexpr int kMax = 4;

    // Pure, unit-tested: the picture made fit (longest side 1920 px) and encoded, PNG, or
    // JPEG when a PNG of it would be too heavy (a photo); `mediaType` says which.
    static QByteArray encode(const QImage &image, QString *mediaType);

private:
    QString save(const QImage &image);
    void prune();
};

} // namespace kisel
