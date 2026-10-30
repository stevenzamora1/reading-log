--[[
Check for updates: asks GitHub for the latest release of Reading Log
(stevenzamora1/reading-log), and if it's newer, downloads its zip and unpacks
it over this plugin folder. A restart then loads the new version. Settings live outside
the plugin folder (settings/readinglog.lua), so they are kept.

The same steps Simple UI's own updater takes: KOReader's socket.http with
socketutil's timeouts, the download streamed to a file, and KOReader's own
archive reader (ffi/archiver, libarchive) to unpack, so no "unzip" program
is needed (Android has none).

Loaded by main.lua with dofile(DIR .. "/updater.lua")(DIR, _, fmt).
]]

local UIManager = require("ui/uimanager")
local logger = require("logger")

local OWNER, REPO = "stevenzamora1", "reading-log"
local API_URL = "https://api.github.com/repos/" .. OWNER .. "/" .. REPO .. "/releases/latest"
local RELEASES_URL = "https://github.com/" .. OWNER .. "/" .. REPO .. "/releases/latest"
local FOLDER = "readinglog.koplugin" -- the folder at the top of the release zip
local AUTO_KEY, LAST_KEY, FOUND_KEY = "readinglog_update_auto", "readinglog_update_last", "readinglog_update_found"
local DAY = 24 * 3600

return function(DIR, _, fmt)

local U = {}

local function gs() return rawget(_G, "G_reader_settings") end

local function info(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    local w = InfoMessage:new{ text = text, timeout = timeout }
    UIManager:show(w)
    return w
end

-- This copy's version, from its own _meta.lua (not require's cache).
function U.current()
    local ok, meta = pcall(dofile, DIR .. "/_meta.lua")
    return ok and type(meta) == "table" and meta.version or "0"
end

local function parts(v)
    local t = {}
    for n in tostring(v or ""):gsub("^%D*", ""):gsub("[-+].*$", ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

-- Is version a newer than b? "v1.3.0" and "1.3" both work.
function U.newer(a, b)
    local pa, pb = parts(a), parts(b)
    if #pa == 0 then return false end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- GET a URL into a sink. Returns true, or nil and a short reason.
local function get(url, sink, accept, file)
    local http = require("socket.http")
    local socket = require("socket")
    local ok_su, socketutil = pcall(require, "socketutil")
    if ok_su then
        if file then socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        else socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT) end
    end
    local code, headers, status = socket.skip(1, http.request{
        url = url, method = "GET", sink = sink, redirect = true,
        headers = { ["User-Agent"] = "KOReader-ReadingLog-Updater", ["Accept"] = accept or "*/*" },
    })
    if ok_su then socketutil:reset_timeout() end
    if ok_su and (code == socketutil.TIMEOUT_CODE or code == socketutil.SSL_HANDSHAKE_CODE
            or code == socketutil.SINK_TIMEOUT_CODE) then
        return nil, "timed out"
    end
    if headers == nil then return nil, "no connection (" .. tostring(code or status) .. ")" end
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return true
end

-- The latest release: { version, url (the zip), notes } or { error }.
function U.parse(body)
    local ok_j, json = pcall(require, "json")
    local ok, data = false, nil
    if ok_j then ok, data = pcall(json.decode, body) end
    if not ok or type(data) ~= "table" then return { error = "could not read the release" } end
    if not data.tag_name then return { error = "no release yet" } end
    local zip
    for _, a in ipairs(data.assets or {}) do
        local name = tostring(a.name or "")
        if name:match("%.zip$") and (name:find("readinglog", 1, true) or not zip) then
            zip = a.browser_download_url
            if name:match("^readinglog%-simpleui") then break end
        end
    end
    local notes = type(data.body) == "string" and data.body or ""
    notes = notes:gsub("\r\n?", "\n"):gsub("#+%s*", ""):gsub("%*%*(.-)%*%*", "%1"):gsub("`(.-)`", "%1")
        :gsub("%[(.-)%]%((.-)%)", "%1"):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if #notes > 700 then notes = notes:sub(1, 700):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "\xE2\x80\xA6" end
    return { version = tostring(data.tag_name):gsub("^%D*", ""), url = zip, notes = notes ~= "" and notes or nil }
end

local function fetch()
    local ltn12 = require("ltn12")
    local chunks = {}
    local ok, err = get(API_URL, ltn12.sink.table(chunks), "application/vnd.github+json")
    if not ok then return { error = err } end
    return U.parse(table.concat(chunks))
end

local function zipPath()
    local ok, DS = pcall(require, "datastorage")
    local dir = ok and DS and DS:getSettingsDir() or DIR
    return dir .. "/readinglog_update.zip"
end

-- Unpack the release zip over this folder. The zip's top folder
-- (readinglog.koplugin/) is dropped, so the files land here whatever this
-- folder is called. Checked first: nothing is written unless the zip holds
-- a whole plugin.
function U.install(zip)
    local ok_a, Archiver = pcall(require, "ffi/archiver")
    if not ok_a then return nil, "this KOReader can't unpack zip files" end
    local arc = Archiver.Reader:new()
    if not arc:open(zip) then return nil, "the download isn't a zip file" end
    local files, has_meta, has_kit = {}, false, false
    for entry in arc:iterate() do
        local rel = entry.path:match("^" .. FOLDER:gsub("%.", "%%.") .. "/(.*)$")
        if rel and rel ~= "" and not rel:find("%.%.") then
            if rel == "_meta.lua" then has_meta = true end
            if rel == "readinglog/init.lua" then has_kit = true end
            if entry.mode == "file" then files[#files + 1] = { entry.path, rel } end
        end
    end
    if not (has_meta and has_kit) then
        arc:close()
        return nil, "the zip doesn't hold " .. FOLDER
    end
    local lfs = require("libs/libkoreader-lfs")
    for _, f in ipairs(files) do
        -- make the folders a file goes into
        local path = DIR
        for dir in f[2]:gmatch("([^/]+)/") do
            path = path .. "/" .. dir
            if lfs.attributes(path, "mode") ~= "directory" then lfs.mkdir(path) end
        end
        if not arc:extractToPath(f[1], DIR .. "/" .. f[2]) then
            local err = arc.err
            arc:close()
            return nil, "could not write " .. f[2] .. (err and (": " .. err) or "")
        end
    end
    arc:close()
    return true
end

-- Run fn in a subprocess behind a dismissable message; done(result) after.
local function inBackground(text, fn, done)
    local ok_t, Trapper = pcall(require, "ui/trapper")
    if not (ok_t and Trapper and Trapper.wrap) then
        local w = info(text)
        UIManager:forceRePaint()
        local r = fn()
        UIManager:close(w)
        return done(r)
    end
    Trapper:wrap(function()
        local completed, r = Trapper:dismissableRunInSubprocess(fn, text)
        if completed then done(r) else info(_("Cancelled."), 3) end
    end)
end

local function remember(release)
    local s = gs()
    if not s then return end
    s:saveSetting(LAST_KEY, os.time())
    if release and release.version and U.newer(release.version, U.current()) then
        s:saveSetting(FOUND_KEY, release.version)
    else
        s:delSetting(FOUND_KEY)
    end
end

-- A newer version found earlier (by the automatic check), or nil.
function U.found()
    local s = gs()
    local v = s and s:readSetting(FOUND_KEY)
    if v and U.newer(v, U.current()) then return v end
end

local function download(release)
    local zip = zipPath()
    inBackground(fmt("Downloading Reading Log %1\xE2\x80\xA6", release.version), function()
        local ltn12 = require("ltn12")
        local fh = io.open(zip, "wb")
        if not fh then return { error = "can't write " .. zip } end
        local ok, err = get(release.url, ltn12.sink.file(fh), nil, true)
        if not ok then os.remove(zip); return { error = err } end
        return { ok = true }
    end, function(r)
        if not (r and r.ok) then
            info(fmt("The download didn't work: %1", r and r.error or "?"), 6)
            return
        end
        local ok, err = U.install(zip)
        os.remove(zip)
        if not ok then
            logger.warn("[readinglog] update could not be installed:", err)
            info(fmt("The update couldn't be installed: %1", err), 8)
            return
        end
        local s = gs()
        if s then s:delSetting(FOUND_KEY) end
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = fmt("Reading Log %1 is installed. Restart KOReader to use it?", release.version),
            ok_text = _("Restart"),
            cancel_text = _("Later"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end)
end

local function offer(release)
    local current = U.current()
    if not U.newer(release.version, current) then
        info(fmt("Reading Log is up to date (%1).", current), 4)
        return
    end
    local text = fmt("Reading Log %1 is available. You have %2.", release.version, current)
    if release.notes then text = text .. "\n\n" .. release.notes end
    local ConfirmBox = require("ui/widget/confirmbox")
    if not release.url then
        UIManager:show(ConfirmBox:new{
            text = text .. "\n\n" .. _("This release has no zip to download. Open the releases page?"),
            ok_text = _("Open"),
            ok_callback = function()
                local Device = require("device")
                if Device.canOpenLink and Device:canOpenLink() then Device:openLink(RELEASES_URL)
                else info(RELEASES_URL) end
            end,
        })
        return
    end
    UIManager:show(ConfirmBox:new{
        text = text .. "\n\n" .. _("Download and install it now?"),
        ok_text = _("Install"),
        ok_callback = function() download(release) end,
    })
end

-- "Check for updates" in the menu: connects if needed, says what it found.
function U.check()
    local function go()
        inBackground(_("Checking for updates\xE2\x80\xA6"), fetch, function(r)
            if not r or r.error then
                info(fmt("Couldn't check for updates: %1", r and r.error or "?"), 5)
                return
            end
            remember(r)
            offer(r)
        end)
    end
    local ok_n, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_n and NetworkMgr and NetworkMgr.runWhenOnline then NetworkMgr:runWhenOnline(go) else go() end
end

function U.autoEnabled()
    local s = gs()
    return s and s:isTrue(AUTO_KEY) or false
end

function U.setAuto(on)
    local s = gs()
    if s then s:saveSetting(AUTO_KEY, on and true or false) end
end

-- At start-up, once a day at most, only when already online (never turns
-- Wi-Fi on), and quietly: a newer version is mentioned once and shows in
-- the menu.
function U.autoCheck()
    if not U.autoEnabled() then return end
    local s = gs()
    local last = s and s:readSetting(LAST_KEY) or 0
    if type(last) ~= "number" or os.time() - last < DAY then return end
    UIManager:scheduleIn(8, function()
        local ok_n, NetworkMgr = pcall(require, "ui/network/manager")
        local online = ok_n and NetworkMgr and NetworkMgr.isOnline and NetworkMgr:isOnline()
        if not online then return end
        local had = U.found()
        local ok, r = pcall(fetch)
        if not ok or not r or r.error then return end
        remember(r)
        local v = U.found()
        if v and v ~= had then
            local Notification = require("ui/widget/notification")
            UIManager:show(Notification:new{ text = fmt("Reading Log %1 is available.", v) })
        end
    end)
end

return U
end
