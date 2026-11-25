--[[
  ui: the drawing kit every card uses (cairo helpers, fonts, icons, formatting).
  The engine calls ui.setup{M = palette, glass = bool} once and ui.begin(cr) before drawing;
  cards then just call ui.text(...), ui.pill(...), etc. Colours are palette entries such as
  M.text or M.blue (tables {r, g, b, a}); the palette follows the sky, so never hard-code colours.
]]
local ui = {}
local cr, M, GLASS

ui.MONO, ui.ICON, ui.DISPLAY = 'JetBrains Mono', 'FiraCode Nerd Font Mono', 'Bebas Neue'

-- nerd-font (material design) glyphs used by the cards; add yours here
ui.I = {
  cpu = '\u{f4bc}', mem = '\u{f035b}', gpu = '\u{f061a}', disk = '\u{f02ca}',
  wifi = '\u{f05a9}', bat = '\u{f0079}', batchg = '\u{f0084}', fan = '\u{f0210}',
  rise = '\u{f059c}', set = '\u{f059b}',
  hum = '\u{f058e}', wind = '\u{f059d}', umbrella = '\u{f054a}',
  music = '\u{f075a}', play = '\u{f040a}', pause = '\u{f03e4}', calendar = '\u{f00ed}',
  battery = '\u{f0079}', heart = '\u{f02d1}', harddisk = '\u{f02ca}',
}
ui.WX = {        -- weather kind -> {day glyph, night glyph}
  clear = {'\u{f0599}', '\u{f0594}'}, partly = {'\u{f0595}', '\u{f0f31}'}, cloudy = {'\u{f0590}', '\u{f0590}'},
  fog = {'\u{f0591}', '\u{f0591}'}, rain = {'\u{f0597}', '\u{f0597}'}, pour = {'\u{f0596}', '\u{f0596}'},
  snow = {'\u{f0598}', '\u{f0598}'}, sleet = {'\u{f067f}', '\u{f067f}'}, storm = {'\u{f067e}', '\u{f067e}'},
}
ui.MOON = {      -- md-moon-* glyphs by phase name
  ['new moon'] = '\u{f0f64}', ['waxing crescent'] = '\u{f0f67}', ['first quarter'] = '\u{f0f61}',
  ['waxing gibbous'] = '\u{f0f68}', ['full moon'] = '\u{f0f62}', ['waning gibbous'] = '\u{f0f66}',
  ['last quarter'] = '\u{f0f63}', ['waning crescent'] = '\u{f0f65}',
}

function ui.setup(opts) M, GLASS = opts.M, opts.glass end
function ui.begin(c) cr = c end

------------------------------------------------------------------ primitives
function ui.rgba(c, a) cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4]) end

function ui.font(size, bold, fam)
  cairo_select_font_face(cr, fam or ui.MONO, CAIRO_FONT_SLANT_NORMAL,
    bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
end

local ext = cairo_text_extents_t:create()
function ui.twidth(s) cairo_text_extents(cr, s, ext); return ext.x_advance end   -- width in the current font

-- text at baseline y; align = nil (left) | 'r' (x is the right edge) | 'c' (x is the centre). Returns the width.
function ui.text(x, y, s, size, col, bold, align, fam)
  s = tostring(s or '')
  ui.font(size, bold, fam)
  local w = ui.twidth(s)
  if align == 'r' then x = x - w elseif align == 'c' then x = x - w / 2 end
  ui.rgba(col); cairo_move_to(cr, math.floor(x + 0.5), math.floor(y + 0.5)); cairo_show_text(cr, s)
  return w
end

-- shorten s with an ellipsis so it fits in maxw px at this font size
function ui.fit(s, maxw, size, bold, fam)
  s = tostring(s or '')
  ui.font(size, bold, fam)
  if ui.twidth(s) <= maxw then return s end
  local chars = {}
  for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars + 1] = ch end   -- UTF-8 aware
  local lo, hi = 0, #chars
  while lo < hi do                      -- longest prefix that fits with the ellipsis
    local mid = math.ceil((lo + hi) / 2)
    if ui.twidth(table.concat(chars, '', 1, mid) .. '…') <= maxw then lo = mid else hi = mid - 1 end
  end
  return table.concat(chars, '', 1, lo) .. '…'
end

function ui.rrect(x, y, w, h, r)        -- rounded-rectangle path (fill / stroke it yourself)
  cairo_new_sub_path(cr)
  cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
  cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
  cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
  cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
  cairo_close_path(cr)
end

------------------------------------------------------------------ widgets
-- progress bar: a rounded track with a gradient fill for frac (0..1)
function ui.pill(x, y, w, h, frac, col)
  frac = math.max(0, math.min(1, frac or 0))
  ui.rrect(x, y, w, h, h / 2); if GLASS then ui.rgba(M.surface1, 0.85) else ui.rgba(M.surface0) end; cairo_fill(cr)
  if frac > 0 then
    local fw = math.max(h, w * frac)
    local g = cairo_pattern_create_linear(x, 0, x + fw, 0)
    cairo_pattern_add_color_stop_rgba(g, 0, col[1], col[2], col[3], 0.55)
    cairo_pattern_add_color_stop_rgba(g, 1, col[1], col[2], col[3], 1)
    ui.rrect(x, y, fw, h, h / 2); cairo_set_source(cr, g); cairo_fill(cr)
    cairo_pattern_destroy(g)
  end
end

-- sparkline of a history list (see ui.push), scaled to maxv, with a soft fill underneath
function ui.spark(x, y, w, h, hist, maxv, col)
  local n = #hist
  if n < 2 then return end
  if not maxv or maxv <= 0 then maxv = 1 end
  local step = w / (n - 1)
  local function pt(i, v) return x + (i - 1) * step, y + h - h * math.min(1, v / maxv) end
  cairo_move_to(cr, x, y + h)
  for i, v in ipairs(hist) do cairo_line_to(cr, pt(i, v)) end
  cairo_line_to(cr, x + w, y + h); cairo_close_path(cr)
  local g = cairo_pattern_create_linear(0, y, 0, y + h)
  cairo_pattern_add_color_stop_rgba(g, 0, col[1], col[2], col[3], 0.35)
  cairo_pattern_add_color_stop_rgba(g, 1, col[1], col[2], col[3], 0.0)
  cairo_set_source(cr, g); cairo_fill(cr); cairo_pattern_destroy(g)
  cairo_move_to(cr, pt(1, hist[1]))
  for i, v in ipairs(hist) do cairo_line_to(cr, pt(i, v)) end
  ui.rgba(col); cairo_set_line_width(cr, 1.5); cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND); cairo_stroke(cr)
end

-- "key ........ value" row: muted key on the left, value right-aligned
function ui.kv(x, y, w, k, v, vc)
  ui.text(x, y, k, 11, M.overlay1)
  ui.text(x + w, y, v, 11, vc or M.text, false, 'r')
end

function ui.divider(x, y, w)            -- thin separator line inside a card
  if GLASS then ui.rgba(M.surface1, 0.8) else ui.rgba(M.surface0) end
  cairo_rectangle(cr, x, y, w, 1); cairo_fill(cr)
end

-- colour by level: base below warn, peach from warn, red from crit
function ui.lvl(v, warn, crit, base)
  if v >= crit then return M.red elseif v >= warn then return M.peach end
  return base or M.green
end

------------------------------------------------------------------ data helpers
function ui.push(hist, v, n)            -- append to a history list, keep the last n values
  hist[#hist + 1] = v
  while #hist > n do table.remove(hist, 1) end
end

function ui.human(kib)                  -- 1536 -> "2 MiB"
  if kib >= 1048576 then return string.format('%.1f GiB', kib / 1048576) end
  if kib >= 1024 then return string.format('%.0f MiB', kib / 1024) end
  return string.format('%.0f KiB', kib)
end

-- "HH:MM" -> "h:MM am" when clock == '12h' (sunrise / sunset strings from core/sky.py)
function ui.hm(s, clock)
  if clock ~= '12h' or type(s) ~= 'string' then return s end
  local h, m = s:match('^(%d+):(%d+)$')
  if not h then return s end
  h = tonumber(h)
  local ap = h < 12 and 'am' or 'pm'
  h = h % 12
  return string.format('%d:%s %s', h == 0 and 12 or h, m, ap)
end

-- temperature (°C in the data) and wind (km/h) for display, per `units` in living-sky.conf
function ui.temp(c, units)
  if units == 'imperial' then return c * 9 / 5 + 32 end
  return c
end
function ui.wind(kmh, units)
  if units == 'imperial' then return kmh * 0.621371, 'mph' end
  return kmh, 'km/h'
end

function ui.rate(kib)                   -- KiB/s -> "1.2 MiB/s"
  if kib >= 1024 then return string.format('%.1f MiB/s', kib / 1024) end
  if kib < 10 then return string.format('%.1f KiB/s', kib) end
  return string.format('%.0f KiB/s', kib)
end

return ui
