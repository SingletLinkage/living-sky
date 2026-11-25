# Contributing to living-sky

Thanks for wanting to help! Bug reports, new cards, pets and scenes are all welcome.

## Reporting a bug
Open an issue with the output of `living-sky doctor` (or **Living Sky → System → Diagnostics → Copy**).
It shows what was detected (screen, sensors, GPU, battery), your non-default settings and the recent errors,
and nothing personal beyond what you see in it: check it before posting.

## Getting set up
```sh
git clone https://github.com/SingletLinkage/living-sky ~/living-sky && cd ~/living-sky
./install.sh                 # or ./install.sh --no-deps to only check
living-sky start
```
The code runs from the clone, so edits apply on `living-sky restart` (Lua, conky configs) or on the next
render (Python). Logs: `living-sky logs -f`.

## Before sending a pull request
```sh
ruff check .                 # Python: real errors only (ruff.toml)
python3 -m pytest -q tests   # ~10 s: sky maths, seasons, colour contrast, config editing, every scene renders,
                             # shell and Lua syntax, the GNOME 45+ extension build
shellcheck -S error install.sh uninstall.sh bin/* tools/*.sh   # if you have shellcheck
```
The same checks run on GitHub for every push and pull request (`.github/workflows/ci.yml`, Ubuntu 22.04).
For anything visual, attach a before / after picture: `living-sky preview --demo` (hides your Wi-Fi name,
IP and place) or `python3 core/sky.py --at "2026-06-21 21:30" --scene camp --out /tmp/x.png`.

## Where things are
- **A new card:** `lua/cards/README.md` (one file per card; the card contract is `init / sample / subtitle /
  visible / draw`).
- **A new pet:** `lua/glob/README.md` (the desktop pet) and `gnome-extension/glob@living-sky/README.md` (the
  same pet in the top panel).
- **A new scene:** put a painted picture in `art/<scene>/source.jpg`, add a cut-out recipe to
  `tools/trace_scenes.py` and a relighting function to `core/scenes.py` (see how `camp` does it), then
  regenerate the previews with `tools/scenesheet.py` and `tools/seasonsheet.py`.
- **How it all fits together:** `docs/how-it-works.md`.

## Style
- Plain, readable code with short comments that say *why*; match what is around you.
- Python 3.10, no new dependencies without a good reason (numpy, OpenCV, Pillow, PyGObject are there).
- Lua runs inside conky every frame: keep `draw` cheap and do slow work in `sample` (once a second or less).
- Don't commit generated files from `~/.cache/living-sky` or `gnome-extension/build/`.
