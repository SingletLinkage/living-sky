# Cards

Each card on the desktop is one file in this folder. The engine (`lua/desktop.lua`) draws the
panel (glass or solid, depending on the theme) and the header row; a card only supplies its data
and its body. You never touch cairo surfaces, the theme, or the wallpaper.

| file | shows |
|---|---|
| `clock.lua` | time, weekday, date, uptime; battery (or host name) and OS · kernel |
| `weather.lua` | temperature, conditions, AQI, UV, humidity / rain / clouds / wind, sunrise / sunset, moon |
| `cpu.lua` | usage + sparkline, temperature, clock speed, per-thread bars, fans, load |
| `memory.lua` | RAM, swap, root disk, disk I/O |
| `gpu.lua` | NVIDIA usage, temperature, power, VRAM (never wakes a sleeping GPU) |
| `network.lua` | interface / Wi-Fi, IP, download / upload sparklines |
| `calendar.lua` | this month's grid, today highlighted (`week_start`) · off by default |
| `media.lua` | now playing from any MPRIS player: title, artist, progress (data from the presence helper) · off by default |
| `disks.lua` | every mounted disk with a usage bar (`df` in the background every 30 s) · off by default |
| `battery.lua` | charge, health vs. design capacity, cycles, power, time left · off by default |

## The card contract

A card file returns a table. Only `draw` is required.

```lua
local C = {
  id = 'disk',            -- unique; also the config switch:  card_disk = on | off
  title = 'DISKS',        -- header text; nil = no header (like the clock)
  icon = 'disk',          -- a key of ui.I (lua/lib/ui.lua) or a glyph string
  accent = 'peach',       -- palette colour name for the header chip (M.<name>)
}
-- title, icon, accent and subtitle may also be functions(d) returning the value.

function C.init(d)        -- optional, once at start: detect hardware, read static info.
  return true             -- return false to hide the card on this machine (e.g. no NVIDIA GPU)
end

function C.sample(d)      -- optional, once per second: read your data into local state
end

function C.subtitle(d)    -- optional: muted text on the right of the header
  return 'nvme0n1'
end

function C.visible(d)     -- optional, per frame: false hides the card for now (e.g. weather before
  return true             -- the first fetch)
end

function C.draw(d, x, y, w)   -- required: draw the body; (x, y) = top-left below the header,
  d.ui.text(x, y + 20, 'hello', 12, d.M.text)   -- w = inner width
  return 24               -- the body height you used (px); the panel is sized from it
end

return C
```

Errors are contained: if a card fails to load or throws, it's skipped (or drawn empty) and the error
is written once to `~/.cache/living-sky/cards.err`. The rest of the desktop keeps running.

## What `d` gives you

| field | what |
|---|---|
| `d.ui` | drawing kit (`lua/lib/ui.lua`): `text(x, y, s, size, colour, bold, align, font)` returns its width; `pill` (progress bar), `spark` (sparkline), `kv` (key … value row), `divider`, `rrect`, `rgba`, `font`, `twidth`, `lvl` (colour by level); formatting: `human`, `rate`, `push` (history list); fonts `ui.MONO`, `ui.ICON`, `ui.DISPLAY`; glyphs `ui.I`, `ui.WX`, `ui.MOON` |
| `d.M` | the live palette: `M.text`, `M.subtext0`, `M.overlay1`, `M.accent` (user primary), `M.accent2` (secondary), `M.blue`, `M.green`, `M.peach`, `M.red`, … It changes with the sky, so always take colours from here |
| `d.sys` | system readers (`lua/lib/sys.lua`): `readf(path)` (first line), `readn(path)` (number), `cmd(shell)` (first output line; forks, keep it out of per-second code), `P('${conky_var}')`, `PN(...)`, `now()`, `on_ac()`, `cpu_temp()`, `default_iface()`; detected hardware `sys.HW` (hwmon name → dir) and `sys.PS` (`bat`, `ac`) |
| `d.S` | shared live values: `S.cpu_temp` |
| `d.tick`, `d.dt` | samples so far, seconds since the last sample (for rates) |
| `d.time` | the time to show (`os.time()`, plus the test offset in `~/.cache/living-sky/fake_offset`); use `os.date(fmt, d.time)` |
| `d.wx`, `d.sky` | weather data (`core/weather.py`) and the current sky slot (sunrise, sunset, moon, flavour) |
| `d.cr` | the cairo context, for raw `cairo_*` calls |
| `d.cache`, `d.q` | the cache dir (`~/.cache/living-sky/`) and a shell-quote function for paths |
| `d.cfg` | all of `living-sky.conf` as strings, for your own options (e.g. `d.cfg.disk_mounts`) |
| `d.glass` | true in the glass style |
| `d.demo` | true while `living-sky preview --demo` renders: show placeholders instead of anything personal (names, addresses, places) |

## Adding a card

1. Copy a small card (`network.lua` is a good start) to `lua/cards/<id>.lua` and edit it.
2. Add `<id>` to `CARDS` near the top of the cards section of `lua/desktop.lua`; the order there is
   the default order on screen. Add it to `CARD_DEFAULT_OFF` too if it should be opt-in.
3. Add a `card_<id> = on` line, with a one-line comment, to the Cards section of
   `living-sky.conf.example`.
4. `living-sky restart`, then `living-sky preview` for a PNG. Check `~/.cache/living-sky/cards.err`.

Keep `sample` cheap (it runs every second): read `/proc` and `/sys` files; run commands in the
background into a cache file (see `gpu.lua`) or only every N ticks (see `network.lua`).
