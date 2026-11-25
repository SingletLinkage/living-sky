#!/usr/bin/env bash
# README screenshots: both card styles, at night (now, if it's dark) and at midday (the sky clock is
# shifted with ~/.cache/living-sky/fake_offset), rendered with `living-sky preview --demo` so the
# Wi-Fi name, IP, place and host name are placeholders.
#   tools/media.sh            -> art/demos/{glass,cards}-{night,day}.jpg (1280 px wide) + *-column.jpg
# Uses the running desktop and switches its theme / sky clock for a minute; everything is put back.
set -eu
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
LS="$ROOT/bin/living-sky"
C="${XDG_CACHE_HOME:-$HOME/.cache}/living-sky"
OUT="$ROOT/art/demos"
mkdir -p "$OUT"
orig=$(cat "$C/theme" 2>/dev/null || echo glass)
trap 'rm -f "$C/fake_offset"; "$LS" start "$orig" >/dev/null' EXIT

wait_running() {                       # theme up, cards loaded, ~20 s of sparkline history
    local t0=$SECONDS
    until pgrep -f "$C/$1.conky.conf" >/dev/null && [ -f "$C/detected" ] \
          && [ "$(stat -c %Y "$C/detected")" -ge "$2" ]; do
        sleep 1; [ $((SECONDS - t0)) -gt 60 ] && { echo "timed out starting $1" >&2; exit 1; }
    done
    sleep 20
}

wait_slot() {                          # the sky slot for the shifted clock is rendered and applied
    local key t0=$SECONDS
    key=$(python3 -c "import datetime as d, time; t = d.datetime.fromtimestamp(time.time() + $1); print(t.strftime('%Y%m%d%H00'))")
    until [ "$(cat "$C/current" 2>/dev/null)" = "$key" ]; do
        sleep 2; [ $((SECONDS - t0)) -gt 180 ] && { echo "timed out waiting for slot $key" >&2; exit 1; }
    done
    sleep 3
}

shot() {                               # shot <theme> <name>
    local png
    png=$("$LS" preview "$1" --demo)
    python3 - "$png" "$OUT/$2.jpg" "$OUT/$2-column.jpg" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
im.resize((1280, round(h * 1280 / w)), Image.LANCZOS).save(sys.argv[2], quality=90, optimize=True)
im.crop((w - 430, 20, w, h - 60)).save(sys.argv[3], quality=90, optimize=True)      # the card column
print(sys.argv[2])
EOF
}

for when in night day; do
    if [ "$when" = day ]; then
        # shift the sky clock to 12:30 tomorrow
        off=$(python3 -c "import datetime as d; n = d.datetime.now(); t = (n + d.timedelta(days=1)).replace(hour=12, minute=30, second=0); print(int((t - n).total_seconds()))")
        echo "$off" > "$C/fake_offset"
    fi
    for theme in glass cards; do
        t=$(date +%s)
        "$LS" start "$theme" >/dev/null
        wait_running "$theme" "$t"
        [ "$when" = day ] && wait_slot "$off"
        shot "$theme" "$theme-$when"
    done
    rm -f "$C/fake_offset"
done
