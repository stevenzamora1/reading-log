-- Reading Log · Cover calendar
-- A Bookshelf micro-module from the Reading Log plugin: the card is drawn by
-- the plugin's shared code in ../readinglog/ (Simple UI uses the same code).
local A = package.loaded["almanac_kit"]
if not A then
    local dir = ... or debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
    A = assert(loadfile(dir .. "/../readinglog/init.lua"))("bookshelf")
    package.loaded["almanac_kit"] = A
end
return A.module("calendar")
