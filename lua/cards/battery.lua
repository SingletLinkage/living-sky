--[[
  Battery: charge with a bar, charging state, health (how much of its design capacity it still holds),
  charge cycles, power draw and the time to empty / full. Hidden on machines without a battery.
  Reads /sys/class/power_supply/<battery>/ (charge_* or energy_*, current_now or power_now).
]]
local C = {id = 'battery', title = 'BATTERY', icon = 'battery', accent = 'green'}
local st = {}

local function n(f) return C.sys.readn(C.bat .. f) end

function C.init(d)
  C.sys, C.bat = d.sys, d.sys.PS.bat
  return C.bat ~= nil
end

function C.sample(d)
  local s = {}
  s.cap = n('capacity') or 0
  s.status = d.sys.readf(C.bat .. 'status') or ''
  local full, design = n('charge_full') or n('energy_full'), n('charge_full_design') or n('energy_full_design')
  s.health = (full and design and design > 0) and math.floor(100 * full / design + 0.5) or nil
  s.cycles = n('cycle_count')
  -- power (W): power_now (µW), or current_now (µA) x voltage_now (µV)
  local p = n('power_now')
  if p then s.watts = p / 1e6
  else s.watts = (n('current_now') or 0) * (n('voltage_now') or 0) / 1e12 end
  -- time left: remaining (or missing) charge / current flow
  local now_c, cur = n('charge_now'), n('current_now')
  local now_e = n('energy_now')
  local hours
  if s.status == 'Discharging' then
    if now_c and cur and cur > 0 then hours = now_c / cur
    elseif now_e and p and p > 0 then hours = now_e / p end
  elseif s.status == 'Charging' then
    if now_c and full and cur and cur > 0 then hours = (full - now_c) / cur
    elseif now_e and full and p and p > 0 then hours = (full - now_e) / p end
  end
  s.left = hours and hours > 0 and hours < 48 and hours or nil
  st.s = s
end

function C.subtitle() return st.s and st.s.status or '' end

function C.draw(d, x, cy, w)
  local ui, M, s = d.ui, d.M, st.s or {}
  local col = (s.cap or 0) <= 15 and M.red or ((s.cap or 0) <= 30 and M.peach or M.green)
  local nw = ui.text(x, cy + 26, s.cap or 0, 30, col, true)
  ui.text(x + nw + 3, cy + 26, '%', 13, M.overlay1)
  local right
  if s.left then
    right = string.format('%dh %02dm %s', math.floor(s.left), math.floor(s.left % 1 * 60),
      s.status == 'Charging' and 'to full' or 'left')
  else right = (s.status == 'Full' or s.status == 'Not charging') and 'on AC' or '' end
  ui.text(x + w, cy + 10, right, 11, M.text, true, 'r')
  ui.text(x + w, cy + 27, (s.watts or 0) > 0.1 and string.format('%.1f W', s.watts) or '', 11, M.subtext0, false, 'r')
  ui.pill(x, cy + 40, w, 6, (s.cap or 0) / 100, col)
  local hcol = not s.health and M.subtext0 or (s.health < 50 and M.red or (s.health < 80 and M.peach or M.text))
  ui.kv(x, cy + 64, w, 'health', s.health and (s.health .. '% of design') or '—', hcol)
  ui.kv(x, cy + 82, w, 'cycles', s.cycles and tostring(s.cycles) or '—', M.subtext0)
  return 86
end

return C
