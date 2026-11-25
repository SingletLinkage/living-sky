--[[
  sys: small readers for /proc and /sys, and hardware detection, shared by the cards.
  Everything here is cheap file reads; nothing blocks. Detection (sys.scan) runs once at start.
]]
local sys = {}

function sys.readf(p)                   -- first line of a file, or nil
  local f = io.open(p, 'r'); if not f then return nil end
  local s = f:read('*l'); f:close(); return s
end
function sys.readn(p) return tonumber(sys.readf(p) or '') end

function sys.cmd(c)                     -- first output line of a shell command (use sparingly: forks)
  local h = io.popen(c .. ' 2>/dev/null')
  if not h then return nil end
  local s = h:read('*l'); h:close(); return s
end

function sys.P(s) return conky_parse(s) or '' end                          -- a conky variable, e.g. '${kernel}'
function sys.PN(s) return tonumber((sys.P(s):gsub('[^%d%.%-]', ''))) or 0 end

function sys.now()                      -- monotonic-ish seconds with sub-second precision
  return tonumber((sys.readf('/proc/uptime') or '0'):match('^[%d%.]+')) or os.time()
end

------------------------------------------------------------------ hardware detection
sys.HW = {}        -- hwmon name -> sysfs dir (numbers move across boots, names don't); HW.cpu = the CPU sensor,
                   -- HW.cpu_input = its temperature file (the package / Tctl reading when the driver labels them)
sys.PS = {}        -- PS.bat = battery dir (with trailing /), PS.ac = AC adapter 'online' file

function sys.scan()
  local HW, PS = sys.HW, sys.PS
  local ls = io.popen('ls -1d /sys/class/hwmon/hwmon* 2>/dev/null')
  if ls then
    for p in ls:lines() do
      local n = sys.readf(p .. '/name')
      if n and not HW[n] then HW[n] = p end
    end
    ls:close()
  end
  -- CPU drivers first (Intel, AMD, Arm SoCs), then laptop / board controllers that also report the CPU
  for _, n in ipairs({'coretemp', 'k10temp', 'zenpower', 'cpu_thermal', 'soc_thermal', 'thinkpad', 'dell_smm',
                      'asus_ec_sensors', 'nct6775', 'nct6683', 'it87', 'acpitz'}) do
    if HW[n] then HW.cpu = HW[n]; break end
  end
  if HW.cpu then                                    -- the labelled package / die reading, else temp1
    local best, rank = HW.cpu .. '/temp1_input', 99
    local wanted = {'^package id', '^tctl', '^tdie', '^cpu', '^cputin', '^core 0'}
    for i = 1, 16 do
      local label = (sys.readf(HW.cpu .. '/temp' .. i .. '_label') or ''):lower()
      for r, pat in ipairs(wanted) do
        if r < rank and label:match(pat) and sys.readf(HW.cpu .. '/temp' .. i .. '_input') then
          best, rank = HW.cpu .. '/temp' .. i .. '_input', r
        end
      end
    end
    HW.cpu_input = best
  end
  local h = io.popen('ls -1 /sys/class/power_supply 2>/dev/null')
  if h then
    for n in h:lines() do
      local d = '/sys/class/power_supply/' .. n
      local ty = sys.readf(d .. '/type')
      if ty == 'Battery' and not PS.bat and sys.readf(d .. '/capacity') then PS.bat = d .. '/' end
      if ty == 'Mains' and not PS.ac then PS.ac = d .. '/online' end
    end
    h:close()
  end
end

function sys.on_ac()                    -- desktops without an AC adapter entry count as "on AC"
  if not sys.PS.ac then return true end
  return sys.readf(sys.PS.ac) == '1'
end

function sys.cpu_temp()                 -- °C from the CPU sensor (0 if none)
  return (sys.readn(sys.HW.cpu_input or '') or 0) / 1000
end

function sys.default_iface()            -- interface of the default route ('lo' when offline)
  local f = io.open('/proc/net/route'); if not f then return 'lo' end
  f:read('*l')
  for l in f:lines() do
    local ifc, dst = l:match('^(%S+)%s+(%S+)')
    if dst == '00000000' then f:close(); return ifc end
  end
  f:close(); return 'lo'
end

return sys
