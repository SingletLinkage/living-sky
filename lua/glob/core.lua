--[[
  glob core: everything glob pets share. A pet file (lua/glob/<pet>.lua) is just
      return dofile(<this dir> .. 'core.lua'){ id = 'pip', ... personality and looks ... }
  and gets: perches on the cards and wandering between them (sink into a card, pop out at another),
  moods by its own sleep schedule, weather gear (umbrella, scarf, haze), sunglasses, AQI masks,
  presence (naps when you're away, startles when you're back), typing along on a tiny laptop,
  Files -> magnifier search, media (dance with headphones / watch with popcorn), "this is fine" when
  the CPU is hot, panel clicks (poke, double-click heart / wake), grumpiness (woken / ignored),
  snacks, the hourly chime, and the export for the GNOME panel extension.
  The pet definition (PET) tunes all of that; see DEFAULTS below for every field. Mimi is the
  defaults (lua/glob/mimi.lua is nothing but her name).

  Moods (highest priority first): video -> watch, music -> music, grumpy (woken), then the pet's
  schedule(h, sunrise, sunset) -> sleep | wake | drowsy | awake.
  Weather overlays: umbrella + drops (rain/storm; PET.rain_gear = false: drops only), scarf + snow,
  scarf + shiver (<= 5 °C), haze (fog). Sunglasses: strong sun, or PET.shades(st, ctx, default, sun_alt).
  Masks by US AQI: 101-150 surgical, 151-200 N95, > 200 respirator; sneezes above PET.sneeze_aqi.
  Grumpy: woken (double-click while asleep: up for PET.woken_s, the last 2 min sleepy again) or
  ignored (no click for PET.neglect_s of you-at-the-PC time; counter in ~/.cache/living-sky/glob_state).
  Commands arrive in ~/.cache/living-sky/glob_cmd as "<id> <verb>" (poke|heart).

  Testing: ~/.cache/living-sky/glob_force, comma-separated tokens, e.g.
    music | sleep | wake | drowsy | awake      (mood)
    rain | storm | snow | fog | cold | hot | clear   (weather)
    sunny | aqi1 | aqi2 | aqi3                       (sunglasses / mask tiers)
    hop | wobble | sway | curious | heart | look | sneeze | typing | chime | startle | doze   (actions)
    squish | eat | wave | coffee | sideeye | dance | search | huff | watch | fire | term | code
    plus each pet's own acts (PET.acts), e.g. splash | nap | stargaze | moonjoy | read
    grumpy | ignored | nomedia | night (clock says 03:00) | day (13:00) | files (Files focused)
    hungry (snack due) | grumpytest (20 s)
    home | topleft | peek_<card id> (peek_weather, peek_cpu, ...) | under  (perch)
    sink | rise                                       (travel: mid-sink at the perch / mid-pop-out)
]]

return function(PET)
local DEFAULTS = {
  id = 'mimi', name = 'Mimi',
  size = {20, 16},             -- half width, half height of the body (px)
  color = nil,                 -- body colour: nil = the primary accent; a palette name ('teal');
                               -- or function(M, light, mix) -> colour
  body = nil,                  -- function(cr, cx, cy, a, b): the body outline path (default: a soft dome)
  breath = 3.5,                -- s per breath
  blink_every = {2.5, 6},      -- s between blinks
  act_every = {15, 40},        -- s between idle actions
  wander_every = {360, 900},   -- s between trips to another perch
  snack_every = {1200, 1800},  -- s between snacks
  snack_heart = 0.4,           -- chance of a heart after a snack
  woken_s = 600, neglect_s = 2 * 3600,
  pool = {hop = 2, wobble = 1, sway = 1, curious = 1, heart = 1, look = 1, wave = 1, sideeye = 1, dance = 1, coffee = 1},
  morning_coffee = true,       -- extra coffee 06-11 h
  sneeze_aqi = 100,
  poke = {hop = 1, squish = 1},  -- what a single click plays
  rain_gear = true,            -- umbrella in the rain
  acts = {},                   -- the pet's own actions: name -> duration (s)
  -- schedule(h, sunrise_h, sunset_h) -> 'sleep' | 'wake' | 'drowsy' | 'awake'
  schedule = function(h, sr)
    if h < 6 then return 'sleep' end
    if h < math.max(6.75, sr + 0.5) then return 'wake' end
    if h >= 22 then return 'drowsy' end
    return 'awake'
  end,
  extra_pool = nil,            -- function(pool, st, ctx): add situational actions to the idle pool
  shades = nil,                -- function(st, ctx, default, sun_alt) -> bool
  pose = nil,                  -- function(an, ap, t, P): squash/stretch for the pet's own acts (P.sx/sy/oy/rot)
  eyes = nil,                  -- function(eyes, an, ap, mood, st) -> eye state ('open', 'happy', 'closed', 'half', 'wide', 'side')
  draw_under = nil,            -- function(E): behind the body (e.g. a glow)
  draw_body = nil,             -- function(E): markings on the body, under the face (clipped to the body)
  draw_over = nil,             -- function(E): over the face (e.g. glasses)
  draw_act = nil,              -- function(E, an, ap): extras for the pet's own acts
}
for k, v in pairs(DEFAULTS) do if PET[k] == nil then PET[k] = v end end
local function rnd(r) return r[1] + math.random() * (r[2] - r[1]) end
local function pick(weights)                -- weighted choice from {name = weight}
  local keys, total = {}, 0
  for k, w in pairs(weights) do keys[#keys + 1] = k; total = total + w end
  table.sort(keys)
  local x = math.random() * total
  for _, k in ipairs(keys) do x = x - weights[k]; if x <= 0 then return k end end
  return keys[#keys]
end

local B = {}
math.randomseed(os.time())

local cr, M
local A0, B0 = PET.size[1], PET.size[2]   -- half width / half height of the body
local SINK_T, RISE_T = 1.25, 1.25   -- s to sink into / pop out of a card
local EYE = {0.12, 0.12, 0.17}

local st = {
  perch = 'home', trip = nil, hidden = false, pop_t0 = -10, pos = nil,
  next_move = nil, blink_at = 0, blink_until = -1, next_glance = 0, glance_until = -1, gaze = {0, 0},
  yawn_until = -1, next_yawn = 0, flash_until = -1,
  act = nil, next_act = 0, dozing = false, chimed = nil, mask = 0, shades = false,
  hot = false, wake_until = nil, grumpy_until = nil, grumpy = nil, cmd_id = nil, pending = nil, type_kind = 'laptop',
  neglect = nil, ignored = false, neglect_saved = 0, last_t = nil, next_food = nil, next_search = 0,
}
local WOKEN_S, SLEEPY_S = PET.woken_s, 120   -- grumpy after a forced wake; the last 2 min it gets sleepy
local NEGLECT_S = PET.neglect_s            -- s of you-at-the-PC time without a click before it sulks
local ACTS = {hop = 1.0, wobble = 1.6, sway = 2.0, curious = 2.6, heart = 2.4, look = 2.0, sneeze = 1.4,
              typing = 9.0, chime = 3.2, startle = 1.4,
              squish = 0.9, eat = 3.2, wave = 2.0, coffee = 3.0, sideeye = 2.0, dance = 2.5, search = 3.0, huff = 1.4}
for k, v in pairs(PET.acts) do ACTS[k] = v end

------------------------------------------------------------------ helpers
local function rgba(c, a) cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4] or 1) end
local function mix(c, d, k) return {c[1] + (d[1] - c[1]) * k, c[2] + (d[2] - c[2]) * k, c[3] + (d[3] - c[3]) * k, 1} end
local WHITE, BLACK = {1, 1, 1, 1}, {0, 0, 0, 1}
local function ellipse(x, y, rx, ry)
  cairo_save(cr); cairo_translate(cr, x, y); cairo_scale(cr, rx, ry)
  cairo_new_sub_path(cr); cairo_arc(cr, 0, 0, 1, 0, 2 * math.pi); cairo_restore(cr)
end
local function rrect(x, y, w, h, r)
  cairo_new_sub_path(cr)
  cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
  cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
  cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
  cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
  cairo_close_path(cr)
end
-- default shape: rounder dome on top, flatter bottom
local function dome_path(cx, cy, a, b)
  cairo_new_path(cr)
  for i = 0, 47 do
    local th = 2 * math.pi * i / 48
    local c, s = math.cos(th), math.sin(th)
    local n = s > 0 and 4.2 or 2.3
    local x = cx + a * (c >= 0 and 1 or -1) * math.abs(c) ^ (2 / n)
    local y = cy + b * (s >= 0 and 1 or -1) * math.abs(s) ^ (2 / n)
    if i == 0 then cairo_move_to(cr, x, y) else cairo_line_to(cr, x, y) end
  end
  cairo_close_path(cr)
end
local function body_path(cx, cy, a, b)
  if PET.body then PET.body(cr, cx, cy, a, b) else dome_path(cx, cy, a, b) end
end
local function body_colour(light)
  local c = PET.color
  if type(c) == 'function' then return c(M, light, mix) end
  local acc = (type(c) == 'string' and M[c]) or M.accent or M.blue
  return light and mix(acc, WHITE, 0.45) or acc
end
local function hm(s)
  local h, m = (s or ''):match('(%d+):(%d+)')
  return h and (tonumber(h) + tonumber(m) / 60) or nil
end

------------------------------------------------------------------ perches / path
local function perches(cards, col_x)
  local P, c1 = {}, cards[1]
  if not c1 then return P end
  local min_x = c1.x
  for _, c in ipairs(cards) do min_x = math.min(min_x, c.x) end
  P.home = {x = c1.x + c1.w - 50, y = c1.y + 2, kind = 'sit'}
  P.topleft = {x = c1.x + 56, y = c1.y + 2, kind = 'sit'}
  for i = 2, #cards do
    local c = cards[i]
    if c.x <= min_x + 10 then                         -- only from the leftmost column (else it pokes into the next)
      P['peek_' .. c.id] = {x = c.x - 7, y = c.y + c.h * 0.5 + 16, kind = 'peekL'}
    end
  end
  local last = cards[#cards]
  P.under = {x = last.x + 64, y = last.y + last.h + 22, kind = 'peekD'}
  return P
end
-- direction + distance that hides the blob inside the card it sits on / peeks from
local function sink_vec(p)
  if p.kind == 'sit' then return 0, 1, 2 * B0 + 6          -- down through the top edge
  elseif p.kind == 'peekL' then return 1, 0, A0 + 14       -- sideways behind the left edge
  else return 0, -1, 2 * B0 - 4 end                         -- up behind the bottom edge
end
local function back_out(k)                                  -- ease-out with a little overshoot
  local c1 = 1.3; local c3 = c1 + 1
  return 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end

------------------------------------------------------------------ state update
local function mood_of(ctx, force)
  for _, k in ipairs({'music', 'watch', 'sleep', 'wake', 'drowsy', 'grumpy', 'awake'}) do if force[k] then return k end end
  if ctx.media == 'video' and not force.nomedia then return 'watch' end
  if ctx.music and not force.nomedia then return 'music' end
  if st.grumpy_until and ctx.t < st.grumpy_until then return 'grumpy' end
  local c = ctx.clock
  local h = force.night and 3 or (force.day and 13 or (c.hour + c.min / 60))
  local sr = hm(ctx.sky and ctx.sky.sunrise) or 6.5
  local ss = hm(ctx.sky and ctx.sky.sunset) or 18
  local m = PET.schedule(h, sr, ss)
  if m == 'sleep' and st.wake_until and ctx.t < st.wake_until then m = 'awake' end   -- woken up
  return m
end
local function weather_of(ctx, force)
  for _, k in ipairs({'rain', 'storm', 'snow', 'fog', 'cold', 'hot', 'clear'}) do if force[k] then return k end end
  local w = ctx.wx
  if not w then return 'clear' end
  local k = w.kind
  if k == 'rain' or k == 'pour' then return 'rain' end
  if k == 'storm' then return 'storm' end
  if k == 'snow' or k == 'sleet' then return 'snow' end
  if k == 'fog' then return 'fog' end
  if (w.temp or 15) <= 5 then return 'cold' end
  if (w.temp or 15) >= 30 and (k == 'clear' or k == 'partly') then return 'hot' end
  return 'clear'
end

function B.update(ctx)
  local t = ctx.t
  local force = {}
  for tok in (ctx.force or ''):gmatch('[%w_]+') do force[tok] = true end
  local P = perches(ctx.cards or {}, ctx.col_x)
  if not P.home then st.ok = false; return end
  st.ok = true
  local mx = ctx.col_x - 30
  -- commands from the panel extension (one per new id; the first one seen is just remembered)
  local cmd = ctx.cmd
  if cmd and cmd.id then
    if st.cmd_id == nil then st.cmd_id = cmd.id
    elseif cmd.id ~= st.cmd_id then
      st.cmd_id = cmd.id
      local v = cmd.verb
      if v == 'poke' or v == 'heart' then
        st.touched = true                                   -- any click resets the neglect counter
        if v == 'heart' and mood_of(ctx, force) == 'sleep' then
          -- double-click while asleep: up for 10 min, and not happy about it
          local d = force.grumpytest and 20 or WOKEN_S
          st.wake_until, st.grumpy_until, st.pending = t + d, t + d, 'startle'
        elseif st.ignored then st.pending = 'forgive'       -- huff, then a grudging heart
        else st.pending = v end
      end
    end
  end
  st.mood = mood_of(ctx, force)
  st.weather = weather_of(ctx, force)
  local files = force.files or ctx.app == 'files'

  -- neglect: s of you-at-the-PC time (it awake) since the last click; persisted across restarts
  local dt = st.last_t and math.max(0, math.min(5, t - st.last_t)) or 0
  st.last_t = t
  if not st.neglect then
    st.neglect = 0
    local f = ctx.state_path and io.open(ctx.state_path)
    if f then st.neglect = tonumber((f:read('*a') or ''):match('neglect%s+(%d+)')) or 0; f:close() end
    st.neglect_saved = t
  end
  local save
  if st.touched then st.touched, st.neglect, save = nil, 0, true
  elseif not ctx.away and st.mood ~= 'sleep' and not st.dozing then st.neglect = st.neglect + dt end
  if t - st.neglect_saved >= 300 then save = true end
  if save and ctx.state_path then
    st.neglect_saved = t
    local f = io.open(ctx.state_path .. '.tmp', 'w')
    if f then f:write(string.format('neglect %d\n', math.floor(st.neglect))); f:close(); os.rename(ctx.state_path .. '.tmp', ctx.state_path) end
  end
  st.ignored = force.ignored or st.neglect >= NEGLECT_S
  if st.mood == 'grumpy' then
    st.grumpy = (st.grumpy_until and st.grumpy_until - t < SLEEPY_S) and 'sleepy' or 'woken'
  elseif st.ignored and (st.mood == 'awake' or st.mood == 'drowsy') then st.grumpy = 'ignored'
  else st.grumpy = nil end
  -- "this is fine": CPU package temperature with hysteresis
  st.cpu_load = ctx.cpu_load or 0
  local temp = ctx.cpu_temp or 0
  if force.fire or temp >= 90 then st.hot = true elseif temp < 85 then st.hot = false end
  st.app = ctx.app or 'other'
  if force.term then st.type_kind = 'term' elseif force.code then st.type_kind = 'code'
  else st.type_kind = ctx.app == 'terminal' and 'term' or (ctx.app == 'code' and 'code' or 'laptop') end

  -- forced perch (testing): teleport
  local fp
  for name in pairs(force) do if P[name] then fp = name end end
  if fp then st.perch, st.trip = fp, nil end
  if force.sink then st.perch = nil; st.trip = {from = fp or 'home', to = fp or 'home', phase = 'sink', t0 = t - SINK_T * 0.5, wait = 1e9} end
  if force.rise then st.perch = nil; st.trip = {from = fp or 'home', to = fp or 'home', phase = 'rise', t0 = t - RISE_T * 0.45, wait = 0} end

  if not fp and not force.sink and not force.rise then
    if not st.next_move then st.next_move = t + rnd(PET.wander_every) end
    if st.perch and not P[st.perch] then st.perch = 'home' end
    -- go home to sleep; otherwise wander every now and then (only when nothing else is going on)
    local want, quick
    if st.mood == 'sleep' and st.perch ~= 'home' and not st.trip then want = 'home'
    elseif (ctx.typing or st.pending or (files and st.mood ~= 'sleep')) and not st.trip and st.perch
        and P[st.perch].kind ~= 'sit' and not st.dozing then
      want, quick = 'home', true                 -- typing / clicked / Files: hurry to the clock card
    elseif not st.trip and (st.mood == 'awake' or st.mood == 'drowsy') and t >= st.next_move
        and not st.act and not ctx.typing and not st.dozing and not st.pending and not files then
      local names = {}
      for n in pairs(P) do if n ~= st.perch then names[#names + 1] = n end end
      table.sort(names)
      want = names[math.random(#names)]
    end
    if want then
      st.trip = {from = st.perch or 'home', to = want, phase = 'sink', t0 = t,
                 wait = quick and 0.3 or (1.5 + math.random() * 2.5), dur = quick and 0.75 or nil}
      st.perch = nil
      st.act = nil                               -- nothing else while travelling
    end
  end

  -- position: sink into the card -> hidden -> pop out at the destination
  st.hidden = false
  if st.trip then
    local tr = st.trip
    if tr.phase == 'sink' then
      local k = (t - tr.t0) / (tr.dur or SINK_T)
      if k >= 1 then tr.phase, tr.t0 = 'hidden', t
      else
        local p = P[tr.from] or P.home
        local dx, dy, d = sink_vec(p)
        local e = k * k                                     -- ease in
        st.pos = {p.x + dx * d * e, p.y + dy * d * e, p.kind, {dx, dy}, 'behind', 'sink', k}
      end
    end
    if tr.phase == 'hidden' then
      st.hidden = true
      if t - tr.t0 >= tr.wait then tr.phase, tr.t0 = 'rise', t end
    end
    if tr.phase == 'rise' then
      local k = (t - tr.t0) / (tr.dur or RISE_T)
      if k >= 1 then
        st.trip, st.perch, st.pop_t0 = nil, tr.to, t
        st.next_move = t + rnd(PET.wander_every)
      else
        st.hidden = false
        local p = P[tr.to] or P.home
        local dx, dy, d = sink_vec(p)
        local e = 1 - back_out(k)                           -- 1 -> slightly past 0 -> 0
        st.pos = {p.x + dx * d * e, p.y + dy * d * e, p.kind, {-dx, -dy}, 'behind', 'rise', k}
      end
    end
  end
  if st.perch then
    local p = P[st.perch]
    st.pos = {p.x, p.y, p.kind, {0, 0}, p.kind == 'sit' and 'front' or 'behind'}
  end
  if not st.pos then st.hidden = true end
  st.layer = st.pos and st.pos[5] or 'front'

  -- idle timers (first call: schedule everything a little into the future)
  if not st.started then
    st.started = true
    st.blink_at, st.next_glance, st.next_act, st.next_yawn = t + 2, t + 5, t + 10, t + 20
  end
  if t >= st.blink_at then
    st.blink_until = t + 0.2
    st.blink_at = t + (st.mood == 'drowsy' and 1.5 or 0) + rnd(PET.blink_every)
  end
  if t >= st.next_glance then
    local opts = {{-1, 0}, {1, 0}, {-0.7, -0.6}, {0, 0.6}}
    st.gaze = opts[math.random(#opts)]
    st.glance_until = t + 1 + math.random()
    st.next_glance = t + 8 + math.random() * 7
  end
  -- accessories
  local w = ctx.wx or {}
  local aqi = w.aqi or -1
  if force.aqi1 then aqi = 120 elseif force.aqi2 then aqi = 170 elseif force.aqi3 then aqi = 250 end
  st.mask = aqi > 200 and 3 or aqi > 150 and 2 or aqi > 100 and 1 or 0
  st.aqi = aqi
  local sun = ctx.sky and ctx.sky.sun_alt or -90
  st.shades = force.sunny or st.weather == 'hot'
    or ((w.uvnow or 0) >= 3 and (w.kind == 'clear' or w.kind == 'partly') and sun > 15 and st.weather == 'clear')
  if PET.shades then st.shades = PET.shades(st, ctx, st.shades, sun) and true or false end

  -- presence: nap when you're away, startle when you're back
  local can_doze = (st.mood == 'awake' or st.mood == 'drowsy')
  if force.doze then st.dozing = true
  elseif not can_doze then st.dozing = false
  elseif ctx.away and not st.trip then st.dozing = true
  elseif st.dozing and not ctx.away then
    st.dozing = false
    if not st.trip then st.act = {name = 'startle', t0 = t, dur = ACTS.startle} end
  end

  -- actions
  if st.act and t > st.act.t0 + st.act.dur then
    local nxt = st.act.after
    st.act = nil
    if nxt and not st.trip then st.act = {name = nxt, t0 = t, dur = ACTS[nxt], user = true} end
  end
  if st.trip then st.act = nil end
  local sitting = st.perch and P[st.perch] and P[st.perch].kind == 'sit'
  -- clicks / menu from the panel (played once settled on a perch)
  if st.pending and st.perch and not st.trip then
    local v = st.pending
    st.pending = nil
    if st.mood == 'sleep' and (v == 'poke' or v == 'heart') then
      st.act = {name = 'wobble', t0 = t, dur = ACTS.wobble, user = true}       -- sleepy wiggle, stays asleep
    elseif st.mood == 'grumpy' and (v == 'poke' or v == 'heart') then
      st.act = {name = 'huff', t0 = t, dur = ACTS.huff, user = true}           -- hmph
    elseif v == 'forgive' then
      st.act = {name = 'huff', t0 = t, dur = ACTS.huff, user = true, after = 'heart'}
    elseif v == 'poke' then
      local n = pick(PET.poke)
      st.act = {name = n, t0 = t, dur = ACTS[n], user = true}
    else
      st.act = {name = v, t0 = t, dur = ACTS[v] or 1.5, user = true}
    end
    st.next_act = math.max(st.next_act or 0, t + 10)
  end
  -- typing mirrors your keyboard (held while keys are coming in)
  local can_type = sitting and not st.dozing and st.mood ~= 'sleep'
  if ctx.typing and can_type and not (st.act and st.act.user) then
    if not (st.act and st.act.name == 'typing') then st.act = {name = 'typing', t0 = t, dur = 3600} end
  elseif st.act and st.act.name == 'typing' and not force.typing then
    st.act = nil
    st.next_act = math.max(st.next_act or 0, t + 8)   -- breather before any random action
  end
  local c = ctx.clock
  if c.min == 0 and c.sec < 8 and st.chimed ~= c.hour and can_doze and not st.dozing and st.perch
      and not (st.act and st.act.name == 'typing') then
    st.chimed = c.hour
    st.act = {name = 'chime', t0 = t, dur = ACTS.chime}
  end
  local free = not st.act and not st.dozing and sitting and not ctx.typing
  -- Files focused: search right away, then every few seconds while it stays focused
  if not files then st.next_search = 0
  elseif free and (st.mood == 'awake' or st.mood == 'drowsy' or st.mood == 'grumpy') and t >= st.next_search then
    st.act = {name = 'search', t0 = t, dur = ACTS.search}
    st.next_search = t + ACTS.search + 4 + math.random() * 3
    free = false
  end
  -- snack every 20-30 min (waits while it's asleep / grumpy / busy)
  if not st.next_food then st.next_food = t + rnd(PET.snack_every) end
  if force.hungry then st.next_food = math.min(st.next_food, t) end
  if free and t >= st.next_food and (st.mood == 'awake' or st.mood == 'drowsy')
      and (st.grumpy == nil or st.grumpy == 'ignored') then
    st.act = {name = 'eat', t0 = t, dur = ACTS.eat, after = (not st.grumpy and math.random() < PET.snack_heart) and 'heart' or nil}
    st.next_food = t + rnd(PET.snack_every)
    st.next_act = math.max(st.next_act, t + 10)
    free = false
  end
  if free and t >= st.next_act and (st.mood == 'awake' or st.mood == 'grumpy') then
    local pool
    if st.grumpy then
      pool = {'sideeye', 'sideeye', 'huff', 'look'}                                 -- sulking
    else
      pool = {}
      local keys = {}
      for k in pairs(PET.pool) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do for _ = 1, PET.pool[k] do pool[#pool + 1] = k end end
      if (st.aqi or -1) > PET.sneeze_aqi then pool[#pool + 1] = 'sneeze' end
      if PET.morning_coffee and c.hour >= 6 and c.hour < 11 then pool[#pool + 1] = 'coffee'; pool[#pool + 1] = 'coffee' end
      if st.hot then pool[#pool + 1] = 'coffee' end
      if PET.extra_pool then PET.extra_pool(pool, st, ctx) end
    end
    local n = pool[math.random(#pool)]
    st.act = {name = n, t0 = t, dur = ACTS[n]}
    st.next_act = t + (st.grumpy and (8 + math.random() * 7) or rnd(PET.act_every))
  end
  for n, d in pairs(ACTS) do                    -- testing: hold an action mid-way
    if force[n] then st.act = {name = n, t0 = t - d * 0.6, dur = d} end
  end
  if st.mood == 'drowsy' and t >= st.next_yawn then
    st.yawn_until = t + 1.6
    st.next_yawn = t + 25 + math.random() * 30
  end
  if st.weather == 'storm' and math.random() < 0.02 then st.flash_until = t + 0.15 end
end

------------------------------------------------------------------ props
local function teardrop(x, y, w, h)          -- flame: tip at (x, y - h), base at (x, y)
  cairo_new_path(cr); cairo_move_to(cr, x, y - h)
  cairo_curve_to(cr, x + w, y - h * 0.45, x + w * 0.85, y, x, y)
  cairo_curve_to(cr, x - w * 0.85, y, x - w, y - h * 0.45, x, y - h); cairo_close_path(cr)
end
local function flames(cx, by, a, t)
  for i, k in ipairs({-1.08, -0.62, 0.62, 1.08}) do
    local h = (k * k > 1 and 11 or 7) * (0.8 + 0.25 * math.sin(t * 9 + i * 1.7))
    local x = cx + k * a
    teardrop(x, by + 1, 4.2, h); rgba({0.98, 0.5, 0.15}, 0.9); cairo_fill(cr)
    teardrop(x, by + 1, 2.2, h * 0.55); rgba({1, 0.85, 0.3}, 0.95); cairo_fill(cr)
  end
end
local function mug(x, y, t, steam)          -- x,y = bottom centre
  rrect(x - 4.5, y - 9, 9, 9, 1.8); rgba({0.96, 0.93, 0.87}); cairo_fill_preserve(cr)
  rgba({0.55, 0.5, 0.45}); cairo_set_line_width(cr, 0.8); cairo_stroke(cr)
  cairo_rectangle(cr, x - 4.5, y - 6.5, 9, 2); rgba(M.peach or {0.98, 0.7, 0.5}); cairo_fill(cr)
  cairo_new_path(cr); cairo_arc(cr, x + 4.6, y - 4.6, 2.4, -math.pi / 2, math.pi / 2)
  rgba({0.55, 0.5, 0.45}); cairo_set_line_width(cr, 1.1); cairo_stroke(cr)
  if steam then
    for k = 0, 1 do
      local p = (t * 0.6 + k * 0.5) % 1
      local sx0 = x - 1.5 + k * 3
      cairo_move_to(cr, sx0, y - 10 - p * 8)
      cairo_curve_to(cr, sx0 + 2, y - 12 - p * 8, sx0 - 2, y - 14 - p * 8, sx0, y - 16 - p * 8)
      rgba(WHITE, 0.55 * math.sin(p * math.pi)); cairo_set_line_width(cr, 0.9); cairo_stroke(cr)
    end
  end
end

------------------------------------------------------------------ drawing
local function draw(ctx)
  cr, M = ctx.cr, ctx.M
  local t = ctx.t
  local bx, by, kind, dir, phase, pk = st.pos[1], st.pos[2], st.pos[3], st.pos[4], st.pos[6], st.pos[7] or 0
  local mood, wx = st.mood, st.weather
  local light = ctx.sky and ctx.sky.flavour == 'latte'

  -- pose: squash / stretch + vertical offset
  local sx, sy, oy, rot = 1, 1, 0, 0
  local br = math.sin(2 * math.pi * t / (mood == 'sleep' and 5 or PET.breath))
  sy, sx = 1 + 0.03 * br, 1 - 0.015 * br
  if mood == 'sleep' then sy, sx = sy * 0.84, sx * 1.08
  elseif mood == 'wake' then local s = math.max(0, math.sin(2 * math.pi * t / 4)); sy, sx = sy * (1 + 0.13 * s), sx * (1 - 0.06 * s)
  elseif mood == 'music' then                 -- dance on a 1 s beat: bounce + alternating lean
    local s = math.abs(math.sin(math.pi * t)); oy = -3 * s; sy = sy * (1 - 0.06 * (1 - s)); rot = 0.1 * math.sin(math.pi * t)
  end
  if phase == 'sink' and pk < 0.25 then sy, sx = sy * 1.08, sx * 0.95 end        -- little 'boing' before diving
  local lp = t - st.pop_t0
  if not phase and lp >= 0 and lp < 0.5 then sy, sx = sy * 0.9, sx * 1.07 end     -- landing squash
  local act = st.act
  local an, ap = act and act.name, act and math.max(0, math.min(1, (t - act.t0) / act.dur)) or 0
  if an == 'hop' or an == 'chime' or an == 'startle' then
    local p = (t - act.t0) / 1.0
    if p < 1 then
      if p < 0.18 or p > 0.82 then sy, sx = sy * 0.9, sx * 1.06
      else oy = oy - (an == 'startle' and 9 or 7) * math.sin(math.pi * (p - 0.18) / 0.64) end
    end
  elseif an == 'wobble' then
    local k = math.sin(4 * math.pi * ap) * (1 - ap); sx, sy = sx * (1 + 0.1 * k), sy * (1 - 0.1 * k)
  elseif an == 'sway' then rot = 0.14 * math.sin(4 * math.pi * ap) * (1 - 0.4 * ap)
  elseif an == 'curious' then rot = 0.17 * math.min(1, ap * 4, (1 - ap) * 4)
  elseif an == 'sneeze' then
    if ap < 0.5 then sy, rot = sy * 1.08, -0.06 else sy, sx = sy * 0.86, sx * 1.08 end
  elseif an == 'squish' then
    if ap < 0.45 then sy, sx = sy * 0.72, sx * 1.16 else local k = math.sin((ap - 0.45) / 0.55 * math.pi); sy, sx = sy * (1 + 0.1 * k), sx * (1 - 0.05 * k) end
  elseif an == 'dance' then
    local s = math.abs(math.sin(math.pi * t)); oy = oy - 4 * s; rot = 0.14 * math.sin(math.pi * t)
  elseif an == 'wave' then rot = 0.05
  elseif an == 'eat' then if math.floor(ap * 6) % 2 == 1 then sy, sx = sy * 0.95, sx * 1.03 end
  elseif an == 'coffee' and ap > 0.35 and ap < 0.7 then rot = -0.05
  elseif an == 'huff' then                                    -- puff up... hmph (deflate)
    if ap < 0.4 then local k = math.sin(ap / 0.4 * math.pi / 2); sx, sy = sx * (1 + 0.08 * k), sy * (1 + 0.08 * k)
    else local k = math.sin((ap - 0.4) / 0.6 * math.pi); sx, sy = sx * (1.08 - 0.1 * k), sy * (1.08 - 0.16 * k) end
    rot = -0.04
  end
  if PET.pose and an then
    local P = {sx = sx, sy = sy, oy = oy, rot = rot}
    PET.pose(an, ap, t, P)
    sx, sy, oy, rot = P.sx, P.sy, P.oy, P.rot
  end
  local grumpy = st.grumpy
  if st.dozing then sy, sx = sy * 0.9, sx * 1.04 end
  if wx == 'cold' or wx == 'snow' then bx = bx + (math.random() - 0.5) * 1.0 end

  local a, b = A0 * sx, B0 * sy
  local cx, cy = bx, by - b + oy

  -- contact shadow when sitting on the top edge
  if kind == 'sit' and not phase then
    ellipse(bx, by + 1, A0 * 0.95, 3.2); rgba(M.shadow or BLACK, 0.28 * (1 + oy / 10)); cairo_fill(cr)
  end

  local base = body_colour(light)
  st.body = base
  -- what the pet's own drawing hooks get
  local E = {cr = cr, M = M, t = t, cx = cx, cy = cy, a = a, b = b, bx = bx, by = by, base = base, light = light,
             mood = mood, st = st, phase = phase, kind = kind, rgba = rgba, ellipse = ellipse, rrect = rrect, mix = mix,
             text = ctx.text, ICON = ctx.ICON, WHITE = WHITE, BLACK = BLACK, EYE = EYE, sky = ctx.sky or {},
             cpu = ctx.cpu_load or 0}
  E.path = function() body_path(cx, cy, a, b) end
  if PET.draw_under then PET.draw_under(E) end
  if st.hot and not phase then flames(bx, by, A0, t) end       -- "this is fine"
  cairo_save(cr)
  cairo_translate(cr, bx, by); cairo_rotate(cr, rot); cairo_translate(cr, -bx, -by)
  -- body
  body_path(cx, cy, a, b)
  local g = cairo_pattern_create_linear(0, cy - b, 0, cy + b)
  local top, bot = mix(base, WHITE, 0.22), mix(base, BLACK, 0.18)
  cairo_pattern_add_color_stop_rgba(g, 0, top[1], top[2], top[3], 1)
  cairo_pattern_add_color_stop_rgba(g, 1, bot[1], bot[2], bot[3], 1)
  cairo_set_source(cr, g); cairo_fill_preserve(cr); cairo_pattern_destroy(g)
  rgba(mix(base, BLACK, 0.35), 0.55); cairo_set_line_width(cr, 1); cairo_stroke(cr)
  if PET.draw_body then
    cairo_save(cr); body_path(cx, cy, a, b); cairo_clip(cr); PET.draw_body(E); cairo_restore(cr)
  end
  -- glossy highlight
  cairo_save(cr); cairo_translate(cr, cx - a * 0.42, cy - b * 0.55); cairo_rotate(cr, -0.45)
  ellipse(0, 0, a * 0.24, b * 0.13); rgba(WHITE, 0.55); cairo_fill(cr); cairo_restore(cr)
  if st.flash_until > t then body_path(cx, cy, a, b); rgba(WHITE, 0.3); cairo_fill(cr) end

  -- scarf (cold / snow), clipped to the body
  if wx == 'cold' or wx == 'snow' then
    cairo_save(cr); body_path(cx, cy, a, b); cairo_clip(cr)
    cairo_rectangle(cr, cx - a - 1, cy + b * 0.22, 2 * a + 2, 5.5); rgba(M.red); cairo_fill(cr)
    for i = 0, 5 do cairo_rectangle(cr, cx - a + i * 8, cy + b * 0.22, 2, 5.5) end
    rgba(WHITE, 0.25); cairo_fill(cr)
    cairo_restore(cr)
    rrect(cx + a * 0.45, cy + b * 0.22 + 3, 5, 10, 2); rgba(M.red); cairo_fill(cr)
  end

  -- face
  local gx, gy = 0, 0
  if phase then gx, gy = 0, 0
  elseif kind == 'peekL' then gx, gy = -1, 0
  elseif kind == 'peekD' then gx, gy = 0, 1
  elseif an == 'typing' then gx, gy = 0, 0.8
  elseif an == 'sideeye' then gx, gy = 1, 0.1
  elseif an == 'search' then gx, gy = math.sin(2 * math.pi * ap * 1.5), 0.2
  elseif mood == 'watch' then gx, gy = 0, -0.5
  elseif an == 'look' then gx, gy = (ap < 0.33 and -1) or (ap < 0.66 and 1) or 0, 0
  elseif t < st.glance_until then gx, gy = st.gaze[1], st.gaze[2]
  elseif grumpy == 'ignored' then gx, gy = 1, 0.1 end                 -- looking away from you
  local fx = (kind == 'peekL') and -a * 0.22 or 0
  local fy = (kind == 'peekD') and b * 0.3 or 0
  local ex, ey = a * 0.36, -b * 0.06 + fy
  local blink = t < st.blink_until
  local eyes = 'open'
  if phase == 'sink' then eyes = 'happy'                     -- bye!
  elseif phase == 'rise' and pk < 0.6 then eyes = 'wide'        -- ta-da
  elseif mood == 'sleep' or st.dozing then eyes = 'closed'
  elseif an == 'startle' then eyes = 'wide'
  elseif an == 'sneeze' and ap < 0.5 then eyes = 'closed'
  elseif mood == 'music' or mood == 'wake' or an == 'heart' or an == 'chime' or an == 'eat' or an == 'wave'
      or an == 'dance' or (an == 'coffee' and ap > 0.35 and ap < 0.7) then eyes = 'happy'
  elseif an == 'sideeye' then eyes = 'side'
  elseif blink then eyes = 'closed'
  elseif grumpy == 'ignored' then eyes = 'side'
  elseif mood == 'drowsy' or st.hot or grumpy then eyes = 'half' end
  if PET.eyes and not phase then eyes = PET.eyes(eyes, an, ap, mood, st) or eyes end
  E.eyes, E.ex, E.ey, E.fx, E.fy, E.gx, E.gy = eyes, ex, ey, fx, fy, gx, gy
  for _, s in ipairs({-1, 1}) do
    local x, y = cx + fx + s * ex + gx * 2.2, cy + ey + gy * 1.6
    if st.shades and eyes ~= 'closed' then
      -- sunglasses drawn below
    elseif eyes == 'wide' then
      ellipse(x, y, 3.6, 4.0); rgba(EYE); cairo_fill(cr)
      ellipse(x - 1.1, y - 1.3, 1.3, 1.3); rgba(WHITE, 0.95); cairo_fill(cr)
    elseif eyes == 'open' then
      ellipse(x, y, 2.9, 3.3); rgba(EYE); cairo_fill(cr)
      ellipse(x - 0.9, y - 1.1, 0.95, 0.95); rgba(WHITE, 0.95); cairo_fill(cr)
    elseif eyes == 'half' then
      ellipse(x, y + 0.8, 2.9, 1.7); rgba(EYE); cairo_fill(cr)
    elseif eyes == 'side' then                       -- unimpressed: flat upper lids
      ellipse(x, y, 2.9, 3.3); rgba(EYE); cairo_fill(cr)
      ellipse(x + 0.6, y - 0.6, 0.9, 0.9); rgba(WHITE, 0.9); cairo_fill(cr)
      cairo_rectangle(cr, x - 3.6, y - 4.2, 7.2, 3.6); rgba(mix(base, WHITE, 0.12)); cairo_fill(cr)
      cairo_move_to(cr, x - 3.4, y - 0.6); cairo_line_to(cr, x + 3.4, y - 0.9)
      rgba(EYE); cairo_set_line_width(cr, 1.3); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
    elseif eyes == 'happy' then
      cairo_new_path(cr); cairo_arc(cr, x, y + 1.6, 2.6, math.pi * 1.15, math.pi * 1.85)
      rgba(EYE); cairo_set_line_width(cr, 1.6); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
    else -- closed
      cairo_new_path(cr); cairo_arc(cr, x, y - 1.2, 2.6, math.pi * 0.15, math.pi * 0.85)
      rgba(EYE); cairo_set_line_width(cr, 1.5); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
    end
  end
  if st.shades and eyes ~= 'closed' then
    for _, s in ipairs({-1, 1}) do rrect(cx + fx + s * ex - 4.2, cy + ey - 3, 8.4, 5.6, 2.2) end
    rgba({0.08, 0.08, 0.12}); cairo_fill(cr)
    cairo_move_to(cr, cx + fx - ex + 4, cy + ey - 1.5); cairo_line_to(cr, cx + fx + ex - 4, cy + ey - 1.5)
    cairo_set_line_width(cr, 1.2); cairo_stroke(cr)
    ellipse(cx + fx - ex - 1.5, cy + ey - 1.4, 1.2, 0.8); rgba(WHITE, 0.7); cairo_fill(cr)
  end
  -- grumpy brows: short angled strokes, inner ends low (a V)
  if grumpy and eyes ~= 'closed' and eyes ~= 'happy' then
    local drop = grumpy == 'ignored' and 1.0 or 1.9
    for _, s in ipairs({-1, 1}) do
      local x, y = cx + fx + s * ex + gx * 1.2, cy + ey - 5.4
      cairo_move_to(cr, x + s * 3.4, y - drop * 0.5); cairo_line_to(cr, x - s * 2.6, y + drop)
    end
    rgba(EYE); cairo_set_line_width(cr, 1.4); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
  end
  -- cheeks
  for _, s in ipairs(st.mask > 0 and {} or {-1, 1}) do
    ellipse(cx + fx + s * a * 0.62 + gx, cy + b * 0.2 + fy, 3.4, 2); rgba(M.pink or {1, 0.6, 0.7}, light and 0.45 or 0.38); cairo_fill(cr)
  end
  -- mouth
  local mx_, my_ = cx + fx + gx * 1.5, cy + b * 0.2 + fy + gy
  local munch = (an == 'eat' and math.floor(ap * 6) % 2 == 0) or (mood == 'watch' and (t % 4) < 0.5)
  if st.mask == 0 and munch then
    ellipse(mx_, my_ + 1, 2.2, 2.4); rgba(EYE); cairo_fill(cr)
  elseif st.mask == 0 and an == 'huff' then                   -- pursed 'hmph'
    ellipse(mx_ - 1.5, my_ + 1, 1.3, 1.0); rgba(EYE); cairo_fill(cr)
  elseif st.mask == 0 and grumpy and an ~= 'heart' then        -- frown
    cairo_new_path(cr); cairo_arc(cr, mx_, my_ + 3.2, 2.6, math.pi * 1.2, math.pi * 1.8)
    rgba(EYE); cairo_set_line_width(cr, 1.2); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
  elseif st.mask == 0 and an == 'sideeye' then
    cairo_move_to(cr, mx_ - 2.5, my_ + 1); cairo_line_to(cr, mx_ + 2.5, my_ + 0.6)
    rgba(EYE); cairo_set_line_width(cr, 1.1); cairo_stroke(cr)
  elseif mood == 'drowsy' and t < st.yawn_until then
    ellipse(mx_, my_ + 1, 1.8, 2.4); rgba(EYE); cairo_fill(cr)
  elseif mood ~= 'sleep' and not st.dozing and st.mask == 0 then
    cairo_new_path(cr); cairo_arc(cr, mx_ - 1.5, my_, 1.5, 0.1 * math.pi, 0.9 * math.pi)
    cairo_new_sub_path(cr); cairo_arc(cr, mx_ + 1.5, my_, 1.5, 0.1 * math.pi, 0.9 * math.pi)
    rgba(EYE); cairo_set_line_width(cr, 1.1); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
  end

  -- masks (by AQI tier)
  if st.mask > 0 then
    local x0, y0 = cx + fx, cy + fy
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    if st.mask == 1 then          -- surgical
      for _, s in ipairs({-1, 1}) do
        cairo_move_to(cr, x0 + s * a * 0.6, y0 + b * 0.26); cairo_line_to(cr, x0 + s * a * 0.95, y0 - b * 0.08)
      end
      rgba(WHITE, 0.85); cairo_set_line_width(cr, 0.9); cairo_stroke(cr)
      rrect(x0 - a * 0.62, y0 + b * 0.18, a * 1.24, b * 0.5, 3)
      rgba({0.68, 0.85, 0.97}); cairo_fill_preserve(cr); rgba({0.45, 0.65, 0.82}); cairo_set_line_width(cr, 0.8); cairo_stroke(cr)
      for _, k in ipairs({0.33, 0.5}) do
        cairo_move_to(cr, x0 - a * 0.5, y0 + b * k); cairo_line_to(cr, x0 + a * 0.5, y0 + b * k)
      end
      rgba({0.45, 0.65, 0.82}, 0.6); cairo_set_line_width(cr, 0.7); cairo_stroke(cr)
    elseif st.mask == 2 then      -- N95 cup
      for _, s in ipairs({-1, 1}) do
        cairo_move_to(cr, x0 + s * a * 0.45, y0 + b * 0.3); cairo_line_to(cr, x0 + s * a * 0.97, y0 + b * 0.05)
      end
      rgba({0.35, 0.36, 0.42}); cairo_set_line_width(cr, 1); cairo_stroke(cr)
      ellipse(x0, y0 + b * 0.42, a * 0.5, b * 0.3)
      rgba({0.96, 0.95, 0.91}); cairo_fill_preserve(cr); rgba({0.66, 0.65, 0.62}); cairo_set_line_width(cr, 0.8); cairo_stroke(cr)
      cairo_move_to(cr, x0, y0 + b * 0.14); cairo_line_to(cr, x0, y0 + b * 0.7)
      rgba({0.66, 0.65, 0.62}, 0.8); cairo_set_line_width(cr, 0.7); cairo_stroke(cr)
      ellipse(x0 + a * 0.24, y0 + b * 0.46, 2.3, 2.3); rgba({0.55, 0.58, 0.66}); cairo_fill(cr)
    else                          -- respirator with filter cans
      for _, s in ipairs({-1, 1}) do
        cairo_move_to(cr, x0 + s * a * 0.4, y0 + b * 0.28); cairo_line_to(cr, x0 + s * a * 0.98, y0 + b * 0.12)
      end
      rgba({0.2, 0.21, 0.25}); cairo_set_line_width(cr, 1.4); cairo_stroke(cr)
      rrect(x0 - a * 0.42, y0 + b * 0.12, a * 0.84, b * 0.6, 5)
      rgba({0.24, 0.25, 0.3}); cairo_fill(cr)
      for i = 0, 2 do
        cairo_move_to(cr, x0 - a * 0.18, y0 + b * (0.3 + i * 0.13)); cairo_line_to(cr, x0 + a * 0.18, y0 + b * (0.3 + i * 0.13))
      end
      rgba({0.55, 0.57, 0.64}); cairo_set_line_width(cr, 0.8); cairo_stroke(cr)
      for _, s in ipairs({-1, 1}) do
        local fxx, fyy = x0 + s * a * 0.55, y0 + b * 0.5
        ellipse(fxx, fyy, 4.4, 4.4); rgba({0.3, 0.31, 0.37}); cairo_fill_preserve(cr)
        rgba({0.98, 0.8, 0.3}); cairo_set_line_width(cr, 1.1); cairo_stroke(cr)
        ellipse(fxx, fyy, 1.6, 1.6); rgba({0.55, 0.57, 0.64}); cairo_fill(cr)
      end
    end
  end
  if PET.draw_over then PET.draw_over(E) end
  -- props
  if mood == 'watch' then                                       -- screen glow + popcorn
    ellipse(cx, cy - b * 0.1, a * 0.8, b * 0.6); rgba(M.sky or M.blue, 0.10 + 0.04 * math.sin(t * 5)); cairo_fill(cr)
    local px, py = cx - a * 0.62, by - 1
    cairo_new_path(cr); cairo_move_to(cr, px - 4.5, py - 9); cairo_line_to(cr, px + 4.5, py - 9)
    cairo_line_to(cr, px + 3.3, py); cairo_line_to(cr, px - 3.3, py); cairo_close_path(cr)
    rgba(WHITE); cairo_fill(cr)
    for i = -1, 1 do cairo_rectangle(cr, px + i * 3 - 0.8, py - 9, 1.6, 9) end
    rgba(M.red or {0.9, 0.3, 0.3}); cairo_fill(cr)
    for i, o in ipairs({{-2.5, -10}, {0.5, -11.2}, {3, -10}, {-0.8, -12.3}}) do
      ellipse(px + o[1], py + o[2], 1.8, 1.5); rgba({1, 0.95, 0.78}); cairo_fill(cr)
    end
  end
  if an == 'eat' and ap < 0.92 then                              -- a little rice-cake treat, bitten 3x
    local r = 5.5 * (1 - math.floor(ap * 3) / 3) + 1.2
    local tx, ty = cx + a * 0.1, by - r - 0.5
    ellipse(tx, ty, r, r * 0.85); rgba({1, 0.94, 0.96}); cairo_fill_preserve(cr)
    rgba({0.8, 0.7, 0.75}); cairo_set_line_width(cr, 0.7); cairo_stroke(cr)
    ellipse(tx + r * 0.2, ty - r * 0.15, r * 0.3, r * 0.25); rgba(M.pink or {1, 0.7, 0.8}, 0.8); cairo_fill(cr)
  end
  if an == 'coffee' then
    if ap > 0.35 and ap < 0.7 then mug(cx + a * 0.3, cy + b * 0.55, t, false)   -- sip
    else mug(cx + a * 0.62, by - 0.5, t, true) end
  elseif st.hot and not phase then mug(cx + a * 0.62, by - 0.5, t, true)      -- calm sip amid the flames
  end
  if an == 'search' then                                        -- magnifying glass
    local hx, hy = cx + a * 0.78 + math.sin(2 * math.pi * ap * 1.5) * 4, cy + b * 0.05
    cairo_move_to(cr, hx + 3.4, hy + 3.4); cairo_line_to(cr, hx + 7.5, hy + 8)
    rgba({0.45, 0.33, 0.25}); cairo_set_line_width(cr, 2); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
    ellipse(hx, hy, 5, 5); rgba(M.sky or WHITE, 0.25); cairo_fill_preserve(cr)
    rgba(M.overlay2 or {0.6, 0.6, 0.7}); cairo_set_line_width(cr, 1.6); cairo_stroke(cr)
    ellipse(hx - 1.6, hy - 1.6, 1.2, 0.8); rgba(WHITE, 0.7); cairo_fill(cr)
  end
  if an == 'wave' then                                          -- a little nub waving hello
    cairo_save(cr); cairo_translate(cr, cx + a * 0.9, cy - b * 0.05)
    cairo_rotate(cr, -0.35 + 0.55 * math.sin(4 * math.pi * ap))
    ellipse(0, -5, 3.2, 6); rgba(mix(base, WHITE, 0.15)); cairo_fill_preserve(cr)
    rgba(mix(base, BLACK, 0.35), 0.6); cairo_set_line_width(cr, 0.9); cairo_stroke(cr)
    cairo_restore(cr)
  end
  -- typing on a tiny laptop (seen from behind the lid)
  if an == 'typing' then
    ellipse(cx, cy + b * 0.1, a * 0.75, b * 0.55); rgba(M.sky or M.blue, 0.14); cairo_fill(cr)   -- screen glow
    local lw, lh = 22, 8
    rrect(cx - lw / 2, by - lh - 1, lw, lh, 2.5); rgba({0.27, 0.28, 0.33}); cairo_fill_preserve(cr)
    rgba({0.45, 0.47, 0.54}); cairo_set_line_width(cr, 0.8); cairo_stroke(cr)
    if st.type_kind == 'term' then                    -- terminal: >_ with a blinking cursor
      ctx.text(cx - 1, by - 2.6, '>' .. ((math.floor(t * 2) % 2 == 0) and '_' or ' '), 7, {0.55, 0.92, 0.55, 1}, true, 'c')
    elseif st.type_kind == 'code' then
      ctx.text(cx, by - 2.6, '</>', 6.5, {(M.sky or M.blue)[1], (M.sky or M.blue)[2], (M.sky or M.blue)[3], 1}, true, 'c')
    else
      ellipse(cx, by - lh / 2 - 1, 1.4, 1.4); rgba(WHITE, 0.55); cairo_fill(cr)
    end
    rrect(cx - lw / 2 - 2, by - 1.5, lw + 4, 2.5, 1); rgba({0.2, 0.21, 0.25}); cairo_fill(cr)
    local f = math.floor(t * 4) % 2
    local paw = mix(base, BLACK, 0.05)
    for i, s in ipairs({-1, 1}) do
      local up = (i - 1 == f) and 2 or 0
      ellipse(cx + s * 5.5, by - lh - 1.5 - up, 2.8, 2.2); rgba(paw); cairo_fill_preserve(cr)
      rgba(mix(base, BLACK, 0.35), 0.6); cairo_set_line_width(cr, 0.8); cairo_stroke(cr)
    end
  end
  cairo_restore(cr)   -- end of rotated body

  -- action extras
  if an == 'heart' then
    local hx, hy, s = cx + a * 0.65, cy - b - 3 - ap * 16, 3.2
    cairo_new_path(cr)
    cairo_arc(cr, hx - s / 2, hy, s / 2, math.pi, 0); cairo_arc(cr, hx + s / 2, hy, s / 2, math.pi, 0)
    cairo_line_to(cr, hx, hy + s * 1.15); cairo_close_path(cr)
    rgba(M.red, math.sin(math.pi * ap)); cairo_fill(cr)
  elseif an == 'curious' then
    ctx.text(cx + a * 0.7, cy - b - 2, '?', 12, {M.text[1], M.text[2], M.text[3], math.min(1, ap * 4, (1 - ap) * 4)}, true)
  elseif an == 'startle' then
    ctx.text(cx + a * 0.55, cy - b - 3, '!', 13, {M.yellow[1], M.yellow[2], M.yellow[3], 1 - ap * 0.6}, true)
  elseif an == 'chime' then
    for i = 0, 5 do
      local ang = i * math.pi / 3 + ap * 1.2
      local r = a + 3 + ap * 10
      local x, y = cx + math.cos(ang) * r, cy + math.sin(ang) * r * 0.8
      cairo_new_path(cr); cairo_move_to(cr, x, y - 2.6); cairo_line_to(cr, x + 1.6, y); cairo_line_to(cr, x, y + 2.6)
      cairo_line_to(cr, x - 1.6, y); cairo_close_path(cr)
      rgba(M.yellow, math.sin(math.pi * ap)); cairo_fill(cr)
    end
  elseif an == 'sneeze' and ap >= 0.5 then
    local k = (ap - 0.5) * 2
    for i = -1, 1 do
      local ang = math.pi + i * 0.45
      local r0, r1 = a * 0.75 + k * 4, a * 0.75 + 4 + k * 6
      cairo_move_to(cr, cx + math.cos(ang) * r0, cy + b * 0.3 + math.sin(ang) * r0 * 0.5)
      cairo_line_to(cr, cx + math.cos(ang) * r1, cy + b * 0.3 + math.sin(ang) * r1 * 0.5)
    end
    rgba(M.text, 0.7 * (1 - k)); cairo_set_line_width(cr, 1.1); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
  end
  if an == 'huff' and ap > 0.4 then                           -- two little puffs of air out the side
    local k = (ap - 0.4) / 0.6
    for i = 0, 1 do
      local r = 1.6 + k * 2.2 - i * 0.6
      ellipse(cx - a - 2 - k * 9 - i * 4, cy + b * 0.25 - i * 3 - k * 2, r, r * 0.8)
      rgba(WHITE, 0.6 * (1 - k)); cairo_fill(cr)
    end
  end
  if PET.draw_act and an then PET.draw_act(E, an, ap) end
  if grumpy == 'woken' and not phase then                      -- pulsing anger mark
    local s = 1 + 0.15 * math.sin(t * 6)
    local mx2, my2 = cx + a * 0.85, cy - b * 0.85
    for _, q in ipairs({{1, 1}, {-1, 1}, {1, -1}, {-1, -1}}) do      -- four brackets bowing inward (a 💢)
      local dx, dy = q[1] * s, q[2] * s
      cairo_move_to(cr, mx2 + dx * 1.3, my2 + dy * 4.6)
      cairo_curve_to(cr, mx2 + dx * 1.6, my2 + dy * 1.6, mx2 + dx * 1.6, my2 + dy * 1.6, mx2 + dx * 4.6, my2 + dy * 1.3)
    end
    rgba(M.red or {0.95, 0.4, 0.5}, 1); cairo_set_line_width(cr, 1.6); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
  end
  if st.dozing then
    local p = (t * 0.25) % 1
    ctx.text(cx - a * 0.5 - p * 8, cy - b - 2 - p * 12, 'z', 8 + p * 3, {M.text[1], M.text[2], M.text[3], math.sin(p * math.pi) * 0.85}, true)
  end

  -- dance burst without music: just the notes
  if an == 'dance' and mood ~= 'music' then
    for k = 0, 1 do
      local p = (t * 0.45 + k * 0.5) % 1
      local col = M.accent2 or M.peach
      ctx.text(cx + a + 4 + p * 8, cy - b - 2 - p * 18, k == 0 and '\u{f0387}' or '\u{f075a}', k == 0 and 11 or 10,
        {col[1], col[2], col[3], math.sin(p * math.pi)}, false, nil, ctx.ICON)
    end
  end
  -- headphones
  if mood == 'music' then
    cairo_new_path(cr); cairo_arc(cr, cx, cy + 1, a * 1.02, math.pi * 1.08, math.pi * 1.92)
    rgba(M.overlay2 or M.subtext0); cairo_set_line_width(cr, 2.6); cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND); cairo_stroke(cr)
    for _, s in ipairs({-1, 1}) do
      rrect(cx + s * a * 0.98 - 3.5, cy - 7, 7, 12, 3); rgba(M.accent2 or M.peach); cairo_fill_preserve(cr)
      rgba(mix(M.accent2 or M.peach, BLACK, 0.35)); cairo_set_line_width(cr, 1); cairo_stroke(cr)
    end
    for k = 0, 1 do
      local p = (t * 0.45 + k * 0.5) % 1
      local al = math.sin(p * math.pi)
      ctx.text(cx - a - 6 - p * 10 + math.sin(p * 6) * 2, cy - b - 2 - p * 20, k == 0 and '\u{f0387}' or '\u{f075a}',
        k == 0 and 11 or 10, {(M.accent2 or M.peach)[1], (M.accent2 or M.peach)[2], (M.accent2 or M.peach)[3], al}, false, nil, ctx.ICON)
    end
  end
  -- zZ
  if mood == 'sleep' then
    for k = 0, 1 do
      local p = (t * 0.22 + k * 0.5) % 1
      local al = math.sin(p * math.pi) * 0.9
      ctx.text(cx - a * 0.6 - p * 14, cy - b - 3 - p * 18, k == 0 and 'z' or 'Z', 8 + p * 5,
        {M.text[1], M.text[2], M.text[3], al}, true)
    end
  end

  -- weather above / around
  if wx == 'rain' or wx == 'storm' then
    local ux, uy = cx + 3, cy - b - 9
    if PET.rain_gear then
    cairo_new_path(cr); cairo_arc(cr, ux, uy + 7, a * 0.95, math.pi, 2 * math.pi)
    for i = 3, 0, -1 do                                   -- scalloped rim
      local x0 = ux - a * 0.95 + (i + 0.5) * (a * 1.9 / 4)
      cairo_arc_negative(cr, x0, uy + 7, a * 1.9 / 8, 0, math.pi)
    end
    cairo_close_path(cr)
    rgba(M.accent2 or M.blue); cairo_fill_preserve(cr); rgba(mix(M.accent2 or M.blue, BLACK, 0.3)); cairo_set_line_width(cr, 1); cairo_stroke(cr)
    cairo_move_to(cr, ux, uy - a * 0.95 + 6); cairo_line_to(cr, ux, uy - a * 0.95 + 3); cairo_stroke(cr)
    cairo_move_to(cr, ux, uy + 7); cairo_line_to(cr, ux, cy - b + 3)
    rgba(M.overlay2 or M.subtext0); cairo_set_line_width(cr, 1.3); cairo_stroke(cr)
    end                                                   -- (no umbrella: just the drops)
    for k = 0, 3 do
      local p = (t * 1.3 + k * 0.27) % 1
      local x = ux + (k % 2 == 0 and -1 or 1) * (a * 1.05 + 3 + k)
      local y = uy + 4 + p * (b * 2 + 6)
      cairo_move_to(cr, x, y); cairo_line_to(cr, x - 1, y + 4)
      rgba(M.sky or M.blue, 0.8 * math.sin(p * math.pi)); cairo_set_line_width(cr, 1.3); cairo_stroke(cr)
    end
  elseif wx == 'snow' then
    for k = 0, 4 do
      local p = (t * 0.35 + k * 0.21) % 1
      local x = cx + (k - 2) * a * 0.55 + math.sin(t * 1.5 + k) * 3
      local y = cy - b - 14 + p * (b * 2 + 18)
      ellipse(x, y, 1.3, 1.3); rgba(WHITE, 0.9 * math.sin(p * math.pi)); cairo_fill(cr)
    end
  elseif wx == 'fog' then
    for k = 0, 1 do
      local ph = (t * 0.08 + k * 0.5) % 1
      ellipse(cx - a * 1.4 + ph * a * 2.8, cy + (k == 0 and -2 or 6), a * 0.9, 3.2)
      rgba(M.overlay2 or WHITE, 0.32 * math.sin(ph * math.pi)); cairo_fill(cr)
    end
  end
end

------------------------------------------------------------------ export (GNOME panel extension)
-- Writes the blob's current state + palette to a small JSON file for the "glob" GNOME Shell
-- extension. Rewritten only when something changes, plus a heartbeat every 30 s.
local function jesc(v) return '"' .. tostring(v or ''):gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"' end
local COLS = {'accent', 'accent2', 'text', 'subtext0', 'overlay2', 'red', 'yellow', 'pink', 'sky', 'blue', 'peach', 'shadow', 'base',
              'lavender', 'mauve', 'teal', 'sapphire', 'green'}
function B.export(path, M_, sky, wx)
  if not st.ok or not st.mood then return end
  if st.act ~= st._last_act then st._last_act = st.act; st.act_id = (st.act_id or 0) + 1 end
  local cols = {}
  for _, k in ipairs(COLS) do
    local c = M_[k] or M_.text
    cols[#cols + 1] = string.format('"%s":[%.3f,%.3f,%.3f]', k, c[1], c[2], c[3])
  end
  sky = sky or {}
  local where = st.trip and ('trip:' .. st.trip.phase .. '->' .. st.trip.to) or (st.perch or '')
  local body = string.format('"pet":%s,"name":%s,"body":[%.3f,%.3f,%.3f],"perch":%s,"mood":%s,"weather":%s,"mask":%d,"shades":%s,"dozing":%s,"act":%s,"act_id":%d,"act_dur":%.2f,'
    .. '"light":%s,"colors":{%s},"hot":%s,"grumpy":%s,"type_kind":%s,"app":%s,"moon":%d,"waxing":%s,"cpu":%d',
    jesc(PET.id), jesc(PET.name), (st.body or M_.accent)[1], (st.body or M_.accent)[2], (st.body or M_.accent)[3],
    jesc(where), jesc(st.mood), jesc(st.weather), st.mask or 0, tostring(st.shades and true or false), tostring(st.dozing and true or false),
    jesc(st.act and st.act.name or ''), st.act_id or 0, st.act and st.act.dur or 0,
    tostring(sky.flavour == 'latte'), table.concat(cols, ','),
    tostring(st.hot and true or false), jesc(st.grumpy), jesc(st.type_kind), jesc(st.app),
    math.floor(tonumber(sky.moon_illum) or 100),
    tostring(not ((sky.moon_phase or ''):find('waning') or (sky.moon_phase or ''):find('last'))),
    math.floor((st.cpu_load or 0) / 5 + 0.5) * 5)          -- rounded, so the file isn't rewritten every second
  local now_s = os.time()
  if body == st._last_body and now_s - (st._last_write or 0) < 30 then return end
  st._last_body, st._last_write = body, now_s
  local f = io.open(path .. '.tmp', 'w')
  if not f then return end
  f:write('{', body, ',"t":', now_s, '}\n'); f:close()
  os.rename(path .. '.tmp', path)
end

function B.draw_behind(ctx) if st.ok and not st.hidden and st.layer == 'behind' then draw(ctx) end end
function B.draw_front(ctx) if st.ok and not st.hidden and st.layer ~= 'behind' then draw(ctx) end end
function B.state() return st end
B.id, B.name = PET.id, PET.name
return B
end
