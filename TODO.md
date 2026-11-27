# living-sky: ideas for later

## Before publishing
- **One fresh git history:** nothing has been pushed yet, and the history (~55 MB) still holds every old
  version of the demo images. Publish from a new branch with a single first commit (~15 MB), keeping the
  current branch around locally.
- **GNOME 45+:** load-test the ES-module build on a real GNOME 45–48 machine (built and syntax-checked; the
  pet drawing is verified as ES modules with gjs).
- **CI:** shellcheck runs at error level only; raise it to warnings once those are cleaned up.

## Display & desktop reach
- **Sharper on big screens:** wallpapers now fit the screen's size and shape, but are drawn at 1920x1200 first,
  so a 4K screen gets a 2x upscale. Drawing the scenes in resolution-independent coordinates would fix it.
- **Multiple monitors:** `monitor = primary | <xrandr name>`; list the outputs in `living-sky doctor`.
- **Card layout:** column side (left / right), width, top offset, margins.
- **Wayland and other desktops:** wallpaper backends beyond gsettings (KDE `plasma-apply-wallpaperimage`,
  XFCE `xfconf-query`, swww / swaybg, feh); conky's `out_to_wayland` / layer-shell where it works; an idle
  fallback in `core/glob-presence.py` when Mutter's IdleMonitor is missing (XScreenSaver / org.freedesktop.ScreenSaver).

## Cards
- **GPU card for AMD / Intel:** amdgpu sysfs (`gpu_busy_percent`, `mem_info_vram_used/total`, hwmon temp /
  power); i915 / xe (`gt_cur_freq_mhz`, hwmon where exposed). Needs that hardware to test.
- **Disks:** one entry per device, so Btrfs subvolumes (e.g. /home) aren't listed separately; they share the
  same space, so at most an option (`card_disks_ignore`, show subvolumes).
- **Network:** an `iw dev <if> link` fallback for the Wi-Fi name; when a VPN (tun0 / wg0 / tailscale0) holds
  the default route, show the VPN and the real interface under it.
- **Weather mini-forecast:** an optional next-hours / 3-day strip from the Open-Meteo call already made.
- **Album art** on the media card: cache `mpris:artUrl` in the presence helper, draw a rounded thumbnail.

## Sky & weather
- **Lunar eclipses** (a copper-red moon) and **meteor showers** (a few streaks on peak nights: Perseids,
  Geminids, ...); `core/sky.py` already has the sun and moon positions.
- **Aurora** at high latitudes (|lat| > ~55°) on clear nights: a faint green / violet curtain.
- **Rainbow** opposite a low sun (0–25°) during light rain or clearing showers.
- **Wind and storms:** rain and snow tilted by the wind speed from `weather.json`; distant lightning lighting
  the clouds during storms.

## Scenes
- **More painted scenes:** add `art/<scene>/source.jpg` (16:10 or wider, a plain sky) and a cut-out recipe in
  `tools/trace_scenes.py`, then a relighting function in `core/scenes.py`. Idea: seaside cliffs with a
  lighthouse beam sweeping at night.

## Desktop integration
- **Palette export:** write the hour's palette to `palette.json` and run an optional hook, so kitty /
  alacritty / tmux / neovim / waybar / GTK can follow the sky's colours.
- **Themes:** `minimal` (the clock and the pet, no hardware cards) and `bar` (a frosted strip along the bottom).
- **Ambient sound** (optional, off by default): quiet sounds matched to the scene and weather (fire crackle at
  the camp, waves and rain at the lake, wind in the forest) via pw-play / ffplay.

## Settings app
- **First-run setup** in the app (the installer's questions as pages) and a **one-line bootstrap script**
  that fetches the project, installs what's missing and opens it.
- **Updates for release downloads** (today: `git pull` for clones).
- **Live preview:** a time-of-day slider (and season / weather / pixel toggles) that renders the wallpaper
  with the cards before you apply it.

## Glob pets
- **New pet ideas** (small silhouettes that read at 16–20 px, each tied to real data):
  - **Nimbi**, a rain cloud: floats a little above the card, happy in the rain (drips instead of an umbrella).
  - **Sprout**, a seedling: opens a bud in clear sun (sun above 15°), folds its leaves at night, perks up after rain.
  - **Byte**, a mini CRT bot: `>_` / `{}` eyes in a terminal or editor, a spinner when the CPU is busy, a
    low-battery blink. (Keep Cubo as the reader; Byte is the coder.)
  - **Mossy**, a river stone with a moss cap: calm, rarely moves, fireflies land on it.
  - **Boba**, milk tea with pearls: pearls slosh when it hops; its thing is the afternoon break (Bun already
    owns snacking).
  - **Astra**, a star / lantern moth: would overlap Nyx, so better as Nyx's companion than a pet of its own.
- **Two pets at once** (`glob = mimi, nyx`): the second on another perch; they glance at each other, wave and
  dance together.
- **Focus / pomodoro timer** (deferred):
  - start it with a panel gesture, e.g. a triple-click (25/5 × 4);
  - the pet wears glasses and writes on a notepad, and the panel shows a countdown;
  - it waves at each break, with an optional `notify-send`;
  - the brain keeps the timer in `st`; the extension only displays it from `glob.json`.
- **Claude Code companion:** Claude Code hooks (`PreToolUse` / `Stop` / `Notification`) write
  `~/.cache/living-sky/agent` (working | waiting | done); the pet sips coffee by a tiny monitor while the agent
  works, waves when it needs permission, hops when it's done.
- **Bond level and unlocks:** XP from typing seconds, clicks and focus minutes (`~/.config/living-sky/bond.json`),
  a level-up sparkle, rarer emotes at higher levels (table flip, Glob.exe), the level shown on hover.
- **Speech bubbles** (optional): rare, short ones ("good morning", "mask on, AQI 160", "it's 3 PM").
- **Welcome back** (optional): a wave after unlock or resume (logind `PrepareForSleep`,
  `org.gnome.ScreenSaver.ActiveChanged`, in `core/glob-presence.py`).

## Code & packaging
- **Split `core/sky.py`** (~1,100 lines) into conf / astro / palette / sky modules; the tests make this safe now.
- **Packaging:** a Makefile with a `PREFIX=/usr` layout, then `.deb` and an AUR `PKGBUILD`; a CHANGELOG from
  the first release on.
