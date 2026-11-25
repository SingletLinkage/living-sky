# Glob: GNOME panel extension (GNOME 42, X11)

Shows your living-sky glob pet (Mimi by default) in the top panel.
- **Brain:** `lua/glob/<pet>.lua`, running inside the living-sky conky desktop.
  It writes `~/.cache/living-sky/glob.json` with the pet id, mood, weather gear, mask, sunglasses,
  current action and palette. It rewrites the file on change, with a heartbeat every 30 s.
- **Body:** `pets/<pet>.js` draws the same pet with cairo (`newAnim`, `drawPet`). `extension.js` checks
  the JSON every frame (a cheap stat; re-read only on change) and repaints at 5 fps.
  Blinks, glances and breathing are local; actions are mirrored from the desktop pet.
- **When living-sky isn't running:** the file goes stale after 90 s and the pet hides itself.
- **Click it:** a left-click pokes it; a double-click gives a heart. While it's asleep, a double-click
  wakes it for 10 min, and it's grumpy about it. A right-click opens the Living Sky settings window.
  Clicks go to the brain through `~/.cache/living-sky/glob_cmd`, so the desktop and panel pet react together.

Adding a pet: write `pets/<id>.js` and register it in `PETS` at the top of `extension.js`.

Install: `./install.sh --extension` from the project root. That links this folder to
`~/.local/share/gnome-shell/extensions/glob@living-sky` and enables it.
- On X11, restart GNOME Shell after changes: Alt+F2, then `r`, then Enter. Windows stay open.
- Logs: `journalctl --user -b /usr/bin/gnome-shell | grep -i glob`
- Enable / disable: `gnome-extensions enable|disable glob@living-sky`
- Offline previews: `gjs tools/render.js /tmp/mimi.png [~/.cache/living-sky/glob.json]`,
  `gjs tools/showcase.js ../../art/glob/mimi/showcase.png`

Two builds from the same drawing code:
- **GNOME 42–44:** this folder as it is (legacy `imports.*` modules). Tested on GNOME 42.
- **GNOME 45+:** `../esm/extension.js` + `../esm/metadata.json`, plus `pets/*.js` turned into ES modules by
  `../build-esm.py` (output: `gnome-extension/build/glob@living-sky`, not in git). `install.sh --extension`
  picks the right one from `gnome-shell --version`. The pet drawing was verified as ES modules with gjs;
  the 45+ entry point itself has only been syntax-checked so far (no GNOME 45+ machine to load it on).
