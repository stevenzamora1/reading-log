--[[
Reading Log modules: every panel as a Simple UI home screen module, and the
Dashboard, which lays several panels out as tabbed pages in one module.

What Simple UI asks of a module (see its modules/moduleregistry.lua):
  M.id, M.name                 stable id, the name in its module lists
  M.build(w, ctx)              a widget w wide; its height is the module's
  M.getHeight(ctx)             that height, without building
  M.getMenuItems(ctx_menu)     the long-press settings
  M.enabled_key, M.default_on  placed on a page (its layout editor sets it)
and, used here:
  M.is_book_mod                Simple UI keeps a slot for the module, so one
                               card can be redrawn in place (a tap, a
                               background read landing, the clock)
  M.has_covers, updateCovers   covers still being extracted are drawn in when
                               they land; also asks e-ink for colour
  M.owns_chrome                Simple UI leaves the module's box to it: the
                               Dashboard paints its own page, and a card puts
                               itself in Simple UI's box or goes without

A card here is the same Canvas the Bookshelf version drew. Its tap regions
(the Continue button, a cover, a month bar, a tab) are hit-tested by the
InputContainer around it; a long-press is left to Simple UI (module settings).
]]

local A = ...
local T = A._
local D = A.D
local P = A.panels
local S = A.S
local H = A.host

local floor, max, min = math.floor, math.max, math.min

-- Text is always drawn at what used to be the "Largest" setting: easier to
-- read on e-ink, and one setting fewer.
A.TEXT_SCALE = 1.25
local function textScale() return A.TEXT_SCALE end

A.ID_PREFIX = "readinglog_"

-- ─── per-card context ────────────────────────────────────────────────────────
-- A "ctx" here is what the panels and settings were written against:
--   width, height        the box
--   config               per-card config (which saved set a slotted card shows)
--   entry.id             the card's id
--   refresh              redraw this card (a background read landed)
--   set_tap_regions      where the card's buttons are
--   tapped_region        during a tap: which one was hit
-- plus, here: sui (Simple UI's screen ctx), screen, mod_id, pfx; and in a
-- settings menu, menu_refresh.

local NOSCREEN = {}
local _latest = setmetatable({}, { __mode = "k" })     -- screen -> { [mod_id] = ctx }
local _refreshers = setmetatable({}, { __mode = "k" }) -- screen -> { [mod_id] = fn }

local function latestCtx(screen, id)
    local per = _latest[screen or NOSCREEN]
    return per and per[id]
end
A.latestCtx = latestCtx

-- One function per card and screen, for as long as the screen lives: the data
-- layer drops repeat redraw requests by comparing functions.
local function refresherFor(screen, id)
    local key = screen or NOSCREEN
    local per = _refreshers[key]
    if not per then per = {}; _refreshers[key] = per end
    local fn = per[id]
    if not fn then
        fn = function()
            local ctx = latestCtx(key, id)
            if ctx then H.repaint(ctx) end
        end
        per[id] = fn
    end
    return fn
end

-- Per-card settings that belong to one screen (the home screen and each
-- custom screen keep their own): which set a slotted card shows, its height.
local function screenKey(pfx, id, what)
    return what .. ":" .. (pfx or "simpleui_hs_") .. id
end
A.screenKey = screenKey

local function slotConfig(pfx, id)
    local key = screenKey(pfx, id, "slot")
    return {
        get = function(_, name, default)
            if name ~= "alm_slot" then return default end
            return A.get(key, default)
        end,
        set = function(_, name, value)
            if name == "alm_slot" then A.set(key, value) end
        end,
    }
end

-- The reader's Text size for a card on a screen, as a share (1 = normal).
A.TEXT_MIN, A.TEXT_MAX, A.TEXT_DEF = 70, 150, 100
function A.textSizePct(pfx, id)
    if not id then return A.TEXT_DEF end
    local v = tonumber(A.get(screenKey(pfx, id, "text"), A.TEXT_DEF)) or A.TEXT_DEF
    return A.clamp(floor(v), A.TEXT_MIN, A.TEXT_MAX)
end

local function cardCtx(id, sctx, w, h)
    local screen = type(sctx) == "table" and sctx._screen_widget or nil
    local pfx = type(sctx) == "table" and sctx.pfx or "simpleui_hs_"
    local ctx = {
        width = w, height = h,
        sui = sctx, screen = screen, mod_id = id, pfx = pfx,
        config = slotConfig(pfx, id),
        entry = { id = id },
        refresh = refresherFor(screen, id),
    }
    ctx.set_tap_regions = function(regions) ctx._regions = regions end
    local key = screen or NOSCREEN
    local per = _latest[key]
    if not per then per = {}; _latest[key] = per end
    per[id] = ctx
    return ctx
end

--- The ctx a card's settings menu works with: no screen of its own; changes
--- redraw through the menu (which also redraws the screen it was opened on).
function A.menuCtx(ctx_menu, id)
    local pfx = ctx_menu and ctx_menu.pfx or "simpleui_hs_"
    return {
        menu = ctx_menu, pfx = pfx, mod_id = id,
        config = slotConfig(pfx, id),
        entry = { id = id },
        menu_refresh = function()
            D.invalidate()
            if ctx_menu and type(ctx_menu.refresh) == "function" then pcall(ctx_menu.refresh) end
        end,
    }
end

-- Everything a panel builder or tap handler needs to know about where it is.
-- o = { nested = bool, slot = n, page = page colour }
local function makeEnv(name, ctx, w, h, o)
    o = o or {}
    local def = P[name]
    local slot = o.slot
    if not slot and ctx and ctx.config then
        local ok, v = pcall(ctx.config.get, ctx.config, "alm_slot", 1)
        slot = ok and tonumber(v) or 1
    end
    slot = A.clamp(floor(slot or 1), 1, 3)
    local prefix = name .. ((def.slots and slot > 1) and tostring(slot) or "") .. "_"
    local stored_tone = A.get(name .. "_tone", nil)
    local tone_name = stored_tone or def.tone
    -- On its own on a Simple UI screen a card takes Simple UI's look (see
    -- A.nativeTone); inside the Dashboard it keeps the theme's. Over a Simple
    -- UI wallpaper with this module's Background Opacity below Solid, a card
    -- on its own draws no background or frame of its own ("bare"): what is
    -- behind it is Simple UI's backdrop, as see-through as its Background
    -- Opacity says, and the wallpaper, like Simple UI's own modules.
    local alone_see = (not o.nested) and ctx and ctx.mod_id and not ctx.menu and H.seeThrough(ctx.pfx, ctx.mod_id) or false
    local native = (not o.nested) and A.standaloneNative()
    -- A tinted panel on a plain page would be a card in a card, so on their
    -- own the tinted cards start plain (unless picked by hand).
    if native and not stored_tone then
        tone_name = ({ tint = "ink", tint2 = "paper" })[A.toneKey(tone_name)] or tone_name
    end
    return {
        name = name, ctx = ctx, w = w, h = h, slot = slot,
        tone = native and A.nativeTone(tone_name) or A.tone(tone_name),
        ts = textScale() * A.textSizePct(ctx and ctx.pfx, ctx and ctx.mod_id) / 100,
        nested = o.nested or false,
        native = native,
        page = o.page,
        see = o.see or false,
        bare = alone_see,
        -- the card sits straight on a wallpaper: its corners blend with it
        behind = o.see and true or false,
        page_heading = o.page_heading or false,
        bleed = false,
        sample = false,
        refresh = ctx and ctx.refresh or nil,
        cfg = function(key, default) return A.get(prefix .. key, default) end,
        setcfg = function(key, value) A.set(prefix .. key, value) end,
    }
end
A.makeEnv = makeEnv

-- A small card naming what went wrong, in place of a panel that failed.
local function errorCard(name, w, h, err)
    A.log(name, "render failed:", err)
    local c = A.canvas{ w = w, h = h, tone = "ink", radius = 12 }
    local s = min(w / 500, h / 200)
    c:label((P[name] and P[name].title or name) .. T(" could not be drawn"), max(12, floor(22 * s)), w / 2, h / 2,
        { anchor = "c", valign = "mid", max_w = w - 20 })
    return c
end

local function buildPanel(name, env)
    local ok, c = pcall(P[name].build, env)
    if ok and c then return c end
    return errorCard(name, env.w, env.h, c)
end

local function declareRegions(ctx, c)
    A.state.regions_ok = true
    if ctx and ctx.set_tap_regions then pcall(ctx.set_tap_regions, c.regions) end
end

local function tapRegion(def, ctx)
    return ctx and ctx.tapped_region
end

-- A card that is already on screen is about to be redrawn (a tap changed it,
-- or the dashboard turned a page). flash = the whole card changes; turn = a
-- Dashboard page turn.
local function inkRefresh(ctx, flash, turn)
    H.repaint(ctx, { flash = flash, turn = turn })
end

-- A new page (a tab, or another month): the data the new page needs is
-- worked out before it is drawn, within a short time limit, so it shows up
-- whole in one go instead of in two steps; and it is put on screen with a
-- quick update rather than a flash (KOReader still flashes every so often,
-- by its own "Full refresh rate", to clear ghosting).
local function pageTurn(ctx)
    D.hurry(0.35)
    inkRefresh(ctx, false, true)
end

-- One flashing refresh of the whole screen, now. Clears whatever ghosting
-- has built up. (Tapping the clock does this; so does Diagnostics.)
function A.cleanScreen()
    pcall(function()
        A.count("cleans")
        require("ui/uimanager"):setDirty(nil, "full")
    end)
end

function A.refreshMode() return "clean" end

function A.render(name, ctx)
    local def = P[name]
    local w, h = floor(ctx.width), floor(ctx.height)
    local c = buildPanel(name, makeEnv(name, ctx, w, h))
    -- painted once and kept (see the paint cache in init.lua); not the
    -- clocks, which are a new picture every minute
    c.cache_me = not def.tick
    declareRegions(ctx, c)
    if def.tick then
        H.wantTick(ctx, { y = 0, h = c.h })
    elseif def.poll then
        -- checked once a minute, redrawn only when what it shows changed
        local ok, sig = pcall(def.poll)
        H.wantTick(ctx, nil, { check = def.poll, seen = ok and sig or nil })
    end
    return c
end

-- ─── what a tap does ─────────────────────────────────────────────────────────
-- A card can be set (settings > When tapped) to run something else instead of
-- its own action: the reading calendar, reading progress, or any of Simple
-- UI's Quick Actions. Stored as { label, action = { [dispatcher name] = true } }
-- or { label, qa = quick action id }. The card's real buttons (Continue,
-- Details, the pager, the tabs) keep their job.

function A.tapAction(name)
    local e = A.get(name .. "_tap_action", nil)
    if type(e) == "table" and (type(e.action) == "table" or type(e.qa) == "string") then
        return e
    end
    return nil
end

-- The custom action that a tap on `region` of card `name` should run, if any.
local function customTap(name, region)
    local def = P[name]
    if not def then return nil end
    if def.controls and def.controls(region) then return nil end
    return A.tapAction(name)
end
A.customTap = customTap

local function runTapAction(entry, ctx)
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        if type(entry.qa) == "string" then
            H.runQuickAction(ctx, entry.qa)
        elseif type(entry.action) == "table" then
            local okd, Dispatcher = pcall(require, "dispatcher")
            if okd and Dispatcher then
                local ok, err = pcall(Dispatcher.execute, Dispatcher, entry.action)
                if not ok then A.log("tap action failed:", err) end
            end
        end
    end)
end
A.runTapAction = runTapAction

function A.onTap(name, ctx)
    local def = P[name]
    local region = tapRegion(def, ctx)
    local custom = customTap(name, region)
    if custom then return runTapAction(custom, ctx) end
    if not def.tap then return end
    local ok, err = pcall(def.tap, makeEnv(name, ctx, 0, 0), region)
    if not ok then A.log(name, "tap failed:", err) end
    if def.keep and def.keep(region) then inkRefresh(ctx) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- Dashboard: several panels as tabbed pages in one module
-- ════════════════════════════════════════════════════════════════════════════
-- Laying the panels out here (instead of as separate modules) lets each row
-- have its own height and puts a tab bar underneath, in one module that fills
-- a Simple UI page.

-- The pages as they come. A row is one card, or two side by side.
A.DASH_PAGES = {
    { id = "today", label = T("Today"),
      rows = { { "banner" }, { "continue" }, { "activity", "week_rings" }, { "bookclub" } } },
    { id = "yearly", label = T("Yearly"), heading = true, kicker = "year",
      rows = { { "year_time", "longest_year" }, { "year_chart" }, { "year_covers" } } },
    { id = "monthly", label = T("Monthly"), heading = true, kicker = "month",
      rows = { { "month_rings", "month_totals" }, { "month_chart" }, { "when_read", "longest_month" } } },
    { id = "trends", label = T("Trends"), heading = true, kicker = "streak",
      rows = { { "challenge", "forecast" }, { "trends" } } },
    { id = "library", label = T("Library"), heading = true, kicker = "library",
      rows = { { "library" }, { "pick", "authors" }, { "quote" } } },
    { id = "calendar", label = T("Calendar"), heading = false, kicker = "month",
      rows = { { "calendar" } } },
}

-- How tall a card wants to be, as a share of the page. A row takes the larger
-- of its cards' shares; the rows then stretch to fill the page between them.
A.DASH_WEIGHT = {
    banner = 0.13, continue = 0.355, activity = 0.24, week_rings = 0.27, month_rings = 0.40, goal = 0.24,
    bookclub = 0.235, tbr = 0.36, genres = 0.215, year_covers = 0.30, week = 0.27,
    heatmap = 0.25, year_chart = 0.30, finished = 0.355, deadline = 0.27,
    longest_year = 0.36, longest_month = 0.36,
    year_time = 0.36, month_totals = 0.40, month_chart = 0.30, when_read = 0.36,
    challenge = 0.33, forecast = 0.33, trends = 0.62, control = 0.24, compare = 0.34,
    library = 0.27, authors = 0.37, pick = 0.37, quote = 0.25, timeline = 0.27,
    calendar = 0.9, cover_week = 0.3, quote2 = 0.25, quote3 = 0.25, quote4 = 0.25, device = 0.24,
    total_pages = 0.27,
}
-- The order cards are offered in when editing a page.
A.DASH_CARDS = { "banner", "continue", "activity", "week_rings", "month_rings", "month_totals", "month_chart",
                 "when_read", "goal", "bookclub", "tbr", "genres", "year_covers", "week", "year_chart",
                 "year_time", "heatmap", "finished", "longest_year", "longest_month", "deadline",
                 "trends", "challenge", "forecast", "control", "device", "total_pages", "compare",
                 "library", "authors", "pick", "quote", "timeline", "calendar", "cover_week",
                 "quote2", "quote3", "quote4" }
A.DASH_MAX_ROWS = 6
A.DASH_MAX_PAGES = 8

-- Pages the reader added: { { id = "c1", label = "My page" }, ... } under
-- dash_custom. Their rows are kept like any page's, under dash_rows_<id>.
local function customPages()
    local out = {}
    local list = A.get("dash_custom", nil)
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) == "table" and type(e.id) == "string" and e.id:match("^c%d+$") then
            out[#out + 1] = { id = e.id, label = (type(e.label) == "string" and e.label ~= "") and e.label or T("My page"),
                custom = true, rows = { { type(e.first) == "string" and e.first or "continue" } } }
        end
    end
    return out
end

--- Every page, built in and added, in the reader's order (dash_order).
function A.dashPages()
    local all, natural = {}, {}
    for _, p in ipairs(A.DASH_PAGES) do all[#all + 1] = p end
    for _, p in ipairs(customPages()) do all[#all + 1] = p end
    for i, p in ipairs(all) do natural[p.id] = i end
    local order = A.get("dash_order", nil)
    if type(order) == "table" then
        local pos = {}
        for i, id in ipairs(order) do if type(id) == "string" and not pos[id] then pos[id] = i end end
        table.sort(all, function(a, b)
            local pa, pb = pos[a.id] or (1000 + natural[a.id]), pos[b.id] or (1000 + natural[b.id])
            return pa < pb
        end)
    end
    return all
end
local ROW_HEIGHTS = { { 0.7, T("Shorter") }, { 1, T("Normal") }, { 1.35, T("Taller") }, { 1.8, T("Tallest") } }

local function pageById(id)
    for _, page in ipairs(A.dashPages()) do if page.id == id then return page end end
    return nil
end

local function pageLabel(page)
    local v = A.get("dash_label_" .. page.id, nil)
    if type(v) == "string" and v ~= "" then return v end
    return page.label
end

local function pageHeading(page)
    local v = A.get("dash_heading_" .. page.id, nil)
    if v == nil then return page.heading and true or false end
    return v and true or false
end

-- The rows of a page: { { cards = { name[, name] }, k = height factor }, ... }
-- and whether the reader has edited it. Edited pages are stored whole under
-- dash_rows_<id>; anything unreadable in there is skipped, and a page that
-- ends up empty falls back to the built-in one.
local function pageRows(page)
    local rows = {}
    local saved = A.get("dash_rows_" .. page.id, nil)
    if type(saved) == "table" then
        for _, r in ipairs(saved) do
            local cards = {}
            if type(r) == "table" and type(r.c) == "table" then
                for _, name in ipairs(r.c) do
                    if type(name) == "string" and A.DASH_WEIGHT[name] and type(P[name]) == "table" and #cards < 2 then
                        cards[#cards + 1] = name
                    end
                end
            end
            if #cards > 0 and #rows < A.DASH_MAX_ROWS then
                rows[#rows + 1] = { cards = cards, k = A.clamp(tonumber(r.k) or 1, 0.4, 3) }
            end
        end
        if #rows > 0 then return rows, true end
    end
    for _, r in ipairs(page.rows) do
        local cards = {}
        for _, name in ipairs(r) do cards[#cards + 1] = name end
        rows[#rows + 1] = { cards = cards, k = 1 }
    end
    return rows, false
end

local function savePageRows(page, rows)
    local out = {}
    for _, r in ipairs(rows) do
        local c = {}
        for _, name in ipairs(r.cards) do c[#c + 1] = name end
        out[#out + 1] = { c = c, k = r.k or 1 }
    end
    A.set("dash_rows_" .. page.id, out)
end

local function rowWeight(row)
    local wgt = 0
    for _, name in ipairs(row.cards) do wgt = max(wgt, A.DASH_WEIGHT[name] or 0.25) end
    return wgt * (row.k or 1)
end

-- The tabs: one per page that is switched on. Returns them and the pages
-- they index into.
local function dashTabs()
    local tabs = {}
    local pages = A.dashPages()
    for i, page in ipairs(pages) do
        if A.get("dash_page_" .. page.id, true) ~= false then
            tabs[#tabs + 1] = { kind = "page", page = i, label = pageLabel(page), id = page.id }
        end
    end
    if #tabs == 0 then tabs[1] = { kind = "page", page = 1, label = pageLabel(pages[1]), id = pages[1].id } end
    return tabs, pages
end

-- Space left clear around the page, so cards do not sit on its edge.
local MARGINS = { none = 0, small = 1, medium = 2 }
local function dashMargin(gap)
    local k = MARGINS[A.get("dash_margin", "small")]
    return floor(gap * (k or 1))
end

local function currentPage(tabs)
    local want = tonumber(A.state.dash_page)
    for _, t in ipairs(tabs) do
        if t.kind == "page" and t.page == want then return want end
    end
    for _, t in ipairs(tabs) do
        if t.kind == "page" then A.state.dash_page = t.page; return t.page end
    end
    return 1
end

local function buildDashboard(ctx, w, h)
    local page_bg, page_fg, dark, _, page_look = A.dashPage()
    -- A theme with its own page colour: paint it, out to the edges of the
    -- cell. Over a Simple UI wallpaper with this module's Background Opacity
    -- below Solid, leave the page unpainted so the wallpaper shows between
    -- the cards (the cards and the tab bar stay solid, to stay readable).
    local see = ctx and H.seeThrough(ctx.pfx, ctx.mod_id) or false
    local c = A.canvas{ w = w, h = h, plain = true, bleed = page_look ~= nil and not see,
        fill = (page_look and not see) and page_bg or nil }
    local th = A.theme()
    local ts = textScale()
    local gap = max(6, floor(min(w, h) * 0.016 + 0.5))
    local tabs, pages = dashTabs()
    local page_i = currentPage(tabs)
    local page = pages[page_i]

    -- Everything is laid out inside a margin: from here on w and h are the
    -- space inside it, and (ox, oy) is where that space starts.
    local m = dashMargin(gap)
    if w - 2 * m < 60 or h - 2 * m < 60 then m = 0 end
    local ox, oy = m, m
    w, h = w - 2 * m, h - 2 * m

    -- tab bar
    local body_h = h
    if #tabs > 1 then
        local bar_h = A.clamp(floor(h * 0.056 + 0.5), 40, 110)
        local bar_w = min(w, max(floor(w * 0.72), #tabs * floor(bar_h * 2.3)))
        local bx, by = ox + floor((w - bar_w) / 2), oy + h - bar_h
        local bw_ = max(2, floor(bar_h * 0.045 + 0.5))
        local CYT = A.cutTheme()
        -- the Dark Academia theme: the tab names alone, the open one underlined in brass
        local ACT = not CYT and A.academiaTheme()
        if CYT or ACT then
            -- the Cyber theme: a row of square tabs, the open one filled
            bar_w, bx = w, ox
        else
            c:frame(bx, by, bar_w, bar_h, bar_h / 2, bw_, page_fg, page_bg, see and A.BEHIND or page_bg)
        end
        local inner = (CYT or ACT) and bar_w or (bar_w - bar_h * 0.5)
        local cell = inner / #tabs
        local size = max(10, floor(bar_h * 0.36 * ts + 0.5))
        local tgap = CYT and max(4, floor(bar_h * 0.12)) or 0
        local caps = CYT and true or nil
        if CYT then size = max(10, floor(size * 0.86)) end
        -- longer tab names (another language, a name of your own) get a
        -- smaller size that fits, instead of being cut short
        for _ = 1, 6 do
            local widest = 0
            for _, tab in ipairs(tabs) do
                widest = max(widest, c:text(tab.label, size, { bold = true, caps = caps }).w)
            end
            local room = CYT and (cell - 6 - tgap - floor(bar_h * 0.3)) or (cell - bar_h * 0.3)
            if widest <= room or size <= 12 then break end
            size = max(12, floor(size * room / widest))
        end
        local fill = A.shown(dark and th.gold or th.wine)
        local on_fill = A.shown(dark and th.ink or th.paper)
        local line = A.mix(page_fg, page_bg, 0.72)
        for i, tab in ipairs(tabs) do
            local cx = bx + ((CYT or ACT) and 0 or bar_h * 0.25) + (i - 0.5) * cell
            local active = tab.kind == "page" and tab.page == page_i
            local t_tab = c:text(tab.label, size, { bold = active or caps, caps = caps, max_w = cell - 6 - tgap,
                color = (active and ACT) and page_fg or active and on_fill or A.mix(page_fg, page_bg, ACT and 0.45 or 0.38) })
            if CYT then
                local tx0, tw0 = floor(cx - cell / 2 + tgap / 2), floor(cell - tgap)
                local th0 = floor(bar_h * 0.86)
                local ty0 = by + floor((bar_h - th0) / 2)
                if active then
                    CYT.cutRect(c, tx0, ty0, tw0, th0, th0 * 0.3, fill)
                else
                    c:frame(tx0, ty0, tw0, th0, 0, max(1, floor(bw_ * 0.6)), line, page_bg, see and A.BEHIND or page_bg)
                end
            elseif ACT then
                if active then
                    local uw = t_tab.w + floor(bar_h * 0.2)
                    c:rect(floor(cx - uw / 2), floor(by + bar_h / 2 + t_tab.h / 2), uw, max(2, floor(bar_h * 0.05)),
                        A.ACCENTS.brass.bright)
                end
            elseif active then
                local pw = min(cell - 4, t_tab.w + bar_h * 0.5)
                local ph = bar_h * 0.6
                c:rrect(cx - pw / 2, by + (bar_h - ph) / 2, pw, ph, ph * 0.22, fill, page_bg)
            end
            c:put(t_tab, cx, by + bar_h / 2, "c", "mid")
            c:region("tab:" .. i, cx - cell / 2, by, cell, bar_h)
        end
        body_h = h - bar_h - gap
    end

    -- Short, wide cell (the hero area): there is not room for a whole page,
    -- so show as many of its rows as fit at a readable height.
    local rows = pageRows(page)
    local heading = pageHeading(page)
    local min_row = w * 0.17
    if body_h < #rows * min_row then
        heading = false
        local keep = max(1, floor(body_h / min_row))
        local cut = {}
        for i = 1, min(keep, #rows) do cut[i] = rows[i] end
        rows = cut
    end

    local y = 0
    if heading then
        local head_h = floor(body_h * 0.105)
        local kicker, nav
        local refresh = ctx.refresh
        local st = D.stats(refresh)
        local dot = "  \xE2\x80\xA2  "
        if page.kicker == "year" then
            -- "2026 · 29 books"
            local yr = D.year(refresh)
            kicker = os.date("%Y") .. (yr and (dot .. A.plural(yr.total, "book", "books")) or "")
        elseif page.kicker == "month" then
            -- "October · day 8 of 31", or for a month gone by "September · 30 days";
            -- and the switcher that steps back through the last twelve months
            local t = os.date("*t")
            local vy, vm, current = A.viewMonth()
            local n_days = tonumber(os.date("%d", os.time{ year = vy, month = vm + 1, day = 0, hour = 12 })) or 30
            kicker = A.monthTitle(vy, vm) .. dot .. (current and (T("day ") .. t.day .. T(" of ") .. n_days) or (n_days .. T(" days")))
            nav = { prev = (tonumber(A.state.month_offset) or 0) > -D.BACK_MONTHS, next = not current, today = not current }
        elseif page.kicker == "library" then
            -- "412 books · 168 read"
            local lib = D.library(refresh)
            kicker = lib and (A.plural(lib.total, "book", "books") .. dot .. A.thousands(lib.counts.finished) .. T(" read")) or nil
        elseif page.kicker == "streak" and st then
            -- "Streak 147 days · best 150"
            kicker = (st.streak > 0 and (T("Streak ") .. A.plural(st.streak, "day", "days")) or T("No streak yet"))
                .. ((st.best or 0) > st.streak and (dot .. T("best ") .. st.best) or "")
        elseif st then
            kicker = T("This week") .. dot .. A.plural(st.week_pages, "page", "pages")
        end
        local env = { w = w, h = head_h, ts = ts, see = see }
        local ok, hc = pcall(P.heading, env, kicker, pageLabel(page), nav)
        if ok and hc then
            hc.cache_me = true
            c:sub(hc, ox, oy + y, "heading|")
        end
        y = y + head_h + floor(gap * 0.6)
    end

    local total = 0
    for _, row in ipairs(rows) do total = total + rowWeight(row) end
    local avail = body_h - y - gap * (#rows - 1)
    for ri, row in ipairs(rows) do
        local rh = floor(avail * rowWeight(row) / total)
        if ri == #rows then rh = body_h - y end
        local names = row.cards
        local pw = floor((w - gap * (#names - 1)) / #names)
        for ni, name in ipairs(names) do
            local x = (ni - 1) * (pw + gap)
            local width = (ni == #names) and (w - x) or pw
            local env = makeEnv(name, ctx, width, rh, { nested = true, slot = 1, page = page_look, see = see, page_heading = heading })
            local child = buildPanel(name, env)
            child.cache_me = not P[name].tick
            c:sub(child, ox + x, oy + y, name .. "|")
            if P[name].tick then c.clock_y, c.clock_h = oy + y, rh end
            -- the rest of the panel: a plain tap on it
            c:region(name .. "|", ox + x, oy + y, width, rh)
        end
        y = y + rh + gap
    end
    A.state.dash_tabs = tabs
    return c
end

local function dashSplit(region)
    if type(region) ~= "string" then return nil end
    local tab = region:match("^tab:(%d+)$")
    if tab then return "tab", tonumber(tab) end
    local nav = region:match("^heading|(%a+)$")
    if nav then return "nav", nav end
    local name, sub = region:match("^([%w_]+)|(.*)$")
    if name and P[name] and type(P[name]) == "table" then
        return "panel", name, (sub ~= "" and sub or nil)
    end
    return nil
end

local Dashboard = {
    key = "alm_dashboard",
    title = A.NAME .. T(" \xC2\xB7 Dashboard"),
    summary = A.tr("All the %1 cards as tabbed pages. Best alone on a page.", A.NAME),
}

-- A screen seen for the first time (a newly opened one) starts the Monthly
-- page on this month again.
local _seen_screens = setmetatable({}, { __mode = "k" })

function Dashboard.render(ctx)
    local w = max(80, floor(tonumber(ctx.width) or 400))
    local h = (ctx.height and ctx.height > 0) and floor(ctx.height) or floor(w * 1.2)
    if ctx.screen and not _seen_screens[ctx.screen] then
        _seen_screens[ctx.screen] = true
        A.state.month_offset = 0
    end
    local ok, c = pcall(buildDashboard, ctx, w, h)
    if not ok then return errorCard(A._("Dashboard"), w, h, c) end
    declareRegions(ctx, c)
    H.wantTick(ctx, c.clock_y and { y = c.clock_y, h = c.clock_h } or nil)
    return c
end

local function dashRegion(ctx)
    return ctx and ctx.tapped_region
end

-- The Monthly page's month switcher: back up to twelve months, forward to
-- this one; Today (shown once you have stepped away) comes straight back.
local function stepMonth(which)
    local off = tonumber(A.state.month_offset) or 0
    local new = off
    if which == "prev" then new = max(-D.BACK_MONTHS, off - 1)
    elseif which == "next" then new = min(0, off + 1)
    elseif which == "now" then new = 0 end
    A.state.month_offset = new
    return new ~= off
end

function Dashboard.keep_open(ctx)
    local kind, a, b = dashSplit(dashRegion(ctx))
    if kind == "nav" then return true end
    if kind == "tab" then
        local tab = A.state.dash_tabs and A.state.dash_tabs[a]
        return tab ~= nil and tab.kind == "page"
    elseif kind == "panel" then
        local def = P[a]
        if customTap(a, b) then return false end
        return (def.keep and def.keep(b)) and true or false
    end
    return false
end

function Dashboard.on_tap(ctx)
    local kind, a, b = dashSplit(dashRegion(ctx))
    if kind == "nav" then
        if stepMonth(a) then pageTurn(ctx) end
        return
    end
    if kind == "tab" then
        local tab = A.state.dash_tabs and A.state.dash_tabs[a]
        if not tab then return end
        if A.state.dash_page ~= tab.page then
            A.state.dash_page = tab.page
            pageTurn(ctx)
        end
    elseif kind == "panel" then
        local def = P[a]
        local custom = customTap(a, b)
        if custom then
            runTapAction(custom, ctx)
        elseif def.tap then
            local ok, err = pcall(def.tap, makeEnv(a, ctx, 0, 0, { nested = true, slot = 1 }), b)
            if not ok then A.log(a, "tap failed:", err) end
            if def.keep and def.keep(b) then inkRefresh(ctx) end
        end
    end
end

local CHECK = "\xE2\x9C\x93 "
local ELLIPSIS = "\xE2\x80\xA6"

local function cardOptions(with_none)
    local opts = {}
    if with_none then opts[1] = { false, T("Nothing (full width)") } end
    for _, name in ipairs(A.DASH_CARDS) do
        if type(P[name]) == "table" then opts[#opts + 1] = { name, P[name].title } end
    end
    return opts
end

local function rowTitle(row)
    local names = {}
    for _, name in ipairs(row.cards) do names[#names + 1] = P[name].title end
    return table.concat(names, "  +  ")
end

-- One row of one page: which card, what (if anything) beside it, how tall,
-- where in the page. Every change is saved and drawn straight away.
local function editRow(ctx, page, idx, back)
    S.open(ctx, pageLabel(page) .. T(": row ") .. idx, function(api)
        local rows = pageRows(page)
        local row = rows[idx]
        local out = {}
        if not row then
            out[1] = S.header(T("That row is no longer there"))
        else
            local function save() savePageRows(page, rows) end
            out[#out + 1] = S.pick(ctx, api, T("Card"), cardOptions(false), row.cards[1], function(v)
                row.cards[1] = v
                save()
            end)
            out[#out + 1] = S.pick(ctx, api, T("Beside it"), cardOptions(true), row.cards[2] or false, function(v)
                row.cards[2] = v or nil
                save()
            end)
            -- snap the stored factor to the nearest choice so one is ticked
            local k, best = row.k or 1, 1
            for _, h in ipairs(ROW_HEIGHTS) do
                if math.abs(h[1] - k) < math.abs(best - k) then best = h[1] end
            end
            out[#out + 1] = S.header(T("Height"))
            out[#out + 1] = S.radio(api, ROW_HEIGHTS, best, function(v) row.k = v; save() end)
            local function move(to)
                rows[idx], rows[to] = rows[to], rows[idx]
                save()
                api.close()
                S.reload(ctx)
                editRow(ctx, page, to, back)
            end
            out[#out + 1] = {
                { text = T("Move up"), enabled = idx > 1, callback = function() move(idx - 1) end },
                { text = T("Move down"), enabled = idx < #rows, callback = function() move(idx + 1) end },
            }
            out[#out + 1] = { { text = T("Remove this row"), enabled = #rows > 1, callback = function()
                table.remove(rows, idx)
                save()
                api.close()
                S.reload(ctx)
                back()
            end } }
        end
        out[#out + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        return out
    end)
end

-- Every setting the Dashboard's layout is kept under (not the cards' own).
local function layoutKeys()
    local keys = { "dash_custom", "dash_order", "dash_margin" }
    for _, page in ipairs(A.dashPages()) do
        for _, k in ipairs{ "dash_rows_", "dash_label_", "dash_heading_", "dash_page_" } do keys[#keys + 1] = k .. page.id end
    end
    return keys
end

--- Every page, tab and row back as it came. Card settings and colours stay.
function A.resetDashboard()
    for _, k in ipairs(layoutKeys()) do A.set(k, nil) end
    A.state.dash_page = 1
    A.state.edit_page = nil
end

--- A new page at the end, starting with a card no page shows yet. Returns its id.
function A.addPage(label)
    if #A.dashPages() >= A.DASH_MAX_PAGES then return nil end
    local list = A.get("dash_custom", nil)
    local copy, top = {}, 0
    if type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" and type(e.id) == "string" then
                copy[#copy + 1] = { id = e.id, label = e.label, first = e.first }
                top = max(top, tonumber(e.id:match("^c(%d+)$")) or 0)
            end
        end
    end
    local used = {}
    for _, page in ipairs(A.dashPages()) do
        if A.get("dash_page_" .. page.id, true) ~= false then
            for _, r in ipairs(pageRows(page)) do for _, name in ipairs(r.cards) do used[name] = true end end
        end
    end
    local first = "continue"
    for _, name in ipairs(A.DASH_CARDS) do if not used[name] then first = name break end end
    local id = "c" .. (top + 1)
    copy[#copy + 1] = { id = id, label = label or (T("Page ") .. (#A.dashPages() + 1)), first = first }
    A.set("dash_custom", copy)
    return id
end

--- Take away a page the reader added.
function A.removePage(id)
    local list = A.get("dash_custom", nil)
    local copy = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and e.id ~= id then copy[#copy + 1] = { id = e.id, label = e.label, first = e.first } end
    end
    A.set("dash_custom", #copy > 0 and copy or nil)
    for _, k in ipairs{ "dash_rows_", "dash_label_", "dash_heading_", "dash_page_" } do A.set(k .. id, nil) end
    local order = A.get("dash_order", nil)
    if type(order) == "table" then
        local keep = {}
        for _, v in ipairs(order) do if v ~= id then keep[#keep + 1] = v end end
        A.set("dash_order", keep)
    end
end

--- Move a page one place left (-1) or right (+1) among the tabs.
function A.movePage(id, step)
    local pages = A.dashPages()
    local ids, at = {}, nil
    for i, p in ipairs(pages) do ids[i] = p.id; if p.id == id then at = i end end
    local to = at and at + step
    if not (at and to >= 1 and to <= #ids) then return false end
    ids[at], ids[to] = ids[to], ids[at]
    A.set("dash_order", ids)
    return true
end

-- The pages: pick one, then its rows are listed. Tap a row to change it.
local function editPages(ctx, back)
    local function again() editPages(ctx, back) end
    S.open(ctx, T("Dashboard pages"), function(api)
        local pages = A.dashPages()
        local page = pageById(A.state.edit_page) or pages[1]
        local out = {}
        local line = {}
        for _, pg in ipairs(pages) do
            line[#line + 1] = {
                text = ((pg.id == page.id) and CHECK or "") .. pageLabel(pg),
                callback = function()
                    A.state.edit_page = pg.id
                    api.again()
                end,
            }
            if #line == 4 then out[#out + 1] = line; line = {} end
        end
        if #line > 0 then out[#out + 1] = line end
        local rows, edited = pageRows(page)
        out[#out + 1] = S.header(T("Rows, top to bottom (tap one to change it)"))
        for i, row in ipairs(rows) do
            out[#out + 1] = { { text = i .. ".  " .. rowTitle(row), callback = function()
                api.close()
                editRow(ctx, page, i, again)
            end } }
        end
        out[#out + 1] = { { text = T("+ Add a row"), enabled = #rows < A.DASH_MAX_ROWS, callback = function()
            -- start with a card this page does not have yet
            local used = {}
            for _, r in ipairs(rows) do for _, name in ipairs(r.cards) do used[name] = true end end
            local pick = A.DASH_CARDS[1]
            for _, name in ipairs(A.DASH_CARDS) do if not used[name] then pick = name break end end
            rows[#rows + 1] = { cards = { pick }, k = 1 }
            savePageRows(page, rows)
            api.close()
            S.reload(ctx)
            editRow(ctx, page, #rows, again)
        end } }
        out[#out + 1] = S.header(T("This page"))
        out[#out + 1] = S.input(api, T("Tab name"), pageLabel(page), function(v)
            A.set("dash_label_" .. page.id, (v ~= "" and v ~= page.label) and v or nil)
        end)
        out[#out + 1] = S.radio(api, { { true, T("Title on the page") }, { false, T("No title") } },
            pageHeading(page), function(v) A.set("dash_heading_" .. page.id, v) end)
        out[#out + 1] = S.radio(api, { { true, T("Page shown") }, { false, T("Page hidden") } },
            A.get("dash_page_" .. page.id, true) ~= false, function(v) A.set("dash_page_" .. page.id, v) end)
        local at = 1
        for i, pg in ipairs(pages) do if pg.id == page.id then at = i end end
        out[#out + 1] = {
            { text = T("\xE2\x80\xB9 Move tab left"), enabled = at > 1, callback = function()
                A.movePage(page.id, -1); api.changed()
            end },
            { text = T("Move tab right \xE2\x80\xBA"), enabled = at < #pages, callback = function()
                A.movePage(page.id, 1); api.changed()
            end },
        }
        if page.custom then
            out[#out + 1] = { { text = T("Remove this page"), callback = function()
                A.removePage(page.id)
                A.state.edit_page = nil
                A.state.dash_page = 1
                api.changed()
            end } }
        else
            out[#out + 1] = { { text = T("Put this page back as it came"), enabled = edited, callback = function()
                A.set("dash_rows_" .. page.id, nil)
                api.changed()
            end } }
        end
        out[#out + 1] = { { text = T("+ Add a page"), enabled = #pages < A.DASH_MAX_PAGES, callback = function()
            A.state.edit_page = A.addPage() or A.state.edit_page
            api.changed()
        end } }
        if back then
            out[#out + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        end
        return out
    end)
end

function Dashboard.show_settings(ctx)
    local function show()
        S.open(ctx, A.NAME .. T(" dashboard"), function(api)
            local rows = {}
            rows[#rows + 1] = { { text = T("Pages and cards") .. ELLIPSIS, callback = function()
                api.close()
                editPages(ctx, show)
            end } }
            for _, r in ipairs(S.styleRows(api, ctx)) do rows[#rows + 1] = r end
            rows[#rows + 1] = S.header(T("Margin around the page"))
            rows[#rows + 1] = S.radio(api, { { "none", T("None") }, { "small", T("Small") }, { "medium", T("Medium") } },
                MARGINS[A.get("dash_margin", "small")] and A.get("dash_margin", "small") or "small",
                function(v) A.set("dash_margin", v ~= "small" and v or nil) end)
            rows[#rows + 1] = { { text = T("Card settings") .. ELLIPSIS, callback = function()
                api.close()
                S.open(ctx, T("Card settings"), function(sub)
                    local list, seen = {}, {}
                    local line = {}
                    for _, page in ipairs(A.dashPages()) do
                        for _, r in ipairs(pageRows(page)) do
                            for _, name in ipairs(r.cards) do
                                if not seen[name] then
                                    seen[name] = true
                                    line[#line + 1] = { text = P[name].title, callback = function()
                                        sub.close()
                                        S.card(name, ctx, function()
                                            return makeEnv(name, ctx, 0, 0, { nested = true, slot = 1 })
                                        end, show)
                                    end }
                                    if #line == 2 then list[#list + 1] = line; line = {} end
                                end
                            end
                        end
                    end
                    if #line > 0 then list[#list + 1] = line end
                    list[#list + 1] = { { text = T("Back"), callback = function() sub.close(); show() end } }
                    return list
                end)
            end } }
            rows[#rows + 1] = { { text = T("Look and colours") .. ELLIPSIS, callback = function()
                api.close()
                S.look(ctx, show)
            end } }
            rows[#rows + 1] = { { text = T("Put the whole Dashboard back as it came") .. ELLIPSIS, callback = function()
                api.close()
                local UIManager = require("ui/uimanager")
                local ConfirmBox = require("ui/widget/confirmbox")
                UIManager:show(ConfirmBox:new{
                    text = T("Put every page, tab and row of the Dashboard back as it came?\n\nPages you added are removed. Each card's own settings and the colours are kept."),
                    ok_text = T("Put back"),
                    ok_callback = function()
                        A.resetDashboard()
                        S.reload(ctx)
                        show()
                    end,
                    cancel_callback = function() show() end,
                })
            end } }
            return rows
        end)
    end
    show()
end

A.Dashboard = Dashboard
A.dashPageRows = pageRows
A.dashPageLabel = pageLabel
A.dashEditPages = editPages
A.DASH_MARGINS = MARGINS

-- ════════════════════════════════════════════════════════════════════════════
-- Simple UI modules
-- ════════════════════════════════════════════════════════════════════════════

-- The order the modules are listed in Simple UI's module lists.
A.MODULE_ORDER = {
    "dashboard", "mini",
    -- Today
    "banner", "continue", "activity", "week_rings", "week", "cover_week", "goal", "bookclub", "timeline",
    "control", "device", "total_pages",
    -- Ornaments (no card)
    "books_year", "streak_flame", "pages_today", "pages_turned", "letter_board",
    -- Monthly
    "calendar", "month_rings", "month_totals", "month_chart", "when_read", "longest_month", "challenge",
    -- Yearly
    "year_time", "longest_year", "year_chart", "year_covers", "genres", "heatmap", "finished",
    -- Trends
    "trends", "compare", "forecast",
    -- Library
    "library", "authors", "pick", "quote", "quote2", "quote3", "quote4",
    -- Shelves and goals
    "tbr", "deadline",
}

-- A card's height: the shape it was designed at (taller when narrow), times
-- the reader's own "Card height" for it on this screen.
A.HEIGHT_MIN, A.HEIGHT_MAX, A.HEIGHT_DEF = 50, 250, 100

function A.cardHeightPct(pfx, id)
    local v = tonumber(A.get(screenKey(pfx, id, "height"), A.HEIGHT_DEF)) or A.HEIGHT_DEF
    return A.clamp(floor(v), A.HEIGHT_MIN, A.HEIGHT_MAX)
end

local function cardHeight(name, w, pfx, id)
    local def = P[name]
    local ratio = (w < 760 and def.ratio_narrow) or def.ratio or 0.5
    return max(60, floor(w * ratio * A.cardHeightPct(pfx, id) / 100 + 0.5))
end

-- The Dashboard's height: the rest of the page below its top margin
-- ("fill"), or a share of the screen's content area.
function A.dashHeightMode(pfx, id)
    local v = A.get(screenKey(pfx, id, "dash_height"), "fill")
    if v == "fill" then return "fill" end
    v = tonumber(v)
    if v and v >= 30 and v <= 100 then return floor(v) end
    return "fill"
end

local function contentHeight(sctx)
    local screen = type(sctx) == "table" and sctx._screen_widget
    if screen and tonumber(screen._layout_content_h) then return screen._layout_content_h end
    local UI = H.try("infra/sui_core")
    if UI and UI.getContentHeight then
        local ok, v = pcall(UI.getContentHeight)
        if ok and v then return v end
    end
    local Screen = A.screen()
    return Screen:getHeight()
end

local function dashHeight(sctx, id)
    local pfx = type(sctx) == "table" and sctx.pfx or "simpleui_hs_"
    local content_h = contentHeight(sctx)
    local mode = A.dashHeightMode(pfx, id)
    if mode ~= "fill" then return max(200, floor(content_h * mode / 100)) end
    local UI = H.try("infra/sui_core")
    local Config = H.try("infra/sui_config")
    local gap = (UI and UI.MOD_GAP) or A.screen():scaleBySize(23)
    if Config and Config.getModuleGapPx then
        local ok, v = pcall(Config.getModuleGapPx, id, pfx, gap)
        if ok and tonumber(v) then gap = tonumber(v) end
    end
    local h = content_h - gap
    -- Simple UI's page bar sits over the bottom of a screen with several pages
    local screen = type(sctx) == "table" and sctx._screen_widget
    if screen and (tonumber(screen._total_pages) or 1) > 1 then
        local SUISettings = H.try("infra/sui_store")
        local hidden = SUISettings and SUISettings.isTrue and SUISettings:isTrue(pfx .. "pagination_hidden")
        if not hidden then h = h - A.screen():scaleBySize(40) end
    end
    return max(200, floor(h))
end
A.dashHeight = dashHeight

-- First region containing (x, y): regions are declared most specific first.
local function hitRegion(regions, x, y)
    if type(regions) ~= "table" then return nil end
    for i = 1, #regions do
        local r = regions[i]
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r.id end
    end
    return nil
end

-- The card, wrapped so a tap reaches it. A long-press is left alone: Simple
-- UI's own wrapper turns it into the module settings.
local function tappable(c, ctx, on_tap)
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local Geom = require("ui/geometry")
    local box = InputContainer:new{ dimen = Geom:new{ w = c.w, h = c.h }, c }
    box.ges_events = {
        TapReadingLog = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } },
    }
    function box:onTapReadingLog(_, ges)
        local d = self.dimen
        local region
        if ges and ges.pos and d and d.x then
            region = hitRegion(ctx._regions, ges.pos.x - d.x, ges.pos.y - d.y)
        end
        ctx.tapped_region = region
        local ok, err = pcall(on_tap)
        ctx.tapped_region = nil
        if not ok then A.log("tap failed:", err) end
        return true
    end
    box._readinglog_ctx = ctx
    ctx._box = box
    return box
end

-- Covers that were still being extracted when a card was drawn: once one
-- lands, the card is redrawn. Simple UI calls this from its cover poll.
local function updateCovers(id)
    return function(_widget, sctx)
        local set = D.cover_pending[id]
        if not set or next(set) == nil then return true end
        local arrived, waiting = false, false
        for fp in pairs(set) do
            local st = H.coverSettled(fp)
            if st == "arrived" then arrived = true; set[fp] = nil
            elseif st == "none" then set[fp] = nil
            else waiting = true end
        end
        if arrived then
            local screen = type(sctx) == "table" and sctx._screen_widget or nil
            local ctx = latestCtx(screen, id)
            if ctx then
                require("ui/uimanager"):nextTick(function() H.repaint(ctx) end)
            end
        end
        return not waiting
    end
end

-- Build one card (or the Dashboard) with its covers attributed to it.
local function draw(id, fn)
    D.cover_pending[id] = nil
    D.cover_owner = id
    local ok, c = pcall(fn)
    D.cover_owner = nil
    return ok, c
end

local function contentWidth(sctx)
    local UI = H.try("infra/sui_core")
    local col_w = type(sctx) == "table" and (sctx.col_w or sctx.inner_w)
    if not col_w and UI and UI.getInnerW then
        local ok, v = pcall(UI.getInnerW)
        if ok then col_w = v end
    end
    col_w = col_w or A.screen():getWidth()
    return max(40, col_w - 2 * ((UI and UI.PAD) or 0))
end

-- Simple UI puts each module in a box of its own (the module's Background:
-- colour, frame, opacity), padded inside the column. A card that draws its
-- own frame and background (a theme with framed cards, like Dark Academia or
-- Cyber, when the wallpaper doesn't show through) and the ornaments go
-- without it: the box would only show as a margin of Simple UI's colour round
-- the card. Every other card gets Simple UI's box as before. Returns Simple
-- UI's chrome module and the chrome to wrap the card in, or nil when this
-- Simple UI has none.
local function chromeOf(name, pfx, id)
    local Chrome = H.try("features/sui_module_chrome")
    if not (Chrome and Chrome.resolve and Chrome.wrap and Chrome.contentWidth) then return nil end
    local none = Chrome.NO_CHROME or { strength = 0, border_sz = 0 }
    if P[name].bare then return Chrome, none end
    if not A.standaloneNative() and not H.seeThrough(pfx, id) then return Chrome, none end
    local ok, chrome = pcall(Chrome.resolve, pfx, id)
    return Chrome, (ok and type(chrome) == "table") and chrome or none
end

-- How much taller the box makes the card (padding and frame, top and bottom).
local function chromeHeight(Chrome, chrome)
    if not (Chrome.hasChrome and Chrome.boxInset) then return 0 end
    local ok, has = pcall(Chrome.hasChrome, chrome)
    if not (ok and has) then return 0 end
    local ok2, v = pcall(Chrome.boxInset, chrome)
    return ok2 and tonumber(v) or 0
end

local function cardModule(name)
    local def = P[name]
    local id = A.ID_PREFIX .. name
    local M = {
        id = id,
        name = A.NAME .. " \xC2\xB7 " .. def.title,
        label = nil,
        enabled_key = id .. "_enabled",
        default_on = false,
        is_book_mod = true,
        has_covers = true,
        -- Simple UI hands over the whole column; the card puts itself in
        -- Simple UI's box, or not (see chromeOf)
        owns_chrome = true,
        readinglog_panel = name,
    }

    function M.build(w, sctx)
        w = max(40, floor(w))
        local pfx = type(sctx) == "table" and sctx.pfx or "simpleui_hs_"
        -- w is the whole column when Simple UI honours owns_chrome (it then
        -- says so in sctx.col_w); otherwise it has already boxed the card
        local Chrome, chrome
        local col_w = type(sctx) == "table" and tonumber(sctx.col_w)
        if col_w and floor(col_w) == w then Chrome, chrome = chromeOf(name, pfx, id) end
        local cw = w
        if chrome then
            local ok, v = pcall(Chrome.contentWidth, w, chrome)
            cw = max(40, floor(ok and tonumber(v) or w))
        end
        local h = cardHeight(name, cw, pfx, id)
        local ctx = cardCtx(id, sctx, cw, h)
        local ok, c = draw(id, function() return A.render(name, ctx) end)
        if not ok or not c then c = errorCard(name, cw, h, c) end
        local box = tappable(c, ctx, function() A.onTap(name, ctx) end)
        if chrome then
            local okw, boxed = pcall(Chrome.wrap, box, chrome, w, (type(sctx) == "table" and sctx.landscape_factor) or 1)
            if okw and boxed then return boxed end
        end
        return box
    end

    function M.getHeight(sctx)
        local pfx = type(sctx) == "table" and sctx.pfx or "simpleui_hs_"
        local col_w = type(sctx) == "table" and tonumber(sctx.col_w)
        local Chrome, chrome
        if col_w then Chrome, chrome = chromeOf(name, pfx, id) end
        if chrome then
            local ok, v = pcall(Chrome.contentWidth, floor(col_w), chrome)
            local cw = max(40, floor(ok and tonumber(v) or col_w))
            return cardHeight(name, cw, pfx, id) + chromeHeight(Chrome, chrome)
        end
        return cardHeight(name, contentWidth(sctx), pfx, id)
    end

    function M.getMenuItems(ctx_menu)
        return S.cardMenu(name, A.menuCtx(ctx_menu, id), ctx_menu)
    end

    M.updateCovers = updateCovers(id)
    return M
end

local function dashboardModule()
    local id = A.ID_PREFIX .. "dashboard"
    local M = {
        id = id,
        name = A.NAME .. " \xC2\xB7 " .. A._("Dashboard"),
        label = nil,
        enabled_key = id .. "_enabled",
        default_on = false,
        is_book_mod = true,
        has_covers = true,
        owns_chrome = true,
        no_top_margin = nil,
    }

    function M.build(w, sctx)
        w = max(80, floor(w))
        local h = dashHeight(sctx, id)
        local ctx = cardCtx(id, sctx, w, h)
        -- shown again after a while (its screen opened): draw the page whole
        -- at once rather than with gaps first (see D.hurry)
        local now = os.time()
        if now - (A.state.dash_built_at or 0) > 30 then D.hurry(0.35) end
        A.state.dash_built_at = now
        local ok, c = draw(id, function() return Dashboard.render(ctx) end)
        if not ok or not c then c = errorCard(A._("Dashboard"), w, h, c) end
        return tappable(c, ctx, function() Dashboard.on_tap(ctx) end)
    end

    function M.getHeight(sctx)
        return dashHeight(sctx, id)
    end

    function M.getMenuItems(ctx_menu)
        return S.dashboardMenu(A.menuCtx(ctx_menu, id), ctx_menu)
    end

    M.updateCovers = updateCovers(id)
    return M
end

--- Every module, in A.MODULE_ORDER.
function A.simpleUIModules()
    if A._modules then return A._modules end
    local list = {}
    for _, name in ipairs(A.MODULE_ORDER) do
        if name == "dashboard" then
            list[#list + 1] = dashboardModule()
        elseif type(P[name]) == "table" then
            list[#list + 1] = cardModule(name)
        end
    end
    A._modules = list
    return list
end

return true
