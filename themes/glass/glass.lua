-- living-sky "glass" theme: frosted liquid-glass cards. The engine is lua/desktop.lua.
LIVING_SKY_STYLE = 'glass'
local root = (debug.getinfo(1, 'S').source or ''):match('^@(.*)/themes/[^/]+/[^/]+%.lua$')
dofile(root .. '/lua/desktop.lua')
