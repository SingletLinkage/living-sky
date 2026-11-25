--[[
  Pip: a small sapphire droplet with far too much energy.
  Personality: hops and dances a lot, short attention span (an idle action every 6-14 s), wanders
  often, blinks fast, startles easily when poked. LOVES rain: no umbrella, it splashes about instead.
  Short-tempered but forgiving: grumpy for only 5 min when woken; needs attention (sulks after 1 h).
  Sleeps 00:00-06:30.
]]
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'

-- teardrop: pointed top, round bottom (the bottom edge sits on the perch)
local function drop(cr, cx, cy, a, b)
  cairo_new_path(cr)
  cairo_move_to(cr, cx, cy - b * 1.18)
  cairo_curve_to(cr, cx + a * 0.3, cy - b * 0.72, cx + a, cy - b * 0.2, cx + a, cy + b * 0.32)
  cairo_curve_to(cr, cx + a, cy + b * 0.92, cx + a * 0.55, cy + b, cx, cy + b)
  cairo_curve_to(cr, cx - a * 0.55, cy + b, cx - a, cy + b * 0.92, cx - a, cy + b * 0.32)
  cairo_curve_to(cr, cx - a, cy - b * 0.2, cx - a * 0.3, cy - b * 0.72, cx, cy - b * 1.18)
  cairo_close_path(cr)
end

return dofile(dir .. 'core.lua'){
  id = 'pip', name = 'Pip',
  size = {16, 16}, color = 'sapphire', body = drop,
  breath = 2.6, blink_every = {1.5, 3.5},
  act_every = {6, 14}, wander_every = {180, 420},
  snack_every = {1500, 2100}, snack_heart = 0.6,
  woken_s = 300, neglect_s = 3600,
  pool = {hop = 4, dance = 2, look = 2, wobble = 1, curious = 1, wave = 1, squish = 1, heart = 1},
  morning_coffee = false,
  poke = {hop = 1, startle = 1, squish = 1},
  rain_gear = false,
  acts = {splash = 2.0},
  schedule = function(h)
    if h < 6.5 then return 'sleep' end
    if h < 7 then return 'wake' end
    if h >= 23 then return 'drowsy' end
    return 'awake'
  end,
  extra_pool = function(pool, st)
    if st.weather == 'rain' or st.weather == 'storm' then
      for _ = 1, 5 do pool[#pool + 1] = 'splash' end
    end
  end,
  pose = function(an, ap, t, P)
    if an == 'splash' then                        -- three little bounces
      local k = math.abs(math.sin(3 * math.pi * ap))
      P.oy = P.oy - 6 * k
      if k < 0.2 then P.sy, P.sx = P.sy * 0.88, P.sx * 1.08 end
    end
  end,
  eyes = function(eyes, an)
    if an == 'splash' then return 'happy' end
  end,
  draw_act = function(E, an, ap)
    if an ~= 'splash' then return end
    local cr = E.cr
    for i = 0, 5 do                               -- droplets flung out on each landing
      local p = (ap * 3 + i * 0.17) % 1
      local side = (i % 2 == 0) and -1 or 1
      local x = E.bx + side * (E.a * 0.6 + p * 14)
      local y = E.by - 2 - 10 * math.sin(math.pi * p)
      E.ellipse(x, y, 1.3, 1.7); E.rgba(E.M.sky or E.M.blue, 0.9 * (1 - p)); cairo_fill(cr)
    end
  end,
}
