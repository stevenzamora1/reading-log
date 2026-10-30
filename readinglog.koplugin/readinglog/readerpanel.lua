--[[
Reading Log's reader panel: shown under the reader's top menu (the row of
tab icons) when the menu opens, instead of the first tab's list. Off until
it is switched on in Tools > Reading Log > Reader panel. Kept small:

  the book     its cover, title and author, then two lines of figures:
               "Page 71/607 · 12% · 02:45 left · 50 m in book · 3 days of
               reading" and "1 page today · 2 m read today · 5-day streak"
               (in the rings' colours when the rings are shown), and a thin
               progress bar; today's rings at the right
  week         this week's rings, in a short row (off as it comes)
  buttons      tiles in the Reading Log style (plain, cute, cyber or dark
               academia) for any KOReader action, each with a glyph,
               one of KOReader's icons or a picture of your own

Each part can be switched off. Tap the open tab to come back to the panel
from a tab's list, and the arrow at the bottom closes the menu as always.

Fast: it never reads the whole statistics database. Today's figures are one
small query plus what the statistics plugin holds in memory and has not
saved yet; the streak and the week come from the figures already worked out
for the cards, with today put in.

The way into KOReader's menu (starting it on a panel of its own, and
tapping the open tab to come back) follows xusoo's Shortcuts Toolbar
plugin (MIT).
]]

local A = ...
local T = A._
local D = A.D
local RP = {}

local floor, max, min = math.floor, math.max, math.min

local GL = A.S.ICONS
local SLIDERS = "\xEF\x87\x9E"
local EXIT = "\xEF\x82\x8B"
RP.EXTRA_ICONS = { sliders = SLIDERS, exit = EXIT }

-- KOReader's own icons offered for a button (from its icon folder), and
-- any in koreader/icons, where your own can go.
RP.KO_ICONS = { "bookmark", "wifi", "home", "book.opened", "star.full", "star.empty", "info", "edit", "exit",
    "check", "plus", "appbar.navigation", "appbar.typeset", "appbar.settings", "appbar.tools", "appbar.search",
    "appbar.filebrowser", "appbar.menu", "appbar.contrast", "appbar.textsize", "appbar.rotation",
    "appbar.pageview", "appbar.pagefit", "appbar.crop", "appbar.pokeball", "dogear.reading", "notice-info",
    "notice-question", "column.two", "zoom.page", "triangle", "texture-box" }

-- What it shows as it comes, once it is switched on.
RP.PARTS = {
    { key = "book", label = T("The book and its progress"), on = true },
    { key = "today", label = T("Today: pages, time and streak"), on = true },
    { key = "thisbook", label = T("This book: days and time"), on = true },
    { key = "rings", label = T("Activity rings"), on = true },
    { key = "week", label = T("Week rings"), on = false },
}
local PART_ON = {}
for _, p in ipairs(RP.PARTS) do PART_ON[p.key] = p.on end

function RP.enabled() return A.get("panel_on", false) == true end
function RP.setEnabled(v) A.set("panel_on", v and true or nil) end

function RP.partOn(key)
    local v = A.get("panel_" .. key, nil)
    if v == nil then return PART_ON[key] and true or false end
    return v and true or false
end
function RP.setPart(key, v)
    if v == (PART_ON[key] and true or false) then v = nil end
    A.set("panel_" .. key, v)
end

-- ─── the buttons ─────────────────────────────────────────────────────────────
-- Each { icon = glyph, image = picture path (an icon of KOReader's, or your
-- own PNG, JPEG or SVG), action = KOReader's action table }: the action is
-- what a gesture runs, so it can be anything KOReader or a plugin offers.

-- the first three are shown as they come; the rest wait for "How many"
RP.DEFAULT_BUTTONS = {
    { icon = GL.wifi, action = { toggle_wifi = true } },
    { icon = GL.bookmark, action = { bookmarks = true } },
    { icon = GL.sun, action = { show_frontlight_dialog = true } },
    { icon = GL.night, action = { night_mode = true } },
    { icon = SLIDERS, action = { show_config_menu = true } },
    { icon = GL.search, action = { toc = true } },
    { icon = GL.chart, action = { book_statistics = true } },
    { icon = GL.power, action = { suspend = true } },
}
RP.MAX_BUTTONS = 8
RP.DEFAULT_COUNT = 3

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

function RP.buttonCount()
    return A.clamp(floor(tonumber(A.get("panel_button_count", RP.DEFAULT_COUNT)) or RP.DEFAULT_COUNT), 0, RP.MAX_BUTTONS)
end
function RP.setButtonCount(n)
    A.set("panel_button_count", n ~= RP.DEFAULT_COUNT and n or nil)
end

local function defaultButton(i)
    local d = RP.DEFAULT_BUTTONS[i]
    return d and { icon = d.icon, action = copy(d.action) } or { icon = GL.puzzle, action = {} }
end

--- The buttons shown, in order.
function RP.buttons()
    local saved = A.get("panel_buttons", nil)
    local out = {}
    for i = 1, RP.buttonCount() do
        local e = type(saved) == "table" and saved[i] or nil
        if type(e) ~= "table" or type(e.action) ~= "table" then e = defaultButton(i) end
        out[i] = e
    end
    return out
end

--- All eight, filled in, as the table kept in the settings (changed in place
--- by KOReader's action chooser; RP.saveButtons writes it out). Once whole,
--- always the same table, so a menu holding an entry stays right.
function RP.editableButtons()
    local saved = A.get("panel_buttons", nil)
    local whole = type(saved) == "table"
    if whole then
        for i = 1, RP.MAX_BUTTONS do
            if type(saved[i]) ~= "table" or type(saved[i].action) ~= "table" then whole = false break end
        end
    end
    if whole then return saved end
    local list = {}
    for i = 1, RP.MAX_BUTTONS do
        local e = type(saved) == "table" and saved[i] or nil
        if type(e) ~= "table" or type(e.action) ~= "table" then e = defaultButton(i) end
        list[i] = e
    end
    A.set("panel_buttons", list)
    return list
end

function RP.saveButtons(list) A.set("panel_buttons", list or A.get("panel_buttons", nil)) end

function RP.resetButton(i)
    local list = RP.editableButtons()
    local d = defaultButton(i)
    -- in place, so a menu holding this entry stays right
    list[i].icon, list[i].action, list[i].image = d.icon, d.action, nil
    RP.saveButtons(list)
end

--- A button's name: what KOReader calls its action.
function RP.buttonName(e)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and Dispatcher and Dispatcher.menuTextFunc and type(e) == "table" and type(e.action) == "table" then
        local ok2, txt = pcall(Dispatcher.menuTextFunc, Dispatcher, e.action)
        if ok2 and type(txt) == "string" and txt ~= "" then return txt end
    end
    return T("Nothing")
end

--- Where KOReader keeps the icon called `name` (your own icons first).
function RP.koIconPath(name)
    local lfs = require("libs/libkoreader-lfs")
    local ok, DataStorage = pcall(require, "datastorage")
    local dirs = { ok and (DataStorage:getDataDir() .. "/icons") or nil, "resources/icons/mdlight", "resources/icons" }
    for _, dir in ipairs(dirs) do
        for _, ext in ipairs({ ".svg", ".png" }) do
            local p = dir .. "/" .. name .. ext
            if lfs.attributes(p, "mode") == "file" then return p end
        end
    end
    return nil
end

--- The icons in koreader/icons (your own), by name.
function RP.ownIcons()
    local out = {}
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local dir = require("datastorage"):getDataDir() .. "/icons"
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        for f in lfs.dir(dir) do
            local name = f:match("^(.+)%.svg$") or f:match("^(.+)%.png$")
            if name then out[#out + 1] = name end
        end
        table.sort(out)
    end)
    return out
end

-- Actions that change something in place: the panel stays open and shows
-- the new state. Anything else closes the menu first.
local IN_PLACE = { toggle_wifi = true, night_mode = true, toggle_frontlight = true, toggle_bookmark = true,
    show_frontlight_dialog = true }

local function onlyInPlace(action)
    local any = false
    for k in pairs(action or {}) do
        if k ~= "settings" then
            any = true
            if not IN_PLACE[k] then return false end
        end
    end
    return any
end

local function isOn(action)
    local id
    for k in pairs(action or {}) do if k ~= "settings" then if id then return false end id = k end end
    if not id then return false end
    return D.toggleState({ action = { [id] = true } }) == true
end

-- ─── the reader, its book and its figures ────────────────────────────────────

local function readerUI()
    local RUI = package.loaded["apps/reader/readerui"]
    local ui = RUI and RUI.instance
    if ui and ui.document and not ui.tearing_down then return ui end
    return nil
end
RP.readerUI = readerUI

local function bookFacts(ui)
    local props = ui.doc_props or {}
    local out = {
        fp = ui.document and ui.document.file,
        title = props.display_title or props.title or "",
        author = props.authors,
    }
    if type(out.author) == "string" then out.author = out.author:gsub("\n", ", ") end
    local ok = pcall(function()
        local cur = ui.getCurrentPage and ui:getCurrentPage() or 0
        local label_cur, label_last, pct
        if ui.pagemap and ui.pagemap:wantsPageLabels() then
            local lc, idx, count = ui.pagemap:getCurrentPageLabel(false)
            label_cur, label_last = lc, ui.pagemap:getLastPageLabel(true)
            pct = (count and count > 0) and idx / count or 0
        else
            local total = ui.document:getPageCount() or 0
            label_cur, label_last = cur, total
            pct = total > 0 and cur / total or 0
        end
        out.page, out.pages, out.pct = label_cur, label_last, A.clamp(pct, 0, 1)
        local left = ui.document.getTotalPagesLeft and ui.document:getTotalPagesLeft(cur)
        if ui.statistics and left and left > 0 and ui.statistics.getTimeForPages then
            out.left = ui.statistics:getTimeForPages(left)
        end
    end)
    if not ok then out.pct = 0 end
    return out
end

local function dayStart()
    local t = os.date("*t")
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
end

-- What the statistics plugin has noted but not saved yet (it saves now and
-- then): pages and seconds since `since`, and every second of it.
local function unsaved(stats, since)
    local pages, secs, all = 0, 0, 0
    local ps = stats and stats.page_stat
    if type(ps) ~= "table" then return 0, 0, 0 end
    for _, list in pairs(ps) do
        local counted = false
        if type(list) == "table" then
            for _, tup in ipairs(list) do
                local ts, dur = tonumber(tup[1]), tonumber(tup[2])
                if ts and dur and dur > 0 then
                    all = all + dur
                    if ts >= since then
                        secs = secs + dur
                        if not counted then pages, counted = pages + 1, true end
                    end
                end
            end
        end
    end
    return pages, secs, all
end
RP._unsaved = unsaved

-- Today's pages and seconds, and this book's days and seconds, from the
-- database: two small queries (the second by the book's own index).
local function saved(id_book, since)
    local out = { pages = 0, secs = 0 }
    pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local DataStorage = require("datastorage")
        local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3", "ro")
        pcall(function()
            conn:exec("PRAGMA busy_timeout=200;")
            local function today(tbl)
                return conn:rowexec(string.format("SELECT count(*), sum(s) FROM (SELECT sum(duration) AS s FROM %s"
                    .. " WHERE start_time >= %d GROUP BY id_book, page);", tbl, since))
            end
            local ok, p, s = pcall(today, "page_stat")
            if not ok then ok, p, s = pcall(today, "page_stat_data") end
            if ok then out.pages, out.secs = tonumber(p) or 0, tonumber(s) or 0 end
            if id_book then
                local d, bs, last = conn:rowexec(string.format(
                    "SELECT count(DISTINCT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime')),"
                    .. " sum(duration), max(start_time) FROM page_stat_data WHERE id_book = %d;", tonumber(id_book) or -1))
                out.book_days, out.book_secs, out.book_last = tonumber(d) or 0, tonumber(bs) or 0, tonumber(last) or 0
            end
        end)
        conn:close()
    end)
    return out
end

--- The panel's figures: today's pages, seconds and streak, this book's
--- days and seconds, and the reading figures with today put in (for the
--- rings). Never reads the whole database (see the top of the file).
function RP.figures(ui)
    local since = dayStart()
    local stats = ui.statistics
    local un_pages, un_secs, un_all = unsaved(stats, since)
    local db = saved(stats and stats.id_curr_book, since)
    local f = {
        pages = db.pages + un_pages, secs = db.secs + un_secs,
        book_secs = db.book_secs and (db.book_secs + un_all) or nil,
        book_days = db.book_days,
    }
    -- read today, and the database has nothing of today for this book yet
    if f.book_days and un_secs > 0 and (db.book_last or 0) < since then f.book_days = f.book_days + 1 end
    -- the streak and the week as the cards last worked them out (read once
    -- now if nothing has yet), with today's figures put in
    local st = D.statsCached() or D.stats(nil, true)
    if type(st) ~= "table" then st = nil end
    local streak = st and st.streak or 0
    local cached_today = st and st.today and st.today.pages or 0
    if f.pages > 0 and cached_today == 0 then streak = streak + 1 end
    f.streak = streak
    if st then
        local s2 = {}
        for k, v in pairs(st) do s2[k] = v end
        s2.today = { pages = f.pages, secs = f.secs }
        s2.streak = streak
        local week = {}
        for i, d in ipairs(st.week or {}) do
            local d2 = {}
            for k, v in pairs(d) do d2[k] = v end
            if d2.today then d2.pages, d2.secs = f.pages, f.secs end
            week[i] = d2
        end
        s2.week = week
        local wp, wsx = 0, 0
        for _, d in ipairs(week) do wp, wsx = wp + (d.pages or 0), wsx + (d.secs or 0) end
        s2.week_pages, s2.week_secs = wp, wsx
        f.stats = s2
    end
    return f
end

-- The colours: the reader's menu is always white (and the screen is turned
-- over at night), so the panel takes it as its page, as a card on its own
-- takes the home screen's; the accents are the theme's.
local function panelTone()
    local real = A.pageColors
    A.pageColors = function() return { 255, 255, 255 }, { 0, 0, 0 } end
    local ok, tone = pcall(A.nativeTone, "ink")
    A.pageColors = real
    return ok and tone or A.tone("ink")
end

-- Which look the buttons take: the Reading Log style in use.
local function buttonLook()
    local CY = A.cutTheme()
    if CY then return "cyber", CY end
    local AC = A.academiaTheme()
    if AC then return "academia", AC end
    if A.styleNow() == "cute" then return "cute" end
    return "plain"
end

local PASTELS = { { 126, 206, 176 }, { 178, 156, 228 }, { 246, 168, 132 }, { 126, 186, 232 } }

-- One button's tile at (x, y), size x size; returns the colour its icon takes.
local function tile(c, look, kit, x, y, w, h, i, on, tone, px)
    if look == "cyber" then
        local cut = floor(min(w, h) * 0.28)
        if on then
            kit.cutRect(c, x, y, w, h, cut, tone.accent)
            return { 0, 0, 0 }
        end
        kit.cutFrame(c, x, y, w, h, cut, max(1, px(2)), tone.accent2, tone.bg)
        return tone.accent2
    elseif look == "academia" then
        local br = A.ACCENTS.brass and A.ACCENTS.brass.deep or { 140, 104, 40 }
        c:rect(x, y, w, h, on and A.mix(tone.bg, br, 0.35) or tone.bg)
        c:frame(x, y, w, h, 0, max(1, px(2)), br, on and A.mix(tone.bg, br, 0.35) or tone.bg)
        c:frame(x + max(2, px(4)), y + max(2, px(4)), w - 2 * max(2, px(4)), h - 2 * max(2, px(4)), 0, 1,
            A.mix(tone.bg, br, 0.6), on and A.mix(tone.bg, br, 0.35) or tone.bg)
        return tone.fg
    elseif look == "cute" then
        local pastel = PASTELS[(i - 1) % #PASTELS + 1]
        local fill = on and A.mix(tone.bg, { 236, 110, 160 }, 0.55) or A.mix(tone.bg, pastel, 0.3)
        c:rrect(x, y, w, h, min(w, h) / 2, fill)
        return A.mix(pastel, { 0, 0, 0 }, 0.6)
    end
    -- plain: a soft rounded tile, the accent while it's on (as the Control centre)
    c:rrect(x, y, w, h, floor(min(w, h) * 0.28), on and tone.btn or A.mix(tone.bg, tone.fg, 0.08))
    return on and tone.btn_fg or tone.fg
end

-- An icon in the box: a picture (your own, or one of KOReader's) or a glyph.
-- KOReader's icons (and any in an icons folder) are black drawings: they
-- take the button's icon colour, like the glyphs.
local function isIcon(path)
    return path:find("resources/icons/", 1, true) ~= nil or path:find("/icons/", 1, true) ~= nil
end
local function icon(c, e, cx, cy, size, col, fpx)
    if e.image and c:image(e.image, cx - size / 2, cy - size / 2, size, size, isIcon(e.image) and { tint = col } or nil) then
        return
    end
    local g = c:text(e.icon or GL.puzzle, fpx(22), { symbol = true, color = col })
    if g.w > size then g = c:text(e.icon or GL.puzzle, max(8, floor(fpx(22) * size / g.w)), { symbol = true, color = col }) end
    c:put(g, cx, cy, "c", "mid")
end

--- The panel as a canvas, w wide; nil when no book is open.
function RP.canvas(w, o)
    o = o or {}
    local ui = o.ui or readerUI()
    if not ui then return nil end
    local Screen = A.screen()
    local s = Screen:scaleBySize(1000) / 1000
    local px, fpx = A.panelScaler(s, 1)
    local tone = panelTone()
    local pad = px(14)
    local gap = px(10)
    local iw = w - 2 * pad

    local show_book, show_today, show_this = RP.partOn("book"), RP.partOn("today"), RP.partOn("thisbook")
    local show_rings, show_week = RP.partOn("rings"), RP.partOn("week")
    local book = show_book and bookFacts(ui) or nil
    local fig = (show_today or show_this or show_rings or show_week) and RP.figures(ui) or {}
    local env = { w = w, h = 0, tone = tone, ts = 1, sample = false, stats = fig.stats,
        cfg = function(_, d) return d end }

    -- two lines of figures: the book's, then today's (in the rings' colours
    -- when the rings are beside them, so each figure matches its ring)
    local top, low = {}, {}
    if book then
        if book.page then top[#top + 1] = { A.tr("Page %1/%2", book.page, book.pages) } end
        top[#top + 1] = { floor((book.pct or 0) * 100 + 0.5) .. "%" }
        if book.left then top[#top + 1] = { A.tr("%1 left", book.left) } end
    end
    if show_this and fig.book_days then
        top[#top + 1] = { A.tr("%1 in book", A.fmtMinutes((fig.book_secs or 0) / 60)) }
        top[#top + 1] = { A.tr("%1 of reading", A.plural(fig.book_days, "day", "days")) }
    end
    if show_today then
        local cols = show_rings and A.ringColors(tone) or {}
        low[1] = { A.tr("%1 today", A.plural(fig.pages or 0, "page", "pages")), cols[1] }
        low[2] = { A.tr("%1 read today", A.fmtMinutes((fig.secs or 0) / 60)), cols[2] }
        low[3] = { A.tr("%1-day streak", fig.streak or 0), cols[3] }
    end

    -- the cover's own space, the rings' at the right, the text between
    local cov_w, cov_h = px(60), px(90)
    local ring_d = show_rings and px(86) or 0
    local tx = pad + (book and (cov_w + px(14)) or 0)
    local room = w - pad - tx - (show_rings and (ring_d + px(14)) or 0)
    -- the open book's cover: from the reader itself when no cache has it
    if book and book.fp and not D.cover(book.fp, cov_w, cov_h) then
        local okc, bb = pcall(function() return ui.bookinfo:getCoverImage(ui.document) end)
        if okc and bb then D.seedCover(book.fp, bb) end
    end

    -- the figures flow left to right with a dot between them, a line of
    -- their own each, and on to the next row only when the room runs out
    local fig_px = fpx(14)
    local SEP = " \xC2\xB7 "
    local function flow(cv, parts, x0, y0, draw)
        if #parts == 0 then return 0 end
        local sep = cv:text(SEP, fig_px, { color = tone.label })
        local x, y, row_h = x0, y0, 0
        for i, p in ipairs(parts) do
            local t = cv:text(p[1], fig_px, { color = p[2] or tone.label, bold = p[2] and true or nil, max_w = room })
            row_h = max(row_h, t.h)
            local need = (i > 1 and sep.w or 0) + t.w
            if i > 1 and x + need > x0 + room then
                x, y = x0, y + row_h
            elseif i > 1 then
                if draw then cv:put(sep, x, y) end
                x = x + sep.w
            end
            if draw then cv:put(t, x, y) end
            x = x + t.w
        end
        return y + row_h - y0
    end

    -- measure, then lay out: the top row, the week, the buttons
    local probe = A.canvas{ w = 10, h = 10, tone = tone, plain = true }
    local text_h = 0
    if book then
        text_h = probe:textbox(book.title, fpx(19), room, 2, { bold = true }).h + px(2)
        if book.author and book.author ~= "" then text_h = text_h + probe:text(book.author, fpx(15)).h + px(2) end
    end
    -- each line on one row: a little smaller type when one is too long
    -- (down to about four fifths), then on to a second row
    local function lineW(parts)
        if #parts == 0 then return 0 end
        local wsum = probe:text(SEP, fig_px).w * (#parts - 1)
        for _, p in ipairs(parts) do wsum = wsum + probe:text(p[1], fig_px, { bold = p[2] and true or nil }).w end
        return wsum
    end
    local widest = max(lineW(top), lineW(low))
    if widest > room then fig_px = max(A.minFont(), floor(fig_px * max(0.78, room / widest))) end
    local top_lh, low_lh = flow(probe, top, 0, 0, false), flow(probe, low, 0, 0, false)
    if top_lh > 0 then text_h = text_h + top_lh + px(1) end
    if low_lh > 0 then text_h = text_h + low_lh + px(1) end
    if top_lh + low_lh > 0 then text_h = text_h + px(3) end
    if book then text_h = text_h + px(6) + max(3, px(5)) end
    probe:free()
    local top_h = max(book and cov_h or 0, text_h, ring_d)
    -- (the week's rings twice the row's first size)
    local week_h = show_week and px(80) or 0
    local buttons = RP.buttons()
    local bd = px(42)
    local row_h = #buttons > 0 and bd or 0
    local H = px(10) + top_h
    if week_h > 0 then H = H + gap + week_h end
    if row_h > 0 then H = H + gap + row_h end
    H = H + px(8)

    local c = A.canvas{ w = w, h = H, tone = tone, plain = true }
    local y = px(10)
    -- the top row
    if top_h > 0 then
        if book then
            c:cover(book.fp, pad, y, cov_w, cov_h, { title = book.title, edge = tone.track })
        end
        local yy = y + max(0, floor((top_h - text_h) / 2))
        if book then
            local t_title = c:textbox(book.title, fpx(19), room, 2, { bold = true, color = tone.fg })
            c:put(t_title, tx, yy); yy = yy + t_title.h + px(2)
            if book.author and book.author ~= "" then
                local t_a = c:text(book.author, fpx(15), { color = tone.fg, max_w = room })
                c:put(t_a, tx, yy); yy = yy + t_a.h + px(2)
            end
        end
        if top_lh > 0 then yy = yy + flow(c, top, tx, yy, true) + px(1) end
        if low_lh > 0 then yy = yy + flow(c, low, tx, yy, true) + px(1) end
        if top_lh + low_lh > 0 then yy = yy + px(3) end
        if book then
            local bar_h = max(3, px(5))
            yy = yy + px(2)
            local bw = min(room, px(520))
            c:rrect(tx, yy, bw, bar_h, bar_h / 2, tone.track)
            local fw = floor(bw * (book.pct or 0))
            if fw > 0 then c:rrect(tx, yy, max(bar_h, fw), bar_h, bar_h / 2, tone.accent) end
            c:region("book", pad, y, tx + room - pad, top_h)
        end
        if show_rings then
            local rx = w - pad - ring_d
            A.miniTile("rings", c, env, rx, y + floor((top_h - ring_d) / 2), ring_d, ring_d, px, fpx, tone)
        end
        y = y + top_h + gap
    end
    if week_h > 0 then
        A.miniTile("weekrow", c, env, pad, y, min(iw, px(700)), week_h, px, fpx, tone)
        y = y + week_h + gap
    end
    if row_h > 0 then
        local look, kit = buttonLook()
        local x = pad
        local room_b = iw
        local step = bd + px(10)
        local n = min(#buttons, max(0, floor((room_b + px(10)) / step)))
        for i = 1, n do
            local e = buttons[i]
            local bx = x + (i - 1) * step
            local col = tile(c, look, kit, bx, y, bd, bd, i, isOn(e.action), tone, px)
            icon(c, e, bx + bd / 2, y + bd / 2, floor(bd * 0.56), col, fpx)
            c:region("btn:" .. i, bx - px(5), y, step, bd)
        end
    end
    return c
end

-- ─── taps ────────────────────────────────────────────────────────────────────

local function hitRegion(regions, x, y)
    for _, r in ipairs(regions or {}) do
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r.id end
    end
    return nil
end

local function closeMenu(menu)
    if menu and menu.close_callback then pcall(menu.close_callback) end
end

-- Runs a KOReader action. KOReader sends an action's event to the window on
-- top; with the menu still open that's the menu, which doesn't take it, and
-- the reader under it only hears events while it says it's always
-- listening. So, for the length of the call, it says so.
local function dispatch(action)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not (ok and Dispatcher and type(action) == "table") then return end
    local ui = readerUI()
    local was = ui and ui.is_always_active
    if ui then ui.is_always_active = true end
    local ok2, err = pcall(Dispatcher.execute, Dispatcher, action)
    if ui then ui.is_always_active = was end
    if not ok2 then A.log("reader panel action failed:", err) end
end

local function broadcast(name)
    pcall(function()
        local Event = require("ui/event")
        require("ui/uimanager"):broadcastEvent(Event:new(name))
    end)
end

-- What a tap on `region` does, with the menu it is in.
function RP.tap(menu, region, refresh)
    if region == "book" then
        closeMenu(menu)
        broadcast("ShowBookStatus")
        return
    end
    if region == "rings:" then
        closeMenu(menu)
        dispatch({ reading_progress = true })
        return
    end
    if region == "week:" then
        closeMenu(menu)
        dispatch({ stats_calendar_view = true })
        return
    end
    local i = type(region) == "string" and tonumber(region:match("^btn:(%d+)$"))
    local e = i and RP.buttons()[i]
    if not e then return end
    if onlyInPlace(e.action) then
        dispatch(e.action)
        -- show the new state once the action has run
        if refresh then require("ui/uimanager"):scheduleIn(0.8, function() pcall(refresh) end) end
    else
        closeMenu(menu)
        require("ui/uimanager"):nextTick(function() dispatch(e.action) end)
    end
end

--- What a long-press on `region` does: a button says what it runs.
function RP.hold(region)
    local i = type(region) == "string" and tonumber(region:match("^btn:(%d+)$"))
    local e = i and RP.buttons()[i]
    local text = e and RP.buttonName(e) or nil
    if text then
        local InfoMessage = require("ui/widget/infomessage")
        require("ui/uimanager"):show(InfoMessage:new{ text = text, timeout = 2 })
    end
end

--- The panel as a widget for the menu: the canvas, taking taps and holds.
function RP.widget(menu, w, refresh)
    local c = RP.canvas(w)
    if not c then return nil end
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local Geom = require("ui/geometry")
    local box = InputContainer:new{ dimen = Geom:new{ w = c.w, h = c.h }, c }
    box.is_readinglog_panel = true
    box.ges_events = {
        TapReadingLogPanel = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } },
        HoldReadingLogPanel = { GestureRange:new{ ges = "hold", range = function() return box.dimen end } },
    }
    local function regionAt(ges)
        local d = box.dimen
        if not (ges and ges.pos and d and d.x) then return nil end
        return hitRegion(c.regions, ges.pos.x - d.x, ges.pos.y - d.y)
    end
    function box:onTapReadingLogPanel(_, ges)
        local region = regionAt(ges)
        local ok, err = pcall(RP.tap, menu, region, refresh)
        if not ok then A.log("reader panel tap failed:", err) end
        return true
    end
    function box:onHoldReadingLogPanel(_, ges)
        pcall(RP.hold, regionAt(ges))
        return true
    end
    return box
end

-- ─── in KOReader's menu ──────────────────────────────────────────────────────

-- The reader's top menu (it has the reader's own tabs).
local function isReaderMenu(menu)
    if not readerUI() or type(menu.tab_item_table) ~= "table" then return false end
    for _, tab in ipairs(menu.tab_item_table) do
        if tab.icon == "appbar.navigation" or tab.icon == "appbar.typeset" then return true end
    end
    return false
end
RP.isReaderMenu = isReaderMenu

-- No tab looks open while the panel shows.
local function clearTabs(menu)
    local bar = menu.bar
    if not bar then return end
    if bar.bar_sep then bar.bar_sep.empty_segments = nil end
    for _, sep in ipairs(bar.icon_seps or {}) do sep.style = "none" end
end

--- Put the panel in the menu in place of a tab's list. fresh = while the
--- menu is being made (it is painted when shown).
function RP.show(menu, fresh)
    if not (menu.item_group and menu.bar) then return false end
    local width = menu.item_width or (menu.width - 2 * (menu.padding or 0))
    local panel = RP.widget(menu, width, function()
        if menu._readinglog_panel then RP.show(menu) end
    end)
    if not panel then return false end
    local old = menu.dimen and menu.dimen:copy()
    menu._readinglog_panel = true
    menu.item_group:clear()
    table.insert(menu.item_group, menu.bar)
    table.insert(menu.item_group, panel)
    if menu.footer_top_margin then table.insert(menu.item_group, menu.footer_top_margin) end
    if menu.footer then table.insert(menu.item_group, menu.footer) end
    if menu.page_info_text then pcall(menu.page_info_text.setText, menu.page_info_text, "") end
    if menu.page_info_left_chev then pcall(menu.page_info_left_chev.hide, menu.page_info_left_chev) end
    if menu.page_info_right_chev then pcall(menu.page_info_right_chev.hide, menu.page_info_right_chev) end
    clearTabs(menu)
    -- the keys move between the tabs only
    if menu.bar.icon_widgets then menu.layout = { menu.bar.icon_widgets } end
    menu.item_group:resetLayout()
    if menu.dimen then
        menu.dimen.w = menu.width
        menu.dimen.h = menu.item_group:getSize().h + (menu.bordersize or 0) * 2 + (menu.padding or 0)
    end
    if not fresh then
        local UIManager = require("ui/uimanager")
        local region = old and menu.dimen and old:combine(menu.dimen) or nil
        UIManager:setDirty("all", function() return "ui", region end)
    end
    return true
end

return RP
