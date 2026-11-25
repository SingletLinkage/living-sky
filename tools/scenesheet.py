#!/usr/bin/env python3
"""Preview strips of each scene through a day (art/demos/scene-<name>.png).
  tools/scenesheet.py [YYYY-MM-DD]      night, dawn, midday and dusk for every scene, side by side
  tools/scenesheet.py [YYYY-MM-DD] --pixel   the pixel-art look instead -> art/demos/pixel.jpg (night + dusk)
Rendered with core/sky.py --at for your location's real sun and moon, with a few clouds.
"""
import datetime as dt, json, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SKY = os.path.join(HERE, '..', 'core', 'sky.py')
sys.path.insert(0, os.path.join(HERE, '..', 'core'))
import scenes  # noqa: E402

pixel = '--pixel' in sys.argv
args = [a for a in sys.argv[1:] if a != '--pixel']
day = args[0] if args else dt.date.today().isoformat()
d0 = dt.datetime.strptime(day, '%Y-%m-%d')
info = json.loads(subprocess.run([sys.executable, SKY, '--info', '--at', d0.strftime('%Y-%m-%d 12:00')],
                                 capture_output=True, text=True, check=True).stdout)


def at(hm, plus=0, fallback=12):
    if ':' not in hm or not hm.replace(':', '').isdigit():   # polar day / night: no sunrise or sunset
        return d0.replace(hour=fallback, minute=0)
    h, m = map(int, hm.split(':'))
    return d0.replace(hour=h, minute=m) + dt.timedelta(minutes=plus)


moments = [('night', d0.replace(hour=1, minute=30)), ('dawn', at(info['rise'], -10, fallback=6)),
           ('midday', d0.replace(hour=12, minute=30)), ('dusk', at(info['set'], 5, fallback=18))]
tmp = tempfile.mkdtemp()


def one(job):
    scene, label, t = job
    f = os.path.join(tmp, '%s-%s.png' % (scene, label))
    subprocess.run([sys.executable, SKY, '--at', t.strftime('%Y-%m-%d %H:%M'), '--scene', scene, '--wx', 'partly:25',
                    '--out', f] + (['--pixel'] if pixel else []), check=True, capture_output=True)
    return job, f


if pixel:
    moments = [moments[0], moments[3]]           # night and dusk
jobs = [(s, label, t) for s in scenes.SCENES for label, t in moments]
with ThreadPoolExecutor(4) as ex:
    done = dict(ex.map(one, jobs))
try:
    font = ImageFont.truetype(subprocess.run(['fc-match', '-f', '%{file}', 'JetBrains Mono:bold'],
                                             capture_output=True, text=True).stdout, 17)
except Exception:
    font = ImageFont.load_default()
TW, TH = 480, 300
if pixel:                                        # one sheet: a row per scene, night | dusk
    sheet = Image.new('RGB', (TW * 2, TH * len(scenes.SCENES)))
    dr = ImageDraw.Draw(sheet)
    for r, s in enumerate(scenes.SCENES):
        for c, (label, t) in enumerate(moments):
            sheet.paste(Image.open(done[(s, label, t)]).convert('RGB').resize((TW, TH), Image.NEAREST), (c * TW, r * TH))
            dr.text((c * TW + 14, r * TH + TH - 14), '%s · %s' % (s, label), font=font, fill=(255, 255, 255),
                    anchor='lb', stroke_width=2, stroke_fill=(20, 20, 30))
    out = os.path.join(HERE, '..', 'art', 'demos', 'pixel.jpg')
    sheet.save(out, quality=90, optimize=True)
    print(out)
    sys.exit(0)
for s in scenes.SCENES:
    strip = Image.new('RGB', (TW * len(moments), TH))
    dr = ImageDraw.Draw(strip)
    for i, (label, t) in enumerate(moments):
        strip.paste(Image.open(done[(s, label, t)]).convert('RGB').resize((TW, TH), Image.LANCZOS), (i * TW, 0))
        dr.text((i * TW + 14, TH - 14), '%s  %s' % (label, t.strftime('%H:%M')), font=font, fill=(255, 255, 255),
                anchor='lb', stroke_width=2, stroke_fill=(20, 20, 30))
    out = os.path.join(HERE, '..', 'art', 'demos', 'scene-%s.jpg' % s)
    strip.save(out, quality=90, optimize=True, progressive=True)
    print(out)
