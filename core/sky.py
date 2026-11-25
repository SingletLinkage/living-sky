#!/usr/bin/env python3
"""Living-sky wallpaper + Catppuccin palette for the current time slot.

Recolours the traced mountain-lake art (art/lake/mtn_*.png, shore.json,
waves.png) for the real sun and moon position at the user's location:
sky gradient, twilight glow, stars + Milky Way, sun, moon with the true
phase, lake reflection with ripples and a glitter path.

  sky.py --now                 render the current slot (if not cached)
  sky.py --now --next          render the upcoming slot (pre-render)
  sky.py --at "2026-11-22 18:30" [--out file.png]   render any moment
  sky.py --info                print location / sun / moon numbers

Cache: ~/.cache/living-sky/<YYYYMMDDHHMM>[-<scene>][-<season set by hand>].png + .lua (palette), 'current'.
Scenes (the land in front of the sky): core/scenes.py; `scene = lake | dunes | forest | city`.
Time can be shifted for testing with ~/.cache/living-sky/fake_offset (seconds).
"""
import argparse, datetime as dt, json, math, os, re, subprocess, sys, time
import numpy as np
import cv2
from PIL import Image
import scenes

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
ASSETS = os.path.join(ROOT, 'art', 'lake')      # the lake scene's traced layers
CONF = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'living-sky', 'living-sky.conf')
if not os.path.exists(CONF):
    CONF = os.path.join(ROOT, 'living-sky.conf.example')
CACHE = os.path.join(os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache'), 'living-sky')
W, H, WATER = 1920, 1200, 778
HORIZON_Y, TOP_Y, CX, KX = 572, 60, 760, 6.0     # sky projection (facing south)
D2R = math.pi / 180

# ================================================================ config / time
def read_conf():
    c = {'lat': '', 'lon': '', 'geo': 'auto', 'interval_min': '60', 'name': '', 'colors': 'auto', 'scene': 'lake',
         'season': 'auto', 'pixel': 'off'}
    try:
        for line in open(CONF):
            # comments: whole-line '#', or ' # ...' after a value (but '#rrggbb' colours stay)
            line = re.sub(r'(^|\s)#(?![0-9a-fA-F]{6}\b).*$', '', line).strip()
            if '=' in line:
                k, v = (s.strip() for s in line.split('=', 1))
                c[k] = v
    except OSError:
        pass
    return c

def now_local():
    off = 0.0
    try:
        off = float(open(os.path.join(CACHE, 'fake_offset')).read().strip() or 0)
    except (OSError, ValueError):
        pass
    return dt.datetime.fromtimestamp(time.time() + off).astimezone()

def slot_start(t, interval):
    m = (t.hour * 60 + t.minute) // interval * interval
    return t.replace(hour=m // 60, minute=m % 60, second=0, microsecond=0)

# ================================================================ location
TZ_DEFAULTS = {'Asia/Kolkata': (22.6, 79.0, 'India'), 'Asia/Calcutta': (22.6, 79.0, 'India')}

def num(v, default=None, lo=None, hi=None):
    """A config number, or `default` when it is missing, not a number or out of range."""
    try:
        x = float(v)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(x):                      # 'inf', 'nan'
        return default
    if (lo is not None and x < lo) or (hi is not None and x > hi):
        return default
    return x

def get_location(conf):
    lat, lon = num(conf.get('lat'), lo=-90, hi=90), num(conf.get('lon'), lo=-180, hi=180)
    if lat is not None and lon is not None:
        return lat, lon, conf.get('name') or 'manual'
    if conf.get('lat') or conf.get('lon'):
        print('living-sky: ignoring lat/lon (need two numbers, -90..90 and -180..180)', file=sys.stderr)
    cache = os.path.join(CACHE, 'location.json')
    cached = None
    try:
        cached = json.load(open(cache))
        if time.time() - os.path.getmtime(cache) < 86400:
            return cached['lat'], cached['lon'], cached.get('name', '')
    except (OSError, ValueError, KeyError):
        pass
    if conf.get('geo', 'auto') != 'off':
        for url, parse in (
            ('https://ipinfo.io/json', lambda j: (*map(float, j['loc'].split(',')), j.get('city', ''))),
            ('https://ipapi.co/json/', lambda j: (float(j['latitude']), float(j['longitude']), j.get('city', ''))),
        ):
            try:
                out = subprocess.run(['curl', '-fsS', '-m', '5', '-A', 'living-sky', url],
                                     capture_output=True, text=True, timeout=8).stdout
                lat, lon, name = parse(json.loads(out))
                os.makedirs(CACHE, exist_ok=True)
                json.dump({'lat': lat, 'lon': lon, 'name': name}, open(cache, 'w'))
                return lat, lon, name
            except Exception:
                continue
    if cached:
        return cached['lat'], cached['lon'], cached.get('name', '')
    tz = ''
    try:
        tz = os.path.realpath('/etc/localtime').split('zoneinfo/')[-1]
    except OSError:
        pass
    if tz in TZ_DEFAULTS:
        return TZ_DEFAULTS[tz]
    # last resort: the time zone's UTC offset gives a rough longitude (15° per hour); mid latitude
    off = dt.datetime.now().astimezone().utcoffset().total_seconds() / 3600
    print('living-sky: no location (set lat/lon in living-sky.conf); guessing from the time zone', file=sys.stderr)
    return 35.0, max(-180.0, min(180.0, off * 15)), ''

# ================================================================ astronomy
def julian(t_utc):
    return t_utc.timestamp() / 86400.0 + 2440587.5

def sun_radec(jd):
    d = jd - 2451545.0
    g = (357.529 + 0.98560028 * d) * D2R
    q = 280.459 + 0.98564736 * d
    L = (q + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g)) * D2R
    e = (23.439 - 0.00000036 * d) * D2R
    ra = math.atan2(math.cos(e) * math.sin(L), math.cos(L))
    dec = math.asin(math.sin(e) * math.sin(L))
    return ra, dec, L

def moon_radec(jd):
    """Schlyter's method with the main perturbation terms (~0.2 deg)."""
    d = jd - 2451543.5
    N = (125.1228 - 0.0529538083 * d) * D2R
    i = 5.1454 * D2R
    w = (318.0634 + 0.1643573223 * d) * D2R
    a, e = 60.2666, 0.054900
    M = ((115.3654 + 13.0649929509 * d) % 360) * D2R
    E = M + e * math.sin(M) * (1 + e * math.cos(M))
    for _ in range(5):
        E = E - (E - e * math.sin(E) - M) / (1 - e * math.cos(E))
    xv, yv = a * (math.cos(E) - e), a * math.sqrt(1 - e * e) * math.sin(E)
    v, r = math.atan2(yv, xv), math.hypot(xv, yv)
    xh = r * (math.cos(N) * math.cos(v + w) - math.sin(N) * math.sin(v + w) * math.cos(i))
    yh = r * (math.sin(N) * math.cos(v + w) + math.cos(N) * math.sin(v + w) * math.cos(i))
    zh = r * (math.sin(v + w) * math.sin(i))
    lon, lat = math.atan2(yh, xh), math.atan2(zh, math.hypot(xh, yh))
    Ms = ((356.0470 + 0.9856002585 * d) % 360) * D2R
    ws = (282.9404 + 4.70935e-5 * d) * D2R
    Ls, Lm = Ms + ws, M + w + N
    D, F = Lm - Ls, Lm - N
    s = math.sin
    lon += D2R * (-1.274 * s(M - 2 * D) + 0.658 * s(2 * D) - 0.186 * s(Ms) - 0.059 * s(2 * M - 2 * D)
                  - 0.057 * s(M - 2 * D + Ms) + 0.053 * s(M + 2 * D) + 0.046 * s(2 * D - Ms)
                  + 0.041 * s(M - Ms) - 0.035 * s(D) - 0.031 * s(M + Ms) - 0.015 * s(2 * F - 2 * D)
                  + 0.011 * s(M - 4 * D))
    lat += D2R * (-0.173 * s(F - 2 * D) - 0.055 * s(M - F - 2 * D) - 0.046 * s(M + F - 2 * D)
                  + 0.033 * s(F + 2 * D) + 0.017 * s(2 * M + F))
    r += -0.58 * math.cos(M - 2 * D) - 0.46 * math.cos(2 * D)
    ecl = (23.4393 - 3.563e-7 * d) * D2R
    xe = math.cos(lon) * math.cos(lat)
    ye = math.sin(lon) * math.cos(lat)
    ze = math.sin(lat)
    ye, ze = ye * math.cos(ecl) - ze * math.sin(ecl), ye * math.sin(ecl) + ze * math.cos(ecl)
    return math.atan2(ye, xe), math.asin(ze), r, lon

def altaz(ra, dec, jd, lat, lon):
    gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)) % 360
    H = (gmst + lon) * D2R - ra
    phi = lat * D2R
    alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(H))
    az = math.atan2(math.sin(H), math.cos(H) * math.sin(phi) - math.tan(dec) * math.cos(phi)) + math.pi
    return alt / D2R, (az / D2R) % 360

def enu(alt, az):
    a, z = alt * D2R, az * D2R
    return np.array([math.cos(a) * math.sin(z), math.cos(a) * math.cos(z), math.sin(a)])

def ephemeris(t_local, lat, lon):
    jd = julian(t_local.astimezone(dt.timezone.utc))
    sra, sdec, slon = sun_radec(jd)
    salt, saz = altaz(sra, sdec, jd, lat, lon)
    mra, mdec, mr, mlon = moon_radec(jd)
    malt, maz = altaz(mra, mdec, jd, lat, lon)
    malt -= math.degrees(math.asin(1 / mr)) * math.cos(malt * D2R)      # topocentric parallax
    vs, vm = enu(salt, saz), enu(malt, maz)
    psi = math.acos(max(-1, min(1, float(vs @ vm))))                   # elongation
    illum = (1 - math.cos(psi)) / 2
    waxing = ((mlon - slon) / D2R) % 360 < 180
    # bright-limb direction in screen space (right = increasing azimuth, up = altitude)
    t = vs - (vs @ vm) * vm
    e_az = np.array([math.cos(maz * D2R), -math.sin(maz * D2R), 0.0])
    e_al = np.array([-math.sin(malt * D2R) * math.sin(maz * D2R),
                     -math.sin(malt * D2R) * math.cos(maz * D2R), math.cos(malt * D2R)])
    limb = (float(t @ e_az), -float(t @ e_al))
    n = math.hypot(*limb) or 1
    return {'sun_alt': salt, 'sun_az': saz, 'moon_alt': malt, 'moon_az': maz,
            'illum': illum, 'waxing': waxing, 'limb': (limb[0] / n, limb[1] / n),
            'age_deg': ((mlon - slon) / D2R) % 360}

def sun_events(day_local, lat, lon):
    """Sunrise / sunset (alt = -0.833) for the local calendar day, 2-min scan."""
    t0 = day_local.replace(hour=0, minute=0, second=0, microsecond=0)
    rise = sset = None
    prev = None
    for k in range(0, 24 * 30 + 1):
        t = t0 + dt.timedelta(minutes=2 * k)
        jd = julian(t.astimezone(dt.timezone.utc))
        ra, dec, _ = sun_radec(jd)
        alt = altaz(ra, dec, jd, lat, lon)[0] + 0.833
        if prev is not None:
            if prev < 0 <= alt and rise is None:
                rise = t - dt.timedelta(minutes=2 * alt / (alt - prev))
            if prev >= 0 > alt:
                sset = t - dt.timedelta(minutes=2 * alt / (alt - prev))
        prev = alt
    return rise, sset

def phase_name(illum, waxing, age):
    if age < 8 or age > 352: return 'new moon'
    if 172 < age < 188: return 'full moon'
    if abs(age - 90) < 8: return 'first quarter'
    if abs(age - 270) < 8: return 'last quarter'
    if illum < 0.5: return ('waxing' if waxing else 'waning') + ' crescent'
    return ('waxing' if waxing else 'waning') + ' gibbous'

# ================================================================ helpers
def C(*rgb):
    return np.array(rgb, np.float32) / 255.0

def keyed(table, x):
    """Piecewise-linear interpolation of a list of (key, value) pairs."""
    if x <= table[0][0]: return table[0][1]
    for (k0, v0), (k1, v1) in zip(table, table[1:]):
        if x <= k1:
            f = (x - k0) / (k1 - k0)
            if isinstance(v0, tuple):
                return tuple(a + (b - a) * f for a, b in zip(v0, v1))
            return v0 + (v1 - v0) * f
    return table[-1][1]

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def screen(base, col, a):
    """screen-blend colour `col` (3,) with per-pixel strength a (H,W)."""
    return 1 - (1 - base) * (1 - col[None, None, :] * a[..., None])

def over(base, col, a):
    return base * (1 - a[..., None]) + col * a[..., None] if col.ndim == 3 else \
        base * (1 - a[..., None]) + col[None, None, :] * a[..., None]

def proj(alt, az):
    daz = (az - 180 + 540) % 360 - 180
    x = CX + KX * daz
    if alt >= 0:
        y = HORIZON_Y - (HORIZON_Y - TOP_Y) * (min(alt, 90) / 90) ** 0.85
    else:
        y = HORIZON_Y - alt * 12
    return x, y

YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)

# ================================================================ colour script
# Sky colours keyed by sun altitude (deg): zenith, mid, horizon
SKY = [
    (-18, (C(15, 15, 27), C(34, 37, 60), C(84, 88, 118))),
    (-12, (C(20, 23, 44), C(44, 48, 84), C(104, 96, 136))),
    (-7, (C(30, 40, 82), C(70, 78, 134), C(168, 128, 160))),
    (-3, (C(48, 66, 124), C(110, 116, 178), C(236, 164, 152))),
    (0, (C(66, 96, 160), C(146, 158, 210), C(250, 188, 148))),
    (4, (C(84, 126, 196), C(168, 186, 226), C(250, 210, 170))),
    (10, (C(94, 144, 214), C(176, 200, 238), C(244, 224, 196))),
    (22, (C(92, 148, 226), C(164, 200, 244), C(214, 230, 248))),
    (50, (C(84, 144, 232), C(148, 192, 246), C(204, 226, 250))),
]
GLOW = [  # twilight glow around the sun's azimuth: colour, strength
    (-14, (C(80, 50, 90), 0.0)), (-9, (C(120, 70, 120), 0.25)), (-4, (C(240, 130, 130), 0.55)),
    (0, (C(255, 160, 100), 0.75)), (4, (C(255, 190, 130), 0.55)), (10, (C(255, 220, 170), 0.25)),
    (18, (C(255, 240, 220), 0.0)),
]
# mountains: gradient map stops (shade 0, 0.5, 1)
MTN = [
    (-18, (C(16, 16, 26), C(32, 34, 50), C(54, 56, 77))),
    (-10, (C(20, 21, 36), C(40, 42, 66), C(70, 70, 102))),
    (-5, (C(30, 30, 56), C(60, 60, 98), C(112, 100, 148))),
    (-1, (C(42, 38, 66), C(84, 76, 114), C(176, 132, 150))),
    (4, (C(52, 50, 84), C(104, 98, 140), C(214, 160, 150))),
    (10, (C(62, 66, 104), C(116, 120, 166), C(222, 196, 186))),
    (22, (C(72, 84, 128), C(124, 142, 186), C(206, 214, 236))),
    (50, (C(76, 90, 136), C(130, 150, 194), C(212, 222, 242))),
]
WATER_TINT = [
    (-18, (C(18, 20, 34), 0.45)), (-6, (C(30, 36, 66), 0.40)), (0, (C(60, 60, 96), 0.38)),
    (10, (C(70, 98, 150), 0.35)), (40, (C(72, 110, 168), 0.32)),
]
GROUND = [(-18, C(14, 13, 22)), (-4, C(22, 20, 36)), (6, C(38, 36, 58)), (30, C(48, 52, 80))]
# snow lit by the sky: moonlit blue at night, lilac at twilight, white by day
SNOW = [(-18, C(58, 62, 92)), (-8, C(86, 90, 128)), (-2, C(176, 166, 196)), (4, C(226, 222, 236)), (15, C(240, 244, 250))]

def snow_col(alt):
    return keyed(SNOW, alt)

SEASON_NAMES = ('winter', 'spring', 'summer', 'autumn')

def snowy(e):
    """How much snow lies on the land, 0..1 (see season_info)."""
    return float(e.get('snow', 0.0))

def season_info(v, t, lat, wx=None):
    """-> (name, weights, snow). `season` = auto blends the seasons smoothly through the year
    (no jumps on the 1st of a month; the southern hemisphere is six months on; always summer
    within 15° of the equator); a season set by hand is fixed. Snow lies when it is snowing now,
    when winter is set by hand, or in an auto winter at high latitudes (above 45°); elsewhere an
    auto winter is just crisper, cooler light."""
    v = (v or 'auto').strip().lower()
    if v in SEASON_NAMES:
        w = {k: float(k == v) for k in SEASON_NAMES}
        snow = 1.0 if v == 'winter' else 0.0
    elif abs(lat) < 15:
        w = {k: float(k == 'summer') for k in SEASON_NAMES}
        snow = 0.0
    else:
        doy = t.timetuple().tm_yday + (182 if lat < 0 else 0)
        ph = ((doy - 15) % 365.25) / 365.25 * 4          # 0 mid-winter (15 Jan), 1 spring, 2 summer, 3 autumn
        i, f = int(ph) % 4, ph - int(ph)
        f = f * f * (3 - 2 * f)
        w = {k: 0.0 for k in SEASON_NAMES}
        w[SEASON_NAMES[i]] += 1 - f
        w[SEASON_NAMES[(i + 1) % 4]] += f
        snow = w['winter'] if abs(lat) >= 45 else 0.0
    if (wx or {}).get('kind') in ('snow', 'sleet'):
        snow = 1.0
    name = max(w, key=w.get)
    return name, w, snow

# subtle seasonal light / colour, as tints mixed in by season weight: (colour, strength)
SEASON_TINT = {
    'spring': {'ground': (C(70, 96, 74), 0.30), 'mtn': (C(150, 176, 170), 0.06), 'water': (C(90, 130, 130), 0.10),
               'air': (C(214, 236, 222), 0.05), 'forest': (C(150, 186, 120), 0.14), 'city': (C(210, 226, 220), 0.04)},
    'summer': {'ground': (C(60, 72, 66), 0.10), 'mtn': (C(0, 0, 0), 0.0), 'water': (C(70, 130, 170), 0.08),
               'air': (C(255, 236, 206), 0.04), 'forest': (C(0, 0, 0), 0.0), 'city': (C(255, 226, 196), 0.05)},
    'autumn': {'ground': (C(122, 88, 60), 0.35), 'mtn': (C(196, 150, 120), 0.07), 'water': (C(120, 100, 90), 0.10),
               'air': (C(255, 206, 170), 0.07), 'forest': (C(184, 120, 70), 0.20), 'city': (C(240, 196, 176), 0.06)},
    'winter': {'ground': (C(150, 160, 186), 0.18), 'mtn': (C(170, 186, 214), 0.10), 'water': (C(120, 140, 176), 0.12),
               'air': (C(214, 226, 250), 0.07), 'forest': (C(150, 160, 186), 0.10), 'city': (C(206, 220, 246), 0.06)},
}

def season_tint(e, col, role, light=1.0):
    """Mix the season's tint for `role` into colour(s) col, scaled by daylight `light`."""
    w = e.get('season_w') or {'summer': 1.0}
    out = col
    for k, wk in w.items():
        if wk <= 0:
            continue
        tint, strength = SEASON_TINT[k][role]
        a = strength * wk * light
        if a > 0:
            out = out * (1 - a) + tint * a
    return out

def sky_cols(a):
    return keyed(SKY, a)

# ================================================================ layers
def layer_sky(e):
    zen, mid, hor = sky_cols(e['sun_alt'])
    t = np.clip(YY / HORIZON_Y, 0, 1.3)[..., None]
    f1 = smooth(0, 0.55, t)
    f2 = smooth(0.5, 1.0, t)
    img = zen * (1 - f1) + mid * f1
    img = img * (1 - f2) + hor * f2
    # twilight glow near the sun's azimuth
    gcol, gs = keyed(GLOW, e['sun_alt'])
    if gs > 0:
        sx, _ = proj(max(e['sun_alt'], 0), e['sun_az'])
        dx = (XX - sx) / 900.0
        dy = (YY - HORIZON_Y) / 330.0
        g = np.exp(-(dx * dx + dy * dy) * 1.6) * gs
        img = screen(img, gcol, g)
        # faint "belt of Venus" on the opposite side
        ox, _ = proj(0, (e['sun_az'] + 180) % 360)
        if -6 < e['sun_alt'] < 4:
            b = np.exp(-(((XX - ox) / 1100) ** 2 + ((YY - (HORIZON_Y - 90)) / 120) ** 2)) * 0.18
            img = screen(img, C(236, 170, 200), b)
    return img

def noise_field(seed, scales=(220, 90, 36, 14)):
    rng = np.random.default_rng(seed)
    acc = np.zeros((H, W), np.float32)
    amp = 1.0
    for s in scales:
        n = rng.standard_normal((H // s + 3, W // s + 3)).astype(np.float32)
        n = cv2.resize(n, (W + 3 * s, H + 3 * s), interpolation=cv2.INTER_CUBIC)[:H, :W]
        acc += n * amp
        amp *= 0.55
    acc -= acc.min(); acc /= acc.max()
    return acc

def layer_night(img, e):
    night = float(smooth(-6, -15, e['sun_alt']))
    if e.get('wx'):
        night *= 1 - 0.85 * min(1.0, e['wx']['cover'] / 100)
    if night <= 0.01:
        return img
    rng = np.random.default_rng(42)
    # a bright moon washes out faint stars and the Milky Way (as it does for real)
    wash = e['illum'] * float(np.clip(e['moon_alt'] / 25.0, 0, 1))
    # Milky Way: a soft band from lower-left to upper-right (as in the original art)
    p0, p1 = np.array([120, 560.0]), np.array([1800, 20.0])
    d = p1 - p0; d /= np.linalg.norm(d)
    nrm = np.array([-d[1], d[0]])
    off = (XX - p0[0]) * nrm[0] + (YY - p0[1]) * nrm[1]
    along = (XX - p0[0]) * d[0] + (YY - p0[1]) * d[1]
    off = off + 70 * np.sin(along / 260.0)
    band = np.exp(-(off / 150.0) ** 2)
    nf = noise_field(7)
    mwk = night * (1 - 0.75 * wash)
    mw = band * (0.35 + 0.9 * nf ** 2) * mwk
    img = screen(img, C(120, 92, 150), mw * 0.5)
    img = screen(img, C(70, 80, 140), np.exp(-(off / 320.0) ** 2) * 0.16 * mwk)
    # stars: steep brightness distribution, most faint, a handful bright
    star = np.zeros((H, W, 3), np.float32)
    def put(x, y, col, b):
        xi, yi = int(x), int(y)
        if 0 <= xi < W - 1 and 0 <= yi < H - 1:
            fx, fy = x - xi, y - yi
            star[yi, xi] += col * b * (1 - fx) * (1 - fy)
            star[yi, xi + 1] += col * b * fx * (1 - fy)
            star[yi + 1, xi] += col * b * (1 - fx) * fy
            star[yi + 1, xi + 1] += col * b * fx * fy
    tints = [C(255, 255, 255), C(205, 230, 255), C(255, 228, 210), C(200, 225, 255)]
    fade = 0.45 * wash                                   # faint stars vanish under moonlight
    for _ in range(380):
        x, y = rng.uniform(0, W), rng.uniform(0, 640)
        b = 0.22 + 1.9 * rng.uniform() ** 4             # magnitude-like falloff
        b = b - fade * 0.5 if b < 0.6 else b
        if b > 0.05:
            put(x, y, tints[rng.integers(4)], b * night)
    # faint dust of stars inside the band
    k = 0
    while k < 340:
        x, y = rng.uniform(0, W), rng.uniform(0, 640)
        if rng.uniform() < band[int(y), int(x)]:
            b = rng.uniform(0.15, 0.55) * (1 - fade)
            put(x, y, C(235, 225, 255), b * night)
            k += 1
    star = cv2.GaussianBlur(star, (0, 0), 0.7) * 3.0
    # a few bright stars with a soft round glow (no cross spikes)
    glow = np.zeros((H, W), np.float32)
    for _ in range(6):
        x, y = rng.uniform(60, W - 60), rng.uniform(30, 520)
        put(x, y, C(255, 255, 255), 1.4 * night)
        xi, yi = int(x), int(y)
        glow[yi, xi] += 1.0
    glow = cv2.GaussianBlur(glow, (0, 0), 2.4) * 40
    img = screen(img, C(200, 225, 255), np.clip(glow, 0, 1) * 0.30 * night)
    return 1 - (1 - img) * (1 - np.clip(star, 0, 1))

def disc_mask(cx, cy, r):
    d = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
    return np.clip(r + 0.5 - d, 0, 1), d

def layer_sun(img, e):
    alt = e['sun_alt']
    if alt < -3:
        return img
    x, y = proj(alt, e['sun_az'])
    low = float(smooth(14, 0, alt))
    col = C(255, 250, 236) * (1 - low) + C(255, 172, 96) * low
    glow = C(255, 236, 200) * (1 - low) + C(255, 150, 90) * low
    m, d = disc_mask(x, y, 30)
    g = gloom(e)
    if g > 0.6:                      # sun hidden behind thick cloud: only a soft bright patch
        return screen(img, glow, np.exp(-(d / 160) ** 2) * 0.35 * (1.6 - g))
    img = screen(img, glow, np.exp(-(d / 70) ** 2) * 0.55)
    img = screen(img, glow, np.exp(-(d / 260) ** 2) * (0.30 + 0.25 * low))
    img = over(img, col, m)
    return img

MARIA = [(-0.30, 0.32, 0.22), (0.16, 0.30, 0.15), (0.32, 0.06, 0.17), (0.64, 0.22, 0.10),
         (0.50, -0.20, 0.13), (-0.12, -0.42, 0.14), (-0.56, 0.06, 0.28), (0.05, -0.05, 0.08)]

def layer_moon(img, e):
    alt = e['moon_alt']
    if alt < -4:
        return img
    x, y = proj(alt, e['moon_az'])
    if not (-120 < x < W + 120):
        return img
    r = 52
    night = float(smooth(-2, -10, e['sun_alt']))
    day = 1 - night
    k = e['illum']
    lx, ly = e['limb']
    # local coords, u toward the sun-lit limb
    u = ((XX - x) * lx + (YY - y) * ly) / r
    v = ((XX - x) * -ly + (YY - y) * lx) / r
    rr = u * u + v * v
    inside = np.clip((1 - np.sqrt(rr)) * r + 0.5, 0, 1)
    p = 2 * k - 1
    term = -p * np.sqrt(np.clip(1 - v * v, 0, 1))
    lit = np.clip((u - term) * r * 0.9 + 0.5, 0, 1) * inside
    # maria (unrotated, screen-up = lunar north, roughly)
    mx, my = (XX - x) / r, -(YY - y) / r
    maria = np.zeros_like(u)
    for a, b, s in MARIA:
        maria += np.exp(-(((mx - a) ** 2 + (my - b) ** 2) / (s * s)))
    maria = np.clip(maria, 0, 1) * 0.16
    zen, mid, hor = sky_cols(e['sun_alt'])
    moon_col = C(228, 230, 252)
    surf = moon_col[None, None, :] * (1 - maria[..., None]) + C(150, 156, 196)[None, None, :] * maria[..., None]
    d = np.sqrt((XX - x) ** 2 + (YY - y) ** 2)
    veil = 1 - 0.75 * gloom(e)                # thick cloud hides most of the moon
    if night > 0:
        g = (0.15 + 0.85 * k) * night * veil
        img = screen(img, C(170, 170, 235), np.exp(-(d / 85) ** 2) * 0.45 * g)
        img = screen(img, C(120, 120, 200), np.exp(-(d / 260) ** 2) * 0.22 * g)
        # earthshine: the dark limb is opaque (hides stars behind it)
        img = over(img, mid * 0.55 + C(52, 54, 88) * 0.45, inside * 0.97 * night * veil)
    a = lit * (night + day * 0.62) * veil
    img = over(img, surf, a)
    return img

def cloud_layer(e):
    """Long, flat stratus streaks (fits the vector art). Layout changes daily."""
    rng = np.random.default_rng(int(e.get('day_seed', 1)))
    S = 2
    mask = np.zeros((H * S, W * S), np.float32)
    under = np.zeros_like(mask)
    n = int(rng.integers(3, 6))
    wx = e.get('wx')
    if wx:                                   # real cloud cover decides how many; a clear sky
        n = max(int(rng.integers(2, 4)), int(round(1 + wx['cover'] / 100 * 9)))  # keeps a few wisps
    # sun / moon discs that clouds should not slice through
    discs = [proj(e[k + '_alt'], e[k + '_az']) for k in ('sun', 'moon') if e[k + '_alt'] > -2]
    for ci in range(10):                     # fixed candidate layout per day
        cx, cy = rng.uniform(80, 1500), rng.uniform(100, 450)
        length = rng.uniform(260, 520)
        parts = [(rng.uniform(-0.45, 0.45), rng.uniform(-14, 10), rng.uniform(0.25, 0.55), rng.uniform(7, 16))
                 for _ in range(int(rng.integers(3, 6)))]
        if ci >= n:
            continue
        for dx, dy in discs:                 # slide the streak clear of the disc (+ its glow)
            if abs(cx - dx) < length * 0.75 and abs(cy - dy) < 85:
                cy = dy + (85 if cy >= dy and dy + 85 < 520 else -85)
        for px, py, pr, ry in parts:
            ox, oy, rx = cx + px * length, cy + py, pr * length
            cv2.ellipse(mask, (int(ox * S), int(oy * S)), (int(rx * S), int(ry * S)), 0, 0, 360, 1.0, -1,
                        cv2.LINE_AA)
            # lower lip, drawn shifted down: becomes the shaded underside
            cv2.ellipse(under, (int(ox * S), int((oy + ry * 0.55) * S)), (int(rx * 0.96 * S), int(ry * 0.6 * S)),
                        0, 0, 360, 1.0, -1, cv2.LINE_AA)
    mask = cv2.GaussianBlur(cv2.resize(mask, (W, H), interpolation=cv2.INTER_AREA), (0, 0), 1.6)
    under = cv2.GaussianBlur(cv2.resize(under, (W, H), interpolation=cv2.INTER_AREA), (0, 0), 4) * mask * 0.8
    return np.clip(mask, 0, 1), np.clip(under, 0, 1)

def layer_clouds(img, e):
    alt = e['sun_alt']
    mask, shade = cloud_layer(e)
    low = float(smooth(16, -2, alt))
    night = float(smooth(-3, -12, alt))
    lit = C(255, 255, 255) * (1 - low) + C(255, 200, 176) * low
    sh = C(206, 216, 240) * (1 - low) + C(196, 146, 186) * low
    moon = e['illum'] * float(np.clip(e['moon_alt'] / 20.0, 0, 1))      # moonlit clouds turn silvery
    lit = lit * (1 - night) + (C(66, 66, 102) * (1 - moon) + C(128, 130, 172) * moon) * night
    sh = sh * (1 - night) + (C(32, 34, 58) * (1 - moon) + C(58, 60, 92) * moon) * night
    g = gloom(e)
    if g > 0:                                # heavy cloud: grey, lower-contrast decks
        grey = C(176, 182, 198) * (1 - night) + C(44, 46, 62) * night
        lit = lit * (1 - 0.7 * g) + grey * 0.7 * g
        sh = sh * (1 - 0.7 * g) + grey * 0.8 * 0.7 * g
    col = lit[None, None, :] * (1 - shade[..., None]) + sh[None, None, :] * shade[..., None]
    a = mask * ((0.85 + 0.12 * g) * (1 - night) + (0.55 + 0.25 * g) * night)
    wx = e.get('wx')
    if wx and wx['cover'] < 20:              # clear sky: keep the wisps, but lighter
        a = a * (0.7 + 0.3 * wx['cover'] / 20)
    return over(img, col, a)

def layer_mountains(img, e):
    a = np.asarray(Image.open(os.path.join(ASSETS, 'mtn_alpha.png')), np.float32) / 255
    s = np.asarray(Image.open(os.path.join(ASSETS, 'mtn_shade.png')), np.float32) / 255
    c0, c1, c2 = keyed(MTN, e['sun_alt'])
    f = s[..., None]
    lo = c0 * (1 - np.clip(f * 2, 0, 1)) + c1 * np.clip(f * 2, 0, 1)
    hi = c1 * (1 - np.clip(f * 2 - 1, 0, 1)) + c2 * np.clip(f * 2 - 1, 0, 1)
    col = np.where(f < 0.5, lo, hi)
    # subtle aerial haze toward the horizon colour at the top of each range
    hor = sky_cols(e['sun_alt'])[2]
    haze = smooth(620, 480, YY)[..., None] * 0.10
    col = col * (1 - haze) + hor * haze
    light = float(smooth(-8, 8, e['sun_alt']))
    col = season_tint(e, col, 'mtn', light)
    snow = snowy(e)
    if snow > 0:
        # snow keeps the hand-drawn facets: crisp on the lit faces of the upper slopes, a pale blue
        # dusting on the shaded ones, nothing low down; the snowline wanders with the terrain
        line = 650 + 50 * (noise_field(13, scales=(300, 120)) - 0.5)
        high = np.clip((line - YY) / 70.0, 0, 1)
        lit = np.clip((s - 0.30) / 0.06, 0, 1)
        sc = snow_col(e['sun_alt'])
        shade = sc * 0.55 + c1 * 0.45                                         # snow in shadow
        on_lit = (lit * high * 0.92 * snow)[..., None]
        on_dark = ((1 - lit) * high * 0.55 * snow)[..., None]
        col = col * (1 - on_lit - on_dark) + sc * on_lit + shade * on_dark
    return img * (1 - a[..., None]) + col * a[..., None]

def layer_lake(img, e):
    rows = np.clip(2 * WATER - np.arange(WATER, H), 0, H - 1)
    refl = img[rows].copy()
    hh = H - WATER
    yy = np.arange(hh, dtype=np.float32)[:, None]
    rng = np.random.default_rng(5)
    ph = rng.uniform(0, 6.28, (hh, 1)).astype(np.float32)
    amp = 0.6 + yy / 70.0
    mapx = (np.arange(W, dtype=np.float32)[None, :] + amp * np.sin(yy * 0.55 + ph)
            + 0.8 * np.sin(np.arange(W)[None, :] / 37.0 + yy * 0.2)).astype(np.float32)
    mapy = np.repeat(yy, W, axis=1).astype(np.float32)
    refl = cv2.remap(refl, mapx, mapy, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    refl = cv2.GaussianBlur(refl, (0, 0), sigmaX=0.6, sigmaY=1.4)
    tint, ta = keyed(WATER_TINT, e['sun_alt'])
    tint = season_tint(e, tint, 'water', float(smooth(-8, 8, e['sun_alt'])))
    deep = np.clip(yy / hh, 0, 1)[..., None]
    water = refl * (1 - ta) + tint * ta
    water = water * (0.94 - 0.16 * deep)
    # thin horizontal streaks
    streak = (noise_field(3, scales=(60, 20, 6))[:hh] - 0.5)
    streak = cv2.GaussianBlur(streak, (0, 0), sigmaX=24, sigmaY=0.6) * 0.10
    water = water * (1 + streak[..., None])
    # glitter path under a bright body
    for body, b_col, strength in (('sun', C(255, 214, 160), 1.0), ('moon', C(210, 214, 255), 0.6)):
        alt = e[body + '_alt']
        if alt < 0:
            continue
        if body == 'moon':
            strength *= float(smooth(-2, -10, e['sun_alt'])) * (0.3 + 0.7 * e['illum'])
        if strength <= 0.02:
            continue
        x, _ = proj(alt, e[body + '_az'])
        width = 8 + yy * 0.32
        gx = np.exp(-((np.arange(W)[None, :] - x) / width) ** 2)
        rn = np.random.default_rng(9).random((hh, W // 6 + 1)).astype(np.float32)
        sp = (cv2.resize(rn, (W, hh), interpolation=cv2.INTER_NEAREST) > 0.86).astype(np.float32)
        sp = cv2.GaussianBlur(sp, (0, 0), sigmaX=3.0, sigmaY=0.4) * (np.arange(hh)[:, None] % 3 == 0)
        g = gx * sp * strength * (0.9 if body == 'sun' else 0.7)
        water = 1 - (1 - water) * (1 - b_col[None, None, :] * g[..., None])
    # waterline highlight
    hor = sky_cols(e['sun_alt'])[2]
    water[0:2] = water[0:2] * 0.6 + hor * 0.4 * 0.6 + water[0:2] * 0.0
    img = img.copy()
    img[WATER:] = water
    # shore, ground and wave lines
    shore = np.array(json.load(open(os.path.join(ASSETS, 'shore.json'))), np.float32)
    gmask = np.clip(YY - shore[None, :] + 0.5, 0, 1)
    ground = season_tint(e, keyed(GROUND, e['sun_alt']), 'ground', float(smooth(-8, 8, e['sun_alt'])))
    img = over(img, ground, gmask)
    if snowy(e) > 0:                         # a frosted rim along the shore, not a white sheet
        rim = np.clip(YY - shore[None, :] + 0.5, 0, 1) * np.clip((shore[None, :] + 9 - YY) / 9, 0, 1)
        img = over(img, snow_col(e['sun_alt']), rim * 0.55 * snowy(e))
    waves = np.asarray(Image.open(os.path.join(ASSETS, 'waves.png')), np.float32) / 255
    wcol = hor * 0.55 + C(235, 238, 250) * 0.45
    night = float(smooth(-2, -12, e['sun_alt']))
    img = over(img, wcol, waves * (0.75 - 0.25 * night))
    return img

# ================================================================ weather
def gloom(e):
    wx = e.get('wx')
    if not wx:
        return 0.0
    g = float(np.clip((wx['cover'] - 55) / 40, 0, 1))
    if wx['kind'] in ('rain', 'pour', 'storm', 'snow', 'sleet', 'fog'):
        g = max(g, 0.7)
    return g

def layer_weather(img, e):
    wx = e.get('wx')
    if not wx:
        return img
    g = gloom(e)
    if g > 0:                                # overcast: greyer, flatter light
        lum = (img @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
        img = img * (1 - 0.45 * g) + (lum * 0.92 + 0.03) * 0.45 * g
    kind = wx['kind']
    if kind in ('pour', 'storm'):
        img = img * 0.82
    rng = np.random.default_rng(int(e.get('day_seed', 1)) + 77)
    night = float(smooth(-3, -12, e['sun_alt']))
    hor = sky_cols(e['sun_alt'])[2]
    if kind == 'fog':
        band = np.exp(-((YY - 700) / 190) ** 2)
        img = over(img, hor * 0.6 + C(200, 204, 220) * 0.4 * (1 - night) + C(60, 62, 84) * 0.4 * night,
                   band * 0.55)
    if kind in ('rain', 'pour', 'storm', 'sleet'):
        n = {'rain': 1300, 'sleet': 1300, 'pour': 2600, 'storm': 2600}[kind]
        lay = np.zeros((H, W), np.float32)
        for _ in range(n):
            x, y = rng.uniform(-40, W), rng.uniform(-30, H)
            L = rng.uniform(14, 30)
            cv2.line(lay, (int(x), int(y)), (int(x + L * 0.26), int(y + L)), float(rng.uniform(0.5, 1)), 1,
                     cv2.LINE_AA)
        col = C(214, 222, 240) * (1 - night) + C(130, 136, 170) * night
        img = over(img, col, lay * 0.22)
    if kind in ('snow', 'sleet'):
        lay = np.zeros((H, W), np.float32)
        for _ in range(900 if kind == 'snow' else 400):
            cv2.circle(lay, (int(rng.uniform(0, W)), int(rng.uniform(0, H))), int(rng.integers(1, 3)), 1.0, -1,
                       cv2.LINE_AA)
        img = over(img, C(240, 242, 252), cv2.GaussianBlur(lay, (0, 0), 0.6) * 0.75)
    return img

def load_wx():
    p = os.path.join(CACHE, 'weather.json')
    try:
        if time.time() - os.path.getmtime(p) > 3 * 3600:
            return None
        w = json.load(open(p))
        return {'cover': float(w.get('cloud', 0)), 'kind': w.get('kind', 'clear')}
    except (OSError, ValueError):
        return None

# ================================================================ render
def scene_name(v=None):
    v = (v if v is not None else read_conf().get('scene') or 'lake').strip().lower()
    return v if v in scenes.SCENES else 'lake'

def slot_suffix(scene):
    """Cache-name suffix: the scene (not for the lake), a season set by hand (not for auto), pixel art, and
    the screen size when it isn't the 1920x1200 the scenes are drawn at."""
    v = (read_conf().get('season') or 'auto').strip().lower()
    sw, sh = screen_size()
    return (('' if scene == 'lake' else '-' + scene) + ('-' + v if v in SEASON_NAMES else '')
            + ('-px' if pixel_on() else '') + ('' if (sw, sh) == (W, H) else '-%dx%d' % (sw, sh)))

def screen_size():
    """The primary monitor's size (LIVING_SKY_W / _H, passed down by bin/living-sky), else 1920x1200."""
    sw = int(num(os.environ.get('LIVING_SKY_W'), W, lo=320, hi=7680))
    sh = int(num(os.environ.get('LIVING_SKY_H'), H, lo=240, hi=4320))
    return sw, sh

def fit_screen(img, scene, size, pixel=False):
    """The 1920x1200 render, cropped to the screen's shape and scaled to its size. The crop keeps what matters
    in each scene (scenes.FOCUS: the campfire, the street lamps, the shore): wider screens lose sky from the
    top more than ground from the bottom; narrower ones lose the sides around the scene's focus."""
    sw, sh = size
    if (sw, sh) == img.size:
        return img
    fx, keep_bottom = scenes.FOCUS.get(scene, (W / 2, 0.75))
    if sw / sh > W / H:                                  # wider: full width, a band of rows
        ch = round(W * sh / sw)
        y0 = round((H - ch) * keep_bottom)
        box = (0, y0, W, y0 + ch)
    else:                                                # narrower: full height, a band of columns
        cw = round(H * sw / sh)
        x0 = int(min(max(fx - cw / 2, 0), W - cw))
        box = (x0, 0, x0 + cw, H)
    out = img.crop(box)
    return out.resize((sw, sh), Image.NEAREST if pixel else Image.LANCZOS)

def pixel_on():
    return (read_conf().get('pixel') or 'off').strip().lower() in ('on', 'yes', 'true', '1')

BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16 - 0.5


def pixelate(img, block=4, levels=14):
    """Pixel art: 4x4 blocks, a reduced palette, and ordered (Bayer) dithering so gradients stay smooth."""
    sh, sw = img.shape[0] // block, img.shape[1] // block
    small = cv2.resize(np.clip(img, 0, 1), (sw, sh), interpolation=cv2.INTER_AREA)
    pat = np.tile(BAYER4, (sh // 4 + 1, sw // 4 + 1))[:sh, :sw, None]
    q = np.clip(np.round((small + pat / levels) * levels) / levels, 0, 1)
    return cv2.resize(q, (img.shape[1], img.shape[0]), interpolation=cv2.INTER_NEAREST)


def render(e):
    img = layer_sky(e)
    img = layer_night(img, e)
    img = layer_sun(img, e)
    img = layer_moon(img, e)
    img = layer_clouds(img, e)
    img = scenes.render(e.get('scene') or scene_name(), img, e, sys.modules[__name__])
    img = layer_weather(img, e)
    rng = np.random.default_rng(1)
    img = img + rng.normal(0, 0.6 / 255, img.shape).astype(np.float32)      # dither
    if e.get('pixel'):
        img = pixelate(img)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')

# ================================================================ palette
FLAVOURS = {
    'latte': dict(rosewater='#dc8a78', flamingo='#dd7878', pink='#ea76cb', mauve='#8839ef', red='#d20f39',
                  maroon='#e64553', peach='#fe640b', yellow='#df8e1d', green='#40a02b', teal='#179299',
                  sky='#04a5e5', sapphire='#209fb5', blue='#1e66f5', lavender='#7287fd', text='#4c4f69',
                  subtext1='#5c5f77', subtext0='#6c6f85', overlay2='#7c7f93', overlay1='#8c8fa1',
                  overlay0='#9ca0b0', surface2='#acb0be', surface1='#bcc0cc', surface0='#ccd0da',
                  base='#eff1f5', mantle='#e6e9ef', crust='#dce0e8'),
    'frappe': dict(rosewater='#f2d5cf', flamingo='#eebebe', pink='#f4b8e4', mauve='#ca9ee6', red='#e78284',
                   maroon='#ea999c', peach='#ef9f76', yellow='#e5c890', green='#a6d189', teal='#81c8be',
                   sky='#99d1db', sapphire='#85c1dc', blue='#8caaee', lavender='#babbf1', text='#c6d0f5',
                   subtext1='#b5bfe2', subtext0='#a5adce', overlay2='#949cbb', overlay1='#838ba7',
                   overlay0='#737994', surface2='#626880', surface1='#51576d', surface0='#414559',
                   base='#303446', mantle='#292c3c', crust='#232634'),
    'macchiato': dict(rosewater='#f4dbd6', flamingo='#f0c6c6', pink='#f5bde6', mauve='#c6a0f6', red='#ed8796',
                      maroon='#ee99a0', peach='#f5a97f', yellow='#eed49f', green='#a6da95', teal='#8bd5ca',
                      sky='#91d7e3', sapphire='#7dc4e4', blue='#8aadf4', lavender='#b7bdf8', text='#cad3f5',
                      subtext1='#b8c0e0', subtext0='#a5adcb', overlay2='#939ab7', overlay1='#8087a2',
                      overlay0='#6e738d', surface2='#5b6078', surface1='#494d64', surface0='#363a4f',
                      base='#24273a', mantle='#1e2030', crust='#181926'),
    'mocha': dict(rosewater='#f5e0dc', flamingo='#f2cdcd', pink='#f5c2e7', mauve='#cba6f7', red='#f38ba8',
                  maroon='#eba0ac', peach='#fab387', yellow='#f9e2af', green='#a6e3a1', teal='#94e2d5',
                  sky='#89dceb', sapphire='#74c7ec', blue='#89b4fa', lavender='#b4befe', text='#cdd6f4',
                  subtext1='#bac2de', subtext0='#a6adc8', overlay2='#9399b2', overlay1='#7f849c',
                  overlay0='#6c7086', surface2='#585b70', surface1='#45475a', surface0='#313244',
                  base='#1e1e2e', mantle='#181825', crust='#11111b'),
}

# ---- contrast helpers (WCAG relative luminance)
def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def rel_lum(h):
    r, g, b = (int(h[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)

def contrast(a, b):
    la, lb = sorted((rel_lum(a), rel_lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

def with_contrast(fg, bg, ratio):
    """Darken fg (keeping hue) until contrast(fg, bg) >= ratio."""
    r, g, b = (int(fg[i:i + 2], 16) for i in (1, 3, 5))
    k = 1.0
    out = fg
    while contrast(out, bg) < ratio and k > 0.2:
        k -= 0.02
        out = '#%02x%02x%02x' % (round(r * k), round(g * k), round(b * k))
    return out

# grey ramp keeps its hierarchy; accents only need to read as coloured text (mostly bold)
LATTE_MIN_CONTRAST = dict(text=8.0, subtext1=6.5, subtext0=5.5, overlay2=5.0, overlay1=4.6, overlay0=4.0,
                          rosewater=3.6, flamingo=3.6, pink=3.6, mauve=4.5, red=4.5, maroon=4.0, peach=3.6,
                          yellow=3.6, green=3.8, teal=4.0, sky=3.6, sapphire=3.8, blue=4.5, lavender=3.6)

# ---- accent colour sets (living-sky.conf `colors = ...`)
# Soft pastels, given as tuned for the dark (Mocha) cards: (primary, secondary).
# primary: the clock, Mimi's body, highlights; secondary: the weekday and other second accents.
COLOR_SETS = {
    'lavender': ('#b4befe', '#fab387'),     # lavender + peach (the classic living-sky night look)
    'sakura':   ('#f5b8d2', '#f9e2af'),     # cherry-blossom pink + butter
    'mint':     ('#94e2d5', '#cba6f7'),     # mint + lilac
    'peach':    ('#fab387', '#f5c2e7'),     # peach + rose
    'ocean':    ('#89b4fa', '#94e2d5'),     # sky blue + sea-glass teal
}

# OKLab / OKLCH (Björn Ottosson), so the per-hour tweaks keep the hue and perceived lightness
def _hex_rgb(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]

def _rgb_hex(c):
    return '#%02x%02x%02x' % tuple(round(min(1, max(0, v)) * 255) for v in c)

def _to_lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def _from_lin(c): return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

def hex_to_oklch(h):
    r, g, b = (_to_lin(v) for v in _hex_rgb(h))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s_
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s_
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s_
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360

def _oklch_rgb(L, C, H):
    A, B = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
    m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
    s_ = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3
    lin = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s_,
           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s_,
           -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s_)
    return [_from_lin(v) if v > 0 else v for v in lin]

def oklch_to_hex(L, C, H):
    """Nearest in-gamut sRGB colour: keep L and H, reduce chroma until it fits."""
    lo, hi = 0.0, C
    rgb = _oklch_rgb(L, C, H)
    if all(-1e-4 <= v <= 1 + 1e-4 for v in rgb):
        return _rgb_hex(rgb)
    for _ in range(20):
        mid = (lo + hi) / 2
        if all(-1e-4 <= v <= 1 + 1e-4 for v in _oklch_rgb(L, mid, H)): lo = mid
        else: hi = mid
    return _rgb_hex(_oklch_rgb(L, lo, H))

def _nudge_hue(h, target, amount):
    d = (target - h + 180) % 360 - 180
    return (h + max(-amount, min(amount, d))) % 360

def tune_accent(hexc, e, flavour, crust, min_contrast):
    """Very slight time-of-day adjustment of a user accent, so it keeps its character:
    calmer at night, a touch cooler in the blue hour, warmer around sunrise/sunset, and
    darkened (with a little extra chroma) on the light daytime cards until it is readable."""
    L, C, H = hex_to_oklch(hexc)
    alt = e['sun_alt']
    night = min(1.0, max(0.0, (-alt - 6) / 12))
    golden = math.exp(-((alt - 2) / 6) ** 2 / 2)
    blue = math.exp(-((alt + 6) / 3) ** 2 / 2)
    L *= 1 - 0.03 * night
    C *= (1 - 0.08 * night) * (1 + 0.05 * golden)
    if C > 0.02:                                     # leave near-greys alone
        H = _nudge_hue(H, 55, 6 * golden)
        H = _nudge_hue(H, 250, 4 * blue)
    out = oklch_to_hex(L, C, H)
    if flavour == 'latte':
        # light cards: do what Catppuccin Latte does with its accents: mid lightness, more chroma
        # (a pastel just darkened turns muddy: peach -> brown), then only as dark as readability needs
        C = max(C * 1.7, 0.06) if C > 0.02 else C
        L = min(L, 0.74)
        while L > 0.3:
            out = oklch_to_hex(L, C, H)
            if contrast(out, crust) >= min_contrast:
                break
            L -= 0.01
    return out

def parse_colors(v):
    """living-sky.conf `colors`: auto | a set name | '#rrggbb, #rrggbb' (primary, secondary)."""
    v = (v or 'auto').strip().lower()
    if v in COLOR_SETS:
        return v, COLOR_SETS[v]
    hexes = [x.strip() for x in v.replace(';', ',').split(',') if x.strip()]
    ok = lambda h: len(h) == 7 and h[0] == '#' and all(c in '0123456789abcdef' for c in h[1:])
    if len(hexes) == 2 and all(map(ok, hexes)):
        return '%s,%s' % tuple(hexes), tuple(hexes)
    return 'auto', None

def palette(e, colors=None):
    alt, morning = e['sun_alt'], e['sun_az'] < 180
    if alt < -10:
        name, acc, acc2 = 'mocha', 'lavender', 'peach'
    elif alt < -3:
        name, acc, acc2 = 'macchiato', 'blue', 'mauve'
    elif alt < 6:
        name, acc, acc2 = 'frappe', ('peach' if morning else 'pink'), ('yellow' if morning else 'mauve')
    elif alt < 16:
        name, acc, acc2 = 'latte', ('sapphire' if morning else 'peach'), ('peach' if morning else 'mauve')
    else:
        name, acc, acc2 = 'latte', 'blue', 'peach'
    p = dict(FLAVOURS[name])
    p['accent'], p['accent2'] = p[acc], p[acc2]
    if name == 'latte':
        # Latte's greys/accents are tuned for an opaque #eff1f5 page; on glass over the
        # wallpaper they wash out. Darken each text colour until it clears a contrast target.
        for k, ratio in LATTE_MIN_CONTRAST.items():
            p[k] = with_contrast(p[k], p['crust'], ratio)
        p.update(shadow='#4c4f69', shadow_a=0.16, glass_a1=0.90, glass_a2=0.94)
    else:
        p.update(shadow=p['crust'], shadow_a=0.35, glass_a1=0.86, glass_a2=0.90)
    p['flavour'] = name
    tag, pair = parse_colors(colors if colors is not None else read_conf().get('colors'))
    if pair:                                         # the user's colour set replaces the time-of-day accents
        # contrast targets on the light cards: the clock is large text (WCAG 3:1), the weekday small bold
        p['accent'] = tune_accent(pair[0], e, name, p['crust'], 3.0)
        p['accent2'] = tune_accent(pair[1], e, name, p['crust'], 3.3)
    elif name == 'latte':                            # the sky's own accents get the same contrast floor
        p['accent'] = with_contrast(p['accent'], p['crust'], 3.0)
        p['accent2'] = with_contrast(p['accent2'], p['crust'], 3.3)
    p['colors'] = tag
    return p

def lua_table(d):
    out = ['return {']
    for k, v in d.items():
        if isinstance(v, str):
            out.append('  %s = %s,' % (k, json.dumps(v)))
        else:
            out.append('  %s = %s,' % (k, repr(round(v, 3)) if isinstance(v, float) else v))
    out.append('}')
    return '\n'.join(out) + '\n'

# ================================================================ frost (glass-card backdrop)
FROST_LUMA = {'latte': ('min', 0.80), 'frappe': ('max', 0.27), 'macchiato': ('max', 0.21), 'mocha': ('max', 0.17)}

def make_frost(img, pal):
    """Blurred, saturated copy of the wallpaper for glass cards, with its brightness pushed
    toward the palette base wherever it would hurt text contrast (light flavour: lift dark
    areas; dark flavours: dim bright areas). Pixel-aligned with the wallpaper."""
    iw, ih = img.size
    small = np.asarray(img.resize((iw // 4, ih // 4), Image.BOX)).astype(np.float32) / 255
    small = cv2.GaussianBlur(small, (0, 0), 7)
    luma = small @ np.array([0.299, 0.587, 0.114], np.float32)
    small = np.clip(luma[..., None] + (small - luma[..., None]) * 1.35, 0, 1)      # vibrancy
    luma = small @ np.array([0.299, 0.587, 0.114], np.float32)
    base = np.array([int(pal['base'][i:i + 2], 16) / 255 for i in (1, 3, 5)], np.float32)
    lb = float(base @ np.array([0.299, 0.587, 0.114], np.float32))
    mode, lim = FROST_LUMA[pal['flavour']]
    if mode == 'min':
        m = np.clip((lim - luma) / np.maximum(lb - luma, 1e-3), 0, 1)
    else:
        m = np.clip((luma - lim) / np.maximum(luma - lb, 1e-3), 0, 1)
    m = np.maximum(m, 0.30)[..., None]                                             # base frosting
    small = small * (1 - m) + base * m
    big = cv2.resize(small, (iw, ih), interpolation=cv2.INTER_CUBIC)
    big += np.random.default_rng(2).normal(0, 1.2 / 255, big.shape).astype(np.float32)  # grain
    return Image.fromarray((np.clip(big, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB')

def save_frost(img, pal, path):
    make_frost(img, pal).save(path + '.tmp.png', compress_level=3)
    os.replace(path + '.tmp.png', path)

# ================================================================ main
def info_for(t, lat, lon, name):
    e = ephemeris(t, lat, lon)
    e['day_seed'] = int(t.strftime('%Y%m%d'))
    e['hour'] = t.hour + t.minute / 60
    e['season'], e['season_w'], e['snow'] = season_info(read_conf().get('season'), t, lat)
    e['pixel'] = pixel_on()
    rise, sset = sun_events(t, lat, lon)
    e.update(rise=rise.strftime('%H:%M') if rise else '--:--',
             set=sset.strftime('%H:%M') if sset else '--:--',
             phase=phase_name(e['illum'], e['waxing'], e['age_deg']), place=name, lat=lat, lon=lon)
    return e

def write_slot(t_slot, interval, lat, lon, name, out_dir):
    scene = scene_name()
    key = t_slot.strftime('%Y%m%d%H%M') + slot_suffix(scene)
    png, lua = os.path.join(out_dir, key + '.png'), os.path.join(out_dir, key + '.lua')
    frost = os.path.join(out_dir, key + '-frost.png')
    mid = t_slot + dt.timedelta(minutes=interval / 2)
    if os.path.exists(png) and os.path.exists(lua):
        made = False
        if not os.path.exists(frost):
            save_frost(Image.open(png).convert('RGB'), palette(info_for(mid, lat, lon, name)), frost)
            made = True
        want = parse_colors(read_conf().get('colors'))[0]
        if ('colors = "%s"' % want) not in open(lua).read():    # colour setting changed: new palette only
            write_palette(info_for(mid, lat, lon, name), key, png, frost, name, lua)
            made = True
        return key, made
    e = info_for(mid, lat, lon, name)
    e['wx'] = load_wx()
    e['season'], e['season_w'], e['snow'] = season_info(read_conf().get('season'), mid, lat, e['wx'])
    e['scene'] = scene
    img = fit_screen(render(e), scene, screen_size(), e.get('pixel'))
    img.save(png + '.tmp.png', optimize=False, compress_level=3)
    os.replace(png + '.tmp.png', png)
    save_frost(img, palette(e), frost)
    write_palette(e, key, png, frost, name, lua)
    return key, True

def write_palette(e, key, png, frost, name, lua):
    p = palette(e)
    p.update(slot=key, scene=scene_name(), season=e.get('season', ''), wall=png, frost=frost, sunrise=e['rise'], sunset=e['set'], moon_phase=e['phase'],
             moon_illum=round(e['illum'] * 100), sun_alt=round(e['sun_alt'], 1), place=name or '')
    with open(lua + '.tmp', 'w') as f:
        f.write(lua_table(p))
    os.replace(lua + '.tmp', lua)

def prune(out_dir, keep=48):
    # every slot render (any suffixes: -camp, -winter, -px, ...), not its -frost.png companion
    pngs = sorted((f for f in os.listdir(out_dir)
                   if re.match(r'^\d{12}(-[a-z0-9]+)*\.png$', f) and not f.endswith('-frost.png')),
                  key=lambda f: os.path.getmtime(os.path.join(out_dir, f)))
    for f in pngs[:-keep]:
        for ext in ('.png', '.lua', '-frost.png'):
            try: os.remove(os.path.join(out_dir, f[:-4] + ext))
            except OSError: pass

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--now', action='store_true')
    ap.add_argument('--next', action='store_true', help='with --now: render the following slot')
    ap.add_argument('--at', help='"YYYY-MM-DD HH:MM" local time')
    ap.add_argument('--out', help='output png (with --at)')
    ap.add_argument('--info', action='store_true')
    ap.add_argument('--wx', help='with --at: "kind:cover", e.g. rain:90, clear:0 (testing)')
    ap.add_argument('--pixel', action='store_true', help='with --at: pixel-art look')
    ap.add_argument('--size', help='with --at: fit to a screen of this size, e.g. 3440x1440 (default: 1920x1200)')
    ap.add_argument('--season', help='with --at: spring | summer | autumn | winter (default: by date)')
    ap.add_argument('--scene', help='with --at: render this scene (%s) instead of the configured one' % ', '.join(scenes.SCENES))
    a = ap.parse_args()
    conf = read_conf()
    interval = int(max(5, num(conf.get('interval_min'), 60, lo=1) or 60))
    lat, lon, name = get_location(conf)
    if a.at:
        t = dt.datetime.strptime(a.at, '%Y-%m-%d %H:%M').astimezone()
    else:
        t = now_local()
    if a.info:
        e = info_for(t, lat, lon, name)
        print(json.dumps({k: (round(v, 3) if isinstance(v, float) else v) for k, v in e.items()}, indent=1))
        return
    if a.at:
        e = info_for(t, lat, lon, name)
        if a.wx:
            k, cv = a.wx.split(':')
            e['wx'] = {'kind': k, 'cover': float(cv)}
        e['scene'] = scene_name(a.scene)
        e['season'], e['season_w'], e['snow'] = season_info(a.season or read_conf().get('season'), t, lat, e.get('wx'))
        e['pixel'] = a.pixel or pixel_on()
        out = a.out or os.path.join(CACHE, 'at-%s.png' % t.strftime('%Y%m%d%H%M'))
        img = render(e)
        if a.size:
            sw, sh = (int(v) for v in a.size.lower().split('x'))
            img = fit_screen(img, e['scene'], (sw, sh), e['pixel'])
        img.save(out)
        print(out, json.dumps({k: (round(v, 2) if isinstance(v, float) else v) for k, v in e.items() if k != 'limb'}))
        return
    os.makedirs(CACHE, exist_ok=True)
    lock = os.path.join(CACHE, 'render.lock')
    try:
        if time.time() - os.path.getmtime(lock) < 180:
            return
    except OSError:
        pass
    open(lock, 'w').write(str(os.getpid()))
    try:
        s = slot_start(t, interval)
        if a.next:
            s = slot_start(s + dt.timedelta(minutes=interval), interval)
        key, made = write_slot(s, interval, lat, lon, name, CACHE)
        if not a.next:
            with open(os.path.join(CACHE, 'current.tmp'), 'w') as f:
                f.write(key + '\n')
            os.replace(os.path.join(CACHE, 'current.tmp'), os.path.join(CACHE, 'current'))
        prune(CACHE)
        print(key, 'rendered' if made else 'cached')
    finally:
        try: os.remove(lock)
        except OSError: pass

if __name__ == '__main__':
    main()
