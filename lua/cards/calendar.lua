--[[
  Calendar: this month as a grid, today highlighted in the primary accent, weekends muted.
  Option: week_start = monday | sunday (living-sky.conf; default monday).
  Weekday initials and the month name follow the system language (LC_TIME).
]]
local C = {id = 'calendar', title = 'CALENDAR', icon = 'calendar', accent = 'pink'}

function C.subtitle(d) return os.date('%B %Y', d.time) end

function C.draw(d, x, cy, w)
  local ui, M, cr = d.ui, d.M, d.cr
  local now = os.date('*t', d.time)
  local sunday_first = (d.cfg.week_start or ''):lower() == 'sunday'
  local cw = w / 7
  -- weekday initials (2001-01-01 was a Monday)
  for i = 0, 6 do
    local wd = sunday_first and (i + 6) % 7 or i                         -- 0 = Monday
    local name = os.date('%a', os.time{year = 2001, month = 1, day = 1 + wd, hour = 12})
    local weekend = wd >= 5
    local short = name:match('^[%z\1-\127\194-\244][\128-\191]*[%z\1-\127\194-\244]?[\128-\191]*') or name
    ui.text(x + cw * (i + 0.5), cy + 10, short, 10, weekend and M.overlay0 or M.overlay1, true, 'c')
  end
  local first = os.date('*t', os.time{year = now.year, month = now.month, day = 1, hour = 12})
  local mon_index = (first.wday + 5) % 7                                 -- Monday = 0
  local col0 = sunday_first and (mon_index + 1) % 7 or mon_index
  local days = os.date('*t', os.time{year = now.year, month = now.month + 1, day = 0, hour = 12}).day
  local row = 0
  for day = 1, days do
    local col = (col0 + day - 1) % 7
    row = (col0 + day - 1) // 7
    local px, py = x + cw * (col + 0.5), cy + 30 + row * 20
    local wd = sunday_first and (col + 6) % 7 or col
    if day == now.day then
      ui.rrect(px - 11, py - 13, 22, 18, 7); ui.rgba(M.accent, 0.9); cairo_fill(cr)
      ui.text(px, py, day, 11, M.crust or M.base, true, 'c')
    else
      ui.text(px, py, day, 11, wd >= 5 and M.overlay1 or M.text, false, 'c')
    end
  end
  return 36 + row * 20
end

return C
