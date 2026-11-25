"""lua/glob/pick.lua (`glob = random | scene | <id>`), run with a Lua interpreter (texlua / lua)."""
import glob
import os
import shutil
import subprocess

import pytest

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
LUA = shutil.which('lua5.4') or shutil.which('lua') or shutil.which('texlua')
pytestmark = pytest.mark.skipif(not LUA, reason='no lua / texlua')

PROBE = r'''
local P = dofile(arg[1])
print('pets', table.concat(P.PETS, ' '))
local t0 = os.time({year = 2026, month = 1, day = 1, hour = 12})
local days = {}
for d = 0, 59 do days[#days + 1] = P.resolve('random', 'lake', t0 + d * 86400) end
print('days', table.concat(days, ' '))
print('sameday', P.resolve('random', 'lake', t0 + 3600 * 2), P.resolve('random', 'lake', t0 + 3600 * 9))
for _, s in ipairs({'lake', 'forest', 'city', 'camp', 'nowhere'}) do print('scene', s, P.resolve('scene', s, t0)) end
print('plain', P.resolve('Ember', 'lake', t0), P.resolve('nope', 'lake', t0), P.resolve('off', 'lake', t0), P.resolve(nil, nil, t0))
'''


@pytest.fixture(scope='module')
def out(tmp_path_factory):
    probe = tmp_path_factory.mktemp('lua') / 'probe.lua'
    probe.write_text(PROBE)
    res = subprocess.run([LUA, str(probe), os.path.join(ROOT, 'lua', 'glob', 'pick.lua')],
                         capture_output=True, text=True, check=True)
    return [line.split() for line in res.stdout.splitlines()]


def rows(out, key):
    return [r[1:] for r in out if r[0] == key]


def test_pet_list_matches_files(out):
    files = sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(ROOT, 'lua', 'glob', '*.lua'))
                   if os.path.basename(p) not in ('core.lua', 'pick.lua'))
    assert sorted(rows(out, 'pets')[0]) == files
    for pet in files:                               # and every pet has a panel twin
        assert os.path.exists(os.path.join(ROOT, 'gnome-extension', 'glob@living-sky', 'pets', pet + '.js'))


def test_pet_of_the_day(out):
    days = rows(out, 'days')[0]
    assert set(days) == set(rows(out, 'pets')[0])              # every pet comes round
    assert all(a != b for a, b in zip(days, days[1:]))         # never the same two days running
    a, b = rows(out, 'sameday')[0]
    assert a == b                                              # stable through the day


def test_scene_and_plain(out):
    scenes = {s: p for s, p in rows(out, 'scene')}
    assert scenes == {'lake': 'pip', 'forest': 'bun', 'city': 'cubo', 'camp': 'ember', 'nowhere': 'mimi'}
    assert rows(out, 'plain')[0] == ['ember', 'mimi', 'off', 'mimi']
