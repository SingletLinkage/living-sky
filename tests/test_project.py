"""Static checks: shell syntax, Lua syntax, the GNOME 45+ build, config example vs. engine defaults."""
import os
import shutil
import subprocess
import sys

import pytest

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
SHELL = ['install.sh', 'uninstall.sh', 'bin/living-sky', 'bin/living-sky-run', 'tools/cardshots.sh', 'tools/media.sh']
LUA = [os.path.join(d, f) for d, _, fs in os.walk(os.path.join(ROOT, 'lua')) for f in fs if f.endswith('.lua')]
LUA_RUN = shutil.which('luac') or shutil.which('luac5.4') or shutil.which('texlua')


@pytest.mark.parametrize('path', SHELL)
def test_shell_syntax(path):
    p = os.path.join(ROOT, path)
    if not os.path.exists(p):
        pytest.skip('missing')
    subprocess.run(['bash', '-n', p], check=True)


@pytest.mark.skipif(not LUA_RUN, reason='no luac / texlua')
@pytest.mark.parametrize('path', LUA, ids=lambda p: os.path.relpath(p, ROOT))
def test_lua_syntax(path, tmp_path):
    if os.path.basename(LUA_RUN).startswith('luac'):
        subprocess.run([LUA_RUN, '-p', path], check=True)
    else:
        chk = tmp_path / 'chk.lua'
        chk.write_text('local f, e = loadfile(arg[1]); if not f then error(e) end\n')
        subprocess.run([LUA_RUN, str(chk), path], check=True)


def test_esm_build(tmp_path):
    out = tmp_path / 'glob@living-sky'
    subprocess.run([sys.executable, os.path.join(ROOT, 'gnome-extension', 'build-esm.py'), str(out)], check=True,
                   capture_output=True)
    js = (out / 'extension.js').read_text()
    assert 'import ' in js and 'imports.gi' not in js
    for pet in ('core', 'mimi', 'pip', 'bun', 'nyx', 'cubo', 'ember'):
        assert 'imports.' not in (out / 'pets' / (pet + '.js')).read_text().split('*/', 1)[-1]


@pytest.mark.skipif(not shutil.which('gjs'), reason='no gjs')
def test_panel_pet_draws(tmp_path):
    png = tmp_path / 'mimi.png'
    subprocess.run(['gjs', os.path.join(ROOT, 'gnome-extension', 'glob@living-sky', 'tools', 'render.js'), str(png)],
                   check=True, capture_output=True, cwd=os.path.join(ROOT, 'gnome-extension', 'glob@living-sky'))
    assert png.stat().st_size > 500


def test_site_images_exist():
    """Every image the website uses exists (the pages workflow copies art/demos, art/glob and art/site next to it)."""
    import re
    site = os.path.join(ROOT, 'site')
    html = open(os.path.join(site, 'index.html')).read()
    js = open(os.path.join(site, 'app.js')).read()
    refs = set(re.findall(r'(?:src|href|data-gif)="(art/[^"]+)"', html))
    scenes, pets = 'lake forest city camp'.split(), 'mimi pip bun nyx cubo ember'.split()
    refs |= {'art/demos/scene-%s.jpg' % s for s in scenes} | {'art/demos/hours/%s.jpg' % s for s in scenes}
    refs |= {'art/glob/%s/showcase.png' % p for p in pets} | {'art/demos/glass-%s.jpg' % t for t in ('night', 'day')}
    for c in re.search(r"const CARDS = \[([^\]]+)\]", js).group(1).replace("'", '').split(','):
        refs.add('art/site/cards/%s.jpg' % c.strip())
    refs |= {'art/site/sticker-%s.png' % k for k in re.findall(r"^\s+(\w+): \{label: ", js, re.M)}
    lost = open(os.path.join(site, '404.html')).read()        # served at any path, so linked from the site root
    refs |= {r[len('/living-sky/'):] for r in re.findall(r'(?:src|href)="(/living-sky/art/[^"]+)"', lost)}
    missing = [r for r in sorted(refs) if not os.path.exists(os.path.join(ROOT, r))]
    assert not missing, missing


def test_site_pets_bundle_in_sync():
    """site/pets.js is generated from the panel pets; it must match a fresh build."""
    subprocess.run([sys.executable, os.path.join(ROOT, 'gnome-extension', 'build-web.py'), '--check'], check=True)
