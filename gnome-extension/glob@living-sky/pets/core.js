// glob pets, panel drawing: a JS/cairo port of living-sky's lua/glob/core.lua (sitting pose only).
// drawPet(cr, S, A, t, w, h, def) draws any pet; `def` is a pet's definition (pets/<id>.js: `var def`)
// with the same hooks as the Lua side (size, body, breath, blinkEvery, pose, eyes, drawUnder,
// drawBody, drawOver, drawAct, rainGear). Hooks get an env E with helpers, so pet files need no imports.
// The body colour comes from the desktop (S.body). Behaviour lives in Lua; this only draws.
// Used by extension.js and by tools/*.js, so keep it free of Shell imports.
/* exported newAnim, tick, drawPet */
'use strict';
const Cairo = imports.cairo;

const EYE = [0.12, 0.12, 0.17];
const WHITE = [1, 1, 1], BLACK = [0, 0, 0];
const ICON_FONT = 'FiraCode Nerd Font Mono', MONO = 'JetBrains Mono';

function newAnim() {
    return {started: false, blinkAt: 0, blinkUntil: -1, nextGlance: 0, glanceUntil: -1, gaze: [0, 0],
        actId: -1, act: null, yawnUntil: -1, nextYawn: 0, flashUntil: -1};
}

const rnd = () => Math.random();
const mix = (c, d, k) => [c[0] + (d[0] - c[0]) * k, c[1] + (d[1] - c[1]) * k, c[2] + (d[2] - c[2]) * k];
function rgba(cr, c, a = 1) { cr.setSourceRGBA(c[0], c[1], c[2], a); }
function ellipse(cr, x, y, rx, ry) {
    cr.save(); cr.translate(x, y); cr.scale(rx, ry);
    cr.newSubPath(); cr.arc(0, 0, 1, 0, 2 * Math.PI); cr.restore();
}
function rrect(cr, x, y, w, h, r) {
    cr.newSubPath();
    cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
    cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
    cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
    cr.arc(x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
    cr.closePath();
}
function bodyPath(cr, cx, cy, a, b) {
    cr.newPath();
    for (let i = 0; i < 48; i++) {
        const th = 2 * Math.PI * i / 48, c = Math.cos(th), s = Math.sin(th);
        const n = s > 0 ? 4.2 : 2.3;
        const x = cx + a * Math.sign(c) * Math.abs(c) ** (2 / n);
        const y = cy + b * Math.sign(s) * Math.abs(s) ** (2 / n);
        if (i === 0) cr.moveTo(x, y); else cr.lineTo(x, y);
    }
    cr.closePath();
}
function text(cr, x, y, s, size, c, a, bold, fam) {
    cr.selectFontFace(fam || MONO, Cairo.FontSlant.NORMAL, bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
    cr.setFontSize(size);
    rgba(cr, c, a); cr.moveTo(x, y); cr.showText(s);
}

function textC(cr, x, y, s, size, c, a, bold, fam) {
    cr.selectFontFace(fam || MONO, Cairo.FontSlant.NORMAL, bold ? Cairo.FontWeight.BOLD : Cairo.FontWeight.NORMAL);
    cr.setFontSize(size);
    const e = cr.textExtents(s);
    rgba(cr, c, a); cr.moveTo(x - e.xAdvance / 2, y); cr.showText(s);
}
function teardrop(cr, x, y, w, h) {
    cr.newPath(); cr.moveTo(x, y - h);
    cr.curveTo(x + w, y - h * 0.45, x + w * 0.85, y, x, y);
    cr.curveTo(x - w * 0.85, y, x - w, y - h * 0.45, x, y - h); cr.closePath();
}
function flames(cr, cx, by, a, t) {
    [-1.08, -0.62, 0.62, 1.08].forEach((k, i) => {
        const h = (k * k > 1 ? 11 : 7) * (0.8 + 0.25 * Math.sin(t * 9 + (i + 1) * 1.7));
        teardrop(cr, cx + k * a, by + 1, 4.2, h); rgba(cr, [0.98, 0.5, 0.15], 0.9); cr.fill();
        teardrop(cr, cx + k * a, by + 1, 2.2, h * 0.55); rgba(cr, [1, 0.85, 0.3], 0.95); cr.fill();
    });
}
function mug(cr, x, y, t, steam, peach) {
    rrect(cr, x - 4.5, y - 9, 9, 9, 1.8); rgba(cr, [0.96, 0.93, 0.87]); cr.fillPreserve();
    rgba(cr, [0.55, 0.5, 0.45]); cr.setLineWidth(0.9); cr.stroke();
    cr.rectangle(x - 4.5, y - 6.5, 9, 2); rgba(cr, peach); cr.fill();
    cr.newPath(); cr.arc(x + 4.6, y - 4.6, 2.4, -Math.PI / 2, Math.PI / 2);
    rgba(cr, [0.55, 0.5, 0.45]); cr.setLineWidth(1.2); cr.stroke();
    if (steam) {
        for (let k = 0; k < 2; k++) {
            const p = (t * 0.6 + k * 0.5) % 1, sx0 = x - 1.5 + k * 3;
            cr.moveTo(sx0, y - 10 - p * 8);
            cr.curveTo(sx0 + 2, y - 12 - p * 8, sx0 - 2, y - 14 - p * 8, sx0, y - 16 - p * 8);
            rgba(cr, WHITE, 0.55 * Math.sin(p * Math.PI)); cr.setLineWidth(1); cr.stroke();
        }
    }
}

// update local idle timers / mirror the desktop blob's current action
function tick(S, A, t, def = {}) {
    if (!A.started) {
        A.started = true;
        A.blinkAt = t + 2; A.nextGlance = t + 5; A.nextYawn = t + 20;
    }
    if (t >= A.blinkAt) { A.blinkUntil = t + 0.2; const be = def.blinkEvery || [2.5, 6]; A.blinkAt = t + (S.mood === 'drowsy' ? 1.5 : 0) + be[0] + rnd() * (be[1] - be[0]); }
    if (t >= A.nextGlance) {
        const o = [[-1, 0], [1, 0], [-0.7, -0.6], [0, 0.6]];
        A.gaze = o[Math.floor(rnd() * o.length)];
        A.glanceUntil = t + 1 + rnd(); A.nextGlance = t + 8 + rnd() * 7;
    }
    if (S.mood === 'drowsy' && t >= A.nextYawn) { A.yawnUntil = t + 1.6; A.nextYawn = t + 25 + rnd() * 30; }
    if (S.weather === 'storm' && rnd() < 0.02) A.flashUntil = t + 0.15;
    if (S.act_id !== A.actId) {
        A.actId = S.act_id;
        A.act = S.act ? {name: S.act, t0: t, dur: Math.max(0.5, S.act_dur || 1.5)} : null;
    }
    if (A.act && t > A.act.t0 + A.act.dur) A.act = null;
}

// Draw the blob into a w x h box (bottom-centred). S = state from glob.json, A = newAnim().
function drawPet(cr, S, A, t, w, h, def = {}) {
    if (!S) return;
    tick(S, A, t, def);
    const [A0, B0] = def.size || [20, 16];          // body half width / height (unscaled units)
    const shape = (c, x, y, a_, b_) => def.body ? def.body(c, x, y, a_, b_) : bodyPath(c, x, y, a_, b_);
    const C = S.colors || {};
    const col = k => C[k] || C.text || [0.8, 0.84, 0.96];
    const scale = h / 60;                          // fit notes / umbrella above the body
    cr.save();
    cr.scale(scale, scale);
    const bx0 = (w / scale) / 2, by = (h / scale) - 4;
    let bx = bx0;
    const mood = S.mood, wx = S.weather, light = S.light;

    // pose
    const br = Math.sin(2 * Math.PI * t / (mood === 'sleep' ? 5 : (def.breath || 3.5)));
    let sy = 1 + 0.03 * br, sx = 1 - 0.015 * br, oy = 0, rot = 0;   // rot also set by the dance
    if (mood === 'sleep') { sy *= 0.84; sx *= 1.08; }
    else if (mood === 'wake') { const s = Math.max(0, Math.sin(2 * Math.PI * t / 4)); sy *= 1 + 0.13 * s; sx *= 1 - 0.06 * s; }
    else if (mood === 'music') { const s = Math.abs(Math.sin(Math.PI * t)); oy = -3 * s; sy *= 1 - 0.06 * (1 - s); rot = 0.1 * Math.sin(Math.PI * t); }
    const act = A.act, an = act && act.name;
    const ap = act ? Math.max(0, Math.min(1, (t - act.t0) / act.dur)) : 0;
    if (an === 'hop' || an === 'chime' || an === 'startle') {
        const p = (t - act.t0) / 1.0;
        if (p < 1) {
            if (p < 0.18 || p > 0.82) { sy *= 0.9; sx *= 1.06; }
            else oy -= (an === 'startle' ? 9 : 7) * Math.sin(Math.PI * (p - 0.18) / 0.64);
        }
    } else if (an === 'wobble') { const k = Math.sin(4 * Math.PI * ap) * (1 - ap); sx *= 1 + 0.1 * k; sy *= 1 - 0.1 * k; }
    else if (an === 'sway') rot = 0.14 * Math.sin(4 * Math.PI * ap) * (1 - 0.4 * ap);
    else if (an === 'curious') rot = 0.17 * Math.min(1, ap * 4, (1 - ap) * 4);
    else if (an === 'sneeze') { if (ap < 0.5) { sy *= 1.08; rot = -0.06; } else { sy *= 0.86; sx *= 1.08; } }
    else if (an === 'squish') {
        if (ap < 0.45) { sy *= 0.72; sx *= 1.16; } else { const k = Math.sin((ap - 0.45) / 0.55 * Math.PI); sy *= 1 + 0.1 * k; sx *= 1 - 0.05 * k; }
    } else if (an === 'dance') { const s = Math.abs(Math.sin(Math.PI * t)); oy -= 4 * s; rot = 0.14 * Math.sin(Math.PI * t); }
    else if (an === 'wave') rot = 0.05;
    else if (an === 'eat') { if (Math.floor(ap * 6) % 2 === 1) { sy *= 0.95; sx *= 1.03; } }
    else if (an === 'coffee' && ap > 0.35 && ap < 0.7) rot = -0.05;
    else if (an === 'huff') {                       // puff up... hmph (deflate)
        if (ap < 0.4) { const k = Math.sin(ap / 0.4 * Math.PI / 2); sx *= 1 + 0.08 * k; sy *= 1 + 0.08 * k; }
        else { const k = Math.sin((ap - 0.4) / 0.6 * Math.PI); sx *= 1.08 - 0.1 * k; sy *= 1.08 - 0.16 * k; }
        rot = -0.04;
    }
    if (def.pose && an) {
        const P = {sx, sy, oy, rot};
        def.pose(an, ap, t, P);
        ({sx, sy, oy, rot} = P);
    }
    const grumpy = S.grumpy || '';
    if (S.dozing) { sy *= 0.9; sx *= 1.04; }
    if (wx === 'cold' || wx === 'snow') bx += (rnd() - 0.5);

    const a = A0 * sx, b = B0 * sy;
    const cx = bx, cy = by - b + oy;

    // contact shadow
    ellipse(cr, bx, by + 1, A0 * 0.95, 3.2); rgba(cr, col('shadow'), 0.3 * (1 + oy / 10)); cr.fill();

    const acc = col('accent');
    const base = S.body || (light ? mix(acc, WHITE, 0.45) : acc);
    // what the pet's drawing hooks get
    const E = {cr, t, cx, cy, a, b, bx, by, base, light, mood, S, col, Cairo, WHITE, BLACK, EYE, ICON_FONT, MONO,
        rgba: (c, al) => rgba(cr, c, al), ellipse: (x, y, rx, ry) => ellipse(cr, x, y, rx, ry),
        rrect: (x, y, w_, h_, r) => rrect(cr, x, y, w_, h_, r), mix, teardrop: (x, y, w_, h_) => teardrop(cr, x, y, w_, h_),
        text: (x, y, s_, size, c, al, bold, fam) => text(cr, x, y, s_, size, c, al, bold, fam),
        textC: (x, y, s_, size, c, al, bold, fam) => textC(cr, x, y, s_, size, c, al, bold, fam),
        path: () => shape(cr, cx, cy, a, b)};
    if (def.drawUnder) def.drawUnder(E);
    if (S.hot) flames(cr, bx, by, A0, t);
    cr.save();
    cr.translate(bx, by); cr.rotate(rot); cr.translate(-bx, -by);
    // body
    shape(cr, cx, cy, a, b);
    const g = new Cairo.LinearGradient(0, cy - b, 0, cy + b);
    const top = mix(base, WHITE, 0.22), bot = mix(base, BLACK, 0.18);
    g.addColorStopRGBA(0, top[0], top[1], top[2], 1);
    g.addColorStopRGBA(1, bot[0], bot[1], bot[2], 1);
    cr.setSource(g); cr.fillPreserve();
    rgba(cr, mix(base, BLACK, 0.35), 0.6); cr.setLineWidth(1.2); cr.stroke();
    if (def.drawBody) {                             // markings on the body, under the face (clipped to it)
        cr.save(); shape(cr, cx, cy, a, b); cr.clip(); def.drawBody(E); cr.restore();
    }
    cr.save(); cr.translate(cx - a * 0.42, cy - b * 0.55); cr.rotate(-0.45);
    ellipse(cr, 0, 0, a * 0.24, b * 0.13); rgba(cr, WHITE, 0.55); cr.fill(); cr.restore();
    if (A.flashUntil > t) { shape(cr, cx, cy, a, b); rgba(cr, WHITE, 0.3); cr.fill(); }

    // scarf
    if (wx === 'cold' || wx === 'snow') {
        cr.save(); shape(cr, cx, cy, a, b); cr.clip();
        cr.rectangle(cx - a - 1, cy + b * 0.22, 2 * a + 2, 5.5); rgba(cr, col('red')); cr.fill();
        for (let i = 0; i <= 5; i++) cr.rectangle(cx - a + i * 8, cy + b * 0.22, 2, 5.5);
        rgba(cr, WHITE, 0.25); cr.fill();
        cr.restore();
        rrect(cr, cx + a * 0.45, cy + b * 0.22 + 3, 5, 10, 2); rgba(cr, col('red')); cr.fill();
    }

    // face
    let gx = 0, gy = 0;
    if (an === 'typing') { gy = 0.8; }
    else if (an === 'sideeye') { gx = 1; gy = 0.1; }
    else if (an === 'search') { gx = Math.sin(2 * Math.PI * ap * 1.5); gy = 0.2; }
    else if (mood === 'watch') { gy = -0.5; }
    else if (an === 'look') { gx = ap < 0.33 ? -1 : ap < 0.66 ? 1 : 0; }
    else if (t < A.glanceUntil) { [gx, gy] = A.gaze; }
    else if (grumpy === 'ignored') { gx = 1; gy = 0.1; }       // looking away from you
    const ex = a * 0.36, ey = -b * 0.06;
    let eyes = 'open';
    if (mood === 'sleep' || S.dozing) eyes = 'closed';
    else if (an === 'startle') eyes = 'wide';
    else if (an === 'sneeze' && ap < 0.5) eyes = 'closed';
    else if (mood === 'music' || mood === 'wake' || an === 'heart' || an === 'chime' || an === 'eat' || an === 'wave' ||
             an === 'dance' || (an === 'coffee' && ap > 0.35 && ap < 0.7)) eyes = 'happy';
    else if (an === 'sideeye') eyes = 'side';
    else if (t < A.blinkUntil) eyes = 'closed';
    else if (grumpy === 'ignored') eyes = 'side';
    else if (mood === 'drowsy' || S.hot || grumpy) eyes = 'half';
    if (def.eyes) eyes = def.eyes(eyes, an, ap, mood, S) || eyes;
    Object.assign(E, {eyes, ex, ey, gx, gy});
    const shades = S.shades && eyes !== 'closed';
    cr.setLineCap(Cairo.LineCap.ROUND);
    for (const s of [-1, 1]) {
        const x = cx + s * ex + gx * 2.2, y = cy + ey + gy * 1.6;
        if (shades) continue;
        if (eyes === 'wide') {
            ellipse(cr, x, y, 3.6, 4.0); rgba(cr, EYE); cr.fill();
            ellipse(cr, x - 1.1, y - 1.3, 1.3, 1.3); rgba(cr, WHITE, 0.95); cr.fill();
        } else if (eyes === 'open') {
            ellipse(cr, x, y, 2.9, 3.3); rgba(cr, EYE); cr.fill();
            ellipse(cr, x - 0.9, y - 1.1, 0.95, 0.95); rgba(cr, WHITE, 0.95); cr.fill();
        } else if (eyes === 'half') {
            ellipse(cr, x, y + 0.8, 2.9, 1.7); rgba(cr, EYE); cr.fill();
        } else if (eyes === 'side') {
            ellipse(cr, x, y, 2.9, 3.3); rgba(cr, EYE); cr.fill();
            ellipse(cr, x + 0.6, y - 0.6, 0.9, 0.9); rgba(cr, WHITE, 0.9); cr.fill();
            cr.rectangle(x - 3.6, y - 4.2, 7.2, 3.6); rgba(cr, mix(base, WHITE, 0.12)); cr.fill();
            cr.moveTo(x - 3.4, y - 0.6); cr.lineTo(x + 3.4, y - 0.9); rgba(cr, EYE); cr.setLineWidth(1.4); cr.stroke();
        } else if (eyes === 'happy') {
            cr.newPath(); cr.arc(x, y + 1.6, 2.6, Math.PI * 1.15, Math.PI * 1.85);
            rgba(cr, EYE); cr.setLineWidth(1.8); cr.stroke();
        } else {
            cr.newPath(); cr.arc(x, y - 1.2, 2.6, Math.PI * 0.15, Math.PI * 0.85);
            rgba(cr, EYE); cr.setLineWidth(1.7); cr.stroke();
        }
    }
    if (shades) {
        for (const s of [-1, 1]) rrect(cr, cx + s * ex - 4.2, cy + ey - 3, 8.4, 5.6, 2.2);
        rgba(cr, [0.08, 0.08, 0.12]); cr.fill();
        cr.moveTo(cx - ex + 4, cy + ey - 1.5); cr.lineTo(cx + ex - 4, cy + ey - 1.5); cr.setLineWidth(1.2); cr.stroke();
        ellipse(cr, cx - ex - 1.5, cy + ey - 1.4, 1.2, 0.8); rgba(cr, WHITE, 0.7); cr.fill();
    }
    if (grumpy && eyes !== 'closed' && eyes !== 'happy') {     // brows: a V
        const drop = grumpy === 'ignored' ? 1.0 : 1.9;
        for (const s of [-1, 1]) {
            const x = cx + s * ex + gx * 1.2, y = cy + ey - 5.4;
            cr.moveTo(x + s * 3.4, y - drop * 0.5); cr.lineTo(x - s * 2.6, y + drop);
        }
        rgba(cr, EYE); cr.setLineWidth(1.6); cr.stroke();
    }
    if (!S.mask) {
        for (const s of [-1, 1]) {
            ellipse(cr, cx + s * a * 0.62 + gx, cy + b * 0.2, 3.4, 2);
            rgba(cr, col('pink'), light ? 0.45 : 0.38); cr.fill();
        }
    }
    const mx = cx + gx * 1.5, my = cy + b * 0.2 + gy;
    const munch = (an === 'eat' && Math.floor(ap * 6) % 2 === 0) || (mood === 'watch' && (t % 4) < 0.5);
    if (!S.mask && munch) { ellipse(cr, mx, my + 1, 2.2, 2.4); rgba(cr, EYE); cr.fill(); }
    else if (!S.mask && an === 'huff') { ellipse(cr, mx - 1.5, my + 1, 1.4, 1.1); rgba(cr, EYE); cr.fill(); }
    else if (!S.mask && grumpy && an !== 'heart') {
        cr.newPath(); cr.arc(mx, my + 3.2, 2.6, Math.PI * 1.2, Math.PI * 1.8); rgba(cr, EYE); cr.setLineWidth(1.4); cr.stroke();
    } else if (!S.mask && an === 'sideeye') {
        cr.moveTo(mx - 2.5, my + 1); cr.lineTo(mx + 2.5, my + 0.6); rgba(cr, EYE); cr.setLineWidth(1.2); cr.stroke();
    } else if (mood === 'drowsy' && t < A.yawnUntil) { ellipse(cr, mx, my + 1, 1.8, 2.4); rgba(cr, EYE); cr.fill(); }
    else if (mood !== 'sleep' && !S.dozing && !S.mask) {
        cr.newPath(); cr.arc(mx - 1.5, my, 1.5, 0.1 * Math.PI, 0.9 * Math.PI);
        cr.newSubPath(); cr.arc(mx + 1.5, my, 1.5, 0.1 * Math.PI, 0.9 * Math.PI);
        rgba(cr, EYE); cr.setLineWidth(1.3); cr.stroke();
    }

    // masks
    if (S.mask === 1) {
        for (const s of [-1, 1]) { cr.moveTo(cx + s * a * 0.6, cy + b * 0.26); cr.lineTo(cx + s * a * 0.95, cy - b * 0.08); }
        rgba(cr, WHITE, 0.85); cr.setLineWidth(1); cr.stroke();
        rrect(cr, cx - a * 0.62, cy + b * 0.18, a * 1.24, b * 0.5, 3);
        rgba(cr, [0.68, 0.85, 0.97]); cr.fillPreserve(); rgba(cr, [0.45, 0.65, 0.82]); cr.setLineWidth(0.9); cr.stroke();
        for (const k of [0.33, 0.5]) { cr.moveTo(cx - a * 0.5, cy + b * k); cr.lineTo(cx + a * 0.5, cy + b * k); }
        rgba(cr, [0.45, 0.65, 0.82], 0.6); cr.setLineWidth(0.8); cr.stroke();
    } else if (S.mask === 2) {
        for (const s of [-1, 1]) { cr.moveTo(cx + s * a * 0.45, cy + b * 0.3); cr.lineTo(cx + s * a * 0.97, cy + b * 0.05); }
        rgba(cr, [0.35, 0.36, 0.42]); cr.setLineWidth(1.1); cr.stroke();
        ellipse(cr, cx, cy + b * 0.42, a * 0.5, b * 0.3);
        rgba(cr, [0.96, 0.95, 0.91]); cr.fillPreserve(); rgba(cr, [0.66, 0.65, 0.62]); cr.setLineWidth(0.9); cr.stroke();
        cr.moveTo(cx, cy + b * 0.14); cr.lineTo(cx, cy + b * 0.7); rgba(cr, [0.66, 0.65, 0.62], 0.8); cr.setLineWidth(0.8); cr.stroke();
        ellipse(cr, cx + a * 0.24, cy + b * 0.46, 2.3, 2.3); rgba(cr, [0.55, 0.58, 0.66]); cr.fill();
    } else if (S.mask === 3) {
        for (const s of [-1, 1]) { cr.moveTo(cx + s * a * 0.4, cy + b * 0.28); cr.lineTo(cx + s * a * 0.98, cy + b * 0.12); }
        rgba(cr, [0.2, 0.21, 0.25]); cr.setLineWidth(1.4); cr.stroke();
        rrect(cr, cx - a * 0.42, cy + b * 0.12, a * 0.84, b * 0.6, 5); rgba(cr, [0.24, 0.25, 0.3]); cr.fill();
        for (let i = 0; i < 3; i++) { cr.moveTo(cx - a * 0.18, cy + b * (0.3 + i * 0.13)); cr.lineTo(cx + a * 0.18, cy + b * (0.3 + i * 0.13)); }
        rgba(cr, [0.55, 0.57, 0.64]); cr.setLineWidth(0.9); cr.stroke();
        for (const s of [-1, 1]) {
            const fx = cx + s * a * 0.55, fy = cy + b * 0.5;
            ellipse(cr, fx, fy, 4.4, 4.4); rgba(cr, [0.3, 0.31, 0.37]); cr.fillPreserve();
            rgba(cr, [0.98, 0.8, 0.3]); cr.setLineWidth(1.2); cr.stroke();
            ellipse(cr, fx, fy, 1.6, 1.6); rgba(cr, [0.55, 0.57, 0.64]); cr.fill();
        }
    }
    if (def.drawOver) def.drawOver(E);
    // props
    if (mood === 'watch') {
        ellipse(cr, cx, cy - b * 0.1, a * 0.8, b * 0.6); rgba(cr, col('sky'), 0.10 + 0.04 * Math.sin(t * 5)); cr.fill();
        const px = cx - a * 0.62, py = by - 1;
        cr.newPath(); cr.moveTo(px - 4.5, py - 9); cr.lineTo(px + 4.5, py - 9); cr.lineTo(px + 3.3, py); cr.lineTo(px - 3.3, py);
        cr.closePath(); rgba(cr, WHITE); cr.fill();
        for (let i = -1; i <= 1; i++) cr.rectangle(px + i * 3 - 0.8, py - 9, 1.6, 9);
        rgba(cr, col('red')); cr.fill();
        for (const o of [[-2.5, -10], [0.5, -11.2], [3, -10], [-0.8, -12.3]]) {
            ellipse(cr, px + o[0], py + o[1], 1.8, 1.5); rgba(cr, [1, 0.95, 0.78]); cr.fill();
        }
    }
    if (an === 'eat' && ap < 0.92) {
        const r = 5.5 * (1 - Math.floor(ap * 3) / 3) + 1.2, tx = cx + a * 0.1, ty = by - r - 0.5;
        ellipse(cr, tx, ty, r, r * 0.85); rgba(cr, [1, 0.94, 0.96]); cr.fillPreserve();
        rgba(cr, [0.8, 0.7, 0.75]); cr.setLineWidth(0.8); cr.stroke();
        ellipse(cr, tx + r * 0.2, ty - r * 0.15, r * 0.3, r * 0.25); rgba(cr, col('pink'), 0.8); cr.fill();
    }
    if (an === 'coffee') {
        if (ap > 0.35 && ap < 0.7) mug(cr, cx + a * 0.3, cy + b * 0.55, t, false, col('peach'));
        else mug(cr, cx + a * 0.62, by - 0.5, t, true, col('peach'));
    } else if (S.hot) {
        mug(cr, cx + a * 0.62, by - 0.5, t, true, col('peach'));
    }
    if (an === 'search') {
        const hx = cx + a * 0.78 + Math.sin(2 * Math.PI * ap * 1.5) * 4, hy = cy + b * 0.05;
        cr.moveTo(hx + 3.4, hy + 3.4); cr.lineTo(hx + 7.5, hy + 8);
        rgba(cr, [0.45, 0.33, 0.25]); cr.setLineWidth(2.2); cr.stroke();
        ellipse(cr, hx, hy, 5, 5); rgba(cr, col('sky'), 0.25); cr.fillPreserve();
        rgba(cr, col('overlay2')); cr.setLineWidth(1.7); cr.stroke();
        ellipse(cr, hx - 1.6, hy - 1.6, 1.2, 0.8); rgba(cr, WHITE, 0.7); cr.fill();
    }
    if (an === 'wave') {
        cr.save(); cr.translate(cx + a * 0.9, cy - b * 0.05); cr.rotate(-0.35 + 0.55 * Math.sin(4 * Math.PI * ap));
        ellipse(cr, 0, -5, 3.2, 6); rgba(cr, mix(base, WHITE, 0.15)); cr.fillPreserve();
        rgba(cr, mix(base, BLACK, 0.35), 0.6); cr.setLineWidth(1); cr.stroke();
        cr.restore();
    }
    // typing
    if (an === 'typing') {
        ellipse(cr, cx, cy + b * 0.1, a * 0.75, b * 0.55); rgba(cr, col('sky'), 0.14); cr.fill();
        const lw = 22, lh = 8;
        rrect(cr, cx - lw / 2, by - lh - 1, lw, lh, 2.5); rgba(cr, [0.27, 0.28, 0.33]); cr.fillPreserve();
        rgba(cr, [0.45, 0.47, 0.54]); cr.setLineWidth(0.8); cr.stroke();
        if (S.type_kind === 'term')
            textC(cr, cx - 1, by - 2.6, '>' + (Math.floor(t * 2) % 2 === 0 ? '_' : ' '), 7.5, [0.55, 0.92, 0.55], 1, true);
        else if (S.type_kind === 'code')
            textC(cr, cx, by - 2.6, '</>', 7, col('sky'), 1, true);
        else { ellipse(cr, cx, by - lh / 2 - 1, 1.4, 1.4); rgba(cr, WHITE, 0.55); cr.fill(); }
        rrect(cr, cx - lw / 2 - 2, by - 1.5, lw + 4, 2.5, 1); rgba(cr, [0.2, 0.21, 0.25]); cr.fill();
        const f = Math.floor(t * 4) % 2;
        [-1, 1].forEach((s, i) => {
            const up = i === f ? 2 : 0;
            ellipse(cr, cx + s * 5.5, by - lh - 1.5 - up, 2.8, 2.2); rgba(cr, mix(base, BLACK, 0.05)); cr.fillPreserve();
            rgba(cr, mix(base, BLACK, 0.35), 0.6); cr.setLineWidth(0.8); cr.stroke();
        });
    }
    cr.restore();   // rotation

    // extras
    if (an === 'heart') {
        const hx = cx + a * 0.65, hy = cy - b - 3 - ap * 14, s = 4;
        cr.newPath(); cr.arc(hx - s / 2, hy, s / 2, Math.PI, 0); cr.arc(hx + s / 2, hy, s / 2, Math.PI, 0);
        cr.lineTo(hx, hy + s * 1.15); cr.closePath(); rgba(cr, col('red'), Math.sin(Math.PI * ap)); cr.fill();
    } else if (an === 'curious') {
        text(cr, cx + a * 0.7, cy - b - 1, '?', 15, col('text'), Math.min(1, ap * 4, (1 - ap) * 4), true);
    } else if (an === 'startle') {
        text(cr, cx + a * 0.55, cy - b - 2, '!', 16, col('yellow'), 1 - ap * 0.6, true);
    } else if (an === 'chime') {
        for (let i = 0; i < 6; i++) {
            const ang = i * Math.PI / 3 + ap * 1.2, r = a + 3 + ap * 8;
            const x = cx + Math.cos(ang) * r, y = cy + Math.sin(ang) * r * 0.8;
            cr.newPath(); cr.moveTo(x, y - 3); cr.lineTo(x + 2, y); cr.lineTo(x, y + 3); cr.lineTo(x - 2, y); cr.closePath();
            rgba(cr, col('yellow'), Math.sin(Math.PI * ap)); cr.fill();
        }
    } else if (an === 'sneeze' && ap >= 0.5) {
        const k = (ap - 0.5) * 2;
        for (let i = -1; i <= 1; i++) {
            const ang = Math.PI + i * 0.45, r0 = a * 0.75 + k * 4, r1 = a * 0.75 + 4 + k * 6;
            cr.moveTo(cx + Math.cos(ang) * r0, cy + b * 0.3 + Math.sin(ang) * r0 * 0.5);
            cr.lineTo(cx + Math.cos(ang) * r1, cy + b * 0.3 + Math.sin(ang) * r1 * 0.5);
        }
        rgba(cr, col('text'), 0.7 * (1 - k)); cr.setLineWidth(1.3); cr.stroke();
    }
    if (an === 'huff' && ap > 0.4) {               // puffs of air out the side
        const k = (ap - 0.4) / 0.6;
        for (let i = 0; i < 2; i++) {
            const r = 1.8 + k * 2.4 - i * 0.6;
            ellipse(cr, cx - a - 2 - k * 8 - i * 4, cy + b * 0.25 - i * 3 - k * 2, r, r * 0.8);
            rgba(cr, WHITE, 0.65 * (1 - k)); cr.fill();
        }
    }
    if (def.drawAct && an) def.drawAct(E, an, ap);
    if (grumpy === 'woken') {                       // pulsing anger mark
        const s = 1 + 0.15 * Math.sin(t * 6), mx2 = cx + a * 0.85, my2 = cy - b * 0.85;
        for (const [qx, qy] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {     // four brackets bowing inward
            const dx = qx * s, dy = qy * s;
            cr.moveTo(mx2 + dx * 1.3, my2 + dy * 4.6);
            cr.curveTo(mx2 + dx * 1.6, my2 + dy * 1.6, mx2 + dx * 1.6, my2 + dy * 1.6, mx2 + dx * 4.6, my2 + dy * 1.3);
        }
        rgba(cr, col('red'), 1); cr.setLineWidth(1.9); cr.stroke();
    }
    if (S.dozing) {
        const p = (t * 0.25) % 1;
        text(cr, cx - a * 0.5 - p * 8, cy - b - 2 - p * 10, 'z', 10 + p * 3, col('text'), Math.sin(p * Math.PI) * 0.85, true);
    }
    if (an === 'dance' && mood !== 'music') {
        for (let k = 0; k < 2; k++) {
            const p = (t * 0.45 + k * 0.5) % 1;
            text(cr, cx + a + 4 + p * 6, cy - b + 4 - p * 16, k === 0 ? '\u{f0387}' : '\u{f075a}', k === 0 ? 14 : 12,
                col('accent2'), Math.sin(p * Math.PI), false, ICON_FONT);
        }
    }
    // headphones + notes
    if (mood === 'music') {
        cr.newPath(); cr.arc(cx, cy + 1, a * 1.02, Math.PI * 1.08, Math.PI * 1.92);
        rgba(cr, col('overlay2')); cr.setLineWidth(3); cr.stroke();
        for (const s of [-1, 1]) {
            rrect(cr, cx + s * a * 0.98 - 3.5, cy - 7, 7, 12, 3); rgba(cr, col('accent2')); cr.fillPreserve();
            rgba(cr, mix(col('accent2'), BLACK, 0.35)); cr.setLineWidth(1); cr.stroke();
        }
        for (let k = 0; k < 2; k++) {
            const p = (t * 0.45 + k * 0.5) % 1;
            text(cr, cx - a - 8 - p * 6 + Math.sin(p * 6) * 2, cy - b + 4 - p * 16, k === 0 ? '\u{f0387}' : '\u{f075a}',
                k === 0 ? 14 : 12, col('accent2'), Math.sin(p * Math.PI), false, ICON_FONT);
        }
    }
    if (mood === 'sleep') {
        for (let k = 0; k < 2; k++) {
            const p = (t * 0.22 + k * 0.5) % 1;
            text(cr, cx - a * 0.6 - p * 12, cy - b - 2 - p * 14, k === 0 ? 'z' : 'Z', 10 + p * 5, col('text'),
                Math.sin(p * Math.PI) * 0.9, true);
        }
    }
    // weather
    if (wx === 'rain' || wx === 'storm') {
        const ux = cx + 3, uy = cy - b - 9;
        if (def.rainGear !== false) {
            cr.newPath(); cr.arc(ux, uy + 7, a * 0.95, Math.PI, 2 * Math.PI);
            for (let i = 3; i >= 0; i--) cr.arcNegative(ux - a * 0.95 + (i + 0.5) * (a * 1.9 / 4), uy + 7, a * 1.9 / 8, 0, Math.PI);
            cr.closePath();
            rgba(cr, col('accent2')); cr.fillPreserve(); rgba(cr, mix(col('accent2'), BLACK, 0.3)); cr.setLineWidth(1); cr.stroke();
            cr.moveTo(ux, uy + 7); cr.lineTo(ux, cy - b + 3); rgba(cr, col('overlay2')); cr.setLineWidth(1.4); cr.stroke();
        }
        for (let k = 0; k < 4; k++) {
            const p = (t * 1.3 + k * 0.27) % 1;
            const x = ux + (k % 2 === 0 ? -1 : 1) * (a * 1.05 + 3 + k), y = uy + 4 + p * (b * 2 + 6);
            cr.moveTo(x, y); cr.lineTo(x - 1, y + 4);
            rgba(cr, col('sky'), 0.8 * Math.sin(p * Math.PI)); cr.setLineWidth(1.4); cr.stroke();
        }
    } else if (wx === 'snow') {
        for (let k = 0; k < 5; k++) {
            const p = (t * 0.35 + k * 0.21) % 1;
            const x = cx + (k - 2) * a * 0.55 + Math.sin(t * 1.5 + k) * 3, y = cy - b - 10 + p * (b * 2 + 14);
            ellipse(cr, x, y, 1.5, 1.5); rgba(cr, WHITE, 0.9 * Math.sin(p * Math.PI)); cr.fill();
        }
    } else if (wx === 'fog') {
        for (let k = 0; k < 2; k++) {
            const ph = (t * 0.08 + k * 0.5) % 1;
            ellipse(cr, cx - a * 1.4 + ph * a * 2.8, cy + (k === 0 ? -2 : 6), a * 0.9, 3.2);
            rgba(cr, col('overlay2'), 0.32 * Math.sin(ph * Math.PI)); cr.fill();
        }
    }
    cr.restore();
}
