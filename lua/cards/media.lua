--[[
  Now playing: title, artist (and album), the player, a progress bar with times, play / pause state.
  Data: ~/.cache/living-sky/nowplaying, written by core/glob-presence.py from MPRIS (any media player:
  Spotify, browsers, VLC, mpv, ...). The position is stamped with the uptime clock, so the bar moves
  on its own between updates. Hidden when nothing is playing or paused.
]]
local C = {id = 'media', title = 'NOW PLAYING', icon = 'music', accent = 'accent2'}
local st = {}

function C.sample(d)
  local f = io.open(d.cache .. 'nowplaying')
  if not f then st.np = nil; return end
  local np = {}
  for line in f:lines() do
    local k, v = line:match('^(%a+) (.*)$')
    if k then np[k] = v end
  end
  f:close()
  st.np = (np.status == 'Playing' or np.status == 'Paused') and np or nil
end

function C.visible() return st.np ~= nil end

function C.subtitle(d)
  return st.np and (d.demo and 'Player' or st.np.player) or ''
end

local function mmss(s)
  s = math.max(0, math.floor(s or 0))
  if s >= 3600 then return string.format('%d:%02d:%02d', s // 3600, s % 3600 // 60, s % 60) end
  return string.format('%d:%02d', s // 60, s % 60)
end

function C.draw(d, x, cy, w)
  local ui, M, np = d.ui, d.M, st.np
  local title = d.demo and 'A Song Title' or (np.title ~= '' and np.title or 'Unknown')
  local who = d.demo and 'An Artist' or np.artist
  if not d.demo and np.album and np.album ~= '' and who ~= '' then who = who .. ' · ' .. np.album end
  local playing = np.status == 'Playing'
  ui.text(x, cy + 14, playing and ui.I.play or ui.I.pause, 16, playing and M.accent or M.overlay1, false, nil, ui.ICON)
  ui.text(x + 24, cy + 10, ui.fit(title, w - 24, 12, true), 12, M.text, true)
  ui.text(x + 24, cy + 27, ui.fit(who, w - 24, 11), 11, M.subtext0)
  local len, pos = tonumber(np.length) or 0, tonumber(np.position) or -1
  if len > 0 and pos >= 0 then
    if playing then pos = pos + (d.sys.now() - (tonumber(np.at) or d.sys.now())) end
    pos = math.min(pos, len)
    ui.pill(x, cy + 40, w, 5, pos / len, M.accent)
    ui.text(x, cy + 60, mmss(pos), 10, M.overlay1)
    ui.text(x + w, cy + 60, mmss(len), 10, M.overlay1, false, 'r')
    return 64
  end
  return 34
end

return C
