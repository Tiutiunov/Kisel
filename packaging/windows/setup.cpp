// KiselSetup.exe: the installer for Windows, and (copied into the folder as
// uninstall.exe, without its load) the uninstaller.
//
// It is this small program with a zip of the whole application appended to it (see
// make-installer.cmake). It asks nothing of the system but what Windows 10 has: the zip
// is unpacked with the system's own tar.exe. Everything is per user: no administrator
// rights, nothing outside the folder chosen, the Start menu and the user's own
// "Apps" entry.
//
//   KiselSetup.exe                 asks where (by default %LOCALAPPDATA%\Programs\Kisel)
//   KiselSetup.exe /SILENT         asks nothing (this is how Kisel updates itself)
//   KiselSetup.exe /DIR=<folder>   installs there
//   KiselSetup.exe /UNPACK         the files and nothing else (for trying the installer out)
//   uninstall.exe /UNINSTALL       removes what was installed; settings and saved keys stay
//
// Installing over a running Kisel closes it first, and starts the new one after.
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <tlhelp32.h>

#include <string>
#include <vector>

#ifndef KISEL_VERSION
#define KISEL_VERSION "0.0.0"
#endif
#define WIDEN2(x) L##x
#define WIDEN(x) WIDEN2(x)

namespace {

const wchar_t *const kTitle = L"Kisel";
const wchar_t *const kVersion = WIDEN(KISEL_VERSION);
const wchar_t *const kUninstallKey = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Kisel";
const wchar_t *const kParts[] = {L"bin", L"plugins", L"qml", L"translations", L"licenses", L"mods"}; // what the zip holds

bool g_silent = false;
bool g_unpackOnly = false; // /UNPACK: the files and nothing else (no shortcut, no "Apps" entry, no start): for trying the installer out

void say(const std::wstring &text, UINT icon = MB_ICONINFORMATION)
{
    if (!g_silent || icon == MB_ICONERROR)
        MessageBoxW(nullptr, text.c_str(), kTitle, MB_OK | icon | MB_SETFOREGROUND);
}

std::wstring selfPath()
{
    std::wstring s(32768, L'\0');
    s.resize(GetModuleFileNameW(nullptr, s.data(), DWORD(s.size())));
    return s;
}

std::wstring knownFolder(REFKNOWNFOLDERID id)
{
    PWSTR p = nullptr;
    std::wstring s;
    if (SUCCEEDED(SHGetKnownFolderPath(id, 0, nullptr, &p)))
        s = p;
    CoTaskMemFree(p);
    return s;
}

bool exists(const std::wstring &path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

std::wstring trimSlash(std::wstring s)
{
    while (s.size() > 3 && (s.back() == L'\\' || s.back() == L'/'))
        s.pop_back();
    return s;
}

// where this program's own code ends in its file: what follows is the zip
ULONGLONG imageEnd(HANDLE file)
{
    IMAGE_DOS_HEADER dos {};
    DWORD got = 0;
    if (!ReadFile(file, &dos, sizeof dos, &got, nullptr) || got != sizeof dos || dos.e_magic != IMAGE_DOS_SIGNATURE)
        return 0;
    LARGE_INTEGER at;
    at.QuadPart = dos.e_lfanew;
    DWORD sig = 0;
    IMAGE_FILE_HEADER fh {};
    if (!SetFilePointerEx(file, at, nullptr, FILE_BEGIN) || !ReadFile(file, &sig, sizeof sig, &got, nullptr) || sig != IMAGE_NT_SIGNATURE
        || !ReadFile(file, &fh, sizeof fh, &got, nullptr))
        return 0;
    at.QuadPart = dos.e_lfanew + sizeof sig + sizeof fh + fh.SizeOfOptionalHeader;
    if (!SetFilePointerEx(file, at, nullptr, FILE_BEGIN))
        return 0;
    ULONGLONG end = 0;
    for (int i = 0; i < fh.NumberOfSections; ++i) {
        IMAGE_SECTION_HEADER sh {};
        if (!ReadFile(file, &sh, sizeof sh, &got, nullptr) || got != sizeof sh)
            return 0;
        const ULONGLONG e = ULONGLONG(sh.PointerToRawData) + sh.SizeOfRawData;
        if (e > end)
            end = e;
    }
    return end;
}

// copy [from, from + count) of this program's file to `to` (count 0: to the end)
bool copyPart(const std::wstring &to, ULONGLONG from, ULONGLONG count)
{
    HANDLE in = CreateFileW(selfPath().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (in == INVALID_HANDLE_VALUE)
        return false;
    HANDLE out = CreateFileW(to.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE) {
        CloseHandle(in);
        return false;
    }
    LARGE_INTEGER at;
    at.QuadPart = LONGLONG(from);
    bool ok = SetFilePointerEx(in, at, nullptr, FILE_BEGIN) != 0;
    std::vector<char> buf(1 << 20);
    ULONGLONG left = count;
    while (ok) {
        DWORD want = DWORD(buf.size()), got = 0, put = 0;
        if (count && left < want)
            want = DWORD(left);
        if (want == 0 || !ReadFile(in, buf.data(), want, &got, nullptr) || got == 0)
            break;
        ok = WriteFile(out, buf.data(), got, &put, nullptr) && put == got;
        left -= got;
    }
    CloseHandle(in);
    CloseHandle(out);
    return ok;
}

// run a command line, hidden, and wait for it (up to `ms`); its exit code, or -1
int run(std::wstring cmd, DWORD ms, const wchar_t *cwd = nullptr, bool wait = true)
{
    STARTUPINFOW si {};
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi {};
    if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, cwd, &si, &pi))
        return -1;
    DWORD code = 0;
    if (wait) {
        if (WaitForSingleObject(pi.hProcess, ms) != WAIT_OBJECT_0)
            code = DWORD(-1);
        else
            GetExitCodeProcess(pi.hProcess, &code);
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return int(code);
}

// Kisel and its relay, if they are running out of this folder: let them go by themselves
// for a moment (Kisel quits when it starts an update), then stop them
void closeRunning(const std::wstring &dir)
{
    const std::wstring root = dir + L"\\";
    for (int pass = 0; pass < 2; ++pass) {
        bool any = false;
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap == INVALID_HANDLE_VALUE)
            return;
        PROCESSENTRY32W pe {};
        pe.dwSize = sizeof pe;
        for (BOOL more = Process32FirstW(snap, &pe); more; more = Process32NextW(snap, &pe)) {
            if (pe.th32ProcessID == GetCurrentProcessId() || (_wcsicmp(pe.szExeFile, L"kisel.exe") != 0 && _wcsicmp(pe.szExeFile, L"kisel-hook.exe") != 0))
                continue;
            HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pe.th32ProcessID);
            if (!p)
                continue;
            wchar_t path[32768];
            DWORD n = 32768;
            if (QueryFullProcessImageNameW(p, 0, path, &n) && _wcsnicmp(path, root.c_str(), root.size()) == 0) {
                any = true;
                if (pass == 0) {
                    WaitForSingleObject(p, 3000);
                } else {
                    TerminateProcess(p, 0);
                    WaitForSingleObject(p, 5000);
                }
            }
            CloseHandle(p);
        }
        CloseHandle(snap);
        if (!any)
            return;
    }
}

// Makes way for the new files. A file of the old installation that something still holds
// (a relay Claude Code started this very moment, a Kisel that could not be stopped) cannot
// be written over, and one such file fails the whole unpacking; but Windows lets a file in
// use be renamed. So such a file is moved aside as "<name>.old-<n>", and the leftovers of
// earlier updates are removed when nothing holds them any more. Read-only marks, which
// stop the unpacking just the same, are taken off.
void makeWay(const std::wstring &folder, std::wstring *held)
{
    WIN32_FIND_DATAW fd {};
    HANDLE h = FindFirstFileW((folder + L"\\*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE)
        return;
    do {
        const std::wstring name = fd.cFileName;
        if (name == L"." || name == L"..")
            continue;
        const std::wstring path = folder + L"\\" + name;
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT))
                makeWay(path, held);
            continue;
        }
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_READONLY)
            SetFileAttributesW(path.c_str(), fd.dwFileAttributes & ~DWORD(FILE_ATTRIBUTE_READONLY));
        if (name.find(L".old-") != std::wstring::npos) {
            DeleteFileW(path.c_str());
            continue;
        }
        HANDLE f = CreateFileW(path.c_str(), GENERIC_WRITE | DELETE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
        if (f != INVALID_HANDLE_VALUE) {
            CloseHandle(f);
            continue;
        }
        bool moved = false;
        for (int n = 0; n < 50 && !moved; ++n)
            moved = MoveFileW(path.c_str(), (path + L".old-" + std::to_wstring(n)).c_str()) != 0;
        if (!moved && held && held->empty())
            *held = path;
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}

bool pickFolder(std::wstring *dir)
{
    IFileOpenDialog *dlg = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dlg))))
        return false;
    DWORD opts = 0;
    dlg->GetOptions(&opts);
    dlg->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    dlg->SetTitle(L"Where to install Kisel");
    bool ok = false;
    if (SUCCEEDED(dlg->Show(nullptr))) {
        IShellItem *item = nullptr;
        if (SUCCEEDED(dlg->GetResult(&item))) {
            PWSTR p = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &p))) {
                *dir = trimSlash(p);
                // (a folder of its own, unless the one picked is Kisel's already)
                if (!exists(*dir + L"\\bin\\kisel.exe") && _wcsicmp(dir->substr(dir->find_last_of(L'\\') + 1).c_str(), L"Kisel") != 0)
                    *dir += (dir->back() == L'\\' ? L"Kisel" : L"\\Kisel");
                ok = true;
            }
            CoTaskMemFree(p);
            item->Release();
        }
    }
    dlg->Release();
    return ok;
}

bool makeShortcut(const std::wstring &link, const std::wstring &target, const std::wstring &cwd)
{
    IShellLinkW *sl = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&sl))))
        return false;
    sl->SetPath(target.c_str());
    sl->SetWorkingDirectory(cwd.c_str());
    sl->SetDescription(L"Kisel");
    IPersistFile *pf = nullptr;
    bool ok = false;
    if (SUCCEEDED(sl->QueryInterface(IID_PPV_ARGS(&pf)))) {
        ok = SUCCEEDED(pf->Save(link.c_str(), TRUE));
        pf->Release();
    }
    sl->Release();
    return ok;
}

void regSet(HKEY key, const wchar_t *name, const std::wstring &value)
{
    RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE *>(value.c_str()), DWORD((value.size() + 1) * sizeof(wchar_t)));
}

std::wstring startMenuLink() { return knownFolder(FOLDERID_Programs) + L"\\Kisel.lnk"; }

int install(std::wstring dir)
{
    const std::wstring self = selfPath();
    HANDLE f = CreateFileW(self.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE)
        return 1;
    const ULONGLONG end = imageEnd(f);
    LARGE_INTEGER size {};
    GetFileSizeEx(f, &size);
    CloseHandle(f);
    if (end == 0 || ULONGLONG(size.QuadPart) <= end + 22) {
        say(L"This installer is incomplete: it carries no application.", MB_ICONERROR);
        return 1;
    }

    if (dir.empty()) {
        // (an earlier installation is updated where it is)
        wchar_t was[32768];
        DWORD n = sizeof was;
        if (RegGetValueW(HKEY_CURRENT_USER, kUninstallKey, L"InstallLocation", RRF_RT_REG_SZ, nullptr, was, &n) == ERROR_SUCCESS && was[0])
            dir = trimSlash(was);
        else
            dir = knownFolder(FOLDERID_LocalAppData) + L"\\Programs\\Kisel";
        if (!g_silent) {
            const std::wstring q = std::wstring(L"Install Kisel ") + kVersion + L" here?\n\n" + dir + L"\n\nYes: install here.   No: choose another folder.";
            const int a = MessageBoxW(nullptr, q.c_str(), kTitle, MB_YESNOCANCEL | MB_ICONQUESTION | MB_SETFOREGROUND);
            if (a == IDCANCEL || (a == IDNO && !pickFolder(&dir)))
                return 2;
        }
    }
    dir = trimSlash(dir);

    closeRunning(dir);
    const int made = SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
    if (made != ERROR_SUCCESS && made != ERROR_ALREADY_EXISTS && made != ERROR_FILE_EXISTS) {
        say(L"Could not create the folder:\n" + dir, MB_ICONERROR);
        return 1;
    }

    wchar_t tmp[MAX_PATH + 1];
    GetTempPathW(MAX_PATH, tmp);
    const std::wstring zip = std::wstring(tmp) + L"kisel-payload-" + std::to_wstring(GetCurrentProcessId()) + L".zip";
    if (!copyPart(zip, end, 0)) {
        say(L"Could not write to the temporary folder.", MB_ICONERROR);
        return 1;
    }
    wchar_t sys[MAX_PATH + 1];
    GetSystemDirectoryW(sys, MAX_PATH);
    const std::wstring tar = std::wstring(sys) + L"\\tar.exe";
    int code = exists(tar) ? -1 : -2;
    std::wstring held;
    // (Claude Code may start the relay at any moment, between the making of way and the
    // unpacking too: then both are done again)
    for (int attempt = 0; attempt < 4 && code != 0 && code != -2; ++attempt) {
        if (attempt > 0) {
            Sleep(700);
            closeRunning(dir);
        }
        held.clear();
        for (const wchar_t *part : kParts)
            makeWay(dir + L"\\" + part, &held);
        code = run(L"\"" + tar + L"\" -xf \"" + zip + L"\" -C \"" + dir + L"\"", 10 * 60 * 1000);
    }
    DeleteFileW(zip.c_str());
    if (code != 0 || !exists(dir + L"\\bin\\kisel.exe")) {
        say(code == -2 ? L"This Windows has no tar.exe to unpack with (Windows 10 version 1803 or newer is needed)."
                       : L"Could not unpack the files into:\n" + dir
                             + (held.empty() ? L"\n\nIs there room on the disk, and may this folder be written to?"
                                             : L"\n\nThis file is in use and would not give way:\n" + held),
            MB_ICONERROR);
        return 1;
    }

    // (a plugin earlier versions carried and this one does not: its folder is not left lying there)
    if (exists(dir + L"\\mods\\cache-band"))
        run(L"cmd.exe /c rmdir /s /q \"" + dir + L"\\mods\\cache-band\"", 15000);
    if (g_unpackOnly)
        return 0;
    // the uninstaller is this program without its load
    copyPart(dir + L"\\uninstall.exe", 0, end);
    makeShortcut(startMenuLink(), dir + L"\\bin\\kisel.exe", dir + L"\\bin");
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kUninstallKey, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        regSet(key, L"DisplayName", L"Kisel");
        regSet(key, L"DisplayVersion", kVersion);
        regSet(key, L"Publisher", L"Kisel");
        regSet(key, L"InstallLocation", dir);
        regSet(key, L"DisplayIcon", dir + L"\\bin\\kisel.exe");
        regSet(key, L"UninstallString", L"\"" + dir + L"\\uninstall.exe\" /UNINSTALL");
        regSet(key, L"QuietUninstallString", L"\"" + dir + L"\\uninstall.exe\" /UNINSTALL /SILENT");
        const DWORD one = 1;
        RegSetValueExW(key, L"NoModify", 0, REG_DWORD, reinterpret_cast<const BYTE *>(&one), sizeof one);
        RegSetValueExW(key, L"NoRepair", 0, REG_DWORD, reinterpret_cast<const BYTE *>(&one), sizeof one);
        RegCloseKey(key);
    }

    const std::wstring bin = dir + L"\\bin";
    run(L"\"" + bin + L"\\kisel.exe\"", 0, bin.c_str(), false);
    return 0;
}

int uninstall()
{
    std::wstring self = selfPath();
    const std::wstring dir = trimSlash(self.substr(0, self.find_last_of(L'\\')));
    if (!exists(dir + L"\\bin\\kisel.exe")) {
        say(L"Kisel is not installed in this folder.", MB_ICONERROR);
        return 1;
    }
    if (!g_silent && MessageBoxW(nullptr, (L"Remove Kisel from this computer?\n\n" + dir + L"\n\nIts hooks are taken out of Claude Code's settings. Your Kisel settings and saved keys stay.").c_str(),
                                 kTitle, MB_OKCANCEL | MB_ICONQUESTION | MB_SETFOREGROUND) != IDOK)
        return 2;

    closeRunning(dir);
    // Claude Code must not be left calling a relay that is gone: Kisel takes its own hooks
    // out (with its usual dated backup of the settings file)
    run(L"\"" + dir + L"\\bin\\kisel.exe\" --remove-hooks", 15000, (dir + L"\\bin").c_str());
    closeRunning(dir);

    DeleteFileW(startMenuLink().c_str());
    DeleteFileW((knownFolder(FOLDERID_Startup) + L"\\Kisel.lnk").c_str());
    HKEY runKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &runKey) == ERROR_SUCCESS) {
        RegDeleteValueW(runKey, L"Kisel");
        RegCloseKey(runKey);
    }
    RegDeleteKeyW(HKEY_CURRENT_USER, kUninstallKey);

    // Only what the installer put there goes, and the folder itself only if that leaves
    // it empty. This program is still running out of it, so a command prompt does the
    // removing a moment after it has gone.
    std::wstring cmd = L"cmd.exe /c ping -n 3 127.0.0.1 >nul";
    for (const wchar_t *part : kParts)
        cmd += L" & rmdir /s /q \"" + dir + L"\\" + part + L"\"";
    cmd += L" & del /q \"" + dir + L"\\uninstall.exe\" & rmdir \"" + dir + L"\"";
    wchar_t tmp[MAX_PATH + 1];
    GetTempPathW(MAX_PATH, tmp);
    run(cmd, 0, tmp, false);
    say(L"Kisel has been removed.");
    return 0;
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    int argc = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    bool remove = false;
    std::wstring dir;
    for (int i = 1; argv && i < argc; ++i) {
        const std::wstring a = argv[i];
        if (_wcsicmp(a.c_str(), L"/SILENT") == 0)
            g_silent = true;
        else if (_wcsicmp(a.c_str(), L"/UNPACK") == 0)
            g_unpackOnly = true;
        else if (_wcsicmp(a.c_str(), L"/UNINSTALL") == 0)
            remove = true;
        else if (_wcsnicmp(a.c_str(), L"/DIR=", 5) == 0)
            dir = trimSlash(a.substr(5));
    }
    LocalFree(argv);
    const int code = remove ? uninstall() : install(dir);
    CoUninitialize();
    return code;
}
