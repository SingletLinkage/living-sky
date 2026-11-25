// Ember, the campfire wisp (lua/glob/ember.lua): a teardrop flame whose tip sways and whose bright core
// flickers faster the busier the CPU is (S.cpu, % from glob.json); a warm glow. Asleep or in the cold it
// is a small blue pilot light; in the rain it steams. Flares up and crackles sparks.
/* exported def */
'use strict';
let T = 0;                                          // time of the current frame (for the swaying tip)
const pilot = E => E.mood === 'sleep' || E.S.weather === 'cold' || E.S.weather === 'snow';
const cpuOf = E => Math.max(0, Math.min(100, E.S.cpu || 0)) / 100;
function radial(E, x, y, r0, r1, c, k0) {
    const g = new E.Cairo.RadialGradient(x, y, r0, x, y, r1);
    g.addColorStopRGBA(0, c[0], c[1], c[2], k0); g.addColorStopRGBA(1, c[0], c[1], c[2], 0);
    return g;
}
var def = {
    id: 'ember', name: 'Ember', size: [16, 14], breath: 2.6, blinkEvery: [2.5, 5.5],
    swatch: '#fab387',
    showcase: [['Flaring up', {act: 'flare', act_dur: 2.0}, {p: 0.5}], ['Crackle!', {act: 'crackle', act_dur: 1.6}, {p: 0.45}],
        ['Busy CPU: roaring', {cpu: 100}], ['Asleep: pilot light', {mood: 'sleep'}],
        ['Rain: steaming', {weather: 'rain'}]],
    animExtra: [[2.0, {act: 'flare', act_dur: 2.0}], [1.6, {act: 'crackle', act_dur: 1.6}]],
    body(cr, cx, cy, a, b) {                        // round bottom, a pointed tip that sways
        const sway = 2.2 * Math.sin(T * 2.3) + 1.0 * Math.sin(T * 5.1);
        const tx = cx + sway, ty = cy - b * 1.55;
        cr.newPath();
        cr.moveTo(tx, ty);
        cr.curveTo(cx + a * 0.25 + sway * 0.4, cy - b * 0.95, cx + a * 1.05, cy - b * 0.45, cx + a, cy + b * 0.15);
        cr.curveTo(cx + a * 0.95, cy + b * 0.8, cx + a * 0.5, cy + b, cx, cy + b);
        cr.curveTo(cx - a * 0.5, cy + b, cx - a * 0.95, cy + b * 0.8, cx - a, cy + b * 0.15);
        cr.curveTo(cx - a * 1.05, cy - b * 0.45, cx - a * 0.25 + sway * 0.4, cy - b * 0.95, tx, ty);
        cr.closePath();
    },
    pose(an, ap, t, P) {
        if (an === 'flare') {
            const k = Math.sin(Math.PI * ap);
            P.sy *= 1 + 0.28 * k; P.sx *= 1 - 0.1 * k; P.oy -= 2 * k;
        } else if (an === 'crackle') {
            P.rot = 0.06 * Math.sin(ap * 40) * (1 - ap);
        }
    },
    eyes(eyes, an, ap, mood, S) {
        if (S && S.hot && mood !== 'sleep') return 'happy';     // "this is fine", genuinely
        if (an === 'flare') return 'wide';
        if (an === 'crackle') return 'happy';
        return null;
    },
    drawUnder(E) {                                  // the glow: bigger with CPU load, blue for a pilot light
        T = E.t;
        const cpu = cpuOf(E), blue = pilot(E);
        const c = blue ? E.col('blue') : E.mix(E.col('peach'), E.col('yellow'), 0.4);
        const r = E.a * (blue ? 1.5 : 1.9 + 0.9 * cpu);
        const k = (E.light ? 0.10 : 0.2) * (blue ? 0.6 : 1) * (0.85 + 0.15 * Math.sin(E.t * (3 + 6 * cpu)));
        const y = E.cy + E.b * 0.2;
        E.cr.newPath(); E.cr.arc(E.cx, y, r, 0, 2 * Math.PI);
        E.cr.setSource(radial(E, E.cx, y, E.a * 0.5, r, c, k)); E.cr.fill();
    },
    drawBody(E) {                                   // the bright core (or the blue of a pilot light)
        const cr = E.cr, {cx, cy, a, b} = E;
        if (pilot(E)) {
            const g = new E.Cairo.LinearGradient(0, cy - b * 1.5, 0, cy + b);
            const hi = E.mix(E.col('sky'), E.WHITE, 0.3), lo = E.mix(E.col('blue'), E.BLACK, 0.15);
            g.addColorStopRGBA(0, hi[0], hi[1], hi[2], 0.9); g.addColorStopRGBA(1, lo[0], lo[1], lo[2], 0.9);
            cr.setSource(g); cr.paint();
            return;
        }
        const cpu = cpuOf(E);
        const f = 0.75 + 0.25 * Math.sin(E.t * (4 + 10 * cpu)) * Math.sin(E.t * (2.7 + 5 * cpu));
        cr.setSource(radial(E, cx, cy + b * 0.35, 1, a * (0.75 + 0.15 * f), E.mix(E.col('yellow'), E.WHITE, 0.55), 0.85 * f));
        cr.paint();
    },
    drawOver(E) {                                   // steam rising in the rain
        const w = E.S.weather;
        if (w !== 'rain' && w !== 'storm') return;
        const cr = E.cr;
        for (let i = 0; i < 3; i++) {
            const p = (E.t * 0.6 + i / 3) % 1;
            const x = E.cx + (i - 1) * E.a * 0.7 + 2 * Math.sin(E.t * 3 + i), y = E.cy - E.b * 0.3 - p * 12;
            cr.newPath(); cr.moveTo(x, y + 4); cr.curveTo(x - 2, y + 2, x + 2, y, x, y - 3);
            E.rgba(E.WHITE, 0.55 * Math.sin(Math.PI * p)); cr.setLineWidth(1.3); cr.stroke();
        }
    },
    drawAct(E, an, ap) {                            // sparks popping off in little arcs
        if (an !== 'crackle' && an !== 'flare') return;
        const n = an === 'crackle' ? 6 : 4;
        for (let i = 1; i <= n; i++) {
            const ang = -Math.PI / 2 + (i - (n + 1) / 2) * 0.45;
            const d = (an === 'crackle' ? 6 : 4) + ap * (an === 'crackle' ? 16 : 22);
            E.ellipse(E.cx + Math.cos(ang) * d, E.cy - E.b * 0.8 + Math.sin(ang) * d + 10 * ap * ap, 1.2, 1.2);
            E.rgba(E.mix(E.col('yellow'), E.WHITE, 0.4), Math.max(0, 1 - ap) * 0.95); E.cr.fill();
        }
    },
};
