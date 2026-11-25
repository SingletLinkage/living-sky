"""core/sky.py: config numbers, sun events (incl. polar day / night), seasons, colours and contrast."""
import datetime as dt

import pytest

import sky


@pytest.mark.parametrize('v, out', [('12.5', 12.5), ('', None), ('abc', None), ('inf', None), ('-inf', None),
                                    ('nan', None), (None, None), ('200', None), ('-91', None)])
def test_num(v, out):
    assert sky.num(v, None, lo=-90, hi=90) == out


def test_sun_events_normal_day():
    day = dt.datetime(2026, 6, 21, 12, 0).astimezone()
    rise, sset = sky.sun_events(day, 48.86, 2.35)
    assert rise is not None and sset is not None
    day_len = ((sset - rise) % dt.timedelta(days=1)).total_seconds() / 3600   # any machine time zone
    assert 15.8 < day_len < 16.6                                               # Paris, midsummer: ~16h10


@pytest.mark.parametrize('month', [6, 12])           # midnight sun and polar night at 78°N
def test_sun_events_polar(month):
    day = dt.datetime(2026, month, 21, 12, 0).astimezone()
    rise, sset = sky.sun_events(day, 78.2, 15.6)
    assert rise is None and sset is None


@pytest.mark.parametrize('lat, month, season', [(48.0, 7, 'summer'), (-34.0, 7, 'winter'), (48.0, 1, 'winter'),
                                                (-34.0, 1, 'summer'), (1.3, 1, 'summer'), (48.0, 10, 'autumn')])
def test_season_by_hemisphere(lat, month, season):
    t = dt.datetime(2026, month, 15, 12, 0).astimezone()
    name, weights, _snow = sky.season_info('auto', t, lat)
    assert name == season
    assert abs(sum(weights.values()) - 1) < 1e-6


def test_season_snow_rules():
    t = dt.datetime(2026, 1, 15, 12, 0).astimezone()
    assert sky.season_info('winter', t, 20.0)[2] == 1          # set by hand: snow
    assert sky.season_info('auto', t, 30.0)[2] == 0            # low-latitude winter: no snow
    assert sky.season_info('auto', t, 60.0)[2] > 0             # high-latitude winter: snow
    assert sky.season_info('auto', t, 30.0, {'kind': 'snow', 'cover': 90})[2] == 1   # snowing


@pytest.mark.parametrize('v, tag', [('auto', 'auto'), ('mint', 'mint'), ('#AABBCC, #112233', '#aabbcc,#112233'),
                                    ('nonsense', 'auto'), ('#abc, #def', 'auto'), ('', 'auto')])
def test_parse_colors(v, tag):
    assert sky.parse_colors(v)[0] == tag


@pytest.mark.parametrize('colors', ['auto', 'lavender', 'sakura', 'mint', 'peach', 'ocean', '#ffffff, #fefefe'])
@pytest.mark.parametrize('alt', [-30, -6, 2, 10, 40])
def test_palette_contrast(colors, alt):
    """Every colour set stays readable on the cards at every time of day (light cards included)."""
    e = {'sun_alt': alt, 'sun_az': 250}
    p = sky.palette(e, colors)
    if p['flavour'] == 'latte':
        for k, ratio in sky.LATTE_MIN_CONTRAST.items():
            assert sky.contrast(p[k], p['crust']) >= ratio - 0.05, k
        assert sky.contrast(p['accent'], p['crust']) >= 2.9
        assert sky.contrast(p['accent2'], p['crust']) >= 3.2
