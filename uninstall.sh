#!/usr/bin/env bash
# living-sky uninstaller: stops it, restores your wallpaper, removes the command link,
# settings launcher, autostart entry and panel extension link. Keeps your config and cache unless --purge.
#   ./uninstall.sh [--purge] [--purge-deps]
#   --purge       also remove ~/.config/living-sky and ~/.cache/living-sky
#   --purge-deps  also remove what the installer downloaded: the fonts in ~/.local/share/fonts/living-sky
#                 and the conky AppImage(s) it fetched (never a conky you installed yourself)
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/living-sky"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/living-sky"
EXT_UUID="glob@living-sky"

"$ROOT/bin/living-sky" stop
if [ "$(readlink -f "$HOME/.local/bin/living-sky" 2>/dev/null)" = "$ROOT/bin/living-sky" ]; then
    rm -f "$HOME/.local/bin/living-sky"
fi
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/living-sky.desktop"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.living_sky.Settings.desktop" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/living-sky.svg"
# Only touch the panel extension if it is ours in *this* home: GNOME Shell is shared by the whole session,
# so a test run with another HOME must not disable the real user's extension.
EXT_LINK="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
if [ -L "$EXT_LINK" ] && case "$(readlink -f "$EXT_LINK")" in "$ROOT"/*) true ;; *) false ;; esac; then
    gnome-extensions disable "$EXT_UUID" 2>/dev/null
    rm -f "$EXT_LINK"
fi
purge=0; purge_deps=0
for a in "$@"; do case "$a" in --purge) purge=1 ;; --purge-deps) purge_deps=1 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;; esac; done
if [ $purge = 1 ]; then
    rm -rf "$CONF_DIR" "$CACHE"
    echo "Removed config and cache."
else
    echo "Kept $CONF_DIR and $CACHE (use --purge to remove them)."
fi
if [ $purge_deps = 1 ]; then
    FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/living-sky"
    if [ -d "$FONT_DIR" ]; then rm -rf "$FONT_DIR"; fc-cache -f >/dev/null 2>&1; echo "Removed the fonts in $FONT_DIR."; fi
    CONKY_DIR="$HOME/.local/opt/conky"
    if [ -f "$CONKY_DIR/.living-sky-downloaded" ]; then
        while read -r f; do
            case "$f" in conky-*.AppImage) [ -f "$CONKY_DIR/$f" ] && rm -f "$CONKY_DIR/$f" && echo "Removed $CONKY_DIR/$f." ;; esac
        done < "$CONKY_DIR/.living-sky-downloaded"
        rm -f "$CONKY_DIR/.living-sky-downloaded"
        rmdir "$CONKY_DIR" 2>/dev/null
    else
        echo "No conky AppImage downloaded by the installer (kept any conky you installed)."
    fi
fi
echo "living-sky uninstalled. The project folder itself is untouched."
