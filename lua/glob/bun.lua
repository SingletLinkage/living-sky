--[[
  Bun: a sleepy slice of bread (toast silhouette, crust rim) who would rather be asleep.
  Personality: slow breathing and blinking, wobbles and sways instead of hopping, takes little naps
  between things, snacks twice as often as anyone else (and loves it), sleeps 22:30-08:30 and gets
  drowsy again after lunch (13:30-15:00) and from 20:00. Extra grumpy when woken (15 min), but
  hardly notices being ignored (sulks only after 3 h).
]]
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'

-- a slice of bread: straight sides, rounded bottom corners, two round lobes on top
local function slice(cr, cx, cy, a, b)
  local w, r = a * 0.86, 4
  cairo_new_path(cr)
  cairo_move_to(cr, cx - w + r, cy + b)
  cairo_line_to(cr, cx + w - r, cy + b)
  cairo_curve_to(cr, cx + w, cy + b, cx + w, cy + b, cx + w, cy + b - r)
  cairo_line_to(cr, cx + w, cy - b * 0.25)
  cairo_curve_to(cr, cx + a * 1.08, cy - b * 0.45, cx + a * 1.0, cy - b * 1.08, cx + a * 0.5, cy - b * 1.08)
  cairo_curve_to(cr, cx + a * 0.2, cy - b * 1.08, cx + a * 0.08, cy - b * 0.94, cx, cy - b * 0.94)
  cairo_curve_to(cr, cx - a * 0.08, cy - b * 0.94, cx - a * 0.2, cy - b * 1.08, cx - a * 0.5, cy - b * 1.08)
  cairo_curve_to(cr, cx - a * 1.0, cy - b * 1.08, cx - a * 1.08, cy - b * 0.45, cx - w, cy - b * 0.25)
  cairo_line_to(cr, cx - w, cy + b - r)
  cairo_curve_to(cr, cx - w, cy + b, cx - w, cy + b, cx - w + r, cy + b)
  cairo_close_path(cr)
end

return dofile(dir .. 'core.lua'){
  id = 'bun', name = 'Bun',
  size = {20, 17}, body = slice,
  color = function(M, light, mix)                 -- the crumb: soft golden cream
    local c = mix(M.yellow, M.peach, 0.18)
    return light and mix(c, {1, 1, 1, 1}, 0.25) or c
  end,
  breath = 5, blink_every = {4, 8},
  act_every = {30, 70}, wander_every = {600, 1500},
  snack_every = {600, 900}, snack_heart = 0.7,
  woken_s = 900, neglect_s = 3 * 3600,
  pool = {nap = 3, wobble = 2, sway = 2, look = 1, heart = 1, curious = 1},
  poke = {wobble = 1, squish = 2},
  acts = {nap = 14},
  schedule = function(h)
    if h >= 22.5 or h < 8.5 then return 'sleep' end
    if h < 9 then return 'wake' end
    if h >= 20 or (h >= 13.5 and h < 15) then return 'drowsy' end
    return 'awake'
  end,
  pose = function(an, ap, t, P)
    if an == 'nap' then P.sy, P.sx = P.sy * 0.92, P.sx * 1.04 end
  end,
  eyes = function(eyes, an)
    if an == 'nap' then return 'closed' end
  end,
  draw_body = function(E)                         -- the crust: a toasted rim just inside the outline
    local cr = E.cr
    E.path(); E.rgba(E.mix(E.M.peach, E.BLACK, 0.18)); cairo_set_line_width(cr, 5.2); cairo_stroke(cr)
    E.path(); E.rgba(E.mix(E.M.peach, E.WHITE, 0.1), 0.6); cairo_set_line_width(cr, 1.4); cairo_stroke(cr)
  end,
  draw_act = function(E, an, ap)
    if an ~= 'nap' then return end
    local p = (E.t * 0.25) % 1
    local c = E.M.text
    E.text(E.cx - E.a * 0.5 - p * 8, E.cy - E.b - 2 - p * 12, 'z', 8 + p * 3, {c[1], c[2], c[3], math.sin(p * math.pi) * 0.85}, true)
  end,
}
