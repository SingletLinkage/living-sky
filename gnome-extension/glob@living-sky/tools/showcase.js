// Showcase sheet: every look of a glob pet, labelled, grouped by section.
//   GLOB_PET=pip gjs tools/showcase.js ../../art/glob/pip/showcase.png     (default pet: mimi)
'use strict';
const {GLib} = imports.gi;
const Cairo = imports.cairo;
const here = GLib.path_get_dirname(GLib.path_get_dirname(GLib.canonicalize_filename(imports.system.programInvocationName, null)));
imports.searchPath.unshift(here);
const Draw = imports.pets.core;
const PET_ID = (typeof PET_ARG !== 'undefined' && PET_ARG) || GLib.getenv('GLOB_PET') || 'mimi';
const DEF = imports.pets[PET_ID].def;

const out = ARGV[0] || 'mimi-showcase.png';
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
const MOCHA = {accent: hex('#b4befe'), accent2: hex('#fab387'), text: hex('#cdd6f4'), subtext0: hex('#a6adc8'),
    overlay2: hex('#9399b2'), red: hex('#f38ba8'), yellow: hex('#f9e2af'), pink: hex('#f5c2e7'), sky: hex('#89dceb'),
    blue: hex('#89b4fa'), peach: hex('#fab387'), shadow: hex('#11111b'), base: hex('#1e1e2e')};
const FRAPPE = Object.assign({}, MOCHA, {accent: hex('#f4b8e4'), accent2: hex('#ca9ee6'), text: hex('#c6d0f5'), pink: hex('#f4b8e4')});
const MORE = {lavender: hex('#b4befe'), mauve: hex('#cba6f7'), teal: hex('#94e2d5'), sapphire: hex('#74c7ec'), green: hex('#a6e3a1')};
Object.assign(MOCHA, MORE);
const LATTE = Object.assign({}, MOCHA, {accent: hex('#1a5ad8'), accent2: hex('#c14c08'), text: hex('#3a3c50'),
    overlay2: hex('#595b6a'), pink: hex('#a85592'), red: hex('#c50e36'), yellow: hex('#9c6314'), shadow: hex('#4c4f69')});

// [label, state overrides, action progress (0..1) or extra anim tweaks]
const SECTIONS = [
    ['Moods', [
        ['Awake', {}],
        ['Dancing to music', {mood: 'music'}, {t: 0.5}],
        ['Watching a video', {mood: 'watch'}],
        ['Drowsy', {mood: 'drowsy'}, {yawn: true}],
        ['Asleep', {mood: 'sleep'}],
        ['Waking up', {mood: 'wake'}, {t: 1.0}],
        ['Napping (you\'re away)', {dozing: true}],
    ]],
    ['Weather & sun', [
        ['Rain', {weather: 'rain'}],
        ['Thunderstorm', {weather: 'storm'}, {flash: true}],
        ['Snow', {weather: 'snow'}],
        ['Cold (≤ 5 °C)', {weather: 'cold'}],
        ['Fog', {weather: 'fog'}, {t: 3.0}],
        ['Strong sun', {shades: true}],
    ]],
    ['Air quality', [
        ['AQI 101–150', {mask: 1}],
        ['AQI 151–200', {mask: 2}],
        ['AQI 200+', {mask: 3}],
        ['Sneeze (bad air)', {mask: 1, act: 'sneeze', act_dur: 1.4}, {p: 0.7}],
        ['Music + rain + N95', {mood: 'music', weather: 'rain', mask: 2}],
        ['Sun + music', {mood: 'music', shades: true}],
    ]],
    ['Knows what you\'re doing', [
        ['Typing with you', {act: 'typing', act_dur: 9}, {p: 0.3}],
        ['Typing in a terminal', {act: 'typing', act_dur: 9, type_kind: 'term'}, {p: 0.25}],
        ['Typing code', {act: 'typing', act_dur: 9, type_kind: 'code'}, {p: 0.3}],
        ['Browsing files', {act: 'search', act_dur: 3}, {p: 0.17}],
        ['Hot CPU: this is fine', {hot: true}],
    ]],
    ['Clicks, snacks & moods (panel)', [
        ['Poke: squish', {act: 'squish', act_dur: 0.9}, {p: 0.3}],
        ['Double-click: heart', {act: 'heart', act_dur: 2.4}, {p: 0.35}],
        ['Woken at night: grumpy', {mood: 'grumpy', grumpy: 'woken'}],
        ['Hmph (huff)', {mood: 'grumpy', grumpy: 'woken', act: 'huff', act_dur: 1.4}, {p: 0.65}],
        ['Ignored too long', {grumpy: 'ignored'}],
        ['Snack time', {act: 'eat', act_dur: 3.2}, {p: 0.05}],
    ]],
    ['Actions', [
        ['Wave', {act: 'wave', act_dur: 2.0}, {p: 0.12}],
        ['Morning coffee', {act: 'coffee', act_dur: 3.0}, {p: 0.2}],
        ['...sip', {act: 'coffee', act_dur: 3.0}, {p: 0.5}],
        ['Side-eye', {act: 'sideeye', act_dur: 2.0}, {p: 0.5}],
        ['Dance', {act: 'dance', act_dur: 2.5}, {t: 0.5, p: 0.2}],
        ['Hop', {act: 'hop', act_dur: 1.0}, {p: 0.5}],
        ['Jelly wobble', {act: 'wobble', act_dur: 1.6}, {p: 0.12}],
        ['Sway', {act: 'sway', act_dur: 2.0}, {p: 0.12}],
        ['Curious', {act: 'curious', act_dur: 2.6}, {p: 0.5}],
        ['Heart', {act: 'heart', act_dur: 2.4}, {p: 0.35}],
        ['Look around', {act: 'look', act_dur: 2.0}, {p: 0.15}],
        ['Top of the hour', {act: 'chime', act_dur: 3.2}, {p: 0.45}],
        ['You\'re back!', {act: 'startle', act_dur: 1.4}, {p: 0.35}],
    ]],
    ...(DEF.showcase && DEF.showcase.length ? [['Only ' + DEF.name, DEF.showcase]] : []),
    ['Follows the sky palette', [
        ['Night', {}, {pal: 'mocha'}],
        ['Dusk', {}, {pal: 'frappe'}],
        ['Day', {light: true}, {pal: 'latte'}],
    ]],
];

const COLS = 6, TW = 200, TH = 190, GAP = 16, M = 40, HEAD = 46, TITLE = 120;
let rowsTotal = 0;
for (const [, items] of SECTIONS) rowsTotal += Math.ceil(items.length / COLS);
const WIDTH = M * 2 + COLS * TW + (COLS - 1) * GAP;
const HEIGHT = TITLE + SECTIONS.length * HEAD + rowsTotal * (TH + GAP) + M;

const surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, WIDTH, HEIGHT);
const cr = new Cairo.Context(surf);
const bg = new Cairo.LinearGradient(0, 0, 0, HEIGHT);
bg.addColorStopRGBA(0, 0.09, 0.09, 0.14, 1); bg.addColorStopRGBA(1, 0.05, 0.05, 0.09, 1);
cr.setSource(bg); cr.paint();

function text(s, x, y, size, col, bold, align) {
    cr.selectFontFace('JetBrains Mono', Cairo.FontSlant.NORMAL, bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
    cr.setFontSize(size);
    const e = cr.textExtents(s);
    const xx = align === 'c' ? x - e.xAdvance / 2 : x;
    cr.setSourceRGBA(col[0], col[1], col[2], col[3] ?? 1); cr.moveTo(xx, y); cr.showText(s);
}
function rrect(x, y, w, h, r) {
    cr.newSubPath();
    cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0); cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
    cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI); cr.arc(x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
    cr.closePath();
}

const SWATCH = DEF.swatch ? hex(DEF.swatch) : null;
text(DEF.name, M, 66, 40, SWATCH || MOCHA.accent, true);
text('a glob pet from living-sky: lives on the desktop cards, reacts to time, weather, air, music and typing',
    M + 150, 62, 15, [...MOCHA.subtext0, 1]);
text('desktop widget (conky + Lua/cairo) · GNOME top-panel extension · living-sky wallpaper', M + 150, 86, 13, [...MOCHA.overlay2, 1]);

let y = TITLE;
let seed = 1;
for (const [title, items] of SECTIONS) {
    text(title.toUpperCase(), M, y + 26, 14, MOCHA.accent2, true);
    cr.rectangle(M, y + 34, WIDTH - 2 * M, 1); cr.setSourceRGBA(1, 1, 1, 0.08); cr.fill();
    y += HEAD;
    items.forEach(([label, over, extra = {}], i) => {
        const cx = M + (i % COLS) * (TW + GAP), cy = y + Math.floor(i / COLS) * (TH + GAP);
        const pal = extra.pal === 'latte' ? LATTE : extra.pal === 'frappe' ? FRAPPE : MOCHA;
        const lightTile = extra.pal === 'latte';
        // tile
        rrect(cx, cy, TW, TH, 18);
        const g = new Cairo.LinearGradient(0, cy, 0, cy + TH);
        if (lightTile) { g.addColorStopRGBA(0, 0.87, 0.91, 0.98, 1); g.addColorStopRGBA(1, 0.78, 0.84, 0.95, 1); }
        else if (extra.pal === 'frappe') { g.addColorStopRGBA(0, 0.23, 0.22, 0.33, 1); g.addColorStopRGBA(1, 0.36, 0.27, 0.38, 1); }
        else { g.addColorStopRGBA(0, 0.15, 0.15, 0.22, 1); g.addColorStopRGBA(1, 0.11, 0.11, 0.17, 1); }
        cr.setSource(g); cr.fillPreserve();
        cr.setSourceRGBA(1, 1, 1, lightTile ? 0.6 : 0.09); cr.setLineWidth(1); cr.stroke();
        // ground line the blob sits on
        cr.rectangle(cx + 40, cy + 142, TW - 80, 1.2); cr.setSourceRGBA(1, 1, 1, lightTile ? 0.5 : 0.10); cr.fill();
        // blob
        const S = Object.assign({mood: 'awake', weather: 'clear', mask: 0, shades: false, dozing: false,
            act: '', act_id: 0, act_dur: 0, light: false, colors: pal}, over, {act_id: seed++});
        // body colour as the desktop would send it: the pet's own colour, or the accent (Mimi); lighter on day cards
        const body0 = SWATCH || pal.accent;
        S.body = lightTile ? body0.map(v => v + (1 - v) * (DEF.swatch ? 0.3 : 0.45)) : body0;
        const A = Draw.newAnim();
        const t0 = 1000;
        Draw.tick(S, A, t0, DEF);                         // starts the action at t0
        A.blinkAt = A.nextGlance = A.nextYawn = 1e12;
        A.blinkUntil = A.glanceUntil = -1; A.flashUntil = -1;
        if (extra.yawn) A.yawnUntil = 1e12;
        if (extra.flash) A.flashUntil = 1e12;
        const t = t0 + (extra.p !== undefined ? extra.p * (S.act_dur || 1) : (extra.t ?? 0.9));
        cr.save();
        cr.translate(cx + TW / 2 - 110, cy + 2);
        Draw.drawPet(cr, S, A, t, 220, 148, DEF);
        cr.restore();
        text(label, cx + TW / 2, cy + TH - 18, 13.5, lightTile ? [0.23, 0.24, 0.31, 1] : [...MOCHA.text, 1], false, 'c');
    });
    y += Math.ceil(items.length / COLS) * (TH + GAP);
}
surf.writeToPNG(out);
print('wrote', out, WIDTH + 'x' + HEIGHT);
