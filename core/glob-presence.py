#!/usr/bin/env python3
"""Event-driven presence for the glob pet (no polling).

Writes ~/.cache/living-sky/presence, only when something changes:
    playing 0|1     any MPRIS media player is Playing  (D-Bus PropertiesChanged / NameOwnerChanged)
    media none|music|video   what kind: music players (Spotify...) / music sites -> music,
                    browsers & video players -> video  (playerctld, a proxy, is ignored)
    away 0|1        no keyboard/mouse input for 5 min  (GNOME Mutter IdleMonitor watches)
    app terminal|code|files|browser|other   coarse category of the focused window
                    (X11 _NET_ACTIVE_WINDOW PropertyNotify -> WM_CLASS only; no titles)
    typing 0|1      a key was pressed on any keyboard in the last 1.5 s
    Also writes ~/.cache/living-sky/nowplaying for the media card (current player, track, position).
    kbd xi2|record|none   how key presses are seen: XInput2 raw events, or the X RECORD extension
                    (older python-xlib). Only the fact that a key went down is used: which key is
                    never decoded or stored. With `none` the conky side uses the laptop i8042 counter.

Single instance (lock file). Started by the conky Lua when missing; exits on its own
when no living-sky conky theme is running (checked every 30 s).
"""
import fcntl, os, re, signal, sys, threading, time
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

CACHE = os.path.join(os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache'), 'living-sky')
OUT = os.path.join(CACHE, 'presence')
PIDF = os.path.join(CACHE, 'presence.pid')
AWAY_MS = 5 * 60 * 1000
IM_NAME, IM_PATH, IM_IFACE = 'org.gnome.Mutter.IdleMonitor', '/org/gnome/Mutter/IdleMonitor/Core', 'org.gnome.Mutter.IdleMonitor'
MPRIS = 'org.mpris.MediaPlayer2.'

os.makedirs(CACHE, exist_ok=True)
lock = open(os.path.join(CACHE, 'presence.lock'), 'w')
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)                                   # already running
with open(PIDF, 'w') as f:
    f.write(str(os.getpid()))

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
state = {'playing': 0, 'media': 'none', 'away': 0, 'app': 'other', 'typing': 0, 'kbd': 'none'}

def put(key, val, force=False):
    if state[key] == val and not force:
        return
    state[key] = val
    with open(OUT + '.tmp', 'w') as f:
        f.write('playing %d\nmedia %s\naway %d\napp %s\ntyping %d\nkbd %s\n' % (
            state['playing'], state['media'], state['away'], state['app'], state['typing'], state['kbd']))
    os.replace(OUT + '.tmp', OUT)

MUSIC_PLAYERS = ('spotify', 'rhythmbox', 'amberol', 'lollypop', 'audacious', 'clementine', 'strawberry', 'elisa',
                 'cmus', 'mpd', 'ncspot', 'tauon', 'quodlibet', 'deadbeef', 'cider', 'tidal')
MUSIC_SITES = ('music.youtube.com', 'open.spotify.com', 'soundcloud.com', 'music.apple.com', 'bandcamp.com')

def media_kind(name):
    """music | video for one playing MPRIS player (URL host checked locally, never stored)."""
    short = name[len(MPRIS):].lower()
    if short.startswith(MUSIC_PLAYERS):
        return 'music'
    try:
        md = bus.call_sync(name, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties', 'Get',
                           GLib.Variant('(ss)', ('org.mpris.MediaPlayer2.Player', 'Metadata')),
                           GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
        url = str(md.get('xesam:url', ''))
        host = url.split('://', 1)[-1].split('/', 1)[0].lower()
        if any(host == h or host.endswith('.' + h) for h in MUSIC_SITES):
            return 'music'
    except (GLib.Error, AttributeError):
        pass
    return 'video'

# ---------------------------------------------------------------- media players
NOWP = os.path.join(CACHE, 'nowplaying')
PLAYER = 'org.mpris.MediaPlayer2.Player'
now = {'last': None}

def prop(name, iface, p):
    return bus.call_sync(name, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties', 'Get',
                         GLib.Variant('(ss)', (iface, p)), GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE,
                         500, None).unpack()[0]

def write_now(name, status, force=False):
    """The media card's file: one player (playing first, else paused); position is stamped with
    /proc/uptime so the card can move the progress bar on its own."""
    if not name:
        if now['last'] is not None:
            now['last'] = None
            try: os.remove(NOWP)
            except OSError: pass
        return
    try:
        md = prop(name, PLAYER, 'Metadata')
    except GLib.Error:
        md = {}
    clean = lambda v: ' '.join(str(v).split())[:200]
    title = clean(md.get('xesam:title', ''))
    artist = clean(', '.join(md.get('xesam:artist', []) or []))
    album = clean(md.get('xesam:album', ''))
    length = float(md.get('mpris:length', 0) or 0) / 1e6
    try:
        ident = clean(prop(name, 'org.mpris.MediaPlayer2', 'Identity'))
    except GLib.Error:
        ident = name[len(MPRIS):].split('.')[0]
    ident = re.sub(r'_[\w-]+$', '', re.sub(r'^Mozilla ', '', ident))      # "Mozilla firefox_firefox" (snap) -> Firefox
    ident = ident[:1].upper() + ident[1:]
    key = (ident, status, title, artist, album, round(length))
    if key == now['last'] and not force:
        return
    now['last'] = key
    try:
        pos = float(prop(name, PLAYER, 'Position')) / 1e6
    except (GLib.Error, TypeError, ValueError):
        pos = -1.0
    up = float(open('/proc/uptime').read().split()[0])
    with open(NOWP + '.tmp', 'w') as f:
        f.write('status %s\nplayer %s\ntitle %s\nartist %s\nalbum %s\nlength %.1f\nposition %.1f\nat %.2f\n'
                % (status, ident, title, artist, album, length, pos, up))
    os.replace(NOWP + '.tmp', NOWP)

def refresh_players(*_, force=False):
    playing, kinds = 0, set()
    current = paused = None
    try:
        names = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'ListNames',
                              None, GLib.VariantType('(as)'), Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
    except GLib.Error:
        names = []
    for n in names:
        if not n.startswith(MPRIS) or n == MPRIS + 'playerctld':
            continue
        try:
            st = bus.call_sync(n, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties', 'Get',
                               GLib.Variant('(ss)', ('org.mpris.MediaPlayer2.Player', 'PlaybackStatus')),
                               GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
            if st == 'Playing':
                playing = 1
                kinds.add(media_kind(n))
                current = current or n
            elif st == 'Paused':
                paused = paused or n
        except GLib.Error:
            pass
    write_now(current or paused, 'Playing' if current else 'Paused', force)
    put('playing', playing)
    put('media', 'music' if 'music' in kinds else ('video' if kinds else 'none'))

def on_props(conn, sender, path, iface, signal, params):
    refresh_players(force=True)

def on_name(conn, sender, path, iface, signal, params):
    name = params.unpack()[0]
    if name.startswith(MPRIS):
        refresh_players()
    elif name == IM_NAME and params.unpack()[2]:  # Mutter came back (e.g. Alt+F2 r): re-arm the watches
        GLib.timeout_add(500, arm_idle)

bus.signal_subscribe(None, 'org.freedesktop.DBus.Properties', 'PropertiesChanged', '/org/mpris/MediaPlayer2',
                     None, Gio.DBusSignalFlags.NONE, on_props)
bus.signal_subscribe(None, PLAYER, 'Seeked', '/org/mpris/MediaPlayer2', None, Gio.DBusSignalFlags.NONE,
                     lambda *a: refresh_players(force=True))
bus.signal_subscribe('org.freedesktop.DBus', 'org.freedesktop.DBus', 'NameOwnerChanged', '/org/freedesktop/DBus',
                     None, Gio.DBusSignalFlags.NONE, on_name)

# ---------------------------------------------------------------- away (idle monitor)
watch = {'idle': None, 'active': None}

def im(method, params=None):
    return bus.call_sync(IM_NAME, IM_PATH, IM_IFACE, method, params, None, Gio.DBusCallFlags.NONE, 2000, None)

def arm_active():
    watch['active'] = im('AddUserActiveWatch').unpack()[0]

def arm_idle(*_):
    try:
        watch['idle'] = im('AddIdleWatch', GLib.Variant('(t)', (AWAY_MS,))).unpack()[0]
        idle_ms = im('GetIdletime').unpack()[0]
        if idle_ms >= AWAY_MS:
            put('away', 1)
            arm_active()
        else:
            put('away', 0)
    except GLib.Error:
        put('away', 0)
    return False

def on_watch(conn, sender, path, iface, signal, params):
    wid = params.unpack()[0]
    if wid == watch['idle']:
        put('away', 1)
        try:
            arm_active()                          # one-shot: fires on the next input
        except GLib.Error:
            pass
    elif wid == watch['active']:
        watch['active'] = None
        put('away', 0)

bus.signal_subscribe(None, IM_IFACE, 'WatchFired', IM_PATH, None, Gio.DBusSignalFlags.NONE, on_watch)

# ---------------------------------------------------------------- focused app (X11, event-driven)
APP_CLASSES = {
    'terminal': ('gnome-terminal', 'kitty', 'alacritty', 'konsole', 'xterm', 'tilix', 'wezterm', 'terminator',
                 'foot', 'urxvt', 'xfce4-terminal', 'blackbox', 'ptyxis', 'guake', 'tilda', 'ghostty',
                 'com.mitchellh.ghostty', 'kgx', 'org.gnome.console', 'rio', 'tabby', 'warp', 'contour', 'st-256color',
                 'qterminal', 'lxterminal', 'terminology', 'cool-retro-term', 'hyper'),
    'code': ('code', 'vscodium', 'codium', 'cursor', 'windsurf', 'jetbrains', 'sublime_text', 'zed', 'neovide', 'emacs',
             'android-studio', 'kate', 'lapce', 'pulsar', 'gnome-builder', 'org.gnome.builder', 'geany', 'kdevelop',
             'qtcreator'),
    'files': ('nautilus', 'org.gnome.nautilus', 'nemo', 'thunar', 'dolphin', 'pcmanfm', 'caja', 'krusader',
              'doublecmd', 'spacefm'),
    'browser': ('firefox', 'navigator', 'chrome', 'google-chrome', 'chromium', 'brave', 'vivaldi', 'opera',
                'microsoft-edge', 'zen', 'librewolf', 'floorp', 'waterfox', 'epiphany', 'org.gnome.epiphany',
                'falkon', 'mullvad', 'thorium', 'tor browser', 'qutebrowser'),
}

def app_category(wm_class):
    names = [c.lower() for c in (wm_class or ()) if c]
    for cat, keys in APP_CLASSES.items():
        for n in names:
            if any(n == k or n.startswith(k) for k in keys):
                return cat
    return 'other'

kbd_src = None
try:
    from Xlib import X, display as xdisplay
    xd = xdisplay.Display()
    xroot = xd.screen().root
    NET_ACTIVE = xd.intern_atom('_NET_ACTIVE_WINDOW')
    xroot.change_attributes(event_mask=X.PropertyChangeMask)
    try:                                          # XInput2 raw key presses (python-xlib >= 0.17)
        from Xlib.ext import xinput, ge
        xd.xinput_query_version()                 # announce XI2 to the server
        xroot.xinput_select_events([(xinput.AllMasterDevices, xinput.RawKeyPressMask)])
        GENERIC, RAW_KEY = ge.GenericEventCode, xinput.RawKeyPress
        kbd_src = 'xi2'
    except Exception:
        GENERIC = RAW_KEY = None

    def refresh_app():
        try:
            prop = xroot.get_full_property(NET_ACTIVE, X.AnyPropertyType)
            wid = prop.value[0] if prop and len(prop.value) else 0
            cls = xd.create_resource_object('window', wid).get_wm_class() if wid else None
        except Exception:
            cls = None
        put('app', app_category(cls))

    def on_x(fd, cond):
        # refresh_app() does X round-trips; python-xlib queues any events that arrive meanwhile, and
        # those never make the fd readable again -> keep draining until the queue is really empty.
        for _ in range(20):
            changed = False
            try:
                while xd.pending_events():
                    ev = xd.next_event()
                    if ev.type == X.PropertyNotify and ev.atom == NET_ACTIVE:
                        changed = True
                    elif ev.type == GENERIC and getattr(ev, 'evtype', None) == RAW_KEY:
                        note_key()                # only the fact that a key went down
            except Exception:
                return True
            if not changed:
                break
            refresh_app()
        return True

    GLib.io_add_watch(xd.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN, on_x)
    xd.flush()
    refresh_app()
except Exception:
    pass                                          # no X11 / python-xlib: app stays 'other'

# ---------------------------------------------------------------- typing (any keyboard)
TYPING_S = 1.5
typing = {'last': 0.0, 'on': False}

def note_key():                                   # a key went down (thread-safe: RECORD thread or X handler)
    typing['last'] = time.monotonic()
    if not typing['on']:
        typing['on'] = True
        GLib.idle_add(typing_start)

def typing_start():
    put('typing', 1)
    GLib.timeout_add(300, typing_check)           # runs only while typing
    return False

def typing_check():
    if time.monotonic() - typing['last'] < TYPING_S:
        return True
    typing['on'] = False
    put('typing', 0)
    return False

def record_thread():
    """X RECORD fallback (python-xlib without XInput2): count KeyPress device events."""
    try:
        from Xlib import X, display as xdisplay
        from Xlib.ext import record
        from Xlib.protocol import rq
        rd = xdisplay.Display()
        ctx = rd.record_create_context(0, [record.AllClients], [{
            'core_requests': (0, 0), 'core_replies': (0, 0), 'ext_requests': (0, 0, 0, 0),
            'ext_replies': (0, 0, 0, 0), 'delivered_events': (0, 0), 'device_events': (X.KeyPress, X.KeyPress),
            'errors': (0, 0), 'client_started': False, 'client_died': False}])
        field = rq.EventField(None)

        def cb(reply):
            if reply.category != record.FromServer or reply.client_swapped or not reply.data:
                return
            data = reply.data
            while len(data):
                ev, data = field.parse_binary_value(data, rd.display, None, None)
                if ev.type == X.KeyPress:          # ev.detail (the key) is deliberately never read
                    note_key()
        rd.record_enable_context(ctx, cb)         # blocks for the life of the helper
    except Exception:
        GLib.idle_add(lambda: put('kbd', 'none') and False)

if kbd_src == 'xi2':
    state['kbd'] = 'xi2'
else:
    try:
        from Xlib import display as _d
        if 'RECORD' in _d.Display().list_extensions():
            state['kbd'] = 'record'
            threading.Thread(target=record_thread, daemon=True).start()
    except Exception:
        pass

# ---------------------------------------------------------------- lifetime
def conky_alive():
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open('/proc/%s/cmdline' % pid, 'rb') as f:
                cmd = f.read()
        except OSError:
            continue
        if b'conky' in cmd and b'living-sky' in cmd and b'conky.conf' in cmd:
            return True
    return False

def check_alive():
    if not conky_alive():
        loop.quit()
        return False
    return True

refresh_players()
arm_idle()
put('app', state['app'], force=True)              # always write the full file once at start
loop = GLib.MainLoop()
GLib.timeout_add_seconds(30, check_alive)
for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):    # `living-sky stop` sends TERM: clean up too
    GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, lambda *_: (loop.quit(), False)[1])
try:
    loop.run()
finally:
    try:
        os.remove(PIDF)
    except OSError:
        pass
    try:
        xd.close()
    except Exception:
        pass
