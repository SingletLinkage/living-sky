"""living-sky.conf, read and written in place (comments and layout kept). Shared by the settings window and
`living-sky set / get`. Comment rule (same as core/sky.py): a whole-line '#', or ' # ...' after a value,
but '#rrggbb' colours are values.

  python3 core/conf.py get <key>            print the value ('' if unset)
  python3 core/conf.py set <key> <value>    set it (a missing key is added; unknown keys are refused)
  python3 core/conf.py keys                 every known key with its value
"""
import os, re, shutil, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), '..'))
EXAMPLE = os.path.join(ROOT, 'living-sky.conf.example')
CONF_DIR = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'living-sky')
CONF = os.path.join(CONF_DIR, 'living-sky.conf')
LINE = re.compile(r'^\s*([a-z_0-9]+)\s*=(.*)$')
COMMENT = re.compile(r'(^|\s)#(?![0-9a-fA-F]{6}\b).*$')
EXTRA_KEYS = {'cards'}                 # documented in a comment, not as a line, in the example


def parse(path):
    vals = {}
    try:
        for line in open(path, encoding='utf-8'):
            if line.lstrip().startswith('#'):
                continue
            m = LINE.match(COMMENT.sub('', line.rstrip('\n')))
            if m:
                vals[m.group(1)] = m.group(2).strip()
    except OSError:
        pass
    return vals


def read():
    return parse(CONF if os.path.exists(CONF) else EXAMPLE)


def known_keys():
    return list(parse(EXAMPLE)) + sorted(EXTRA_KEYS)


def write(key, value, before=None):
    """Set `key = value` in the user's config, keeping every comment. A missing key goes before the line of
    key `before` (if given and present), else at the end. Creates the config from the example if needed."""
    if not os.path.exists(CONF):
        os.makedirs(CONF_DIR, exist_ok=True)
        shutil.copy(EXAMPLE, CONF)
    lines = open(CONF, encoding='utf-8').read().split('\n')
    new = ('%s = %s' % (key, value)).rstrip()

    def find(k):
        for i, line in enumerate(lines):
            m = LINE.match(line)
            if m and not line.lstrip().startswith('#') and m.group(1) == k:
                return i
        return None
    i = find(key)
    if i is not None:
        lines[i] = new
    else:
        at = find(before) if before else None
        lines.insert(len(lines) if at is None else at, new)
    tmp = CONF + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    os.replace(tmp, CONF)


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['get'] and len(a) == 2:
        print(read().get(a[1], ''))
    elif a[:1] == ['set'] and len(a) >= 3:
        if a[1] not in known_keys():
            sys.exit("unknown setting '%s' (see: living-sky set --list)" % a[1])
        write(a[1], ' '.join(a[2:]), before='card_clock' if a[1] == 'cards' else None)
    elif a[:1] == ['keys']:
        vals = read()
        for k in known_keys():
            print('%-16s %s' % (k, vals.get(k, '')))
    else:
        sys.exit(__doc__.split('\n\n')[1])
