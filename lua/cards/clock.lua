--[[
  Clock card: big time, weekday, date, uptime; footer: battery (or the host name on desktops) and OS · kernel.
  No header row (title = nil). The glob pet sits on the first card shown, usually this one.
  Options: clock = 24h | 12h. Weekday and month names follow the system locale (LC_TIME).
  The card contract is described in lua/cards/README.md.
]]
local C = {id = 'clock', accent = 'accent'}
local st = {}

function C.init(d)
  st.os = (d.sys.cmd('{ . /etc/os-release || . /usr/lib/os-release; } 2>/dev/null; echo "$PRETTY_NAME"') or 'Linux'):gsub(' LTS', '')
  st.kernel = d.sys.P('${kernel}'):gsub('%-generic', '')
  st.host = d.sys.P('${nodename}')
end

function C.sample(d)
  local up = d.sys.now()
  local dd, h, m = math.floor(up / 86400), math.floor(up % 86400 / 3600), math.floor(up % 3600 / 60)
  st.up = (dd > 0 and (dd .. 'd ') or '') .. h .. 'h ' .. m .. 'm'
end

function C.draw(d, x, cy, w)
  local ui, M, sys = d.ui, d.M, d.sys
  local t = d.time or os.time()
  local tw
  if (d.cfg.clock or ''):lower() == '12h' then
    tw = ui.text(x - 2, cy + 62, (os.date('%I:%M', t):gsub('^0', '')), 78, M.accent, false, nil, ui.DISPLAY)
    tw = tw + 3 + ui.text(x + tw + 1, cy + 62, os.date('%H', t) < '12' and 'AM' or 'PM', 13, M.accent2, true)
  else
    tw = ui.text(x - 2, cy + 62, os.date('%H:%M', t), 78, M.accent, false, nil, ui.DISPLAY)
  end
  local dx = x + tw + 16
  ui.text(dx, cy + 22, os.date('%A', t):upper(), 13, M.accent2, true)
  ui.text(dx, cy + 40, os.date('%d %B %Y', t), 12, M.text)
  ui.text(dx, cy + 58, 'up ' .. (st.up or ''), 11, M.overlay1)
  ui.divider(x, cy + 78, w)
  -- footer: battery, or the host name when there is none
  local B = sys.PS.bat
  if B then
    local ac = sys.on_ac()
    local cap = sys.readn(B .. 'capacity') or 0
    local bcol = cap <= 15 and M.red or (cap <= 30 and M.peach or M.green)
    local watts = (sys.readn(B .. 'current_now') or 0) * (sys.readn(B .. 'voltage_now') or 0) / 1e12
    if watts == 0 then watts = (sys.readn(B .. 'power_now') or 0) / 1e6 end
    ui.text(x, cy + 99, ac and ui.I.batchg or ui.I.bat, 14, bcol, false, nil, ui.ICON)
    local bw = ui.text(x + 18, cy + 98, cap .. '%', 11, bcol, true)
    ui.text(x + 22 + bw, cy + 98, ac and '· on AC' or (watts > 0.1 and string.format('· %.1f W', watts) or ''), 11, M.subtext0)
  else
    ui.text(x, cy + 98, d.demo and 'my-pc' or st.host or '', 11, M.subtext0)
  end
  ui.text(x + w, cy + 98, (st.os or '') .. ' · ' .. (st.kernel or ''), 11, M.overlay0, false, 'r')
  return 104
end

return C
