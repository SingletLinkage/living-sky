-- living-sky "cards" theme: solid Catppuccin cards. The engine is lua/desktop.lua.
LIVING_SKY_STYLE = 'cards'
local root = (debug.getinfo(1, 'S').source or ''):match('^@(.*)/themes/[^/]+/[^/]+%.lua$')
dofile(root .. '/lua/desktop.lua')
