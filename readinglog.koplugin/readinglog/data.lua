--[[
Reading Log data: everything the cards show, read from where KOReader and
Simple UI already keep it.

  reading list    ReadHistory + each book's sidecar (Simple UI's sidecar cache)
  finished books  Simple UI's finished-books ledger, so the counts agree with
                  its Reading goals; ReadHistory + sidecars without it
  reading stats   statistics.sqlite3, opened read-only
  covers          Simple UI's cover cache (CoverBrowser's database underneath)
  collections     KOReader's ReadCollection

Nothing here writes to any of those. Slow reads (the statistics scans, the
year's finished books) run off the paint path: the card shows what it has,
the query runs on the next tick, and the card redraws when it lands.
All host calls go through A.host (host.lua).
]]

local A = ...
local T = A._
local D = {}
A.D = D

local floor, max, min = math.floor, math.max, math.min

local function lfs()
    local ok, m = pcall(require, "libs/libkoreader-lfs")
    return ok and m or nil
end

function D.fileExists(fp)
    local l = lfs()
    if not (l and type(fp) == "string") then return false end
    return l.attributes(fp, "mode") == "file"
end

-- ─── deferred, cached reads ──────────────────────────────────────────────────
-- slot(refresh) returns: a table (data), false (looked, nothing there) or nil
-- (first load still running). When stale it hands back what it has and
-- recomputes in the background, then calls every waiting refresh once.

local _slots = {}

-- o.ttl   seconds a result stays fresh (default 60)
-- o.key   optional function: the result is also stale once key() changes
-- o.sig   optional function(value) -> string: waiting cards are only asked
--         to redraw when this changes, so a recheck that finds nothing new
--         does not repaint the screen
-- o.heavy never worked out in a hurry (see D.hurry): it can take seconds
--
-- D.hurry(seconds): for that long, a read that is needed is worked out on the
-- spot instead of in the background (when it took less than the time left
-- last time), so a page that was just turned to is drawn whole, once,
-- rather than drawn with gaps and then again when the reads land: less
-- waiting, and one screen update instead of two.
--
-- Times are wall-clock seconds (KOReader's monotonic clock): reading the
-- statistics database or a sidecar waits on the disk, which CPU time misses.
local _wall
local function wall()
    if not _wall then
        local ok, time = pcall(require, "ui/time")
        if ok and type(time) == "table" and time.now and time.to_s then
            _wall = function() return time.to_s(time.now()) end
        else
            _wall = os.clock
        end
    end
    return _wall()
end
D.wall = wall
function D.hurry(secs) D._hurry_until = wall() + (secs or 0.3) end

local function deferred(name, o, compute)
    local s = { at = 0, value = nil, busy = false, waiters = {}, key = nil, sig = nil, sticky = o.sticky, cost = nil }
    _slots[name] = s
    local ttl = o.ttl or 60
    local function fresh()
        return s.value ~= nil and os.time() - s.at < ttl and (not o.key or o.key() == s.key)
    end
    local function run()
        local key = o.key and o.key() or nil
        local t0 = wall()
        local ok, v = pcall(compute)
        s.cost = wall() - t0
        if not ok then A.log(name, "failed:", v) end
        local first = s.value == nil
        s.value = (ok and v) or false
        s.at, s.key = os.time(), key
        local sig = (o.sig and s.value) and o.sig(s.value) or tostring(s.value)
        local changed = first or sig ~= s.sig or not o.sig
        s.sig = sig
        return changed
    end
    return function(refresh, sync)
        if fresh() then return s.value end
        if sync then run() return s.value end
        local until_ = D._hurry_until
        if until_ and not o.heavy then
            local left = until_ - wall()
            if left > 0 and (s.cost or 0.05) < left then
                run()
                return s.value
            end
        end
        if refresh then
            local seen = false
            for _, r in ipairs(s.waiters) do if r == refresh then seen = true break end end
            if not seen then s.waiters[#s.waiters + 1] = refresh end
        end
        if not s.busy then
            s.busy = true
            require("ui/uimanager"):scheduleIn(0, function()
                -- (already worked out meanwhile, in a hurry: just tell the waiters)
                local changed = true
                if not fresh() then changed = run() end
                s.busy = false
                local ws = s.waiters
                s.waiters = {}
                if changed then
                    for _, r in ipairs(ws) do pcall(r) end
                end
            end)
        end
        return s.value
    end
end

-- Drop everything cached (after a setting changed, or on request).
function D.invalidate()
    for _, s in pairs(_slots) do if not s.sticky then s.at = 0 end end
    D._reading = nil
    D._info_reset()
end

-- ─── per-book facts ──────────────────────────────────────────────────────────

local _info = {}
function D._info_reset() _info = {} end

-- Title / author / genres / series for a file (custom metadata applied).
function D.info(fp)
    local c = _info[fp]
    if c then return c end
    local ok, rec = pcall(A.host.bookMeta, fp)
    if not ok or type(rec) ~= "table" then rec = {} end
    local name = (fp:match("([^/]+)$") or fp):gsub("%.[^.]+$", "")
    c = {
        title = (rec.title and rec.title ~= "" and rec.title) or name,
        author = rec.author,
        genres = type(rec.genres) == "table" and rec.genres or {},
        series = rec.series,
    }
    _info[fp] = c
    return c
end

-- pct (0..1), status ("reading" | "finished" | "on_hold" | "new" (not
-- started) | nil), pages, opened
function D.progress(fp)
    local ok, pct, status, pages, opened = pcall(A.host.progress, fp)
    if ok then return pct, status, pages, opened end
    return nil
end

-- The date a book was marked finished ("YYYY-MM-DD", or a timestamp), or nil.
function D.finishedOn(fp)
    local ok, d = pcall(A.host.finishedOn, fp)
    return ok and d or nil
end

local function ymOf(d)
    if type(d) == "string" then
        local y, m, dd = d:match("^(%d%d%d%d)%-(%d%d)%-?(%d?%d?)")
        if y then return tonumber(y), tonumber(m), tonumber(dd) end
        return nil
    end
    if type(d) == "number" then
        local t = os.date("*t", d)
        return t.year, t.month, t.day
    end
    if type(d) == "table" and tonumber(d.year) then
        return tonumber(d.year), tonumber(d.month), tonumber(d.day)
    end
    return nil
end

local function history()
    local ok, rh = pcall(require, "readhistory")
    if ok and rh and type(rh.hist) == "table" then return rh.hist end
    return {}
end

-- ─── currently reading ───────────────────────────────────────────────────────
-- Newest first. A book counts while its status is "reading", or it has no
-- status yet but has been started and not finished. The book you have open
-- (or opened last) counts too, even at 0%, unless it's marked finished or
-- on hold: it's the one Bookshelf's and Simple UI's own top card show.

-- The list is kept until the reading history changes (a book opened), a
-- setting changes, or two minutes pass; rescanning the history (and each
-- book's progress) on every redraw and every minute cost battery for nothing.
local READING_TTL = 120
local READING_SCAN = 80

-- Changes whenever a book is opened (it moves to the top of the history).
local function historySig()
    local h = history()
    local e = h[1]
    return #h .. ":" .. tostring(e and e.file) .. ":" .. tostring(e and e.time)
end
D.historySig = historySig

local STATUS = { complete = "finished", abandoned = "on_hold" }

-- The book open in the reader, as the reader has it now: Bookshelf 6 keeps
-- a book open behind the shelf for a while after you go home, and its
-- sidecar (where the progress and status are read from otherwise) is only
-- written when it really closes. { fp, pct, status } or nil.
local function liveBook()
    local RUI = package.loaded["apps/reader/readerui"]
    local ui = type(RUI) == "table" and RUI.instance or nil
    if not (type(ui) == "table" and type(ui.document) == "table" and not ui.tearing_down) then return nil end
    local fp = ui.document.file
    if type(fp) ~= "string" then return nil end
    local out = { fp = fp }
    pcall(function()
        local ds = ui.doc_settings
        local summary = ds and ds.readSetting and ds:readSetting("summary")
        local st = type(summary) == "table" and summary.status or nil
        out.status = STATUS[st] or st
    end)
    pcall(function()
        local pct
        if ui.rolling and ui.rolling.getLastPercent then pct = ui.rolling:getLastPercent()
        elseif ui.paging and ui.paging.getLastPercent then pct = ui.paging:getLastPercent() end
        if not tonumber(pct) then
            local cur = ui.getCurrentPage and ui:getCurrentPage()
            local total = ui.document.getPageCount and ui.document:getPageCount()
            if tonumber(cur) and tonumber(total) and total > 0 then pct = cur / total end
        end
        out.pct = tonumber(pct) and A.clamp(tonumber(pct), 0, 1) or nil
    end)
    return out
end
D.liveBook = liveBook

-- The book being read now: the one open in the reader, else the last one
-- opened (KOReader's "lastfile").
local function currentFile(live)
    if live then return live.fp end
    local gs = rawget(_G, "G_reader_settings")
    local ok, lf = pcall(function() return gs and gs:readSetting("lastfile") end)
    return ok and type(lf) == "string" and lf or nil
end

function D.reading(limit)
    limit = limit or 5
    local want = max(limit, 10) -- one scan serves every card (and the day counts)
    local now = os.time()
    local c = D._reading
    local live = liveBook()
    local cur_fp = currentFile(live)
    local sig = historySig() .. "|" .. tostring(cur_fp) .. "|" .. tostring(live and live.status)
        .. "|" .. tostring(live and live.pct and live.pct >= 0.995)
    if c and now - c.at < READING_TTL and c.epoch == A.epoch and c.limit >= limit and c.sig == sig then
        -- the open book's progress as it is now (it moves on as you read)
        if live and live.pct then
            for _, item in ipairs(c.list) do
                if item.fp == live.fp then item.pct = live.pct end
            end
        end
        if #c.list <= limit then return c.list end
        local cut = {}
        for i = 1, limit do cut[i] = c.list[i] end
        return cut
    end
    local list, seen = {}, {}
    local hist = history()
    for i = 1, min(#hist, READING_SCAN) do
        local fp = hist[i] and hist[i].file
        if fp and not seen[fp] and D.fileExists(fp) then
            seen[fp] = true
            local pct, status, pages = D.progress(fp)
            if live and fp == live.fp then
                pct = live.pct or pct
                status = live.status or status
            end
            pct = tonumber(pct)
            local done = status == "finished" or status == "on_hold"
                or ((status == nil or fp == cur_fp) and pct and pct >= 0.995 and status ~= "reading")
            local in_progress = status == "reading"
                or (status == nil and pct and pct > 0 and pct < 0.995)
                or (fp == cur_fp and not done)
            if in_progress then
                local info = D.info(fp)
                local item = {
                    fp = fp, title = info.title, author = info.author,
                    pct = pct or 0, pages = tonumber(pages),
                }
                local okl, left = pcall(A.host.timeLeft, fp, item.pct)
                item.left_min = okl and tonumber(left) or nil
                list[#list + 1] = item
                if #list >= want then break end
            end
        end
    end
    D._reading = { at = now, list = list, epoch = A.epoch, limit = want, sig = sig }
    if #list <= limit then return list end
    local cut = {}
    for i = 1, limit do cut[i] = list[i] end
    return cut
end

-- ─── finished this year ──────────────────────────────────────────────────────
-- With Simple UI: its finished-books ledger, so this year's count is the one
-- its Reading goals module shows (books it lists by hand, or whose file is
-- gone, count towards the totals; books it leaves out of goals do not).
-- Without it: a book counts in the year it was MARKED finished (the sidecar's
-- date_finished, else summary.modified); the date it was last opened stands
-- in when there is none.

-- The first month the Monthly page can go back to: twelve before this one.
local BACK_MONTHS = 12
D.BACK_MONTHS = BACK_MONTHS

local function ymKey(y, m) return string.format("%04d-%02d", y, m) end
D.ymKey = ymKey

local function computeYear()
    local t = os.date("*t")
    local year_start = os.time{ year = t.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
    local back_start = os.time{ year = t.year, month = t.month - BACK_MONTHS, day = 1, hour = 0, min = 0, sec = 0 }
    local since = math.min(year_start, back_start)
    local first_key = os.date("%Y-%m", back_start)
    local months = {}
    for m = 1, 12 do months[m] = {} end
    -- every month back to back_start, this year's and last year's: "YYYY-MM" -> books
    local recent = {}
    local list = {}
    local extra = 0      -- counted this year, but no file or no month to place it in
    local excluded = 0   -- listed this year, but left out of the count

    -- the last time each book was opened, from the history
    local opened_at = {}
    for _, entry in ipairs(history()) do
        if entry.file and not opened_at[entry.file] then opened_at[entry.file] = entry.time or 0 end
    end

    -- KOReader stamps a new finish date when a finished book is marked
    -- finished again (say, a page turn past the end after reopening it). The
    -- date is pulled back to the last day of real reading on or before it.
    local fixer = D.finishFixer and D.finishFixer() or nil
    local function add(fp, y, m, d, skip_count)
        if y and m and fixer then
            local fy, fm, fd = fixer.fix(fp, y, m, d or 1)
            if fy then y, m, d = fy, fm, fd end
        end
        if not (y and m and m >= 1 and m <= 12) then
            if y == t.year and not skip_count then extra = extra + 1 end
            return
        end
        -- outside both this year and the months the Monthly page goes back to
        if y ~= t.year and ymKey(y, m) < first_key then return end
        local info = D.info(fp)
        local _, _, pages = D.progress(fp)
        local item = { fp = fp, year = y, month = m, day = d or 1, title = info.title,
            author = info.author, genres = info.genres, pages = tonumber(pages) or 0,
            excluded = skip_count or nil }
        local key = ymKey(y, m)
        if key >= first_key then
            recent[key] = recent[key] or {}
            recent[key][#recent[key] + 1] = item
        end
        if y == t.year then
            months[m][#months[m] + 1] = item
            list[#list + 1] = item
            if skip_count then excluded = excluded + 1 end
        end
    end

    local ok_l, ledger = pcall(A.host.finishedBooks)
    if ok_l and type(ledger) == "table" then
        local first_year = tonumber(first_key:sub(1, 4))
        for _, b in ipairs(ledger.books or {}) do
            local y, m, d = b.y, b.m, b.d
            if not (y and y >= first_year) then y = nil end
            if y and not m then
                -- a year but no date: place it in the month it was last opened
                local at = opened_at[b.fp]
                if at and at > 0 then
                    local et = os.date("*t", at)
                    if et.year == y then m, d = et.month, et.day end
                end
            end
            if y then add(b.fp, y, m, d, b.excluded) end
        end
        extra = extra + (tonumber((ledger.extra or {})[t.year]) or 0)
    else
        local seen = {}
        for _, entry in ipairs(history()) do
            local fp = entry.file
            if fp and not seen[fp] and (entry.time or 0) >= since then
                seen[fp] = true
                local _, status = D.progress(fp)
                if status == "finished" then
                    local y, m, d = ymOf(D.finishedOn(fp))
                    if not y then
                        local et = os.date("*t", entry.time or 0)
                        y, m, d = et.year, et.month, et.day
                    end
                    add(fp, y, m, d)
                end
            end
        end
    end
    if fixer then fixer.close() end
    for _, l in pairs(recent) do table.sort(l, function(a, b) return a.day > b.day end) end
    local function byDay(a, b)
        if a.month ~= b.month then return a.month > b.month end
        return a.day > b.day
    end
    table.sort(list, byDay) -- newest first
    for m = 1, 12 do table.sort(months[m], function(a, b) return a.day > b.day end) end

    local tally, order = {}, {}
    for _, it in ipairs(list) do
        local counted = {}
        for _, g in ipairs(it.genres or {}) do
            g = type(g) == "string" and g:match("^%s*(.-)%s*$") or nil
            if g and g ~= "" and not counted[g] then
                counted[g] = true
                if not tally[g] then tally[g] = 0; order[#order + 1] = g end
                tally[g] = tally[g] + 1
            end
        end
    end
    local genres = {}
    for _, g in ipairs(order) do genres[#genres + 1] = { name = g, n = tally[g] } end
    table.sort(genres, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)

    return { year = t.year, month = t.month, months = months, list = list,
             total = #list - excluded + extra, genres = genres, recent = recent }
end

D.year = deferred("year", {
    -- worked out again when a book is opened or the day changes, and at
    -- most every five minutes otherwise (was: every minute)
    ttl = 300,
    key = function() return historySig() .. "|" .. os.date("%Y-%m-%d") end,
    sig = function(v)
        local parts = { v.year, v.total }
        for m = 1, 12 do parts[#parts + 1] = #v.months[m] end
        parts[#parts + 1] = v.list[1] and v.list[1].fp or ""
        local keys = {}
        for k, l in pairs(v.recent or {}) do keys[#keys + 1] = k .. "=" .. #l end
        table.sort(keys)
        parts[#parts + 1] = table.concat(keys, ";")
        return table.concat(parts, ",")
    end,
}, computeYear)

-- Yearly target (books) and daily target (minutes): Simple UI's Reading
-- goals, read and written through the host, so changing a goal in either
-- place changes both. `other` (books read outside KOReader) is 0 with Simple
-- UI: books it lists by hand are already in the year's count.

function D.yearGoal()
    local ok, target, other = pcall(A.host.yearGoal)
    if not ok then target, other = 24, 0 end
    return max(1, floor(tonumber(target) or 24)), max(0, floor(tonumber(other) or 0))
end

function D.setYearGoal(target)
    if tonumber(target) and tonumber(target) > 0 then
        pcall(A.host.setYearGoal, floor(tonumber(target)))
        A.epoch = A.epoch + 1
    end
end

function D.setOtherBooks(n)
    if tonumber(n) and tonumber(n) >= 0 then
        pcall(A.host.setOtherBooks, floor(tonumber(n)))
        A.epoch = A.epoch + 1
    end
end

function D.dailyMinutesGoal()
    local ok, v = pcall(A.host.dailyMinutesGoal)
    if ok and tonumber(v) and tonumber(v) > 0 then return max(1, floor(tonumber(v))) end
    return 30
end

function D.setDailyMinutesGoal(v)
    if tonumber(v) and tonumber(v) > 0 then
        pcall(A.host.setDailyMinutesGoal, floor(tonumber(v)))
        A.epoch = A.epoch + 1
    end
end

-- ─── reading statistics ──────────────────────────────────────────────────────

-- Thirteen months, so the Monthly page can go back a year.
local WINDOW_DAYS = 400

local function statsPath()
    local DataStorage = require("datastorage")
    return DataStorage:getSettingsDir() .. "/statistics.sqlite3"
end

-- First day of the week, 1 = Sunday .. 7 = Saturday. Follows the statistics
-- plugin's calendar setting unless overridden in Look and colours.
function D.weekStart()
    local v = tonumber(A.get("week_start"))
    if v and v >= 1 and v <= 7 then return v end
    local st = G_reader_settings and G_reader_settings:readSetting("statistics")
    v = type(st) == "table" and tonumber(st.calendar_start_day_of_week) or nil
    if v and v >= 1 and v <= 7 then return v end
    return 2
end

local function ymdAt(t) return os.date("%Y-%m-%d", t) end

-- The statistics plugin only writes while a book is open, so the file's
-- modification time says whether there is anything new to read. Sitting on
-- the home screen, the per-minute clock redraw then costs one stat() here
-- rather than two scans of the database.
local function statsKey()
    local l = lfs()
    if not l then return os.date("%Y-%m-%d") end
    local path = statsPath()
    -- With write-ahead logging on (KOReader's default where the storage
    -- allows it) new rows land in the -wal file first.
    return table.concat({
        tostring(l.attributes(path, "modification") or 0),
        tostring(l.attributes(path .. "-wal", "modification") or 0),
        tostring(l.attributes(path .. "-wal", "size") or 0),
        os.date("%Y-%m-%d"),
    }, "@")
end

-- Raw read: per-day pages/seconds for the recent window, and the day number
-- of every day with any reading (for streaks).
-- Where the figures' read starts: January last year (the year-on-year
-- comparison), or WINDOW_DAYS ago if that's earlier, at midnight. The pages
-- before it never change, so Pages turned counts them once (D.pagesTurned).
local function windowStart()
    local t = os.date("*t")
    local jan1 = os.time{ year = t.year - 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
    local since = math.min(os.time() - WINDOW_DAYS * 86400, jan1)
    local d = os.date("*t", since)
    return os.time{ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 }
end

local function loadStats()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local days, all_days, hours = {}, {}, {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        -- The recent window, and never less than this year so far (the
        -- year chart adds up every month since January), back to January
        -- last year for the year-on-year comparison.
        local since = windowStart()
        -- Same shape as the statistics plugin's own per-day query (page_stat
        -- rescales pages to the book's current pagination); falls back to
        -- the raw table on a database old enough not to have the view.
        local function window(tbl)
            local stmt = conn:prepare(
                "SELECT dates, count(*), sum(sum_duration) FROM ("
                .. " SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS dates,"
                .. " sum(duration) AS sum_duration FROM " .. tbl
                .. " WHERE start_time >= ? GROUP BY id_book, page, dates)"
                .. " GROUP BY dates ORDER BY dates")
            local row = stmt:reset():bind(since):step()
            while row do
                days[row[1]] = { pages = tonumber(row[2]) or 0, secs = tonumber(row[3]) or 0 }
                row = stmt:step()
            end
            stmt:close()
        end
        if not pcall(window, "page_stat") then
            days = {}
            window("page_stat_data")
        end
        local stmt = conn:prepare(
            "SELECT DISTINCT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')"
            .. " FROM page_stat_data ORDER BY 1")
        local row = stmt:step()
        while row do
            all_days[#all_days + 1] = row[1]
            row = stmt:step()
        end
        stmt:close()
        -- The time of day the reading happened, hour by hour, for every day
        -- in the window (the When you read card adds up whichever span it shows).
        stmt = conn:prepare(
            "SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),"
            .. " CAST(strftime('%H', start_time, 'unixepoch', 'localtime') AS INTEGER), sum(duration)"
            .. " FROM page_stat_data WHERE start_time >= ? GROUP BY 1, 2")
        row = stmt:reset():bind(since):step()
        while row do
            local d, hr, secs = row[1], tonumber(row[2]), tonumber(row[3]) or 0
            if d and hr and hr >= 0 and hr <= 23 then
                local rec = hours[d]
                if not rec then rec = {}; hours[d] = rec end
                rec[hr] = (rec[hr] or 0) + secs
            end
            row = stmt:step()
        end
        stmt:close()
    end)
    conn:close()
    if not ok then error(err) end
    local nums = {}
    for _, d in ipairs(all_days) do
        local y, m, dd = A.parseYmd(d)
        if y then nums[#nums + 1] = A.dayNumber(y, m, dd) end
    end
    return { days = days, nums = nums, hours = hours }
end

local rawStats = deferred("stats", {
    ttl = 900, key = statsKey,
    sig = function(v)
        local last = v.nums[#v.nums] or 0
        local today = v.days[os.date("%Y-%m-%d")]
        return table.concat({ #v.nums, last, today and today.pages or 0, today and today.secs or 0 }, ",")
    end,
}, loadStats)

-- Today, this week and the streaks, worked out from the raw read.
local function deriveStats(raw)
    local days, nums = raw.days, raw.nums
    local t = os.date("*t")
    local today_n = A.dayNumber(t.year, t.month, t.day)
    local best, run = 0, 0
    for i, n in ipairs(nums) do
        if i > 1 and n == nums[i - 1] + 1 then run = run + 1 else run = 1 end
        if run > best then best = run end
    end
    local streak = 0
    if #nums > 0 and (nums[#nums] == today_n or nums[#nums] == today_n - 1) then
        streak = 1
        for i = #nums - 1, 1, -1 do
            if nums[i] == nums[i + 1] - 1 then streak = streak + 1 else break end
        end
    end
    local ws = D.weekStart()
    local back = (t.wday - ws) % 7
    local week = {}
    local wp, wsx = 0, 0
    for i = 0, 6 do
        local dt = os.time{ year = t.year, month = t.month, day = t.day - back + i, hour = 12 }
        local key = ymdAt(dt)
        local rec = days[key] or { pages = 0, secs = 0 }
        week[i + 1] = { key = key, pages = rec.pages, secs = rec.secs,
            wday = tonumber(os.date("%w", dt)) + 1, today = (i == back), future = (i > back) }
        wp, wsx = wp + rec.pages, wsx + rec.secs
    end
    local today = days[ymdAt(os.time())] or { pages = 0, secs = 0 }
    -- this year, month by month
    local month_pages, month_secs = {}, {}
    for m = 1, 12 do month_pages[m], month_secs[m] = 0, 0 end
    local prefix = string.format("%04d-", t.year)
    for key, rec in pairs(days) do
        if key:sub(1, 5) == prefix then
            local m = tonumber(key:sub(6, 7))
            if m and month_pages[m] then
                month_pages[m] = month_pages[m] + (rec.pages or 0)
                month_secs[m] = month_secs[m] + (rec.secs or 0)
            end
        end
    end
    -- the hour of day the reading happened: this month, the last 30 days, this year
    local hours = { month = {}, days30 = {}, year = {} }
    for _, k in pairs(hours) do for hr = 0, 23 do k[hr] = 0 end end
    local month_prefix = string.format("%04d-%02d-", t.year, t.month)
    local cut30 = ymdAt(os.time{ year = t.year, month = t.month, day = t.day - 29, hour = 12 })
    for key, rec in pairs(raw.hours or {}) do
        local in_year = key:sub(1, 5) == prefix
        local in_month = key:sub(1, 8) == month_prefix
        local in_30 = key >= cut30
        for hr, secs in pairs(rec) do
            if in_year then hours.year[hr] = hours.year[hr] + secs end
            if in_month then hours.month[hr] = hours.month[hr] + secs end
            if in_30 then hours.days30[hr] = hours.days30[hr] + secs end
        end
    end
    return {
        days = days, today = today, streak = streak, best = best,
        week = week, week_pages = wp, week_secs = wsx,
        month_pages = month_pages, month_secs = month_secs,
        hours = hours, hours_by_day = raw.hours or {},
    }
end

-- ─── reading not saved yet ───────────────────────────────────────────────────
-- KOReader's statistics plugin keeps the pages of a sitting in memory and
-- saves them when the book closes. Bookshelf 6 leaves the book open behind
-- the shelf after you go home (it closes it once you've been idle a while),
-- so the database has nothing of that sitting yet. These put in what the
-- open reader holds and hasn't saved: a walk over that sitting's pages.

local function dayStart()
    local t = os.date("*t")
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
end

--- Pages and seconds read since `since` (today, by default) that an open
--- reader holds and hasn't saved: 0, 0 when no book is open.
function D.unsaved(since)
    since = since or dayStart()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local ui = ok and type(ReaderUI) == "table" and ReaderUI.instance or nil
    local ps = ui and ui.statistics and ui.statistics.page_stat
    if type(ps) ~= "table" then return 0, 0 end
    local pages, secs = 0, 0
    for _, list in pairs(ps) do
        local counted = false
        if type(list) == "table" then
            for _, tup in ipairs(list) do
                local ts, dur = tonumber(tup[1]), tonumber(tup[2])
                if ts and dur and dur > 0 and ts >= since then
                    secs = secs + dur
                    if not counted then pages, counted = pages + 1, true end
                end
            end
        end
    end
    return pages, secs
end

-- The figures with today's unsaved reading put in. When the book has just
-- closed (its pages now in the database, which hasn't been read again yet),
-- the last ones are kept in until it has, so the numbers never dip back.
local _live = { raw = nil, p = 0, s = 0 }
local function withLive(st, raw)
    local p, s = D.unsaved()
    if p == 0 and s == 0 and _live.raw == raw then p, s = _live.p, _live.s end
    _live.raw, _live.p, _live.s = raw, p, s
    if p == 0 and s == 0 then return st end
    if _live.base == st and _live.vp == p and _live.vs == s then return _live.value end
    local v = {}
    for k, x in pairs(st) do v[k] = x end
    local had = st.today or { pages = 0, secs = 0 }
    v.today = { pages = (had.pages or 0) + p, secs = (had.secs or 0) + s }
    if (had.pages or 0) == 0 and p > 0 then
        v.streak = (st.streak or 0) + 1
        v.best = max(st.best or 0, v.streak)
    end
    local key = os.date("%Y-%m-%d")
    local days = {}
    for k, x in pairs(st.days or {}) do days[k] = x end
    days[key] = v.today
    v.days = days
    local week = {}
    for i, d in ipairs(st.week or {}) do
        if d.today then
            local d2 = {}
            for k, x in pairs(d) do d2[k] = x end
            d2.pages, d2.secs = (d.pages or 0) + p, (d.secs or 0) + s
            week[i] = d2
        else
            week[i] = d
        end
    end
    v.week = week
    v.week_pages, v.week_secs = (st.week_pages or 0) + p, (st.week_secs or 0) + s
    local m = os.date("*t").month
    if st.month_pages then
        local mp, ms = {}, {}
        for i = 1, 12 do mp[i], ms[i] = st.month_pages[i], st.month_secs and st.month_secs[i] or 0 end
        mp[m], ms[m] = (mp[m] or 0) + p, (ms[m] or 0) + s
        v.month_pages, v.month_secs = mp, ms
    end
    _live.base, _live.vp, _live.vs, _live.value = st, p, s, v
    return v
end

local _derived
--- Reading figures: a table, false (no statistics database) or nil (loading).
--- Today's figures take in what an open book hasn't saved yet.
function D.stats(refresh, sync)
    local raw = rawStats(refresh, sync)
    if not raw then return raw end
    local stamp = os.date("%Y-%m-%d") .. ":" .. tostring(D.weekStart())
    if not (_derived and _derived.raw == raw and _derived.stamp == stamp) then
        _derived = { raw = raw, stamp = stamp, value = deriveStats(raw) }
    end
    return withLive(_derived.value, raw)
end

-- ─── every page ever turned ──────────────────────────────────────────────────

-- The pages turned before the figures' window (and the first day read), read
-- once: they never change. Read again only when the window moves on.
local function loadPagesBefore()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local out = { pages = 0, secs = 0 }
    local before = windowStart()
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local function count(tbl)
            local p, s2, first = conn:rowexec(string.format(
                "SELECT count(*), sum(s), min(dates) FROM ("
                .. " SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,"
                .. " sum(duration) AS s FROM %s WHERE start_time < %d GROUP BY id_book, page, dates);", tbl, before))
            out.pages, out.secs, out.first = tonumber(p) or 0, tonumber(s2) or 0, first
        end
        if not pcall(count, "page_stat") then count("page_stat_data") end
    end)
    conn:close()
    if not ok then error(err) end
    return out
end
local pagesBefore = deferred("pages_before", {
    ttl = 86400, heavy = true, sticky = true,
    key = function() return statsPath() .. "|" .. os.date("%Y-%m-%d", windowStart()) end,
}, loadPagesBefore)

--- Every page turned (or this year's, period "year"): { pages =, first =
--- "YYYY-MM-DD" (the first day read) }, nil while loading, false without
--- statistics. Today's unsaved reading counts too (see D.stats).
function D.pagesTurned(refresh, period)
    local year = period == "year"
    -- (both asked for before either is waited on, so they load together;
    -- nil = still loading, so not `x and f() or false`, which turns nil into false)
    local b = false
    if not year then b = pagesBefore(refresh) end
    local st = D.stats(refresh)
    if not st then return st end
    local base, first = 0, nil
    if not year then
        if b == nil then return nil end
        if b then base, first = b.pages or 0, b.first end
    end
    local prefix = os.date("%Y-")
    local sum, first_w = 0, nil
    for k, rec in pairs(st.days or {}) do
        local p = rec.pages or 0
        if p > 0 and (not year or k:sub(1, 5) == prefix) then
            sum = sum + p
            if not first_w or k < first_w then first_w = k end
        end
    end
    return { pages = base + sum, first = first or first_w, year = year }
end

--- What the reading figures depend on, cheaply: the statistics file and
--- the day, and what an open book hasn't saved. A card that polls redraws
--- when this changes.
function D.statsSig()
    local p, s = D.unsaved()
    return statsKey() .. "|" .. p .. "," .. s
end

--- The reading figures as last worked out, without reading the database
--- again (nil if they never were). The reader panel uses these, so opening
--- the menu never starts a full read.
function D.statsCached()
    local s = _slots.stats
    local raw = s and s.value
    if type(raw) ~= "table" then return nil end
    local stamp = os.date("%Y-%m-%d") .. ":" .. tostring(D.weekStart())
    if not (_derived and _derived.raw == raw and _derived.stamp == stamp) then
        _derived = { raw = raw, stamp = stamp, value = deriveStats(raw) }
    end
    return _derived.value
end

-- ─── any one month ───────────────────────────────────────────────────────────

--- The books finished in month m of year y (newest first), from the twelve
--- months the Monthly page can show. nil while loading.
function D.finishedIn(refresh, y, m)
    local yr = D.year(refresh)
    if not yr then return nil end
    return (yr.recent or {})[ymKey(y, m)] or {}
end

--- A month's reading from the statistics: days in it, the days so far (all
--- of them for a past month), pages and seconds per day, the totals, and the
--- seconds read in each hour of the day.
function D.monthStats(st, y, m)
    local now = os.date("*t")
    local n_days = tonumber(os.date("%d", os.time{ year = y, month = m + 1, day = 0, hour = 12 })) or 30
    local current = (y == now.year and m == now.month)
    local out = { year = y, month = m, n_days = n_days, current = current,
        elapsed = current and min(now.day, n_days) or n_days, days = {}, pages = 0, secs = 0, hours = {} }
    for hr = 0, 23 do out.hours[hr] = 0 end
    if type(st) ~= "table" then return out end
    local prefix = ymKey(y, m) .. "-"
    for d = 1, n_days do
        local rec = st.days and st.days[prefix .. string.format("%02d", d)]
        if rec then
            out.days[d] = rec
            out.pages, out.secs = out.pages + (rec.pages or 0), out.secs + (rec.secs or 0)
        end
    end
    for key, rec in pairs(st.hours_by_day or {}) do
        if key:sub(1, 8) == prefix then
            for hr, secs in pairs(rec) do out.hours[hr] = out.hours[hr] + secs end
        end
    end
    return out
end

-- ─── how long each finished book took ───────────────────────────────────────
-- For every book finished this year: the reading time KOReader's statistics
-- recorded for it, the days it was read on, and how many calendar days it
-- took from the first session to the day it was marked finished. One pass
-- over the database for the whole list. Books are matched the way the
-- statistics plugin matches them: by the partial MD5 kept in the sidecar
-- (worked out from the file when the sidecar lacks it); when one MD5 has two
-- rows, the one opened last is the one being read into.

local _md5_cache = {}
local function bookMd5(fp)
    if _md5_cache[fp] then return _md5_cache[fp] end
    local md5
    pcall(function()
        md5 = require("docsettings"):open(fp):readSetting("partial_md5_checksum")
    end)
    if not md5 then
        pcall(function() md5 = require("util").partialMD5(fp) end)
    end
    _md5_cache[fp] = md5
    return md5
end
D.bookMd5 = bookMd5

-- ─── real reading days ───────────────────────────────────────────────────────
-- The finish-date correction, after the one in BrownTigerz's (TK's) Reading
-- Log for SimpleUI (AGPL-3.0): a day only counts as a reading day for a book
-- when something was actually read, at least READ_MIN_SECS seconds or
-- READ_MIN_PAGES different pages. Opening a finished book for a few seconds
-- is not reading it.
local READ_MIN_SECS, READ_MIN_PAGES = 60, 2
D.READ_MIN_SECS, D.READ_MIN_PAGES = READ_MIN_SECS, READ_MIN_PAGES

local SQL_BOOK_DAYS =
    "SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS d,"
    .. " sum(duration), count(DISTINCT page), min(start_time)"
    .. " FROM page_stat_data WHERE id_book = ? GROUP BY d ORDER BY d"

-- Opens the statistics read-only and returns
--   { days(fp)     real reading days, oldest first: { ymd, secs, pages, first }
--                  (nil when the book is not in the statistics),
--     all_secs(fp) every second recorded, token opens included,
--     fix(fp, y, m, d) the corrected finish date, or nil to keep it,
--     close() }
-- or nil without a statistics database. Per-book days are kept until the
-- statistics change.
function D.finishFixer()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return nil end
    local conn, q_id, q_days, broken
    local function open()
        if conn or broken then return conn ~= nil end
        local ok = pcall(function()
            local SQ3 = require("lua-ljsqlite3/init")
            conn = SQ3.open(path, "ro")
            conn:exec("PRAGMA busy_timeout=200;")
            q_id = conn:prepare("SELECT id FROM book WHERE md5 = ? ORDER BY last_open DESC LIMIT 1")
            q_days = conn:prepare(SQL_BOOK_DAYS)
        end)
        if not ok then
            broken = true
            if conn then pcall(conn.close, conn) end
            conn = nil
        end
        return conn ~= nil
    end
    local key = statsKey()
    if D._days_key ~= key then D._days_key, D._days_cache = key, {} end
    local cache = D._days_cache
    local F = {}
    local function load(fp)
        local c = cache[fp]
        if c ~= nil then return c end
        c = false
        if not open() then return c end
        pcall(function()
            local md5 = bookMd5(fp)
            local row = md5 and q_id:reset():bind(md5):step()
            local id = row and tonumber(row[1])
            if not id then return end
            local real, total = {}, 0
            local r = q_days:reset():bind(id):step()
            while r do
                local secs, pages = tonumber(r[2]) or 0, tonumber(r[3]) or 0
                total = total + secs
                if secs >= READ_MIN_SECS or pages >= READ_MIN_PAGES then
                    real[#real + 1] = { ymd = r[1], secs = secs, pages = pages, first = tonumber(r[4]) }
                end
                r = q_days:step()
            end
            c = { real = real, total = total }
        end)
        cache[fp] = c
        return c
    end
    function F.days(fp) local c = load(fp); return c and c.real or nil end
    function F.all_secs(fp) local c = load(fp); return c and c.total or 0 end
    function F.fix(fp, y, m, d)
        local c = load(fp)
        if not c or #c.real == 0 then return nil end
        local stamped = string.format("%04d-%02d-%02d", y, m, d or 1)
        local last
        for _, day in ipairs(c.real) do
            if day.ymd <= stamped then last = day.ymd else break end
        end
        -- nothing read on or before that date: keep the date as saved
        if not last or last == stamped then return nil end
        local ly, lm, ld = last:match("^(%d+)%-(%d+)%-(%d+)$")
        return tonumber(ly), tonumber(lm), tonumber(ld)
    end
    function F.close()
        if not conn then return end
        pcall(function() q_id:close(); q_days:close() end)
        pcall(conn.close, conn)
        conn = nil
    end
    return F
end

local function computeLengths()
    local yr = D.year(nil, true)
    -- this year's books and the twelve months before
    local list, seen = {}, {}
    for _, it in ipairs(yr and yr.list or {}) do seen[it.fp] = true; list[#list + 1] = it end
    for _, l in pairs(yr and yr.recent or {}) do
        for _, it in ipairs(l) do
            if not seen[it.fp] then seen[it.fp] = true; list[#list + 1] = it end
        end
    end
    local F = D.finishFixer()
    if not F then return false end
    local out = {}
    local ok, err = pcall(function()
        for _, it in ipairs(list) do
            local days = F.days(it.fp)
            if days then
                -- the reading up to the (corrected) finish day: token opens
                -- and any rereading afterwards don't stretch the book
                local end_ymd = string.format("%04d-%02d-%02d", it.year or yr.year, it.month, it.day or 1)
                local secs, read_days, first = 0, 0, nil
                for _, day in ipairs(days) do
                    if day.ymd <= end_ymd then
                        secs = secs + day.secs
                        read_days = read_days + 1
                        first = first or day.first
                    end
                end
                if read_days == 0 then
                    -- all of it after the saved date: count everything
                    secs = F.all_secs(it.fp)
                    read_days = #days
                    first = days[1] and days[1].first
                end
                local span
                if first then
                    local ft = os.date("*t", first)
                    local start_n = A.dayNumber(ft.year, ft.month, ft.day)
                    local end_n = A.dayNumber(it.year or yr.year, it.month, it.day or 1)
                    span = max(1, end_n - start_n + 1)
                end
                out[it.fp] = { secs = secs, read_days = read_days, span = span or read_days }
            end
        end
    end)
    F.close()
    if not ok then error(err) end
    return out
end

local rawLengths = deferred("lengths", {
    ttl = 900,
    key = function() return statsKey() .. "|" .. A.epoch end,
    sig = function(v)
        local n, secs = 0, 0
        for _, rec in pairs(v) do n = n + 1; secs = secs + (rec.secs or 0) end
        return n .. ":" .. secs
    end,
}, computeLengths)

--- The books finished this year (or, with month, in that month: of `year`,
--- this year when nil), each with secs / span / read_days, longest first by
--- `by` ("time" or "days"). nil while loading, false without a statistics
--- database.
function D.longest(refresh, month, by, year)
    local yr = D.year(refresh)
    if not yr then return nil end
    local lengths = rawLengths(refresh)
    if lengths == nil then return nil end
    if lengths == false then return false end
    local rows = {}
    local src = yr.list or {}
    if month then src = (yr.recent or {})[ymKey(year or yr.year, month)] or {} end
    for _, it in ipairs(src) do
        local rec = lengths[it.fp]
        if rec and (rec.secs > 0 or (rec.span or 0) > 0) then
            rows[#rows + 1] = { fp = it.fp, title = it.title, author = it.author, month = it.month, day = it.day,
                secs = rec.secs, span = rec.span or 0, read_days = rec.read_days }
        end
    end
    local function key(r) if by == "days" then return r.span, r.secs end return r.secs, r.span end
    table.sort(rows, function(a, b)
        local a1, a2 = key(a)
        local b1, b2 = key(b)
        if a1 ~= b1 then return a1 > b1 end
        if a2 ~= b2 then return a2 > b2 end
        return (a.title or "") < (b.title or "")
    end)
    return rows
end

-- ─── when each book in progress was started ─────────────────────────────────
-- The first session the statistics recorded for each book on the Continue
-- reading list, and the reading time recorded for it so far, so the card can
-- say "4 days of reading, 2 h 14 m".

local STARTED_LIST = 10

local function readingKey()
    local fps = {}
    for _, it in ipairs(D.reading(STARTED_LIST)) do fps[#fps + 1] = it.fp end
    return table.concat(fps, "\n")
end

local function computeStarted()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local out = {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local q_id = conn:prepare("SELECT id FROM book WHERE md5 = ? ORDER BY last_open DESC LIMIT 1")
        local q_first = conn:prepare("SELECT min(start_time), sum(duration) FROM page_stat_data WHERE id_book = ?")
        for _, it in ipairs(D.reading(STARTED_LIST)) do
            local md5 = bookMd5(it.fp)
            local row = md5 and q_id:reset():bind(md5):step()
            local id = row and tonumber(row[1])
            local r = id and q_first:reset():bind(id):step()
            local first = r and tonumber(r[1])
            if first then out[it.fp] = { first = first, secs = tonumber(r[2]) or 0 } end
        end
        q_id:close(); q_first:close()
    end)
    conn:close()
    if not ok then error(err) end
    return out
end

local rawStarted = deferred("started", {
    ttl = 900,
    key = function() return statsKey() .. "|" .. readingKey() end,
    sig = function(v)
        local parts = {}
        for fp, t in pairs(v) do parts[#parts + 1] = fp .. "=" .. t.first .. ":" .. t.secs end
        table.sort(parts)
        return table.concat(parts, ",")
    end,
}, computeStarted)

--- How many days this book has been on the go (1 = started today), when it
--- was started, and the seconds spent reading it so far. nil when the
--- statistics have no session for it (or are still loading).
function D.dayOfBook(refresh, fp)
    local v = rawStarted(refresh)
    local rec = type(v) == "table" and v[fp]
    if not rec then return nil end
    local ft, t = os.date("*t", rec.first), os.date("*t")
    local n = A.dayNumber(t.year, t.month, t.day) - A.dayNumber(ft.year, ft.month, ft.day) + 1
    return max(1, n), rec.first, rec.secs
end

-- ─── reading sessions ───────────────────────────────────────────────────────
-- A session is a run of page turns with no break longer than SESSION_GAP.
-- One row per session (start time, seconds read) for the trends window. The
-- grouping runs inside SQLite where window functions are available, and in
-- Lua over the raw rows where they are not.

local SESSION_GAP = 600
local TREND_DAYS, TREND_RECENT = 365, 90

local function computeSessions()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local since = os.time() - (TREND_DAYS + 2) * 86400
    local out = {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local grouped = pcall(function()
            local stmt = conn:prepare(
                "WITH r AS (SELECT start_time AS s, duration AS d,"
                .. " LAG(start_time + duration) OVER (ORDER BY start_time) AS pe"
                .. " FROM page_stat_data WHERE start_time >= ?),"
                .. " g AS (SELECT s, d, CASE WHEN pe IS NULL OR s - pe > " .. SESSION_GAP .. " THEN 1 ELSE 0 END AS n FROM r),"
                .. " h AS (SELECT s, d, SUM(n) OVER (ORDER BY s ROWS UNBOUNDED PRECEDING) AS id FROM g)"
                .. " SELECT min(s), sum(d) FROM h GROUP BY id ORDER BY 1")
            local row = stmt:reset():bind(since):step()
            while row do
                out[#out + 1] = { start = tonumber(row[1]) or 0, secs = tonumber(row[2]) or 0 }
                row = stmt:step()
            end
            stmt:close()
        end)
        if not grouped then
            out = {}
            local stmt = conn:prepare("SELECT start_time, duration FROM page_stat_data WHERE start_time >= ? ORDER BY start_time")
            local row = stmt:reset():bind(since):step()
            local cur, last_end
            while row do
                local st, d = tonumber(row[1]) or 0, tonumber(row[2]) or 0
                if not cur or st - last_end > SESSION_GAP then
                    cur = { start = st, secs = 0 }
                    out[#out + 1] = cur
                end
                cur.secs = cur.secs + d
                last_end = max(last_end or 0, st + d)
                row = stmt:step()
            end
            stmt:close()
        end
    end)
    conn:close()
    if not ok then error(err) end
    return out
end

local rawSessions = deferred("sessions", {
    ttl = 900, key = statsKey,
    sig = function(v)
        local last = v[#v]
        return #v .. ":" .. (last and (last.start .. "+" .. last.secs) or "")
    end,
}, computeSessions)

-- ─── reading trends ─────────────────────────────────────────────────────────
-- Like the trends in Apple's Fitness app: each figure over the last 90 days
-- against the last 365, both ending yesterday so a half-read today does not
-- drag them down. Up (or within 3 %) = keep it going; further down = worth a
-- look; too little history = needs more data.

D.TREND_RECENT, D.TREND_DAYS = TREND_RECENT, TREND_DAYS

local TREND_DEFS = {
    { id = "time",    name = T("Time read"),      unit = T("min/day"),
      hint = T("A short session before bed would bring this back up.") },
    { id = "pages",   name = T("Pages"),          unit = T("pages/day"),
      hint = T("A few extra pages a day adds up fast.") },
    { id = "days",    name = T("Reading days"),   unit = T("days/week"),
      hint = T("Try ten minutes on the days you usually skip.") },
    { id = "session", name = T("Session length"), unit = T("min/session"),
      hint = T("Your sittings are shorter lately. One long read a week helps.") },
    { id = "speed",   name = T("Reading speed"),  unit = T("pages/hr"),
      hint = T("Slower pages can just mean a denser book.") },
    { id = "books",   name = T("Books finished"), unit = T("books/month"),
      hint = T("A couple of shorter reads would bring this back up.") },
}
D.TREND_DEFS = TREND_DEFS

--- Pure: the trends from the figures. days = { ["YYYY-MM-DD"] = {pages, secs} },
--- first_n = day number of the first day ever read, sessions = { {start, secs} },
--- finished = finish dates as day numbers, now = os.date("*t") for today.
function D.trendsFrom(days, first_n, sessions, finished, now)
    now = now or os.date("*t")
    local today_n = A.dayNumber(now.year, now.month, now.day)
    local span = first_n and (today_n - first_n) or 0
    -- session day numbers, worked out once
    local sess = {}
    for _, ss in ipairs(sessions or {}) do
        if (ss.secs or 0) >= 60 then
            local t = os.date("*t", ss.start)
            sess[#sess + 1] = { n = A.dayNumber(t.year, t.month, t.day), secs = ss.secs }
        end
    end
    -- the n_days ending yesterday, less any before the first day ever read
    local function window(n_days)
        local w = { len = 0, pages = 0, secs = 0, read_days = 0, sessions = 0, session_secs = 0, books = 0 }
        local lo = today_n - n_days
        if first_n and first_n > lo then lo = first_n end
        for k = 1, n_days do
            local n = today_n - k
            if n < lo then break end
            w.len = w.len + 1
            local key = os.date("%Y-%m-%d", os.time{ year = now.year, month = now.month, day = now.day - k, hour = 12 })
            local rec = days[key]
            if rec then
                w.pages, w.secs = w.pages + (rec.pages or 0), w.secs + (rec.secs or 0)
                if (rec.secs or 0) > 0 or (rec.pages or 0) > 0 then w.read_days = w.read_days + 1 end
            end
        end
        for _, ss in ipairs(sess) do
            if ss.n >= lo and ss.n < today_n then
                w.sessions, w.session_secs = w.sessions + 1, w.session_secs + ss.secs
            end
        end
        for _, fn in ipairs(finished or {}) do
            if fn >= lo and fn < today_n then w.books = w.books + 1 end
        end
        return w
    end
    local r, b = window(TREND_RECENT), window(TREND_DAYS)
    local enough = span >= 120 and b.read_days >= 30
    local function val(w, id)
        if w.len <= 0 then return nil end
        if id == "time" then return w.secs / 60 / w.len end
        if id == "pages" then return w.pages / w.len end
        if id == "days" then return w.read_days / (w.len / 7) end
        if id == "session" then return w.sessions > 0 and (w.session_secs / w.sessions / 60) or nil end
        if id == "speed" then return w.secs > 0 and (w.pages / (w.secs / 3600)) or nil end
        if id == "books" then return w.books / (w.len / 30.44) end
    end
    local function ready(id)
        if not enough then return false end
        if id == "session" then return r.sessions >= 5 and b.sessions >= 10 end
        if id == "speed" then return r.secs >= 3 * 3600 and b.secs >= 6 * 3600 end
        if id == "books" then return b.books >= 3 end
        return true
    end
    local out = {}
    for _, def in ipairs(TREND_DEFS) do
        local rv, bv = val(r, def.id), val(b, def.id)
        local item = { id = def.id, name = def.name, unit = def.unit, hint = def.hint, recent = rv, base = bv }
        if not ready(def.id) or not rv or not bv or bv <= 0 then
            item.group = "more"
        else
            item.ratio = rv / bv
            item.group = item.ratio >= 0.97 and "keep" or "look"
        end
        out[#out + 1] = item
    end
    return out, { history = span, enough = enough }
end

--- The trends (see D.trendsFrom), nil while loading, false without a
--- statistics database.
function D.trends(refresh)
    local raw = rawStats(refresh)
    if raw == false then return false end
    local sessions = rawSessions(refresh)
    local yr = D.year(refresh)
    if not raw or sessions == nil or not yr then return nil end
    local finished = {}
    for _, l in pairs(yr.recent or {}) do
        for _, it in ipairs(l) do
            if it.year and it.month then finished[#finished + 1] = A.dayNumber(it.year, it.month, it.day or 1) end
        end
    end
    return D.trendsFrom(raw.days, raw.nums[1], sessions or {}, finished, os.date("*t"))
end

-- ─── this week against last week ────────────────────────────────────────────
-- Like Apple Health's highlights: your average a day so far this week (month,
-- year) against the whole of last week (month, year). A today with no reading
-- yet is left out, so the morning does not drag the average down.

local PERIOD_WORDS = {
    week = { T("this week"), T("last week") }, month = { T("this month"), T("last month") }, year = { T("this year"), T("last year") },
}

--- Pure. days = { ["YYYY-MM-DD"] = {pages, secs} }, period "week"|"month"|"year",
--- metric "time"|"pages", now = os.date("*t"), ws = first weekday (1 = Sunday),
--- first_n = day number of the first day ever read (or nil).
function D.compareFrom(days, period, metric, now, ws, first_n)
    now = now or os.date("*t")
    now = os.date("*t", os.time{ year = now.year, month = now.month, day = now.day, hour = 12 }) -- fills in the weekday
    ws = ws or 2
    if not PERIOD_WORDS[period] then period = "week" end
    if metric ~= "pages" then metric = "time" end
    local today_n = A.dayNumber(now.year, now.month, now.day)
    local function at(k) -- the date k days before today
        return os.date("%Y-%m-%d", os.time{ year = now.year, month = now.month, day = now.day - k, hour = 12 })
    end
    local function value(rec)
        if not rec then return 0 end
        return metric == "pages" and (rec.pages or 0) or (rec.secs or 0) / 60
    end
    -- the current period: k = 0 (today) back to `back`
    local back, last_from, last_len
    if period == "week" then
        back = (now.wday - ws) % 7
        last_from, last_len = back + 1, 7
    elseif period == "month" then
        back = now.day - 1
        local prev_len = tonumber(os.date("%d", os.time{ year = now.year, month = now.month, day = 0, hour = 12 })) or 30
        last_from, last_len = back + 1, prev_len
    else
        back = (tonumber(os.date("%j", os.time{ year = now.year, month = now.month, day = now.day, hour = 12 })) or 1) - 1
        local prev_len = tonumber(os.date("%j", os.time{ year = now.year - 1, month = 12, day = 31, hour = 12 })) or 365
        last_from, last_len = back + 1, prev_len
    end
    -- the days gone by; today joins them once it has lifted the average (a
    -- half-read today never drags it down)
    local sum, n = 0, 0
    for k = back, 1, -1 do
        sum, n = sum + value(days[at(k)]), n + 1
    end
    local today_v = value(days[at(0)])
    if n > 0 and today_v > sum / n then
        sum, n = sum + today_v, n + 1
    end
    local lsum, ln = 0, 0
    for k = last_from, last_from + last_len - 1 do
        if not first_n or today_n - k >= first_n then
            lsum, ln = lsum + value(days[at(k)]), ln + 1
        end
    end
    local last = ln > 0 and lsum / ln or nil
    -- the first day of the period: today counts once it beats last time's average
    if n == 0 and last and today_v > last then sum, n = today_v, 1 end
    local this = n > 0 and sum / n or nil
    local words = PERIOD_WORDS[period]
    local unit = T(metric == "pages" and "pages" or "minutes")
    local sentence, dir
    if not this then
        sentence = ({ week = T("This week has only just started."),
            month = T("This month has only just started."), year = T("This year has only just started.") })[period]
    elseif not last then
        sentence = A.tr("Nothing to compare with %1 yet.", words[2])
    elseif last == 0 and this == 0 then
        sentence = A.tr("Nothing read %1 or %2 yet.", words[1], words[2])
    elseif this > last * 1.03 then
        dir = "up"
        sentence = A.tr("You're averaging more %1 a day %2 than %3.", unit, words[1], words[2])
    elseif this < last * 0.97 then
        dir = "down"
        sentence = A.tr("You're averaging fewer %1 a day %2 than %3.", unit, words[1], words[2])
    else
        dir = "same"
        sentence = A.tr("You're averaging about as many %1 a day %2 as %3.", unit, words[1], words[2])
    end
    -- what to call the two bars
    local label_this, label_last
    if period == "year" then
        label_this, label_last = tostring(now.year), tostring(now.year - 1)
    elseif period == "month" then
        label_this = A.date("%B", os.time{ year = now.year, month = now.month, day = 1, hour = 12 })
        label_last = A.date("%B", os.time{ year = now.year, month = now.month - 1, day = 1, hour = 12 })
    else
        label_this, label_last = T("This week"), T("Last week")
    end
    return { period = period, metric = metric, this = this, last = last, dir = dir, sentence = sentence,
        label_this = label_this, label_last = label_last, days_this = n, days_last = ln }
end

--- The comparison from the statistics, nil while loading, false without them.
function D.compare(refresh, period, metric)
    local raw = rawStats(refresh)
    if not raw then return raw end
    return D.compareFrom(raw.days, period, metric, os.date("*t"), D.weekStart(), raw.nums[1])
end

-- ─── monthly challenge ──────────────────────────────────────────────────────
-- One goal for the month. As it comes it is picked like Apple's monthly
-- challenge: the measure takes turns month by month (pages, then minutes,
-- then reading days) and the target is a tenth above your daily rate over
-- the last three months, for this month's length. Either can be set by hand.

D.CHALLENGE_METRICS = { "pages", "minutes", "days" }

local function monthTotals(days, y, m)
    local n_days = tonumber(os.date("%d", os.time{ year = y, month = m + 1, day = 0, hour = 12 })) or 30
    local tot = { pages = 0, minutes = 0, days = 0, n_days = n_days, by_day = {} }
    local prefix = ymKey(y, m) .. "-"
    for d = 1, n_days do
        local rec = days[prefix .. string.format("%02d", d)]
        local day = { pages = 0, minutes = 0, days = 0 }
        if rec then
            day.pages, day.minutes = rec.pages or 0, (rec.secs or 0) / 60
            if (rec.secs or 0) > 0 or (rec.pages or 0) > 0 then day.days = 1 end
            tot.pages = tot.pages + day.pages
            tot.minutes = tot.minutes + day.minutes
            tot.days = tot.days + day.days
        end
        tot.by_day[d] = day
    end
    return tot
end

local function roundTarget(metric, v, n_days)
    if metric == "days" then return A.clamp(math.ceil(v), 1, n_days) end
    if metric == "minutes" then
        local step = v >= 600 and 60 or 30
        return max(step, floor(v / step + 0.5) * step)
    end
    local step = v >= 2000 and 100 or 50
    return max(step, floor(v / step + 0.5) * step)
end

local CHALLENGE_DEFAULT = { pages = 300, minutes = 600, days = 12 }

--- Pure: this month's challenge. metric_pref "auto" or one of the metrics,
--- target_pref a number or nil (auto). now = os.date("*t") for this month.
function D.challengeFrom(days, metric_pref, target_pref, now)
    now = now or os.date("*t")
    local y, m = now.year, now.month
    local metric = metric_pref
    local auto_metric = not (metric == "pages" or metric == "minutes" or metric == "days")
    if auto_metric then metric = D.CHALLENGE_METRICS[(m - 1) % 3 + 1] end
    local cur = monthTotals(days or {}, y, m)
    local n_days = cur.n_days
    -- the last three whole months
    local sum, len = 0, 0
    for back = 1, 3 do
        local t = os.date("*t", os.time{ year = y, month = m - back, day = 1, hour = 12 })
        local mt = monthTotals(days or {}, t.year, t.month)
        sum, len = sum + mt[metric], len + mt.n_days
    end
    local target = tonumber(target_pref)
    local auto_target = not (target and target > 0)
    if auto_target then
        if sum > 0 and len > 0 then
            target = roundTarget(metric, sum / len * n_days * 1.1, n_days)
        else
            target = CHALLENGE_DEFAULT[metric]
        end
    end
    target = max(1, floor(target + 0.5))
    if metric == "days" then target = min(target, n_days) end
    local done = metric == "minutes" and floor(cur.minutes + 0.5) or cur[metric]
    local day = min(now.day, n_days)
    local left_days = n_days - day
    local remaining = max(0, target - done)
    -- what each day still to come (today counts) needs to bring
    local per_day = remaining > 0 and (remaining / max(1, left_days + 1)) or 0
    -- the running total, day by day, up to today
    local series, run = {}, 0
    for d = 1, day do
        run = run + (cur.by_day[d] and cur.by_day[d][metric] or 0)
        series[d] = run
    end
    return {
        series = series,
        metric = metric, target = target, done = done, frac = done / target,
        n_days = n_days, day = day, left_days = left_days, remaining = remaining,
        per_day = per_day, complete = done >= target,
        on_pace = done >= target * day / n_days,
        auto_metric = auto_metric, auto_target = auto_target, year = y, month = m,
    }
end

--- This month's challenge, nil while loading, false without statistics.
function D.challenge(refresh, metric_pref, target_pref)
    local raw = rawStats(refresh)
    if not raw then return raw end
    return D.challengeFrom(raw.days, metric_pref, target_pref)
end

-- ─── finish forecast ────────────────────────────────────────────────────────
-- When each book in progress will be done at the rate you have been reading
-- lately: its time left (worked out from your speed in that book, as Simple
-- UI's Currently reading shows it) over your average reading time a day across the last 30 days, or, for
-- a book with no time left on record, its pages left over your pages a day.

local FORECAST_DAYS = 30

--- Pure: the forecast for one book. avg = { secs = per day, pages = per day }.
function D.forecastFor(item, avg, now_t)
    now_t = now_t or os.time()
    local days
    if tonumber(item.left_min) and avg.secs > 0 then
        days = item.left_min * 60 / avg.secs
    elseif tonumber(item.pages) and avg.pages > 0 then
        days = item.pages * (1 - (item.pct or 0)) / avg.pages
    end
    if not days then return nil end
    days = max(0, math.ceil(days - 1e-9))
    local t = os.date("*t", now_t)
    local when = os.time{ year = t.year, month = t.month, day = t.day + days, hour = 12 }
    return { days = days, when = when }
end

--- Your reading a day over the last 30 days (today included).
function D.recentAverage(st)
    local out = { secs = 0, pages = 0, days = FORECAST_DAYS }
    if type(st) ~= "table" or type(st.days) ~= "table" then return out end
    local t = os.date("*t")
    for i = 0, FORECAST_DAYS - 1 do
        local rec = st.days[os.date("%Y-%m-%d", os.time{ year = t.year, month = t.month, day = t.day - i, hour = 12 })]
        if rec then out.secs, out.pages = out.secs + (rec.secs or 0), out.pages + (rec.pages or 0) end
    end
    out.secs, out.pages = out.secs / FORECAST_DAYS, out.pages / FORECAST_DAYS
    return out
end

--- Books finished this year so far, and where the year is heading at that rate.
function D.yearPace(yr)
    if type(yr) ~= "table" then return nil end
    local t = os.date("*t")
    local done = (yr.total or 0) + (select(2, D.yearGoal()) or 0)
    local days_in_year = tonumber(os.date("%j", os.time{ year = t.year, month = 12, day = 31, hour = 12 })) or 365
    local doy = tonumber(os.date("%j")) or 1
    local projected = doy >= 14 and floor(done / doy * days_in_year + 0.5) or nil
    return { done = done, projected = projected, goal = (D.yearGoal()) }
end

-- ─── the front light ────────────────────────────────────────────────────────
-- Brightness and warmth as 0..100, read from and set through KOReader's own
-- power device, the way its front light dialog does it.

local function powerd()
    local ok, Device = pcall(require, "device")
    if not (ok and Device) then return nil end
    local okp, pd = pcall(Device.getPowerDevice, Device)
    return okp and pd or nil, Device
end

function D.light()
    local pd, Device = powerd()
    local out = { has_light = false, has_warmth = false, level = 0, warmth = 0 }
    if not (pd and Device) then return out end
    local ok_fl, has = pcall(Device.hasFrontlight, Device)
    out.has_light = ok_fl and has and true or false
    if out.has_light then
        local lo, hi = tonumber(pd.fl_min) or 0, tonumber(pd.fl_max) or 100
        local cur = tonumber((pcall(pd.frontlightIntensity, pd)) and pd:frontlightIntensity()) or 0
        out.level = hi > lo and A.clamp(floor((cur - lo) / (hi - lo) * 100 + 0.5), 0, 100) or 0
        out.on = (pcall(pd.isFrontlightOn, pd)) and pd:isFrontlightOn() or cur > lo
    end
    local ok_nl, nl = pcall(Device.hasNaturalLight, Device)
    out.has_warmth = ok_nl and nl and true or false
    if out.has_warmth then
        out.warmth = tonumber((pcall(pd.frontlightWarmth, pd)) and pd:frontlightWarmth()) or 0
    end
    return out
end

--- Set the brightness to pct (1..100) of the light's range.
function D.setLight(pct)
    local pd = powerd()
    if not pd then return false end
    local lo, hi = tonumber(pd.fl_min) or 0, tonumber(pd.fl_max) or 100
    local v = lo + floor((hi - lo) * A.clamp(pct, 1, 100) / 100 + 0.5)
    v = A.clamp(max(v, lo + 1), lo, hi)
    pcall(pd.setIntensity, pd, v)
    if (pcall(pd.isFrontlightOff, pd)) and pd:isFrontlightOff() then pcall(pd.turnOnFrontlight, pd) end
    pcall(pd.updateResumeFrontlightState, pd)
    return true
end

--- Set the warmth to pct (0..100).
function D.setWarmth(pct)
    local pd = powerd()
    if not pd then return false end
    pcall(pd.setWarmth, pd, A.clamp(floor(pct + 0.5), 0, 100))
    return true
end

-- ─── the device: battery, storage, memory, Wi-Fi ─────────────────────────────
-- For the Device card. The battery, light and Wi-Fi are read each time (the
-- power device keeps them at hand); storage and memory mean a system call and
-- a file read, so they are read at most once a minute.

local _slow = { at = -1e9 }

-- Free and total space where the books are, in bytes, without starting `df`
-- (util.diskUsage forks the whole of KOReader to run it): statvfs, as df
-- itself does. f_bavail is what df calls Available.
local function diskSpace(path)
    local ok, total, free = pcall(function()
        local ffi = require("ffi")
        require("ffi/posix_h")
        local st = ffi.new("struct statvfs")
        if ffi.C.statvfs(path, st) ~= 0 then return nil end
        local unit = tonumber(st.f_frsize) or 0
        if unit <= 0 then unit = tonumber(st.f_bsize) or 0 end
        return tonumber(st.f_blocks) * unit, tonumber(st.f_bavail) * unit
    end)
    if ok and type(total) == "number" and total > 0 then return total, free end
    local ok_u, util = pcall(require, "util")
    if ok_u and util and util.diskUsage then
        local ok2, u = pcall(util.diskUsage, path)
        if ok2 and type(u) == "table" and tonumber(u.total) and tonumber(u.available) then
            return tonumber(u.total), tonumber(u.available)
        end
    end
    return nil
end

local function readSlow()
    local now = os.time()
    if now - _slow.at < 60 then return _slow end
    local out = { at = now }
    local ok_d, Device = pcall(require, "device")
    local home = ok_d and Device and Device.home_dir
    if type(home) ~= "string" or home == "" then
        home = G_reader_settings and G_reader_settings:readSetting("home_dir") or "."
    end
    out.disk_total, out.disk_free = diskSpace(home)
    -- the whole device's memory: how much is in use, of how much
    local ok_u, util = pcall(require, "util")
    if ok_u and util and util.calcFreeMem then
        local ok2, free, total = pcall(util.calcFreeMem)
        if ok2 and tonumber(free) and tonumber(total) and total > 0 then
            out.mem_total, out.mem_free = tonumber(total), tonumber(free)
        end
    end
    -- what KOReader itself takes (as Bookshelf's status line shows it)
    local fh = io.open("/proc/self/status", "r")
    if fh then
        local kb = (fh:read("*a") or ""):match("VmRSS:%s+(%d+)%s+kB")
        fh:close()
        if kb then out.mem_own = tonumber(kb) * 1024 end
    end
    _slow = out
    return out
end

--- { battery = { pct, charging, charged } | nil, light = D.light(),
---   wifi = { on, connected } | nil, disk_total, disk_free, mem_total, mem_free,
---   mem_own } (sizes in bytes; any of them nil when the device can't say)
function D.device()
    local out = {}
    local pd = powerd()
    if pd and pd.getCapacity then
        local ok, cap = pcall(pd.getCapacity, pd)
        if ok and type(cap) == "number" then
            local function call(name)
                if type(pd[name]) ~= "function" then return nil end
                local okv, v = pcall(pd[name], pd)
                return okv and v or nil
            end
            out.battery = { pct = A.clamp(floor(cap + 0.5), 0, 100),
                charging = call("isCharging") and true or false, charged = call("isCharged") and true or false }
        end
    end
    out.light = D.light()
    local ok_n, NM = pcall(require, "ui/network/manager")
    if ok_n and type(NM) == "table" and NM.isWifiOn then
        local ok1, on = pcall(NM.isWifiOn, NM)
        local ok2, conn = false, false
        if NM.isConnected then ok2, conn = pcall(NM.isConnected, NM) end
        if ok1 then out.wifi = { on = on and true or false, connected = (on and ok2 and conn) and true or false } end
    end
    local slow = readSlow()
    out.disk_total, out.disk_free = slow.disk_total, slow.disk_free
    out.mem_total, out.mem_free, out.mem_own = slow.mem_total, slow.mem_free, slow.mem_own
    return out
end

--- A short string that changes when what the Device card shows changes
--- (checked once a minute, so the card is only redrawn when it must be).
function D.deviceSig(d)
    d = d or D.device()
    local b, l, wf = d.battery or {}, d.light or {}, d.wifi or {}
    -- coarse steps for the sizes, which move a little all the time
    local function step(n, mib) return n and floor(n / 1048576 / mib) or "-" end
    return table.concat({ b.pct or "-", tostring(b.charging), tostring(b.charged), tostring(l.on), l.level or "-",
        l.warmth or "-", tostring(wf.on), tostring(wf.connected), step(d.disk_free, 100), step(d.mem_own, 16),
        d.mem_total and d.mem_free and floor((1 - d.mem_free / d.mem_total) * 20) or "-" }, "|")
end

--- Whether a toggle action is on right now: true / false, or nil when it is
--- not a toggle we can read.
function D.toggleState(entry)
    local action = type(entry) == "table" and type(entry.action) == "table" and entry.action or nil
    if not action then return nil end
    local id = next(action)
    if id == "toggle_wifi" or id == "wifi_on" then
        local ok, NM = pcall(require, "ui/network/manager")
        if ok and NM and NM.isWifiOn then
            local ok2, on = pcall(NM.isWifiOn, NM)
            if ok2 then return on and true or false end
        end
        return nil
    end
    if id == "night_mode" or id == "set_night_mode" then
        return G_reader_settings and G_reader_settings:isTrue("night_mode") or false
    end
    if id == "toggle_frontlight" then
        return D.light().on and true or false
    end
    return nil
end

-- ─── collections ─────────────────────────────────────────────────────────────

function D.collections()
    local ok, RC = pcall(require, "readcollection")
    if not (ok and RC and type(RC.coll) == "table") then return {} end
    local names = {}
    for name in pairs(RC.coll) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names, RC.default_collection_name
end

function D.collectionLabel(name)
    local ok, RC = pcall(require, "readcollection")
    if ok and RC and name == RC.default_collection_name then return T("Favorites") end
    return name
end

-- Files of a collection in the reader's own order.
function D.collection(name)
    local ok, RC = pcall(require, "readcollection")
    if not (ok and RC and type(RC.coll) == "table" and type(RC.coll[name]) == "table") then return nil end
    local items = {}
    for fp, item in pairs(RC.coll[name]) do
        items[#items + 1] = { fp = fp, order = type(item) == "table" and tonumber(item.order) or 0 }
    end
    table.sort(items, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.fp < b.fp
    end)
    local out = {}
    for _, it in ipairs(items) do out[#out + 1] = it.fp end
    return out
end

function D.inCollection(name, fp)
    local ok, RC = pcall(require, "readcollection")
    if not (ok and RC and type(RC.coll) == "table" and type(RC.coll[name]) == "table") then return false end
    return RC.coll[name][fp] ~= nil
end

-- ─── the library ─────────────────────────────────────────────────────────────
-- Every book under KOReader's home folder (Simple UI's library scan; see
-- A.host.libraryFiles), with its status. Titles, authors, series and genres
-- come from CoverBrowser's database in one read (A.host.libraryMeta), the
-- status from each book's sidecar. A book with no sidecar has never been
-- opened, which costs one file check.

local function statusFrom(fp)
    local pct, status, _, opened = D.progress(fp)
    if status == "reading" or status == "finished" or status == "on_hold" then return status end
    -- not started, by its status (Bookshelf: no status, or marked New)
    if status == "new" then return "unread" end
    pct = tonumber(pct)
    if opened and pct and pct > 0 then return pct >= 0.995 and "finished" or "reading" end
    return "unread"
end

-- Kept per book with its sidecar's modification time: a sidecar only changes
-- when its book is opened, so a recount re-reads only the books opened since.
local _status_memo = {}
local function bookStatus(fp)
    local ok, DocSettings = pcall(require, "docsettings")
    local l = lfs()
    if not (ok and DocSettings and DocSettings.findSidecarFile and l) then return statusFrom(fp) end
    local ok_f, sidecar = pcall(DocSettings.findSidecarFile, DocSettings, fp)
    if not ok_f then return statusFrom(fp) end
    if not sidecar then
        _status_memo[fp] = nil
        return "unread"
    end
    local mtime = l.attributes(sidecar, "modification") or 0
    local m = _status_memo[fp]
    if m and m.mtime == mtime then return m.status end
    local st = statusFrom(fp)
    _status_memo[fp] = { mtime = mtime, status = st }
    return st
end
D.bookStatus = bookStatus

-- "King, Stephen" -> "Stephen King"; anything else as it is.
local function authorName(a)
    if type(a) ~= "string" then return nil end
    a = a:match("^%s*(.-)%s*$")
    if a == "" then return nil end
    local last, first = a:match("^([^,]+),%s*([^,]+)$")
    if last and first then a = first .. " " .. last end
    return a
end
D.authorName = authorName

-- One book as the library cards use it, from CoverBrowser's record (or just
-- the file name when the book has not been indexed yet).
local function libBook(fp, meta, status)
    local name = (fp:match("([^/]+)$") or fp):gsub("%.[^.]+$", "")
    local authors = {}
    if type(meta) == "table" then
        local list = type(meta.authors) == "table" and meta.authors or { meta.author }
        for _, a in ipairs(list) do
            local n = authorName(a)
            if n then authors[#authors + 1] = n end
        end
    end
    local genres = {}
    if type(meta) == "table" and type(meta.genres) == "table" then
        for _, g in ipairs(meta.genres) do
            if type(g) == "string" and g:match("%S") then genres[#genres + 1] = g:match("^%s*(.-)%s*$") end
        end
    end
    local series = type(meta) == "table" and type(meta.series_name) == "string" and meta.series_name ~= "" and meta.series_name or nil
    return {
        fp = fp, status = status,
        title = (type(meta) == "table" and type(meta.title) == "string" and meta.title ~= "" and meta.title) or name,
        authors = authors, genres = genres, series = series,
        num = series and tonumber(type(meta) == "table" and meta.series_num) or nil,
    }
end
D.libBook = libBook

local function computeLibrary()
    local ok, paths = pcall(A.host.libraryFiles)
    if not ok or type(paths) ~= "table" then return false end
    local ok_m, all_meta = pcall(A.host.libraryMeta)
    if not (ok_m and type(all_meta) == "table") then all_meta = {} end
    local books, counts = {}, { unread = 0, reading = 0, on_hold = 0, finished = 0 }
    for _, fp in ipairs(paths) do
        if type(fp) == "string" then
            local meta = all_meta[fp]
            local st = bookStatus(fp)
            counts[st] = counts[st] + 1
            books[#books + 1] = libBook(fp, meta, st)
        end
    end
    return { books = books, counts = counts, total = #books }
end

-- Recounted at most every 15 minutes, and only while a card that needs it is
-- on screen; a settings change does not trigger a recount.
D.library = deferred("library", {
    ttl = 900, sticky = true, heavy = true,
    sig = function(v)
        local c = v.counts
        return table.concat({ v.total, c.unread, c.reading, c.on_hold, c.finished }, ",")
    end,
}, computeLibrary)

-- Count the library again on the next look.
function D.recountLibrary()
    if _slots.library then _slots.library.at = 0 end
end

-- Distinct genres or authors in the library, most books first: { {name, n} }.
function D.libraryValues(lib, field)
    local tally, order = {}, {}
    for _, b in ipairs(lib and lib.books or {}) do
        local seen = {}
        for _, v in ipairs(b[field] or {}) do
            local k = v:lower()
            if not seen[k] then
                seen[k] = true
                if not tally[k] then tally[k] = { name = v, n = 0 }; order[#order + 1] = k end
                tally[k].n = tally[k].n + 1
            end
        end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = tally[k] end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- ─── most-read authors ───────────────────────────────────────────────────────
-- By books: finished books in the library, per author. By time: hours in the
-- statistics, per author (every book KOReader has timed, kept or not).

function D.authorsByBooks(lib)
    local tally, order = {}, {}
    for _, b in ipairs(lib and lib.books or {}) do
        if b.status == "finished" then
            for _, a in ipairs(b.authors) do
                local k = a:lower()
                if not tally[k] then tally[k] = { name = a, n = 0, books = 0 }; order[#order + 1] = k end
                tally[k].n = tally[k].n + 1
                tally[k].books = tally[k].books + 1
            end
        end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = tally[k] end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

local function computeAuthorTime()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local tally, order = {}, {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local stmt = conn:prepare("SELECT authors, total_read_time FROM book WHERE total_read_time > 0")
        local row = stmt:step()
        while row do
            local secs = tonumber(row[2]) or 0
            local raw = type(row[1]) == "string" and row[1] or ""
            local names, seen = {}, {}
            for part in raw:gmatch("[^\n]+") do
                local n = authorName(part)
                if n and not seen[n:lower()] then seen[n:lower()] = true; names[#names + 1] = n end
            end
            for _, n in ipairs(names) do
                local k = n:lower()
                if not tally[k] then tally[k] = { name = n, n = 0, books = 0 }; order[#order + 1] = k end
                tally[k].n = tally[k].n + secs
                tally[k].books = tally[k].books + 1
            end
            row = stmt:step()
        end
        stmt:close()
    end)
    conn:close()
    if not ok then error(err) end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = tally[k] end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

D.authorTime = deferred("author_time", {
    ttl = 900, key = statsKey,
    sig = function(v) return #v .. ":" .. (v[1] and (v[1].name .. v[1].n) or "") end,
}, computeAuthorTime)

--- The most-read authors: { {name, n, books} } with n = books finished or
--- seconds read. nil while loading, false without the data.
function D.authors(refresh, by)
    if by == "time" then return D.authorTime(refresh) end
    local lib = D.library(refresh)
    if not lib then return lib end
    return D.authorsByBooks(lib)
end

-- ─── random pick ─────────────────────────────────────────────────────────────
-- A book you haven't started, from the whole library or one collection, and
-- only the genres or authors you choose. A book in a series stands in for the
-- series, and the series offers only its next book: the first one in order
-- that isn't finished, and only if that one isn't started yet either (if
-- you're in the middle of book 7, the series sits this one out).

D.PICK_EVERY = { "day", "week", "month", "tap" }

local function lowerSet(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local set = {}
    for _, v in ipairs(list) do if type(v) == "string" then set[v:lower()] = true end end
    return set
end

local function anyIn(list, set)
    for _, v in ipairs(list or {}) do if set[v:lower()] then return true end end
    return false
end

--- Pure: the books the pick can land on, sorted by file.
--- o = { coll = { [fp] = true } or nil, genres = { names } or nil, authors = { names } or nil }
function D.pickCandidates(books, o)
    o = o or {}
    local genres, authors = lowerSet(o.genres), lowerSet(o.authors)
    local series = {}
    for _, b in ipairs(books) do
        if b.series then
            local k = b.series:lower()
            series[k] = series[k] or {}
            table.insert(series[k], b)
        end
    end
    for _, list in pairs(series) do
        table.sort(list, function(a, b)
            if (a.num ~= nil) ~= (b.num ~= nil) then return a.num ~= nil end
            if a.num and b.num and a.num ~= b.num then return a.num < b.num end
            return a.title:lower() < b.title:lower()
        end)
    end
    local out, seen = {}, {}
    for _, b in ipairs(books) do
        if b.status == "unread"
                and (not o.coll or o.coll[b.fp])
                and (not genres or anyIn(b.genres, genres))
                and (not authors or anyIn(b.authors, authors)) then
            local pick = b
            if b.series then
                pick = nil
                for _, s in ipairs(series[b.series:lower()]) do
                    if s.status ~= "finished" then
                        if s.status == "unread" then pick = s end
                        break
                    end
                end
            end
            if pick and not seen[pick.fp] then
                seen[pick.fp] = true
                out[#out + 1] = pick
            end
        end
    end
    table.sort(out, function(a, b) return a.fp < b.fp end)
    return out
end

-- Where in the series a book sits: "Book 7 of 8", or nil.
function D.seriesPlace(books, b)
    if not (b and b.series) then return nil end
    local n, top = 0, 0
    for _, o in ipairs(books) do
        if o.series and o.series:lower() == b.series:lower() then
            n = n + 1
            if o.num and o.num > top then top = o.num end
        end
    end
    return b.num, max(n, floor(top))
end

-- The stretch of time one pick lasts: "2026-10-19", "w2026-10-19" (the
-- week's first day), "2026-10" or "tap".
function D.pickPeriod(every, now)
    now = now or os.time()
    if every == "tap" then return "tap" end
    if every == "month" then return os.date("%Y-%m", now) end
    if every == "week" then
        local t = os.date("*t", now)
        local back = (t.wday - D.weekStart()) % 7
        return "w" .. os.date("%Y-%m-%d", os.time{ year = t.year, month = t.month, day = t.day - back, hour = 12 })
    end
    return os.date("%Y-%m-%d", now)
end

local function hash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483647 end
    return h
end

--- Pure: which candidate a period lands on. n = how many times "Another"
--- was tapped this period; skip = a file to step over when there is a choice.
function D.pickAt(cands, period, n, skip)
    if #cands == 0 then return nil end
    local i = (hash(period .. "#" .. tostring(n or 0)) % #cands) + 1
    if skip and #cands > 1 and cands[i].fp == skip then i = i % #cands + 1 end
    return cands[i]
end

-- ─── today's reading, sitting by sitting ─────────────────────────────────────

--- Pure: rows = { {start, secs, book, title} } in time order -> sittings
--- { {start, stop, secs, title} } (a break of more than ten minutes ends one;
--- a sitting is named after the book it spent longest on).
function D.timelineFrom(rows, gap)
    gap = gap or SESSION_GAP
    local out, cur, last_end = {}, nil, nil
    for _, r in ipairs(rows) do
        if not cur or r.start - last_end > gap then
            cur = { start = r.start, stop = r.start, secs = 0, by_book = {} }
            out[#out + 1] = cur
        end
        cur.secs = cur.secs + r.secs
        cur.stop = max(cur.stop, r.start + r.secs)
        local k = r.book or 0
        local e = cur.by_book[k]
        if not e then e = { secs = 0, title = r.title }; cur.by_book[k] = e end
        e.secs = e.secs + r.secs
        last_end = max(last_end or 0, r.start + r.secs)
    end
    for _, s in ipairs(out) do
        local best
        for k, e in pairs(s.by_book) do
            if not best or e.secs > best.secs or (e.secs == best.secs and tostring(k) < tostring(best.k)) then
                best = { secs = e.secs, title = e.title, k = k }
            end
        end
        s.title = best and best.title or nil
        s.book = best and best.k or nil
        s.by_book = nil
    end
    return out
end

local function computeToday()
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local t = os.date("*t")
    local since = os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
    local rows = {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local stmt = conn:prepare("SELECT p.start_time, p.duration, p.id_book, b.title FROM page_stat_data p"
            .. " LEFT JOIN book b ON b.id = p.id_book WHERE p.start_time >= ? ORDER BY p.start_time")
        local row = stmt:reset():bind(since):step()
        while row do
            rows[#rows + 1] = { start = tonumber(row[1]) or 0, secs = tonumber(row[2]) or 0,
                book = tonumber(row[3]), title = type(row[4]) == "string" and row[4] or nil }
            row = stmt:step()
        end
        stmt:close()
    end)
    conn:close()
    if not ok then error(err) end
    return { day = os.date("%Y-%m-%d"), since = since, sittings = D.timelineFrom(rows) }
end

local rawToday = deferred("today", {
    ttl = 120, key = statsKey,
    sig = function(v)
        local last = v.sittings[#v.sittings]
        return v.day .. #v.sittings .. ":" .. (last and (last.start .. "+" .. last.secs) or "")
    end,
}, computeToday)

--- Today's sittings, nil while loading, false without statistics.
function D.today(refresh)
    local v = rawToday(refresh)
    if v and v.day ~= os.date("%Y-%m-%d") then return { day = os.date("%Y-%m-%d"), sittings = {} } end
    return v
end

-- ─── cover calendar ──────────────────────────────────────────────────────────
-- Which books were read on each day, from the statistics, and the file each
-- one is (for its cover). The statistics know a book by its checksum, and so
-- does its sidecar, so the reading history is matched by checksum: newest
-- first, each sidecar read once a session, stopping at the first match. A
-- book not found that way is matched by title against the library if it has
-- been counted already; failing that the day shows the title instead.

local _fp_md5, _md5_fp = {}, {}

local function sidecarMd5(fp)
    local v = _fp_md5[fp]
    if v == nil then
        v = false
        pcall(function()
            v = require("docsettings"):open(fp):readSetting("partial_md5_checksum") or false
        end)
        _fp_md5[fp] = v
        if v and not _md5_fp[v] then _md5_fp[v] = fp end
    end
    return v or nil
end

local function fileForBook(md5, title)
    if md5 then
        local known = _md5_fp[md5]
        if known and D.fileExists(known) then return known end
        for _, e in ipairs(history()) do
            local fp = e.file
            if fp and _fp_md5[fp] == nil and D.fileExists(fp) and sidecarMd5(fp) == md5 then return fp end
        end
    end
    local lib = _slots.library and _slots.library.value
    if lib and type(title) == "string" and title ~= "" then
        local want = title:lower()
        for _, b in ipairs(lib.books) do
            if b.title:lower() == want then return b.fp end
        end
    end
    return nil
end

-- The days from..to (times, to not included): { ["YYYY-MM-DD"] = { book, ... } },
-- each day's books read longest first: { title, author, secs, pages, fp }.
local function readDays(from_t, to_t)
    local l = lfs()
    local path = statsPath()
    if not (l and l.attributes(path, "mode") == "file") then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(path, "ro")
    local days, books = {}, {}
    local ok, err = pcall(function()
        conn:exec("PRAGMA busy_timeout=200;")
        local stmt = conn:prepare("SELECT strftime('%Y-%m-%d', p.start_time, 'unixepoch', 'localtime'), p.id_book,"
            .. " sum(p.duration), count(DISTINCT p.page), b.title, b.authors, b.md5"
            .. " FROM page_stat_data p JOIN book b ON b.id = p.id_book"
            .. " WHERE p.start_time >= ? AND p.start_time < ? GROUP BY 1, 2")
        local row = stmt:reset():bind(from_t, to_t):step()
        while row do
            local id = tonumber(row[2]) or 0
            local bk = books[id]
            if not bk then
                local author = type(row[6]) == "string" and row[6]:match("^[^\n]+") or nil
                bk = { title = type(row[5]) == "string" and row[5] or "", author = author,
                    md5 = type(row[7]) == "string" and row[7] or nil }
                books[id] = bk
            end
            local d = tostring(row[1])
            days[d] = days[d] or {}
            table.insert(days[d], { book = bk, secs = tonumber(row[3]) or 0, pages = tonumber(row[4]) or 0 })
            row = stmt:step()
        end
        stmt:close()
    end)
    conn:close()
    if not ok then error(err) end
    for _, bk in pairs(books) do bk.fp = fileForBook(bk.md5, bk.title) end
    local out = {}
    for d, list in pairs(days) do
        table.sort(list, function(a, b) return a.secs > b.secs end)
        local day = {}
        for i, e in ipairs(list) do
            day[i] = { title = e.book.title, author = e.book.author, fp = e.book.fp, secs = e.secs, pages = e.pages }
        end
        out[d] = day
    end
    return out
end

local function monthRange()
    local y, m = A.viewMonth()
    return os.time{ year = y, month = m, day = 1, hour = 0 }, os.time{ year = y, month = m + 1, day = 1, hour = 0 }, y .. "-" .. m
end

local function weekRange()
    local t = os.date("*t")
    local back = (t.wday - D.weekStart()) % 7
    local from = os.time{ year = t.year, month = t.month, day = t.day - back, hour = 0 }
    local to = os.time{ year = t.year, month = t.month, day = t.day - back + 7, hour = 0 }
    return from, to, os.date("%Y-%m-%d", from)
end

local function daysSig(v)
    local keys = {}
    for d, list in pairs(v) do
        local secs = 0
        for _, e in ipairs(list) do secs = secs + e.secs end
        keys[#keys + 1] = d .. "=" .. #list .. ":" .. secs .. ":" .. tostring(list[1] and list[1].fp)
    end
    table.sort(keys)
    return table.concat(keys, ";")
end

local coverMonth = deferred("cover_month", {
    ttl = 600, sig = daysSig,
    key = function() local _, _, k = monthRange(); return statsKey() .. "|" .. k end,
}, function() local from, to = monthRange(); return readDays(from, to) end)

local coverWeek = deferred("cover_week", {
    ttl = 600, sig = daysSig,
    key = function() local _, _, k = weekRange(); return statsKey() .. "|" .. k .. "|" .. D.weekStart() end,
}, function() local from, to = weekRange(); return readDays(from, to) end)

--- The books read each day of the month the Monthly page shows ("month") or
--- of this week ("week"). nil while loading, false without statistics.
function D.coverDays(refresh, which, sync)
    if which == "week" then return coverWeek(refresh, sync) end
    return coverMonth(refresh, sync)
end
D.readDays = readDays

-- ─── your highlights ─────────────────────────────────────────────────────────
-- Read from each book's sidecar (KOReader's "annotations", or the older
-- "highlight" table), once per sidecar version: a sidecar only changes when
-- its book is opened, so a re-read touches only the books opened since.

local _hl_memo = {}
local HL_TEXT_MAX = 700

local function clipText(s)
    s = s:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #s > HL_TEXT_MAX then
        s = (s:sub(1, HL_TEXT_MAX):match("^(.-)%s+%S*$") or s:sub(1, HL_TEXT_MAX)) .. "\xE2\x80\xA6"
    end
    return s
end

--- A book's highlights: { {text, note, chapter, datetime}, ... } in the order made.
function D.highlightsOf(fp)
    local okd, DocSettings = pcall(require, "docsettings")
    local l = lfs()
    if not (okd and DocSettings and DocSettings.findSidecarFile and l and type(fp) == "string") then return {} end
    local ok, sidecar = pcall(DocSettings.findSidecarFile, DocSettings, fp)
    if not ok or not sidecar then _hl_memo[fp] = nil; return {} end
    local mtime = l.attributes(sidecar, "modification") or 0
    local m = _hl_memo[fp]
    if m and m.mtime == mtime then return m.list end
    local list = {}
    pcall(function()
        local ds = DocSettings:open(fp)
        local ann = ds:readSetting("annotations")
        if type(ann) == "table" and #ann > 0 then
            for _, a in ipairs(ann) do
                -- a highlight has a drawer; a plain page bookmark does not
                if type(a) == "table" and a.drawer and type(a.text) == "string" and a.text:match("%S") then
                    local note = type(a.note) == "string" and a.note:match("%S") and clipText(a.note) or nil
                    list[#list + 1] = { text = clipText(a.text), note = note,
                        chapter = type(a.chapter) == "string" and a.chapter or nil,
                        datetime = type(a.datetime) == "string" and a.datetime or nil }
                end
            end
        else
            local hl = ds:readSetting("highlight")
            if type(hl) == "table" then
                local pages = {}
                for page in pairs(hl) do pages[#pages + 1] = page end
                table.sort(pages, function(a, b) return tostring(a) < tostring(b) end)
                for _, page in ipairs(pages) do
                    for _, h in ipairs(type(hl[page]) == "table" and hl[page] or {}) do
                        if type(h) == "table" and type(h.text) == "string" and h.text:match("%S") then
                            list[#list + 1] = { text = clipText(h.text),
                                datetime = type(h.datetime) == "string" and h.datetime or nil }
                        end
                    end
                end
            end
        end
    end)
    _hl_memo[fp] = { mtime = mtime, list = list }
    return list
end

local HL_SCAN = 300

-- Every book in the reading history that has highlights: { {fp, list}, ... }.
local function computeHighlights()
    local out, seen, total = {}, {}, 0
    local hist = history()
    for i = 1, min(#hist, HL_SCAN) do
        local fp = hist[i] and hist[i].file
        if fp and not seen[fp] and D.fileExists(fp) then
            seen[fp] = true
            local list = D.highlightsOf(fp)
            if #list > 0 then
                out[#out + 1] = { fp = fp, list = list }
                total = total + #list
            end
        end
    end
    return { books = out, total = total }
end

D.highlights = deferred("highlights", {
    ttl = 1800, sticky = true, heavy = true,
    sig = function(v) return v.total .. ":" .. #v.books end,
}, computeHighlights)

--- Pure: 1..n in an order of their own for `day`, the same all day (the
--- quote cards walk through it).
local _order = {}
function D.dayOrder(n, day)
    local key = n .. "|" .. tostring(day)
    if _order.key == key then return _order.list end
    local h = 5381
    for i = 1, #key do h = (h * 33 + key:byte(i)) % 2147483647 end
    local seed = h > 0 and h or 1
    local list = {}
    for i = 1, n do list[i] = i end
    for i = n, 2, -1 do
        seed = (seed * 48271) % 2147483647
        local j = (seed % i) + 1
        list[i], list[j] = list[j], list[i]
    end
    _order.key, _order.list = key, list
    return list
end

-- ─── quote of the day ────────────────────────────────────────────────────────
-- One of your highlights a day, from the books in your history (see
-- A.host.quoteOfTheDay). It keeps a count of each book's highlights and opens
-- only the sidecar it picks from.

D.hasQuotes = function() return true end

local quoteSlot = deferred("quote", {
    ttl = 600,
    key = function() return os.date("%Y-%m-%d") end,
    sig = function(v) return v and tostring(v.text) .. tostring(v.filepath) or "" end,
}, function()
    return A.host.quoteOfTheDay() or false
end)

function D.quote(refresh, sync) return quoteSlot(refresh, sync) end

--- The quote Quote of the day showed last, without looking for one.
function D.quotePeek()
    local slot = _slots.quote
    return slot and slot.value or nil
end

-- Step to another quote (and show it straight away).
function D.nextQuote()
    pcall(A.host.rerollQuote)
    _slots.quote.at = 0
    quoteSlot(nil, true)
end

-- ─── covers ──────────────────────────────────────────────────────────────────
-- Through Simple UI's cover cache: the cover cropped to fill exactly w x h,
-- cached there, and queued for extraction when CoverBrowser has not indexed
-- the book yet (the card is redrawn when it lands; see modules.lua). Without
-- Simple UI, from CoverBrowser's database directly, scaled here.
--
-- Scaled covers kept here are only ever DROPPED (never freed): a card still on
-- screen may be holding that bitmap, and Blitbuffer frees the memory itself
-- once nothing refers to it.

local _covers, _cover_order, _cover_bytes = {}, {}, 0
local COVER_BUDGET = 12 * 1024 * 1024
local _cover_miss = {}

-- Files whose cover was asked for while it was still being extracted, by
-- module: modules.lua checks them and redraws the card when they arrive.
D.cover_owner = nil
D.cover_pending = {}

local function bbBytes(bb)
    local ok, n = pcall(function() return tonumber(bb.stride) * bb:getHeight() end)
    return ok and n or 0
end

-- A light unsharp mask (3 x 3) for a small cover, so it stays crisp on
-- e-ink after shrinking. Works on the 8-bit grey and 32-bit colour bitmaps;
-- any other kind is left as it is.
local function sharpen(bb, amount)
    local ffi = require("ffi")
    local BB = require("ffi/blitbuffer")
    local t = bb:getType()
    local bpp = (t == BB.TYPE_BB8 and 1) or (t == BB.TYPE_BBRGB32 and 4) or nil
    if not bpp or bb:getRotation() ~= 0 or bb:getInverse() ~= 0 then return end
    local w, h = bb:getWidth(), bb:getHeight()
    local stride = tonumber(bb.stride)
    if w < 3 or h < 3 or not stride or stride < w * bpp then return end
    local dst = ffi.cast("uint8_t*", bb.data)
    local n = stride * h
    local src = ffi.new("uint8_t[?]", n)
    ffi.copy(src, dst, n)
    local chans = bpp == 1 and 1 or 3
    for y = 1, h - 2 do
        local row = y * stride
        for x = 1, w - 2 do
            local base = row + x * bpp
            for ch = 0, chans - 1 do
                local i = base + ch
                local around = src[i - stride - bpp] + src[i - stride] + src[i - stride + bpp]
                    + src[i - bpp] + src[i + bpp]
                    + src[i + stride - bpp] + src[i + stride] + src[i + stride + bpp]
                local c = src[i]
                local v = c + amount * (c - around / 8)
                dst[i] = v < 0 and 0 or (v > 255 and 255 or floor(v + 0.5))
            end
        end
    end
end
D._sharpen = sharpen

local function keepCover(key, bb)
    _covers[key] = bb
    _cover_order[#_cover_order + 1] = key
    _cover_bytes = _cover_bytes + bbBytes(bb)
    while _cover_bytes > COVER_BUDGET and #_cover_order > 1 do
        local old = table.remove(_cover_order, 1)
        local obb = _covers[old]
        if obb then _cover_bytes = _cover_bytes - bbBytes(obb) end
        _covers[old] = nil
    end
end

--- A bitmap at least w x h, scaled so the cover fills that box (the caller
--- crops the overhang). align = "top" crops from the top where it can.
--- sharp: sharpened a little (small covers that are also turned, like the
--- polaroids), as a copy of our own. nil when the book has no cover (or it
--- is not extracted yet).
-- A cover handed over for one book (the reader panel gives the open book's,
-- which no cover cache may hold yet). Kept until another replaces it.
local _seed = {}
function D.seedCover(fp, bb)
    if _seed.bb and _seed.bb ~= bb then pcall(_seed.bb.free, _seed.bb) end
    _seed = { fp = fp, bb = bb }
end

function D.cover(fp, w, h, align, sharp)
    if type(fp) ~= "string" or w < 2 or h < 2 then return nil end
    w, h = floor(w), floor(h)
    local key = fp .. "\0" .. w .. "x" .. h .. (sharp and "\0s" or "")
    if sharp and _covers[key] then return _covers[key] end
    local seeded = (_seed.fp == fp) and _seed.bb or nil
    local handled, bb, pending
    if not seeded then handled, bb, pending = A.host.cover(fp, w, h, align) end
    if handled then
        if not bb and pending and D.cover_owner then
            local set = D.cover_pending[D.cover_owner]
            if not set then set = {}; D.cover_pending[D.cover_owner] = set end
            set[fp] = true
        end
        if bb and sharp then
            -- Simple UI's bitmap belongs to its cache: sharpen a copy
            local ok, cp = pcall(function() return bb:copy() end)
            if ok and cp then
                pcall(sharpen, cp, 0.6)
                keepCover(key, cp)
                return cp
            end
        end
        return bb
    end
    local hit = _covers[key]
    if hit then return hit end
    local miss = _cover_miss[fp]
    if not seeded and miss and os.time() - miss < 120 then return nil end
    local src = seeded or A.host.rawCover(fp)
    if not src then
        _cover_miss[fp] = os.time()
        return nil
    end
    -- Scaled into a bitmap of our own. KOReader's scaler frees the bitmap it
    -- was given unless told not to (and hands the same one back when no
    -- scaling is needed): the seeded cover must outlive this call, so it is
    -- never freed here and is copied when it's already the right size. A
    -- cover read for this call alone (rawCover decodes a fresh one) is ours
    -- to free once scaled.
    local ok, scaled = pcall(function()
        local sw, sh = src:getWidth(), src:getHeight()
        local k = max(w / sw, h / sh)
        local tw, th = max(w, floor(sw * k + 0.5)), max(h, floor(sh * k + 0.5))
        local out = require("ui/renderimage"):scaleBlitBuffer(src, tw, th, false)
        if out == src then
            if seeded then out = src:copy() end
        elseif not seeded then
            src:free()
        end
        return out
    end)
    if ok and scaled and sharp then pcall(sharpen, scaled, 0.6) end
    if not ok or not scaled then
        _cover_miss[fp] = os.time()
        return nil
    end
    keepCover(key, scaled)
    return scaled
end

-- ─── actions ─────────────────────────────────────────────────────────────────

function D.openBook(ctx, fp)
    if not D.fileExists(fp) then
        pcall(function()
            require("ui/uimanager"):show(require("ui/widget/notification"):new{
                text = T("That file is no longer on the device"),
            })
        end)
        return
    end
    A.host.openBook(ctx, fp)
end

-- The book's menu (Simple UI's book dialog: status, collections, book
-- information, ...), or KOReader's book information without Simple UI.
function D.showDetails(ctx, fp)
    if not D.fileExists(fp) then return D.openBook(ctx, fp) end
    A.host.showDetails(ctx, fp)
end

-- Run a KOReader action by its dispatcher name.
function D.dispatch(name)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and Dispatcher then pcall(Dispatcher.execute, Dispatcher, { [name] = true }) end
end

-- Is a plugin with this name loaded? (FileManager or Reader instance.)
function D.hasPlugin(name)
    for _, mod in ipairs{ "apps/filemanager/filemanager", "apps/reader/readerui" } do
        local ok, UI = pcall(require, mod)
        if ok and UI and UI.instance and UI.instance[name] then return true end
    end
    return false
end

return D
