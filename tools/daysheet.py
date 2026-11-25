#!/usr/bin/env python3
"""Review aid: contact sheet of the sky renders.
  daysheet.py 2026-11-22 out.png            24 hourly frames (HH:30), 6x4
  daysheet.py 2026-11-22 out.png --moon     8 midnight frames, 3.7 days apart
  --scene dunes                             a scene other than the configured one
  out.jpg                                   JPEG (smaller), any other extension: PNG
"""
import datetime as dt, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
day, out = sys.argv[1], sys.argv[2]
moon = '--moon' in sys.argv
scene = sys.argv[sys.argv.index('--scene') + 1] if '--scene' in sys.argv else None
d0 = dt.datetime.strptime(day, '%Y-%m-%d')
if moon:
    times = [d0 + dt.timedelta(days=3.69 * i, hours=23, minutes=30) for i in range(8)]
    cols = 4
else:
    times = [d0 + dt.timedelta(hours=h, minutes=30) for h in range(24)]
    cols = 6
tmp = tempfile.mkdtemp()

def one(t):
    f = os.path.join(tmp, t.strftime('%Y%m%d%H%M') + '.png')
    subprocess.run([sys.executable, os.path.join(HERE, '..', 'core', 'sky.py'), '--at', t.strftime('%Y-%m-%d %H:%M'),
                    '--out', f] + (['--scene', scene] if scene else []), check=True, capture_output=True)
    return t, f

with ThreadPoolExecutor(6) as ex:
    res = list(ex.map(one, times))
tw, th = 400, 250
rows = (len(res) + cols - 1) // cols
sheet = Image.new('RGB', (cols * tw, rows * th))
dr = ImageDraw.Draw(sheet)
for i, (t, f) in enumerate(res):
    x, y = (i % cols) * tw, (i // cols) * th
    sheet.paste(Image.open(f).resize((tw, th)), (x, y))
    dr.text((x + 8, y + 6), t.strftime('%d %b %H:%M'), fill=(255, 255, 255))
sheet.save(out, quality=88, optimize=True) if out.lower().endswith(('.jpg', '.jpeg')) else sheet.save(out)
print(out)
