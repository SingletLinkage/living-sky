#!/usr/bin/env python3
"""One-shot: extract reusable layers from the original night wallpaper.

Writes into art/lake/:
  mtn_alpha.png  L  mountain coverage (skyline matte, antialiased), y < WATER
  mtn_shade.png  L  normalised mountain luminance (facets / ridges / depth)
  shore.json        per-column y of the shoreline (ground below it)
  waves.png      L  wave-line strokes on the water (alpha)

sky.py recolours these per hour (gradient map), so every render keeps the
exact hand-drawn composition of the original art.
"""
import json, os
import numpy as np
import cv2
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'art', 'lake')
SRC = os.path.join(ASSETS, 'wallpaper-static.png')
W, H, WATER = 1920, 1200, 778

im = np.asarray(Image.open(SRC).convert('RGB')).astype(np.float32)
lum = im @ np.array([0.299, 0.587, 0.114], np.float32)
# remove stars / small bright specks (grey opening) for analysis
clean = cv2.morphologyEx(lum, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))

# ---------------------------------------------------------------- skyline matte
alpha = np.zeros((H, W), np.float32)
alpha[WATER:, :] = 0
edge = np.zeros(W, np.int32)
Y0, Y1 = 430, 700
for x in range(W):
    col = cv2.GaussianBlur(clean[Y0:Y1, max(0, x - 1):x + 2], (1, 3), 0).mean(axis=1)
    d = col[3:] - col[:-3]                       # drop over 3 px
    i = int(np.argmin(d)) + 1
    edge[x] = Y0 + i
# stars right above the ridge can fool the detector into thin upward spikes
med = np.array([np.median(edge[max(0, x - 12):x + 13]) for x in range(W)]).astype(np.int32)
edge = np.where(edge < med - 4, med, edge)

for x in range(W):
    e = edge[x]
    sky = clean[e - 6:e - 3, x].mean()
    mtn = clean[e + 3:e + 6, x].mean()
    span = max(sky - mtn, 4.0)
    for y in range(e - 3, e + 4):
        alpha[y, x] = np.clip((sky - lum[y, x]) / span, 0, 1)
    alpha[e + 4:WATER, x] = 1.0
    alpha[:e - 3, x] = 0.0

# ---------------------------------------------------------------- shade map
reg = clean.copy()
m = alpha > 0.5
lo, hi = np.percentile(reg[m], 0.5), np.percentile(reg[m], 99.7)
shade = np.clip((reg - lo) / (hi - lo), 0, 1)
# recover near-edge pixels (opening darkens thin rims): use raw lum there
shade = np.where(alpha < 1, np.clip((np.minimum(lum, hi) - lo) / (hi - lo), 0, 1), shade)
shade[WATER:, :] = 0
shade = cv2.bilateralFilter(shade.astype(np.float32), 5, 0.05, 3)
shade *= (alpha > 0)

# ---------------------------------------------------------------- shore
# ground (near-black) below the lake; find first row from bottom upward that
# is brighter than the ground band -> shoreline.
shore = np.zeros(W, np.float32)
for x in range(W):
    col = clean[1000:H, x]
    g = col[-15:].mean()
    above = np.where(col > g + 14)[0]
    shore[x] = 1000 + (above.max() + 1 if len(above) else 150)
shore = cv2.GaussianBlur(shore.reshape(1, -1), (0, 0), 6).ravel()

# ---------------------------------------------------------------- waves
bg = cv2.GaussianBlur(lum, (0, 0), 9)
hp = lum - bg
wm = ((hp > 9) & (np.arange(H)[:, None] > 1040)).astype(np.uint8)
yy = np.arange(H)[:, None]
wm[(yy >= shore[None, :] - 2)[:, :] & np.ones((1, W), bool)] = 0
wm[995:1118, 440:650] = 0                         # moon reflection
n, lab, st, _ = cv2.connectedComponentsWithStats(wm, 8)
keep = np.zeros_like(wm)
for i in range(1, n):
    x, y, w, h, a = st[i]
    if w >= 40 and w > 4 * h:
        keep[lab == i] = 1
waves = np.clip(hp / 40.0, 0, 1) * cv2.dilate(keep, np.ones((3, 3), np.uint8))

def save(arr, name):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), 'L').save(os.path.join(ASSETS, name))

save(alpha, 'mtn_alpha.png')
save(shade, 'mtn_shade.png')
save(waves, 'waves.png')
with open(os.path.join(ASSETS, 'shore.json'), 'w') as f:
    json.dump([round(float(v), 1) for v in shore], f)
print('skyline y range', edge.min(), edge.max(), 'shore range', shore.min().round(), shore.max().round(),
      'wave comps', int(keep.sum()))
