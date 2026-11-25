// Glob for GNOME 45+ (ES modules). Same behaviour as ../glob@living-sky/extension.js (GNOME 42-44);
// the pet drawing (pets/*.js) is shared: build-esm.py turns it into modules next to this file.
// Shows the living-sky pet in the top panel from ~/.cache/living-sky/glob.json; left-click pokes it,
// double-click gives a heart (or wakes it, grumpy, when asleep). Clicks go to ~/.cache/living-sky/glob_cmd.
import GObject from 'gi://GObject';
import St from 'gi://St';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Clutter from 'gi://Clutter';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as Core from './pets/core.js';
import {def as mimi} from './pets/mimi.js';
import {def as pip} from './pets/pip.js';
import {def as bun} from './pets/bun.js';
import {def as nyx} from './pets/nyx.js';
import {def as cubo} from './pets/cubo.js';
import {def as ember} from './pets/ember.js';

const PETS = {mimi, pip, bun, nyx, cubo, ember};       // pet id -> definition
const STATE = GLib.build_filenamev([GLib.get_user_cache_dir(), 'living-sky', 'glob.json']);
const CMD = GLib.build_filenamev([GLib.get_user_cache_dir(), 'living-sky', 'glob_cmd']);
const DOUBLE_MS = 350;
const W = 56, H = 36;           // drawing area (px)
const FRAME_MS = 200;           // 5 fps
const STALE_S = 90;             // conky rewrites at least every 30 s
const decoder = new TextDecoder();

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
        this._poll();
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
            const mtime = secs * 1e6 + info.get_attribute_uint32('time::modified-usec');
            if (GLib.get_real_time() / 1e6 - secs < STALE_S) {
                if (mtime !== this._stamp || !this._state) {
                    const [ok, bytes] = GLib.file_get_contents(STATE);
                    if (ok)
                        state = JSON.parse(decoder.decode(bytes));
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
            console.error('glob:', e);
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
            if (pet !== this._pet) {
                this._pet = pet;
                this._anim = Core.newAnim();
            }
            Core.drawPet(cr, this._state, this._anim, GLib.get_monotonic_time() / 1e6, w, h, pet);
        } catch (e) {
            console.error('glob:', e);
        }
        cr.$dispose();
    }

    destroy() {
        if (this._frameId)
            GLib.source_remove(this._frameId);
        this._frameId = 0;
        super.destroy();
    }
});

export default class GlobExtension extends Extension {
    enable() {
        this._button = new GlobButton();
        Main.panel.addToStatusArea(this.uuid, this._button, 0, 'right');
    }

    disable() {
        this._button?.destroy();
        this._button = null;
    }
}
