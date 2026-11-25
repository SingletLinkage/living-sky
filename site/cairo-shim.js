// A tiny cairo-like API over the browser's Canvas 2D, just enough for the glob pets' drawing code
// (gnome-extension/glob@living-sky/pets/*.js, bundled into pets.js by gnome-extension/build-web.py).
// The same code draws the pets in the GNOME panel (real cairo) and on this page (this shim).
'use strict';
(function () {
  const css = (r, g, b, a) => `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},${a})`;

  class Gradient {
    constructor() { this.stops = []; }
    addColorStopRGBA(o, r, g, b, a) { this.stops.push([o, css(r, g, b, a)]); }
    addColorStopRGB(o, r, g, b) { this.addColorStopRGBA(o, r, g, b, 1); }
    make(ctx) {
      const g = this.create(ctx);
      for (const [o, c] of this.stops) g.addColorStop(Math.min(1, Math.max(0, o)), c);
      return g;
    }
  }
  class LinearGradient extends Gradient {
    constructor(x0, y0, x1, y1) { super(); this.p = [x0, y0, x1, y1]; }
    create(ctx) { return ctx.createLinearGradient(...this.p); }
  }
  class RadialGradient extends Gradient {
    constructor(x0, y0, r0, x1, y1, r1) { super(); this.p = [x0, y0, Math.max(0, r0), x1, y1, Math.max(0, r1)]; }
    create(ctx) { return ctx.createRadialGradient(...this.p); }
  }

  // Nerd Font icons used by the pets -> plain Unicode on the web
  const GLYPHS = {'\u{f0387}': '♪', '\u{f075a}': '♫'};

  class Context {
    constructor(ctx) {
      this.ctx = ctx; this.sub = true; this.px = 0; this.py = 0;
      this.font = {family: 'JetBrains Mono', weight: 'normal', size: 10};
      ctx.beginPath();
    }
    // paths (cairo keeps the path across save/restore; so does canvas)
    newPath() { this.ctx.beginPath(); this.sub = true; }
    newSubPath() { this.sub = true; }
    moveTo(x, y) { this.ctx.moveTo(x, y); this.px = x; this.py = y; this.sub = false; }
    lineTo(x, y) { if (this.sub) this.moveTo(x, y); else { this.ctx.lineTo(x, y); this.px = x; this.py = y; } }
    curveTo(a, b, c, d, x, y) { if (this.sub) this.moveTo(a, b); this.ctx.bezierCurveTo(a, b, c, d, x, y); this.px = x; this.py = y; }
    closePath() { this.ctx.closePath(); }
    rectangle(x, y, w, h) { this.ctx.rect(x, y, w, h); this.sub = true; }
    arc(x, y, r, a1, a2) { this._arc(x, y, r, a1, a2, false); }
    arcNegative(x, y, r, a1, a2) { this._arc(x, y, r, a1, a2, true); }
    _arc(x, y, r, a1, a2, neg) {
      if (this.sub) this.ctx.moveTo(x + r * Math.cos(a1), y + r * Math.sin(a1));
      this.ctx.arc(x, y, Math.max(0, r), a1, a2, neg);
      this.px = x + r * Math.cos(a2); this.py = y + r * Math.sin(a2); this.sub = false;
    }
    // painting
    setSourceRGBA(r, g, b, a) { this.ctx.fillStyle = this.ctx.strokeStyle = css(r, g, b, a); }
    setSourceRGB(r, g, b) { this.setSourceRGBA(r, g, b, 1); }
    setSource(p) { const g = p.make(this.ctx); this.ctx.fillStyle = this.ctx.strokeStyle = g; }
    fill() { this.ctx.fill(); this.newPath(); }
    fillPreserve() { this.ctx.fill(); }
    stroke() { this.ctx.stroke(); this.newPath(); }
    strokePreserve() { this.ctx.stroke(); }
    clip() { this.ctx.clip(); this.newPath(); }
    paint() {
      const c = this.ctx;
      c.save(); c.setTransform(1, 0, 0, 1, 0, 0); c.fillRect(0, 0, c.canvas.width, c.canvas.height); c.restore();
    }
    setLineWidth(w) { this.ctx.lineWidth = w; }
    setLineCap(c) { this.ctx.lineCap = c; }
    setLineJoin(j) { this.ctx.lineJoin = j; }
    // transforms
    save() { this.ctx.save(); }
    restore() { this.ctx.restore(); }
    translate(x, y) { this.ctx.translate(x, y); }
    rotate(a) { this.ctx.rotate(a); }
    scale(x, y) { this.ctx.scale(x, y); }
    // text
    selectFontFace(family, slant, weight) { this.font.family = family; this.font.weight = weight; }
    setFontSize(s) { this.font.size = s; }
    _font(s) {
      const icon = /[\u{f0000}-\u{fffff}]/u.test(s);
      const fam = icon ? 'system-ui' : `"${this.font.family}"`;
      this.ctx.font = `${this.font.weight} ${this.font.size}px ${fam}, "JetBrains Mono", ui-monospace, monospace`;
      return icon ? s.replace(/[\u{f0000}-\u{fffff}]/gu, ch => GLYPHS[ch] || '') : s;
    }
    showText(s) {
      const t = this._font(s);
      this.ctx.fillText(t, this.px, this.py);
      this.px += this.ctx.measureText(t).width;
    }
    textExtents(s) {
      const m = this.ctx.measureText(this._font(s));
      return {xAdvance: m.width, width: m.width, height: (m.actualBoundingBoxAscent || 0) + (m.actualBoundingBoxDescent || 0),
        xBearing: 0, yBearing: -(m.actualBoundingBoxAscent || 0)};
    }
  }

  window.LivingSkyCairo = {
    Context, LinearGradient, RadialGradient,
    FontSlant: {NORMAL: 'normal', ITALIC: 'italic', OBLIQUE: 'oblique'},
    FontWeight: {NORMAL: 'normal', BOLD: 'bold'},
    LineCap: {BUTT: 'butt', ROUND: 'round', SQUARE: 'square'},
    LineJoin: {MITER: 'miter', ROUND: 'round', BEVEL: 'bevel'},
    Format: {ARGB32: 0},
  };
})();
