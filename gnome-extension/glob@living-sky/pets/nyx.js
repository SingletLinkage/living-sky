// Nyx, the little moon (lua/glob/nyx.lua): a pale cratered round body whose shading follows the real
// moon phase tonight (S.moon = illumination %, S.waxing), a glow after dark, a nightcap while she
// sleeps through the day. Stargazes and cheers at a full moon.
/* exported def */
'use strict';
function sparkle(cr, x, y, r) {
    cr.newPath();
    cr.moveTo(x, y - r); cr.lineTo(x + r * 0.3, y - r * 0.3); cr.lineTo(x + r, y); cr.lineTo(x + r * 0.3, y + r * 0.3);
    cr.lineTo(x, y + r); cr.lineTo(x - r * 0.3, y + r * 0.3); cr.lineTo(x - r, y); cr.lineTo(x - r * 0.3, y - r * 0.3); cr.closePath();
}
var def = {
    id: 'nyx', name: 'Nyx', size: [17, 16], breath: 4, blinkEvery: [3, 6.5],
    swatch: '#ece1cd',
    showcase: [['Stargazing', {act: 'stargaze', act_dur: 4.0}, {p: 0.5}], ['Full moon!', {act: 'moonjoy', act_dur: 2.4, moon: 100}, {p: 0.4}],
        ['New moon tonight', {moon: 3, waxing: true}], ['Asleep all day', {mood: 'sleep', light: true}, {pal: 'latte'}],
        ['Woken at noon', {shades: true, light: true}, {pal: 'latte'}]],
    animExtra: [[4.0, {act: 'stargaze', act_dur: 4.0}], [2.4, {act: 'moonjoy', act_dur: 2.4}]],
    body(cr, cx, cy, a, b) {                       // nearly round, sitting a little flat on the card
        cr.newPath();
        for (let i = 0; i < 48; i++) {
            const th = 2 * Math.PI * i / 48, c = Math.cos(th), s = Math.sin(th);
            const n = s > 0 ? 2.6 : 2.0;
            const x = cx + a * Math.sign(c) * Math.abs(c) ** (2 / n), y = cy + b * Math.sign(s) * Math.abs(s) ** (2 / n);
            if (i === 0) cr.moveTo(x, y); else cr.lineTo(x, y);
        }
        cr.closePath();
    },
    pose(an, ap, t, P) {
        if (an === 'stargaze') P.rot = -0.08 * Math.min(1, ap * 5, (1 - ap) * 5);
        else if (an === 'moonjoy') P.oy -= 6 * Math.abs(Math.sin(2 * Math.PI * ap));
    },
    eyes(eyes, an) {
        if (an === 'moonjoy') return 'happy';
        if (an === 'stargaze' && eyes === 'open') return 'wide';
        return null;
    },
    drawUnder(E) {                                  // soft moonlight glow after dark
        if (E.light) return;
        const r = E.a * 2.0, c = E.base, k = 0.14 + 0.05 * Math.sin(E.t * 1.3);
        const g = new E.Cairo.RadialGradient(E.cx, E.cy, E.a * 0.7, E.cx, E.cy, r);
        g.addColorStopRGBA(0, c[0], c[1], c[2], k); g.addColorStopRGBA(1, c[0], c[1], c[2], 0);
        E.cr.newPath(); E.cr.arc(E.cx, E.cy, r, 0, 2 * Math.PI); E.cr.setSource(g); E.cr.fill();
    },
    drawBody(E) {
        const cr = E.cr, {cx, cy, a, b} = E;
        // craters (kept clear of the face)
        for (const [dx, dy, r] of [[0.58, -0.5, 2.8], [-0.62, -0.42, 2.0], [0.18, -0.8, 1.5], [0.72, 0.42, 1.7]]) {
            E.ellipse(cx + dx * a, cy + dy * b, r, r * 0.85); E.rgba(E.mix(E.base, E.BLACK, 0.14), 0.75); cr.fill();
            E.ellipse(cx + dx * a + r * 0.25, cy + dy * b + r * 0.25, r * 0.7, r * 0.55); E.rgba(E.WHITE, 0.18); cr.fill();
        }
        // tonight's phase: shadow on the unlit side, terminator as a half-ellipse
        const k = Math.max(0, Math.min(1, (E.S.moon ?? 100) / 100));
        if (k > 0.97) return;
        const side = E.S.waxing === false ? 1 : -1;  // waxing: lit on the right, shadow on the left
        const tx = a * 1.05 * (1 - 2 * k);
        cr.newPath();
        for (let i = 0; i <= 24; i++) {             // the outer edge of the unlit side, top -> bottom
            const th = -Math.PI / 2 + Math.PI * i / 24;
            const x = cx + side * a * 1.1 * Math.cos(th), y = cy + b * 1.1 * Math.sin(th);
            if (i === 0) cr.moveTo(x, y); else cr.lineTo(x, y);
        }
        for (let i = 24; i >= 0; i--) {             // terminator, bottom -> top
            const th = -Math.PI / 2 + Math.PI * i / 24;
            cr.lineTo(cx - side * tx * Math.cos(th), cy + b * 1.1 * Math.sin(th));
        }
        cr.closePath();
        E.rgba(E.mix(E.col('mauve'), E.BLACK, 0.45), 0.36); cr.fill();
    },
    drawOver(E) {                                   // a striped nightcap while asleep
        if (E.mood !== 'sleep') return;
        const cr = E.cr, {cx, cy, a, b} = E;
        cr.newPath();
        cr.moveTo(cx - a * 0.78, cy - b * 0.55);
        cr.curveTo(cx - a * 0.3, cy - b * 1.45, cx + a * 0.55, cy - b * 1.35, cx + a * 1.25, cy - b * 0.35);
        cr.curveTo(cx + a * 0.7, cy - b * 0.7, cx + a * 0.2, cy - b * 0.8, cx - a * 0.78, cy - b * 0.55);
        cr.closePath();
        E.rgba(E.col('blue')); cr.fillPreserve(); E.rgba(E.mix(E.col('blue'), E.BLACK, 0.3)); cr.setLineWidth(0.9); cr.stroke();
        cr.moveTo(cx - a * 0.8, cy - b * 0.56); cr.curveTo(cx - a * 0.2, cy - b * 0.82, cx + a * 0.3, cy - b * 0.8, cx + a * 0.7, cy - b * 0.68);
        E.rgba(E.WHITE, 0.9); cr.setLineWidth(2.2); cr.stroke();
        E.ellipse(cx + a * 1.28, cy - b * 0.3, 2.6, 2.6); E.rgba(E.WHITE); cr.fill();
    },
    drawAct(E, an, ap) {
        const cr = E.cr;
        if (an === 'stargaze') {
            for (let i = 0; i < 3; i++) {
                const tw = 0.5 + 0.5 * Math.sin(E.t * 5 + i * 2.1);
                sparkle(cr, E.cx - E.a * 0.7 + i * E.a * 0.7, E.cy - E.b - 8 - (i % 2) * 6, 2.4 + tw * 1.4);
                E.rgba(E.col('yellow'), Math.min(1, ap * 4, (1 - ap) * 4) * (0.5 + 0.5 * tw)); cr.fill();
            }
        } else if (an === 'moonjoy') {
            for (let i = 0; i < 5; i++) {
                const ang = -Math.PI / 2 + (i - 2) * 0.55, r = E.a + 4 + ap * 10;
                sparkle(cr, E.cx + Math.cos(ang) * r, E.cy + Math.sin(ang) * r, 2.6);
                E.rgba(E.col('yellow'), Math.sin(Math.PI * ap)); cr.fill();
            }
        }
    },
};
