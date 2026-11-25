// Animation frames of a glob pet for the README GIFs: a short loop through everyday moments,
// plus the pet's own (def.animExtra).
//   GLOB_PET=pip gjs tools/anim.js <frames-dir>   -> <frames-dir>/0000.png ... (then: tools/gif.py)
// Drawn with pets/core.js at 10 fps on a card-coloured tile, like tools/showcase.js.
'use strict';
const {GLib} = imports.gi;
const Cairo = imports.cairo;
const here = GLib.path_get_dirname(GLib.path_get_dirname(GLib.canonicalize_filename(imports.system.programInvocationName, null)));
imports.searchPath.unshift(here);
const Draw = imports.pets.core;
const PET_ID = (typeof PET_ARG !== 'undefined' && PET_ARG) || GLib.getenv('GLOB_PET') || 'mimi';
const DEF = imports.pets[PET_ID].def;

const dir = ARGV[0] || 'mimi-frames';
GLib.mkdir_with_parents(dir, 0o755);
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
const COLORS = {accent: hex('#b4befe'), accent2: hex('#fab387'), text: hex('#cdd6f4'), subtext0: hex('#a6adc8'),
    overlay2: hex('#9399b2'), red: hex('#f38ba8'), yellow: hex('#f9e2af'), pink: hex('#f5c2e7'), sky: hex('#89dceb'),
    blue: hex('#89b4fa'), peach: hex('#fab387'), shadow: hex('#11111b'), base: hex('#1e1e2e'),
    lavender: hex('#b4befe'), mauve: hex('#cba6f7'), teal: hex('#94e2d5'), sapphire: hex('#74c7ec'), green: hex('#a6e3a1')};
const BODY = DEF.swatch ? hex(DEF.swatch) : COLORS.accent;

// [seconds, state overrides]; a new act starts at each segment
const SCRIPT = [
    [2.0, {}],
    [1.2, {act: 'hop', act_dur: 1.0}],
    [2.0, {act: 'wave', act_dur: 2.0}],
    [3.0, {act: 'typing', act_dur: 3.0, type_kind: 'code'}],
    ...(DEF.animExtra && DEF.animExtra.length ? DEF.animExtra : [[3.0, {act: 'coffee', act_dur: 3.0}]]),
    [2.4, {act: 'heart', act_dur: 2.4}],
    [2.5, {mood: 'music'}],
    [2.0, {act: 'sideeye', act_dur: 2.0}],
    [1.5, {}],
];
const FPS = 10, TW = 240, TH = 200;

const A = Draw.newAnim();
let t = 100, n = 0, id = 1;
for (const [secs, over] of SCRIPT) {
    const S = Object.assign({mood: 'awake', weather: 'clear', mask: 0, shades: false, dozing: false,
        act: '', act_id: 0, act_dur: 0, light: false, colors: COLORS, body: BODY}, over, {act_id: id++});
    for (let f = 0; f < secs * FPS; f++, t += 1 / FPS) {
        const surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, TW, TH);
        const cr = new Cairo.Context(surf);
        const g = new Cairo.LinearGradient(0, 0, 0, TH);
        g.addColorStopRGBA(0, 0.15, 0.15, 0.22, 1); g.addColorStopRGBA(1, 0.11, 0.11, 0.17, 1);
        cr.setSource(g); cr.paint();
        cr.rectangle(40, 172, TW - 80, 1.2); cr.setSourceRGBA(1, 1, 1, 0.10); cr.fill();
        cr.save(); cr.translate(TW / 2 - 110, 30);
        Draw.drawPet(cr, S, A, t, 220, 148, DEF);
        cr.restore();
        surf.writeToPNG(`${dir}/${String(n++).padStart(4, '0')}.png`);
        cr.$dispose();
    }
}
print('wrote', n, 'frames to', dir);
