// living-sky site: switchers over the images in art/ (copied next to this page on deploy) and live glob pets
// drawn by the same code as the desktop panel pet (pets.js, on cairo-shim.js).
// Everything here is progressive enhancement: the page reads fine without it.
const $ = s => document.querySelector(s);
const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
const safe = (name, fn) => { try { fn(); } catch (e) { console.error(`living-sky site: ${name}`, e); } };
const saveData = !!(navigator.connection && navigator.connection.saveData);

// Swap an <img>'s source with a short cross-fade; the new file is fetched first so nothing flashes blank.
function swap(img, src, alt) {
  img.alt = alt;
  if (img.getAttribute('src') === src) return;
  const token = img._swap = (img._swap || 0) + 1;
  const done = () => { if (img._swap === token) { img.src = src; img.classList.remove('fading'); } };
  if (!calm) img.classList.add('fading');
  const pre = new Image();
  pre.onload = pre.onerror = () => setTimeout(done, calm ? 0 : 150);
  pre.src = src;
}

// A row of toggle buttons sharing one data-* attribute (aria-pressed).
function toggles(sel, attr, onPick) {
  const btns = [...document.querySelectorAll(`${sel} [data-${attr}]`)];
  btns.forEach(b => b.addEventListener('click', () => {
    btns.forEach(x => { x.classList.toggle('on', x === b); x.setAttribute('aria-pressed', String(x === b)); });
    onPick(b.dataset[attr]);
  }));
}

// A real tablist: roles, aria-selected, roving tabindex, arrow/Home/End keys.
function tablist(list, panel, attr, onPick) {
  const btns = [...list.querySelectorAll(`[data-${attr}]`)];
  list.setAttribute('role', 'tablist');
  const select = (b, focus) => {
    btns.forEach(x => {
      const on = x === b;
      x.classList.toggle('on', on); x.setAttribute('aria-selected', String(on)); x.tabIndex = on ? 0 : -1;
    });
    panel.setAttribute('aria-labelledby', b.id);
    if (focus) b.focus();
    onPick(b.dataset[attr]);
  };
  btns.forEach((b, i) => {
    b.setAttribute('role', 'tab'); b.setAttribute('aria-controls', panel.id);
    b.setAttribute('aria-selected', String(b.classList.contains('on'))); b.tabIndex = b.classList.contains('on') ? 0 : -1;
    b.addEventListener('click', () => select(b, false));
    b.addEventListener('keydown', e => {
      const k = {ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1, ArrowUp: i - 1, Home: 0, End: btns.length - 1}[e.key];
      if (k === undefined) return;
      e.preventDefault(); select(btns[(k + btns.length) % btns.length], true);
    });
  });
}

// Header: menu button (small screens), shadow on scroll, current section
safe('header', () => {
  const header = $('.top'), nav = $('#site-nav'), btn = $('.menu-btn');
  const setOpen = open => { nav.classList.toggle('open', open); btn.setAttribute('aria-expanded', String(open)); };
  btn.addEventListener('click', () => setOpen(!nav.classList.contains('open')));
  nav.addEventListener('click', e => { if (e.target.closest('a')) setOpen(false); });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && nav.classList.contains('open')) { setOpen(false); btn.focus(); }
  });
  document.addEventListener('click', e => { if (!header.contains(e.target)) setOpen(false); });
  const onScroll = () => header.classList.toggle('scrolled', scrollY > 8);
  addEventListener('scroll', onScroll, {passive: true}); onScroll();

  if ('IntersectionObserver' in window) {
    const links = new Map([...nav.querySelectorAll('a[href^="#"]')].map(a => [a.getAttribute('href').slice(1), a]));
    const spy = new IntersectionObserver(entries => entries.forEach(en => {
      const a = links.get(en.target.id);
      if (!a) return;
      if (en.isIntersecting) { links.forEach(l => l.removeAttribute('aria-current')); a.setAttribute('aria-current', 'true'); }
      else a.removeAttribute('aria-current');
    }), {rootMargin: '-40% 0px -55% 0px'});
    links.forEach((_, id) => { const s = document.getElementById(id); if (s) spy.observe(s); });
  }
});

// Install: copy buttons on the code blocks
safe('copy', () => {
  const status = $('#copy-status');
  document.querySelectorAll('main pre').forEach(pre => {
    pre.tabIndex = 0; pre.setAttribute('role', 'region'); pre.setAttribute('aria-label', 'Commands (scrollable)');
    const box = document.createElement('div'); box.className = 'codebox';
    pre.replaceWith(box);
    const bar = document.createElement('div'); bar.className = 'codebox-bar'; box.append(bar, pre);
    bar.innerHTML = '<span class="dots" aria-hidden="true"><i></i><i></i><i></i></span><span class="codebox-title"></span>';
    bar.querySelector('.codebox-title').textContent = pre.dataset.title || 'terminal';
    if (pre.hasAttribute('data-no-copy')) return;      // reference / either-or blocks: copying them would run them all
    const btn = document.createElement('button');
    btn.type = 'button'; btn.className = 'copy'; btn.textContent = 'Copy'; btn.setAttribute('aria-label', 'Copy commands');
    bar.appendChild(btn);
    btn.addEventListener('click', async () => {
      const text = pre.innerText.trim();
      try { await navigator.clipboard.writeText(text); }
      catch (e) {
        const ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); } catch (e2) { /* nothing more to try */ }
        ta.remove(); btn.focus();
      }
      btn.textContent = 'Copied'; status.textContent = 'Copied to clipboard';
      setTimeout(() => { btn.textContent = 'Copy'; status.textContent = ''; }, 1800);
    });
  });
});

// Scroll reveal (skipped for reduced motion; without JS everything is simply visible)
safe('reveal', () => {
  if (calm || !('IntersectionObserver' in window)) return;
  const io = new IntersectionObserver(entries => entries.forEach(en => {
    if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
  }), {threshold: 0.12, rootMargin: '0px 0px -8% 0px'});
  document.querySelectorAll('main > section:not(.hero) > *').forEach(el => { el.classList.add('reveal-ready'); io.observe(el); });
});

// Hero: a static poster first, the 3.5 MB animation after load, and a pause/play button
safe('hero', () => {
  const img = $('#hero-img'), cap = $('#hero-cap'), fig = $('#hero-media');
  const poster = {src: img.getAttribute('src'), alt: img.alt, cap: 'The lake at night with frosted cards. Press play to watch a day pass.'};
  const gif = {src: img.dataset.gif, alt: 'A day of the living sky, from night through sunrise and noon to sunset', cap: cap.textContent};
  const btn = document.createElement('button');
  btn.type = 'button'; btn.className = 'btn small';
  $('.hero-row').appendChild(btn);
  // states: 'still' (poster), 'loading' (fetching the animation; poster still shown), 'playing'
  let state = 'still', loaded = false;
  const set = s => {
    state = s;
    const playing = s === 'playing', v = playing ? gif : poster;
    img.src = v.src; img.alt = v.alt;
    cap.textContent = s === 'loading' ? 'Loading the day animation (3.5 MB)…' : v.cap;
    btn.textContent = playing ? 'Pause animation' : s === 'loading' ? 'Loading…' : 'Play animation';
    btn.setAttribute('aria-pressed', String(s !== 'still'));
    btn.toggleAttribute('aria-busy', s === 'loading');
  };
  const play = () => {
    if (loaded) return set('playing');
    set('loading');
    const pre = new Image();
    pre.onload = () => { loaded = true; if (state === 'loading') set('playing'); };
    pre.onerror = () => { if (state === 'loading') { set('still'); cap.textContent = 'The animation could not be loaded.'; } };
    pre.src = gif.src;
  };
  btn.addEventListener('click', () => { if (state === 'still') play(); else set('still'); });
  set('still');
  // plays by itself after the page has loaded, unless the visitor asked for less motion or less data
  if (!calm && !saveData) {
    const start = () => { if (state === 'still') play(); };
    if (document.readyState === 'complete') setTimeout(start, 200); else addEventListener('load', () => setTimeout(start, 200));
  }
});

// Sky: the glass style at night or by day (solid cards are shown once, beside it)
safe('looks', () => {
  toggles('#looks .switch', 'time', t => {
    swap($('#look-img'), `art/demos/glass-${t}.jpg`, `The glass cards over the lake ${t === 'day' ? 'by day' : 'at night'}`);
    $('#look-title').textContent = `living-sky · glass · ${t}`;
  });
  if (!saveData) addEventListener('load', () => (window.requestIdleCallback || setTimeout)(() => { new Image().src = 'art/demos/glass-day.jpg'; }));
});

// Scenes
safe('scenes', () => {
  const SCENES = {
    lake: 'Mountains over a lake with reflections; snow on the lit faces of the peaks in winter.',
    forest: 'Rolling pine hills: valley mist at dawn and dusk, a cabin window that glows at night, gold larches in autumn.',
    city: 'A skyline whose windows light up in the evening and go dark through the night, a different set every hour.',
    camp: 'A tent in a forest clearing; the campfire burns from dusk to dawn, only embers by day; fireflies on summer nights.',
  };
  const hours = $('#hours-img'), details = $('#hours-details');
  let scene = 'lake';
  const applyHours = () => swap(hours, `art/demos/hours/${scene}.jpg`, `The ${scene} scene for every hour of a day`);
  details.addEventListener('toggle', () => { if (details.open) applyHours(); });   // only fetch the big sheet when it is open
  const showScene = s => {
    scene = s;
    swap($('#scene-img'), `art/demos/scene-${s}.jpg`, `The ${s} scene at four times of day`);
    if (details.open) applyHours();
    $('#scene-text').textContent = SCENES[s];
    $('#scene-title').textContent = `${s} · night · dawn · midday · dusk`;
  };
  tablist($('#scenes .switch'), $('#scene-panel'), 'scene', showScene);
});

// Cards (glass only, night | day)
const CARDS = ['clock', 'weather', 'calendar', 'media', 'cpu', 'memory', 'disks', 'gpu', 'battery', 'network'];
safe('cards', () => {
  const NAME = {cpu: 'CPU', gpu: 'GPU', media: 'Now playing'};
  const tabs = $('#card-tabs'), img = $('#card-img');
  CARDS.forEach((c, i) => {
    const b = document.createElement('button');
    b.type = 'button'; b.id = `tab-card-${c}`;
    b.textContent = NAME[c] || c[0].toUpperCase() + c.slice(1);
    b.dataset.card = c;
    if (i === 0) b.className = 'on';
    tabs.appendChild(b);
  });
  tablist(tabs, $('#card-panel'), 'card', c => {
    swap(img, `art/site/cards/${c}.jpg`, `The ${(NAME[c] || c).toLowerCase()} card at night and by day`);
    $('#card-title').textContent = `card · ${c} · night | day`;
  });
});

// ---------------------------------------------------------------- glob pets (live)
const P = window.LivingSkyPets, LSC = window.LivingSkyCairo;
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
const MOCHA = {accent: '#b4befe', accent2: '#fab387', text: '#cdd6f4', subtext0: '#a6adc8', overlay2: '#9399b2', red: '#f38ba8',
  yellow: '#f9e2af', pink: '#f5c2e7', sky: '#89dceb', blue: '#89b4fa', peach: '#fab387', shadow: '#11111b', base: '#1e1e2e',
  lavender: '#b4befe', mauve: '#cba6f7', teal: '#94e2d5', sapphire: '#74c7ec', green: '#a6e3a1'};
const COLORS = Object.fromEntries(Object.entries(MOCHA).map(([k, v]) => [k, hex(v)]));
const INFO = {
  mimi: ['Mimi', 'Cheerful, social lavender blob. Morning coffee, dances, waves.', 'asleep 00–06'],
  pip: ['Pip', 'A hyper sapphire droplet: hops a lot, splashes in the rain, startles easily.', 'scene pet: lake'],
  bun: ['Bun', 'A sleepy slice of bread: naps, snacks twice as often, grumpy when woken.', 'scene pet: forest'],
  nyx: ['Nyx', 'A little moon showing tonight’s real phase: awake at night, stargazes.', 'asleep by day'],
  cubo: ['Cubo', 'A studious teal cube with glasses: reads, coffee all day, sneezes at dust.', 'scene pet: city'],
  ember: ['Ember', 'A campfire wisp that burns with your CPU; a blue pilot light when cold.', 'scene pet: camp'],
};
// still poses for the guides: state + an action and how far into it (0..1)
const POSES = {
  wave: {act: 'wave', dur: 2.0, p: 0.15}, curious: {act: 'curious', dur: 2.6, p: 0.5}, read: {act: 'read', dur: 4.0, p: 0.3},
  flare: {act: 'flare', dur: 2.0, p: 0.5}, stargaze: {act: 'stargaze', dur: 4.0, p: 0.5}, sleep: {S: {mood: 'sleep'}},
};

function petState(id, extra) {
  const def = P.PETS[id];
  return Object.assign({mood: 'awake', weather: 'clear', mask: 0, shades: false, dozing: false, hot: false, act: '', act_id: 0,
    act_dur: 0, light: false, colors: COLORS, body: def.swatch ? hex(def.swatch) : COLORS.accent, cpu: 30, moon: 100,
    waxing: true}, extra || {});
}
// size a canvas for the screen's pixel density; its width/height attributes are its CSS size
function fitCanvas(cv, w, h) {
  const dpr = Math.min(3, window.devicePixelRatio || 1);
  cv.style.width = `${w}px`; cv.style.height = `${h}px`;
  cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
  const ctx = cv.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return ctx;
}
function drawInto(ctx, w, h, id, S, A, t) {
  ctx.clearRect(0, 0, w, h);
  P.drawPet(new LSC.Context(ctx), S, A, t, w, h, P.PETS[id]);
}
// one still frame of a pet in a pose (the drawing code animates by time, so step it to the pose's moment)
function drawPose(ctx, w, h, id, poseName) {
  const pose = POSES[poseName] || {};
  const S = petState(id, pose.S);
  if (pose.act) { S.act = pose.act; S.act_dur = pose.dur; S.act_id = 1; }
  const A = P.newAnim();
  P.tick(S, A, 10, P.PETS[id]);            // start the action at t = 10 (past the first blink)
  A.blinkAt = 1e9; A.nextGlance = 1e9;     // a still shouldn't catch a blink
  drawInto(ctx, w, h, id, S, A, 10 + (pose.dur || 0) * (pose.p || 0));
}

safe('pets', () => {
  if (!P || !LSC) { document.documentElement.classList.add('no-pets'); return; }

  // guides beside the section headings: a still pose; a little hop when you point at them
  document.querySelectorAll('canvas.guide-pet').forEach(cv => {
    const w = +cv.getAttribute('width'), h = +cv.getAttribute('height'), id = cv.dataset.pet, pose = cv.dataset.pose;
    const ctx = fitCanvas(cv, w, h);
    drawPose(ctx, w, h, id, pose);
    if (calm) return;
    const host = cv.closest('.guide, .hero-media, .signoff') || cv;
    let busy = false;
    host.addEventListener('pointerenter', () => {
      if (busy || pose === 'sleep') return;
      busy = true;
      const S = petState(id, {act: 'hop', act_dur: 1.0, act_id: 1}), A = P.newAnim();
      const t0 = performance.now() / 1000;
      const frame = () => {
        const t = performance.now() / 1000 - t0;
        drawInto(ctx, w, h, id, S, A, 10 + t);
        if (t < 1.1) requestAnimationFrame(frame); else { drawPose(ctx, w, h, id, pose); busy = false; }
      };
      requestAnimationFrame(frame);
    });
  });

  // the playground
  const pg = $('#playground'); pg.hidden = false;
  const stage = $('#stage'), wrap = stage.parentElement;
  const ACTS = [['hop', 'Hop', 1.0], ['wave', 'Wave', 2.0], ['heart', 'Heart', 2.4], ['dance', 'Dance', 2.5],
    ['coffee', 'Coffee', 3.0], ['wobble', 'Wobble', 1.6], ['curious', 'Curious', 2.6], ['sneeze', 'Sneeze', 1.4]];
  const MOODS = [                  // [key, label, state, exclusive group]
    ['sleep', 'Asleep', {mood: 'sleep'}, 'mood'], ['music', 'Music', {mood: 'music'}, 'mood'],
    ['rain', 'Rain', {weather: 'rain'}, 'weather'], ['storm', 'Storm', {weather: 'storm'}, 'weather'],
    ['snow', 'Snow', {weather: 'snow'}, 'weather'], ['shades', 'Sunglasses', {shades: true}, null],
    ['mask', 'Mask (bad air)', {mask: 2}, null], ['hot', 'Hot CPU', {hot: true}, null]];
  const BASE = {mood: 'awake', weather: 'clear', shades: false, mask: 0, hot: false};
  let id = 'mimi', S = petState(id), A = P.newAnim(), on = new Set(), actUntil = 0, visible = true, raf = 0;
  let W = 640, H = 360, ctx = null;

  const resize = () => { W = Math.max(240, wrap.clientWidth); H = Math.round(W * 9 / 16); ctx = fitCanvas(stage, W, H); paint(); };
  const floorY = () => Math.round(H * 0.66);
  function paint() {
    if (!ctx) return;
    const t = performance.now() / 1000;
    ctx.clearRect(0, 0, W, H);
    // a frosted card for the pet to sit on, like the desktop's clock card
    const fy = floorY(), cx = W * 0.2, cw = W * 0.6;
    ctx.save();
    ctx.fillStyle = 'rgba(49,50,68,0.72)'; ctx.strokeStyle = 'rgba(205,214,244,0.16)'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.roundRect ? ctx.roundRect(cx, fy, cw, H - fy + 24, 16) : ctx.rect(cx, fy, cw, H - fy + 24); ctx.fill(); ctx.stroke();
    ctx.fillStyle = 'rgba(180,190,254,0.92)'; ctx.font = `${Math.round(H * 0.11)}px "Bebas Neue", sans-serif`;
    ctx.fillText('19:59', cx + cw * 0.07, fy + H * 0.17);
    ctx.fillStyle = 'rgba(250,179,135,0.9)'; ctx.font = `bold ${Math.round(H * 0.035)}px "JetBrains Mono", monospace`;
    ctx.fillText('TUESDAY', cx + cw * 0.42, fy + H * 0.13);
    ctx.fillStyle = 'rgba(205,214,244,0.55)'; ctx.fillRect(cx + cw * 0.42, fy + H * 0.16, cw * 0.36, 3);
    ctx.restore();
    // the pet, sitting on the card's top edge (its drawing box is 60 units tall, feet 4 units up)
    const bh = Math.round(H * 0.62), bw = Math.round(bh * 1.6), k = bh / 60;
    ctx.save();
    ctx.translate(Math.round(W / 2 - bw / 2), fy - (bh - 4 * k));
    P.drawPet(new LSC.Context(ctx), S, A, t, bw, bh, dressed(id));
    ctx.restore();
  }
  // seasonal hats (art/site/sticker-*.png): drawn in the pet's own drawOver step, so they follow hops and tilts
  // hat: visible width `w` (in body half-widths a), its brim `brim` of the way down the image, sitting `dy`
  // (in body half-heights b) below the top of the head; clips: an image `w` wide centred at (x a, y b) from the top
  const WEAR = {
    snowcap: {label: 'Snow cap', hat: true, w: 1.25, ink: 0.67, brim: 0.80, dy: 0.32},
    leaf: {label: 'Autumn leaf', w: 0.95, x: 0.62, y: 0.12},
    blossom: {label: 'Blossom', w: 0.9, x: 0.62, y: 0.12},
  };
  const TIP = {ember: 1.5, pip: 1.25};                             // pointed pets: the top is above the body
  const wearImg = {};
  let wearing = null;
  function dressed(pid) {
    const def = P.PETS[pid];
    if (!wearing) return def;
    const img = wearImg[wearing], w = WEAR[wearing];
    if (!img || !img.complete || !img.naturalWidth) return def;
    return Object.assign(Object.create(def), {
      drawOver(E) {
        if (def.drawOver) def.drawOver.call(def, E);
        if (E.mood === 'sleep' && wearing === 'snowcap') return;   // the sleeping pets already wear a nightcap
        const top = E.cy - E.b * (TIP[pid] || 1);
        if (w.hat) {
          const size = E.a * w.w / w.ink;
          E.cr.ctx.drawImage(img, E.cx - size / 2, top + E.b * w.dy - size * w.brim, size, size);
        } else {
          const size = E.a * w.w;
          E.cr.ctx.drawImage(img, E.cx + E.a * w.x - size / 2, top + E.b * w.y - size / 2, size, size);
        }
      },
    });
  }
  let last = 0;
  const loop = now => {
    raf = 0;
    const t = performance.now() / 1000;
    if (now - last < (t < actUntil ? 16 : 33)) { if (visible && !document.hidden) raf = requestAnimationFrame(loop); return; }   // ~30 fps idle, 60 during an action
    last = now;
    paint();
    if (visible && !document.hidden && (!calm || t < actUntil)) raf = requestAnimationFrame(loop);
  };
  const kick = () => { if (!raf) raf = requestAnimationFrame(loop); };

  const apply = () => {                       // rebuild S from the base + the chips that are on
    const keep = {act: S.act, act_id: S.act_id, act_dur: S.act_dur, cpu: S.cpu, moon: S.moon};
    S = petState(id, Object.assign({}, BASE, keep));
    MOODS.forEach(([key, , st]) => { if (on.has(key)) Object.assign(S, st); });
    kick();
  };
  const say = msg => { const l = $('#pet-live'); if (l) l.textContent = msg; };
  const act = (name, dur) => {
    S.act = name; S.act_dur = dur; S.act_id += 1;
    actUntil = performance.now() / 1000 + dur + 0.2;
    const lab = [...document.querySelectorAll('#pet-acts .chip')].find(c => c.dataset.act === name);
    say(`${INFO[id][0]}: ${lab ? lab.textContent : name}`);
    kick();
  };
  const chip = (label, cls) => { const b = document.createElement('button'); b.type = 'button'; b.className = cls || 'chip'; b.textContent = label; return b; };

  // pet picker: a radio group with live avatars
  const pick = $('#pet-pick'), radios = [];
  const selectPet = (pid, focus) => {
    id = pid; A = P.newAnim(); S.act = ''; S.act_id += 1; apply();
    radios.forEach(r => { const sel = r.dataset.pet === pid; r.setAttribute('aria-checked', String(sel)); r.tabIndex = sel ? 0 : -1; r.classList.toggle('on', sel); if (sel && focus) r.focus(); });
    const [name, blurb, tag] = INFO[pid];
    $('#pet-blurb').textContent = blurb; $('#pet-tag').textContent = tag;
    $('#stage-title').textContent = `playground · ${pid}`;
    stage.setAttribute('aria-label', `${name}. Press Enter to poke.`);
    $('#pet-more').textContent = `Every look of ${name}`;
    buildActs(); buildExtra();
    if (detailOpen) openDetail();
  };
  P.ORDER.forEach((pid, i) => {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'pick'; b.dataset.pet = pid; b.setAttribute('role', 'radio');
    const cv = document.createElement('canvas'); cv.setAttribute('aria-hidden', 'true');
    const nm = document.createElement('span'); nm.textContent = INFO[pid][0];
    b.append(cv, nm);
    pick.appendChild(b); radios.push(b);
    drawPose(fitCanvas(cv, 56, 44), 56, 44, pid, '');
    b.addEventListener('click', () => selectPet(pid, false));
    b.addEventListener('keydown', e => {
      const k = {ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1, ArrowUp: i - 1, Home: 0, End: radios.length - 1}[e.key];
      if (k === undefined) return;
      e.preventDefault(); selectPet(P.ORDER[(k + radios.length) % radios.length], true);
    });
  });

  const LABEL = {moonjoy: 'Full moon!', nap: 'Nap', eat: 'Snack', splash: 'Splash', startle: 'Startle', read: 'Read',
    stargaze: 'Stargaze', flare: 'Flare up', crackle: 'Crackle'};
  function buildActs() {                      // the shared actions + this pet's own (pets/<id>.js animExtra)
    const box = $('#pet-acts'); box.textContent = '';
    const extra = (P.PETS[id].animExtra || []).map(([dur, st]) =>
      [st.act, LABEL[st.act] || st.act[0].toUpperCase() + st.act.slice(1), st.act_dur || dur, st.weather, true]);
    const seen = new Set();
    [...ACTS, ...extra].forEach(([name, label, dur, weather, own]) => {
      if (seen.has(name)) return; seen.add(name);
      const b = chip(label, own ? 'chip own' : 'chip'); b.dataset.act = name;
      b.addEventListener('click', () => {
        if (weather && !on.has(weather)) $(`#pet-moods [data-key="${weather}"]`).click();   // e.g. Pip splashes in the rain
        act(name, dur);
      });
      box.appendChild(b);
    });
  }
  (() => {
    const box = $('#pet-moods');
    MOODS.forEach(([key, label, , group]) => {
      const b = chip(label); b.setAttribute('aria-pressed', 'false'); b.dataset.key = key;
      b.addEventListener('click', () => {
        const was = on.has(key);
        if (group) MOODS.forEach(([k2, , , g2]) => { if (g2 === group) on.delete(k2); });
        if (!was) on.add(key); else on.delete(key);
        box.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(on.has(x.dataset.key))));
        apply();
      });
      box.appendChild(b);
    });
  })();
  (() => {
    const box = $('#pet-wear');
    Object.entries(WEAR).forEach(([key, w]) => {
      const b = chip(w.label); b.setAttribute('aria-pressed', 'false'); b.dataset.wear = key;
      b.addEventListener('click', () => {
        wearing = wearing === key ? null : key;
        if (wearing && !wearImg[key]) { const im = new Image(); im.onload = kick; im.src = `art/site/sticker-${key}.png`; wearImg[key] = im; }
        box.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.wear === wearing)));
        say(wearing ? `${INFO[id][0]} put on the ${w.label.toLowerCase()}` : `${INFO[id][0]} took the hat off`);
        kick();
      });
      box.appendChild(b);
    });
  })();
  function buildExtra() {                     // a slider for the pets that read a live number
    const box = $('#pet-extra'); box.textContent = '';
    const spec = {ember: ['CPU load', 'cpu', '%'], nyx: ['Tonight’s moon', 'moon', '% lit']}[id];
    if (!spec) return;
    const [label, key, unit] = spec;
    const l = document.createElement('label'); l.className = 'slider';
    const s = document.createElement('input'); s.type = 'range'; s.min = 0; s.max = 100; s.value = S[key];
    const v = document.createElement('output'); v.textContent = `${S[key]} ${unit}`;
    s.addEventListener('input', () => { S[key] = +s.value; v.textContent = `${s.value} ${unit}`; kick(); });
    l.append(document.createTextNode(label), s, v);
    box.appendChild(l);
  }

  // poke: click the pet (or Enter / Space on the stage)
  stage.tabIndex = 0;
  const poke = () => { act(S.mood === 'sleep' ? 'startle' : 'squish', S.mood === 'sleep' ? 1.4 : 0.9); say(`${INFO[id][0]}: poked`); };
  stage.addEventListener('click', poke);
  stage.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); poke(); } });

  // every look of the pet: the showcase sheet in a panel under the stage
  const panel = $('#pet-detail'), more = $('#pet-more');
  let detailOpen = false;
  function openDetail() {
    detailOpen = true;
    const name = INFO[id][0];
    $('#pet-name').textContent = name;
    const sheet = $('#pet-sheet');
    sheet.parentElement.scrollTop = 0;
    swap(sheet, `art/glob/${id}/showcase.png`, `${name}'s showcase sheet: every mood, weather and action`);
    panel.inert = false; panel.classList.add('open'); more.setAttribute('aria-expanded', 'true');
  }
  const closeDetail = () => { detailOpen = false; panel.classList.remove('open'); panel.inert = true; more.setAttribute('aria-expanded', 'false'); more.focus(); };
  more.addEventListener('click', () => {
    if (detailOpen) return closeDetail();
    openDetail();
    const nm = $('#pet-name'), focusName = () => nm.focus({preventScroll: true});
    focusName(); if (document.activeElement !== nm) requestAnimationFrame(() => { focusName(); if (document.activeElement !== nm) setTimeout(focusName, 60); });
    if (panel.getBoundingClientRect().top > innerHeight - 200) panel.scrollIntoView({behavior: calm ? 'auto' : 'smooth', block: 'start'});
  });
  $('#pet-close').addEventListener('click', closeDetail);
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && detailOpen && panel.contains(document.activeElement)) closeDetail(); });

  // only animate while the stage is on screen and the tab is visible
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(es => es.forEach(en => { visible = en.isIntersecting; if (visible) kick(); })).observe(stage);
  }
  document.addEventListener('visibilitychange', kick);
  if ('ResizeObserver' in window) new ResizeObserver(resize).observe(wrap); else addEventListener('resize', resize);
  selectPet('mimi', false);
  resize();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(paint);
});

// A missing image should look like a quiet box, not a broken-image icon
document.querySelectorAll('main img').forEach(img => img.addEventListener('error', () => img.classList.add('img-failed')));
