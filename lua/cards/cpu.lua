--[[
  CPU card: total usage with a 48 s sparkline, package temperature, clock speed,
  one pill per thread (8 per row, up to 4 rows), fans (or the thread count) and load average.
  The CPU temperature comes from the engine (d.S.cpu_temp), because the pet uses it too.
]]
local C = {id = 'cpu', title = 'PROCESSOR', icon = 'cpu', accent = 'blue'}
local st = {cores = {}, hist = {}, fans = {}, prev = {}}

-- short model name: "13th Gen Intel(R) Core(TM) i7-13700HX" -> "i7-13700HX", "AMD Ryzen 7 5800H with ..." -> "Ryzen 7 5800H"
local function cpu_name()
  local f = io.open('/proc/cpuinfo'); if not f then return '' end
  local m
  for l in f:lines() do m = l:match('^model name%s*:%s*(.+)$'); if m then break end end
  f:close()
  if not m then return '' end
  m = m:gsub('%(R%)', ''):gsub('%(TM%)', ''):gsub('%s+@.*$', ''):gsub('%s+with%s.*$', '')
  m = m:gsub('%d+th Gen%s+', ''):gsub('Intel%s+Core%s+', ''):gsub('^Intel%s+', ''):gsub('^AMD%s+', '')
  m = m:gsub('%s+CPU', ''):gsub('%s+Processor', ''):gsub('%s+%d+%-Core', ''):gsub('%s+', ' ')
  return m
end

-- per-thread usage from /proc/stat deltas: [0] = total, [1..n] = threads
local function sample_cores()
  local out, prev = {}, st.prev
  local f = io.open('/proc/stat'); if not f then return out end
  for l in f:lines() do
    local id, rest = l:match('^cpu(%d*)%s+(.*)')
    if not id then break end
    local v, i = {}, 0
    for n in rest:gmatch('%d+') do i = i + 1; v[i] = tonumber(n) end
    local idle = v[4] + (v[5] or 0)
    local total = 0
    for k = 1, math.min(8, #v) do total = total + v[k] end
    local key = id == '' and 0 or (tonumber(id) + 1)
    local p = prev[key]
    if p then
      local dt, di = total - p[1], idle - p[2]
      out[key] = dt > 0 and math.max(0, math.min(100, 100 * (dt - di) / dt)) or 0
    else out[key] = 0 end
    prev[key] = {total, idle}
  end
  f:close(); return out
end

function C.init(d)
  st.name = cpu_name()
  for _, p in pairs(d.sys.HW) do                  -- up to two fans from any hwmon device
    for i = 1, 4 do
      if #st.fans < 2 and d.sys.readf(p .. '/fan' .. i .. '_input') then st.fans[#st.fans + 1] = p .. '/fan' .. i .. '_input' end
    end
  end
  table.sort(st.fans)
end

function C.subtitle() return st.name end

function C.sample(d)
  st.cores = sample_cores()
  d.ui.push(st.hist, st.cores[0] or 0, 48)
  st.freq = d.sys.PN('${freq_g}')
  local la = d.sys.readf('/proc/loadavg') or ''
  local a1, run, tot = la:match('^(%S+) %S+ %S+ (%d+)/(%d+)')
  st.load, st.tasks = a1 or '?', (tot or '?') .. ' threads · ' .. (run or '?') .. ' run'
  st.rpm = {}
  for i, p in ipairs(st.fans) do st.rpm[i] = string.format('%d', d.sys.readn(p) or 0) end
end

function C.draw(d, x, cy, w)
  local ui, M = d.ui, d.M
  local c = math.floor((st.cores[0] or 0) + 0.5)
  local col = ui.lvl(c, 60, 85, M.blue)
  local nw = ui.text(x, cy + 26, c, 30, col, true)
  ui.text(x + nw + 3, cy + 26, '%', 13, M.overlay1)
  ui.spark(x + 80, cy, w - 180, 28, st.hist, 100, col)
  local temp = d.S.cpu_temp or 0
  ui.text(x + w, cy + 10, string.format('%.0f°C', temp), 12, ui.lvl(temp, 80, 95, M.peach), true, 'r')
  ui.text(x + w, cy + 27, string.format('%.2f GHz', st.freq or 0), 11, M.subtext0, false, 'r')

  -- one pill per thread; beyond 32 threads neighbours are merged (max)
  local n = #st.cores
  local per = math.max(1, math.ceil(n / 32))
  local cells = math.ceil(n / per)
  local rows = math.max(1, math.ceil(cells / 8))
  local gap = 6
  local cw = (w - 7 * gap) / 8
  for i = 1, cells do
    local v, k0 = 0, (i - 1) * per
    for j = 1, per do v = math.max(v, st.cores[k0 + j] or 0) end
    local r, k = math.floor((i - 1) / 8), (i - 1) % 8
    ui.pill(x + k * (cw + gap), cy + 42 + r * 10, cw, 5, v / 100, ui.lvl(v, 60, 85, M.sapphire))
  end

  local fy = cy + 42 + rows * 10 + 18
  if #st.fans > 0 then
    ui.text(x, fy, ui.I.fan, 13, M.teal, false, nil, ui.ICON)
    ui.text(x + 18, fy, #st.fans > 1 and 'fans' or 'fan', 11, M.overlay1)
    ui.text(x + 58, fy, table.concat(st.rpm or {}, ' · ') .. ' rpm', 11, M.teal)
  else
    ui.text(x, fy, st.tasks or '', 11, M.overlay1)
  end
  ui.text(x + w, fy, 'load ' .. (st.load or '?'), 11, M.overlay1, false, 'r')
  return fy - cy + 4
end

return C
