#!/usr/bin/env python3
"""Trace the painted scenes into layers the renderer composites over the live sky (run once per new art).

  tools/trace_scenes.py [camp|forest|city ...]      default: all three

Each scene's source picture is art/<scene>/source.jpg (generated with Google Gemini). It is cropped to
16:10 and scaled to the 1920x1200 canvas, then:
  fg.webp       the land with its own sky cut away: RGBA, the alpha antialiased, and the sky colour
                removed from the half-transparent edge pixels (so no pale halo against a night sky)
  camp          tent.png   the tent's lamp-lit canvas and doorway (dimmed by day)
  forest        larch.png  the yellow-green larches (they turn gold in autumn)
  city          windows.json  [x, y, w, h] of every window;  lamps.json  [x, y] of every street lamp
The lake is traced separately by tools/trace_ridges.py (art/lake/).
"""
import json, os, sys
import numpy as np
import cv2
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, '..', 'art')
W, H = 1920, 1200
YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)


def load(scene):
    im = Image.open(os.path.join(ART, scene, 'source.jpg')).convert('RGB')
    w, h = im.size
    if w / h > W / H:                                  # wider than 16:10: crop the sides
        tw = round(h * W / H)
        im = im.crop(((w - tw) // 2, 0, (w - tw) // 2 + tw, h))
    else:
        th = round(w * H / W)
        im = im.crop((0, h - th, w, h))                # keep the bottom (the land)
    return np.asarray(im.resize((W, H), Image.LANCZOS), np.float32) / 255


def cut_sky(rgb, sky_ref, thresh, below, solid_from, close=0, columns_from=None):
    """Sky = pixels near the reference sky colour(s), connected to the top edge, above `below`.
    sky_ref is (3,) or a per-row profile (H, 3). From row `columns_from` down, a pixel only counts as sky
    if the column above it is sky all the way up (no pockets of sky inside the treeline).
    Returns (decontaminated rgb, alpha)."""
    ref = sky_ref if sky_ref.ndim == 2 else np.broadcast_to(sky_ref, (H, 3))
    diff = np.linalg.norm(rgb - ref[:, None, :], axis=2)
    cand = ((diff < thresh) & (YY < below)).astype(np.uint8)
    _, lab = cv2.connectedComponents(cand, connectivity=4)
    top = set(np.unique(lab[0])) - {0}
    sky = np.isin(lab, list(top)).astype(np.uint8)
    if columns_from is not None:
        open_above = np.cumprod(sky[columns_from:], axis=0) * sky[columns_from - 1][None, :]
        sky[columns_from:] = open_above
    if close:                                          # fill pinholes in the treeline (sky leaking through)
        fg = cv2.morphologyEx(1 - sky, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (close, close)))
        sky = 1 - fg
    a = np.clip(1 - cv2.GaussianBlur(sky.astype(np.float32), (0, 0), 0.9) * 1.15, 0, 1)
    a[solid_from:] = 1
    edge = (a > 0.02) & (a < 0.98)
    out = rgb.copy()
    rows = np.where(edge)[0]
    out[edge] = np.clip((rgb[edge] - ref[rows] * (1 - a[edge, None])) / np.maximum(a[edge, None], 0.15), 0, 1)
    return out, a


def save_rgba(path, rgb, a):
    px = np.dstack([rgb, a[..., None]])
    Image.fromarray((np.clip(px, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(path, lossless=True, method=6)


def save_mask(path, m):
    Image.fromarray((np.clip(m, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').save(path, optimize=True)


def camp():
    rgb = load('camp')
    prof = np.median(rgb[:, 860:1060], axis=1)         # the sky's vertical gradient, from a clear column...
    prof[540:] = np.median(prof[500:540], axis=0)      # ...above the far ridge (below it the column is land)
    fg, a = cut_sky(rgb, prof, 0.06, 685, 690, close=5, columns_from=560)
    save_rgba(os.path.join(ART, 'camp', 'fg.webp'), fg, a)
    r, b = fg[..., 0], fg[..., 2]
    zone = ((XX > 560) & (XX < 920) & (YY > 630) & (YY < 995)).astype(np.float32)
    tent = np.clip((r - b - 0.08) / 0.35, 0, 1) * zone        # the warm, lamp-lit canvas
    save_mask(os.path.join(ART, 'camp', 'tent.png'), tent)
    return 'fg.webp tent.png'


def forest():
    rgb = load('forest')
    sky_col = np.median(np.median(rgb[:420, 700:1200], axis=1)[:300], axis=0)
    fg, a = cut_sky(rgb, sky_col, 0.08, 600, 605)
    save_rgba(os.path.join(ART, 'forest', 'fg.webp'), fg, a)
    r, g, b = fg[..., 0], fg[..., 1], fg[..., 2]
    larch = np.clip((r - b - 0.015) / 0.08, 0, 1) * np.clip((g - b - 0.03) / 0.09, 0, 1) * (YY < 1090)
    save_mask(os.path.join(ART, 'forest', 'larch.png'), cv2.GaussianBlur(larch.astype(np.float32), (0, 0), 1.0))
    return 'fg.webp larch.png'


def city():
    rgb = load('city')
    sky_col = np.median(rgb[:260, 400:1500], axis=(0, 1))
    fg, a = cut_sky(rgb, sky_col, 0.045, 920, 940)
    save_rgba(os.path.join(ART, 'city', 'fg.webp'), fg, a)
    lum = fg @ np.array([0.299, 0.587, 0.114], np.float32)
    # windows: small dark rectangles on the buildings
    rel = (cv2.GaussianBlur(lum, (45, 45), 0) - lum) / np.maximum(cv2.GaussianBlur(lum, (45, 45), 0), 0.08)
    cand = ((rel > 0.065) & (lum < 0.36) & (a > 0.95) & (YY > 460) & (YY < 1055)).astype(np.uint8)
    cand = cv2.morphologyEx(cand, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, _, st, _ = cv2.connectedComponentsWithStats(cand, 4)
    wins = [[int(x + 2), int(y + 2), int(max(4, bw - 4)), int(max(4, bh - 4))]
            for x, y, bw, bh, area in st[1:] if 10 <= bw <= 56 and 12 <= bh <= 74 and area >= 90 and area / (bw * bh) > 0.45]
    # street lamps: narrow dark posts along the avenue
    post = (lum[1085:1125] < 0.09).mean(axis=0) > 0.75
    lamps, x0 = [], None
    for x in range(W + 1):
        on = x < W and post[x]
        if on and x0 is None:
            x0 = x
        elif not on and x0 is not None:
            if 2 <= x - x0 <= 12:
                lamps.append([(x0 + x) // 2, 1072])
            x0 = None
    json.dump(wins, open(os.path.join(ART, 'city', 'windows.json'), 'w'))
    json.dump(lamps, open(os.path.join(ART, 'city', 'lamps.json'), 'w'))
    return 'fg.webp, %d windows, %d lamps' % (len(wins), len(lamps))


if __name__ == '__main__':
    for s in sys.argv[1:] or ['camp', 'forest', 'city']:
        print(s, '->', {'camp': camp, 'forest': forest, 'city': city}[s]())
