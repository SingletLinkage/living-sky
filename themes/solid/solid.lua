-- living-sky "solid" theme: the cards style, fully opaque (no wallpaper showing through). The engine is lua/desktop.lua.
LIVING_SKY_STYLE = 'solid'
local root = (debug.getinfo(1, 'S').source or ''):match('^@(.*)/themes/[^/]+/[^/]+%.lua$')
dofile(root .. '/lua/desktop.lua')
