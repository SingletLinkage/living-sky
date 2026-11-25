// Offline preview: renders the panel pet in several states to a PNG.
//   gjs tools/render.js out.png [state.json]
// Without a state file it uses a built-in Mocha state and varies mood/accessories per tile.
'use strict';
const {GLib} = imports.gi;
const Cairo = imports.cairo;
const here = GLib.path_get_dirname(GLib.path_get_dirname(GLib.canonicalize_filename(imports.system.programInvocationName, null)));
imports.searchPath.unshift(here);
const Draw = imports.pets.core;
const PET_ID = (typeof PET_ARG !== 'undefined' && PET_ARG) || GLib.getenv('GLOB_PET') || 'mimi';
const DEF = imports.pets[PET_ID].def;

const out = ARGV[0] || 'mimi.png';
let base;
if (ARGV[1]) {
    const [, bytes] = GLib.file_get_contents(ARGV[1]);
    base = JSON.parse(imports.byteArray.toString(bytes));
} else {
    base = {mood: 'awake', weather: 'clear', mask: 0, shades: false, dozing: false, act: '', act_id: 0, act_dur: 0, light: false,
        colors: {accent: [0.706, 0.745, 0.996], accent2: [0.98, 0.702, 0.529], text: [0.804, 0.839, 0.957],
            overlay2: [0.576, 0.6, 0.698], red: [0.953, 0.545, 0.659], yellow: [0.976, 0.886, 0.686],
            pink: [0.961, 0.761, 0.906], sky: [0.537, 0.863, 0.922], shadow: [0.067, 0.067, 0.106]}};
}
const tiles = [
    {}, {mood: 'music'}, {mood: 'sleep'}, {mood: 'drowsy'}, {weather: 'rain'}, {weather: 'snow'},
    {shades: true}, {mask: 1}, {mask: 2}, {mask: 3}, {act: 'typing'}, {act: 'heart'}, {act: 'curious'},
    {act: 'chime'}, {dozing: true}, {mood: 'music', weather: 'rain', mask: 2},
];
const W = 56, H = 36, Z = 3, cols = 8;          // panel-size tiles, drawn 3x for inspection
const rows = Math.ceil(tiles.length / cols);
const surf = new Cairo.ImageSurface(Cairo.Format.ARGB32, W * Z * cols, H * Z * rows);
const cr = new Cairo.Context(surf);
cr.setSourceRGB(0.11, 0.11, 0.16); cr.paint();
tiles.forEach((o, i) => {
    const S = Object.assign({}, base, o, {act_id: i + 1, act_dur: 2.0});
    const A = Draw.newAnim();
    A.started = true; A.blinkAt = 1e12; A.nextGlance = 1e12; A.nextYawn = 1e12;
    cr.save();
    cr.translate((i % cols) * W * Z, Math.floor(i / cols) * H * Z);
    cr.scale(Z, Z);
    cr.rectangle(0.5, 0.5, W - 1, H - 1); cr.setSourceRGBA(1, 1, 1, 0.08); cr.setLineWidth(1 / Z); cr.stroke();
    Draw.tick(S, A, 100.0, DEF);                           // start the action ...
    Draw.drawPet(cr, S, A, 101.0, W, H, DEF);          // ... and draw it 1 s in
    cr.restore();
});
surf.writeToPNG(out);
print('wrote', out);
