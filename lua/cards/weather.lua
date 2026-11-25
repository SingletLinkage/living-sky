--[[
  Weather card: temperature, conditions, feels-like, today's high / low, AQI, UV; a stats row
  (humidity, rain chance, cloud cover, wind); sunrise / sunset and the moon phase.
  Data: d.wx (core/weather.py, refreshed by the engine every 15 min) and d.sky (the sky slot's
  palette file: sunrise, sunset, moon). The card hides itself until the first weather fetch.
  Options: units = metric | imperial (display only: the data stays metric for the sky and the pet),
  clock = 24h | 12h (sunrise / sunset).
]]
local C = {id = 'weather', title = 'WEATHER', accent = 'sky'}

function C.visible(d) return d.wx ~= nil end

function C.icon(d)
  local wd = d.wx
  return (d.ui.WX[wd.kind] or d.ui.WX.cloudy)[wd.day and 1 or 2]
end

function C.subtitle(d)                  -- place, plus the data's age when it's stale (offline)
  local wd = d.wx
  local age = os.time() - (wd.fetched or 0)
  return (d.demo and 'Somewhere' or wd.place or '') .. (age > 3 * 3600 and string.format(' · %dh old', math.floor(age / 3600)) or '')
end

function C.draw(d, x, cy, w)
  local ui, M, wd = d.ui, d.M, d.wx
  local units, clock = (d.cfg.units or ''):lower(), (d.cfg.clock or ''):lower()
  local function deg(c) return math.floor(ui.temp(c or 0, units) + 0.5) end
  local tw = ui.text(x, cy + 26, string.format('%d°', deg(wd.temp)), 30, M.sky, true)
  local tx = x + tw + 14
  ui.text(tx, cy + 10, wd.text or '', 12, M.text, true)
  ui.text(tx, cy + 27, string.format('feels %d°  ·  %d° / %d°', deg(wd.feels), deg(wd.hi), deg(wd.lo)), 11, M.subtext0)
  if (wd.aqi or -1) >= 0 then
    local a = wd.aqi
    local acol = a <= 50 and M.green or a <= 100 and M.yellow or a <= 150 and M.peach or a <= 200 and M.red or M.mauve
    ui.text(x + w, cy + 10, 'AQI ' .. a, 11, acol, true, 'r')
  end
  ui.text(x + w, cy + 27, string.format('UV %.0f', wd.uv or 0), 11, M.overlay1, false, 'r')

  -- stats row: humidity, rain chance, cloud cover, wind; first flush left, last flush right, equal gaps
  local dirs = {'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'}
  local dir = dirs[math.floor(((wd.wdir or 0) + 22.5) / 45) % 8 + 1]
  local sy = cy + 52
  local items = {
    {ui.I.hum, M.sapphire, string.format('%d%%', math.floor(wd.hum or 0))},
    {ui.I.umbrella, M.blue, string.format('%d%%', math.floor(wd.pop or 0))},
    {ui.WX.cloudy[1], M.lavender, string.format('%d%%', math.floor(wd.cloud or 0))},
    {ui.I.wind, M.teal, string.format('%d %s', math.floor(ui.wind(wd.wind or 0, units) + 0.5), dir)},
  }
  ui.font(11, false)
  local total = 0
  for _, it in ipairs(items) do it.w = 18 + ui.twidth(it[3]); total = total + it.w end
  local gap, ix = (w - total) / (#items - 1), x
  for _, it in ipairs(items) do
    ui.text(ix, sy + 1, it[1], 13, it[2], false, nil, ui.ICON)
    ui.text(ix + 18, sy, it[3], 11, M.text)
    ix = ix + it.w + gap
  end

  -- sun / moon row
  local si = d.sky
  if not si then return 60 end
  ui.divider(x, sy + 12, w)
  local ry = sy + 32
  ix = x
  ui.text(ix, ry + 1, ui.I.rise, 14, M.yellow, false, nil, ui.ICON)
  ix = ix + 20 + ui.text(ix + 20, ry, ui.hm(si.sunrise, clock) or '--:--', 11, M.text)
  ui.text(ix + 12, ry + 1, ui.I.set, 14, M.peach, false, nil, ui.ICON)
  ui.text(ix + 32, ry, ui.hm(si.sunset, clock) or '--:--', 11, M.text)
  local ph = si.moon_phase or ''
  local pw = ui.text(x + w, ry, ph .. ' ' .. (si.moon_illum or 0) .. '%', 11, M.text, false, 'r')
  ui.text(x + w - pw - 8, ry + 1, ui.MOON[ph] or '', 14, M.lavender, false, 'r', ui.ICON)
  return 92
end

return C
