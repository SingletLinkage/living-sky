--[[
  Ember: a little campfire wisp. A teardrop flame whose tip sways, with a bright core that flickers
  faster the busier the CPU is (ctx.cpu_load) and a warm glow around it.
  Personality: a night owl by the fire. Asleep 01-07 h, drowsy after 23 h; asleep, or out in the cold,
  it shrinks to a blue pilot light. Flares up and crackles sparks; flares more when the CPU is busy.
  "This is fine" (CPU >= 90 °C) makes it happy, not worried: it's a fire. In the rain it steams under
  its umbrella.
]]
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'

local T = 0                                     -- time of the current frame (for the swaying tip)

local function flame(cr, cx, cy, a, b)          -- round bottom, a pointed tip that sways
  local sway = 2.2 * math.sin(T * 2.3) + 1.0 * math.sin(T * 5.1)
  local tx, ty = cx + sway, cy - b * 1.55
  cairo_new_path(cr)
  cairo_move_to(cr, tx, ty)
  cairo_curve_to(cr, cx + a * 0.25 + sway * 0.4, cy - b * 0.95, cx + a * 1.05, cy - b * 0.45, cx + a, cy + b * 0.15)
  cairo_curve_to(cr, cx + a * 0.95, cy + b * 0.8, cx + a * 0.5, cy + b, cx, cy + b)
  cairo_curve_to(cr, cx - a * 0.5, cy + b, cx - a * 0.95, cy + b * 0.8, cx - a, cy + b * 0.15)
  cairo_curve_to(cr, cx - a * 1.05, cy - b * 0.45, cx - a * 0.25 + sway * 0.4, cy - b * 0.95, tx, ty)
  cairo_close_path(cr)
end

local function pilot(E)                          -- asleep or cold: a small blue flame
  local w = E.st.weather
  return E.mood == 'sleep' or w == 'cold' or w == 'snow'
end

local function radial(cr, x, y, r0, r1, c, k0)
  local g = cairo_pattern_create_radial(x, y, r0, x, y, r1)
  cairo_pattern_add_color_stop_rgba(g, 0, c[1], c[2], c[3], k0)
  cairo_pattern_add_color_stop_rgba(g, 1, c[1], c[2], c[3], 0)
  cairo_set_source(cr, g)
  return g
end

return dofile(dir .. 'core.lua'){
  id = 'ember', name = 'Ember',
  size = {16, 14}, body = flame,
  color = function(M, light, mix)                 -- warm peach, a touch deeper on the light day cards
    local c = mix(M.peach, M.yellow, 0.2)
    return light and mix(c, M.red, 0.12) or c
  end,
  breath = 2.6, blink_every = {2.5, 5.5},
  act_every = {10, 28},
  pool = {flare = 2, crackle = 2, hop = 1, dance = 1, heart = 1, look = 1, sway = 1},
  morning_coffee = false,
  acts = {flare = 2.0, crackle = 1.6},
  schedule = function(h)
    if h >= 1 and h < 7 then return 'sleep' end
    if h >= 7 and h < 7.75 then return 'wake' end
    if h >= 23 then return 'drowsy' end
    return 'awake'
  end,
  extra_pool = function(pool, st, ctx)            -- a busy CPU stokes the fire
    if (ctx.cpu_load or 0) >= 60 then pool[#pool + 1] = 'flare'; pool[#pool + 1] = 'flare' end
  end,
  pose = function(an, ap, t, P)
    if an == 'flare' then
      local k = math.sin(math.pi * ap)
      P.sy, P.sx, P.oy = P.sy * (1 + 0.28 * k), P.sx * (1 - 0.1 * k), P.oy - 2 * k
    elseif an == 'crackle' then P.rot = 0.06 * math.sin(ap * 40) * (1 - ap) end
  end,
  eyes = function(eyes, an, ap, mood, st)
    if st and st.hot and mood ~= 'sleep' then return 'happy' end            -- "this is fine", genuinely
    if an == 'flare' then return 'wide' end
    if an == 'crackle' then return 'happy' end
  end,
  draw_under = function(E)                        -- the glow: bigger with CPU load, blue for a pilot light
    T = E.t
    if E.phase then return end
    local cr, cpu = E.cr, math.max(0, math.min(100, E.cpu or 0)) / 100
    local blue = pilot(E)
    local c = blue and E.M.blue or E.mix(E.M.peach, E.M.yellow, 0.4)
    local r = E.a * (blue and 1.5 or (1.9 + 0.9 * cpu))
    local k = (E.light and 0.10 or 0.2) * (blue and 0.6 or 1) * (0.85 + 0.15 * math.sin(E.t * (3 + 6 * cpu)))
    local g = radial(cr, E.cx, E.cy + E.b * 0.2, E.a * 0.5, r, c, k)
    cairo_new_path(cr); cairo_arc(cr, E.cx, E.cy + E.b * 0.2, r, 0, 2 * math.pi); cairo_fill(cr)
    cairo_pattern_destroy(g)
  end,
  draw_body = function(E)                         -- the bright core (or the blue of a pilot light)
    local cr, cx, cy, a, b = E.cr, E.cx, E.cy, E.a, E.b
    if pilot(E) then
      local g = cairo_pattern_create_linear(0, cy - b * 1.5, 0, cy + b)
      local hi, lo = E.mix(E.M.sky, E.WHITE, 0.3), E.mix(E.M.blue, E.BLACK, 0.15)
      cairo_pattern_add_color_stop_rgba(g, 0, hi[1], hi[2], hi[3], 0.9)
      cairo_pattern_add_color_stop_rgba(g, 1, lo[1], lo[2], lo[3], 0.9)
      cairo_set_source(cr, g); cairo_paint(cr); cairo_pattern_destroy(g)
      return
    end
    local cpu = math.max(0, math.min(100, E.cpu or 0)) / 100
    local f = 0.75 + 0.25 * math.sin(E.t * (4 + 10 * cpu)) * math.sin(E.t * (2.7 + 5 * cpu))
    local core = E.mix(E.M.yellow, E.WHITE, 0.55)
    local g = radial(cr, cx, cy + b * 0.35, 1, a * (0.75 + 0.15 * f), core, 0.85 * f)
    cairo_paint(cr); cairo_pattern_destroy(g)
  end,
  draw_over = function(E)                         -- steam rising in the rain
    local w = E.st.weather
    if not (w == 'rain' or w == 'storm') or E.phase then return end
    local cr = E.cr
    for i = 0, 2 do
      local p = (E.t * 0.6 + i / 3) % 1
      local x = E.cx + (i - 1) * E.a * 0.7 + 2 * math.sin(E.t * 3 + i)
      local y = E.cy - E.b * 0.3 - p * 12
      cairo_new_path(cr)
      cairo_move_to(cr, x, y + 4)
      cairo_curve_to(cr, x - 2, y + 2, x + 2, y, x, y - 3)
      E.rgba(E.WHITE, 0.55 * math.sin(math.pi * p)); cairo_set_line_width(cr, 1.2); cairo_stroke(cr)
    end
  end,
  draw_act = function(E, an, ap)
    local cr = E.cr
    if an == 'crackle' or an == 'flare' then      -- sparks popping off in little arcs
      local n = an == 'crackle' and 6 or 4
      for i = 1, n do
        local ang = -math.pi / 2 + (i - (n + 1) / 2) * 0.45
        local d = (an == 'crackle' and 6 or 4) + ap * (an == 'crackle' and 16 or 22)
        local x = E.cx + math.cos(ang) * d
        local y = E.cy - E.b * 0.8 + math.sin(ang) * d + 10 * ap * ap
        E.ellipse(x, y, 1.1, 1.1)
        E.rgba(E.mix(E.M.yellow, E.WHITE, 0.4), math.max(0, 1 - ap) * 0.95); cairo_fill(cr)
      end
    end
  end,
}
