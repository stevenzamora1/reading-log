--[[
Reading Log host adapter for Simple UI: everything the cards need from the app
around them.

They come from Simple UI where it has them (so the cards agree with Simple
UI's own modules) and from KOReader itself otherwise. host_bookshelf.lua
starts from this file and puts Bookshelf's answers in where Bookshelf has
them:

  settings          settings/readinglog.lua, a file of Reading Log's own, shared
                    with the Bookshelf cards (store.lua)
  card colour, ink  Simple UI's background and text colours
  fonts             Simple UI's UI font (with its bold/italic files), at exact
                    pixel sizes (its Global Text Size would make text overflow
                    a card drawn to fit)
  book facts        Simple UI's sidecar cache (custom metadata applied), and
                    CoverBrowser's database for genres
  finished books    Simple UI's finished-books ledger (same count as its
                    Reading goals module)
  goals             Simple UI's Reading goals (year books, minutes a day)
  covers            Simple UI's cover cache, which also queues extraction
  open / details    Simple UI's own book opening and book dialog
  tap actions       Simple UI's Quick Actions
  redraws           Simple UI's in-place repaint of one module, and a
                    once-a-minute tick for the cards that show the time

Every call into Simple UI is guarded: a Simple UI without some piece falls
back to KOReader, or to a full redraw of the screen.
]]

local A = ...
local H = {}
A.host = H

local floor, max, min = math.floor, math.max, math.min

-- ─── finding things ──────────────────────────────────────────────────────────

local _mods = {}
-- A module of Simple UI or KOReader, or nil when it is not there. Only hits
-- are remembered, so a module that loads later is still found.
local function try(name)
    local m = _mods[name]
    if m then return m end
    local ok, r = pcall(require, name)
    if ok and r then _mods[name] = r; return r end
    return nil
end
H.try = try

local function logger() return try("logger") end

--- Is Simple UI there (its module registry can be loaded)?
function H.available()
    return try("modules/moduleregistry") ~= nil
end

--- Simple UI's version, from its _meta.lua, or nil.
function H.version()
    for entry in package.path:gmatch("[^;]+") do
        local root = entry:match("^(.*simpleui%.koplugin)/%?%.lua$")
        if root then
            local ok, meta = pcall(dofile, root .. "/_meta.lua")
            if ok and type(meta) == "table" and meta.version then return meta.version end
        end
    end
    return nil
end

-- ─── settings file ───────────────────────────────────────────────────────────
-- settings/readinglog.lua, shared with the Bookshelf cards (store.lua).

local _St
local function sharedStore()
    if not _St then _St = dofile(A.dir .. "/store.lua") end
    return _St
end

local function settingsDir()
    return require("datastorage"):getSettingsDir()
end

function H.importBookshelf(s) return sharedStore().importBookshelf(s) end
function H.store() return sharedStore().file() end
function H.get(key) return sharedStore().get(key) end
function H.set(key, value) sharedStore().set(key, value) end

-- ─── text ────────────────────────────────────────────────────────────────────

local REPLACEMENT = "\xEF\xBF\xBD"
local MAX_TEXT = 4000

--- Text from book metadata or typed by the reader, made safe for the text
--- shaper: invalid UTF-8 replaced, control characters (but tab, newline and
--- carriage return) removed, absurd lengths cut.
function H.safeText(s)
    if type(s) ~= "string" then return "" end
    local util = try("util")
    if util and util.fixUtf8 then
        local ok, r = pcall(util.fixUtf8, s, REPLACEMENT)
        if ok and type(r) == "string" then s = r end
    end
    s = s:gsub("[%z\1-\8\11\12\14-\31\127]", "")
    if #s > MAX_TEXT then s = s:sub(1, MAX_TEXT) end
    return s
end

local _date_map
--- English day and month names in an os.date string, in the interface
--- language (KOReader's own translations of them).
function H.localizeDate(str)
    if type(str) ~= "string" then return str end
    if not _date_map then
        _date_map = {}
        local dt = try("datetime")
        if type(dt) == "table" then
            for eng, tr in pairs(dt.longMonthTranslation or {}) do _date_map[eng] = tr end
            for eng, tr in pairs(dt.shortMonthTranslation or {}) do _date_map[eng] = tr end
            for eng, tr in pairs(dt.shortDayOfWeekTranslation or {}) do _date_map[eng] = tr end
            local long = { Mon = "Monday", Tue = "Tuesday", Wed = "Wednesday", Thu = "Thursday",
                Fri = "Friday", Sat = "Saturday", Sun = "Sunday" }
            for short, eng_long in pairs(long) do
                local tr = (dt.shortDayOfWeekToLongTranslation or {})[short]
                if tr then _date_map[eng_long] = tr end
            end
        end
    end
    return (str:gsub("%a+", function(word) return _date_map[word] end))
end

local _textClass
function H.textClass()
    if _textClass then return _textClass end
    local ok, cls = pcall(dofile, A.dir .. "/colourtext.lua")
    _textClass = (ok and type(cls) == "table" and cls.new) and cls or require("ui/widget/textwidget")
    return _textClass
end

-- Font:getFace as KOReader has it, before Simple UI's Global Text Size
-- wraps it. Newer Simple UI keeps it on Font; 2.7.x on its plugin instance.
function H.nativeGetFace()
    local Font = require("ui/font")
    if Font._simpleui_native_getface then return Font._simpleui_native_getface end
    local UI = try("infra/sui_core")
    local plugin
    if UI and UI.getLivePlugin then
        local ok, p = pcall(UI.getLivePlugin)
        if ok then plugin = p end
    end
    if not plugin then
        local FM = package.loaded["apps/filemanager/filemanager"]
        plugin = FM and FM.instance and FM.instance._simpleui_plugin
    end
    return type(plugin) == "table" and plugin._orig_font_getface or nil
end

--- A face for text `size` (KOReader size units, already converted from
--- pixels) in Simple UI's UI font. Returns face, whether bold must be
--- synthesised. Simple UI's Global Text Size patches Font:getFace to scale
--- every face; the cards are drawn to fit their box, so they ask the
--- unpatched one, the way Simple UI's own fixed-size glyphs do.
function H.face(size, o)
    o = o or {}
    local Font = require("ui/font")
    local SUIStyle = try("features/sui_style")
    local variant = o.bold and (o.italic and "bolditalic" or "bold") or (o.italic and "italic" or "regular")
    local function get()
        if SUIStyle and SUIStyle.getStyledFace then
            return SUIStyle.getStyledFace(nil, size, variant)
        end
        return Font:getFace(o.bold and "tfont" or "cfont", size), false
    end
    local native = H.nativeGetFace()
    local ok, face, bold
    if native and Font.getFace ~= native then
        local patched = Font.getFace
        Font.getFace = native
        ok, face, bold = pcall(get)
        Font.getFace = patched
    else
        ok, face, bold = pcall(get)
    end
    if ok and face then return face, bold and true or false end
    return Font:getFace(o.bold and "tfont" or "cfont", size), false
end

-- ─── wallpaper ───────────────────────────────────────────────────────────────

--- Whether Simple UI shows its wallpaper through this module: a wallpaper is
--- on and the module's Background Opacity is below Solid. The Dashboard then
--- leaves its page unpainted, so the wallpaper shows between its cards.
function H.seeThrough(pfx, id)
    local WP = try("features/sui_wallpaper")
    if not (WP and WP.getModuleBackdropStrength) then return false end
    local ok, active = pcall(function()
        if WP.isWallpaperActive then return WP.isWallpaperActive() end
        return WP.styleGetBgWidget and WP.styleGetBgWidget() ~= nil
    end)
    if not (ok and active) then return false end
    local ok2, strength = pcall(WP.getModuleBackdropStrength, pfx or "simpleui_hs_", id)
    strength = ok2 and tonumber(strength) or 100
    return strength < 100
end

-- ─── colours ─────────────────────────────────────────────────────────────────

-- type(), not `c == nil`: a colour is FFI cdata, and == on cdata runs
-- Blitbuffer's __eq, which errors on nil.
local function rgbOf(c, fallback)
    if type(c) == "nil" then return fallback end
    local ok, r, g, b = pcall(function()
        local x = c:getColorRGB32()
        return x.r, x.g, x.b
    end)
    if ok and r then return { r, g, b } end
    return fallback
end

--- The page the cards sit on: Simple UI's background, its ink, its dim ink.
function H.pageColors()
    local SUIStyle = try("features/sui_style")
    local C = SUIStyle and SUIStyle.COLOR or {}
    return rgbOf(C.surface, { 255, 255, 255 }), rgbOf(C.text_primary, { 0, 0, 0 }),
           rgbOf(C.text_dim, { 0x8C, 0x8C, 0x8C })
end

-- ─── books ───────────────────────────────────────────────────────────────────

local function booksShared() return try("modules/module_books_shared") end

local function bookInfoManager()
    local Config = try("infra/sui_config")
    if Config and Config.getBookInfoManager then
        local ok, bim = pcall(Config.getBookInfoManager)
        if ok and bim then return bim end
    end
    return try("bookinfomanager")
end

-- A book's sidecar fields: Simple UI's cached copy, or DocSettings directly.
local function sidecar(fp)
    local SH = booksShared()
    if SH and SH.sidecarData then
        local ok, d = pcall(SH.sidecarData, fp, true)
        if ok and type(d) == "table" then return d end
        if ok then return nil end
    elseif SH and SH._cacheGet then
        -- Simple UI 2.7.x: its cache, when it has this book
        local ok, d = pcall(SH._cacheGet, fp)
        if ok and type(d) == "table" and d.summary ~= nil then return d end
    end
    local ok, d = pcall(function()
        local ds = require("docsettings"):open(fp)
        local stats = ds:readSetting("stats") or {}
        return {
            percent = ds:readSetting("percent_finished"),
            summary = ds:readSetting("summary"),
            doc_pages = ds:readSetting("doc_pages"),
            stat_pages = stats.pages,
            stat_total_time = stats.total_time_in_sec,
            partial_md5_checksum = ds:readSetting("partial_md5_checksum"),
        }
    end)
    return ok and d or nil
end
H.sidecar = sidecar

-- "Fantasy, Horror / Gothic; Classics" -> { "Fantasy", "Horror", "Gothic", "Classics" }
local function splitGenres(src)
    if type(src) ~= "string" or src == "" then return {} end
    local t = {}
    local norm = src:gsub("%s+/%s+", "\n")
    for part in norm:gmatch("[^,;|\n]+") do
        local s = part:match("^%s*(.-)%s*$")
        if s and s ~= "" then t[#t + 1] = s end
    end
    return t
end

--- { title, author, genres, series } for a file.
function H.bookMeta(fp)
    local title, authors, keywords, series
    local SH = booksShared()
    if SH and SH.getBookData then
        local ok, d = pcall(SH.getBookData, fp)
        if ok and type(d) == "table" then
            title, authors = d.title, d.authors
            -- getBookData falls back to "?" or the file name: let ours win
            if title == "?" then title = nil end
        end
    end
    local bim = bookInfoManager()
    if bim then
        local ok, info = pcall(bim.getBookInfo, bim, fp, false)
        if ok and type(info) == "table" then
            keywords, series = info.keywords, info.series
            if not title or title == "" then title = info.title end
            if not authors or authors == "" then authors = info.authors end
        end
    end
    local author
    if type(authors) == "string" and authors ~= "" then
        author = authors:match("^([^\n]+)") or authors
    end
    return { title = title, author = author, genres = splitGenres(keywords), series = series }
end

--- pct (0..1), status ("reading" | "finished" | "on_hold" | nil), pages,
--- opened. KOReader's "complete" / "abandoned" read as finished / on hold;
--- a book with progress but no status is being read.
function H.progress(fp)
    local d = sidecar(fp)
    if not d then return nil end
    local pct = tonumber(d.percent)
    local summary = type(d.summary) == "table" and d.summary or nil
    local st = summary and summary.status
    local status
    if st == "complete" then status = "finished"
    elseif st == "abandoned" then status = "on_hold"
    elseif st == "reading" then status = "reading" end
    if not status and pct and pct > 0 then status = "reading" end
    local pages = tonumber(d.doc_pages) or tonumber(d.stat_pages)
    if not pages then
        -- a "p(624)" page count in the file name, as Simple UI reads it
        local SH = booksShared()
        if SH and SH.pageCountFromFilename then pages = SH.pageCountFromFilename(fp) end
    end
    return pct, status, pages, (summary ~= nil or (pct or 0) > 0)
end

--- The date the book was marked finished: summary.date_finished, else
--- summary.modified.
function H.finishedOn(fp)
    local d = sidecar(fp)
    local s = d and type(d.summary) == "table" and d.summary or nil
    if not s then return nil end
    return s.date_finished or s.modified
end

--- Minutes left in the book at `pct`, from the sidecar's own reading speed
--- (the same estimate Simple UI's Currently reading module shows), or nil.
function H.timeLeft(fp, pct)
    local SH = booksShared()
    if not (SH and SH.getBookData) then return nil end
    local ok, d = pcall(SH.getBookData, fp)
    if not (ok and type(d) == "table") then return nil end
    local pages, avg = tonumber(d.pages), tonumber(d.avg_time)
    if not (pages and pages > 0 and avg and avg > 0) then return nil end
    local p = tonumber(pct) or tonumber(d.percent) or 0
    local left = max(0, 1 - p) * pages
    return floor(left * avg / 60 + 0.5)
end

-- ─── covers ──────────────────────────────────────────────────────────────────

--- handled, bitmap, pending. `handled` = Simple UI answered (bitmap may be
--- nil: no cover, or `pending` while it is being extracted). Its bitmaps
--- belong to its cache: drawn from, never freed.
function H.cover(fp, w, h, align)
    local Config = try("infra/sui_config")
    if not (Config and Config.getCroppedCoverBB) then return false end
    local ok, bb = pcall(Config.getCroppedCoverBB, fp, w, h, nil)
    if not ok then return false end
    if bb then return true, bb, false end
    local missing = Config.isCoverMissing and Config.isCoverMissing(fp)
    return true, nil, not missing
end

--- Whether a cover that was pending has been settled: "arrived", "none" (the
--- book has no cover) or nil (still being extracted).
function H.coverSettled(fp)
    local Config = try("infra/sui_config")
    if not (Config and Config.getCroppedCoverBB) then return "none" end
    if Config.isCoverMissing and Config.isCoverMissing(fp) then return "none" end
    local ok, bb = pcall(Config.getCroppedCoverBB, fp, 12, 18, nil)
    if ok and bb then return "arrived" end
    if not ok then return "none" end
    return nil
end

--- CoverBrowser's own cover bitmap (without Simple UI).
function H.rawCover(fp)
    local bim = bookInfoManager()
    if not bim then return nil end
    local ok, info = pcall(bim.getBookInfo, bim, fp, true)
    if ok and type(info) == "table" and not info.ignore_cover then return info.cover_bb end
    return nil
end

-- ─── the library ─────────────────────────────────────────────────────────────
-- Every book under KOReader's home folder, for Library stats, Most-read
-- authors and Random pick (the Bookshelf version asked Bookshelf's library).
-- Simple UI's own library scan when it has one (the books its Library module
-- shows, cached until a folder changes), else a bounded walk of our own.

local WALK_DEPTH, WALK_MAX = 8, 20000
local SKIP_DIRS = { proc = true, sys = true, dev = true, run = true, tmp = true, ["lost+found"] = true }

function H.homeDir()
    local LS = try("engines/sui_library_scan")
    if LS and LS.resolveHomeDir then
        local ok, h = pcall(LS.resolveHomeDir)
        if ok and type(h) == "string" and h ~= "" then return h end
    end
    local h = G_reader_settings and G_reader_settings:readSetting("home_dir")
    if type(h) ~= "string" or h == "" then
        local Device = try("device")
        h = Device and Device.home_dir
    end
    return h
end

local function ownWalk(home)
    local lfs = try("libs/libkoreader-lfs")
    local DR = try("document/documentregistry")
    if not lfs then return nil end
    local out = {}
    local function isBook(fp, name)
        if DR and DR.hasProvider then
            local ok, yes = pcall(DR.hasProvider, DR, fp)
            if ok then return yes and true or false end
        end
        local ext = name:match("%.([^.]+)$")
        ext = ext and ext:lower()
        return ext == "epub" or ext == "pdf" or ext == "mobi" or ext == "azw3" or ext == "fb2" or ext == "cbz"
            or ext == "djvu" or ext == "txt"
    end
    local function walk(dir, depth)
        if depth > WALK_DEPTH or #out >= WALK_MAX then return end
        local ok, iter, obj = pcall(lfs.dir, dir)
        if not ok then return end
        local subdirs = {}
        for name in iter, obj do
            if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                local fp = (dir:sub(-1) == "/") and (dir .. name) or (dir .. "/" .. name)
                local mode = lfs.attributes(fp, "mode")
                if mode == "directory" then
                    if not name:match("%.sdr$") and not SKIP_DIRS[name] then subdirs[#subdirs + 1] = fp end
                elseif mode == "file" and isBook(fp, name) then
                    out[#out + 1] = fp
                    if #out >= WALK_MAX then return end
                end
            end
        end
        for _, sub in ipairs(subdirs) do walk(sub, depth + 1) end
    end
    walk(home, 0)
    return out
end

--- The library's files, or nil when there is no home folder to look in.
function H.libraryFiles()
    local home = H.homeDir()
    local lfs = try("libs/libkoreader-lfs")
    if not (home and lfs and lfs.attributes(home, "mode") == "directory") then return nil end
    local LS = try("engines/sui_library_scan")
    if LS and LS.getFileList then
        local ok, list = pcall(LS.getFileList, home)
        if ok and type(list) == "table" then return list end
    end
    return ownWalk(home)
end

-- CoverBrowser's database read in one go: fp -> { title, authors = { ... },
-- genres = { ... }, series_name, series_num }. Read again only when the
-- database file has changed (a book was indexed since).
local _libmeta = { stamp = nil, map = nil }

local function splitLines(s)
    local t = {}
    if type(s) ~= "string" then return t end
    for part in s:gmatch("[^\n]+") do
        local v = part:match("^%s*(.-)%s*$")
        if v ~= "" then t[#t + 1] = v end
    end
    return t
end

function H.libraryMeta()
    local lfs = try("libs/libkoreader-lfs")
    if not lfs then return {} end
    local path = settingsDir() .. "/bookinfo_cache.sqlite3"
    local size = lfs.attributes(path, "size")
    if not size then return {} end
    local stamp = size .. ":" .. tostring(lfs.attributes(path, "modification") or 0)
    if _libmeta.stamp == stamp and _libmeta.map then return _libmeta.map end
    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_sq then return {} end
    local ok_c, conn = pcall(SQ3.open, path, "ro")
    if not (ok_c and conn) then return {} end
    local map = {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local stmt = conn:prepare("SELECT directory, filename, title, authors, series, series_index, keywords"
            .. " FROM bookinfo WHERE in_progress = 0")
        local row = stmt:step()
        while row do
            local dir, name = row[1], row[2]
            if type(dir) == "string" and type(name) == "string" then
                local genres = {}
                for _, g in ipairs(splitLines(row[7])) do
                    for _, part in ipairs(splitGenres(g)) do genres[#genres + 1] = part end
                end
                local series = type(row[5]) == "string" and row[5]:match("^%s*(.-)%s*$") or nil
                map[dir .. name] = {
                    title = type(row[3]) == "string" and row[3] or nil,
                    authors = splitLines(row[4]),
                    genres = genres,
                    series_name = (series ~= "") and series or nil,
                    series_num = tonumber(row[6]),
                }
            end
            row = stmt:step()
        end
        stmt:close()
    end)
    pcall(conn.close, conn)
    if not ok then
        local log = logger()
        if log then log.warn("[readinglog] library metadata read failed:", err) end
        return _libmeta.map or {}
    end
    _libmeta.stamp, _libmeta.map = stamp, map
    return map
end

-- ─── highlights (Quote of the day) ───────────────────────────────────────────
-- One of your own highlights a day, from the books in your history (the
-- Bookshelf version used Bookshelf's quote provider). How many highlights
-- each book has is kept in settings/readinglog_highlights.lua with its
-- sidecar's modification time, so a day's pick opens only the sidecar it
-- picks from, and only books opened since are counted again.

local HL_MIN, HL_MAX, HL_BOOKS = 10, 700, 400
local _hl_store

local function hlStore()
    if not _hl_store then
        _hl_store = require("luasettings"):open(settingsDir() .. "/readinglog_highlights.lua")
    end
    return _hl_store
end

local function cleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("\r", ""):gsub("[ \t]+", " "):match("^%s*(.-)%s*$")
    if #s < HL_MIN or #s > HL_MAX then return nil end
    return s
end

-- A book's highlights in reading order: { { text, chapter } }, its title, author.
local function bookHighlights(fp)
    local DocSettings = try("docsettings")
    if not DocSettings then return {} end
    local ok, ds = pcall(DocSettings.open, DocSettings, fp)
    if not (ok and ds) then return {} end
    local list = {}
    local ann = ds:readSetting("annotations")
    if type(ann) == "table" and #ann > 0 then
        for _, a in ipairs(ann) do
            if type(a) == "table" and a.drawer then
                local t = cleanText(a.text)
                if t then list[#list + 1] = { text = t, chapter = type(a.chapter) == "string" and a.chapter or nil } end
            end
        end
    else
        -- the older layout: { [page] = { { text = ... }, ... } }
        local hl = ds:readSetting("highlight")
        if type(hl) == "table" then
            local pages = {}
            for page in pairs(hl) do pages[#pages + 1] = page end
            table.sort(pages, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
            for _, page in ipairs(pages) do
                if type(hl[page]) == "table" then
                    for _, h in ipairs(hl[page]) do
                        local t = type(h) == "table" and cleanText(h.text)
                        if t then list[#list + 1] = { text = t, chapter = type(h.chapter) == "string" and h.chapter or nil } end
                    end
                end
            end
        end
    end
    local props = ds:readSetting("doc_props")
    local title, author
    if type(props) == "table" then
        if type(props.title) == "string" and props.title ~= "" then title = props.title end
        if type(props.authors) == "string" and props.authors ~= "" then author = props.authors:match("^[^\n]+") end
    end
    return list, title, author
end

-- { { fp, n } } for every book in the history with highlights, by file.
local function highlightCounts()
    local RH = try("readhistory")
    local DocSettings = try("docsettings")
    local lfs = try("libs/libkoreader-lfs")
    if not (RH and type(RH.hist) == "table" and DocSettings and lfs) then return {} end
    local store = hlStore()
    local counts = store:readSetting("counts")
    if type(counts) ~= "table" then counts = {} end
    local out, seen, changed = {}, {}, false
    for i, e in ipairs(RH.hist) do
        if i > HL_BOOKS then break end
        local fp = e.file
        if type(fp) == "string" and not seen[fp] and lfs.attributes(fp, "mode") == "file" then
            seen[fp] = true
            local ok, sidecar = pcall(DocSettings.findSidecarFile, DocSettings, fp)
            local mtime = ok and sidecar and lfs.attributes(sidecar, "modification")
            if mtime then
                local c = counts[fp]
                if not (type(c) == "table" and c.m == mtime) then
                    c = { m = mtime, n = #(bookHighlights(fp)) }
                    counts[fp] = c
                    changed = true
                end
                if (tonumber(c.n) or 0) > 0 then out[#out + 1] = { fp = fp, n = c.n } end
            end
        end
    end
    -- forget books no longer in the history
    for fp in pairs(counts) do
        if not seen[fp] then counts[fp] = nil; changed = true end
    end
    if changed then
        store:saveSetting("counts", counts)
        store:flush()
    end
    table.sort(out, function(a, b) return a.fp < b.fp end)
    return out
end

-- A 32-bit hash that spreads its input well (FNV-1a with murmur's finish),
-- so the picks for "today#1" and "today#2" land far apart. (A plain running
-- hash put them one apart, and Another walked a book's highlights in order.)
local M32 = 4294967296
local bit = require("bit")
local function mul32(a, b)
    local ah, al = floor(a / 65536), a % 65536
    return ((ah * b) % 65536 * 65536 + al * b) % M32
end
local function xor32(a, b) return bit.bxor(a, b) % M32 end
local function hash(str)
    local h = 2166136261
    for i = 1, #str do h = mul32(xor32(h, str:byte(i)), 16777619) end
    h = mul32(xor32(h, floor(h / 65536)), 0x85EBCA6B)
    h = mul32(xor32(h, floor(h / 8192)), 0xC2B2AE35)
    return xor32(h, floor(h / 65536))
end
H.hash = hash

-- Which highlight to show for today's nth pick: any highlight, chosen evenly,
-- but never the one just shown, and never a third in a row from one book
-- while there are others. Returns the book's file and the highlight's place
-- in it.
local function pickQuote(books, total, today, roll, attempt, also_avoid)
    local avoid = (roll.fp and (tonumber(roll.streak) or 0) >= 2 and #books > 1) and roll.fp or nil
    local pool, sum = {}, 0
    for _, b in ipairs(books) do
        if b.fp ~= avoid and b.fp ~= also_avoid then pool[#pool + 1] = b; sum = sum + b.n end
    end
    if sum == 0 then pool, sum = books, total end
    local k = hash(today .. "#" .. tostring(roll.n or 0) .. (attempt > 0 and ("#" .. attempt) or "")) % sum
    for _, b in ipairs(pool) do
        if k < b.n then return b.fp, k end
        k = k - b.n
    end
    return pool[1].fp, 0
end

--- Today's highlight: { text, filepath, title, author, chapter }, or false
--- when there are none. The pick is kept (quote_roll), so every redraw shows
--- the same one until Another asks for the next.
---   quote_roll = { day, n (today's picks so far), fp and hi (the highlight
---   shown), th (its text's hash), streak (how many in a row from fp),
---   shown (fp/hi is the pick for n) }
function H.quoteOfTheDay()
    local books = highlightCounts()
    local total = 0
    for _, b in ipairs(books) do total = total + b.n end
    if total == 0 then return false end
    local today = os.date("%Y-%m-%d")
    local roll = A.get("quote_roll", nil)
    if type(roll) ~= "table" or roll.day ~= today then roll = { day = today, n = 0 } end
    local fp, hi = roll.fp, tonumber(roll.hi)
    local book
    for _, b in ipairs(books) do if b.fp == fp then book = b break end end
    local fresh = not (roll.shown and book and hi and hi >= 0 and hi < book.n)
    local list, title, author
    if fresh then
        -- never the quote just shown (the same text, from either picker): the
        -- book's next highlight, or another book when that was its only one
        local skip
        for attempt = 0, 5 do
            fp, hi = pickQuote(books, total, today, roll, attempt, skip)
            list, title, author = bookHighlights(fp)
            if #list > 0 then
                hi = hi % #list
                if not (roll.th and hash(list[hi + 1].text) == roll.th) then break end
                if #list > 1 then hi = (hi + 1) % #list; break end
                skip = fp
            end
        end
    else
        list, title, author = bookHighlights(fp)
    end
    if #list == 0 then return false end
    hi = hi % #list
    if fresh then
        local streak = (fp == roll.fp) and ((tonumber(roll.streak) or 0) + 1) or 1
        A.set("quote_roll", { day = today, n = roll.n or 0, fp = fp, hi = hi, th = hash(list[hi + 1].text),
            streak = streak, shown = true })
    end
    local h = list[hi + 1]
    return { text = h.text, chapter = h.chapter, filepath = fp,
             title = title or (fp:match("([^/]+)%.[^.]+$") or fp), author = author }
end

--- "Another": a fresh pick for today (see pickQuote).
function H.rerollQuote()
    local today = os.date("%Y-%m-%d")
    local roll = A.get("quote_roll", nil)
    if type(roll) ~= "table" or roll.day ~= today then roll = { day = today, n = 0 } end
    roll.n = (tonumber(roll.n) or 0) + 1
    roll.shown = nil
    A.set("quote_roll", roll)
end

-- ─── finished books and goals ────────────────────────────────────────────────

local function parseStamp(s)
    if type(s) ~= "string" then return nil end
    local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then return tonumber(y), tonumber(m), tonumber(d) end
    y = s:match("^(%d%d%d%d)")
    return y and tonumber(y) or nil
end

--- The books Simple UI counts as finished, in the shape the data layer reads:
---   { books = { { fp, y, m, d, excluded } }, extra = { [year] = n } }
--- `extra`: books it counts that have no file here (entered by hand, or the
--- file is gone). Newer Simple UI keeps a finished-books ledger; 2.7.x works it
--- out from the sidecars of the books in the history each time, by the rule
--- copied here. Either way the year's count matches its Reading goals.
function H.finishedBooks()
    local SP = try("modules/module_stats_provider")
    if SP and SP.getFinishedBooks then
        local ok, books = pcall(SP.getFinishedBooks)
        if ok and type(books) == "table" then
            local out, extra = {}, {}
            for _, b in ipairs(books) do
                local y, m, d = parseStamp(b.date_finished)
                y = y or tonumber(b.year)
                if b.filepath and not b.manual then
                    out[#out + 1] = { fp = b.filepath, y = y, m = m, d = d, excluded = b.exclude_from_goals and true or false }
                elseif y and not b.exclude_from_goals then
                    extra[y] = (extra[y] or 0) + (tonumber(b.count) or 1)
                end
            end
            return { books = out, extra = extra }
        end
    end
    if not H.available() then return nil end
    -- Simple UI 2.7.x: "complete" in the sidecar, in the year of its
    -- date_finished (or a written-out summary.modified). A numeric modified is
    -- only the last time the book was closed, so it is no finish date; then
    -- the day it was last opened stands in, as Reading Log always did.
    local RH = package.loaded["readhistory"] or try("readhistory")
    local lfs = try("libs/libkoreader-lfs")
    if not (RH and type(RH.hist) == "table" and lfs) then return nil end
    local out, seen, md5s = {}, {}, {}
    for _, e in ipairs(RH.hist) do
        local fp = e.file
        if fp and not seen[fp] and lfs.attributes(fp, "mode") == "file" then
            seen[fp] = true
            local d = sidecar(fp)
            local sm = d and type(d.summary) == "table" and d.summary or nil
            if sm and sm.status == "complete" then
                if d.partial_md5_checksum then md5s[d.partial_md5_checksum] = true end
                local stamp = sm.date_finished
                if stamp == nil and type(sm.modified) == "string" then stamp = sm.modified end
                local y, m, dd = parseStamp(stamp)
                if not y and e.time then
                    local t = os.date("*t", e.time)
                    y, m, dd = t.year, t.month, t.day
                end
                out[#out + 1] = { fp = fp, y = y, m = m, d = dd, excluded = sm.exclude_from_goals and true or false }
            end
        end
    end
    -- finished books kept after their file was deleted (when that is on)
    local extra = {}
    local Store = try("infra/sui_store")
    local Deleted = Store and Store.DeletedBooks
    if Deleted and Deleted.isEnabled then
        local ok, on = pcall(Deleted.isEnabled)
        if ok and on then
            local ok2, all = pcall(Deleted.getAll)
            for md5, entry in pairs(ok2 and type(all) == "table" and all or {}) do
                local y = type(entry) == "table" and tonumber(entry.year)
                if y and not md5s[md5] then extra[y] = (extra[y] or 0) + 1 end
            end
        end
    end
    return { books = out, extra = extra }
end

-- Reading goals are Simple UI's settings, under the same keys in 2.7.x and
-- newer: books this year, books read outside KOReader (2.7.x; newer versions
-- list those as books of their own, already in the count), seconds a day.
local KEY_ANNUAL, KEY_PHYSICAL, KEY_DAILY =
    "simpleui_reading_goal", "simpleui_reading_goal_physical", "simpleui_daily_reading_goal_secs"

local function suiStore()
    local S = try("infra/sui_store")
    if S and S.readSetting and S.saveSetting then return S end
    return nil
end

-- Simple UI's goal module and figures redraw after a goal changes.
local function goalsChanged()
    local G = try("infra/sui_goals")
    local SP = package.loaded["modules/module_stats_provider"]
    if SP and SP.invalidate then pcall(SP.invalidate) end
    if G then
        local HS = package.loaded["screens/sui_homescreen"]
        if HS and HS.refresh then pcall(HS.refresh, false) end
    end
end

local function hasLedger()
    local SP = try("modules/module_stats_provider")
    return SP and SP.getFinishedBooks and true or false
end

--- Books to read this year, and books read outside KOReader.
function H.yearGoal()
    local S = suiStore()
    if S then
        local target = tonumber(S:readSetting(KEY_ANNUAL)) or 12
        local other = hasLedger() and 0 or (tonumber(S:readSetting(KEY_PHYSICAL)) or 0)
        return max(1, target), max(0, other)
    end
    local other = A.get("other_books", nil)
    local n = (type(other) == "table" and tonumber(other.year) == os.date("*t").year) and tonumber(other.n) or 0
    return A.get("year_goal", 24), n
end

function H.setYearGoal(n)
    local S = suiStore()
    if not S then return A.set("year_goal", n) end
    local G = try("infra/sui_goals")
    if G and G.setUnits then
        pcall(G.setUnits, "annual", min(365, max(1, n)))
    else
        S:saveSetting(KEY_ANNUAL, min(365, max(1, n)))
        goalsChanged()
    end
end

function H.setOtherBooks(n)
    local S = suiStore()
    if S and not hasLedger() then
        S:saveSetting(KEY_PHYSICAL, max(0, n))
        goalsChanged()
    else
        A.set("other_books", { year = os.date("*t").year, n = n })
    end
end

--- Whether "Read outside KOReader" is a setting here (true), or Simple UI
--- lists those books itself (false).
function H.ownOtherBooks()
    return not hasLedger()
end

--- Minutes a day, or nil when no daily goal is set.
function H.dailyMinutesGoal()
    local S = suiStore()
    if S then
        local secs = tonumber(S:readSetting(KEY_DAILY))
        if secs and secs > 0 then return max(1, floor(secs / 60 + 0.5)) end
        return nil
    end
    return A.get("daily_minutes", nil)
end

function H.setDailyMinutesGoal(minutes)
    local S = suiStore()
    if not S then return A.set("daily_minutes", minutes) end
    minutes = min(720, max(1, minutes))
    local G = try("infra/sui_goals")
    if G and G.setUnits then
        pcall(G.setUnits, "daily", minutes)
    else
        S:saveSetting(KEY_DAILY, minutes * 60)
        goalsChanged()
    end
end

-- How the goal settings describe themselves, and their limits.
H.GOALS = {
    year_max = 365, daily_max = 720,
    year_note = A._("Shared with Simple UI's Reading goals (annual goal)."),
    daily_note = A._("Shared with Simple UI's Reading goals (daily goal)."),
}
H.KIND = "simpleui"

-- ─── opening books ───────────────────────────────────────────────────────────

-- The Simple UI screen ctx a card ctx belongs to (nil in settings menus).
local function sui(ctx) return type(ctx) == "table" and ctx.sui or nil end

function H.openBook(ctx, fp)
    local s = sui(ctx)
    if s and type(s.open_fn) == "function" then
        local ok = pcall(s.open_fn, fp)
        if ok then return end
    end
    require("apps/reader/readerui"):showReader(fp)
end

function H.showDetails(ctx, fp)
    local s = sui(ctx)
    if s and type(s.hold_fn) == "function" then
        local ok = pcall(s.hold_fn, fp, ctx.mod_id)
        if ok then return end
    end
    local FM = package.loaded["apps/filemanager/filemanager"]
    local fm = FM and FM.instance
    if fm and fm.bookinfo and fm.bookinfo.show then
        local ok = pcall(fm.bookinfo.show, fm.bookinfo, fp)
        if ok then return end
    end
    A.D.openBook(ctx, fp)
end

-- ─── tap actions ─────────────────────────────────────────────────────────────

--- Simple UI's Quick Actions, as { { id, label } }, built-in ones then the
--- reader's own (custom) ones.
function H.quickActions()
    local QA = try("features/sui_quickactions")
    if not QA then return {} end
    local out, seen = {}, {}
    local function add(id)
        if type(id) ~= "string" or seen[id] then return end
        seen[id] = true
        local label = id
        local ok, e = pcall(QA.getEntry, id)
        if ok and type(e) == "table" then
            local l = e.label
            if type(l) == "function" then
                local ok2, r = pcall(l, id)
                l = ok2 and r or nil
            end
            if type(l) == "string" and l ~= "" then label = l end
        end
        out[#out + 1] = { id = id, label = label }
    end
    local ok, ids = pcall(function() return QA.allIds and QA.allIds() end)
    for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do add(id) end
    local ok2, custom = pcall(function() return QA.getCustomQAList and QA.getCustomQAList() end)
    for _, id in ipairs(ok2 and type(custom) == "table" and custom or {}) do add(id) end
    return out
end

function H.runQuickAction(ctx, id)
    local s = sui(ctx)
    if s and type(s.on_qa_tap) == "function" then
        local ok = pcall(s.on_qa_tap, id)
        if ok then return true end
    end
    local UI = try("infra/sui_core")
    if UI and UI.makeQaTap then
        local ok = pcall(UI.makeQaTap(), id)
        if ok then return true end
    end
    local QA = try("features/sui_quickactions")
    if QA and QA.execute then return pcall(QA.execute, id, {}) end
    return false
end

-- ─── screens ─────────────────────────────────────────────────────────────────

local function engine() return package.loaded["engines/sui_screen_engine"] or try("engines/sui_screen_engine") end

-- Is `screen` (a Simple UI ScreenWidget) open and in front?
local function live(screen)
    if type(screen) ~= "table" then return false end
    local SE = engine()
    if SE and SE.getInstance and screen._id ~= nil and SE.getInstance(screen._id) ~= screen then return false end
    if type(screen.isActive) == "function" then
        local ok, active = pcall(screen.isActive, screen)
        if ok and not active then return false end
    end
    return true
end
H.live = live

local function suspended()
    local Device = try("device")
    if Device and Device.screen_saver_mode then return true end
    local FM = package.loaded["apps/filemanager/filemanager"]
    local plugin = FM and FM.instance and FM.instance._simpleui_plugin
    return plugin and plugin._simpleui_suspended and true or false
end

local function reading()
    local RUI = package.loaded["apps/reader/readerui"]
    return RUI and RUI.instance and true or false
end

--- Redraw every open Simple UI screen (a theme or accent changed).
function H.redrawAll()
    local SE = engine()
    if SE and SE.refreshAllLiveImmediate then
        if pcall(SE.refreshAllLiveImmediate, true) then return end
    end
    local HS = package.loaded["screens/sui_homescreen"]
    if HS and HS.refresh then pcall(HS.refresh, false) end
end

--- Redraw the card `ctx` belongs to, in place.
---   o.flash   a flashing refresh (the dashboard turned a page)
---   o.strip   { y, h }: only this band changed (the clock); refresh just it
--- A ctx from a settings menu redraws through the menu's own refresh.
function H.repaint(ctx, o)
    o = o or {}
    if type(ctx) ~= "table" then return H.redrawAll() end
    if ctx.menu_refresh then
        pcall(ctx.menu_refresh)
        return
    end
    local screen, mod_id = ctx.screen, ctx.mod_id
    if not (screen and mod_id and live(screen)) then return end
    local UIManager = require("ui/uimanager")
    local slot = screen._book_mod_slots and screen._book_mod_slots[mod_id]
    -- where this card was last painted: its own tap box (every Simple UI)
    local painted = ctx._box and ctx._box.dimen
    if not slot then
        -- not on this page, or a Simple UI without in-place repaints
        if screen._book_mod_slots == nil and screen._refreshImmediate then
            pcall(screen._refreshImmediate, screen, true)
        end
        return
    end

    -- The clock: rebuild quietly and refresh only its band of the screen.
    if o.strip and screen._buildModWidget and screen._makeModWrapper and screen._ctx_cache then
        local old = painted
        local ok = pcall(function()
            local widget, content = screen:_buildModWidget(slot.mod, slot.col_w, screen._ctx_cache)
            if not widget then error("no widget") end
            screen:_makeModWrapper(slot.mod, widget, slot.col_w)
            slot.widget = widget
            if slot.content ~= nil then slot.content = content end
        end)
        if ok then
            local region
            if old and old.x and old.w and old.w > 0 then
                local Geom = require("ui/geometry")
                region = Geom:new{ x = old.x, y = old.y + floor(o.strip.y or 0),
                    w = old.w, h = max(1, floor(o.strip.h or old.h)) }
            else
                local wrapper = screen._wrapper_pool and screen._wrapper_pool[mod_id]
                region = wrapper and wrapper.dimen
            end
            UIManager:setDirty(screen, function() return "ui", region, true end)
            return
        end
    end

    local done = false
    if screen._refreshBookModSlot then
        local ok, r = pcall(screen._refreshBookModSlot, screen, mod_id)
        done = ok and r
    end
    if not done then
        if screen._refreshImmediate then pcall(screen._refreshImmediate, screen, true) end
        return
    end
    if o.flash or o.turn then
        local wrapper = screen._wrapper_pool and screen._wrapper_pool[mod_id]
        local region = wrapper and wrapper.dimen
        if region then
            -- a page turn: a quick ghost-clearing update, which KOReader turns
            -- into a flash every "Full refresh rate" updates, like a book's pages
            local kind = o.turn and "partial" or "flashui"
            UIManager:setDirty(screen, function() return kind, region, true end)
        end
    end
end

-- ─── the minute tick ─────────────────────────────────────────────────────────
-- Cards showing the time (the Banner, the Dashboard's Today page) ask for a
-- redraw once a minute, at the start of each minute like Simple UI's own
-- clock. Only the clock's band of the screen is refreshed. The tick stops
-- while the device sleeps, a book is open or the screen is closed, and
-- starts again the next time one of those cards is drawn.

local _tick = { timer = nil, entries = setmetatable({}, { __mode = "k" }) }

local function tickNow()
    _tick.timer = nil
    if suspended() then return end
    local any = false
    for screen, per in pairs(_tick.entries) do
        if live(screen) and not screen._suspended then
            for _, e in pairs(per) do
                any = true
                -- (nothing while the screen is under a book)
                if not reading() then
                    if e.poll then
                        -- a polled card: redrawn only when what it shows changed
                        local ok, now = pcall(e.poll.check)
                        if ok and now ~= e.poll.seen then
                            e.poll.seen = now
                            pcall(H.repaint, e.ctx, {})
                        end
                    else
                        pcall(H.repaint, e.ctx, { strip = e.strip })
                    end
                end
            end
        else
            _tick.entries[screen] = nil
        end
    end
    if any then H.scheduleTick() end
end

function H.scheduleTick()
    if _tick.timer then return end
    local UIManager = require("ui/uimanager")
    _tick.timer = tickNow
    UIManager:scheduleIn(60 - (os.time() % 60) + 1, tickNow)
end

--- A card that shows the time was drawn. strip = { y, h } (its clock band
--- inside the card), or nil when it shows no clock now. Or a polled card
--- (the Device card): poll = { check = fn, seen = what it showed }.
function H.wantTick(ctx, strip, poll)
    local screen = type(ctx) == "table" and ctx.screen
    if not screen or not ctx.mod_id then return end
    local per = _tick.entries[screen]
    if not per then per = {}; _tick.entries[screen] = per end
    if strip or poll then
        per[ctx.mod_id] = { ctx = ctx, strip = strip, poll = poll }
        H.scheduleTick()
    else
        per[ctx.mod_id] = nil
    end
end

function H.stopTick()
    if _tick.timer then
        pcall(function() require("ui/uimanager"):unschedule(_tick.timer) end)
        _tick.timer = nil
    end
end

return H
