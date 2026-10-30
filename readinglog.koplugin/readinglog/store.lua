--[[
Reading Log's settings: settings/readinglog.lua, one file for both apps.

The cards in Simple UI and the cards in Bookshelf read and write the same
settings, through one LuaSettings object kept for the whole KOReader session
(in package.loaded), so a change made in one app is there in the other, and
the two never write over each other.

On the first run, the settings the older Bookshelf micro-modules version kept
in Bookshelf's micro-module data file (theme, accents, banner lines, book club
picks, dashboard pages, ...) are copied in, so moving to the plugin keeps
them.
]]

local KEY = "readinglog_store"
local St = package.loaded[KEY]
if type(St) == "table" then return St end
St = {}

local SETTINGS_FILE = "readinglog.lua"
local BOOKSHELF_FILE = "bookshelf/micromodule_data.lua"
local BOOKSHELF_PREFIX = "micromodule_almanac_"

local _store

local function settingsDir()
    return require("datastorage"):getSettingsDir()
end

local function fileExists(path)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    return ok and lfs and lfs.attributes(path, "mode") == "file"
end

local function log(...)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.info("[readinglog]", ...) end
end

--- Copy the Bookshelf micro-modules version's settings into `store`.
--- Returns how many were copied, or nil when there is nothing to copy.
function St.importBookshelf(store)
    store = store or St.file()
    local path = settingsDir() .. "/" .. BOOKSHELF_FILE
    if not fileExists(path) then return nil end
    local ok, src = pcall(function() return require("luasettings"):open(path) end)
    if not (ok and src and type(src.data) == "table") then return nil end
    local n = 0
    for key, value in pairs(src.data) do
        if type(key) == "string" and key:sub(1, #BOOKSHELF_PREFIX) == BOOKSHELF_PREFIX then
            local name = key:sub(#BOOKSHELF_PREFIX + 1)
            -- a text size or refresh mode from a test build has no meaning here
            if name ~= "" and name ~= "text_size" and name ~= "refresh" then
                store:saveSetting(name, value)
                n = n + 1
            end
        end
    end
    if n > 0 then
        store:flush()
        log("copied", n, "settings from the Bookshelf micro-modules")
    end
    return n
end

-- Settings kept in memory only: when there is no settings folder to write to
-- (outside KOReader, in the tests).
local function memoryStore()
    local data = {}
    return {
        data = data,
        readSetting = function(_, k) return data[k] end,
        saveSetting = function(_, k, v) data[k] = v end,
        delSetting = function(_, k) data[k] = nil end,
        flush = function() end,
    }
end

--- The settings file (a LuaSettings), opened once.
function St.file()
    if _store then return _store end
    local ok_dir, dir = pcall(settingsDir)
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    if not (ok_dir and type(dir) == "string" and ok_ls and LuaSettings) then
        _store = memoryStore()
        return _store
    end
    local path = dir .. "/" .. SETTINGS_FILE
    local fresh = not fileExists(path)
    _store = LuaSettings:open(path)
    if fresh then
        pcall(St.importBookshelf, _store)
        -- write the file even when nothing was copied, so this runs once
        _store:saveSetting("created", os.date("%Y-%m-%d"))
        _store:flush()
    end
    return _store
end

-- Bumped on every write, so a card drawn by the other app's copy of the kit
-- can tell a setting changed.
St.gen = 0

function St.get(key)
    return St.file():readSetting(key)
end

function St.set(key, value)
    local s = St.file()
    if value == nil then s:delSetting(key) else s:saveSetting(key, value) end
    s:flush()
    St.gen = St.gen + 1
end

package.loaded[KEY] = St
return St
