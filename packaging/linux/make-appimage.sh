#!/bin/bash
# Builds Kisel for KDE Plasma and packs it as one file that runs on any recent
# distribution: Kisel-<version>-x86_64.AppImage.
#
#   packaging/linux/make-appimage.sh <source folder> <work folder>
#
# It is meant to run where Qt 6, LayerShellQt and the KDE Frameworks Kisel uses are
# installed as the distribution packages them; .github/workflows/linux.yml runs it in
# KDE neon's own image (Ubuntu LTS underneath, so what it builds starts on anything as
# new as that). What goes into the file:
#
#   usr/bin/kisel              the application, and qt.conf beside it saying where the rest is
#   usr/lib                    Qt, LayerShellQt, the Frameworks and what they need that a
#                              desktop does not surely have (see `host` below for what is
#                              left to the system on purpose)
#   usr/plugins, usr/qml       the parts of Qt that are loaded by name
#   usr/libexec/kisel-hook     the relay with the one library it needs: Kisel copies this
#                              folder's files out to the user's data folder, where Claude
#                              Code runs the relay from
#   usr/mods                   the Claude Code mods Settings installs
#
# Nothing is found through LD_LIBRARY_PATH: every file is told where its libraries are
# (its RUNPATH), so the programs Kisel starts (claude, the player of its sounds, whatever
# a notification opens) see the system's own libraries and not ours.
set -euo pipefail

src=$(realpath "$1")
work=$(realpath -m "$2")
build="$work/build"
app="$work/AppDir"
mkdir -p "$work"

cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$build"
(cd "$build" && QT_QPA_PLATFORM=offscreen ctest --output-on-failure)
version=$(sed -n 's/^CMAKE_PROJECT_VERSION:STATIC=//p' "$build/CMakeCache.txt")

if [ -d "$app" ]; then rm -r -- "$app"; fi
DESTDIR="$app" cmake --install "$build" >/dev/null

qtpaths=$(command -v qtpaths6 || command -v qtpaths)
plugins=$("$qtpaths" --query QT_INSTALL_PLUGINS)
qml=$("$qtpaths" --query QT_INSTALL_QML)
libexecs=$("$qtpaths" --query QT_INSTALL_LIBEXECS)

# ---- the parts of Qt that are loaded by name -----------------------------------
for kind in platforms wayland-shell-integration wayland-graphics-integration-client wayland-decoration-client \
            xcbglintegrations imageformats iconengines tls platforminputcontexts; do
    [ -d "$plugins/$kind" ] || continue
    mkdir -p "$app/usr/plugins/$kind"
    for file in "$plugins/$kind"/*.so; do
        case "$kind/$(basename "$file")" in
            platforms/libqwayland*|platforms/libqxcb.so|platforms/libqoffscreen.so|platforms/libqminimal.so) ;;
            platforms/*) continue ;;                        # (the ones for screens without a desktop)
            imageformats/libqsvg.so|imageformats/libqjpeg.so|imageformats/libqgif.so|imageformats/libqico.so|imageformats/libqwebp.so) ;;
            imageformats/*) continue ;;
            iconengines/libqsvgicon.so) ;;
            iconengines/*) continue ;;
            platforminputcontexts/*virtualkeyboard*) continue ;;
        esac
        cp -L "$file" "$app/usr/plugins/$kind/"
    done
done
# The QML modules Kisel's own files ask for, and the ones those ask for in turn.
scanner="$libexecs/qmlimportscanner"
[ -x "$scanner" ] || scanner=$(command -v qmlimportscanner6 || command -v qmlimportscanner)
"$scanner" -rootPath "$src/qml" -importPath "$qml" > "$work/imports.json"
python3 - "$work/imports.json" "$qml" "$app/usr/qml" <<'EOF'
import json, os, shutil, sys
found, root, out = json.load(open(sys.argv[1])), os.path.realpath(sys.argv[2]), sys.argv[3]
for one in found:
    path = one.get('path')
    if one.get('type') != 'module' or not path:
        continue
    path = os.path.realpath(path)
    if not path.startswith(root + os.sep):
        continue
    to = os.path.join(out, os.path.relpath(path, root))
    os.makedirs(to, exist_ok=True)
    for name in os.listdir(path):            # (its own files; a module under it is listed by itself if used)
        file = os.path.join(path, name)
        if os.path.isfile(file) and not name.endswith(('.qmltypes', '.debug')):
            shutil.copy2(file, os.path.join(to, name))
EOF

# ---- the relay, in a folder of its own -------------------------------------------
mkdir -p "$app/usr/libexec/kisel-hook" "$app/usr/lib"
mv "$app/usr/bin/kisel-hook" "$app/usr/libexec/kisel-hook/"

# ---- the libraries all of that needs ---------------------------------------------
# What every desktop that runs Plasma has, and must be the system's own: the C library
# and the compiler's, the graphics drivers' side (GL, DRM, Wayland, X), fonts, the
# session bus, GLib, OpenSSL, the sound servers. Bundling a second copy of these breaks
# things (two Wayland client libraries in one program do not know of each other's
# objects) or leaves a security fix unapplied.
host='^(ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libresolv\.so|libutil\.so|libnss_|libanl\.so|libstdc\+\+\.so|libgcc_s\.so'
host+='|libGL\.so|libEGL\.so|libGLX\.so|libOpenGL\.so|libGLdispatch\.so|libGLESv2\.so|libdrm\.so|libgbm\.so|libglapi\.so|libvulkan\.so'
host+='|libwayland-|libX11\.so|libX11-xcb\.so|libxcb\.so|libXau\.so|libXdmcp\.so|libXext\.so|libxkbcommon'
host+='|libfontconfig\.so|libfreetype\.so|libharfbuzz\.so|libglib-2\.0|libgobject-2\.0|libgio-2\.0|libgmodule-2\.0|libgthread-2\.0'
host+='|libdbus-1\.so|libsystemd\.so|libudev\.so|libz\.so|libexpat\.so|libssl\.so|libcrypto\.so'
host+='|libasound\.so|libpulse|libpipewire|libselinux\.so|libmount\.so|libblkid\.so|libcap\.so|libuuid\.so|libcom_err\.so'
host+='|libgcrypt\.so|libgpg-error\.so|libnvidia|libp11-kit\.so)'

# every library `file` needs that is not the host's and not here yet -> into $2
gather() {
    local into=$2
    ldd "$1" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }' | while read -r lib; do
        local name
        name=$(basename "$lib")
        if [[ "$name" =~ $host ]] || [ -e "$into/$name" ]; then continue; fi
        case "$lib" in "$app"/*) continue ;; esac
        cp -L "$lib" "$into/$name"
        chmod u+w "$into/$name"
    done
}
elves() { find "$1" -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print; }

for round in 1 2 3; do
    while read -r file; do gather "$file" "$app/usr/lib"; done < <(elves "$app/usr/bin"; elves "$app/usr/plugins"; elves "$app/usr/qml"; elves "$app/usr/lib")
done
for round in 1 2; do
    while read -r file; do gather "$file" "$app/usr/libexec/kisel-hook"; done < <(elves "$app/usr/libexec/kisel-hook")
done

# ---- where each file finds its libraries -----------------------------------------
while read -r file; do
    case "$file" in
        "$app/usr/libexec/kisel-hook/"*) rpath='$ORIGIN' ;;
        *) rpath="\$ORIGIN/$(realpath --relative-to="$(dirname "$file")" "$app/usr/lib")" ;;
    esac
    patchelf --set-rpath "$rpath" "$file"
done < <(elves "$app/usr")
strip --strip-unneeded "$app/usr/bin/kisel" "$app/usr/libexec/kisel-hook/kisel-hook" 2>/dev/null || true
printf '[Paths]\nPrefix = ..\nLibraries = lib\nPlugins = plugins\nQmlImports = qml\n' > "$app/usr/bin/qt.conf"

# ---- the AppImage's own three files, and the file itself ---------------------------
cp "$app/usr/share/applications/kisel.desktop" "$app/kisel.desktop"
cp "$app/usr/share/icons/hicolor/scalable/apps/kisel.svg" "$app/kisel.svg"
ln -sf kisel.svg "$app/.DirIcon"
printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/kisel" "$@"\n' > "$app/AppRun"
chmod +x "$app/AppRun"

# The few kilobytes at the head of every AppImage that mount what follows and start it:
# the AppImage project's own, as it publishes it.
runtime="$work/runtime-x86_64"
if [ ! -s "$runtime" ]; then
    curl -fsSL -o "$runtime" https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64
fi
echo "runtime sha256: $(sha256sum "$runtime" | cut -d' ' -f1)"
out="$work/Kisel-$version-x86_64.AppImage"
mksquashfs "$app" "$work/app.squashfs" -root-owned -noappend -comp zstd -Xcompression-level 19 -quiet -no-progress
cat "$runtime" "$work/app.squashfs" > "$out"
chmod +x "$out"
rm -- "$work/app.squashfs"
echo "AppImage: $out ($(( $(stat -c %s "$out") / 1048576 )) MB)"
