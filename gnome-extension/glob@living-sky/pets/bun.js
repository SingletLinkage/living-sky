// Bun, the sleepy slice of bread (lua/glob/bun.lua): toast silhouette with a crust rim, naps, snacks.
/* exported def */
'use strict';
var def = {
    id: 'bun', name: 'Bun', size: [20, 17], breath: 5, blinkEvery: [4, 8],
    swatch: '#f9daa9',
    showcase: [['A little nap', {act: 'nap', act_dur: 14}, {p: 0.3}], ['Snack time (again)', {act: 'eat', act_dur: 3.2}, {p: 0.4}]],
    animExtra: [[4.0, {act: 'nap', act_dur: 4.0}], [3.2, {act: 'eat', act_dur: 3.2}]],
    body(cr, cx, cy, a, b) {                       // a slice of bread: straight sides, two round lobes on top
        const w = a * 0.86, r = 4;
        cr.newPath();
        cr.moveTo(cx - w + r, cy + b);
        cr.lineTo(cx + w - r, cy + b);
        cr.curveTo(cx + w, cy + b, cx + w, cy + b, cx + w, cy + b - r);
        cr.lineTo(cx + w, cy - b * 0.25);
        cr.curveTo(cx + a * 1.08, cy - b * 0.45, cx + a * 1.0, cy - b * 1.08, cx + a * 0.5, cy - b * 1.08);
        cr.curveTo(cx + a * 0.2, cy - b * 1.08, cx + a * 0.08, cy - b * 0.94, cx, cy - b * 0.94);
        cr.curveTo(cx - a * 0.08, cy - b * 0.94, cx - a * 0.2, cy - b * 1.08, cx - a * 0.5, cy - b * 1.08);
        cr.curveTo(cx - a * 1.0, cy - b * 1.08, cx - a * 1.08, cy - b * 0.45, cx - w, cy - b * 0.25);
        cr.lineTo(cx - w, cy + b - r);
        cr.curveTo(cx - w, cy + b, cx - w, cy + b, cx - w + r, cy + b);
        cr.closePath();
    },
    pose(an, ap, t, P) { if (an === 'nap') { P.sy *= 0.92; P.sx *= 1.04; } },
    eyes(eyes, an) { return an === 'nap' ? 'closed' : null; },
    drawBody(E) {                                   // the crust: a toasted rim just inside the outline
        const cr = E.cr;
        E.path(); E.rgba(E.mix(E.col('peach'), E.BLACK, 0.18)); cr.setLineWidth(5.2); cr.stroke();
        E.path(); E.rgba(E.mix(E.col('peach'), E.WHITE, 0.1), 0.6); cr.setLineWidth(1.4); cr.stroke();
    },
    drawAct(E, an) {
        if (an !== 'nap') return;
        const p = (E.t * 0.25) % 1;
        E.text(E.cx - E.a * 0.5 - p * 8, E.cy - E.b - 2 - p * 10, 'z', 10 + p * 3, E.col('text'), Math.sin(p * Math.PI) * 0.85, true);
    },
};
