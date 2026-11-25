--[[
  Cubo: a rounded teal jelly cube with tiny round glasses.
  Personality: studious. Reads, sips coffee all day (not just mornings), asks "?" a lot, helps
  search when Files is open, types along eagerly. Sensitive to dust: sneezes from AQI 50.
  Night-time studier: drowsy 23:00-01:00, asleep 01:00-07:00.
]]
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'

-- rounded square (superellipse)
local function cube(cr, cx, cy, a, b)
  cairo_new_path(cr)
  for i = 0, 47 do
    local th = 2 * math.pi * i / 48
    local c, s = math.cos(th), math.sin(th)
    local n = 5
    local x = cx + a * (c >= 0 and 1 or -1) * math.abs(c) ^ (2 / n)
    local y = cy + b * (s >= 0 and 1 or -1) * math.abs(s) ^ (2 / n)
    if i == 0 then cairo_move_to(cr, x, y) else cairo_line_to(cr, x, y) end
  end
  cairo_close_path(cr)
end

return dofile(dir .. 'core.lua'){
  id = 'cubo', name = 'Cubo',
  size = {18, 16}, color = 'teal', body = cube,
  act_every = {12, 30},
  pool = {read = 3, coffee = 2, curious = 2, look = 1, search = 1, heart = 1, hop = 1, wave = 1},
  morning_coffee = false,
  sneeze_aqi = 50,
  acts = {read = 4.0},
  schedule = function(h)
    if h >= 1 and h < 7 then return 'sleep' end
    if h >= 7 and h < 7.5 then return 'wake' end
    if h >= 23 or h < 1 then return 'drowsy' end
    return 'awake'
  end,
  pose = function(an, ap, t, P)
    if an == 'read' then P.rot = 0.04 end
  end,
  draw_over = function(E)                         -- round glasses (not over sunglasses)
    if E.st.shades then return end
    local cr = E.cr
    local y = E.cy + E.ey + (E.gy or 0) * 1.6
    for _, s in ipairs({-1, 1}) do
      cairo_new_sub_path(cr); cairo_arc(cr, E.cx + (E.fx or 0) + s * E.ex + (E.gx or 0) * 2.2, y, 4.6, 0, 2 * math.pi)
    end
    E.rgba(E.EYE, 0.85); cairo_set_line_width(cr, 1.1); cairo_stroke(cr)
    local x0 = E.cx + (E.fx or 0) + (E.gx or 0) * 2.2
    cairo_move_to(cr, x0 - E.ex + 4.6, y - 0.6); cairo_line_to(cr, x0 + E.ex - 4.6, y - 0.6)
    cairo_set_line_width(cr, 1.0); cairo_stroke(cr)
  end,
  draw_act = function(E, an, ap)
    if an ~= 'read' then return end
    local cr = E.cr
    local x, y = E.cx, E.by - 1                   -- an open book held in front, a page turns halfway
    E.rrect(x - 11, y - 9, 22, 9, 1.5); E.rgba(E.M.red or {0.9, 0.4, 0.4}); cairo_fill(cr)
    E.rrect(x - 10, y - 10, 9.5, 9, 1); E.rrect(x + 0.5, y - 10, 9.5, 9, 1); E.rgba({0.98, 0.96, 0.9}); cairo_fill(cr)
    for i = 0, 2 do
      cairo_move_to(cr, x - 8.5, y - 8 + i * 2.3); cairo_line_to(cr, x - 2.5, y - 8 + i * 2.3)
      cairo_move_to(cr, x + 2, y - 8 + i * 2.3); cairo_line_to(cr, x + 8, y - 8 + i * 2.3)
    end
    E.rgba({0.6, 0.6, 0.66}, 0.8); cairo_set_line_width(cr, 0.6); cairo_stroke(cr)
    if ap > 0.45 and ap < 0.6 then                -- the turning page
      local k = (ap - 0.45) / 0.15
      local w = 9.5 * math.cos(math.pi * k)
      E.rrect(x + math.min(0, w), y - 10.5, math.abs(w), 9, 1); E.rgba({1, 1, 0.96}); cairo_fill(cr)
    end
  end,
}
