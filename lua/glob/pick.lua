--[[
  Which pet to show for `glob = ...` in living-sky.conf:
    <pet id> | off      that pet (unknown names: mimi)
    random              a pet of the day: the same pet all day, a different one tomorrow (never the same
                        two days running), cycling through all of them
    scene               the pet that goes with the wallpaper scene (lake: pip, forest: bun, city: cubo,
                        camp: ember)
  resolve(glob, scene, time) -> pet id. A new pet goes into PETS (and SCENE if it suits a scene).
]]
local M = {}
M.PETS = {'bun', 'cubo', 'ember', 'mimi', 'nyx', 'pip'}
M.SCENE = {lake = 'pip', forest = 'bun', city = 'cubo', camp = 'ember'}

local function known(id)
  for _, p in ipairs(M.PETS) do if p == id then return true end end
  return false
end

local function day_number(t)                    -- local calendar day as a whole number
  local d = os.date('*t', t)
  return math.floor(os.time({year = d.year, month = d.month, day = d.day, hour = 12}) / 86400)
end

local function of_day(n)                        -- scrambled, so it doesn't read like a fixed rota
  local h = (n * 2654435761) % 4294967296
  return math.floor(h / 65536) % #M.PETS + 1
end

function M.daily(t)
  local n = day_number(t or os.time())
  local i = of_day(n)
  if i == of_day(n - 1) then i = i % #M.PETS + 1 end      -- never the same pet two days running
  return M.PETS[i]
end

function M.resolve(glob, scene, t)
  local v = (glob or 'mimi'):lower():gsub('%s', '')
  if v == 'off' then return 'off' end
  if v == 'random' then return M.daily(t) end
  if v == 'scene' then return M.SCENE[(scene or 'lake'):lower():gsub('%s', '')] or 'mimi' end
  return known(v) and v or 'mimi'
end

return M
