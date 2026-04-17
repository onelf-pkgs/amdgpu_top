#!/bin/sh
# Build amdgpu_top as an onelf package.
# Runs inside a Debian/Ubuntu container.
#
# Expected env:
#   DEB_PATH      - path to the upstream .deb
#   PKG_VERSION   - version string (injected into onelf.toml via ${PKG_VERSION})
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$SCRIPT_DIR/appdir"

# Extract binary + data from the .deb.
mkdir -p "$APPDIR"
dpkg -x "$DEB_PATH" "$APPDIR"

# Install the .deb's runtime dependencies so bundle-libs can resolve
# every shared library from the system's ldconfig cache. No need to
# manually list them.
DEPS=$(dpkg-deb -f "$DEB_PATH" Depends \
    | tr ',' '\n' \
    | sed 's/([^)]*)//g; s/|.*//; s/^ *//; s/ *$//' \
    | grep -v '^$' \
    | sort -u)
if [ -n "$DEPS" ]; then
    echo "Installing deps: $DEPS"
    apt-get install -y --no-install-recommends $DEPS
fi

# GUI libs that the binary dlopens but aren't in the deb's Depends.
# bundle-libs auto-detects these via scan-dlopen but they must be
# installed on the build host for it to find and copy them.
# Install each individually so a missing package (e.g. t64 rename
# on some arches) doesn't block the rest.
for pkg in \
    libwayland-client0 libwayland-cursor0 libwayland-egl1 \
    libxkbcommon0 libdecor-0-0 \
    libx11-6 libxcursor1 libxrandr2 libxi6 libxinerama1 \
    libgl1 libglx0 libegl1 libgbm1 libvulkan1 \
    libgtk-4-1 xkb-data; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || \
    apt-get install -y --no-install-recommends "${pkg}t64" 2>/dev/null || \
    echo "note: $pkg not available, skipping"
done

# Flatten usr/ (deb extracts to appdir/usr/bin, we want appdir/bin).
if [ -d "$APPDIR/usr" ]; then
    cp -a "$APPDIR/usr/." "$APPDIR/"
    rm -rf "$APPDIR/usr"
fi

# Bundle xkb keyboard layout data. xkbcommon crashes without it and
# the data doesn't get pulled in by bundle-libs (not a shared lib).
if [ -d /usr/share/X11/xkb ]; then
    mkdir -p "$APPDIR/share/X11"
    cp -rL /usr/share/X11/xkb "$APPDIR/share/X11/"
fi

# Copy recipe into AppDir.
cp "$SCRIPT_DIR/onelf.toml" "$APPDIR/onelf.toml"

# Bundle shared libs + build.
cd "$APPDIR"
onelf bundle-libs .
onelf build

# Generate zsync control file for delta updates.
ONELF_FILE=$(ls *.onelf 2>/dev/null | head -1)
if [ -n "$ONELF_FILE" ] && command -v zsyncmake >/dev/null 2>&1; then
    zsyncmake -u "${PKG_NAME}.onelf" "$ONELF_FILE" -o "${ONELF_FILE}.zsync"
fi
