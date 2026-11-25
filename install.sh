#!/usr/bin/env bash
# living-sky installer. Runs from wherever you cloned / unpacked the project; re-running it is safe.
#
#   ./install.sh                 check everything, offer to install what's missing (packages with sudo,
#                                the conky AppImage, fonts), ask a few setup questions, install
#   ./install.sh --yes           no questions: install what's missing and keep the defaults
#   ./install.sh --no-deps       only check dependencies; don't install packages or download anything
#   ./install.sh --extension     install the glob pet panel extension (asked anyway when interactive)
#   ./install.sh --no-autostart  don't start it at login
#   ./install.sh --start         start it at the end
#   ./install.sh --dry-run       show what would be installed / downloaded / written, change nothing
#   ./install.sh --ask           ask the questions even when the input isn't a terminal (scripted tests)
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN="$HOME/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/living-sky"
CONF="$CONF_DIR/living-sky.conf"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/living-sky.desktop"
EXT_UUID="glob@living-sky"
APP_ID="io.github.living_sky.Settings"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/living-sky"
CONKY_DIR="$HOME/.local/opt/conky"

yes=0; deps=1; want_ext=""; autostart=1; start=0; dry=0; force_ask=0
for a in "$@"; do
    case "$a" in
        --yes|-y) yes=1 ;;
        --no-deps) deps=0 ;;
        --extension) want_ext=1 ;;
        --no-autostart) autostart=0 ;;
        --start) start=1 ;;
        --dry-run) dry=1 ;;
        --ask) force_ask=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a (see --help)" >&2; exit 1 ;;
    esac
done
interactive=0
{ [ -t 0 ] || [ $force_ask = 1 ]; } && [ $yes = 0 ] && interactive=1

# ------------------------------------------------------------------ helpers
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
run()  { if [ $dry = 1 ]; then echo "    would run: $*"; else "$@"; fi; }
ask() {                   # ask "question" default -> the answer (the default without a terminal / with --yes)
    local a
    if [ $interactive = 0 ]; then echo "$2"; return; fi
    read -r -p "  ? $1 [$2]: " a </dev/stdin || a=""
    echo "${a:-$2}"
}
confirm() {               # confirm "question" y|n -> exit status
    local a
    a=$(ask "$1 (y/n)" "$2")
    case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}
choose() {                # choose "question" default "a b c" -> one of the options
    local a
    a=$(ask "$1 ($(echo $3 | tr ' ' '/'))" "$2")
    case " $3 " in *" $a "*) echo "$a" ;; *) warn "'$a' isn't one of: $3 — using $2" >&2; echo "$2" ;; esac
}

# ------------------------------------------------------------------ what's missing
PM=""
for m in apt-get dnf pacman zypper; do command -v $m >/dev/null && { PM=$m; break; }; done

pkg() {                   # pkg <need> -> the package name for this distro
    case "$PM:$1" in
        apt-get:numpy) echo python3-numpy ;;   dnf:numpy) echo python3-numpy ;;
        pacman:numpy) echo python-numpy ;;     zypper:numpy) echo python3-numpy ;;
        apt-get:cv2) echo python3-opencv ;;    dnf:cv2) echo python3-opencv ;;
        pacman:cv2) echo python-opencv ;;      zypper:cv2) echo python3-opencv ;;
        apt-get:PIL) echo python3-pil ;;       dnf:PIL) echo python3-pillow ;;
        pacman:PIL) echo python-pillow ;;      zypper:PIL) echo python3-Pillow ;;
        apt-get:gi) echo python3-gi ;;         dnf:gi) echo python3-gobject ;;
        pacman:gi) echo python-gobject ;;      zypper:gi) echo python3-gobject ;;
        apt-get:adw) echo gir1.2-adw-1 ;;      dnf:adw) echo libadwaita ;;
        pacman:adw) echo libadwaita ;;         zypper:adw) echo typelib-1_0-Adw-1 ;;
        apt-get:Xlib) echo python3-xlib ;;     dnf:Xlib) echo python3-xlib ;;
        pacman:Xlib) echo python-xlib ;;       zypper:Xlib) echo python3-python-xlib ;;
        *:curl) echo curl ;;
        apt-get:xrandr) echo x11-xserver-utils ;; pacman:xrandr) echo xorg-xrandr ;; *:xrandr) echo xrandr ;;
        apt-get:gsettings) echo libglib2.0-bin ;; zypper:gsettings) echo glib2-tools ;; *:gsettings) echo glib2 ;;
        *:fc-list) echo fontconfig ;;
        apt-get:fuse) apt-cache show libfuse2t64 >/dev/null 2>&1 && echo libfuse2t64 || echo libfuse2 ;;
        dnf:fuse) echo fuse-libs ;; pacman:fuse) echo fuse2 ;; zypper:fuse) echo libfuse2 ;;
    esac
}

font_pkg() {              # font_pkg <font name> -> the distro package for it, if the distro has one
    case "$PM:$1" in
        apt-get:"JetBrains Mono") echo fonts-jetbrains-mono ;;  dnf:"JetBrains Mono") echo jetbrains-mono-fonts-all ;;
        pacman:"JetBrains Mono") echo ttf-jetbrains-mono ;;     zypper:"JetBrains Mono") echo jetbrains-mono-fonts ;;
        pacman:"FiraCode Nerd Font") echo ttf-firacode-nerd ;;
    esac
}
pkg_available() {         # is package $1 in this distro's repositories?
    case "$PM" in
        apt-get) apt-cache show "$1" >/dev/null 2>&1 ;;
        dnf) dnf info -q "$1" >/dev/null 2>&1 ;;
        pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
        zypper) zypper -q info "$1" 2>/dev/null | grep -q "^Name" ;;
        *) false ;;
    esac
}
fonts_missing() {         # re-check just the fonts (after a package install)
    local f; missing_fonts=()
    for f in "JetBrains Mono" "FiraCode Nerd Font" "Bebas Neue"; do
        fc-list 2>/dev/null | grep -qi "$f" || missing_fonts+=("$f")
    done
}

conky_status() {          # -> "ok <path> <ver>" | "missing" | "old <ver>" | "nocairo <ver>"
    local c info ver
    c="${CONKY_BIN:-$(ls -1 "$CONKY_DIR"/conky-*.AppImage 2>/dev/null | sort -V | tail -1)}"
    [ -x "$c" ] || c=$(command -v conky || true)
    [ -n "$c" ] || { echo missing; return; }
    info=$("$c" -v 2>/dev/null)
    ver=$(echo "$info" | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    case "$ver" in 1.1[0-8].*|1.[0-9].*) echo "old $ver"; return ;; esac
    echo "$info" | grep -qi cairo || { echo "nocairo $ver"; return; }
    echo "ok $c $ver"
}

need=()                   # package needs (see pkg)
missing_fonts=()
check() {
    need=(); missing_fonts=()
    local m t f
    for m in numpy cv2 PIL gi Xlib; do
        if python3 -c "import $m" 2>/dev/null; then ok "python3 $m"; else bad "python3 $m"; need+=("$m"); fi
    done
    if python3 -c "import gi; gi.require_version('Gtk', '4.0'); gi.require_version('Adw', '1')" 2>/dev/null; then
        ok "GTK 4 + libadwaita (settings window)"
    else bad "GTK 4 + libadwaita for Python (the settings window)"; need+=(adw); fi
    for t in curl gsettings xrandr fc-list; do
        if command -v "$t" >/dev/null; then ok "$t"; else bad "$t"; need+=("$t"); fi
    done
    case "$(conky_status)" in
        ok*) set -- $(conky_status); ok "conky $3 with Lua cairo ($2)" ;;
        missing) bad "conky (not installed)"; CONKY_NEEDED=1 ;;
        old*) bad "conky $(conky_status | cut -d' ' -f2) is too old (1.19+ needed)"; CONKY_NEEDED=1 ;;
        nocairo*) bad "conky without Lua cairo bindings"; CONKY_NEEDED=1 ;;
    esac
    if [ "${CONKY_NEEDED:-0}" = 1 ] && ! ldconfig -p 2>/dev/null | grep -q 'libfuse.so.2'; then
        bad "libfuse2 (the conky AppImage needs it)"; need+=(fuse)
    fi
    for f in "JetBrains Mono" "FiraCode Nerd Font" "Bebas Neue"; do
        if fc-list 2>/dev/null | grep -qi "$f"; then ok "font: $f"; else bad "font: $f"; missing_fonts+=("$f"); fi
    done
    local xv
    xv=$(python3 -c "import Xlib; print('.'.join(map(str, Xlib.__version__)))" 2>/dev/null)
    case "$xv" in 0.1[0-6]|0.[0-9]) warn "python-xlib $xv is old: typing falls back to X RECORD (pip install --user -U python-xlib)";; esac
    command -v nvidia-smi >/dev/null && ok "nvidia-smi (GPU card)" || warn "nvidia-smi not found: the GPU card stays hidden (fine without an NVIDIA GPU)"
}

latest_tag() {            # latest_tag owner/repo -> vX.Y.Z (from the releases/latest redirect; no API)
    curl -sIL -m 20 -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/tag/||'
}

get_conky() {
    local tag arch url
    tag=$(latest_tag brndnmtthws/conky); arch=$(uname -m)
    [ -n "$tag" ] && [ "${tag#v}" != "$tag" ] || { bad "couldn't find the latest conky release"; return 1; }
    url="https://github.com/brndnmtthws/conky/releases/download/$tag/conky-$arch-$tag.AppImage"
    echo "    conky $tag ($arch) -> $CONKY_DIR/"
    run mkdir -p "$CONKY_DIR"
    run curl -fL --progress-bar -o "$CONKY_DIR/conky-$arch-$tag.AppImage" "$url" || { bad "download failed: $url"; return 1; }
    run chmod +x "$CONKY_DIR/conky-$arch-$tag.AppImage"
    # remember what we downloaded, so `uninstall.sh --purge-deps` removes only that
    [ $dry = 1 ] || echo "conky-$arch-$tag.AppImage" >> "$CONKY_DIR/.living-sky-downloaded"
}

get_fonts() {
    local f tmp tag
    tmp=$(mktemp -d)
    run mkdir -p "$FONT_DIR"
    for f in "${missing_fonts[@]}"; do
        case "$f" in
            "JetBrains Mono")
                tag=$(latest_tag JetBrains/JetBrainsMono)
                run curl -fsSL -o "$tmp/jb.zip" "https://github.com/JetBrains/JetBrainsMono/releases/download/$tag/JetBrainsMono-${tag#v}.zip" &&
                run python3 -c "import sys, zipfile, os; z = zipfile.ZipFile(sys.argv[1]); [open(os.path.join(sys.argv[2], os.path.basename(n)), 'wb').write(z.read(n)) for n in z.namelist() if n in ('fonts/ttf/JetBrainsMono-Regular.ttf', 'fonts/ttf/JetBrainsMono-Bold.ttf')]" "$tmp/jb.zip" "$FONT_DIR" ;;
            "FiraCode Nerd Font")
                run curl -fsSL -o "$tmp/fc.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" &&
                run python3 -c "import sys, zipfile, os; z = zipfile.ZipFile(sys.argv[1]); [open(os.path.join(sys.argv[2], n), 'wb').write(z.read(n)) for n in z.namelist() if n in ('FiraCodeNerdFontMono-Regular.ttf', 'FiraCodeNerdFontMono-Bold.ttf')]" "$tmp/fc.zip" "$FONT_DIR" ;;
            "Bebas Neue")
                run curl -fsSL -o "$FONT_DIR/BebasNeue-Regular.ttf" "https://github.com/google/fonts/raw/main/ofl/bebasneue/BebasNeue-Regular.ttf" ;;
        esac && ok "font: $f -> $FONT_DIR" || bad "couldn't download $f"
    done
    run fc-cache -f "$FONT_DIR" >/dev/null 2>&1
    rm -rf "$tmp"
}

# ------------------------------------------------------------------ 1. dependencies
step "Checking what living-sky needs"
CONKY_NEEDED=0
check
if [ $deps = 1 ] && { [ ${#need[@]} -gt 0 ] || [ "$CONKY_NEEDED" = 1 ] || [ ${#missing_fonts[@]} -gt 0 ]; }; then
    step "Installing what's missing"
    fontpkgs=()               # fonts the distro packages: install those with the rest, download only what's left
    for f in "${missing_fonts[@]}"; do
        p=$(font_pkg "$f"); [ -n "$p" ] && pkg_available "$p" && fontpkgs+=("$p")
    done
    if [ ${#need[@]} -gt 0 ] || [ ${#fontpkgs[@]} -gt 0 ]; then
        if [ -z "$PM" ]; then
            bad "no known package manager (apt / dnf / pacman / zypper): install these yourself: ${need[*]}"
        else
            pkgs=("${fontpkgs[@]}"); for n in "${need[@]}"; do p=$(pkg "$n"); [ -n "$p" ] && pkgs+=("$p"); done
            echo "  packages: ${pkgs[*]}"
            if confirm "Install them with sudo $PM?" y; then
                case "$PM" in
                    apt-get) run sudo apt-get install -y "${pkgs[@]}" ;;
                    dnf) run sudo dnf install -y "${pkgs[@]}" ;;
                    pacman) run sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
                    zypper) run sudo zypper install -y "${pkgs[@]}" ;;
                esac
            fi
        fi
    fi
    if [ "$CONKY_NEEDED" = 1 ] && confirm "Download the conky AppImage (latest release) into $CONKY_DIR?" y; then
        get_conky
    fi
    [ $dry = 0 ] && [ ${#fontpkgs[@]} -gt 0 ] && fonts_missing
    if [ ${#missing_fonts[@]} -gt 0 ] && confirm "Download the fonts (${missing_fonts[*]}) into $FONT_DIR?" y; then
        get_fonts
    fi
    if [ $dry = 0 ]; then step "Checking again"; CONKY_NEEDED=0; check; fi
fi
deps_ok=1
{ [ ${#need[@]} -gt 0 ] || [ "$CONKY_NEEDED" = 1 ] || [ ${#missing_fonts[@]} -gt 0 ]; } && deps_ok=0

step "Session"
session_ok=1
[ "${XDG_SESSION_TYPE:-}" = "x11" ] && ok "X11 session" || {
    warn "session is '${XDG_SESSION_TYPE:-?}': living-sky needs X11. Log out, click the gear on the login"
    warn "screen and choose \"GNOME on Xorg\" (Ubuntu: \"Ubuntu on Xorg\"), then log in again."
    session_ok=0
}
GNOME_MAJOR=$(gnome-shell --version 2>/dev/null | grep -o '[0-9]\+' | head -1)
case "${XDG_CURRENT_DESKTOP:-}" in *GNOME*) ok "GNOME ${GNOME_MAJOR:-?}" ;; *) warn "not GNOME: the wallpaper is set the GNOME way (gsettings), the panel pet is GNOME only";; esac

# ------------------------------------------------------------------ 2. settings
set_conf() {              # set_conf key value  (keeps the layout and comments of the config page)
    [ $dry = 1 ] && { echo "    would set: $1 = $2"; return; }
    python3 - "$CONF" "$1" "$2" <<'PY'
import re, sys
fn, key, val = sys.argv[1:]
lines = open(fn).read().split('\n')
for i, l in enumerate(lines):
    if re.match(r'^%s\s*=' % re.escape(key), l):
        lines[i] = ('%s = %s' % (key, val)).rstrip(); break
else:
    lines.append('%s = %s' % (key, val))
open(fn, 'w').write('\n'.join(lines))
PY
}

step "Settings"
fresh=0
if [ ! -f "$CONF" ]; then
    run mkdir -p "$CONF_DIR"; run cp "$ROOT/living-sky.conf.example" "$CONF"; fresh=1
    ok "settings page: $CONF"
else
    ok "keeping your settings: $CONF"
fi
if [ $interactive = 1 ] && { [ $fresh = 1 ] || confirm "Go through the setup questions again?" n; }; then
    [ $dry = 1 ] && [ ! -f "$CONF" ] && CONF="$ROOT/living-sky.conf.example"    # dry run: read the defaults
    cur() { sed -n "s/^$1 *= *\(.*\)/\1/p" "$CONF" | head -1; }
    set_conf theme  "$(choose 'Card style' "$(cur theme)" 'glass cards')"
    set_conf scene  "$(choose 'Scene' "$(cur scene)" 'lake forest city camp')"
    set_conf pixel  "$(choose 'Pixel-art look' "$(cur pixel)" 'off on')"
    set_conf colors "$(choose 'Colours' "$(cur colors)" 'auto lavender sakura mint peach ocean')"
    set_conf glob   "$(choose 'Pet' "$(cur glob)" 'mimi pip bun nyx cubo ember random scene off')"
    set_conf units  "$(choose 'Units' "$(cur units)" 'metric imperial')"
    set_conf clock  "$(choose 'Clock' "$(cur clock)" '24h 12h')"
    if confirm "Find your location once from your IP address (for the sun, moon and weather)?" y; then
        set_conf geo auto
    else
        set_conf lat "$(ask 'Latitude (e.g. 48.85)' '')"
        set_conf lon "$(ask 'Longitude (e.g. 2.35)' '')"
        set_conf name "$(ask 'Place name for the weather card' '')"
        set_conf geo off
    fi
    extra=$(ask "Extra cards: any of calendar, media, disks, battery (comma separated, or none)" none)
    for c in calendar media disks battery; do
        case ",${extra// /}," in *",$c,"*) set_conf "card_$c" on ;; *) set_conf "card_$c" off ;; esac
    done
    ok "saved; change anything later in $CONF"
fi

# ------------------------------------------------------------------ 3. install
step "Installing"
run mkdir -p "$BIN"
run ln -sfn "$ROOT/bin/living-sky" "$BIN/living-sky" && ok "command: living-sky -> $ROOT/bin/living-sky"
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not in your PATH yet: log out and back in (or add it)";; esac

# the settings window: a launcher in the app grid ("Living Sky") with its icon
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
if [ $dry = 1 ]; then echo "    would write: $APPS/$APP_ID.desktop"
else
    mkdir -p "$APPS" "$ICONS"
    cp "$ROOT/app/living-sky.svg" "$ICONS/living-sky.svg"
    cat > "$APPS/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Living Sky
Comment=Settings for the living-sky wallpaper, cards and glob pet
Exec=$ROOT/bin/living-sky settings
Icon=living-sky
Categories=Settings;DesktopSettings;GTK;
Keywords=wallpaper;conky;sky;pet;widgets;
StartupNotify=true
EOF
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null
fi
ok "settings window: \"Living Sky\" in your apps, or: living-sky settings"

[ $interactive = 1 ] && [ $autostart = 1 ] && { confirm "Start living-sky when you log in?" y || autostart=0; }
if [ $autostart = 1 ]; then
    if [ $dry = 1 ]; then echo "    would write: $AUTOSTART"
    else
        mkdir -p "$(dirname "$AUTOSTART")"
        cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=living-sky
Comment=Living-sky wallpaper, cards and glob pet (conky)
Exec=$ROOT/bin/living-sky start
X-GNOME-Autostart-Delay=5
X-GNOME-Autostart-enabled=true
EOF
    fi
    ok "autostart: $AUTOSTART"
fi

# the panel pet: GNOME 42-44 use the extension as it is; 45+ get the ES-module build
if [ -z "$want_ext" ] && [ $interactive = 1 ] && [ -n "$GNOME_MAJOR" ]; then
    confirm "Also show the pet in the top panel (GNOME extension)?" y && want_ext=1
fi
if [ "$want_ext" = 1 ]; then
    if [ -z "$GNOME_MAJOR" ]; then warn "GNOME Shell not found: skipping the panel extension"
    else
        if [ "$GNOME_MAJOR" -ge 45 ]; then
            src="$ROOT/gnome-extension/build/$EXT_UUID"
            run python3 "$ROOT/gnome-extension/build-esm.py" "$src" >/dev/null && ok "built the GNOME $GNOME_MAJOR (ES module) version"
        else
            src="$ROOT/gnome-extension/$EXT_UUID"
        fi
        run mkdir -p "$(dirname "$EXT_DIR")"
        [ -L "$EXT_DIR" ] && run rm -f "$EXT_DIR"
        if [ -e "$EXT_DIR" ]; then warn "$EXT_DIR exists and isn't a link: leaving it alone"
        else run ln -s "$src" "$EXT_DIR" && ok "panel extension: $EXT_DIR"; fi
        if [ $dry = 0 ] && gnome-extensions enable "$EXT_UUID" 2>/dev/null; then ok "panel extension enabled"
        else warn "GNOME Shell loads new extensions after a restart: log out and in (X11: Alt+F2, r), then: gnome-extensions enable $EXT_UUID"; fi
    fi
fi

# ------------------------------------------------------------------ 4. start
if [ $start = 0 ] && [ $interactive = 1 ] && [ $deps_ok = 1 ] && [ $session_ok = 1 ]; then
    confirm "Start living-sky now?" y && start=1
fi
if [ $start = 1 ]; then
    if [ $deps_ok = 0 ]; then echo "Not starting: something it needs is still missing (see above)."
    elif [ $session_ok = 0 ]; then echo "Not starting: log in to an X11 session first."
    else run "$ROOT/bin/living-sky" start; fi
fi
step "Done"
echo "  living-sky start | stop | restart | status | doctor | settings     config: $CONF"
