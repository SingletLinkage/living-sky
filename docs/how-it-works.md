# How living-sky works

## Layout
- Each theme is a transparent, click-through, full-screen conky canvas with no conky text
  (`themes/<name>/conky.conf`). `themes/<name>/<name>.lua` only sets the style (`glass` or `cards`)
  and loads the engine.
- `lua/desktop.lua`, the engine: reads `living-sky.conf`, loads the enabled cards, samples them once
  a second, draws each card's panel and header, switches the living-sky wallpaper and palette, and
  hosts the glob pet. The card bodies are cached in an off-screen layer that is redrawn once a
  second; each frame (4 fps) only composites that layer and the animated pet.
- `lua/cards/<id>.lua`: one file per card (data + body drawing). How to write or change one:
  [`lua/cards/README.md`](../lua/cards/README.md).
- `lua/lib/ui.lua` (drawing kit: text, bars, sparklines, icons) and `lua/lib/sys.lua`
  (`/proc` and `/sys` readers, hardware detection) are shared by the cards.
- The canvas covers the primary monitor (size from `xrandr`, filled in by `bin/living-sky`); the card
  column sits 30 px from its right edge. To move or resize the stack, edit `COL_X, COL_W, TOP, GAP`
  near the top of `lua/desktop.lua`.
- Hardware is detected at start by the cards themselves: CPU model, thread count and fans (cpu),
  temperature sensor (coretemp / k10temp / zenpower, in `sys.scan`), RAM size and root disk type
  (memory), battery and AC adapter (clock), an NVIDIA GPU (the gpu card hides itself without one).
- Preview: `living-sky preview [--demo]` writes `~/.cache/living-sky/preview-<theme>.png`; `--demo` makes
  the cards show placeholders for personal details (Wi-Fi name, IP, place, host).
- `living-sky doctor` prints the code version, non-default settings, session and conky version, what the
  running desktop detected (`~/.cache/living-sky/detected`, written by the engine), the presence helper's
  state and the last lines of every log.

## Glass theme
How the glass works:
- conky can't read the pixels behind its window, so a real backdrop blur isn't possible.
- Instead, `sky.py` writes `<slot>-frost.png` next to each hourly wallpaper. It is a blurred,
  colour-boosted copy whose brightness is nudged toward the palette base, so text stays
  readable even over dark mountains in daylight.
- The glass style paints that image inside each card, mapped exactly like GNOME's zoomed wallpaper, then adds:
  - a few magnified rings at the edge (lens refraction)
  - a tint and a top-left specular sheen
  - a darker inner lower edge
  - a lit rim
- The look is tuned in `glass_style()` (light and dark sets) and `FROST_LUMA` / `make_frost()`
  in `core/sky.py`.

## Living sky
The wallpaper and card palette follow the real sky at your location. Each hour slot is rendered for its
midpoint (HH:30), and the switch happens live without restarting conky.

- `core/sky.py` redraws the lake-and-mountain art for the actual sun and moon position:
  - sky gradient and twilight glow
  - stars and the Milky Way (night only)
  - sun, and the moon with its real phase and bright-limb tilt
  - daily-varying clouds
  - lake reflection with a glitter path

  It also writes a palette: Mocha for night, Macchiato for blue hour, Frappé for dawn and dusk,
  Latte for day, with sky-matched accents.
- The geometry comes from the original art (`art/lake/wallpaper-static.png`).
  `tools/trace_ridges.py` extracted `art/lake/mtn_alpha.png`, `mtn_shade.png`, `shore.json` and `waves.png`.
  Rerun it only if you change the source art.
- `lua/desktop.lua` (the "living sky" section) checks the slot every ~15 s:
  - It applies `~/.cache/living-sky/<slot>.lua` and sets the GNOME background to `<slot>.png`.
  - It starts a background render (`nice 19`, about 1.5 s) when a slot is missing.
  - It pre-renders the next slot 3 minutes early.

  There's no cron or timer: when another theme runs, nothing changes, and a missed hour after suspend
  is caught within seconds.
- `living-sky.conf`:
  - `lat` / `lon`: leave blank to auto-locate through ipinfo.io (ipapi.co as fallback), cached for 24 h.
  - `geo = off`: never go online.
  - `interval_min`: 60 by default; 30 or 20 give smoother sunsets.
- Weather: `core/weather.py` pulls current conditions, today's high/low, UV and rain chance
  from Open-Meteo, plus US AQI from Open-Meteo air quality. There's no API key, and location is rounded to about 1 km.
  The Lua refreshes it every 15 min into `~/.cache/living-sky/weather.lua` and draws the WEATHER card (plus sunrise/sunset and moon phase).
  The battery is now a compact row in the clock card. Each hourly render also reads `weather.json`:
  - cloud cover decides how many clouds appear
  - overcast greys the sky and hides the sun and moon
  - rain, storms, snow and fog are drawn in
  Test with `sky.py --at "..." --wx rain:100`.
- Cache: `~/.cache/living-sky/` keeps the newest 48 renders. `render.log` holds renderer output.

Handy commands:
```
python3 core/sky.py --info                          # location, sun/moon, sunrise/sunset, phase
python3 core/sky.py --at "2026-12-24 17:30" --out /tmp/x.png
python3 tools/daysheet.py 2026-11-22 /tmp/day.png    # 24-hour contact sheet
echo 3600 > ~/.cache/living-sky/fake_offset            # shift the sky clock +1h (testing); rm to undo
```

## Scenes and seasons
`scene` in `living-sky.conf` picks the land in front of the sky. `core/sky.py` draws the shared layers
(sky gradient and twilight glow, stars, sun, moon, clouds) and the weather; `core/scenes.py` paints the land.

Every scene starts from a painted picture (generated with Google Gemini) that is traced **once** into layers,
so an hourly render only loads files and relights them:
- `lake`: `tools/trace_ridges.py` -> `art/lake/mtn_alpha.png`, `mtn_shade.png`, `shore.json`, `waves.png`;
  recoloured per facet, with water reflections.
- `forest`, `city`, `camp`: `tools/trace_scenes.py` crops `art/<scene>/source.jpg` to 16:10, cuts the sky out
  (pixels near the painted sky colour that connect to the top edge; below the treeline only where the
  column is open sky all the way up, so no pockets) and removes the sky tint from the antialiased edge,
  giving `fg.webp` (RGBA, lossless). Extras: `camp/tent.png` (the lamp-lit canvas), `forest/larch.png`,
  `city/windows.json` and `lamps.json` (115 windows, 10 street lamps).

At render time each picture is relit from the sun's altitude: a cool, deep version at night, a brighter one
by day, a warm tint around sunrise and sunset, and sky-coloured haze on the distant parts. On top:
- `forest`: valley mist around sunrise and sunset, chimney smoke on cold evenings, the cabin window glowing
  after dark with light spilling onto the slope; larches gold in autumn.
- `city`: the share of lit windows follows the hour (most around 21:00, few after 03:00) and the set changes
  every hour (some cool TV/monitor light); sky reflections on the glass by day, lamps and bloom at night.
- `camp`: the painting is a night scene; by day it is lifted and the tent's lamp-lit canvas turns plain khaki
  with a shadowed doorway. From dusk to dawn the fire burns (flames change shape every hour, embers rise,
  the clearing glows); smoke always; fireflies on summer nights.

Every scene is drawn at 1920x1200, then fitted to the primary monitor (`sky.fit_screen`): cropped to the
screen's shape around the scene's focus (`scenes.FOCUS`: wider screens lose mostly sky from the top, narrower
ones the sides) and scaled to its exact size, so GNOME shows it 1:1 and the cards' frost lines up. Renders for
other sizes are cached with the size in the name (`<slot>...-3440x1440.png`).

`pixel = on` turns any scene into pixel art: the finished wallpaper is reduced to 4x4 blocks and 14 levels per
channel with ordered (Bayer) dithering, so gradients stay smooth (renders cached as `<slot>...-px.png`).

Seasons work through colour and light rather than stickers. `season_info` gives smooth weights for the
four seasons from the day of the year and the hemisphere (`season = auto`; always summer within 15° of the
equator) or a fixed season set by hand, and `season_tint` shifts each scene's colours by a few percent:
fresher in spring, warmer in summer, amber in autumn, crisp and cool in winter; the forest's larches turn
gold in autumn. Snow lies only when it is snowing (weather), when `season = winter`, or in an auto winter
above 45° latitude: on the lake it settles on the lit upper facets of the peaks (a blue-grey dusting on
shaded faces) with frost along the shore; in the forest on the bough tops, the open hills and the cabin roof;
in the city along each flat roof and ledge; at the camp on the boughs, the tent ridge and the clearing
(melted around the fire).
Renders are cached per scene and hand-set season (`<slot>.png` for the lake, `<slot>-<scene>[-<season>].png`),
so a change of either is a new file and GNOME picks it up. `tools/scenesheet.py`, `tools/seasonsheet.py`
and `tools/daysheet.py --scene` draw the preview images.

## Colours
`colors` in `living-sky.conf` picks the accent pair: `auto` (accents follow the time of day), one of five pastel
sets (`lavender`, `sakura`, `mint`, `peach`, `ocean`), or your own `#primary, #secondary`.
The primary colours the clock, the glob pet and highlights; the secondary colours the weekday and
other second accents. `core/sky.py` tunes the pair for each hourly slot in OKLCH, keeping the hue:
- night: a little calmer (−8% chroma, −3% lightness)
- blue hour: hue nudged up to 4° cooler; golden hour: up to 6° warmer and +5% chroma
- daytime (light cards): more chroma and mid lightness, darkened only until it reads
  (3:1 for the clock, 3.3:1 for the weekday), the way Catppuccin Latte's accents work.
Changing `colors` takes effect within ~15 s: the engine notices the palette's `colors` tag doesn't match
and `sky.py` rewrites just the palette (no re-render). `tools/colorsheet.py` draws `art/demos/colors.jpg`.

## Glob pets
Glob is the pet system; `glob = mimi | pip | bun | nyx | cubo | ember | random | scene | off` in
`living-sky.conf` picks one (`lua/glob/pick.lua`: `random` is a pet of the day, never the same two days running;
`scene` matches the wallpaper). The engine re-checks every 5 s and restarts itself when the answer changes
(a new day, or a new scene).
`lua/glob/core.lua` holds everything pets share (behaviour, accessories, drawing, the panel export);
each pet file passes its looks and personality to it (`return dofile(core){ ... }`), and the panel
draws the same pet with `pets/core.js` + `pets/<pet>.js`. Demo images live in `art/glob/<pet>/`.
How the five differ and how to write one: [`lua/glob/README.md`](../lua/glob/README.md).
What follows describes the shared behaviour, with Mimi's timings (the defaults).
- Home is the top-right of the clock card, which is why the stack starts at y=108 when it's on (room for its notes, umbrella and hops below the GNOME top bar).
- Moods:
  - music: headphones and notes, while any media player is Playing
  - asleep 00–06 h, stretching until sunrise + 30 min, drowsy 22–24 h, otherwise awake
    (blinks, breathes, glances, hops)
- Weather: umbrella for rain or storm, scarf for snow or ≤5 °C, haze for fog.
- Sunglasses in strong sun: current UV ≥3, a clear or partly cloudy sky and the sun above 15°, or clear and ≥30 °C.
- Masks by US AQI: 101–150 surgical, 151–200 N95, over 200 respirator. Above 100 it also sneezes now and then.
- Idle actions every 15–40 s while it sits awake: hop, wobble, sway, curious "?", heart, look-around,
  and a sneeze when AQI is over 100. It does no actions while it's wandering, and it only sets off
  when it's idle and you're not typing.
- Typing follows any keyboard live: the presence helper sees key presses through XInput2 raw events
  (python-xlib ≥ 0.17) or the X RECORD extension, and only records that *a* key went down, never which.
  Without either, the laptop keyboard's i8042 counter in `/proc/interrupts` is used. It stops about
  1.5 s after you do.
- Presence: `core/glob-presence.py` is event-driven (D-Bus, no polling) and writes `~/.cache/living-sky/presence`.
  - Music state changes are seen in under 0.5 s.
  - It naps after 5 min with no input and startles "!" when you're back.
  - Conky starts it when it's missing, and it exits when living-sky isn't running.
- Ideas partly from miflow13/mochi-desktop (no code or art copied):
  - **Panel clicks:** left-click pokes it (hop or squish), a double-click gives a heart. There's no menu.
  - **New random emotes:** wave, coffee (mostly in the morning), side-eye, a dance burst.
  - **Media:** a video playing (browser, VLC, mpv) means it **watches**, with screen glow and popcorn.
    Music players and music sites mean **dancing** with headphones.
  - **Focused app** (coarse category from X11 `WM_CLASS`, no titles): typing in a terminal shows `>_`
    on its laptop, in a code editor `</>`. With Files focused it hurries to the clock card and searches
    with a magnifier, again every few seconds while Files stays focused.
  - **CPU ≥ 90 °C:** "this is fine", with little flames and a calm coffee.
  - Commands go panel → brain through `~/.cache/living-sky/glob_cmd`.
  - Ideas for later are in `TODO.md`.
- **Snacks:** every 20–30 min it eats a little rice-cake treat on its own (it waits while asleep, busy or grumpy).
- **Grumpy:**
  - **Woken up:** a double-click while it's asleep wakes it for 10 min. It's grumpy the whole time
    (brows, frown, a pulsing 💢), huffs at clicks, gets sleepy in the last 2 min, then goes back to sleep.
  - **Ignored:** after 2 h of you-at-the-PC time with no click, it sulks and side-eyes everything.
    Time away and its sleep don't count. The next click gets a "hmph", then a grudging heart.
    The counter is kept in `~/.cache/living-sky/glob_state`, so restarts don't reset it.
- At the top of each hour it hops with sparkles.
- Pet errors, if any, go to `~/.cache/living-sky/glob.err`.
- Every 6–15 min it floats along the left margin to another perch:
  - top-left of the clock card
  - peeking from behind a card
  - peeking out under the last card
- conky redraws at 4 fps (`update_interval = 0.25`). The cards are cached and re-rendered once per second,
  so this costs about +0.4% of one core. Stats are still sampled at 1 Hz.
- `glob = off` in `living-sky.conf` hides it; also set `update_interval = 1.0` in `conky.conf` to drop the extra frames.
- Testing: `echo "music,rain,peek_cpu" > ~/.cache/living-sky/glob_force` (see the header of `lua/glob/mimi.lua`
  for the tokens), then `rm` it.
