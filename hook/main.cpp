// kisel-hook: the relay Claude Code runs on every hook event.
//
// Reads the hook JSON on stdin, adds a little terminal context and hands it to
// Kisel over the Unix socket $XDG_RUNTIME_DIR/kisel.sock (on Windows the named
// pipe \\.\pipe\kisel-<user SID>).
//
// Hard rule: NEVER block Claude Code.
//  * No socket (Kisel is closed): exit 0 at once with nothing on stdout.
//  * Every step runs against one deadline (poll with a remaining budget, or
//    overlapped I/O on Windows), so a peer that accepts and then stops reading
//    cannot wedge a session.
//  * Only PermissionRequest waits for an answer. No answer means empty stdout,
//    and Claude Code asks in the terminal as if Kisel were not installed.
//
// Usage: kisel-hook [--agent <name>] [<EventName>]
//
// Depends on QtCore (JSON) only; no event loop, no QCoreApplication.

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <sddl.h>

#include <fcntl.h>
#include <io.h>
#else
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#endif

namespace {
using Clock = std::chrono::steady_clock;

constexpr int kConnectMs = 300;
constexpr int kFireAndForgetMs = 2000;
constexpr int kDecisionMs = 110'000;
constexpr int kMaxFieldLen = 2000;

int msLeft(Clock::time_point deadline)
{
    const auto d = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
    return d < 0 ? 0 : int(d);
}

#ifdef _WIN32
using Conn = HANDLE;
const Conn kNoConn = INVALID_HANDLE_VALUE;

long readStdin(char *buf, unsigned size) { return _read(_fileno(stdin), buf, size); }

// The user a process runs as, as a SID in `buf`.
bool userOf(HANDLE process, BYTE *buf, DWORD size)
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(process, TOKEN_QUERY, &token))
        return false;
    DWORD len = 0;
    const bool ok = GetTokenInformation(token, TokenUser, buf, size, &len) != 0;
    CloseHandle(token);
    return ok;
}
PSID sidIn(BYTE *buf) { return reinterpret_cast<TOKEN_USER *>(buf)->User.Sid; }

// Must match kisel::paths::socketPath() in the app.
std::wstring socketPath()
{
    BYTE me[256];
    LPWSTR text = nullptr;
    if (!userOf(GetCurrentProcess(), me, sizeof me) || !ConvertSidToStringSidW(sidIn(me), &text))
        return {};
    const std::wstring path = std::wstring(L"\\\\.\\pipe\\kisel-") + text;
    LocalFree(text);
    return path;
}

// The pipe's name is guessable, so somebody else could have created it first:
// talk only to a server that runs as the same user.
bool serverIsSameUser(HANDLE pipe)
{
    ULONG pid = 0;
    if (!GetNamedPipeServerProcessId(pipe, &pid))
        return false;
    HANDLE server = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!server)
        return false;
    BYTE me[256], them[256];
    const bool same = userOf(GetCurrentProcess(), me, sizeof me) && userOf(server, them, sizeof them)
        && EqualSid(sidIn(me), sidIn(them));
    CloseHandle(server);
    return same;
}

// A short retry while every pipe instance is busy. Any other failure means
// nobody is listening and waiting would only delay Claude Code.
Conn connectSocket()
{
    const std::wstring path = socketPath();
    if (path.empty())
        return kNoConn;
    const auto deadline = Clock::now() + std::chrono::milliseconds(kConnectMs);
    for (;;) {
        // SECURITY_IDENTIFICATION: the server may learn who we are, never act as us.
        HANDLE h = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                               FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
        if (h != INVALID_HANDLE_VALUE) {
            if (!serverIsSameUser(h)) {
                CloseHandle(h);
                return kNoConn;
            }
            return h; // overlapped; every I/O below waits against the deadline
        }
        if (GetLastError() != ERROR_PIPE_BUSY || msLeft(deadline) == 0)
            return kNoConn;
        WaitNamedPipeW(path.c_str(), DWORD(msLeft(deadline)) | 1); // 0 would mean the pipe's default wait
    }
}

// Waits for one overlapped read or write, cancelling it at the deadline.
bool finishIo(HANDLE h, OVERLAPPED &ov, BOOL started, DWORD *n, Clock::time_point deadline)
{
    if (!started) {
        if (GetLastError() != ERROR_IO_PENDING)
            return false;
        if (WaitForSingleObject(ov.hEvent, DWORD(msLeft(deadline))) != WAIT_OBJECT_0) {
            CancelIo(h);
            GetOverlappedResult(h, &ov, n, TRUE); // the buffer is ours again only once the cancel has landed
            return false;
        }
    }
    return GetOverlappedResult(h, &ov, n, FALSE) != 0;
}

bool writeAll(Conn h, const std::string &data, Clock::time_point deadline)
{
    OVERLAPPED ov {};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!ov.hEvent)
        return false;
    size_t off = 0;
    bool ok = true;
    while (ok && off < data.size()) {
        DWORD n = 0;
        const BOOL started = WriteFile(h, data.data() + off, DWORD(data.size() - off), nullptr, &ov);
        ok = finishIo(h, ov, started, &n, deadline) && n > 0;
        off += n;
    }
    CloseHandle(ov.hEvent);
    return ok;
}

// Reads until a newline, EOF or the deadline. Empty on timeout.
std::string readLine(Conn h, Clock::time_point deadline)
{
    OVERLAPPED ov {};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!ov.hEvent)
        return {};
    std::string buf;
    char chunk[512];
    bool timedOut = false;
    for (;;) {
        DWORD n = 0;
        const BOOL started = ReadFile(h, chunk, sizeof chunk, nullptr, &ov);
        if (!finishIo(h, ov, started, &n, deadline) || n == 0) {
            timedOut = msLeft(deadline) == 0;
            break; // otherwise the pipe was closed
        }
        buf.append(chunk, n);
        if (buf.find('\n') != std::string::npos)
            break;
    }
    CloseHandle(ov.hEvent);
    if (timedOut)
        return {};
    while (!buf.empty() && (buf.back() == '\n' || buf.back() == ' ' || buf.back() == '\r'))
        buf.pop_back();
    return buf;
}
#else
using Conn = int;
constexpr Conn kNoConn = -1;

long readStdin(char *buf, unsigned size) { return long(read(STDIN_FILENO, buf, size)); }

// Must match kisel::paths::socketPath() in the app.
std::string socketPath()
{
    std::string dir;
    const char *xdg = std::getenv("XDG_RUNTIME_DIR");
    if (xdg && xdg[0] == '/')
        dir = xdg;
    else
        dir = "/run/user/" + std::to_string(getuid());

    struct stat st {};
    // A real directory, ours, closed to everyone else, or there is no relay.
    if (lstat(dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 077))
        return {};
    return dir + "/kisel.sock";
}

bool serverIsSameUser(int fd)
{
    ucred cred {};
    socklen_t len = sizeof cred;
    return getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0 && cred.uid == getuid();
}

// Non-blocking connect with a short retry while the backlog is full. Any other
// failure means nobody is listening and waiting would only delay Claude Code.
Conn connectSocket()
{
    const std::string path = socketPath();
    if (path.empty() || path.size() >= sizeof(sockaddr_un::sun_path))
        return -1;
    const auto deadline = Clock::now() + std::chrono::milliseconds(kConnectMs);
    for (;;) {
        int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        if (fd < 0)
            return -1;
        sockaddr_un addr {};
        addr.sun_family = AF_UNIX;
        std::memcpy(addr.sun_path, path.c_str(), path.size());
        if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr) == 0) {
            if (!serverIsSameUser(fd)) {
                close(fd);
                return -1;
            }
            return fd; // stays non-blocking; every I/O below uses poll
        }
        const int err = errno;
        close(fd);
        if (err != EAGAIN || msLeft(deadline) == 0)
            return -1;
        usleep(15'000);
    }
}

bool writeAll(int fd, const std::string &data, Clock::time_point deadline)
{
    size_t off = 0;
    while (off < data.size()) {
        const ssize_t n = write(fd, data.data() + off, data.size() - off);
        if (n > 0) {
            off += size_t(n);
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            pollfd p {fd, POLLOUT, 0};
            if (poll(&p, 1, msLeft(deadline)) <= 0)
                return false;
            continue;
        }
        return false;
    }
    return true;
}

// Reads until a newline, EOF or the deadline. Empty on timeout.
std::string readLine(int fd, Clock::time_point deadline)
{
    std::string buf;
    char chunk[512];
    for (;;) {
        pollfd p {fd, POLLIN, 0};
        if (poll(&p, 1, msLeft(deadline)) <= 0)
            return {};
        const ssize_t n = read(fd, chunk, sizeof chunk);
        if (n > 0) {
            buf.append(chunk, size_t(n));
            if (buf.find('\n') != std::string::npos)
                break;
        } else if (n == 0) {
            break;
        } else if (errno != EINTR && errno != EAGAIN) {
            break;
        }
    }
    while (!buf.empty() && (buf.back() == '\n' || buf.back() == ' ' || buf.back() == '\r'))
        buf.pop_back();
    return buf;
}
#endif

void truncateStrings(QJsonValue &v)
{
    if (v.isString()) {
        QString s = v.toString();
        if (s.size() > kMaxFieldLen)
            v = s.left(kMaxFieldLen) + QChar(0x2026); // QString cuts on UTF-16 units, never mid-codepoint bytes
    } else if (v.isArray()) {
        QJsonArray a = v.toArray();
        for (qsizetype i = 0; i < a.size(); ++i) {
            QJsonValue x = a.at(i);
            truncateStrings(x);
            a[i] = x;
        }
        v = a;
    } else if (v.isObject()) {
        QJsonObject o = v.toObject();
        for (auto it = o.begin(); it != o.end(); ++it) {
            QJsonValue x = it.value();
            truncateStrings(x);
            it.value() = x;
        }
        v = o;
    }
}

// The documented PermissionRequest output. The app answers with one line:
//   allow | always | deny                       a plain decision
//   {"decision":"allow","updatedInput":{...}}   allow, with the tool input
//                                               changed (AskUserQuestion answers)
// Anything unrecognised prints nothing: silence is the safe answer.
std::string decisionJson(const std::string &line)
{
    QJsonObject decision;
    if (line == "allow" || line == "always") {
        decision["behavior"] = "allow";
    } else if (line == "deny") {
        decision["behavior"] = "deny";
        decision["message"] = "Denied from Kisel";
    } else if (!line.empty() && line.front() == '{') {
        const QJsonObject o = QJsonDocument::fromJson(QByteArray::fromStdString(line)).object();
        if (o.value("decision").toString() != QLatin1String("allow") || !o.value("updatedInput").isObject())
            return {};
        decision["behavior"] = "allow";
        decision["updatedInput"] = o.value("updatedInput");
    } else {
        return {};
    }
    const QJsonObject out {{"hookSpecificOutput", QJsonObject {{"hookEventName", "PermissionRequest"}, {"decision", decision}}}};
    return QJsonDocument(out).toJson(QJsonDocument::Compact).toStdString();
}

} // namespace

int main(int argc, char **argv)
{
#ifdef _WIN32
    // bytes in, bytes out: no CR LF translation
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#else
    std::signal(SIGPIPE, SIG_IGN);
#endif

    // ---- stdin ----
    std::string raw;
    char chunk[4096];
    for (long n; (n = readStdin(chunk, sizeof chunk)) > 0;)
        raw.append(chunk, size_t(n));
    if (raw.empty())
        return 0;
    if (raw.size() >= 3 && raw.compare(0, 3, "\xEF\xBB\xBF") == 0)
        raw.erase(0, 3);

    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromStdString(raw), &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject())
        return 0;
    QJsonObject obj = doc.object();

    // ---- argv: [--agent name] [EventName] ----
    QString agent, argEvent;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a == QLatin1String("--agent") && i + 1 < argc)
            agent = QString::fromLocal8Bit(argv[++i]);
        else if (argEvent.isEmpty())
            argEvent = a;
    }
    // Absent means Claude Code; the app validates the name, not us.
    if (!agent.isEmpty())
        obj["kisel_agent"] = agent;

    QString event = obj.value("hook_event_name").toString();
    if (event.isEmpty())
        event = argEvent;
    obj["hook_event_name"] = event;

    // Fields that are pointless to forward and can be enormous.
    obj.remove("tool_response");
    obj.remove("transcript_path");

    if (obj.value("cwd").toString().isEmpty())
        obj["cwd"] = QDir::currentPath();
    // Terminal context only; never a filter.
    static const struct { const char *key, *var; } ctx[] = {
        {"term_program", "TERM_PROGRAM"}, {"konsole_dbus_service", "KONSOLE_DBUS_SERVICE"},
        {"term_session_id", "TERM_SESSION_ID"}, {"vscode_pid", "VSCODE_PID"}, {"tmux", "TMUX"},
    };
    for (const auto &c : ctx)
        if (!obj.contains(c.key))
            obj[c.key] = QString::fromLocal8Bit(std::getenv(c.var) ? std::getenv(c.var) : "");

    QJsonValue root = obj;
    truncateStrings(root);

    // ---- talk ----
    const bool waits = event == QLatin1String("PermissionRequest");
    const auto deadline = Clock::now() + std::chrono::milliseconds(waits ? kDecisionMs : kFireAndForgetMs);

    const Conn fd = connectSocket();
    if (fd == kNoConn)
        return 0;
    std::string line = QJsonDocument(root.toObject()).toJson(QJsonDocument::Compact).toStdString();
    line.push_back('\n');
    if (!writeAll(fd, line, deadline) || !waits)
        return 0;

    const std::string out = decisionJson(readLine(fd, deadline));
    if (!out.empty()) {
        std::fputs(out.c_str(), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
    }
    return 0;
}
