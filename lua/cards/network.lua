--[[
  Network card: the default-route interface, Wi-Fi name and signal, IPv4 address,
  download / upload rates with 60 s sparklines.
]]
local C = {id = 'network', title = 'NETWORK', icon = 'wifi', accent = 'sapphire'}
local st = {down = 0, up = 0, hdown = {}, hup = {}, essid = '', ip = ''}

local function sample_net(ifc)          -- rx / tx byte counters of one interface
  local f = io.open('/proc/net/dev'); if not f then return 0, 0 end
  local rx, tx = 0, 0
  for l in f:lines() do
    local n, rest = l:match('^%s*([^:]+):%s*(.*)')
    if n == ifc then
      local v, i = {}, 0
      for x in rest:gmatch('%d+') do i = i + 1; v[i] = tonumber(x) end
      rx, tx = v[1], v[9]
    end
  end
  f:close(); return rx, tx
end

function C.init(d) st.ifc = d.sys.default_iface() end

function C.subtitle() return st.wq and (st.wq .. '%') or st.ifc end

function C.sample(d)
  local sys = d.sys
  if d.tick % 10 == 1 then st.ifc = sys.default_iface() end
  local rx, tx = sample_net(st.ifc)
  local p = st.prev
  if p and p.ifc == st.ifc then
    st.down, st.up = math.max(0, (rx - p.rx) / 1024 / d.dt), math.max(0, (tx - p.tx) / 1024 / d.dt)
  else st.down, st.up = 0, 0 end
  st.prev = {ifc = st.ifc, rx = rx, tx = tx}
  d.ui.push(st.hdown, st.down, 60); d.ui.push(st.hup, st.up, 60)
  if d.tick % 15 == 1 then                        -- slow-changing link info every 15 s (forks)
    if st.ifc == 'lo' then st.essid, st.ip = '', ''          -- no default route: offline
    else
      st.essid = sys.cmd('iwgetid -r') or sys.cmd("nmcli -t -f active,ssid dev wifi | sed -n 's/^yes://p'") or ''
      st.ip = sys.cmd('ip -4 -o addr show dev ' .. st.ifc .. " | awk '{print $4}' | head -1") or ''
    end
  end
  st.wq = nil                                     -- Wi-Fi link quality (0..70) as %
  local f = io.open('/proc/net/wireless')
  if f then
    for l in f:lines() do
      local n, q = l:match('^%s*([^:]+):%s+%S+%s+(%d+)')
      if n == st.ifc then st.wq = math.floor(tonumber(q) * 100 / 70 + 0.5) end
    end
    f:close()
  end
end

function C.draw(d, x, cy, w)
  local ui, M = d.ui, d.M
  local essid, ip = st.essid, st.ip
  if d.demo then essid, ip = 'home-wifi', '192.168.1.20' end     -- screenshots: no real network details
  ui.kv(x, cy, w, (essid ~= '' and essid) or st.ifc, ip ~= '' and ip or 'offline', M.subtext0)
  local mx = 64
  for _, v in ipairs(st.hdown) do mx = math.max(mx, v) end
  for _, v in ipairs(st.hup) do mx = math.max(mx, v) end
  local hw = (w - 14) / 2
  ui.spark(x, cy + 12, hw, 30, st.hdown, mx, M.sapphire)
  ui.spark(x + hw + 14, cy + 12, hw, 30, st.hup, mx, M.peach)
  ui.text(x, cy + 60, '↓ ' .. ui.rate(st.down), 11, M.sapphire, true)
  ui.text(x + hw + 14, cy + 60, '↑ ' .. ui.rate(st.up), 11, M.peach, true)
  return 64
end

return C
