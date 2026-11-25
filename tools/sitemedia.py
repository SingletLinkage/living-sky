#!/usr/bin/env python3
"""Website-only images, derived from the README demos (art/demos stays the source of truth).
  tools/sitemedia.py            -> art/site/
Run after tools/cardshots.sh or tools/scenesheet.py --pixel. Writes:
  art/site/cards/<id>.jpg   each card in the glass style only: night | day (the left half of
                            art/demos/cards/<id>.jpg, which is glass night | glass day | cards night | cards day)
  art/site/pixel-wide.jpg   the pixel-art sheet (art/demos/pixel.jpg: a row per scene, night | dusk) re-laid as two
                            wide rows, every scene at night then at dusk, so it spans the page like the other sheets
"""
import glob, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, '..', 'art')
OUT = os.path.join(ART, 'site')
PANEL, GAP = 388, 12                  # tools/cardshots.sh: four panels, 12 px apart (card + 14 px margins)
TILE_W, TILE_H = 480, 300             # tools/scenesheet.py --pixel: tile size


def cards():
    os.makedirs(os.path.join(OUT, 'cards'), exist_ok=True)
    made = []
    for path in sorted(glob.glob(os.path.join(ART, 'demos', 'cards', '*.jpg'))):
        im = Image.open(path).convert('RGB')
        glass = im.crop((0, 0, 2 * PANEL + GAP, im.height))
        out = os.path.join(OUT, 'cards', os.path.basename(path))
        glass.save(out, quality=90, optimize=True, progressive=True)
        made.append(out)
    return made


def pixel_wide():
    src = Image.open(os.path.join(ART, 'demos', 'pixel.jpg')).convert('RGB')
    rows = src.height // TILE_H                      # one row per scene
    wide = Image.new('RGB', (rows * TILE_W, 2 * TILE_H))
    for r in range(rows):
        for c in range(2):                           # 0 = night, 1 = dusk
            tile = src.crop((c * TILE_W, r * TILE_H, (c + 1) * TILE_W, (r + 1) * TILE_H))
            wide.paste(tile, (r * TILE_W, c * TILE_H))
    out = os.path.join(OUT, 'pixel-wide.jpg')
    wide.save(out, quality=90, optimize=True, progressive=True)
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for p in cards() + [pixel_wide()]:
        print(os.path.relpath(p, os.path.join(HERE, '..')))
