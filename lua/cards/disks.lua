--[[
  Disks: every real mounted filesystem (devices under /dev; no tmpfs, snaps, overlays or FUSE app
  mounts), each with used / size and a bar; up to 5, largest first. Refreshed every 30 s with `df`
  in the background (it never blocks the desktop), plus once at start.
]]
local C = {id = 'disks', title = 'DISKS', icon = 'harddisk', accent = 'peach'}
local st = {list = {}}
local OUT

local function refresh(d)
  os.execute('(df -kP -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs > ' .. d.q(OUT .. '.tmp')
    .. ' 2>/dev/null; mv ' .. d.q(OUT .. '.tmp') .. ' ' .. d.q(OUT) .. ') >/dev/null 2>&1 &')
end

function C.init(d)
  OUT = d.cache .. 'disks.txt'
  refresh(d)
end

function C.sample(d)
  if d.tick % 30 == 0 then refresh(d) end
  local f = io.open(OUT)
  if not f then return end
  local list, seen = {}, {}
  f:read('*l')                                   -- header
  for line in f:lines() do
    local dev, size, used, mnt = line:match('^(%S+)%s+(%d+)%s+(%d+)%s+%d+%s+%d+%%%s+(.+)$')
    if dev and dev:match('^/dev/') and not seen[dev] and not mnt:match('^/snap') then
      seen[dev] = true
      list[#list + 1] = {mnt = mnt, size = tonumber(size), used = tonumber(used)}
    end
  end
  f:close()
  table.sort(list, function(a, b) return a.size > b.size end)
  while #list > 5 do table.remove(list) end
  st.list = list
end

function C.subtitle() return #st.list > 0 and (#st.list .. (#st.list == 1 and ' volume' or ' volumes')) or '' end

function C.draw(d, x, cy, w)
  local ui, M = d.ui, d.M
  local y = cy
  for i, v in ipairs(st.list) do
    local frac = v.size > 0 and v.used / v.size or 0
    local name = v.mnt == '/' and '/' or ui.fit(v.mnt, w * 0.5, 11)
    ui.kv(x, y, w, name, ui.human(v.used) .. ' / ' .. ui.human(v.size), M.text)
    ui.pill(x, y + 8, w, 5, frac, ui.lvl(frac * 100, 80, 92, M.peach))
    y = y + 30
    if i == #st.list then y = y - 6 end
  end
  if #st.list == 0 then ui.text(x, cy + 10, 'reading…', 11, M.overlay1); return 14 end
  return y - cy
end

return C
