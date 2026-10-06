// kisel-hook: the relay Claude Code runs on every hook event.
//
// Reads the hook JSON on stdin, adds a little terminal context and hands it to
// Kisel over the Unix socket $XDG_RUNTIME_DIR/kisel.sock.
//
// Hard rule: NEVER block Claude Code.
//  * No socket (Kisel is closed): exit 0 at once with nothing on stdout.
//  * Every step runs against one deadline (poll with a remaining budget), so a
//    peer that accepts and then stops reading cannot wedge a session.
//  * Only PermissionRequest waits for an answer. No answer means empty stdout,
//    and Claude Code asks in the terminal as if Kisel were not installed.
//
// Usage: kisel-hook [--agent <name>] [<EventName>]
//
// Depends on QtCore (JSON) only; no event loop, no QCoreApplication.

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

#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

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
int connectSocket()
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
    std::signal(SIGPIPE, SIG_IGN);

    // ---- stdin ----
    std::string raw;
    char chunk[4096];
    for (ssize_t n; (n = read(STDIN_FILENO, chunk, sizeof chunk)) > 0;)
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

    if (obj.value("cwd").toString().isEmpty()) {
        char cwd[4096];
        if (getcwd(cwd, sizeof cwd))
            obj["cwd"] = QString::fromLocal8Bit(cwd);
    }
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

    const int fd = connectSocket();
    if (fd < 0)
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
