// Pip, the hyper droplet (lua/glob/pip.lua): teardrop body, fast blinks, splashes in the rain.
/* exported def */
'use strict';
var def = {
    id: 'pip', name: 'Pip', size: [16, 16], breath: 2.6, blinkEvery: [1.5, 3.5], rainGear: false,
    swatch: '#74c7ec',            // body colour in the offline tools (the desktop sends the real one)
    showcase: [['Splashing in the rain', {weather: 'rain', act: 'splash', act_dur: 2.0}, {p: 0.35}],
        ['Poke: startled!', {act: 'startle', act_dur: 1.4}, {p: 0.3}]],
    animExtra: [[2.0, {weather: 'rain', act: 'splash', act_dur: 2.0}], [1.4, {act: 'startle', act_dur: 1.4}]],
    body(cr, cx, cy, a, b) {
        cr.newPath();
        cr.moveTo(cx, cy - b * 1.18);
        cr.curveTo(cx + a * 0.3, cy - b * 0.72, cx + a, cy - b * 0.2, cx + a, cy + b * 0.32);
        cr.curveTo(cx + a, cy + b * 0.92, cx + a * 0.55, cy + b, cx, cy + b);
        cr.curveTo(cx - a * 0.55, cy + b, cx - a, cy + b * 0.92, cx - a, cy + b * 0.32);
        cr.curveTo(cx - a, cy - b * 0.2, cx - a * 0.3, cy - b * 0.72, cx, cy - b * 1.18);
        cr.closePath();
    },
    pose(an, ap, t, P) {
        if (an === 'splash') {
            const k = Math.abs(Math.sin(3 * Math.PI * ap));
            P.oy -= 6 * k;
            if (k < 0.2) { P.sy *= 0.88; P.sx *= 1.08; }
        }
    },
    eyes(eyes, an) { return an === 'splash' ? 'happy' : null; },
    drawAct(E, an, ap) {
        if (an !== 'splash') return;
        for (let i = 0; i < 6; i++) {
            const p = (ap * 3 + i * 0.17) % 1, side = i % 2 === 0 ? -1 : 1;
            E.ellipse(E.bx + side * (E.a * 0.6 + p * 14), E.by - 2 - 10 * Math.sin(Math.PI * p), 1.5, 1.9);
            E.rgba(E.col('sky'), 0.9 * (1 - p)); E.cr.fill();
        }
    },
};
