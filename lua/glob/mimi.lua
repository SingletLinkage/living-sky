--[[
  Mimi, the first glob pet: a soft lavender blob. With `colors = auto` she stays lavender all day (the
  auto accents change with the sky, pink at dusk, and a pet shouldn't); with a colour set of your own
  (`colors = mint`, '#rrggbb, #rrggbb', ...) she wears your primary colour.
  Cheerful and social: hops, waves, dances, morning coffee; asleep 00-06 h, drowsy after 22 h;
  snacks every 20-30 min; sulks after 2 h without a click. She is the core's defaults, so this
  file only names her. See lua/glob/core.lua for every field a pet can set.
]]
local dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*/)') or './'
return dofile(dir .. 'core.lua'){
  id = 'mimi', name = 'Mimi',
  color = function(M, light, mix)
    local c = ((M.colors or 'auto') == 'auto') and (M.lavender or M.accent) or M.accent
    return light and mix(c, {1, 1, 1}, 0.45) or c
  end,
}
