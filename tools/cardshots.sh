#!/usr/bin/env bash
# One image per card: art/demos/cards/<id>.png, a strip of glass-night, glass-day, cards-night, cards-day.
# Uses the running desktop: turns every card on, switches style and sky clock for a couple of minutes,
# renders `living-sky preview --demo` (placeholders for personal details) and puts everything back.
set -eu
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
LS="$ROOT/bin/living-sky"
C="${XDG_CACHE_HOME:-$HOME/.cache}/living-sky"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/living-sky/living-sky.conf"
TMP=$(mktemp -d)
orig=$(cat "$C/theme" 2>/dev/null || echo glass)
cp "$CONF" "$TMP/conf.bak"
trap 'cp "$TMP/conf.bak" "$CONF"; rm -f "$C/fake_offset"; "$LS" start "$orig" >/dev/null' EXIT
sed -i 's/^\(card_[a-z]*\) *= *off/\1 = on/' "$CONF"

for when in night day; do
    if [ "$when" = day ]; then
        python3 -c "import datetime as d; n = d.datetime.now(); t = (n + d.timedelta(days=1)).replace(hour=12, minute=30, second=0); print(int((t - n).total_seconds()))" > "$C/fake_offset"
    fi
    for theme in glass cards; do
        t=$(date +%s)
        "$LS" start "$theme" >/dev/null
        until pgrep -f "$C/$theme.conky.conf" >/dev/null && [ -f "$C/detected" ] && [ "$(stat -c %Y "$C/detected")" -ge "$t" ]; do sleep 1; done
        if [ "$when" = day ]; then
            key=$(python3 -c "import datetime as d, time; print(d.datetime.fromtimestamp(time.time() + $(cat "$C/fake_offset")).strftime('%Y%m%d%H00'))")
            until grep -q "^$key" "$C/current" 2>/dev/null; do sleep 2; done
        fi
        sleep 20                                   # some sparkline history
        "$LS" preview "$theme" --demo >/dev/null
        cp "$C/preview-$theme.png" "$TMP/$theme-$when.png"; cp "$C/preview-$theme.rects" "$TMP/$theme-$when.rects"
    done
    rm -f "$C/fake_offset"
done

python3 - "$TMP" "$ROOT/art/demos/cards" <<'PY'
import os, sys
from PIL import Image
tmp, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
variants = ['glass-night', 'glass-day', 'cards-night', 'cards-day']
rects = {v: {l.split()[0]: tuple(map(int, l.split()[1:])) for l in open(os.path.join(tmp, v + '.rects'))} for v in variants}
for cid in rects['glass-night']:
    crops = []
    for v in variants:
        if cid not in rects[v]:
            continue
        x, y, w, h = rects[v][cid]
        top = 54 if cid == list(rects[v])[0] else 10            # room for the pet on the first card
        crops.append(Image.open(os.path.join(tmp, v + '.png')).convert('RGB').crop((x - 14, y - top, x + w + 14, y + h + 16)))
    W, H = sum(c.width for c in crops) + 12 * (len(crops) - 1), max(c.height for c in crops)
    strip = Image.new('RGB', (W, H), (17, 17, 27))
    px = 0
    for c in crops:
        strip.paste(c, (px, 0)); px += c.width + 12
    strip.save(os.path.join(out, cid + '.jpg'), quality=92, optimize=True)
    print(os.path.join(out, cid + '.jpg'))
PY
