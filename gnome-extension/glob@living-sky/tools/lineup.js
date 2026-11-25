// "Meet the globs": every pet side by side with its name and one line about it.
//   gjs tools/lineup.js ../../art/glob/lineup.png
'use strict';
const {GLib} = imports.gi;
const Cairo = imports.cairo;
const here = GLib.path_get_dirname(GLib.path_get_dirname(GLib.canonicalize_filename(imports.system.programInvocationName, null)));
imports.searchPath.unshift(here);
const Draw = imports.pets.core;

const out = ARGV[0] || 'lineup.png';
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
const COLORS = {accent: hex('#b4befe'), accent2: hex('#fab387'), text: hex('#cdd6f4'), subtext0: hex('#a6adc8'),
    overlay2: hex('#9399b2'), red: hex('#f38ba8'), yellow: hex('#f9e2af'), pink: hex('#f5c2e7'), sky: hex('#89dceb'),
    blue: hex('#89b4fa'), peach: hex('#fab387'), shadow: hex('#11111b'), base: hex('#1e1e2e'),
    lavender: hex('#b4befe'), mauve: hex('#cba6f7'), teal: hex('#94e2d5'), sapphire: hex('#74c7ec'), green: hex('#a6e3a1')};
const PETS = [
    ['mimi', 'cheerful and social', 'a lavender blob'],
    ['pip', 'hyper; loves the rain', 'short-tempered, forgives fast'],
    ['bun', 'sleepy slice of bread', 'naps, always snacking'],
    ['nyx', 'a little moon; night owl', 'shows tonight\'s moon phase'],
    ['cubo', 'studious; reads, coffee', 'sneezes at dust'],
    ['ember', 'a campfire wisp', 'burns with your CPU'],
];
const TW = 250, TH = 250, M = 30, W = M * 2 + PETS.length * TW, H = TH + M * 2;
const surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, W, H);
const cr = new Cairo.Context(surf);
const bg = new Cairo.LinearGradient(0, 0, 0, H);
bg.addColorStopRGBA(0, 0.09, 0.09, 0.14, 1); bg.addColorStopRGBA(1, 0.05, 0.05, 0.09, 1);
cr.setSource(bg); cr.paint();
function text(s, x, y, size, col, bold) {
    cr.selectFontFace('JetBrains Mono', Cairo.FontSlant.NORMAL, bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
    cr.setFontSize(size);
    const e = cr.textExtents(s);
    cr.setSourceRGBA(col[0], col[1], col[2], 1); cr.moveTo(x - e.xAdvance / 2, y); cr.showText(s);
}
PETS.forEach(([id, line1, line2], i) => {
    const DEF = imports.pets[id].def;
    const x = M + i * TW;
    const body = DEF.swatch ? hex(DEF.swatch) : COLORS.accent;
    const S = {mood: 'awake', weather: 'clear', mask: 0, shades: false, dozing: false, act: '', act_id: 1, act_dur: 0,
        light: false, colors: COLORS, body, moon: 72, waxing: true};   // Nyx shows a waxing gibbous moon
    const A = Draw.newAnim();
    Draw.tick(S, A, 1000, DEF);
    A.blinkAt = A.nextGlance = 1e12; A.blinkUntil = A.glanceUntil = -1;
    cr.rectangle(x + 50, M + 150, TW - 100, 1.2); cr.setSourceRGBA(1, 1, 1, 0.10); cr.fill();
    cr.save(); cr.translate(x + TW / 2 - 110, M + 4);
    Draw.drawPet(cr, S, A, 1000.9, 220, 148, DEF);
    cr.restore();
    text(DEF.name, x + TW / 2, M + 190, 22, body, true);
    text(line1, x + TW / 2, M + 215, 13, COLORS.text);
    text(line2, x + TW / 2, M + 234, 12, COLORS.subtext0);
});
surf.writeToPNG(out);
print('wrote', out, W + 'x' + H);
