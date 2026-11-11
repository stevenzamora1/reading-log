--[[
When each book was published, for the Decades card.

KOReader does not keep a book's publication date (its book info stops at
title, authors, series, language, description and keywords), so it is read
here out of the book file, the cheapest way each format allows:

  EPUB         the OPF's dc:date: one marked as the publication first, then
               one with no event (calibre's and EPUB 3's), then dcterms:issued
  FB2          publish-info's year (the edition), then title-info's date
  FB2.ZIP      the same, inside the zip
  CBZ          ComicInfo.xml's Year
  MOBI/AZW3    EXTH record 106 (publishing date)

PDFs and other formats have no date worth showing (a PDF's CreationDate is
usually when it was scanned), so they count as "no date".

With Bookshelf 6.4 or newer running, its own date for a book wins: the one
you typed in, or the one it already read from the file. Its Decades shelf
and this card then agree.

Each book is read once and kept with the file's modification time in
settings/readinglog_pubdates.lua; a changed file is read again. The reading
is done a batch at a time in a forked child (as KOReader's own cover
extraction is), so a big library never holds up a page turn, and the cards
that asked are redrawn as each batch comes in.
]]

local A = ...
local D = A.D
local floor = math.floor

local PD = {}
D.pubdates = PD

-- Bumped when a parser learns a new place to look: books stored with no date
-- are read again.
local READER = 1
local BATCH = 30          -- books per child
local POLL = 0.25         -- seconds between checks on the child
local TIMEOUT = 60        -- seconds before a stuck child is given up on

local _store, _dirty
local function store()
    if _store then return _store end
    local ok, s = pcall(function()
        local dir = require("datastorage"):getSettingsDir()
        return require("luasettings"):open(dir .. "/readinglog_pubdates.lua")
    end)
    _store = (ok and s) or { data = {}, flush = function() end }
    if type(_store.data) ~= "table" then _store.data = {} end
    local books = _store.data.books
    if type(books) ~= "table" then _store.data.books = {} end
    if _store.data.reader ~= READER then
        -- an older reader's "no date": look again
        for fp, e in pairs(_store.data.books) do
            if type(e) ~= "table" or e.y == 0 then _store.data.books[fp] = nil end
        end
        _store.data.reader = READER
        _dirty = true
    end
    return _store
end

local function save()
    if _dirty and _store then
        pcall(function() _store:flush() end)
        _dirty = false
    end
end

local function lfs()
    local ok, l = pcall(require, "libs/libkoreader-lfs")
    return ok and l or nil
end

local function mtimeOf(fp)
    local l = lfs()
    return l and l.attributes(fp, "modification") or nil
end

-- ─── dates out of text ───────────────────────────────────────────────────────

local THIS_YEAR = tonumber(os.date("%Y")) or 2100

-- A year someone meant: calibre writes 0101-01-01 for "no date", and an empty
-- field can come through as 0000.
local function validYear(y)
    y = tonumber(y)
    if y and y >= 1000 and y <= THIS_YEAR + 1 then return y end
    return nil
end

-- The year in an ISO date or timestamp, a compact date, or failing those the
-- first standalone four-digit year in free text ("1 Jan 1869").
function PD.yearOf(s)
    if type(s) ~= "string" then return nil end
    local y = validYear(s:match("^%s*D?:?(%d%d%d%d)"))
    if y then return y end
    for d in s:gmatch("%f[%d](%d%d%d%d)%f[%D]") do
        y = validYear(d)
        if y then return y end
    end
    return nil
end

local function unescape(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

-- fromOpf(opf) -> year | nil
function PD.fromOpf(opf)
    if type(opf) ~= "string" then return nil end
    local marked, plain, issued
    -- <dc:date opf:event="publication">1897-05-26</dc:date>
    for attrs, body in opf:gmatch("<[%w]*:?date([^>]*)>(.-)</[%w]*:?date>") do
        local y = PD.yearOf(unescape(body))
        if y then
            local event = attrs:match("event%s*=%s*[\"']([^\"']*)[\"']")
            if event then
                event = event:lower()
                if event == "publication" or event == "original-publication" or event == "issued" then
                    marked = marked or y
                end
            else
                plain = plain or y
            end
        end
    end
    -- <meta property="dcterms:issued">1897</meta> (never dcterms:modified)
    for attrs, body in opf:gmatch("<meta%s([^>]*)>(.-)</meta>") do
        if attrs:find("dcterms:issued", 1, true) or attrs:find("dcterms:date", 1, true) then
            issued = issued or PD.yearOf(unescape(body))
        end
    end
    -- <meta name="dcterms:issued" content="1897"/> (EPUB 2 style)
    if not issued then
        for attrs in opf:gmatch("<meta%s([^>]-)/?>") do
            if attrs:find("dcterms:issued", 1, true) then
                issued = PD.yearOf(attrs:match("content%s*=%s*[\"']([^\"']*)[\"']"))
                if issued then break end
            end
        end
    end
    return marked or plain or issued
end

-- fromFb2(xml) -> year | nil (the edition's year, then the work's date)
function PD.fromFb2(xml)
    if type(xml) ~= "string" then return nil end
    local pub = xml:match("<publish%-info>(.-)</publish%-info>")
    local y = pub and PD.yearOf(pub:match("<year>(.-)</year>"))
    if y then return y end
    local title = xml:match("<title%-info>(.-)</title%-info>")
    if title then
        local attrs, body = title:match("<date([^>]*)>(.-)</date>")
        if not attrs then attrs = title:match("<date([^>]*)/>") end
        y = attrs and PD.yearOf(attrs:match("value%s*=%s*[\"']([^\"']*)[\"']"))
        if y then return y end
        return body and PD.yearOf(body) or nil
    end
    return nil
end

-- fromComicInfo(xml) -> year | nil
function PD.fromComicInfo(xml)
    if type(xml) ~= "string" then return nil end
    return validYear((xml:match("<Year>%s*(%d+)%s*</Year>")))
end

-- fromMobi(bytes) -> year | nil: EXTH record 106 in record 0.
function PD.fromMobi(data)
    if type(data) ~= "string" or #data < 90 then return nil end
    local function u16(o) local a, b = data:byte(o + 1, o + 2); return a and b and (a * 256 + b) or nil end
    local function u32(o)
        local a, b, c, d = data:byte(o + 1, o + 4)
        if not d then return nil end
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    if u16(76) == nil or u16(76) < 1 then return nil end
    local r0 = u32(78)
    if not r0 or data:sub(r0 + 17, r0 + 20) ~= "MOBI" then return nil end
    local mobi_len = u32(r0 + 20)
    local flags = u32(r0 + 128)
    if not (mobi_len and flags) or flags % 128 < 64 then return nil end -- no EXTH
    local ex = r0 + 16 + mobi_len
    if data:sub(ex + 1, ex + 4) ~= "EXTH" then return nil end
    local count = u32(ex + 8) or 0
    local o = ex + 12
    for _ = 1, math.min(count, 500) do
        local typ, len = u32(o), u32(o + 4)
        if not (typ and len) or len < 8 then return nil end
        if typ == 106 then return PD.yearOf(data:sub(o + 9, o + len)) end
        o = o + len
    end
    return nil
end

-- ─── reading a file ──────────────────────────────────────────────────────────

local function readHead(fp, n)
    local f = io.open(fp, "rb")
    if not f then return nil end
    local s = f:read(n)
    f:close()
    return s
end

-- Entries of a zip, by a test on their names: { [path] = content }. Only small
-- entries are read; nil when the zip can't be opened.
local function fromZip(fp, want)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not (ok and Archiver and Archiver.Reader) then return nil end
    local r = Archiver.Reader:new()
    if not r:open(fp) then return nil end
    local out = {}
    local ok2 = pcall(function()
        for entry in r:iterate() do
            if entry.mode == "file" and entry.size < 2 * 1024 * 1024 and want(entry.path) then
                out[entry.path] = r:extractToMemory(entry.path)
            end
        end
    end)
    pcall(function() r:close() end)
    return ok2 and out or nil
end

local function ext(fp)
    local lower = fp:lower()
    if lower:match("%.fb2%.zip$") then return "fb2.zip" end
    return lower:match("%.([%w]+)$") or ""
end

-- PD.read(fp) -> year, or false when the file has none (or can't be read).
-- Opens the file; meant for the child process.
function PD.read(fp)
    local e = ext(fp)
    local y
    if e == "epub" or e == "kepub" then
        local got = fromZip(fp, function(p)
            local l = p:lower()
            return l == "meta-inf/container.xml" or l:match("%.opf$") ~= nil
        end)
        if got then
            local container
            for p, s in pairs(got) do if p:lower() == "meta-inf/container.xml" then container = s end end
            local root = container and container:match("full%-path%s*=%s*[\"']([^\"']+)[\"']")
            if root and got[root] then y = PD.fromOpf(got[root]) end
            if not y then
                for p, s in pairs(got) do
                    if p:lower():match("%.opf$") then y = PD.fromOpf(s); if y then break end end
                end
            end
        end
    elseif e == "fb2" then
        y = PD.fromFb2(readHead(fp, 64 * 1024))
    elseif e == "fb2.zip" then
        local got = fromZip(fp, function(p) return p:lower():match("%.fb2$") ~= nil end)
        if got then for _, s in pairs(got) do y = PD.fromFb2(s:sub(1, 64 * 1024)); break end end
    elseif e == "cbz" then
        local got = fromZip(fp, function(p) return p:lower():match("comicinfo%.xml$") ~= nil end)
        if got then for _, s in pairs(got) do y = PD.fromComicInfo(s); break end end
    elseif e == "mobi" or e == "azw" or e == "azw3" or e == "prc" then
        y = PD.fromMobi(readHead(fp, 512 * 1024))
    end
    return y or false
end

-- Formats that can carry a date. Everything else is "no date" without opening
-- the file.
local READABLE = { epub = true, kepub = true, fb2 = true, ["fb2.zip"] = true, cbz = true,
    mobi = true, azw = true, azw3 = true, prc = true }
function PD.readable(fp) return READABLE[ext(fp)] == true end

-- ─── Bookshelf's date ────────────────────────────────────────────────────────

-- With Bookshelf running: the date it already has for the book (yours, or one
-- it read from the file), without asking it to read anything.
local function bookshelfYear(fp)
    local Published = package.loaded["lib/bookshelf_published"]
    if type(Published) ~= "table" then return nil end
    if Published.userDate then
        local ok, d = pcall(Published.userDate, fp)
        local y = ok and PD.yearOf(d)
        if y then return y end
    end
    -- the dates it has read from files, all at once (one query a session)
    local F = package.loaded["lib/bookshelf_book_facts_db"]
    if type(F) == "table" and F.publishedMap then
        local ok, map = pcall(F.publishedMap)
        local e = ok and type(map) == "table" and map[fp]
        if type(e) == "table" and type(e.pd) == "string" and e.pd ~= "" then return PD.yearOf(e.pd) end
    end
    return nil
end

-- ─── the store ───────────────────────────────────────────────────────────────

local _checked = {}
-- Goes up whenever a date is learnt, so the card's list is worked out again.
local _gen = 0
local _memo

-- PD.year(fp) -> a year, false (no date), or nil (not read yet)
function PD.year(fp)
    local y = bookshelfYear(fp)
    if y then return y end
    local books = store().data.books
    local e = books[fp]
    if e then
        -- a file changed since its date was read is read again (checked once
        -- a session)
        if not _checked[fp] then
            _checked[fp] = true
            local m = mtimeOf(fp)
            if m and e.m and m ~= e.m then
                books[fp] = nil
                return nil
            end
        end
        return (e.y and e.y > 0) and e.y or false
    end
    if not PD.readable(fp) then return false end
    return nil
end

local function remember(fp, y, m)
    store().data.books[fp] = { y = y or 0, m = m }
    _checked[fp] = true
    _dirty = true
    _gen = _gen + 1
end

-- ─── reading in the background ───────────────────────────────────────────────

local _queue, _queued = {}, {}
local _waiters = {}
local _running, _broken = false, false
local _woke_at

local function wakeWaiters()
    local ws = _waiters
    _waiters = {}
    for _, r in ipairs(ws) do pcall(r) end
end

-- Read a batch: in a forked child when KOReader can make one, else here, a
-- few at a time. done(results) gets { [fp] = { y = year|0, m = mtime } }.
local function spawn(batch, done)
    local ok_u, util = pcall(require, "ffi/util")
    local UIManager = require("ui/uimanager")
    if not _broken and ok_u and util and util.runInSubProcess and util.isSubProcessDone and util.readAllFromFD then
        local dir = A.dir
        local pid, fd = util.runInSubProcess(function(_pid, write_fd)
            -- a fresh copy of the readers in the child (no card state needed)
            local chunk = loadfile(dir .. "/pubdates.lua")
            local P = { D = {} }
            local okc = pcall(chunk, P)
            local reader = okc and P.D.pubdates or nil
            local l = require("libs/libkoreader-lfs")
            local lines = {}
            for i, fp in ipairs(batch) do
                local y = false
                if reader then
                    local okr, v = pcall(reader.read, fp)
                    y = okr and v or false
                end
                lines[i] = tostring(y or 0) .. "\t" .. tostring(l.attributes(fp, "modification") or 0)
            end
            util.writeToFD(write_fd, table.concat(lines, "\n") .. "\n", true)
        end, true)
        if pid and fd then
            local waited = 0
            local function check()
                if util.isSubProcessDone(pid) then
                    local out = util.readAllFromFD(fd) or ""
                    local res, k = {}, 0
                    for line in out:gmatch("([^\n]*)\n") do
                        k = k + 1
                        local y, m = line:match("^(%d+)\t(%d+)$")
                        if batch[k] and y then res[batch[k]] = { y = tonumber(y), m = tonumber(m) } end
                    end
                    return done(res)
                end
                waited = waited + POLL
                if waited >= TIMEOUT then
                    pcall(util.terminateSubProcess, pid)
                    UIManager:scheduleIn(1, function() pcall(util.isSubProcessDone, pid) end)
                    pcall(util.readAllFromFD, fd)
                    -- given up on: these books count as having no date this session
                    local res = {}
                    for _, fp in ipairs(batch) do res[fp] = { y = 0, m = nil, skip = true } end
                    return done(res)
                end
                UIManager:scheduleIn(POLL, check)
            end
            UIManager:scheduleIn(POLL, check)
            return
        end
        _broken = true
    end
    -- no child: a few books per tick, here
    local res, i = {}, 0
    local function step()
        for _ = 1, 4 do
            i = i + 1
            local fp = batch[i]
            if not fp then return done(res) end
            local ok, y = pcall(PD.read, fp)
            res[fp] = { y = (ok and y) or 0, m = mtimeOf(fp) }
        end
        UIManager:scheduleIn(0.05, step)
    end
    UIManager:scheduleIn(0, step)
end

local run
run = function()
    if _running then return end
    if #_queue == 0 then
        save()
        wakeWaiters()
        return
    end
    _running = true
    local batch = {}
    while #batch < BATCH and #_queue > 0 do
        local fp = table.remove(_queue, 1)
        batch[#batch + 1] = fp
    end
    spawn(batch, function(res)
        _running = false
        for _, fp in ipairs(batch) do
            _queued[fp] = nil
            local r = res and res[fp]
            if r and not r.skip then
                remember(fp, r.y, r.m)
            elseif r and r.skip then
                store().data.books[fp] = nil
                _queued[fp] = "skip"
            end
        end
        save()
        -- the cards redraw with what has come in: after the first batch, then
        -- every so often (each redraw is a screen refresh), and at the end
        local now = os.time()
        if #_queue == 0 or not _woke_at or now - _woke_at >= 20 then
            _woke_at = now
            wakeWaiters()
        end
        if #_queue > 0 then require("ui/uimanager"):scheduleIn(0.5, run) end
    end)
end

-- PD.want(fps, refresh): read these books' dates in the background; refresh()
-- is called as batches come in.
function PD.want(fps, refresh)
    local added = false
    for _, fp in ipairs(fps) do
        if not _queued[fp] then
            _queued[fp] = true
            _queue[#_queue + 1] = fp
            added = true
        end
    end
    if refresh then
        local seen = false
        for _, r in ipairs(_waiters) do if r == refresh then seen = true break end end
        if not seen then _waiters[#_waiters + 1] = refresh end
    end
    if added and not _running then require("ui/uimanager"):scheduleIn(0.5, run) end
end

-- How many books are waiting to be read.
function PD.pending() return #_queue + (_running and BATCH or 0) end

-- Forget everything read (Diagnostics: read the dates again).
function PD.forget()
    store().data.books = {}
    _checked, _memo = {}, nil
    _gen = _gen + 1
    _dirty = true
    save()
end

-- ─── the Decades card's books ────────────────────────────────────────────────

--- The books for the Decades card, with the year each was published:
--- { rows = { {fp, title, author, year} } (oldest first), none = n (no date),
---   pending = n (not read yet), total = n }. scope "finished" counts finished
--- books only; coll limits it to one collection. nil while the library is
--- being counted.
function D.decades(refresh, scope, coll)
    local lib = D.library(refresh)
    if not lib then return lib end
    -- the same answer until the library, the settings or a date changes
    local set, set_n
    if coll and coll ~= "" then set, set_n = D.collectionSet(coll); set = set or {} end
    local key = table.concat({ tostring(lib), scope or "", coll or "", tostring(set_n), _gen }, "|")
    if _memo and _memo.key == key and _memo.value.pending == 0 then return _memo.value end
    local rows, none, unknown = {}, 0, {}
    local total = 0
    for _, b in ipairs(lib.books or {}) do
        if (scope ~= "finished" or b.status == "finished") and (not set or set[b.fp]) then
            total = total + 1
            local y = PD.year(b.fp)
            if y then
                rows[#rows + 1] = { fp = b.fp, title = b.title, author = b.authors and b.authors[1], year = y }
            elseif y == false or _queued[b.fp] == "skip" then
                none = none + 1
            else
                unknown[#unknown + 1] = b.fp
            end
        end
    end
    if #unknown > 0 then PD.want(unknown, refresh) end
    table.sort(rows, function(a, b)
        if a.year ~= b.year then return a.year < b.year end
        return (a.title or "") < (b.title or "")
    end)
    local value = { rows = rows, none = none, pending = #unknown, total = total }
    _memo = { key = key, value = value }
    return value
end

return PD
