"""Foreground scenes for the living sky (`scene = lake | forest | city | camp` in living-sky.conf).

The sky (gradient, glow, stars, sun, moon, clouds) and the weather are shared and drawn by sky.py; a scene
paints the land in front of it. Every scene is a painted picture (generated with Google Gemini), traced once
into layers in art/<scene>/ and relit here for the hour, the season and the weather:

  lake    mountains over a lake with reflections (art/lake/, traced by tools/trace_ridges.py;
          drawn by sky.layer_mountains / layer_lake)
  forest  rolling pine hills with a cabin: valley mist at dawn and dusk, the cabin window glows after
          dark and the chimney smokes on cold evenings, larches turn gold in autumn
  city    a skyline whose windows light up in the evening and go dark through the night (a different set
          every hour), street lamps along the avenue, sky reflections on the glass by day
  camp    a tent and a campfire in a forest clearing: the fire burns from dusk to dawn (flames, embers,
          smoke, firelight), only embers by day; fireflies on summer nights

The others are traced by tools/trace_scenes.py into art/<scene>/fg.webp (the land with the sky cut out, RGBA)
plus a few masks / positions. Each is relit from its painted light: night is a cool deep version, day a
brighter warmer one, dusk a warm tint, with sky-coloured haze on the distant parts.

Seasons work through colour and light: e['season_w'] blends the seasons (sky.season_info). Snow (e['snow'],
0..1) lies only when it is snowing, when winter is set by hand, or in high-latitude winters.

A scene is a function (img, e, S) -> img: img is the float RGB image so far (H, W, 3), e the sky info
(sun_alt, sun_az, hour, day_seed, season_w, snow, ...) and S the sky module (keyed, smooth, over, screen,
C, sky_cols, proj, snow_col, snowy, season_tint, noise_field, YY, XX, W, H).
"""
import json
import os
import numpy as np
import cv2
from PIL import Image

SCENES = ('lake', 'forest', 'city', 'camp')
SEASONS = ('spring', 'summer', 'autumn', 'winter')
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'art')
LUMA = np.array([0.299, 0.587, 0.114], np.float32)


def render(name, img, e, S):
    return {'lake': lake, 'forest': forest, 'city': city, 'camp': camp}.get(name, lake)(img, e, S)


_cache = {}


def _asset(scene, name):
    """A traced layer from art/<scene>/ (cached): image -> float array (RGBA or mask), .json -> data."""
    key = (scene, name)
    if key not in _cache:
        path = os.path.join(ART, scene, name)
        if name.endswith('.json'):
            _cache[key] = json.load(open(path))
        else:
            _cache[key] = np.asarray(Image.open(path), np.float32) / 255
    return _cache[key]


def _fg(scene):
    px = _asset(scene, 'fg.webp')
    return px[..., :3], px[..., 3]


def _relight(base, light, twilight, night_k, day_k, dusk_k, lift=0.0):
    """The painted land, relit: night (cool, dark) -> day (bright), with a warm tint around sunrise/set."""
    lum = (base @ LUMA)[..., None]
    night = base * np.array(night_k, np.float32)
    day = np.clip(base * np.array(day_k, np.float32) + lift * lum, 0, 1)
    col = night * (1 - light) + day * light
    return _mix(col, np.clip(base * np.array(dusk_k, np.float32), 0, 1), twilight * 0.65), lum


def _haze(col, hor, m):
    return col * (1 - m[..., None]) + hor[None, None, :] * m[..., None]


def _seasons(col, e, light, autumn=(1.08, 0.98, 0.86), k_aut=0.25, k_spr=0.28):
    w = e.get('season_w') or {}
    if w.get('autumn', 0) > 0.05 and light > 0.05:
        col = _mix(col, np.clip(col * np.array(autumn, np.float32), 0, 1), k_aut * w['autumn'] * light)
    if w.get('spring', 0) > 0.05 and light > 0.05:
        col = _mix(col, np.clip(col * np.array([0.96, 1.12, 0.94], np.float32), 0, 1), k_spr * w['spring'] * light)
    return col


def _snow_on(col, mask, snow, snow_c, k=0.85):
    a = np.clip(mask, 0, 1)[..., None] * snow * k
    return col * (1 - a) + snow_c[None, None, :] * a


def _tops(lum, blur=1.5, gain=2.2):
    """Upward-facing edges (tops of boughs, roofs, ledges): where it gets darker going down."""
    gy = cv2.Sobel(cv2.GaussianBlur(lum, (0, 0), blur), cv2.CV_32F, 0, 1, ksize=5)
    return np.clip(gy * gain, 0, 1)


def _smoke(S, img, hor, x, y, rise, drift, n, r0, r1, k, blur):
    puffs = np.zeros((S.H, S.W), np.float32)
    for i in range(n):
        t = i / (n - 1)
        cv2.circle(puffs, (int(x + drift * t + 0.3 * drift * np.sin(t * 5 + 0.5) * t), int(y - rise * t)),
                   int(r0 + (r1 - r0) * t), float(0.55 * (1 - t) + 0.08), -1, cv2.LINE_AA)
    return S.over(img, _mix(hor, S.C(210, 212, 222), 0.35), np.clip(cv2.GaussianBlur(puffs, (0, 0), blur), 0, 1) * k)


def _poly_mask(S, polys, ss=2):
    """Antialiased mask of filled polygons (lists of (x, y) points), supersampled."""
    m = np.zeros((S.H * ss, S.W * ss), np.uint8)
    pts = [np.round(np.asarray(p, np.float32) * ss).astype(np.int32) for p in polys]
    if pts:
        cv2.fillPoly(m, pts, 255, cv2.LINE_AA)
    return cv2.resize(m, (S.W, S.H), interpolation=cv2.INTER_AREA).astype(np.float32) / 255


def _mix(a, b, k):
    return a * (1 - k) + b * k


def lake(img, e, S):
    img = S.layer_mountains(img, e)
    return S.layer_lake(img, e)


# ---------------------------------------------------------------- forest
CABIN_WIN = (482, 708, 502, 732)        # the cabin's window
CHIMNEY = (424.0, 646.0)


def forest(img, e, S):
    alt = e['sun_alt']
    hor = S.sky_cols(alt)[2]
    light = float(S.smooth(-8, 10, alt))
    dark = float(S.smooth(-2, -8, alt))
    twilight = float(S.smooth(-12, -2, alt) * S.smooth(10, 0, alt))
    snow, snow_c = S.snowy(e), S.snow_col(alt)
    w = e.get('season_w') or {}
    base, alpha = _fg('forest')
    col, lum = _relight(base, light, twilight, (0.42, 0.44, 0.62), (1.22, 1.38, 1.05), (1.15, 0.92, 0.98), 0.04 * light)
    far = cv2.GaussianBlur(np.clip((680.0 - S.YY) / 260.0, 0, 1) * (alpha > 0.5), (0, 0), 10)
    col = _haze(col, hor, far * (0.16 + 0.25 * light + 0.14 * twilight))
    if w.get('autumn', 0) > 0.05 and light > 0.05:       # larches turn gold
        gold = np.clip(np.stack([lum[..., 0] * 1.9 + 0.12, lum[..., 0] * 1.35 + 0.04, lum[..., 0] * 0.45], -1), 0, 1)
        col = _mix(col, gold, _asset('forest', 'larch.png')[..., None] * 0.85 * w['autumn'] * light)
    col = _seasons(col, e, light)
    if snow > 0:                                         # snow on bough tops, open hillsides and the cabin roof
        smooth_lum = cv2.GaussianBlur(lum[..., 0], (0, 0), 8)
        hills = (np.clip((smooth_lum - 0.11) / 0.16, 0, 1) * np.clip((S.YY - 490.0) / 110.0, 0, 1)
                 * np.clip((1120.0 - S.YY) / 60.0, 0, 1))
        roof = _poly_mask(S, [[(322, 795), (478, 650), (488, 662), (336, 795)], [(478, 650), (544, 795), (532, 795), (476, 666)]])
        tops = np.clip(_tops(lum[..., 0], 2.5, 1.6) - 0.15, 0, 1)
        col = _snow_on(col, np.maximum.reduce([tops * 0.75, hills * 0.7, roof]), snow, snow_c)
    img = img * (1 - alpha[..., None]) + col * alpha[..., None]
    mist = float(S.smooth(-6, -1, alt) * S.smooth(12, 3, alt))   # valley mist around sunrise and sunset
    if mist > 0:
        band = np.exp(-((S.YY - 670.0) / 85.0) ** 2) * 0.6 + np.exp(-((S.YY - 860.0) / 95.0) ** 2) * 0.45
        img = S.over(img, _mix(hor, S.C(236, 236, 246), 0.3), band * 0.34 * mist)
    cold = max(dark, w.get('winter', 0), w.get('autumn', 0) * 0.6)
    if cold > 0.3:                                       # chimney smoke on cold evenings
        img = _smoke(S, img, hor, CHIMNEY[0], CHIMNEY[1], 95, 44, 10, 5, 17, 0.48 * cold, 4.5)
    if dark > 0:                                         # the window glows, light spills onto the slope
        x0, y0, x1, y1 = CABIN_WIN
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        warm = S.C(255, 196, 114)
        glow = np.exp(-(((S.XX - cx) / 56) ** 2 + ((S.YY - cy) / 42) ** 2)) * 0.36
        spill = np.exp(-(((S.XX - cx) / 72) ** 2 + ((S.YY - cy - 98) / 24) ** 2)) * 0.22
        img = S.screen(img, warm, (glow + spill) * dark)
        img = S.over(img, warm, _poly_mask(S, [[(x0, y0), (x1, y0), (x1, y1), (x0, y1)]]) * dark)
    return img


# ---------------------------------------------------------------- city
def _lit_share(hour):
    """Share of windows lit, by local hour."""
    table = [(0, 0.16), (1, 0.09), (3, 0.04), (5, 0.05), (6.5, 0.14), (8, 0.06), (17, 0.06), (18.5, 0.28),
             (21, 0.32), (23, 0.24), (24, 0.16)]
    for (h0, v0), (h1, v1) in zip(table, table[1:]):
        if hour <= h1:
            return v0 + (v1 - v0) * (hour - h0) / (h1 - h0)
    return 0.22


def city(img, e, S):
    alt = e['sun_alt']
    hor = S.sky_cols(alt)[2]
    light = float(S.smooth(-8, 10, alt))
    dark = float(S.smooth(-1, -8, alt))
    twilight = float(S.smooth(-12, -2, alt) * S.smooth(10, 0, alt))
    hour = float(e.get('hour', 12.0))
    snow, snow_c = S.snowy(e), S.snow_col(alt)
    base, alpha = _fg('city')
    col, lum = _relight(base, light, twilight, (0.36, 0.39, 0.56), (1.28, 1.32, 1.36), (1.22, 0.96, 1.06), 0.06 * light)
    far = (np.clip((lum[..., 0] - 0.25) / 0.18, 0, 1) * np.clip((850.0 - S.YY) / 350.0, 0, 1) * (alpha > 0.5))
    col = _haze(col, hor, cv2.GaussianBlur(far, (0, 0), 8) * (0.15 + 0.25 * light + 0.15 * twilight))
    col = _seasons(col, e, light, k_aut=0.3, k_spr=0.0)
    if snow > 0:                                         # a line of snow on every flat roof and ledge
        gy = cv2.Sobel(lum[..., 0], cv2.CV_32F, 0, 1, ksize=3)
        edges = np.clip(-gy * 3.5, 0, 1) * ((S.YY > 360) & (S.YY < 1050))
        flat = cv2.dilate(cv2.erode(edges, np.ones((1, 11), np.uint8)), np.ones((2, 7), np.uint8))
        col = _snow_on(col, np.clip(cv2.GaussianBlur(flat, (0, 0), 0.8) * 1.4, 0, 1) * (alpha > 0.8), snow, snow_c, 0.78)
    img = img * (1 - alpha[..., None]) + col * alpha[..., None]

    # windows: a different set lit every hour (most around 21:00); sky reflections by day
    rng = np.random.default_rng(int(e.get('day_seed', 1)) * 24 + int(hour))
    share = _lit_share(hour) * (0.25 + 0.75 * dark)
    lit, tv, refl = (np.zeros((S.H, S.W), np.float32) for _ in range(3))
    for (x, y, ww, wh) in _asset('city', 'windows.json'):
        if rng.random() < share:
            cv2.rectangle(tv if rng.random() < 0.15 else lit, (x, y), (x + ww, y + wh), 1.0, -1)
        elif dark < 0.7 and rng.random() < 0.45:
            cv2.rectangle(refl, (x, y), (x + ww, y + wh), 1.0, -1)
    warm, cool = S.C(255, 212, 136), S.C(220, 232, 255)
    if dark < 0.7:
        img = S.over(img, hor * 0.75 + S.C(200, 215, 240) * 0.25, refl * 0.36 * (1 - dark))
    img = S.over(img, warm, lit * (0.55 + 0.35 * dark))
    img = S.over(img, cool, tv * (0.45 + 0.30 * dark))
    if dark > 0:                                         # window bloom and street lamps
        lamps = np.zeros((S.H, S.W), np.float32)
        for lx, ly in _asset('city', 'lamps.json'):
            cv2.circle(lamps, (lx, ly), 4, 1.0, -1, cv2.LINE_AA)
        glow = cv2.GaussianBlur(lit, (0, 0), 7) * 0.36 + np.clip(cv2.GaussianBlur(lamps, (0, 0), 9) * 3.2 + lamps, 0, 1)
        img = S.screen(img, warm, np.clip(glow * dark, 0, 1))
        img = S.screen(img, cool, np.clip(cv2.GaussianBlur(tv, (0, 0), 7) * 0.25 * dark, 0, 1))
    return img


# ---------------------------------------------------------------- camp
FIRE = (1182.0, 1005.0)                 # the base of the flames: on the logs in the stone ring


def _flame(x, yb, w, h, lean):
    """A flame tongue: base (x, yb), tip h above, leaning by `lean` px."""
    return [(x - w, yb), (x - w * 0.9, yb - h * 0.35), (x - w * 0.35 + lean * 0.5, yb - h * 0.7), (x + lean, yb - h),
            (x + w * 0.4 + lean * 0.4, yb - h * 0.62), (x + w * 0.95, yb - h * 0.3), (x + w, yb)]


def _poly_blob(cx, cy, rx, ry, n=16):
    return [(cx + rx * np.cos(2 * np.pi * k / n), cy + ry * np.sin(2 * np.pi * k / n)) for k in range(n)]


def camp(img, e, S):
    alt = e['sun_alt']
    hor = S.sky_cols(alt)[2]
    light = float(S.smooth(-8, 10, alt))
    dark = float(S.smooth(2, -6, alt))
    fire = float(S.smooth(4, -3, alt))                  # the fire burns from dusk to dawn
    snow, snow_c = S.snowy(e), S.snow_col(alt)
    w = e.get('season_w') or {}
    FX, FY = FIRE
    base, alpha = _fg('camp')
    tent = _asset('camp', 'tent.png')[..., None]        # the lamp-lit canvas
    lum = (base @ LUMA)[..., None]

    # the art is painted at night: by day lift it, at night deepen it away from the fire
    day = np.clip(base * (1.0 + 1.15 * light) + np.array([0.04, 0.07, 0.03], np.float32) * light * lum * 2.5, 0, 1)
    far = np.clip(np.sqrt(((S.XX - FX) / 480.0) ** 2 + ((S.YY - FY) / 290.0) ** 2), 0, 1)[..., None]
    col = base * (1 - light) * (1 - 0.25 * (1 - light) * far) + day * light
    # the tent lamp is off by day: the lit canvas becomes plain khaki like the rest of the tent
    # (the unlit side panel is about lum x (0.61, 0.57, 0.49); the brightest part, the doorway, becomes a
    # shadowed opening)
    shade = np.where(lum > 0.4, 0.4 - (lum - 0.4) * 0.9, lum)
    khaki = np.clip(shade * np.array([0.61, 0.57, 0.49], np.float32) / 0.4 * 0.42 * (1.0 + 1.15 * light), 0, 1)
    col = _mix(col, khaki, np.clip(tent * 1.6, 0, 1) * light)
    distant = np.clip((740.0 - S.YY) / 260.0, 0, 1) * (np.abs(S.XX - 960.0) < 620.0)
    col = _haze(col, hor, cv2.GaussianBlur(distant.astype(np.float32), (0, 0), 12) * (0.14 + 0.24 * light))
    col = _seasons(col, e, light, autumn=(1.14, 0.96, 0.78), k_aut=0.35, k_spr=0.25)
    if snow > 0:                                         # snow on boughs, the outer clearing and the tent ridge
        melt = 1 - np.exp(-(((S.XX - FX) / 195.0) ** 2 + ((S.YY - FY) / 76.0) ** 2)) * fire
        ground = (np.clip((S.YY - 890.0) / 140.0, 0, 1) * (1 - tent[..., 0])
                  * cv2.GaussianBlur((lum[..., 0] > 0.08).astype(np.float32), (0, 0), 4))
        roof = _poly_mask(S, [[(432, 658), (705, 650), (700, 672), (432, 680)]])
        tops = np.clip(_tops(lum[..., 0], 2.5, 1.6) - 0.15, 0, 1) * (S.YY > 140)
        col = _snow_on(col, np.maximum.reduce([tops * 0.75, ground * 0.65, roof * 0.85]) * melt, snow, snow_c, 0.82)
    img = img * (1 - alpha[..., None]) + col * alpha[..., None]

    flick = np.random.default_rng(int(e.get('day_seed', 1)) * 24 + int(e.get('hour', 0)))   # this hour's flames
    if fire > 0:
        g1 = np.exp(-(((S.XX - FX) / 220) ** 2 + ((S.YY - FY) / 85) ** 2))
        g2 = np.exp(-(((S.XX - FX) / 560) ** 2 + ((S.YY - FY + 30) / 260) ** 2)) * 0.16
        img = S.screen(img, S.C(255, 138, 52), np.clip((g1 * 0.62 + g2) * fire, 0, 1))
        flames = [_flame(FX + (k - 2) * 16 + flick.uniform(-4, 4), FY, 16 - abs(k - 2) * 2.2,
                         (68 - abs(k - 2) * 13) * flick.uniform(0.85, 1.15), flick.uniform(-9, 9)) for k in range(5)]
        for colr, sc in ((S.C(235, 86, 36), 1.0), (S.C(255, 168, 56), 0.70), (S.C(255, 240, 185), 0.38)):
            polys = [[(FX + (px - FX) * sc, FY - (FY - py) * sc) for px, py in f] for f in flames]
            img = S.over(img, colr, _poly_mask(S, polys) * fire)
        emb = np.zeros((S.H, S.W), np.float32)           # embers rising
        for _ in range(28):
            cv2.circle(emb, (int(FX + flick.uniform(-65, 65)), int(FY - flick.uniform(40, 270))),
                       int(flick.integers(1, 3)), float(flick.uniform(0.6, 1.0)), -1, cv2.LINE_AA)
        img = S.screen(img, S.C(255, 206, 118), np.clip(cv2.GaussianBlur(emb, (0, 0), 3.0) * 1.8 + emb, 0, 1) * fire)
    else:                                                # by day: embers
        img = S.over(img, S.C(175, 75, 32), _poly_mask(S, [_poly_blob(FX, FY - 2, 34, 8)]) * 0.45)
    img = _smoke(S, img, hor, FX, 835, 350, 28, 15, 7, 29, 0.18 + 0.22 * fire, 7)
    if dark > 0.3 and w.get('summer', 0) > 0.3 and snow < 0.2:     # fireflies on summer nights
        ff = np.zeros((S.H, S.W), np.float32)
        for _ in range(30):
            fx = flick.uniform(220, 540) if flick.random() < 0.5 else flick.uniform(1400, 1740)
            cv2.circle(ff, (int(fx), int(flick.uniform(760, 1100))), 1, float(flick.uniform(0.6, 1.0)), -1, cv2.LINE_AA)
        img = S.screen(img, S.C(230, 248, 140), np.clip(cv2.GaussianBlur(ff, (0, 0), 4.5) * 5 + ff, 0, 1) * dark)
    return img
