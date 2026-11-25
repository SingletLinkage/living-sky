--[[
  Memory card: RAM and swap use, the root filesystem (used / size), and disk I/O rates
  (with the NVMe temperature when there is one).
]]
local C = {id = 'memory', title = 'MEMORY', icon = 'mem', accent = 'mauve'}
local st = {mem = {}}

local function ram_label(kib)           -- installed size: the kernel reports a bit less (15.3 GiB -> 16 GB)
  local g = (kib or 0) / 1048576
  for _, n in ipairs({1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512}) do
    if g <= n then return n .. ' GB' end
  end
  return string.format('%.0f GB', g)
end

local function sample_mem()
  local m = {}
  local f = io.open('/proc/meminfo'); if not f then return m end
  for l in f:lines() do
    local k, v = l:match('^(%S+):%s+(%d+)')
    if k then m[k] = tonumber(v) end
  end
  f:close(); return m
end

-- sectors read / written over whole disks (nvmeXnY, sdX, vdX, mmcblkN; not partitions, loop or zram)
local function sample_disk()
  local f = io.open('/proc/diskstats'); if not f then return 0, 0 end
  local r, w = 0, 0
  for l in f:lines() do
    local name, rest = l:match('^%s*%d+%s+%d+%s+(%S+)%s+(.*)')
    if name and (name:match('^nvme%d+n%d+$') or name:match('^[sv]d%a+$') or name:match('^mmcblk%d+$')) then
      local v, i = {}, 0
      for x in rest:gmatch('%d+') do i = i + 1; v[i] = tonumber(x) end
      r, w = r + v[3], w + v[7]
    end
  end
  f:close(); return r, w
end

function C.init(d)
  -- root filesystem device -> label: 'nvme /', 'ssd /', 'hdd /' or 'disk /'
  local src = d.sys.cmd('findmnt -no SOURCE /') or ''
  local dev = src:match('/dev/(nvme%d+n%d+)') or src:match('/dev/([sv]d%a+)') or src:match('/dev/(mmcblk%d+)')
  local rot = dev and d.sys.readf('/sys/block/' .. dev .. '/queue/rotational')
  st.disk = (src:find('nvme') and 'nvme' or (rot == '1' and 'hdd') or (rot == '0' and 'ssd') or 'disk') .. ' /'
  st.mem = sample_mem()
end

function C.subtitle() return ram_label(st.mem.MemTotal) end

function C.sample(d)
  st.mem = sample_mem()
  local r, w = sample_disk()
  if st.prev then
    st.dr, st.dw = (r - st.prev.r) / 2 / d.dt, (w - st.prev.w) / 2 / d.dt     -- KiB/s (512-byte sectors)
  else st.dr, st.dw = 0, 0 end
  st.prev = {r = r, w = w}
  st.nvmet = (d.sys.readn((d.sys.HW.nvme or '') .. '/temp1_input') or 0) / 1000
end

function C.draw(d, x, cy, w)
  local ui, M, sys = d.ui, d.M, d.sys
  local m = st.mem
  local tot, av = m.MemTotal or 1, m.MemAvailable or 0
  local mp = (tot - av) / tot
  ui.kv(x, cy, w, 'ram', ui.human(tot - av) .. ' / ' .. ui.human(tot), M.text)
  ui.pill(x, cy + 8, w, 6, mp, ui.lvl(mp * 100, 75, 90, M.mauve))
  ui.kv(x, cy + 32, w, 'swap', ui.human((m.SwapTotal or 0) - (m.SwapFree or 0)) .. ' / ' .. ui.human(m.SwapTotal or 0), M.subtext0)
  local used, size = sys.P('${fs_used /}'), sys.P('${fs_size /}')
  local fp = sys.PN('${fs_used_perc /}')
  local sp = function(s) return (s:gsub('(%d)(%a)', '%1 %2')) end           -- "232GiB" -> "232 GiB"
  ui.kv(x, cy + 62, w, st.disk, sp(used) .. ' / ' .. sp(size), M.text)
  ui.pill(x, cy + 70, w, 6, fp / 100, ui.lvl(fp, 80, 92, M.pink))
  ui.kv(x, cy + 94, w, (st.nvmet or 0) > 0 and string.format('io  %.0f°C', st.nvmet) or 'io',
    'r ' .. ui.rate(st.dr or 0) .. '   w ' .. ui.rate(st.dw or 0), M.subtext0)
  return 98
end

return C
