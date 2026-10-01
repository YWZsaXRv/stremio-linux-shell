#!/usr/bin/env bash
#
# Gera um AppImage do Stremio Linux shell.
#
# O que entra no AppImage:
#   - o binário compilado
#   - o Node.js, usado pelo servidor
#   - o server.js
#   - o schema do GSettings, o .desktop e o ícone
#
# O que fica por conta do sistema:
#   - WebKitGTK 6.0 (os processos auxiliares dele usam um caminho fixo,
#     então não dá pra colocar dentro do AppImage)
#   - GTK 4, libadwaita, libmpv, libepoxy, glib
#
# Pra compilar você precisa de:
#   cargo, gcc, pkgconf, curl, rsvg-convert, glib-compile-schemas, msgfmt
#   e os headers do webkitgtk-6.0, gtk4, libadwaita e mpv.
#
# Como usar:
#   ./build-appimage.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merro:\033[0m %s\n' "$*" >&2; exit 1; }

VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' Cargo.toml | head -1)"
ARCH="$(uname -m)"
NODE_VERSION="${NODE_VERSION:-v22.20.0}"

# o node usa nomes de arquitetura próprios, diferentes do uname
case "$ARCH" in
    x86_64)        NODE_ARCH="x64"   ;;
    aarch64|arm64) NODE_ARCH="arm64" ;;
    armv7l)        NODE_ARCH="armv7l";;
    *)             die "arquitetura não suportada: $ARCH" ;;
esac

TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
BUILD="$ROOT/build"
TOOLS="$BUILD/tools"
APPDIR="$BUILD/AppDir"
OUT="$ROOT/dist"
NAME="Stremio-${VERSION}-${ARCH}.AppImage"

# conferindo o básico
for c in cargo curl rsvg-convert glib-compile-schemas; do
    command -v "$c" >/dev/null || die "não achei a ferramenta: $c"
done

pkg-config --exists webkitgtk-6.0 || die \
"não achei os headers do WebKitGTK 6.0. Instale antes:
  Arch:   sudo pacman -S webkitgtk-6.0
  Debian: sudo apt install libwebkitgtk-6.0-dev
  Fedora: sudo dnf install webkitgtk6.0-devel"

mkdir -p "$BUILD" "$TOOLS" "$OUT"

# compilando o binário
msg "Compilando o binário (cargo build --release --locked)"
cargo build --release --locked --all-features
BIN="$TARGET_DIR/release/stremio-linux-shell"
[ -x "$BIN" ] || die "o binário não saiu em $BIN"

# appimagetool
APPIMAGETOOL="$TOOLS/appimagetool"
if [ ! -x "$APPIMAGETOOL" ]; then
    msg "Baixando o appimagetool"
    curl -fsSL -o "$APPIMAGETOOL" \
        "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

# node.js que vai empacotado
NODE_DIR="$TOOLS/node-${NODE_VERSION}-linux-${NODE_ARCH}"
if [ ! -x "$NODE_DIR/bin/node" ]; then
    msg "Baixando o Node ${NODE_VERSION}"
    curl -fsSL -o "$TOOLS/node.tar.xz" \
        "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
    rm -rf "$NODE_DIR"
    tar -xJf "$TOOLS/node.tar.xz" -C "$TOOLS"
fi

# montando o appdir
msg "Montando o AppDir"
rm -rf "$APPDIR"
mkdir -p \
    "$APPDIR/usr/bin" \
    "$APPDIR/usr/share/stremio" \
    "$APPDIR/usr/share/glib-2.0/schemas" \
    "$APPDIR/usr/share/icons/hicolor/scalable/apps" \
    "$APPDIR/usr/share/locale"

install -m755 "$BIN"               "$APPDIR/usr/bin/stremio"
install -m755 "$NODE_DIR/bin/node" "$APPDIR/usr/bin/node"
install -m644 data/server.js       "$APPDIR/usr/share/stremio/server.js"
install -m644 data/com.stremio.Stremio.gschema.xml \
                                   "$APPDIR/usr/share/glib-2.0/schemas/"
install -m644 data/icons/com.stremio.Stremio.svg \
                                   "$APPDIR/usr/share/icons/hicolor/scalable/apps/"

# traduções, quando der
if compgen -G "po/*.po" >/dev/null; then
    for po in po/*.po; do
        lang="$(basename "$po" .po)"
        [ "$lang" = "stremio" ] && continue
        d="$APPDIR/usr/share/locale/$lang/LC_MESSAGES"
        mkdir -p "$d"
        msgfmt -o "$d/stremio.mo" "$po" 2>/dev/null || true
    done
fi

glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas"

install -m755 appimage/AppRun          "$APPDIR/AppRun"
install -m644 appimage/stremio.desktop "$APPDIR/stremio.desktop"
rsvg-convert -w 256 -h 256 data/icons/com.stremio.Stremio.svg -o "$APPDIR/stremio.png"
ln -sf stremio.png "$APPDIR/.DirIcon"

# fechando o appimage
msg "Gerando o $NAME"
ARCH="$ARCH" APPIMAGE_EXTRACT_AND_RUN=1 \
    "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUT/$NAME"

msg "Pronto!"
ls -lh "$OUT/$NAME"
