--[[
  GPU card (NVIDIA): usage with a sparkline, temperature, power and clock, VRAM.
  Power-aware: it never wakes a sleeping dGPU. Stats come from nvidia-smi, run in the background
  into a cache file, only on AC power and only every 15 s; on battery it shows a status chip.
  Hidden on machines without an NVIDIA GPU (init returns false). Other vendors: TODO.
]]
local C = {id = 'gpu', title = 'GRAPHICS', icon = 'gpu', accent = 'green'}
local POLL_AC = 15
local st = {state = '—', util = 0, mem = 0, memtot = 0, label = 'GPU', hist = {}}

function C.init(d)
  local h = io.popen('ls -1 /sys/bus/pci/devices 2>/dev/null')
  if h then
    for n in h:lines() do                         -- NVIDIA (vendor 0x10de), display class 0x03xxxx
      local dev = '/sys/bus/pci/devices/' .. n
      if d.sys.readf(dev .. '/vendor') == '0x10de' and (d.sys.readf(dev .. '/class') or ''):match('^0x03') then st.pci = dev; break end
    end
    h:close()
  end
  st.csv = d.cache .. 'gpu.csv'                   -- temp, util, mem used, mem total, power, clock
  st.namef = d.cache .. 'gpu-name'                -- "name, total MiB", queried once (it wakes the dGPU)
  return st.pci ~= nil and (d.sys.cmd('command -v nvidia-smi') or '') ~= ''   -- nouveau / no driver tools: hide
end

function C.subtitle() return st.label end

local function spawn(query, out, q)
  os.execute('(nvidia-smi --query-gpu=' .. query .. ' --format=csv,noheader,nounits > ' .. q(out .. '.tmp')
    .. ' 2>/dev/null && mv ' .. q(out .. '.tmp') .. ' ' .. q(out) .. ') >/dev/null 2>&1 &')
end

function C.sample(d)
  local sys = d.sys
  if st.label == 'GPU' then                       -- model name + VRAM, once
    local l = sys.readf(st.namef)
    if l then
      local n, mt = l:match('^(.-),%s*(%d+)')
      if n then
        n = n:gsub('^NVIDIA%s+', ''):gsub('^GeForce%s+', ''):gsub('%s+Laptop GPU', ''):gsub('%s+GPU', '')
        st.label = n .. string.format(' · %.0f GB', tonumber(mt) / 1024)
        if st.memtot == 0 then st.memtot = tonumber(mt) end
      end
    elseif d.tick % 60 == 1 and sys.on_ac() then
      spawn('name,memory.total', st.namef, d.q)
    end
  end
  st.state = sys.readf(st.pci .. '/power/runtime_status') or 'active'
  if st.state == 'active' then
    local l = sys.readf(st.csv)
    if l then
      local t, u, m, mt, pw, ck = l:match('([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+)')
      st.temp, st.util, st.mem = tonumber(t), tonumber(u) or 0, tonumber(m) or 0
      st.memtot, st.pwr, st.clk = tonumber(mt) or st.memtot, tonumber(pw), tonumber(ck)
    end
    -- any nvidia-smi call resets the dGPU's idle timer: never on battery, every POLL_AC s on AC
    st.paused = not sys.on_ac()
    if not st.paused and d.tick % POLL_AC == 1 then
      spawn('temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,clocks.gr', st.csv, d.q)
    end
  else
    st.temp, st.util, st.mem, st.pwr = nil, 0, 0, nil
  end
  d.ui.push(st.hist, st.util or 0, 48)
end

function C.draw(d, x, cy, w)
  local ui, M = d.ui, d.M
  if st.state == 'active' and st.temp and not st.paused then
    local col = ui.lvl(st.util, 60, 90, M.green)
    local nw = ui.text(x, cy + 26, st.util, 30, col, true)
    ui.text(x + nw + 3, cy + 26, '%', 13, M.overlay1)
    ui.spark(x + 80, cy, w - 180, 28, st.hist, 100, col)
    ui.text(x + w, cy + 10, string.format('%d°C', st.temp), 12, ui.lvl(st.temp, 75, 87, M.peach), true, 'r')
    ui.text(x + w, cy + 27, st.pwr and string.format('%.0f W · %d MHz', st.pwr, st.clk or 0) or '', 11, M.subtext0, false, 'r')
    ui.kv(x, cy + 50, w, 'vram', string.format('%d / %d MiB', st.mem, st.memtot))
    ui.pill(x, cy + 58, w, 6, st.mem / math.max(1, st.memtot), M.green)
    return 64
  end
  -- asleep / paused: a status chip
  local state, sub
  if st.state == 'active' and st.paused then state, sub = 'active', 'stats paused on battery'
  elseif st.state == 'active' then state, sub = 'active', 'sampling…'
  else state, sub = 'asleep', 'runtime D3 · iGPU driving' end
  local cr = d.cr
  ui.rrect(x, cy, 74, 24, 12); ui.rgba(state == 'asleep' and M.overlay0 or M.green, 0.18); cairo_fill(cr)
  ui.text(x + 37, cy + 16, state, 11, state == 'asleep' and M.subtext0 or M.green, true, 'c')
  ui.text(x + 86, cy + 16, sub, 11, M.overlay1)
  return 28
end

return C
