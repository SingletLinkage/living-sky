--[[
  Nyx: a little moon. A pale, cratered, round body whose shading follows the real moon phase
  tonight (from the sky slot: moon_illum, moon_phase), with a soft glow after dark.
  Personality: nocturnal. Asleep while the sun is up (from 30 min after sunrise to 30 min before
  sunset), in a striped nightcap; stretches awake at dusk, drowsy in the hour before dawn.
  At night it stargazes and cheers at a full moon. Woken in daylight it squints behind sunglasses.
]]
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'

local function round(cr, cx, cy, a, b)          -- nearly round, sitting a little flat on the card
  cairo_new_path(cr)
  for i = 0, 47 do
    local th = 2 * math.pi * i / 48
    local c, s = math.cos(th), math.sin(th)
    local n = s > 0 and 2.6 or 2.0
    local x = cx + a * (c >= 0 and 1 or -1) * math.abs(c) ^ (2 / n)
    local y = cy + b * (s >= 0 and 1 or -1) * math.abs(s) ^ (2 / n)
    if i == 0 then cairo_move_to(cr, x, y) else cairo_line_to(cr, x, y) end
  end
  cairo_close_path(cr)
end

local function sparkle(cr, x, y, r)
  cairo_new_path(cr)
  cairo_move_to(cr, x, y - r); cairo_line_to(cr, x + r * 0.3, y - r * 0.3); cairo_line_to(cr, x + r, y)
  cairo_line_to(cr, x + r * 0.3, y + r * 0.3); cairo_line_to(cr, x, y + r); cairo_line_to(cr, x - r * 0.3, y + r * 0.3)
  cairo_line_to(cr, x - r, y); cairo_line_to(cr, x - r * 0.3, y - r * 0.3); cairo_close_path(cr)
end

return dofile(dir .. 'core.lua'){
  id = 'nyx', name = 'Nyx',
  size = {17, 16}, body = round,
  color = function(M, light, mix)                 -- moonlight cream
    local c = mix(M.yellow, M.text, 0.35)
    return light and mix(c, {1, 1, 1, 1}, 0.25) or mix(c, {1, 1, 1, 1}, 0.12)
  end,
  breath = 4, blink_every = {3, 6.5},
  act_every = {14, 34},
  pool = {stargaze = 3, look = 2, curious = 1, wave = 1, sideeye = 1, heart = 1, hop = 1},
  morning_coffee = false,
  acts = {stargaze = 4.0, moonjoy = 2.4},
  schedule = function(h, sr, ss)
    if h >= sr + 0.5 and h < ss - 0.5 then return 'sleep' end
    if h >= ss - 0.5 and h < ss + 0.5 then return 'wake' end
    if h >= sr - 1 and h < sr + 0.5 then return 'drowsy' end
    return 'awake'
  end,
  extra_pool = function(pool, st, ctx)
    if ctx.sky and (ctx.sky.moon_illum or 0) >= 95 then
      pool[#pool + 1] = 'moonjoy'; pool[#pool + 1] = 'moonjoy'
    end
  end,
  shades = function(st, ctx, default, sun) return default or sun > 0 end,     -- awake in daylight: squinting
  pose = function(an, ap, t, P)
    if an == 'stargaze' then P.rot = -0.08 * math.min(1, ap * 5, (1 - ap) * 5)
    elseif an == 'moonjoy' then P.oy = P.oy - 6 * math.abs(math.sin(2 * math.pi * ap)) end
  end,
  eyes = function(eyes, an)
    if an == 'moonjoy' then return 'happy' end
    if an == 'stargaze' and eyes == 'open' then return 'wide' end
  end,
  draw_under = function(E)                        -- soft moonlight glow after dark
    if E.light or E.phase then return end
    local cr, c = E.cr, E.base
    local r = E.a * 2.0
    local k = 0.14 + 0.05 * math.sin(E.t * 1.3)
    local g = cairo_pattern_create_radial(E.cx, E.cy, E.a * 0.7, E.cx, E.cy, r)
    cairo_pattern_add_color_stop_rgba(g, 0, c[1], c[2], c[3], k)
    cairo_pattern_add_color_stop_rgba(g, 1, c[1], c[2], c[3], 0)
    cairo_new_path(cr); cairo_arc(cr, E.cx, E.cy, r, 0, 2 * math.pi); cairo_set_source(cr, g); cairo_fill(cr)
    cairo_pattern_destroy(g)
  end,
  draw_body = function(E)
    local cr, cx, cy, a, b = E.cr, E.cx, E.cy, E.a, E.b
    for _, c in ipairs({{0.58, -0.5, 2.8}, {-0.62, -0.42, 2.0}, {0.18, -0.8, 1.5}, {0.72, 0.42, 1.7}}) do   -- craters
      local x, y, r = cx + c[1] * a, cy + c[2] * b, c[3]
      E.ellipse(x, y, r, r * 0.85); E.rgba(E.mix(E.base, E.BLACK, 0.14), 0.75); cairo_fill(cr)
      E.ellipse(x + r * 0.25, y + r * 0.25, r * 0.7, r * 0.55); E.rgba(E.WHITE, 0.18); cairo_fill(cr)
    end
    -- tonight's phase: shadow on the unlit side (waxing: lit on the right), terminator as a half-ellipse
    local k = math.max(0, math.min(1, (tonumber(E.sky.moon_illum) or 100) / 100))
    if k > 0.97 then return end
    local ph = E.sky.moon_phase or ''
    local side = (ph:find('waning') or ph:find('last')) and 1 or -1
    local tx = a * 1.05 * (1 - 2 * k)
    cairo_new_path(cr)
    for i = 0, 24 do
      local th = -math.pi / 2 + math.pi * i / 24
      local x, y = cx + side * a * 1.1 * math.cos(th), cy + b * 1.1 * math.sin(th)
      if i == 0 then cairo_move_to(cr, x, y) else cairo_line_to(cr, x, y) end
    end
    for i = 24, 0, -1 do
      local th = -math.pi / 2 + math.pi * i / 24
      cairo_line_to(cr, cx - side * tx * math.cos(th), cy + b * 1.1 * math.sin(th))
    end
    cairo_close_path(cr)
    E.rgba(E.mix(E.M.mauve, E.BLACK, 0.45), 0.36); cairo_fill(cr)
  end,
  draw_over = function(E)                         -- a striped nightcap while asleep
    if E.mood ~= 'sleep' then return end
    local cr, cx, cy, a, b = E.cr, E.cx, E.cy, E.a, E.b
    local blue = E.M.blue
    cairo_new_path(cr)
    cairo_move_to(cr, cx - a * 0.78, cy - b * 0.55)
    cairo_curve_to(cr, cx - a * 0.3, cy - b * 1.45, cx + a * 0.55, cy - b * 1.35, cx + a * 1.25, cy - b * 0.35)
    cairo_curve_to(cr, cx + a * 0.7, cy - b * 0.7, cx + a * 0.2, cy - b * 0.8, cx - a * 0.78, cy - b * 0.55)
    cairo_close_path(cr)
    E.rgba(blue); cairo_fill_preserve(cr); E.rgba(E.mix(blue, E.BLACK, 0.3)); cairo_set_line_width(cr, 0.9); cairo_stroke(cr)
    cairo_move_to(cr, cx - a * 0.8, cy - b * 0.56)
    cairo_curve_to(cr, cx - a * 0.2, cy - b * 0.82, cx + a * 0.3, cy - b * 0.8, cx + a * 0.7, cy - b * 0.68)
    E.rgba(E.WHITE, 0.9); cairo_set_line_width(cr, 2.0); cairo_stroke(cr)
    E.ellipse(cx + a * 1.28, cy - b * 0.3, 2.4, 2.4); E.rgba(E.WHITE); cairo_fill(cr)
  end,
  draw_act = function(E, an, ap)
    local cr = E.cr
    if an == 'stargaze' then
      for i = 0, 2 do
        local tw = 0.5 + 0.5 * math.sin(E.t * 5 + i * 2.1)
        sparkle(cr, E.cx - E.a * 0.7 + i * E.a * 0.7, E.cy - E.b - 8 - (i % 2) * 6, 2.2 + tw * 1.4)
        E.rgba(E.M.yellow, math.min(1, ap * 4, (1 - ap) * 4) * (0.5 + 0.5 * tw)); cairo_fill(cr)
      end
    elseif an == 'moonjoy' then                     -- a burst of sparkles over its head
      for i = 0, 4 do
        local ang = -math.pi / 2 + (i - 2) * 0.55
        local r = E.a + 4 + ap * 10
        sparkle(cr, E.cx + math.cos(ang) * r, E.cy + math.sin(ang) * r, 2.4)
        E.rgba(E.M.yellow, math.sin(math.pi * ap)); cairo_fill(cr)
      end
    end
  end,
}
