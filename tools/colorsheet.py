#!/usr/bin/env python3
"""Demo sheet of the colour sets across the day (art/demos/colors.jpg).
  tools/colorsheet.py [out.png]
Each row is a `colors =` choice; each column a moment of the day, with the card flavour
and the slightly tuned accents core/sky.py would use then (clock = primary, weekday = secondary,
the blob = Mimi's body colour).
"""
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'core'))
import sky  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'art', 'demos', 'colors.jpg')
ROWS = ['auto'] + list(sky.COLOR_SETS)
COLS = [('night', -30, 0, '02:30'), ('blue hour', -6, 250, '18:05'), ('golden hour', 2, 250, '17:40'),
        ('morning', 10, 120, '08:30'), ('midday', 40, 180, '12:30')]
CW, CH, M, LW, HEAD = 230, 120, 28, 150, 96


def font(family, size):
    try:
        path = subprocess.run(['fc-match', '-f', '%{file}', family], capture_output=True, text=True).stdout
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def rgb(h, a=255):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (a,)


def mix(h, k, to=(255, 255, 255)):
    c = rgb(h)
    return tuple(round(c[i] + (to[i] - c[i]) * k) for i in range(3)) + (255,)


W = M * 2 + LW + len(COLS) * CW + (len(COLS) - 1) * 12
H = M + HEAD + len(ROWS) * CH + (len(ROWS) - 1) * 12 + M
img = Image.new('RGBA', (W, H), (17, 17, 27, 255))
d = ImageDraw.Draw(img)
f_title, f_sub = font('JetBrains Mono:bold', 30), font('JetBrains Mono', 15)
f_head, f_row = font('JetBrains Mono:bold', 15), font('JetBrains Mono:bold', 17)
f_clock, f_day, f_small = font('Bebas Neue', 54), font('JetBrains Mono:bold', 14), font('JetBrains Mono', 12)

d.text((M, M - 4), 'living-sky colours', font=f_title, fill=(180, 190, 254))
d.text((M, M + 38), 'living-sky.conf  colors = auto | lavender | sakura | mint | peach | ocean | #primary, #secondary'
       '   ·   each set is nudged slightly with the sun', font=f_sub, fill=(166, 173, 200))
for j, (label, *_rest) in enumerate(COLS):
    d.text((M + LW + j * (CW + 12) + 6, M + HEAD - 26), label.upper(), font=f_head, fill=(250, 179, 135))

for i, name in enumerate(ROWS):
    y = M + HEAD + i * (CH + 12)
    d.text((M, y + CH / 2 - 10), name, font=f_row, fill=(205, 214, 244))
    for j, (_label, alt, az, clock) in enumerate(COLS):
        x = M + LW + j * (CW + 12)
        p = sky.palette({'sun_alt': alt, 'sun_az': az}, colors=name)
        light = p['flavour'] == 'latte'
        # card
        card = Image.new('RGBA', (CW, CH))
        cd = ImageDraw.Draw(card)
        top, bot = rgb(p['base'], 240), rgb(p['mantle'], 245)
        for yy in range(CH):
            k = yy / (CH - 1)
            cd.line([(0, yy), (CW, yy)], fill=tuple(round(top[c] + (bot[c] - top[c]) * k) for c in range(4)))
        mask = Image.new('L', (CW, CH), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, CW - 1, CH - 1], 16, fill=255)
        img.paste(card, (x, y), mask)
        d.rounded_rectangle([x, y, x + CW - 1, y + CH - 1], 16, outline=rgb(p['surface1'], 160), width=1)
        # clock (primary), weekday (secondary), date (text)
        d.text((x + 16, y + 16), clock, font=f_clock, fill=rgb(p['accent']))
        d.text((x + 128, y + 24), 'TUESDAY', font=f_day, fill=rgb(p['accent2']))
        d.text((x + 128, y + 44), p['flavour'], font=f_small, fill=rgb(p['overlay1']))
        # Mimi-ish blob in the primary colour (lighter on the light cards, like the real one)
        bx, by = x + CW - 52, y + CH - 44
        body = mix(p['accent'], 0.45) if light else rgb(p['accent'])
        d.ellipse([bx, by, bx + 38, by + 30], fill=body, outline=mix(p['accent'], 0.35, (0, 0, 0)))
        for ex in (bx + 12, bx + 26):
            d.ellipse([ex - 2.5, by + 11, ex + 2.5, by + 17], fill=(30, 30, 43, 255))
        d.text((x + 16, y + CH - 24), '%s  %s' % (p['accent'], p['accent2']), font=f_small, fill=rgb(p['overlay1']))

os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
img.convert('RGB').save(OUT, quality=92, optimize=True)
print(OUT, img.size)
