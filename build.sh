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

# Flatten usr/ (deb extracts to appdir/usr/bin, we want appdir/bin).
if [ -d "$APPDIR/usr" ]; then
    cp -a "$APPDIR/usr/." "$APPDIR/"
    rm -rf "$APPDIR/usr"
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
