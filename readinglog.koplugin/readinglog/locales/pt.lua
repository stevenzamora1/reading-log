-- Portuguese from Portugal (pt, pt_PT) uses the Brazilian catalog, the closest we have.
local dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
return dofile(dir .. "/pt_br.lua")
