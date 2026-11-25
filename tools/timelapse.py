#!/usr/bin/env python3
"""A day of the living sky as an animated GIF (for the README).
  tools/timelapse.py [YYYY-MM-DD] [out.gif]     default: today, art/demos/sky-day.gif
Frames: every 30 min, plus every 15 min within an hour of sunrise and sunset (where the sky changes
most). Rendered with core/sky.py --at (your location's real sun and moon), 6 at a time.
"""
import datetime as dt, json, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SKY = os.path.join(HERE, '..', 'core', 'sky.py')
day = sys.argv[1] if len(sys.argv) > 1 else dt.date.today().isoformat()
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '..', 'art', 'demos', 'sky-day.gif')
W, H = 640, 400

d0 = dt.datetime.strptime(day, '%Y-%m-%d')
info = json.loads(subprocess.run([sys.executable, SKY, '--info', '--at', d0.strftime('%Y-%m-%d 12:00')],
                                 capture_output=True, text=True, check=True).stdout)
def at(hm, fallback=12):
    if ':' not in hm or not hm.replace(':', '').isdigit():   # polar day / night: no sunrise or sunset
        return d0.replace(hour=fallback, minute=0)
    h, m = map(int, hm.split(':'))
    return d0.replace(hour=h, minute=m)
rise, sset = at(info['rise'], 6), at(info['set'], 18)
times = set(d0 + dt.timedelta(minutes=30 * i) for i in range(48))
for ev in (rise, sset):
    times |= set(ev + dt.timedelta(minutes=m) for m in range(-60, 61, 15))
times = sorted(t for t in times if t.date() == d0.date())
tmp = tempfile.mkdtemp()

def one(t):
    f = os.path.join(tmp, t.strftime('%H%M') + '.png')
    subprocess.run([sys.executable, SKY, '--at', t.strftime('%Y-%m-%d %H:%M'), '--wx', 'partly:25', '--out', f],
                   check=True, capture_output=True)
    return t, f

with ThreadPoolExecutor(6) as ex:
    frames = list(ex.map(one, times))

try:
    path = subprocess.run(['fc-match', '-f', '%{file}', 'JetBrains Mono:bold'], capture_output=True, text=True).stdout
    font = ImageFont.truetype(path, 18)
except Exception:
    font = ImageFont.load_default()

imgs = []
for t, f in frames:
    im = Image.open(f).convert('RGB').resize((W, H), Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    label = t.strftime('%H:%M')
    dr.text((W - 16, H - 14), label, font=font, fill=(255, 255, 255), anchor='rb', stroke_width=2, stroke_fill=(20, 20, 30))
    imgs.append(im.quantize(colors=112, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG))
durations = [600 if (abs((t - rise).total_seconds()) <= 3600 or abs((t - sset).total_seconds()) <= 3600) else 350
             for t, _ in frames]
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=durations, loop=0, optimize=True)
print(out, len(imgs), 'frames', round(os.path.getsize(out) / 1e6, 2), 'MB')
