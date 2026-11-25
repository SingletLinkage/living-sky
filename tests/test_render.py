"""Smoke renders: every scene by night and by day, in summer and with snow, and the pixel look."""
import datetime as dt

import numpy as np
import pytest

import scenes
import sky

LAT, LON = 48.86, 2.35


def frame(scene, when, season, pixel=False):
    t = dt.datetime.strptime(when, '%Y-%m-%d %H:%M').astimezone()
    e = sky.info_for(t, LAT, LON, 'Test')
    e['wx'] = {'kind': 'partly', 'cover': 25}
    e['scene'] = scene
    e['season'], e['season_w'], e['snow'] = sky.season_info(season, t, LAT, e['wx'])
    e['pixel'] = pixel
    return np.asarray(sky.render(e))


@pytest.mark.parametrize('scene', scenes.SCENES)
@pytest.mark.parametrize('when, season', [('2026-07-01 13:00', 'summer'), ('2026-01-10 23:30', 'winter')])
def test_scene_renders(scene, when, season):
    img = frame(scene, when, season)
    assert img.shape == (sky.H, sky.W, 3)
    assert 2 < img.mean() < 250 and img.std() > 5          # not blank, not one flat colour


def test_pixel_blocks():
    img = frame('lake', '2026-07-01 20:00', 'summer', pixel=True)
    assert (img[0::4] == img[1::4]).all() and (img[:, 0::4] == img[:, 3::4]).all()   # 4x4 blocks
