// Glob: shows the living-sky pet (lua/glob/<pet>.lua) in the GNOME top panel.
// The conky Lua writes ~/.cache/living-sky/glob.json (pet, mood, accessories, action, palette);
// this extension only draws it with the matching pets/<pet>.js, animated locally at ~5 fps.
// Hidden while that file is stale (living-sky not running).
// Left-click pokes the pet; double-click = heart (or, while it's asleep, wakes it for 10 min, grumpy).
// No menu. Clicks are sent to the conky brain via ~/.cache/living-sky/glob_cmd ("<id> <verb>"); the reaction
// comes back through glob.json, so the desktop and panel pet always do the same thing.
/* exported init, enable, disable */
'use strict';
const {GObject, St, GLib, Gio, Clutter} = imports.gi;
const ByteArray = imports.byteArray;
const Main = imports.ui.main;
const PanelMenu = imports.ui.panelMenu;
const Me = imports.misc.extensionUtils.getCurrentExtension();
const Core = Me.imports.pets.core;              // shared drawing (newAnim, drawPet)
const PETS = {};                                // pet id -> definition (pets/<id>.js)
for (const id of ['mimi', 'pip', 'bun', 'nyx', 'cubo', 'ember'])
    PETS[id] = Me.imports.pets[id].def;

const STATE = GLib.build_filenamev([GLib.get_user_cache_dir(), 'living-sky', 'glob.json']);
const CMD = GLib.build_filenamev([GLib.get_user_cache_dir(), 'living-sky', 'glob_cmd']);
const DOUBLE_MS = 350;
const W = 56, H = 36;           // drawing area (px)
const FRAME_MS = 200;           // 5 fps
const STALE_S = 90;             // conky rewrites at least every 30 s

const GlobButton = GObject.registerClass(
class GlobButton extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Glob', true);           // no menu
        this._area = new St.DrawingArea({width: W, height: H, y_align: Clutter.ActorAlign.CENTER});
        this._area.connect('repaint', area => this._repaint(area));
        this.add_child(this._area);
        this._pet = null;
        this._anim = null;
        this._state = null;
        this._stamp = null;

        this._lastClick = 0;

        // one timer: check the state file (a stat; re-read only when it changed), then repaint
        this._poll();
        this._pollId = 0;
        this._frameId = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, FRAME_MS, () => {
            this._poll();
            if (this._state && this.container.visible)
                this._area.queue_repaint();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _poll() {
        let state = null;
        try {
            const info = Gio.File.new_for_path(STATE).query_info('time::modified,time::modified-usec',
                Gio.FileQueryInfoFlags.NONE, null);
            const secs = info.get_attribute_uint64('time::modified');
            // sub-second stamp: the file can change several times within one second (e.g. typing on/off)
            const mtime = secs * 1e6 + info.get_attribute_uint32('time::modified-usec');
            if (GLib.get_real_time() / 1e6 - secs < STALE_S) {
                if (mtime !== this._stamp || !this._state) {
                    const [ok, bytes] = GLib.file_get_contents(STATE);
                    if (ok)
                        state = JSON.parse(ByteArray.toString(bytes));
                    this._stamp = mtime;
                } else {
                    state = this._state;
                }
            }
        } catch (e) {
            state = null;
        }
        this._state = state;
        this.container.visible = !!state;
    }

    _send(verb) {
        try {
            GLib.file_set_contents(CMD, `${Date.now()} ${verb}\n`);
        } catch (e) {
            logError(e, 'glob');
        }
    }

    vfunc_event(event) {
        const type = event.type();
        if (type === Clutter.EventType.BUTTON_PRESS || type === Clutter.EventType.TOUCH_BEGIN) {
            const button = type === Clutter.EventType.BUTTON_PRESS ? event.get_button() : 1;
            if (button === 1) {
                const now = GLib.get_monotonic_time() / 1000;
                this._send(now - this._lastClick < DOUBLE_MS ? 'heart' : 'poke');
                this._lastClick = now;
            } else if (button === 3) {                  // right-click: the settings window
                try {
                    const app = Gio.DesktopAppInfo.new('io.github.living_sky.Settings.desktop');
                    if (app)
                        app.launch([], null);
                } catch (e) {
                    logError(e, 'glob');
                }
            }
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _repaint(area) {
        const cr = area.get_context();
        const [w, h] = area.get_surface_size ? area.get_surface_size() : [area.get_width(), area.get_height()];
        try {
            const id = (this._state && this._state.pet) || 'mimi';
            const pet = PETS[id] || PETS.mimi;
            if (pet !== this._pet) {             // pet changed: fresh local animation state
                this._pet = pet;
                this._anim = Core.newAnim();
            }
            Core.drawPet(cr, this._state, this._anim, GLib.get_monotonic_time() / 1e6, w, h, pet);
        } catch (e) {
            logError(e, 'glob');
        }
        cr.$dispose();
    }

    destroy() {
        if (this._pollId)
            GLib.source_remove(this._pollId);
        if (this._frameId)
            GLib.source_remove(this._frameId);
        this._pollId = this._frameId = 0;
        super.destroy();
    }
});

let button = null;

function init() {}

function enable() {
    button = new GlobButton();
    // left end of the right box (just before the tray / status icons)
    Main.panel.addToStatusArea('glob', button, 0, 'right');
}

function disable() {
    if (button)
        button.destroy();
    button = null;
}
