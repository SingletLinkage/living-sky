# Glob pets

A glob pet lives on the desktop cards (and, with the GNOME extension, in the top panel). Everything
pets have in common is in `core.lua`; a pet is one small file that describes its looks and personality.

| pet | looks | personality |
|---|---|---|
| `mimi.lua` | soft dome in your primary accent | cheerful, social; asleep 00–06 |
| `pip.lua` | sapphire teardrop | hyper: idle action every 6–14 s, hops, splashes in the rain (no umbrella), startles when poked; short-tempered but forgiving |
| `bun.lua` | a slice of bread with a crust rim | sleepy: naps, slow, snacks every 10–15 min; asleep 22:30–08:30, drowsy after lunch; very grumpy when woken |
| `nyx.lua` | a little cratered moon whose shading follows tonight's real moon phase | nocturnal: asleep while the sun is up (in a nightcap), glows at night, stargazes, cheers at a full moon; shades if woken by day |
| `cubo.lua` | teal rounded cube with glasses | studious: reads, coffee all day, curious, sneezes from AQI 50; asleep 01–07 |

## What the core gives every pet
Perches on the cards and wandering (sink into a card, pop out at another), moods from its sleep
schedule, weather gear, sunglasses, AQI masks, naps when you're away, typing along, Files search,
music / video, "this is fine" when the CPU is hot, panel clicks, grumpiness (woken / ignored),
snacks, the hourly chime, and the state export for the panel. See the header of `core.lua`.

## Writing a pet
```lua
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'
return dofile(dir .. 'core.lua'){
  id = 'fern', name = 'Fern',            -- id = file name = `glob = fern` in living-sky.conf
  size = {18, 15},                       -- half width, half height (px)
  color = 'green',                       -- palette name, nil (= the user's accent) or function(M, light, mix)
  body = function(cr, cx, cy, a, b) ... end,   -- outline path (cairo); default: Mimi's dome
  schedule = function(h, sunrise, sunset) return h < 7 and 'sleep' or 'awake' end,
  pool = {hop = 1, sway = 2, grow = 3},  -- idle actions and their weights
  acts = {grow = 3.0},                   -- the pet's own actions and their durations (s)
  pose = function(an, ap, t, P) end,     -- squash / stretch for its own acts (P.sx, P.sy, P.oy, P.rot)
  eyes = function(eyes, an, ap, mood, st) end,  -- change the eye state for an act
  draw_under = function(E) end,          -- behind the body (a glow)
  draw_body = function(E) end,           -- markings on the body under the face, clipped to it (E.path() re-traces the outline)
  draw_over = function(E) end,           -- over the face (glasses, markings)
  draw_act = function(E, an, ap) end,    -- extras for its own acts
}
```
Every field is optional; `DEFAULTS` at the top of `core.lua` lists them all with Mimi's values
(timings such as `act_every`, `wander_every`, `snack_every`, `blink_every`, `breath`; `poke`,
`rain_gear`, `sneeze_aqi`, `woken_s`, `neglect_s`, `extra_pool`, `shades`).
Drawing hooks get `E`: `cr`, `M` (palette), `t`, the body centre and size (`cx, cy, a, b`), its base
point (`bx, by`), `base` (body colour), `light`, `mood`, `st` (state), the eye layout
(`eyes, ex, ey, fx, fy, gx, gy`, after the face is drawn), `sky` (the sky slot: sunrise, sunset,
`moon_illum`, `moon_phase`, …) and helpers (`rgba, ellipse, rrect, mix, text, path`).

## The panel version
The GNOME extension draws the same pet from the state the desktop writes; behaviour stays in Lua.
Add `gnome-extension/glob@living-sky/pets/<id>.js` with `var def = {...}` using the same hooks in
camelCase (`size, body, breath, blinkEvery, pose, eyes, drawUnder, drawBody, drawOver, drawAct, rainGear`), plus
`swatch` (its colour for the offline tools), `showcase` and `animExtra` (its own moments for the
showcase sheet and GIF). Register the id in `extension.js` (`for (const id of [...])`), in
`../esm/extension.js` (an import + `PETS`), and in `lua/glob/pick.lua` (`PETS`, and `SCENE` if it suits a scene)
so `glob = random` / `scene` can choose it. `tests/test_pets.py` checks the lists match the files.
For the website, add it to `ORDER` in `gnome-extension/build-web.py` and `INFO` in `site/app.js`, then run
`gnome-extension/build-web.py`: the site's playground draws it with the same `pets/<id>.js`.

## Testing and images
- `glob = <id>` in `living-sky.conf`, `living-sky restart`, then force a state with
  `echo "awake,grow" > ~/.cache/living-sky/glob_force` and `living-sky preview`; `rm` the file after.
  Errors go to `~/.cache/living-sky/glob.err`.
- From `gnome-extension/glob@living-sky`:
  `GLOB_PET=<id> gjs tools/showcase.js ../../art/glob/<id>/showcase.png`,
  `GLOB_PET=<id> gjs tools/anim.js /tmp/frames && ../../tools/gif.py /tmp/frames ../../art/glob/<id>/<id>.gif`,
  and add it to `tools/lineup.js` (`art/glob/lineup.png`).
