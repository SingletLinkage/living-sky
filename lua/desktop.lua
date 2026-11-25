--[[
  living-sky desktop engine: the card stack, the living-sky wallpaper switcher, and the glob pet host.
  One engine, two styles, picked by the theme file that loads it (themes/<name>/<name>.lua sets
  LIVING_SKY_STYLE before dofile'ing this):
    glass  frosted "liquid glass" panes. conky can't read the pixels behind its window, so
           core/sky.py pre-renders a blurred, contrast-safe copy of each wallpaper (<slot>-frost.png);
           we paint it pixel-aligned inside every card, then add edge refraction, a tint,
           a specular sheen and a lit rim.
    cards  solid, translucent Catppuccin cards.
  Full-screen, transparent, click-through conky canvas; the cards sit in the right-hand column.
  Preview: touch ~/.cache/living-sky/preview-<style> -> ~/.cache/living-sky/preview-<style>.png
]]

require 'cairo'
pcall(require, 'cairo_xlib')

------------------------------------------------------------------ paths
-- Code root is found from this file's location (<root>/lua/desktop.lua), so the
-- project can live anywhere. User config: ~/.config/living-sky/living-sky.conf; cache: ~/.cache/living-sky.
local HOME = os.getenv('HOME')
local ROOT = ((debug.getinfo(1, 'S').source or ''):match('^@(.*)/lua/[^/]+%.lua$')
  or (HOME .. '/.local/share/living-sky')) .. '/'
local CONF = (os.getenv('XDG_CONFIG_HOME') or (HOME .. '/.config')) .. '/living-sky/living-sky.conf'
local SKYDIR = (os.getenv('XDG_CACHE_HOME') or (HOME .. '/.cache')) .. '/living-sky/'
do local f = io.open(CONF) if f then f:close() else CONF = ROOT .. 'living-sky.conf.example' end end
os.setlocale('', 'time')                -- weekday / month names from the system locale (LC_TIME only)
local STYLE = LIVING_SKY_STYLE or 'glass'
local GLASS = (STYLE == 'glass')
local function q(p) return "'" .. p:gsub("'", "'\\''") .. "'" end      -- shell-quote a path

------------------------------------------------------------------ palette (Mocha)
local function hex(h, a)
  return {tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1}
end
local M = {
  crust = hex('#11111b'), mantle = hex('#181825'), base = hex('#1e1e2e'),
  surface0 = hex('#313244'), surface1 = hex('#45475a'), overlay0 = hex('#6c7086'),
  overlay1 = hex('#7f849c'), overlay2 = hex('#9399b2'), subtext0 = hex('#a6adc8'), text = hex('#cdd6f4'),
  lavender = hex('#b4befe'), blue = hex('#89b4fa'), sapphire = hex('#74c7ec'),
  sky = hex('#89dceb'), teal = hex('#94e2d5'), green = hex('#a6e3a1'),
  yellow = hex('#f9e2af'), peach = hex('#fab387'), maroon = hex('#eba0ac'),
  red = hex('#f38ba8'), mauve = hex('#cba6f7'), pink = hex('#f5c2e7'),
}
-- living-sky extras (overridden per time slot by ~/.cache/living-sky/<slot>.lua)
M.accent, M.accent2, M.shadow = hex('#b4befe'), hex('#fab387'), hex('#11111b')
M.shadow_a, M.glass_a1, M.glass_a2 = 0.35, 0.86, 0.90
------------------------------------------------------------------ layout
-- screen (primary monitor) size, passed in by bin/living-sky. core/sky.py renders the wallpaper at this size
-- (older renders may be 1920x1200); GNOME shows it with 'zoom' (cover + centre), so the glass frost is mapped
-- the same way, from the size of the picture actually loaded (set_art)
local SW = tonumber(os.getenv('LIVING_SKY_W') or '') or 1920
local SH = tonumber(os.getenv('LIVING_SKY_H') or '') or 1200
local ART_W, ART_H, ZK, ZX, ZY
local function set_art(w, h)
  ART_W, ART_H = w, h
  ZK = math.max(SW / ART_W, SH / ART_H)
  ZX, ZY = (SW - ART_W * ZK) / 2, (SH - ART_H * ZK) / 2
end
set_art(1920, 1200)
local COL_W = 360
local COL_X = SW - COL_W - 30     -- card column, 30 px from the right edge (icons live on the left)
------------------------------------------------------------------ config (living-sky.conf)
-- One flat 'key = value' file; '#' starts a comment (but '#rrggbb' colours are values).
local function conf_read()              -- -> settings table, file text
  local t, f = {}, io.open(CONF)
  if not f then return t, '' end
  local txt = f:read('*a') or ''
  f:close()
  for line in (txt .. '\n'):gmatch('([^\n]*)\n') do
    line = line:gsub('^%s*#.*$', ''):gsub('%s+#[^%x].*$', ''):gsub('%s+#$', '')
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k then t[k] = v end
  end
  return t, txt
end
local CFG, CFG_TEXT = conf_read()
local function cfg_on(key, default)     -- on/off switches: on | off | yes | no | true | false | 1 | 0
  local v = (CFG[key] or ''):lower()
  if v == '' then return default end
  return v == 'on' or v == 'yes' or v == 'true' or v == '1'
end

-- the glob pet (lua/glob/<pet>.lua) perches on the first card; `glob = off` hides it,
-- `glob = random` is a pet of the day, `glob = scene` matches the wallpaper (lua/glob/pick.lua)
local PICK = dofile(ROOT .. 'lua/glob/pick.lua')
local function pet_for(cfg) return PICK.resolve(cfg.glob, cfg.scene, os.time()) end
local PET = pet_for(CFG)
if PET ~= 'off' then
  local pf = io.open(ROOT .. 'lua/glob/' .. PET .. '.lua')
  if pf then pf:close() else PET = 'mimi' end          -- missing pet file: fall back to Mimi
end
local GLOB_ON = PET ~= 'off'
local TOP, GAP, PAD, R = GLOB_ON and 108 or 58, 14, 18, GLASS and 22 or 16

------------------------------------------------------------------ cards
-- Each card is a file in lua/cards/ (see lua/cards/README.md). CARDS is the order on screen;
-- `card_<id> = off` in living-sky.conf hides one (it isn't even loaded then, so it costs nothing).
local CARDS = {'clock', 'weather', 'calendar', 'media', 'cpu', 'memory', 'disks', 'gpu', 'battery', 'network'}
local CARD_DEFAULT_OFF = {calendar = true, media = true, disks = true, battery = true}   -- opt-in (screen space)

local ui = dofile(ROOT .. 'lua/lib/ui.lua')
local sys = dofile(ROOT .. 'lua/lib/sys.lua')
ui.setup{M = M, glass = GLASS}
local rrect, rgba, text = ui.rrect, ui.rgba, ui.text
local readf, now = sys.readf, sys.now

local cr                                -- the cairo context being drawn on (see use())
local S = {}                            -- shared live values: S.cpu_temp (cards and the pet use it)
-- what every card function receives (d): drawing kit, palette, system readers, data
-- d.demo is true only while `living-sky preview --demo` renders: cards then hide personal details
local D = {ui = ui, sys = sys, M = M, S = S, cache = SKYDIR, q = q, glass = GLASS, cfg = CFG, demo = false,
           tick = 0, dt = 1, sky = nil, wx = nil, cr = nil}
local function use(c) cr = c; ui.begin(c); D.cr = c end

local card_err = {}
local function card_fail(c, what, err)  -- log a card's error once to ~/.cache/living-sky/cards.err
  local key = c.id .. what .. tostring(err)
  if card_err[key] then return end
  card_err[key] = true
  local f = io.open(SKYDIR .. 'cards.err', 'a')
  if f then f:write(os.date('%F %T '), c.id, ' ', what, ': ', tostring(err), '\n'); f:close() end
end

local ACTIVE = {}                       -- loaded, enabled cards in screen order

-- screen order: `cards = a, b, c` in living-sky.conf first, then any others in CARDS order
local function card_order()
  local known, order, seen = {}, {}, {}
  for _, id in ipairs(CARDS) do known[id] = true end
  for id in (CFG.cards or ''):lower():gmatch('[%w_]+') do
    if not known[id] then card_fail({id = id}, 'order', 'unknown card id in `cards =` (have: ' .. table.concat(CARDS, ', ') .. ')')
    elseif not seen[id] then order[#order + 1] = id; seen[id] = true end
  end
  for _, id in ipairs(CARDS) do if not seen[id] then order[#order + 1] = id end end
  return order
end

local report = {}                       -- hidden cards and why, for ~/.cache/living-sky/detected
local detected_write
local function cards_load()
  sys.scan()
  for _, id in ipairs(card_order()) do
    local why
    if not cfg_on('card_' .. id, not CARD_DEFAULT_OFF[id]) then why = 'off in living-sky.conf'
    else
      local ok, c = pcall(dofile, ROOT .. 'lua/cards/' .. id .. '.lua')
      if ok and type(c) == 'table' then
        c.id = c.id or id
        if c.init then
          local ok2, r = pcall(c.init, D)
          if not ok2 then card_fail(c, 'init', r); why = 'error in init (see cards.err)'
          elseif r == false then why = 'not available on this machine' end
        end
        if not why then ACTIVE[#ACTIVE + 1] = c end
      else
        card_fail({id = id}, 'load', c); why = 'failed to load (see cards.err)'
      end
    end
    if why then report[#report + 1] = string.format('  %-8s hidden: %s', id, why) end
  end
  detected_write()
end

-- what was detected, for `living-sky doctor` (rewritten at the 10th sample, when e.g. the GPU name is known)
function detected_write()
  local f = io.open(SKYDIR .. 'detected', 'w')
  if f then
    f:write(string.format('style %s · screen %dx%d · pet %s · colors %s\n', STYLE, SW, SH, PET, CFG.colors or 'auto'))
    f:write('cards (in order):\n')
    for _, c in ipairs(ACTIVE) do
      local ok, sub = pcall(function() return type(c.subtitle) == 'function' and c.subtitle(D) or c.subtitle end)
      f:write(string.format('  %-8s shown%s\n', c.id, (ok and sub and sub ~= '') and ('  (' .. tostring(sub) .. ')') or ''))
    end
    for _, l in ipairs(report) do f:write(l, '\n') end
    local hw = {}
    for k in pairs(sys.HW) do if k ~= 'cpu' then hw[#hw + 1] = k end end
    table.sort(hw)
    f:write('sensors (hwmon): ', table.concat(hw, ', '), '\n')
    f:write('cpu sensor: ', sys.HW.cpu_input or 'none', '\n')
    f:write('battery: ', sys.PS.bat or 'none', ' · ac: ', sys.PS.ac or 'none', '\n')
    f:close()
  end
end

local prev_t
local function sample_all()             -- once per second
  if not prev_t then cards_load() end
  local t = sys.now()
  D.dt = prev_t and math.max(0.2, t - prev_t) or 1
  prev_t = t
  D.tick = D.tick + 1
  S.cpu_temp = sys.cpu_temp()
  S.cpu_load = sys.PN('${cpu cpu0}')          -- % busy (Ember's fire follows it)
  if D.tick == 10 then detected_write() end
  for _, c in ipairs(ACTIVE) do
    if c.sample then
      local ok, err = pcall(c.sample, D)
      if not ok then card_fail(c, 'sample', err) end
    end
  end
end

------------------------------------------------------------------ card frame (panel + header)
local heights = {}
local cards_min_x = COL_X              -- left edge of the leftmost card column drawn so far
local rects, last_rects = {}, {}   -- card rects this frame / last frame (pet perches)

local FROST_SRC = nil       -- cairo surface of the current frost backdrop (set per frame)
local function glass_style()
  local light = (M.flavour_light == true)
  if light then
    return { tint = {1, 1, 1}, tint_a1 = 0.30, tint_a2 = 0.12, sheen = 0.40, rim_hi = 0.95, rim_mid = 0.18,
             rim_lo = 0.55, inner = 0.10, shadow_a = 0.12, refr = {2, 4, 7} }
  end
  return { tint = {M.base[1], M.base[2], M.base[3]}, tint_a1 = 0.08, tint_a2 = 0.26, sheen = 0.09, rim_hi = 0.42,
           rim_mid = 0.05, rim_lo = 0.20, inner = 0.35, shadow_a = 0.32, refr = {2, 4, 7} }
end

-- set the frost backdrop as the source, mapped like the zoomed wallpaper
local function frost_source()
  cairo_translate(cr, ZX, ZY); cairo_scale(cr, ZK, ZK)
  cairo_set_source_surface(cr, FROST_SRC, 0, 0)       -- the pattern keeps this transform
  cairo_scale(cr, 1 / ZK, 1 / ZK); cairo_translate(cr, -ZX, -ZY)
end

-- paint the frost backdrop magnified around the pane centre so that, inside a ring of
-- width e at the edge, the background is pulled inward by d px (cheap lens refraction)
local function refract_ring(x, y, w, h, r, e, d)
  local cx, cy, hw, hh = x + w / 2, y + h / 2, w / 2, h / 2
  cairo_save(cr)
  cairo_new_path(cr)
  rrect(x, y, w, h, r); rrect(x + e, y + e, w - 2 * e, h - 2 * e, math.max(2, r - e))
  cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD); cairo_clip(cr)
  cairo_translate(cr, cx, cy); cairo_scale(cr, hw / (hw - d), hh / (hh - d)); cairo_translate(cr, -cx, -cy)
  frost_source(); cairo_paint(cr)
  cairo_restore(cr)
end

local function glass_panel(x, y, w, h, r)
  local st = glass_style()
  -- soft, wide shadow (a few stacked layers)
  for i = 1, 4 do
    rrect(x - i + 1, y + 1 + i * 1.5, w + 2 * i - 2, h + i, r + i)
    rgba(M.shadow, st.shadow_a / (i + 0.6)); cairo_fill(cr)
  end
  cairo_save(cr)
  rrect(x, y, w, h, r); cairo_clip(cr)
  if FROST_SRC then
    frost_source(); cairo_paint(cr)
    for i, e in ipairs({14, 8, 4}) do refract_ring(x, y, w, h, r, e, st.refr[i]) end
  else  -- no frost yet: plain translucent body
    rgba(M.base, 0.88); cairo_paint(cr)
  end
  -- tint (lighter at the top for light glass, deeper at the bottom for dark glass)
  local t = st.tint
  local g = cairo_pattern_create_linear(0, y, 0, y + h)
  cairo_pattern_add_color_stop_rgba(g, 0, t[1], t[2], t[3], st.tint_a1)
  cairo_pattern_add_color_stop_rgba(g, 1, t[1], t[2], t[3], st.tint_a2)
  cairo_set_source(cr, g); cairo_paint(cr); cairo_pattern_destroy(g)
  -- specular sheen from the top-left
  g = cairo_pattern_create_radial(x + w * 0.22, y - h * 0.15, 0, x + w * 0.22, y - h * 0.15, math.max(w, h) * 0.75)
  cairo_pattern_add_color_stop_rgba(g, 0, 1, 1, 1, st.sheen)
  cairo_pattern_add_color_stop_rgba(g, 1, 1, 1, 1, 0)
  cairo_set_source(cr, g); cairo_paint(cr); cairo_pattern_destroy(g)
  cairo_restore(cr)
  -- inner shade along the lower edge (gives the pane thickness)
  rrect(x + 1.5, y + 1.5, w - 3, h - 3, r - 1.5)
  g = cairo_pattern_create_linear(0, y, 0, y + h)
  cairo_pattern_add_color_stop_rgba(g, 0.55, M.shadow[1], M.shadow[2], M.shadow[3], 0)
  cairo_pattern_add_color_stop_rgba(g, 1, M.shadow[1], M.shadow[2], M.shadow[3], st.inner)
  cairo_set_source(cr, g); cairo_set_line_width(cr, 2); cairo_stroke(cr); cairo_pattern_destroy(g)
  -- lit rim: bright top-left, dim middle, softer bottom-right catch-light
  rrect(x + 0.5, y + 0.5, w - 1, h - 1, r - 0.5)
  g = cairo_pattern_create_linear(x, y, x + w * 0.6, y + h * 1.4)
  cairo_pattern_add_color_stop_rgba(g, 0, 1, 1, 1, st.rim_hi)
  cairo_pattern_add_color_stop_rgba(g, 0.35, 1, 1, 1, st.rim_mid)
  cairo_pattern_add_color_stop_rgba(g, 0.7, 1, 1, 1, st.rim_mid)
  cairo_pattern_add_color_stop_rgba(g, 1, 1, 1, 1, st.rim_lo)
  cairo_set_source(cr, g); cairo_set_line_width(cr, 1.2); cairo_stroke(cr); cairo_pattern_destroy(g)
end

local function solid_panel(x, y, w, h, r)        -- the cards style
  rrect(x + 2, y + 4, w, h, r); rgba(M.shadow, M.shadow_a); cairo_fill(cr)
  rrect(x, y, w, h, r)
  local g = cairo_pattern_create_linear(0, y, 0, y + h)
  cairo_pattern_add_color_stop_rgba(g, 0, M.base[1], M.base[2], M.base[3], M.glass_a1)
  cairo_pattern_add_color_stop_rgba(g, 1, M.mantle[1], M.mantle[2], M.mantle[3], M.glass_a2)
  cairo_set_source(cr, g); cairo_fill_preserve(cr); cairo_pattern_destroy(g)
  rgba(M.surface1, 0.55); cairo_set_line_width(cr, 1); cairo_stroke(cr)
end
local function val(v, c)                -- a card field may be a value or a function(d)
  if type(v) == 'function' then return v(D) end
  return v
end

-- draws one card: the panel, the optional header (icon chip, title, subtitle), then c.draw for the body.
-- The panel is sized from the body height the card returned last time (stable after the first frame).
local function card_frame(c, x, y)
  local w = COL_W
  local h = heights[c.id] or 120
  if GLASS then glass_panel(x, y, w, h, R) else solid_panel(x, y, w, h, R) end
  local cy = y + PAD
  local title = val(c.title, c)
  if title then
    local acc = val(c.accent, c)
    acc = type(acc) == 'string' and (M[acc] or M.accent) or acc or M.accent
    local icon = val(c.icon, c)
    icon = ui.I[icon] or icon or ''
    -- header: accent icon chip (glassy in the glass style), title, muted subtitle on the right
    if GLASS then
      rrect(x + PAD, cy - 2, 26, 26, 9); rgba(acc, 0.20); cairo_fill_preserve(cr)
      rgba({1, 1, 1}, M.flavour_light and 0.55 or 0.16); cairo_set_line_width(cr, 1); cairo_stroke(cr)
    else
      rrect(x + PAD, cy - 2, 26, 26, 8); rgba(acc, 0.16); cairo_fill(cr)
    end
    text(x + PAD + 13, cy + 17, icon, 15, acc, false, 'c', ui.ICON)
    text(x + PAD + 36, cy + 16, title, 12, M.text, true)
    local ok, sub = pcall(val, c.subtitle, c)
    if ok and sub and sub ~= '' then text(x + w - PAD, cy + 16, sub, 11, M.overlay1, false, 'r') end
    cy = cy + 40
  end
  local ok, used = pcall(c.draw, D, x + PAD, cy, w - 2 * PAD)
  if not ok then card_fail(c, 'draw', used); used = 20 end
  heights[c.id] = (cy - y) + (tonumber(used) or 0) + PAD - 4
  rects[#rects + 1] = {id = c.id, x = x, y = y, w = w, h = heights[c.id]}
  return y + heights[c.id] + GAP
end

------------------------------------------------------------------ living sky
-- core/sky.py renders a wallpaper + palette per time slot into ~/.cache/living-sky.
-- Every ~15 s we check the slot; when it changes we apply the palette and set
-- the GNOME background. Missing renders are launched in the background (nice 19),
-- and the next slot is pre-rendered during the last 3 minutes of the current one.
local sky = { applied = nil, info = nil, tick = 0, interval = 60, wall = nil, fails = 0, pre = nil,
              colors = 'auto', recolor = nil }   -- colors: living-sky.conf colour set, normalised like core/sky.py
-- the land in front of the sky (core/scenes.py); renders are cached as <slot>-<scene>.png (lake: <slot>.png)
local SCENES = {lake = true, forest = true, city = true, camp = true}
local function sky_settings()           -- from CFG (again whenever living-sky.conf changes)
  sky.interval = math.max(5, tonumber(CFG.interval_min or '') or 60)
  sky.scene = (CFG.scene or 'lake'):lower():gsub('%s', '')
  if not SCENES[sky.scene] then sky.scene = 'lake' end
  -- a season set by hand is part of the cache name too (auto: by date, no suffix); same rule as core/sky.py
  sky.season = (CFG.season or 'auto'):lower():gsub('%s', '')
  if not ({spring = true, summer = true, autumn = true, winter = true})[sky.season] then sky.season = nil end
  local c = (CFG.colors or ''):lower():gsub('%s', ''):gsub(';', ',')
  local sets = {auto = true, lavender = true, sakura = true, mint = true, peach = true, ocean = true}
  if not (sets[c] or c:match('^#%x%x%x%x%x%x,#%x%x%x%x%x%x$')) then c = 'auto' end   -- same rule as core/sky.py
  sky.colors = c
end
sky_settings()
local function exists(p) local f = io.open(p, 'r'); if f then f:close(); return true end; return false end
local function sky_now() return os.time() + (tonumber(readf(SKYDIR .. 'fake_offset') or '') or 0) end
local function slot_key(t)
  local d = os.date('*t', t)
  local m = math.floor((d.hour * 60 + d.min) / sky.interval) * sky.interval
  return string.format('%04d%02d%02d%02d%02d', d.year, d.month, d.day, math.floor(m / 60), m % 60)
    .. (sky.scene == 'lake' and '' or ('-' .. sky.scene)) .. (sky.season and ('-' .. sky.season) or '')
    .. (cfg_on('pixel', false) and '-px' or '')
    .. ((SW == 1920 and SH == 1200) and '' or string.format('-%dx%d', SW, SH))   -- same rule as core/sky.py
end
local function apply_palette(path)
  local ok, p = pcall(dofile, path)
  if not ok or type(p) ~= 'table' then return false end
  for k, v in pairs(p) do
    if type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') then M[k] = hex(v)
    elseif type(v) == 'number' and (k == 'shadow_a' or k == 'glass_a1' or k == 'glass_a2') then M[k] = v end
  end
  M.flavour_light = (p.flavour == 'latte')
  M.colors = p.colors or 'auto'      -- the colour setting (pets with no colour of their own use it)
  sky.info = p
  return true
end
local frost = { path = nil, img = nil, xs = nil, wait = 0 }
local function frost_drop()
  if frost.xs then cairo_surface_destroy(frost.xs) end
  if frost.img then cairo_surface_destroy(frost.img) end
  frost.xs, frost.img, frost.path = nil, nil, nil
end
local function frost_load(path)
  frost_drop()
  if not exists(path) then return false end
  local s = cairo_image_surface_create_from_png(path)
  if cairo_surface_status(s) ~= CAIRO_STATUS_SUCCESS then cairo_surface_destroy(s); return false end
  frost.img, frost.path = s, path
  set_art(cairo_image_surface_get_width(s), cairo_image_surface_get_height(s))
  return true
end
local function sky_spawn(args)
  os.execute('nice -n 19 python3 ' .. q(ROOT .. 'core/sky.py') .. ' ' .. args .. ' >>' .. q(SKYDIR .. 'render.log') .. ' 2>&1 &')
end
local wx = { data = nil, fetched_at = 0 }
local function weather_update()
  local t = os.time()
  if t - wx.fetched_at > 900 then          -- refresh every 15 min (keeps stale data offline)
    wx.fetched_at = t
    os.execute('nice -n 19 python3 ' .. q(ROOT .. 'core/weather.py') .. ' >>' .. q(SKYDIR .. 'weather.log') .. ' 2>&1 &')
  end
  local ok, d = pcall(dofile, SKYDIR .. 'weather.lua')
  if ok and type(d) == 'table' then wx.data = d end
end
local function sky_update()
  sky.tick = sky.tick - 1
  if sky.tick > 0 then return end
  sky.tick = 15
  weather_update()
  local now = sky_now()
  local key = slot_key(now)
  if key ~= sky.applied then
    local lua, png = SKYDIR .. key .. '.lua', SKYDIR .. key .. '.png'
    if exists(lua) and exists(png) and apply_palette(lua) then
      sky.applied, sky.wall, sky.fails = key, png, 0
      if (sky.info.colors or 'auto') ~= sky.colors and sky.recolor ~= key then
        sky.recolor = key                 -- colour setting changed: sky.py rewrites just the palette
        sky_spawn('--now')
      end
      local cf = io.open(SKYDIR .. 'current', 'w')            -- start.sh shows this at login
      if cf then cf:write(key .. '\n'); cf:close() end
      if GLASS and not frost_load(SKYDIR .. key .. '-frost.png') then sky_spawn('--now'); frost.wait = 8 end
      local uri = q('file://' .. png)
      os.execute(string.format("(gsettings set org.gnome.desktop.background picture-uri %s;"
        .. " gsettings set org.gnome.desktop.background picture-uri-dark %s;"
        .. " gsettings set org.gnome.desktop.background picture-options zoom) >/dev/null 2>&1 &", uri, uri))
    else
      os.execute('mkdir -p ' .. q(SKYDIR))
      sky_spawn('--now')
      sky.fails = sky.fails + 1
      sky.tick = sky.fails > 6 and 600 or 5     -- back off if rendering keeps failing
    end
  else
    if sky.recolor == key and (sky.info.colors or 'auto') ~= sky.colors then     -- recoloured palette ready?
      local lua = SKYDIR .. key .. '.lua'
      local f = io.open(lua); local txt = f and f:read('*a') or ''; if f then f:close() end
      if txt:find('colors = "' .. sky.colors .. '"', 1, true) then apply_palette(lua) end
    end
    if GLASS and not frost.path and frost.wait > 0 then          -- backfilled frost for an older render
      frost.wait = frost.wait - 1
      frost_load(SKYDIR .. key .. '-frost.png')
    end
    local nxt = slot_key(now + 180)
    if nxt ~= key and sky.pre ~= nxt and not exists(SKYDIR .. nxt .. '.lua') then
      sky.pre = nxt
      sky_spawn('--now --next')
    end
  end
end

------------------------------------------------------------------ glob (the pet)
local GLOB
local function glob_load()
  if not GLOB_ON then return end
  local ok, m = pcall(dofile, ROOT .. 'lua/glob/' .. PET .. '.lua')
  if ok and type(m) == 'table' then GLOB = m end
end
glob_load()
local music = { n = 0, on = false, away = false, force = nil }
local PRESENCE = SKYDIR .. 'presence'
-- core/glob-presence.py: event-driven (D-Bus) "playing" + "away" flags; we only read its file.
local function presence_daemon()
  local pid = readf(SKYDIR .. 'presence.pid')
  local f = pid and pid:match('^%d+$') and io.open('/proc/' .. pid .. '/cmdline')
  local alive = false
  if f then alive = (f:read('*a') or ''):find('glob%-presence') ~= nil; f:close() end
  if not alive then
    os.execute('nice -n 10 python3 ' .. q(ROOT .. 'core/glob-presence.py') .. ' >/dev/null 2>&1 &')
  end
end
local function presence_read()           -- every frame (tiny file, changes only on events)
  if not GLOB then return end
  local f = io.open(PRESENCE)
  if f then
    local s = f:read('*a') or ''; f:close()
    local playing = s:find('playing 1') ~= nil
    music.media = s:match('media (%a+)')
    music.on = playing and (music.media == 'music' or music.media == nil)
    music.video = playing and music.media == 'video'
    music.away = s:find('away 1') ~= nil
    music.app = s:match('app (%a+)')
    music.typing = s:find('typing 1') ~= nil
    music.kbd = s:match('kbd (%a+)')           -- xi2 | record: the helper sees every keyboard
  end
  local cf = io.open(SKYDIR .. 'glob_cmd')           -- clicks from the panel extension
  if cf then
    local id, verb = (cf:read('*l') or ''):match('^(%d+)%s+(%a+)')
    cf:close()
    music.cmd = id and {id = id, verb = verb} or nil
  end
end
local function music_poll()              -- 1 Hz: keep the presence helper alive, read test overrides
  if not GLOB then return end
  music.n = music.n + 1
  if music.n % 30 == 1 then presence_daemon() end
  local ff = io.open(SKYDIR .. 'glob_force')
  if ff then music.force = ff:read('*a'); ff:close() else music.force = nil end
end
-- typing: from the presence helper (XInput2 / RECORD: any keyboard, only "a key went down"),
-- else the laptop keyboard's i8042 interrupt counter (counts key events only, never which keys);
-- "typing" stays on for 1.5 s after the last key press
local kbd = { n = nil, last = -100, ok = true }
local function kbd_typing(tnow)
  local fake = readf(SKYDIR .. 'kbd_fake')        -- testing: a number here replaces the real counter
  if fake then
    local n = tonumber(fake) or 0
    if kbd.n and n ~= kbd.n then kbd.last = tnow end
    kbd.n = n
    return tnow - kbd.last < 1.5
  end
  if music.kbd == 'xi2' or music.kbd == 'record' then return music.typing end
  if not kbd.ok then return false end
  local f = io.open('/proc/interrupts')
  if not f then kbd.ok = false; return false end
  local n
  for l in f:lines() do
    local rest = l:match('^%s*1:(.*)')
    if rest then
      if rest:find('i8042') then
        n = 0
        for tok in rest:gmatch('%S+') do local v = tonumber(tok); if not v then break end; n = n + v end
      end
      break
    end
  end
  f:close()
  if not n then kbd.ok = false; return false end
  if kbd.n and n ~= kbd.n then kbd.last = tnow end
  kbd.n = n
  return tnow - kbd.last < 1.5
end

local glob_err
local function gcall(fn, ctx)             -- run a pet step; log the first error to the cache dir
  local ok, err = pcall(fn, ctx)
  if not ok and err ~= glob_err then
    glob_err = err
    local f = io.open(SKYDIR .. 'glob.err', 'w'); if f then f:write(tostring(err), '\n'); f:close() end
  end
  return ok
end
local function glob_begin()                -- update the pet; nil when disabled / failing
  if not GLOB then return nil end
  local mctx = {cr = cr, M = M, t = now(), clock = os.date('*t'), sky = sky.info, wx = wx.data, music = music.on, away = music.away, typing = kbd_typing(now()),
                media = music.video and 'video' or (music.on and 'music' or nil), app = music.app, cmd = music.cmd,
                cpu_temp = S.cpu_temp, cpu_load = S.cpu_load,
                force = music.force, cards = last_rects, col_x = COL_X, text = text, ICON = ui.ICON,
                state_path = SKYDIR .. 'glob_state'}
  if gcall(GLOB.update, mctx) then return mctx end
  return nil
end

------------------------------------------------------------------ draw
local function draw()
  local fo = cairo_font_options_create()
  cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_GRAY)
  cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_SLIGHT)
  cairo_set_font_options(cr, fo)
  D.sky, D.wx = sky.info, wx.data
  D.time = sky_now()                    -- wall clock (+ the test offset in ~/.cache/living-sky/fake_offset)
  rects = {}
  local x, y = COL_X, TOP
  for _, c in ipairs(ACTIVE) do
    local ok, vis = true, true
    if c.visible then ok, vis = pcall(c.visible, D) end
    if ok and vis then
      if y > TOP and y + (heights[c.id] or 120) > SH - 12 then     -- full: continue in a column to the left
        x, y = x - COL_W - 24, TOP
      end
      cards_min_x = math.min(cards_min_x, x)
      y = card_frame(c, x, y)
    end
  end
  last_rects = rects
  cairo_font_options_destroy(fo)
end


------------------------------------------------------------------ living-sky.conf changes
-- Checked every 5 s. Settings that only change how things are drawn apply in place (cards read d.cfg each
-- frame; scene / season / pixel / interval / colors pick the matching render); anything that changes what
-- is loaded (style, pet, which cards, location) restarts living-sky, from a detached shell.
local LIVE = {units = true, clock = true, week_start = true, colors = true, scene = true, season = true,
              pixel = true, interval_min = true}
local conf_tick = 5
local function conf_watch()
  conf_tick = conf_tick - 1
  if conf_tick > 0 then return end
  conf_tick = 5
  local new, txt = conf_read()
  local restart = 'setsid -f ' .. q(ROOT .. 'bin/living-sky') .. ' restart >/dev/null 2>&1 < /dev/null'
  if txt == CFG_TEXT then
    if pet_for(CFG) ~= PET then os.execute(restart); conf_tick = 60 end    -- glob = random: a new day
    return
  end
  CFG_TEXT = txt
  local live_only = pet_for(new) == PET              -- glob = scene: a new scene can mean a new pet
  for _, t in ipairs({new, CFG}) do
    for k in pairs(t) do
      if (new[k] or '') ~= (CFG[k] or '') and not LIVE[k] then live_only = false end
    end
  end
  if not live_only then
    os.execute(restart)
    conf_tick = 60
    return
  end
  for k in pairs(CFG) do CFG[k] = nil end
  for k, v in pairs(new) do CFG[k] = v end
  sky_settings()
  sky.applied, sky.recolor, sky.tick = nil, nil, 0       -- pick (or render) the matching wallpaper now
end

------------------------------------------------------------------ main
local last_sample = -10
local card_layer                       -- offscreen copy of the card column
local LAYER_X = COL_X - 140
function conky_living_sky_main()
  if conky_window == nil then return end
  if (tonumber(conky_parse('${updates}')) or 0) < 2 then return end
  -- conky redraws ~4x/s (smooth pet animation); system sampling stays at 1 Hz
  local tnow = now()
  local fresh = false
  if tnow - last_sample >= 0.95 then
    last_sample, fresh = tnow, true
    sample_all()
    conf_watch()
    sky_update()
    music_poll()
  end
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
    conky_window.visual, conky_window.width, conky_window.height)
  if GLASS and frost.img and not frost.xs then
    local ok, xs = pcall(cairo_surface_create_similar, cs, CAIRO_CONTENT_COLOR, ART_W, ART_H)
    if ok and xs then
      local c2 = cairo_create(xs); cairo_set_source_surface(c2, frost.img, 0, 0); cairo_paint(c2); cairo_destroy(c2)
      frost.xs = xs
    end
  end
  FROST_SRC = frost.xs or frost.img
  -- the cards only change once per sample: render them into a cached layer then, and
  -- each frame just composite that layer plus the animated blob
  if not card_layer then
    local ok, ls = pcall(cairo_surface_create_similar, cs, CAIRO_CONTENT_COLOR_ALPHA, SW - LAYER_X, SH)
    if ok and ls then card_layer, fresh = ls, true end
  end
  if card_layer and cards_min_x - 140 < LAYER_X then   -- cards wrapped into another column: widen the layer
    cairo_surface_destroy(card_layer); card_layer = nil
    LAYER_X = math.max(0, cards_min_x - 140)
    local ok, ls = pcall(cairo_surface_create_similar, cs, CAIRO_CONTENT_COLOR_ALPHA, SW - LAYER_X, SH)
    if ok and ls then card_layer, fresh = ls, true end
  end
  if card_layer and fresh then
    use(cairo_create(card_layer))
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR); cairo_paint(cr); cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
    cairo_translate(cr, -LAYER_X, 0)
    draw()
    cairo_destroy(cr)
  end
  use(cairo_create(cs))
  presence_read()
  local mctx = glob_begin()
  if mctx and GLOB.export then                    -- state for the GNOME panel extension (written on change)
    gcall(function() GLOB.export(SKYDIR .. 'glob.json', M, sky.info, wx.data) end)
  end
  if mctx then gcall(GLOB.draw_behind, mctx) end
  if card_layer then cairo_set_source_surface(cr, card_layer, LAYER_X, 0); cairo_paint(cr) else draw() end
  if mctx then gcall(GLOB.draw_front, mctx) end
  cairo_destroy(cr); cairo_surface_destroy(cs); cr = nil

  local flag = SKYDIR .. 'preview-' .. STYLE
  local ff = io.open(flag, 'r')
  if ff then
    local req = ff:read('*a') or ''; ff:close(); os.remove(flag)
    D.demo = req:find('demo') ~= nil       -- `living-sky preview --demo`: placeholders for personal details
    glob_load()
    local wall = cairo_image_surface_create_from_png(sky.wall or (ROOT .. 'art/lake/wallpaper-static.png'))
    set_art(cairo_image_surface_get_width(wall), cairo_image_surface_get_height(wall))
    local img = cairo_image_surface_create(CAIRO_FORMAT_RGB24, SW, SH)
    use(cairo_create(img))                                 -- the wallpaper as GNOME shows it (zoom)
    cairo_translate(cr, ZX, ZY); cairo_scale(cr, ZK, ZK)
    cairo_set_source_surface(cr, wall, 0, 0); cairo_paint(cr)
    cairo_destroy(cr); cairo_surface_destroy(wall)
    FROST_SRC = frost.img
    use(cairo_create(img))
    local pm = glob_begin()
    if pm then gcall(GLOB.draw_behind, pm) end
    draw()
    if pm then pm.cr = cr; gcall(GLOB.draw_front, pm) end
    cairo_destroy(cr); cr = nil
    cairo_surface_write_to_png(img, flag .. '.png.tmp')
    cairo_surface_destroy(img)
    os.rename(flag .. '.png.tmp', flag .. '.png')
    local rf = io.open(flag .. '.rects', 'w')        -- where each card is, for tools/cardshots.sh
    if rf then
      for _, r in ipairs(last_rects) do rf:write(string.format('%s %d %d %d %d\n', r.id, r.x, r.y, r.w, r.h)) end
      rf:close()
    end
    D.demo = false
  end
end
