#!/usr/bin/env python3
"""living-sky settings: a small GNOME window for everything in living-sky.conf.

  living-sky settings          (or the "Living Sky" launcher in the app grid, or right-click the panel pet)

Every change is written straight into ~/.config/living-sky/living-sky.conf (its comments and layout are
kept, so hand edits and this window always agree). The running desktop notices within ~5 s: looks apply in
place, structural changes (style, pet, cards, location) make it restart itself.
GTK 4 + libadwaita 1.1 (Ubuntu 22.04 / GNOME 42 and newer).
"""
import json, os, re, subprocess, sys, threading

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

APP_ID = 'io.github.living_sky.Settings'
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), '..'))
CLI = os.path.join(ROOT, 'bin', 'living-sky')
EXAMPLE = os.path.join(ROOT, 'living-sky.conf.example')
CONF = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'living-sky', 'living-sky.conf')
CACHE = os.path.join(os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache'), 'living-sky')
AUTOSTART = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'autostart', 'living-sky.desktop')
EXT_UUID = 'glob@living-sky'
EXT_LINK = os.path.join(os.path.expanduser('~/.local/share/gnome-shell/extensions'), EXT_UUID)
ART = os.path.join(ROOT, 'art')

SCENES = [('lake', 'Lake', 'Mountains over a lake, with reflections'),
          ('forest', 'Forest', 'Pine hills and a cabin; valley mist, a glowing window at night'),
          ('city', 'City', 'A skyline whose windows light up in the evening'),
          ('camp', 'Camp', 'A tent in a forest clearing; the campfire burns from dusk to dawn')]
SEASONS = [('auto', 'Automatic', 'Follows the date for your hemisphere'), ('spring', 'Spring', ''),
           ('summer', 'Summer', ''), ('autumn', 'Autumn', ''), ('winter', 'Winter', 'Snow lies everywhere')]
THEMES = [('glass', 'Glass', 'Frosted glass panes over the wallpaper'), ('cards', 'Cards', 'Solid Catppuccin cards')]
COLOR_SETS = [('auto', 'Follow the sky', 'Accents change with the time of day'),
              ('lavender', 'Lavender', 'Lavender + peach'), ('sakura', 'Sakura', 'Cherry-blossom pink + butter'),
              ('mint', 'Mint', 'Mint + lilac'), ('peach', 'Peach', 'Peach + rose'),
              ('ocean', 'Ocean', 'Sky blue + sea-glass teal'), ('custom', 'Your own', 'Pick two colours')]
PETS = [('mimi', 'Mimi', 'Cheerful, social lavender blob (asleep 00–06)'),
        ('pip', 'Pip', 'Hyper sapphire droplet: hops, splashes in the rain (asleep 00–06:30)'),
        ('bun', 'Bun', 'Sleepy slice of bread: naps and snacks (asleep 22:30–08:30)'),
        ('nyx', 'Nyx', 'A little moon showing tonight\'s phase: awake at night'),
        ('cubo', 'Cubo', 'Studious teal cube with glasses: reads, drinks coffee (asleep 01–07)'),
        ('ember', 'Ember', 'A campfire wisp: flickers with your CPU, a blue pilot light when cold (asleep 01–07)'),
        ('random', 'Pet of the day', 'A different pet every day'),
        ('scene', 'Matches the scene', 'Lake: Pip · Forest: Bun · City: Cubo · Camp: Ember'),
        ('off', 'No pet', '')]
CARDS = [('clock', 'Clock', 'Time, weekday, date, uptime, battery and OS'),
         ('weather', 'Weather', 'Temperature, air quality, wind, sunrise / sunset, moon'),
         ('calendar', 'Calendar', 'This month, today highlighted'),
         ('media', 'Now playing', 'Title, artist and progress from any media player'),
         ('cpu', 'CPU', 'Usage per thread, temperature, clock, fans, load'),
         ('memory', 'Memory', 'RAM, swap, root disk, disk I/O'),
         ('disks', 'Disks', 'Every mounted disk with a usage bar'),
         ('gpu', 'GPU', 'NVIDIA usage, temperature, power, VRAM'),
         ('battery', 'Battery', 'Charge, health, cycles, power draw, time left'),
         ('network', 'Network', 'Wi-Fi, IP address, download / upload')]
CARD_DEFAULT_ON = {'clock', 'weather', 'cpu', 'memory', 'gpu', 'network'}


# ------------------------------------------------------------------ config file (shared with `living-sky set`)
sys.path.insert(0, os.path.join(ROOT, 'core'))
import conf  # noqa: E402

read_conf, write_key = conf.read, conf.write


def color_sets():
    """The colour sets' hex pairs, from core/sky.py (without importing it)."""
    out = {}
    try:
        src = open(os.path.join(ROOT, 'core', 'sky.py'), encoding='utf-8').read()
        for name, a, b in re.findall(r"'(\w+)':\s*\('(#[0-9a-fA-F]{6})',\s*'(#[0-9a-fA-F]{6})'\)", src):
            out[name] = (a, b)
    except OSError:
        pass
    return out


def cli(*args, wait=True):
    if wait:
        return subprocess.run([CLI, *args], capture_output=True, text=True, timeout=60).stdout
    subprocess.Popen([CLI, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def is_running():
    try:
        return cli('status').startswith('running')
    except Exception:
        return False


def gnome_major():
    try:
        v = subprocess.run(['gnome-shell', '--version'], capture_output=True, text=True, timeout=10).stdout
        return int(re.search(r'(\d+)', v).group(1))
    except Exception:
        return None


def ext_state():
    """'enabled' | 'disabled' | 'missing'"""
    if not os.path.exists(EXT_LINK):
        return 'missing'
    try:
        out = subprocess.run(['gnome-extensions', 'info', EXT_UUID], capture_output=True, text=True, timeout=10).stdout
        return 'enabled' if re.search(r'State:\s*(ENABLED|ACTIVE)', out) else 'disabled'
    except Exception:
        return 'disabled'


# ------------------------------------------------------------------ small widgets
def hex_rgba(h):
    c = Gdk.RGBA()
    c.parse(h)
    return c


def rgba_hex(c):
    return '#%02x%02x%02x' % (round(c.red * 255), round(c.green * 255), round(c.blue * 255))


def swatch(colors, size=22):
    """Two overlapping colour dots (primary, secondary)."""
    area = Gtk.DrawingArea()
    area.set_content_width(int(size * 1.7))
    area.set_content_height(size)
    area.set_valign(Gtk.Align.CENTER)
    area.colors = colors

    def draw(_a, cr, w, h, _d=None):
        r = h / 2 - 1
        for i, c in enumerate(reversed(area.colors)):
            x = w - r - 1 if i == 0 else r + 1
            rgba = hex_rgba(c)
            cr.arc(x, h / 2, r, 0, 6.2832)
            cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, 1)
            cr.fill_preserve()
            cr.set_source_rgba(0, 0, 0, 0.25)
            cr.set_line_width(1)
            cr.stroke()
    area.set_draw_func(draw)
    return area


def picture(path, height):
    pic = Gtk.Picture()
    pic.set_keep_aspect_ratio(True)
    pic.set_can_shrink(True)
    pic.set_size_request(-1, height)
    if path and os.path.exists(path):
        pic.set_filename(path)
    frame = Gtk.Frame()
    frame.set_child(pic)
    frame.set_margin_bottom(12)
    frame.pic = pic
    return frame


def combo(title, subtitle, options, current, on_change):
    row = Adw.ComboRow(title=title)
    if subtitle:
        row.set_subtitle(subtitle)
    row.set_model(Gtk.StringList.new([o[1] for o in options]))
    ids = [o[0] for o in options]
    row.set_selected(ids.index(current) if current in ids else 0)

    def changed(r, _p):
        i = r.get_selected()
        if 0 <= i < len(ids):
            on_change(ids[i])
    row.connect('notify::selected', changed)
    row.ids = ids
    return row


def switch_row(title, subtitle, active, on_change):
    row = Adw.ActionRow(title=title)
    if subtitle:
        row.set_subtitle(subtitle)
    sw = Gtk.Switch(active=active, valign=Gtk.Align.CENTER)
    sw.connect('notify::active', lambda s, _p: on_change(s.get_active()))
    row.add_suffix(sw)
    row.set_activatable_widget(sw)
    row.switch = sw
    return row


def entry_row(title, subtitle, text, on_change, width=16, placeholder=''):
    row = Adw.ActionRow(title=title)
    if subtitle:
        row.set_subtitle(subtitle)
    e = Gtk.Entry(text=text, valign=Gtk.Align.CENTER, width_chars=width, placeholder_text=placeholder)
    e.connect('changed', lambda w: on_change(w))
    row.add_suffix(e)
    row.entry = e
    return row


def button(label, cb, style=None, icon=None):
    b = Gtk.Button(valign=Gtk.Align.CENTER)
    if icon:
        b.set_icon_name(icon)
        b.set_tooltip_text(label)
    else:
        b.set_label(label)
    if style:
        b.add_css_class(style)
    b.connect('clicked', lambda *_: cb())
    return b


# ------------------------------------------------------------------ the window
class Settings(Adw.PreferencesWindow):
    def __init__(self, app):
        super().__init__(application=app, title='Living Sky')
        self.set_default_size(780, 860)
        self.set_search_enabled(False)
        self.conf = read_conf()
        self.sets = color_sets()
        self._restart_id = 0
        self.add(self.page_look())
        self.add(self.page_colours())
        self.add(self.page_cards())
        self.add(self.page_location())
        self.add(self.page_system())

    # ---- saving
    def get(self, key, default=''):
        v = self.conf.get(key, '').strip()
        return v if v else default

    def set(self, key, value, before=None, restart=True):
        value = str(value)
        if self.conf.get(key, None) == value:
            return
        self.conf[key] = value
        try:
            write_key(key, value, before)
        except OSError as e:
            self.toast('Could not save: %s' % e)
            return
        if restart:
            self.saved()

    def saved(self, delay=1200):
        """One toast per burst of changes (the desktop applies them itself)."""
        if self._restart_id:
            GLib.source_remove(self._restart_id)
        self._restart_id = GLib.timeout_add(delay, self._saved_toast)

    def _saved_toast(self):
        self._restart_id = 0
        self.toast('Saved: applies within a few seconds' if is_running()
                   else 'Saved. living-sky isn\'t running: start it from System')
        GLib.timeout_add(8000, self.refresh_status)
        return False

    def toast(self, text):
        t = Adw.Toast.new(text)
        t.set_timeout(3)
        self.add_toast(t)

    # ---- Look
    def page_look(self):
        page = Adw.PreferencesPage(title='Look', icon_name='preferences-desktop-wallpaper-symbolic')
        g = Adw.PreferencesGroup(title='Wallpaper', description='The sky follows the real sun, moon and weather; the scene is the land in front of it.')
        scene = self.get('scene', 'lake')
        self.scene_pic = picture(os.path.join(ART, 'demos', 'scene-%s.jpg' % scene), 120)
        g.add(self.scene_pic)

        def on_scene(v):
            self.scene_pic.pic.set_filename(os.path.join(ART, 'demos', 'scene-%s.jpg' % v))
            self.scene_row.set_subtitle(dict((s[0], s[2]) for s in SCENES)[v])
            self.set('scene', v)
        self.scene_row = combo('Scene', dict((s[0], s[2]) for s in SCENES).get(scene, ''), SCENES, scene, on_scene)
        g.add(self.scene_row)
        g.add(combo('Season', 'Light, colours and snow', SEASONS, self.get('season', 'auto'), lambda v: self.set('season', v)))
        g.add(switch_row('Pixel art', 'Draw the wallpaper as chunky dithered pixels',
                         self.get('pixel', 'off') == 'on', lambda on: self.set('pixel', 'on' if on else 'off')))
        row = Adw.ActionRow(title='Redraw every', subtitle='Minutes between new wallpapers (the sky moves slowly)')
        spin = Gtk.SpinButton.new_with_range(5, 240, 5)
        spin.set_valign(Gtk.Align.CENTER)
        try:
            spin.set_value(int(float(self.get('interval_min', '60'))))
        except ValueError:
            spin.set_value(60)
        spin.connect('value-changed', lambda s: self.set('interval_min', s.get_value_as_int()))
        row.add_suffix(spin)
        g.add(row)
        page.add(g)

        g = Adw.PreferencesGroup(title='Cards', description='The column of cards on the right of the screen.')
        theme = self.get('theme', 'glass')
        self.theme_pic = picture(os.path.join(ART, 'demos', '%s-night.jpg' % theme), 220)
        g.add(self.theme_pic)

        def on_theme(v):
            self.theme_pic.pic.set_filename(os.path.join(ART, 'demos', '%s-night.jpg' % v))
            self.set('theme', v)
        g.add(combo('Style', None, THEMES, theme, on_theme))
        g.add(combo('Size', 'Make the cards and the pet bigger on HiDPI screens',
                    [('auto', 'Automatic', ''), ('1', '100 %', ''), ('1.25', '125 %', ''), ('1.5', '150 %', ''),
                     ('1.75', '175 %', ''), ('2', '200 %', '')], self.get('scale', 'auto'), lambda v: self.set('scale', v)))
        page.add(g)
        return page

    # ---- Colours & pet
    def page_colours(self):
        page = Adw.PreferencesPage(title='Colours & Pet', icon_name='applications-graphics-symbolic')
        g = Adw.PreferencesGroup(title='Accent colours',
                                 description='The primary colour is used for the clock and highlights, the secondary for the weekday.')
        cur = self.get('colors', 'auto').lower().replace(' ', '')
        custom = re.match(r'^(#[0-9a-f]{6}),(#[0-9a-f]{6})$', cur)
        sel = 'custom' if custom else (cur if cur in self.sets or cur == 'auto' else 'auto')
        pair = (custom.group(1), custom.group(2)) if custom else ('#b4befe', '#fab387')

        row = combo('Colours', None, COLOR_SETS, sel, lambda v: self.on_colours(v))
        self.colour_row = row
        self.colour_swatch = swatch(self.sets.get(sel, pair) if sel != 'auto' else ('#b4befe', '#f4b8e4'))
        row.add_prefix(self.colour_swatch)
        row.set_subtitle(dict((c[0], c[2]) for c in COLOR_SETS)[sel])
        g.add(row)

        self.custom_rows = []
        for i, label in enumerate(('Primary', 'Secondary')):
            r = Adw.ActionRow(title=label)
            b = Gtk.ColorButton(valign=Gtk.Align.CENTER)
            b.set_rgba(hex_rgba(pair[i]))
            b.connect('color-set', lambda *_: self.on_colours('custom'))
            r.add_suffix(b)
            r.button = b
            r.set_visible(sel == 'custom')
            g.add(r)
            self.custom_rows.append(r)
        page.add(g)

        g = Adw.PreferencesGroup(title='Glob pet', description='Lives on the cards and reacts to the time, the weather, your music and your typing.')
        g.add(picture(os.path.join(ART, 'glob', 'lineup.png'), 110))
        pet = self.get('glob', 'mimi')

        def on_pet(v):
            self.pet_row.set_subtitle(dict((p[0], p[2]) for p in PETS)[v])
            self.set('glob', v)
        self.pet_row = combo('Pet', dict((p[0], p[2]) for p in PETS).get(pet, ''), PETS, pet, on_pet)
        g.add(self.pet_row)
        page.add(g)
        return page

    def on_colours(self, v):
        for r in self.custom_rows:
            r.set_visible(v == 'custom')
        self.colour_row.set_subtitle(dict((c[0], c[2]) for c in COLOR_SETS)[v])
        if v == 'custom':
            a, b = (rgba_hex(r.button.get_rgba()) for r in self.custom_rows)
            self.colour_swatch.colors = (a, b)
            value = '%s, %s' % (a, b)
        else:
            self.colour_swatch.colors = self.sets.get(v, ('#b4befe', '#f4b8e4'))
            value = v
        self.colour_swatch.queue_draw()
        self.set('colors', value)

    # ---- Cards
    def card_order(self):
        ids = [c[0] for c in CARDS]
        given = [x.strip() for x in self.get('cards', '').split(',') if x.strip() in ids]
        seen = []
        for x in given + ids:
            if x not in seen:
                seen.append(x)
        return seen

    def page_cards(self):
        page = Adw.PreferencesPage(title='Cards', icon_name='view-grid-symbolic')
        g = Adw.PreferencesGroup(title='Cards and their order',
                                 description='Cards that don\'t apply to this computer hide themselves (e.g. GPU without an NVIDIA card). '
                                             'Extra cards continue in a second column. The pet sits on the first card.')
        self.card_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self.card_list.add_css_class('boxed-list')
        g.add(self.card_list)
        self.order = self.card_order()
        self.fill_cards()
        page.add(g)

        g = Adw.PreferencesGroup(title='Formats')
        g.add(combo('Units', None, [('metric', 'Metric (°C, km/h)', ''), ('imperial', 'Imperial (°F, mph)', '')],
                    self.get('units', 'metric'), lambda v: self.set('units', v)))
        g.add(combo('Clock', None, [('24h', '24-hour', ''), ('12h', '12-hour (AM / PM)', '')],
                    self.get('clock', '24h'), lambda v: self.set('clock', v)))
        g.add(combo('Calendar weeks start on', None, [('monday', 'Monday', ''), ('sunday', 'Sunday', '')],
                    self.get('week_start', 'monday'), lambda v: self.set('week_start', v)))
        page.add(g)
        return page

    def fill_cards(self):
        while (child := self.card_list.get_first_child()) is not None:
            self.card_list.remove(child)
        info = {c[0]: c for c in CARDS}
        for i, cid in enumerate(self.order):
            _id, title, sub = info[cid]
            on = self.get('card_' + cid, 'on' if cid in CARD_DEFAULT_ON else 'off') == 'on'
            row = Adw.ActionRow(title=title, subtitle=sub)
            up = button('Move up', lambda c=cid: self.move_card(c, -1), 'flat', 'go-up-symbolic')
            down = button('Move down', lambda c=cid: self.move_card(c, 1), 'flat', 'go-down-symbolic')
            up.set_sensitive(i > 0)
            down.set_sensitive(i < len(self.order) - 1)
            sw = Gtk.Switch(active=on, valign=Gtk.Align.CENTER)
            sw.connect('notify::active', lambda s, _p, c=cid: self.set('card_' + c, 'on' if s.get_active() else 'off'))
            for w in (up, down, sw):
                row.add_suffix(w)
            self.card_list.append(row)

    def move_card(self, cid, d):
        i = self.order.index(cid)
        j = i + d
        if not 0 <= j < len(self.order):
            return
        self.order[i], self.order[j] = self.order[j], self.order[i]
        self.fill_cards()
        self.set('cards', ', '.join(self.order), before='card_clock')

    # ---- Location
    def page_location(self):
        page = Adw.PreferencesPage(title='Location', icon_name='mark-location-symbolic')
        g = Adw.PreferencesGroup(title='Where you are', description='Used for the sun, the moon, the seasons and the weather. '
                                 'Automatic looks it up once from your IP address (ipinfo.io / ipapi.co) and remembers it.')
        manual = bool(self.get('lat')) and bool(self.get('lon'))
        self.loc_auto = combo('Location', None, [('auto', 'Automatic', ''), ('manual', 'Set it myself', '')], 'manual' if manual else 'auto', self.on_loc_mode)
        g.add(self.loc_auto)
        self.loc_now = Adw.ActionRow(title='Currently')
        self.loc_now.set_subtitle(self.current_place())
        g.add(self.loc_now)
        self.lat_row = entry_row('Latitude', 'Decimal degrees, north positive', self.get('lat'), lambda e: self.on_coord(), 12, 'e.g. 48.86')
        self.lon_row = entry_row('Longitude', 'Decimal degrees, east positive', self.get('lon'), lambda e: self.on_coord(), 12, 'e.g. 2.35')
        self.name_row = entry_row('Place name', 'Shown on the weather card', self.get('name'), lambda e: self.on_coord(), 16, 'e.g. Paris')
        for r in (self.lat_row, self.lon_row, self.name_row):
            r.set_visible(manual)
            g.add(r)
        page.add(g)
        return page

    def current_place(self):
        try:
            d = json.load(open(os.path.join(CACHE, 'location.json')))
            return '%s (%.2f, %.2f)' % (d.get('name') or 'unnamed', float(d['lat']), float(d['lon']))
        except Exception:
            return 'Not looked up yet'

    def on_loc_mode(self, v):
        for r in (self.lat_row, self.lon_row, self.name_row):
            r.set_visible(v == 'manual')
        if v == 'auto':
            self.set('lat', '', restart=False)
            self.set('lon', '', restart=False)
            self.set('name', '', restart=False)
            self.set('geo', 'auto')
        else:
            self.on_coord()

    def on_coord(self):
        def num(row, lo, hi):
            t = row.entry.get_text().strip()
            try:
                v = float(t)
                ok = lo <= v <= hi
            except ValueError:
                ok = False
            (row.entry.remove_css_class if ok else row.entry.add_css_class)('error')
            return t if ok else None
        lat, lon = num(self.lat_row, -90, 90), num(self.lon_row, -180, 180)
        if lat is None or lon is None:
            return
        self.set('lat', lat, restart=False)
        self.set('lon', lon, restart=False)
        self.set('name', self.name_row.entry.get_text().strip(), restart=False)
        self.set('geo', 'off', restart=False)
        self.saved(2500)

    # ---- System
    def page_system(self):
        page = Adw.PreferencesPage(title='System', icon_name='emblem-system-symbolic')
        g = Adw.PreferencesGroup(title='living-sky')
        self.status_row = Adw.ActionRow(title='Status')
        self.btn_start = button('Start', lambda: self.run_and_refresh('start'), 'suggested-action')
        self.btn_restart = button('Restart', lambda: self.run_and_refresh('restart'))
        self.btn_stop = button('Stop', lambda: self.run_and_refresh('stop'))
        for b in (self.btn_start, self.btn_restart, self.btn_stop):
            self.status_row.add_suffix(b)
        g.add(self.status_row)
        g.add(switch_row('Start when you log in', None, os.path.exists(AUTOSTART), self.set_autostart))
        self.ext_row = Adw.ActionRow(title='Pet in the top panel', subtitle='GNOME Shell extension')
        self.ext_switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.ext_switch.connect('notify::active', self.on_ext)
        self.ext_row.add_suffix(self.ext_switch)
        self.ext_row.set_activatable_widget(self.ext_switch)
        g.add(self.ext_row)
        page.add(g)

        g = Adw.PreferencesGroup(title='Updates')
        self.update_row = Adw.ActionRow(title='Version', subtitle=self.version())
        self._update_ready = False
        self.update_btn = button('Check for updates', lambda: self.do_update() if self._update_ready else self.check_updates())
        self.update_row.add_suffix(self.update_btn)
        g.add(self.update_row)
        page.add(g)

        g = Adw.PreferencesGroup(title='Help')
        r = Adw.ActionRow(title='Diagnostics', subtitle='What was detected, your settings and recent errors (for bug reports)')
        r.add_suffix(button('Show', self.show_doctor))
        g.add(r)
        r = Adw.ActionRow(title='Edit the settings file', subtitle=CONF.replace(os.path.expanduser('~'), '~'))
        r.add_suffix(button('Open', lambda: Gtk.show_uri(self, 'file://' + (CONF if os.path.exists(CONF) else EXAMPLE), 0)))
        g.add(r)
        r = Adw.ActionRow(title='Uninstall', subtitle='Stop it, restore your wallpaper, remove the command, launcher and autostart')
        r.add_suffix(button('Uninstall…', self.confirm_uninstall, 'destructive-action'))
        g.add(r)
        page.add(g)
        self.refresh_status()
        return page

    def refresh_status(self):
        on = is_running()
        self.status_row.set_subtitle('Running (%s style)' % self.get('theme', 'glass') if on else 'Not running')
        self.btn_start.set_visible(not on)
        self.btn_restart.set_visible(on)
        self.btn_stop.set_visible(on)
        st = ext_state()
        self._ext_syncing = True
        self.ext_switch.set_active(st == 'enabled')
        self._ext_syncing = False
        self.ext_row.set_subtitle({'enabled': 'GNOME Shell extension: on', 'disabled': 'GNOME Shell extension: off',
                                   'missing': 'GNOME Shell extension: not installed (turning it on installs it)'}[st])
        return False

    def run_and_refresh(self, cmd):
        def work():
            try:
                cli(cmd)
            finally:
                GLib.idle_add(self.refresh_status)
        threading.Thread(target=work, daemon=True).start()

    def set_autostart(self, on):
        if on:
            os.makedirs(os.path.dirname(AUTOSTART), exist_ok=True)
            with open(AUTOSTART, 'w') as f:
                f.write('[Desktop Entry]\nType=Application\nName=living-sky\n'
                        'Comment=Living-sky wallpaper, cards and glob pet (conky)\n'
                        'Exec=%s start\nX-GNOME-Autostart-Delay=5\nX-GNOME-Autostart-enabled=true\n' % CLI)
            self.toast('living-sky will start when you log in')
        else:
            try:
                os.remove(AUTOSTART)
            except FileNotFoundError:
                pass
            self.toast('Won\'t start at login')

    def on_ext(self, sw, _p):
        if getattr(self, '_ext_syncing', False):
            return
        on = sw.get_active()
        if on and not os.path.exists(EXT_LINK):
            major = gnome_major()
            if major is None:
                self.toast('GNOME Shell not found')
                return self.refresh_status()
            src = os.path.join(ROOT, 'gnome-extension', EXT_UUID)
            if major >= 45:
                src = os.path.join(ROOT, 'gnome-extension', 'build', EXT_UUID)
                subprocess.run([sys.executable, os.path.join(ROOT, 'gnome-extension', 'build-esm.py'), src], capture_output=True)
            os.makedirs(os.path.dirname(EXT_LINK), exist_ok=True)
            os.symlink(src, EXT_LINK)
        r = subprocess.run(['gnome-extensions', 'enable' if on else 'disable', EXT_UUID], capture_output=True, text=True)
        if on and r.returncode != 0:
            self.toast('Installed: GNOME loads it after you log out and back in')
        GLib.timeout_add(800, self.refresh_status)

    # ---- updates
    def git(self, *args):
        return subprocess.run(['git', '-C', ROOT, *args], capture_output=True, text=True, timeout=60)

    def version(self):
        if not os.path.isdir(os.path.join(ROOT, '.git')):
            return 'Installed from a download'
        r = self.git('log', '-1', '--format=%h · %cd', '--date=short')
        return r.stdout.strip() or 'unknown'

    def check_updates(self):
        if not os.path.isdir(os.path.join(ROOT, '.git')):
            self.update_row.set_subtitle('Download the latest release to update')
            return
        if not self.git('remote').stdout.strip():
            self.update_row.set_subtitle('%s · no update source (this copy isn\'t linked to GitHub)' % self.version())
            return
        self.update_btn.set_sensitive(False)
        self.update_row.set_subtitle('Checking…')

        def work():
            f = self.git('fetch', '--quiet')
            behind = self.git('rev-list', '--count', 'HEAD..@{u}').stdout.strip() if f.returncode == 0 else ''
            GLib.idle_add(self.updates_checked, f.returncode == 0, behind)
        threading.Thread(target=work, daemon=True).start()

    def updates_checked(self, ok, behind):
        self.update_btn.set_sensitive(True)
        if not ok:
            self.update_row.set_subtitle('%s · could not reach the update source' % self.version())
        elif behind in ('', '0'):
            self.update_row.set_subtitle('%s · up to date' % self.version())
        else:
            self.update_row.set_subtitle('%s · %s new change%s' % (self.version(), behind, '' if behind == '1' else 's'))
            self.update_btn.set_label('Update now')
            self.update_btn.add_css_class('suggested-action')
            self._update_ready = True
        return False

    def do_update(self):
        r = self.git('pull', '--ff-only', '--quiet')
        if r.returncode == 0:
            self.toast('Updated')
            self.update_row.set_subtitle('%s · up to date' % self.version())
            self.update_btn.set_label('Check for updates')
            self.update_btn.remove_css_class('suggested-action')
            self._update_ready = False
            if is_running():
                cli('restart', wait=False)
        else:
            self.toast('Could not update: you have local changes (see Diagnostics)')

    # ---- help
    def show_doctor(self):
        text = re.sub(r'\x1b\[[0-9;]*m', '', cli('doctor'))
        win = Adw.Window(transient_for=self, modal=True, title='Diagnostics', default_width=720, default_height=640)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        head = Adw.HeaderBar()
        head.set_title_widget(Adw.WindowTitle(title='Diagnostics', subtitle='Paste this into a bug report'))
        copy = button('Copy', lambda: (Gdk.Display.get_default().get_clipboard().set(text), self.toast('Copied')), 'suggested-action')
        head.pack_start(copy)
        box.append(head)
        view = Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                            left_margin=12, right_margin=12, top_margin=12, bottom_margin=12)
        view.get_buffer().set_text(text)
        sc = Gtk.ScrolledWindow(vexpand=True)
        sc.set_child(view)
        box.append(sc)
        win.set_content(box)
        win.present()

    def confirm_uninstall(self):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                              buttons=Gtk.ButtonsType.NONE, text='Uninstall living-sky?')
        d.set_property('secondary-text', 'It stops, your previous wallpaper comes back, and the command, launcher, autostart '
                                         'and panel pet are removed. Your settings and the project folder are kept.')
        d.add_button('Cancel', Gtk.ResponseType.CANCEL)
        d.add_button('Uninstall', Gtk.ResponseType.ACCEPT).add_css_class('destructive-action')

        def resp(dlg, r):
            dlg.destroy()
            if r == Gtk.ResponseType.ACCEPT:
                subprocess.run([os.path.join(ROOT, 'uninstall.sh')], capture_output=True)
                self.get_application().quit()
        d.connect('response', resp)
        d.present()


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.win = None

    def do_activate(self):
        if self.win is None:
            self.win = Settings(self)
        self.win.present()


if __name__ == '__main__':
    sys.exit(App().run(sys.argv[:1]))
