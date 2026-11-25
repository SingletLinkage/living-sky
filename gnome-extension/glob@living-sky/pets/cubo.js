// Cubo, the nerdy cube (lua/glob/cubo.lua): rounded jelly cube, round glasses, reads books.
/* exported def */
'use strict';
var def = {
    id: 'cubo', name: 'Cubo', size: [18, 16],
    swatch: '#94e2d5',
    showcase: [['Reading', {act: 'read', act_dur: 4.0}, {p: 0.3}], ['...page turn', {act: 'read', act_dur: 4.0}, {p: 0.52}],
        ['Dusty air: achoo', {act: 'sneeze', act_dur: 1.4}, {p: 0.7}]],
    animExtra: [[4.0, {act: 'read', act_dur: 4.0}], [3.0, {act: 'coffee', act_dur: 3.0}]],
    body(cr, cx, cy, a, b) {
        cr.newPath();
        for (let i = 0; i < 48; i++) {
            const th = 2 * Math.PI * i / 48, c = Math.cos(th), s = Math.sin(th);
            const x = cx + a * Math.sign(c) * Math.abs(c) ** (2 / 5), y = cy + b * Math.sign(s) * Math.abs(s) ** (2 / 5);
            if (i === 0) cr.moveTo(x, y); else cr.lineTo(x, y);
        }
        cr.closePath();
    },
    pose(an, ap, t, P) { if (an === 'read') P.rot = 0.04; },
    drawOver(E) {
        if (E.S.shades) return;
        const cr = E.cr, y = E.cy + E.ey + E.gy * 1.6, x0 = E.cx + E.gx * 2.2;
        cr.newPath();
        for (const s of [-1, 1]) { cr.newSubPath(); cr.arc(x0 + s * E.ex, y, 4.6, 0, 2 * Math.PI); }
        E.rgba(E.EYE, 0.85); cr.setLineWidth(1.2); cr.stroke();
        cr.moveTo(x0 - E.ex + 4.6, y - 0.6); cr.lineTo(x0 + E.ex - 4.6, y - 0.6); cr.setLineWidth(1.1); cr.stroke();
    },
    drawAct(E, an, ap) {
        if (an !== 'read') return;
        const cr = E.cr, x = E.cx, y = E.by - 1;
        E.rrect(x - 11, y - 9, 22, 9, 1.5); E.rgba(E.col('red')); cr.fill();
        E.rrect(x - 10, y - 10, 9.5, 9, 1); E.rrect(x + 0.5, y - 10, 9.5, 9, 1); E.rgba([0.98, 0.96, 0.9]); cr.fill();
        for (let i = 0; i < 3; i++) {
            cr.moveTo(x - 8.5, y - 8 + i * 2.3); cr.lineTo(x - 2.5, y - 8 + i * 2.3);
            cr.moveTo(x + 2, y - 8 + i * 2.3); cr.lineTo(x + 8, y - 8 + i * 2.3);
        }
        E.rgba([0.6, 0.6, 0.66], 0.8); cr.setLineWidth(0.7); cr.stroke();
        if (ap > 0.45 && ap < 0.6) {
            const w = 9.5 * Math.cos(Math.PI * (ap - 0.45) / 0.15);
            E.rrect(x + Math.min(0, w), y - 10.5, Math.abs(w), 9, 1); E.rgba([1, 1, 0.96]); cr.fill();
        }
    },
};
