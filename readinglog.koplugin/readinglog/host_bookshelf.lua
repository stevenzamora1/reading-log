--[[
Reading Log host adapter for Bookshelf: everything the cards need from the app
around them, when they are Bookshelf micro-modules (the bookshelf_modules/
folder of this plugin).

It starts from host.lua (KOReader's own answers underneath) and puts
Bookshelf's in wherever Bookshelf has them, so the cards agree with
Bookshelf's own modules:

  card colour, ink  Bookshelf's module card (the colours the reader gave this
                    card with the palette icon, while it draws)
  fonts             Bookshelf's font
  book facts        Bookshelf's book repository (its cached records)
  covers            Bookshelf's repository (custom covers first)
  the library       Bookshelf's library walk and its light records
  goals             Bookshelf's Reading goals settings (shared with its card)
  quotes            Bookshelf's quote of the day (shared with its card)
  open / details    ctx.open_book / ctx.show_book (Bookshelf 6.0.2 and
                    newer), else the older ways
  redraws           the card's own reload, or a rebuild of the top panel

Settings are the same file as with Simple UI (store.lua).
]]

local A = ...
local chunk = assert(loadfile(A.dir .. "/host.lua"))
local H = chunk(A)   -- sets A.host = H; the Bookshelf answers go on top
local T = A._

local floor, max = math.floor, math.max
local try = H.try

H.KIND = "bookshelf"

local function repo() return try("lib/bookshelf_book_repository") end

--- Is Bookshelf there (its module kit can be loaded)?
function H.available()
    return try("lib/bookshelf_module_kit") ~= nil
end

--- Bookshelf's version, from the _meta.lua beside the code that is running.
function H.version()
    local ok, v = pcall(function()
        local Kit = require("lib/bookshelf_module_kit")
        local fn
        for _, f in pairs(Kit) do if type(f) == "function" then fn = f break end end
        local src = debug.getinfo(fn, "S").source:gsub("^@", "")
        return dofile(src:match("^(.*)/lib/[^/]*$") .. "/_meta.lua").version
    end)
    return ok and v or nil
end

-- ─── text ────────────────────────────────────────────────────────────────────

local base_safe = H.safeText
function H.safeText(s)
    local Safe = try("lib/bookshelf_text_safe")
    if Safe and Safe.safe then
        local ok, r = pcall(Safe.safe, s)
        if ok and type(r) == "string" then return r end
    end
    return base_safe(s)
end

local base_text = H.textClass
function H.textClass()
    local Tx = try("lib/bookshelf_colour_text")
    if type(Tx) == "table" and Tx.new then return Tx end
    return base_text()
end

--- A face in Bookshelf's font. Returns face, whether bold must be synthesised.
function H.face(size, o)
    o = o or {}
    local Fonts = try("lib/bookshelf_fonts")
    if Fonts and Fonts.getFace then
        local ok, face, bold = pcall(Fonts.getFace, Fonts, "cfont", size, { bold = o.bold, italic = o.italic })
        if ok and face then return face, bold end
    end
    local Font = require("ui/font")
    local getFace = H.nativeGetFace() or Font.getFace
    return getFace(Font, o.bold and "tfont" or "cfont", size), false
end

-- Simple UI's wallpaper never shows through a Bookshelf card.
function H.seeThrough() return false end

-- ─── colours ─────────────────────────────────────────────────────────────────

local function rgbOf(c, fallback)
    if type(c) == "nil" then return fallback end
    local ok, r, g, b = pcall(function()
        local x = c:getColorRGB32()
        return x.r, x.g, x.b
    end)
    if ok and r then return { r, g, b } end
    return fallback
end

--- Bookshelf's module card, its ink and its muted ink. Bookshelf points these
--- at the card's own colours (the palette icon) while the card draws.
function H.pageColors()
    local bg, fg, muted = { 0xEE, 0xEE, 0xEE }, { 0, 0, 0 }, { 0x55, 0x55, 0x55 }
    local Kit = try("lib/bookshelf_module_kit")
    if Kit then
        bg = rgbOf(Kit.CARD_BG, bg)
        fg = rgbOf(Kit.COLOR_PRIMARY, fg)
        muted = rgbOf(Kit.COLOR_MUTED, muted)
    end
    return bg, fg, muted
end

-- ─── books ───────────────────────────────────────────────────────────────────

local base_meta = H.bookMeta
--- { title, author, genres, series, cover_path } from Bookshelf's records.
function H.bookMeta(fp)
    local Repo = repo()
    if Repo and Repo.buildBookMeta then
        local ok, r = pcall(Repo.buildBookMeta, fp, { want_cover = false })
        if ok and type(r) == "table" then
            return {
                title = r.title,
                author = r.author or (type(r.authors) == "table" and r.authors[1]) or nil,
                genres = type(r.genres) == "table" and r.genres or {},
                series = r.series_name,
                cover_path = r.cover_image_path,
            }
        end
    end
    return base_meta(fp)
end

-- A book's status is the one Bookshelf gives it (its Shelf size card, its
-- Reading filter): marked New is not started, whatever percentage is left
-- in it, and so is an opened book Bookshelf gives no status (older versions;
-- 6.0.4 and newer call one with a percentage Reading themselves).
local base_progress = H.progress
function H.progress(fp)
    local Repo = repo()
    if Repo and Repo.progressFor then
        local ok, pct, status, _, pages, opened = pcall(Repo.progressFor, fp)
        if ok then
            if opened and status == nil then status = "new" end
            return pct, status, pages, opened
        end
    end
    if Repo and Repo.readProgress then
        local ok, pct, status, _, pages = pcall(Repo.readProgress, fp)
        if ok then return pct, status or "new", pages, true end
    end
    return base_progress(fp)
end

local base_finished = H.finishedOn
function H.finishedOn(fp)
    local Repo = repo()
    if Repo and Repo.finishedOn then
        local ok, d = pcall(Repo.finishedOn, fp)
        if ok then return d end
    end
    return base_finished(fp)
end

--- Minutes left, as Bookshelf works it out from your speed in that book.
function H.timeLeft(fp, pct)
    local Repo = repo()
    if Repo and Repo.enrichStats then
        local probe = { filepath = fp, book_pct = pct }
        local ok = pcall(Repo.enrichStats, probe)
        if ok then return tonumber(probe.book_time_left_minutes) end
    end
    return nil
end

-- Bookshelf keeps no finished-books ledger: the data layer counts the
-- history and the sidecars, the same rule as Bookshelf's Reading goals card.
function H.finishedBooks() return nil end

-- ─── covers ──────────────────────────────────────────────────────────────────

-- Not handled here: the data layer scales the bitmap rawCover gives it.
function H.cover() return false end
function H.coverSettled() return "none" end

local base_raw = H.rawCover
function H.rawCover(fp)
    local meta = H.bookMeta(fp)
    local lfs = try("libs/libkoreader-lfs")
    if meta.cover_path and lfs and lfs.attributes(meta.cover_path, "mode") == "file" then
        local ok, bb = pcall(function()
            return require("ui/renderimage"):renderImageFile(meta.cover_path, false)
        end)
        if ok and bb then return bb end
    end
    local Repo = repo()
    if Repo and Repo.getCoverBB then
        local ok, bb = pcall(Repo.getCoverBB, fp)
        if ok and bb then return bb end
    end
    return base_raw(fp)
end

-- ─── the library ─────────────────────────────────────────────────────────────

local base_files = H.libraryFiles
--- Every book Bookshelf's library walk finds; KOReader's home folder without it.
function H.libraryFiles()
    local Repo = repo()
    if Repo and Repo.getAllFilepaths then
        local ok, paths = pcall(Repo.getAllFilepaths)
        if ok and type(paths) == "table" then return paths end
    end
    return base_files()
end

local base_libmeta = H.libraryMeta
--- fp -> Bookshelf's light record, looked up as each book is asked for.
function H.libraryMeta()
    local Repo = repo()
    if not (Repo and Repo.lightMetaFor) then return base_libmeta() end
    return setmetatable({}, { __index = function(t, fp)
        local ok, m = pcall(Repo.lightMetaFor, fp)
        local v = ok and type(m) == "table" and m or false
        rawset(t, fp, v)
        return v or nil
    end })
end

-- ─── quote of the day ────────────────────────────────────────────────────────

local function quotes()
    local Q = try("lib/bookshelf_quotes")
    if type(Q) == "table" and Q.ofTheDay then return Q end
    return nil
end

local base_quote, base_reroll = H.quoteOfTheDay, H.rerollQuote
--- The day's first quote is the one Bookshelf's own Quote of the day card
--- shows. Another picks from your highlights here (host.lua): at random, and
--- never three in a row from one book. (Bookshelf's own picker steps to the
--- next highlight of the same book.)
function H.quoteOfTheDay()
    local today = os.date("%Y-%m-%d")
    local roll = A.get("quote_roll", nil)
    local first = type(roll) ~= "table" or roll.day ~= today or (tonumber(roll.n) or 0) == 0
    local Q = first and quotes() or nil
    if Q then
        local q = Q.ofTheDay()
        if q then
            -- its book and text, so Another keeps to the rules above
            local th = H.hash(tostring(q.text))
            if type(roll) ~= "table" or roll.day ~= today or roll.th ~= th then
                A.set("quote_roll", { day = today, n = 0, fp = q.filepath, hi = -1, th = th, streak = 1, shown = true })
            end
            return q
        end
    end
    return base_quote()
end

function H.rerollQuote() return base_reroll() end

-- ─── goals ───────────────────────────────────────────────────────────────────
-- Bookshelf's Reading goals settings, read and written under the same keys,
-- so changing a goal here or in its Reading goals card changes both.

local KEY_YEARLY = "micromodule_reading_goal_yearly"
local KEY_OTHER  = "micromodule_reading_goal_other_books"
local KEY_DAILY  = "micromodule_reading_goal_daily"

local function bsStore() return try("lib/bookshelf_settings_store") end

function H.yearGoal()
    local S = bsStore()
    local target, other = 24, 0
    if S then
        local ok, v = pcall(S.read, KEY_YEARLY, 24)
        if ok and tonumber(v) then target = max(1, floor(tonumber(v))) end
        local ok2, o = pcall(S.read, KEY_OTHER)
        if ok2 and type(o) == "table" and tonumber(o.year) == os.date("*t").year then
            other = max(0, floor(tonumber(o.n) or 0))
        end
    end
    return target, other
end

function H.setYearGoal(n)
    local S = bsStore()
    if S then pcall(S.save, KEY_YEARLY, floor(n)) end
end

function H.setOtherBooks(n)
    local S = bsStore()
    if S then pcall(S.save, KEY_OTHER, { year = os.date("*t").year, n = floor(n) }) end
end

function H.ownOtherBooks() return true end

function H.dailyMinutesGoal()
    local S = bsStore()
    if S then
        local ok, v = pcall(S.read, KEY_DAILY, 30)
        if ok and tonumber(v) then return max(1, floor(tonumber(v))) end
    end
    return 30
end

function H.setDailyMinutesGoal(minutes)
    local S = bsStore()
    if S then pcall(S.save, KEY_DAILY, floor(minutes)) end
end

-- How the goal settings describe themselves, and their limits.
H.GOALS = {
    year_max = 1000, daily_max = 1440,
    year_note = T("Shared with Bookshelf's Reading goals card."),
    daily_note = T("Shared with Bookshelf's Reading goals card."),
}

-- ─── opening books ───────────────────────────────────────────────────────────
-- Bookshelf 6.0.2 hands every module ctx.open_book and ctx.show_book; an older
-- Bookshelf only has its shelf's own ways, which are used then.

function H.openBook(ctx, fp)
    if type(ctx) == "table" and type(ctx.open_book) == "function" then
        if pcall(ctx.open_book, fp) then return end
    end
    local bw = type(ctx) == "table" and ctx.bw or nil
    if bw and type(bw._openBook) == "function" then
        if pcall(bw._openBook, bw, { filepath = fp }) then return end
    end
    require("apps/reader/readerui"):showReader(fp)
end

function H.showDetails(ctx, fp)
    if type(ctx) == "table" and type(ctx.show_book) == "function" then
        if pcall(ctx.show_book, fp) then return end
    end
    local bw = type(ctx) == "table" and ctx.bw or nil
    local Repo = repo()
    if bw and type(bw._showBookDetail) == "function" and Repo and Repo.buildBook then
        local ok, book = pcall(Repo.buildBook, fp)
        if ok and book and pcall(bw._showBookDetail, bw, book) then return end
    end
    A.D.openBook(ctx, fp)
end

-- ─── tap actions ─────────────────────────────────────────────────────────────
-- Buttons and taps use Bookshelf's action chooser (settings.lua), not Simple
-- UI's Quick Actions.

function H.quickActions() return {} end
function H.runQuickAction() return false end

--- Bookshelf's action chooser, when it has one: rows for a dialog that end
--- in on_pick(fields).
function H.actionRows(close, on_pick)
    local Chooser = try("lib/bookshelf_action_chooser")
    if not (type(Chooser) == "table" and Chooser.actionRows) then return nil end
    local ok, rows = pcall(Chooser.actionRows, close, on_pick)
    return ok and type(rows) == "table" and rows or nil
end

--- Bookshelf's icon library, when it has one: shows it, calls on_pick(icon)
--- (nil when nothing was picked). Returns false when there is none.
function H.pickIcon(on_pick)
    local Lib = try("lib/bookshelf_icons_library")
    if not (Lib and Lib.show) then return false end
    Lib:show(function(value)
        on_pick((value and value ~= "") and value or nil)
    end, { dynamic = false, svg = false })
    return true
end

-- ─── redraws ─────────────────────────────────────────────────────────────────

--- Redraw the card a settings dialog belongs to.
function H.repaint(ctx)
    if type(ctx) == "table" and ctx.menu and ctx.menu._reload then pcall(ctx.menu._reload, ctx.menu) end
end

--- Redraw every card (a theme or accent changed): in the top panel or the
--- full-screen view that means rebuilding them; the start menu's own reload
--- already redraws the whole menu.
function H.redrawAll(ctx)
    if type(ctx) ~= "table" then return end
    local bw = ctx.bw
    if bw and (ctx.surface == "hero" or ctx.surface == "fullscreen") then
        local HeroModules = try("lib/bookshelf_hero_modules")
        if HeroModules and HeroModules._rebuild and pcall(HeroModules._rebuild, bw) then return end
    end
    H.repaint(ctx)
end

-- Bookshelf's own refresh drives the clock (bookshelf.lua): no tick here.
function H.scheduleTick() end
function H.wantTick() end
function H.stopTick() end

return H
