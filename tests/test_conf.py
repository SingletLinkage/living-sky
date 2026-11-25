"""core/conf.py: in-place editing keeps comments; '#rrggbb' is a value, ' # ...' a comment."""
import os

import conf


def test_write_keeps_comments_and_reads_back():
    if os.path.exists(conf.CONF):
        os.remove(conf.CONF)
    conf.write('scene', 'camp')
    conf.write('colors', '#a6e3a1, #f5c2e7')
    conf.write('cards', 'network, clock', before='card_clock')
    text = open(conf.CONF).read()
    example = open(conf.EXAMPLE).read()
    assert text.count('\n#') == example.count('\n#')            # every comment line kept
    vals = conf.read()
    assert vals['scene'] == 'camp'
    assert vals['colors'] == '#a6e3a1, #f5c2e7'
    assert vals['cards'] == 'network, clock'
    lines = text.split('\n')
    assert lines.index('cards = network, clock') < lines.index('card_clock = on')


def test_inline_comment(tmp_path):
    p = tmp_path / 'c.conf'
    p.write_text('units = imperial   # freedom units\n# glob = pip\ncolors = #112233, #445566\n')
    vals = conf.parse(str(p))
    assert vals == {'units': 'imperial', 'colors': '#112233, #445566'}


def test_known_keys():
    keys = conf.known_keys()
    for k in ('theme', 'scene', 'pixel', 'colors', 'glob', 'card_clock', 'cards', 'lat'):
        assert k in keys
