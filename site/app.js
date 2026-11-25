// living-sky site: small switchers over the images in art/ (copied next to this page on deploy).
const $ = s => document.querySelector(s);

function group(sel, attr, onPick) {                 // a row of toggle buttons sharing one data-* attribute
  const btns = [...document.querySelectorAll(`${sel} [data-${attr}]`)];
  btns.forEach(b => b.addEventListener('click', () => {
    btns.forEach(x => x.classList.toggle('on', x === b));
    onPick(b.dataset[attr]);
  }));
}

// Looks: style x time
const look = {style: 'glass', time: 'night'};
const showLook = () => {
  $('#look-img').src = `art/demos/${look.style}-${look.time}.jpg`;
  $('#look-img').alt = `The ${look.style} style by ${look.time}`;
};
group('#looks .switch', 'style', v => { look.style = v; showLook(); });
group('#looks .switch', 'time', v => { look.time = v; showLook(); });

// Scenes
const SCENES = {
  lake: 'Mountains over a lake with reflections; snow on the lit faces of the peaks in winter.',
  forest: 'Rolling pine hills: valley mist at dawn and dusk, a cabin window that glows at night, gold larches in autumn.',
  city: 'A skyline whose windows light up in the evening and go dark through the night, a different set every hour.',
  camp: 'A tent in a forest clearing; the campfire burns from dusk to dawn, only embers by day; fireflies on summer nights.',
};
const showScene = s => {
  $('#scene-img').src = `art/demos/scene-${s}.jpg`;
  $('#scene-img').alt = `The ${s} scene at four times of day`;
  $('#hours-img').src = `art/demos/hours/${s}.jpg`;
  $('#scene-text').textContent = SCENES[s];
};
group('#scenes .switch', 'scene', showScene);
showScene('lake');

// Pets
const PETS = [
  ['mimi', 'Mimi', 'Cheerful, social lavender blob. Morning coffee, dances, waves.', 'asleep 00–06'],
  ['pip', 'Pip', 'A hyper sapphire droplet: hops a lot, splashes in the rain, startles easily.', 'scene pet: lake'],
  ['bun', 'Bun', 'A sleepy slice of bread: naps, snacks twice as often, grumpy when woken.', 'scene pet: forest'],
  ['nyx', 'Nyx', 'A little moon showing tonight’s real phase: awake at night, stargazes.', 'asleep by day'],
  ['cubo', 'Cubo', 'A studious teal cube with glasses: reads, coffee all day, sneezes at dust.', 'scene pet: city'],
  ['ember', 'Ember', 'A campfire wisp that burns with your CPU; a blue pilot light when cold.', 'scene pet: camp'],
];
const list = $('#pet-list');
PETS.forEach(([id, name, text, tag]) => {
  const b = document.createElement('button');
  b.className = 'pet';
  b.innerHTML = `<img src="art/glob/${id}/${id}.gif" alt="${name}, animated" loading="lazy"><b>${name}</b><span>${text}</span><span class="tag">${tag}</span>`;
  b.addEventListener('click', () => {
    document.querySelectorAll('.pet').forEach(x => x.classList.toggle('on', x === b));
    $('#pet-name').textContent = `Every look of ${name}`;
    $('#pet-sheet').src = `art/glob/${id}/showcase.png`;
    $('#pet-sheet').alt = `${name}'s showcase sheet: every mood, weather and action`;
    $('#pet-detail').hidden = false;
    $('#pet-detail').scrollIntoView({behavior: 'smooth', block: 'nearest'});
  });
  list.appendChild(b);
});
$('#pet-close').addEventListener('click', () => {
  $('#pet-detail').hidden = true;
  document.querySelectorAll('.pet').forEach(x => x.classList.remove('on'));
});

// Cards
const CARDS = ['clock', 'weather', 'calendar', 'media', 'cpu', 'memory', 'disks', 'gpu', 'battery', 'network'];
const tabs = $('#card-tabs');
CARDS.forEach((c, i) => {
  const b = document.createElement('button');
  b.textContent = {cpu: 'CPU', gpu: 'GPU', media: 'Now playing'}[c] || c[0].toUpperCase() + c.slice(1);
  b.dataset.card = c;
  if (i === 0) b.className = 'on';
  tabs.appendChild(b);
});
const showCard = c => { $('#card-img').src = `art/demos/cards/${c}.jpg`; $('#card-img').alt = `The ${c} card in both styles, night and day`; };
group('#card-tabs', 'card', showCard);
showCard('clock');
