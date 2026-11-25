#!/usr/bin/env python3
"""Every scene in every season, at mid-morning (art/demos/seasons.jpg).
  tools/seasonsheet.py [YYYY-MM-DD]
Rows: lake, forest, city, camp; columns: spring, summer, autumn, winter.
"""
import datetime as dt, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SKY = os.path.join(HERE, '..', 'core', 'sky.py')
day = sys.argv[1] if len(sys.argv) > 1 else dt.date.today().isoformat()
ROWS, COLS = ['lake', 'forest', 'city', 'camp'], ['spring', 'summer', 'autumn', 'winter']
tmp = tempfile.mkdtemp()


def one(job):
    scene, season = job
    f = os.path.join(tmp, '%s-%s.png' % job)
    subprocess.run([sys.executable, SKY, '--at', day + ' 10:30', '--scene', scene, '--season', season,
                    '--wx', 'partly:25', '--out', f], check=True, capture_output=True)
    return job, f


with ThreadPoolExecutor(4) as ex:
    done = dict(ex.map(one, [(r, c) for r in ROWS for c in COLS]))
try:
    font = ImageFont.truetype(subprocess.run(['fc-match', '-f', '%{file}', 'JetBrains Mono:bold'],
                                             capture_output=True, text=True).stdout, 16)
except Exception:
    font = ImageFont.load_default()
TW, TH = 480, 300
sheet = Image.new('RGB', (TW * len(COLS), TH * len(ROWS)))
dr = ImageDraw.Draw(sheet)
for r, scene in enumerate(ROWS):
    for c, season in enumerate(COLS):
        sheet.paste(Image.open(done[(scene, season)]).convert('RGB').resize((TW, TH), Image.LANCZOS), (c * TW, r * TH))
        dr.text((c * TW + 12, r * TH + TH - 12), '%s · %s' % (scene, season), font=font, fill=(255, 255, 255),
                anchor='lb', stroke_width=2, stroke_fill=(20, 20, 30))
out = os.path.join(HERE, '..', 'art', 'demos', 'seasons.jpg')
sheet.save(out, quality=88, optimize=True)
print(out)
