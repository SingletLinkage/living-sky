// living-sky site: small switchers over the images in art/ (copied next to this page on deploy).
// Everything here is progressive enhancement: the page reads fine without it.
const $ = s => document.querySelector(s);
const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
const safe = (name, fn) => { try { fn(); } catch (e) { console.error(`living-sky site: ${name}`, e); } };

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
  fig.appendChild(btn);
  let loaded = false;
  const show = playing => {
    const v = playing ? gif : poster;
    img.src = v.src; img.alt = v.alt; cap.textContent = v.cap;
    btn.textContent = playing ? 'Pause animation' : 'Play animation';
    btn.setAttribute('aria-pressed', String(playing));
  };
  const play = () => {
    if (loaded) return show(true);
    const pre = new Image();
    pre.onload = () => { loaded = true; if (btn.getAttribute('aria-pressed') === 'true') show(true); };
    pre.src = gif.src;
  };
  btn.addEventListener('click', () => {
    if (btn.getAttribute('aria-pressed') === 'true') show(false);
    else { btn.setAttribute('aria-pressed', 'true'); btn.textContent = 'Pause animation'; play(); }
  });
  show(false);
  if (!calm) {
    const start = () => { btn.setAttribute('aria-pressed', 'true'); btn.textContent = 'Pause animation'; play(); };
    if (document.readyState === 'complete') setTimeout(start, 200); else addEventListener('load', () => setTimeout(start, 200));
  }
});

// Looks: style x time
safe('looks', () => {
  const look = {style: 'glass', time: 'night'};
  const show = () => swap($('#look-img'), `art/demos/${look.style}-${look.time}.jpg`, `The ${look.style} style by ${look.time}`);
  toggles('#looks .switch', 'style', v => { look.style = v; show(); });
  toggles('#looks .switch', 'time', v => { look.time = v; show(); });
  // fetch the other variants once the page is idle, so switching never flashes
  const warm = () => ['glass-day', 'cards-night', 'cards-day'].forEach(n => { new Image().src = `art/demos/${n}.jpg`; });
  if (!(navigator.connection && navigator.connection.saveData)) addEventListener('load', () => (window.requestIdleCallback || setTimeout)(warm));
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
  const applyHours = () => { if (hours.getAttribute('src') !== `art/demos/hours/${scene}.jpg`) hours.src = `art/demos/hours/${scene}.jpg`; hours.alt = `The ${scene} scene for every hour of a day`; };
  details.addEventListener('toggle', () => { if (details.open) applyHours(); });   // only fetch the big sheet when it is open
  const showScene = s => {
    scene = s;
    swap($('#scene-img'), `art/demos/scene-${s}.jpg`, `The ${s} scene at four times of day`);
    if (details.open) applyHours();
    $('#scene-text').textContent = SCENES[s];
  };
  tablist($('#scenes .switch'), $('#scene-panel'), 'scene', showScene);
});

// Pets
safe('pets', () => {
  const PETS = [
    ['mimi', 'Mimi', 'Cheerful, social lavender blob. Morning coffee, dances, waves.', 'asleep 00–06'],
    ['pip', 'Pip', 'A hyper sapphire droplet: hops a lot, splashes in the rain, startles easily.', 'scene pet: lake'],
    ['bun', 'Bun', 'A sleepy slice of bread: naps, snacks twice as often, grumpy when woken.', 'scene pet: forest'],
    ['nyx', 'Nyx', 'A little moon showing tonight’s real phase: awake at night, stargazes.', 'asleep by day'],
    ['cubo', 'Cubo', 'A studious teal cube with glasses: reads, coffee all day, sneezes at dust.', 'scene pet: city'],
    ['ember', 'Ember', 'A campfire wisp that burns with your CPU; a blue pilot light when cold.', 'scene pet: camp'],
  ];
  const list = $('#pet-list'), panel = $('#pet-detail'), close = $('#pet-close');
  const buttons = [];
  let current = null;
  const closePanel = restoreFocus => {
    const prev = current;
    current = null;
    panel.classList.remove('open'); panel.inert = true;
    buttons.forEach(x => { x.classList.remove('on'); x.setAttribute('aria-expanded', 'false'); });
    if (restoreFocus && prev) prev.focus();
  };
  PETS.forEach(([id, name, text, tag]) => {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'pet';
    b.setAttribute('aria-expanded', 'false'); b.setAttribute('aria-controls', 'pet-detail');
    const img = new Image(240, 200);
    img.src = `art/glob/${id}/${id}.gif`; img.alt = ''; img.loading = 'lazy'; img.decoding = 'async';
    const n = document.createElement('b'); n.textContent = name;
    const t = document.createElement('span'); t.textContent = text;
    const g = document.createElement('span'); g.className = 'tag'; g.textContent = tag;
    b.append(img, n, t, g);
    b.addEventListener('click', () => {
      if (current === b) return closePanel(false);
      current = b;
      buttons.forEach(x => { x.classList.toggle('on', x === b); x.setAttribute('aria-expanded', String(x === b)); });
      $('#pet-name').textContent = `Every look of ${name}`;
      $('#pet-text').textContent = text;
      $('#pet-tag').textContent = tag;
      close.setAttribute('aria-label', `Close ${name} details`);
      const sheet = $('#pet-sheet');
      sheet.src = `art/glob/${id}/showcase.png`;
      sheet.alt = `${name}'s showcase sheet: every mood, weather and action`;
      panel.inert = false; panel.classList.add('open');
      $('#pet-name').focus({preventScroll: true});
      if (panel.getBoundingClientRect().top > innerHeight - 200) panel.scrollIntoView({behavior: calm ? 'auto' : 'smooth', block: 'start'});
    });
    buttons.push(b);
    list.appendChild(b);
  });
  close.addEventListener('click', () => closePanel(true));
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && current && panel.contains(document.activeElement)) closePanel(true); });
});

// Cards
const CARDS = ['clock', 'weather', 'calendar', 'media', 'cpu', 'memory', 'disks', 'gpu', 'battery', 'network'];
safe('cards', () => {
  const HEIGHT = {battery: 184, calendar: 234, clock: 206, cpu: 192, disks: 152, gpu: 162, media: 162, memory: 196, network: 162, weather: 190};
  const tabs = $('#card-tabs'), img = $('#card-img');
  CARDS.forEach((c, i) => {
    const b = document.createElement('button');
    b.type = 'button'; b.id = `tab-card-${c}`;
    b.textContent = {cpu: 'CPU', gpu: 'GPU', media: 'Now playing'}[c] || c[0].toUpperCase() + c.slice(1);
    b.dataset.card = c;
    if (i === 0) b.className = 'on';
    tabs.appendChild(b);
  });
  tablist(tabs, $('#card-panel'), 'card', c => {
    img.height = HEIGHT[c];
    swap(img, `art/demos/cards/${c}.jpg`, `The ${c} card in both styles, night and day`);
  });
});

// A missing image should look like a quiet box, not a broken-image icon
document.querySelectorAll('main img').forEach(img => img.addEventListener('error', () => img.classList.add('img-failed')));
