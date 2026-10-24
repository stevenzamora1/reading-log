-- Reading Log · Quote of the day 3
-- A Bookshelf micro-module. The card is drawn by the shared kit in the
-- almanac/ folder next to this file; keep the two together.
local A = package.loaded["almanac_kit"]
if not A then
    local dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
    A = dofile(dir .. "/almanac/init.lua")
    package.loaded["almanac_kit"] = A
end
return A.module("quote3")
