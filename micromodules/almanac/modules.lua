--[[
Reading Log modules: turns a panel into a Bookshelf micro-module spec, and
defines the Dashboard, which lays several panels out as tabbed pages.

What Bookshelf asks of a module (see its micromodules/README.md):
  render(ctx)        return a widget for ctx.width x ctx.height
  on_tap(ctx)        ctx.tapped_region says which declared region was hit
  keep_open(ctx)     true = redraw this card after the tap
  show_settings(ctx) the long-press "Module settings" dialog
]]

local A = ...
local T = A._
local D = A.D
local P = A.panels
local S = A.S

local floor, max, min = math.floor, math.max, math.min

-- Text is always drawn at what used to be the "Largest" setting: easier to
-- read on e-ink, and one setting fewer. (A size stored by an earlier version
-- is ignored.)
A.TEXT_SCALE = 1.25
local function textScale() return A.TEXT_SCALE end

A.state.minute_seen = A.state.minute_seen or {}
A.state.own_redraw = A.state.own_redraw or {}
A.state.refreshers = A.state.refreshers or {}

-- ctx.refresh, wrapped so that a redraw this card asked for (a background
-- read landed) can be told apart from Bookshelf's once-a-minute clock redraw.
-- One wrapper per card for as long as Bookshelf hands over the same function:
-- the data layer drops repeat requests by comparing functions.
local function ownRefresh(ctx)
    local fn = ctx and ctx.refresh
    if type(fn) ~= "function" then return nil end
    local id = ctx.entry and ctx.entry.id
    if not id then return fn end
    local slot = A.state.refreshers[id]
    if not slot or slot.fn ~= fn then
        slot = { fn = fn, wrapped = function(...)
            A.state.own_redraw[id] = true
            return fn(...)
        end }
        A.state.refreshers[id] = slot
    end
    return slot.wrapped
end

-- Everything a panel builder or tap handler needs to know about where it is.
-- o = { nested = bool, slot = n }
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
    -- Bookshelf's own module text-size settings arrive as ctx.scale (100 =
    -- normal); honour them on top of the cards' own text size.
    local host_scale = A.clamp((ctx and tonumber(ctx.scale) or 100) / 100, 0.7, 1.5)
    local surface = ctx and ctx.surface
    -- On its own in Bookshelf's grid, a card takes Bookshelf's card as its
    -- own (see A.nativeTone); inside the Dashboard it keeps the theme's.
    local native = (not o.nested) and A.standaloneNative()
    -- A tinted panel inside Bookshelf's card would be a card in a card, so
    -- on their own the tinted cards start plain (unless picked by hand).
    if native and not stored_tone then
        tone_name = ({ tint = "ink", tint2 = "paper" })[A.toneKey(tone_name)] or tone_name
    end
    return {
        name = name, ctx = ctx, w = w, h = h, slot = slot,
        tone = native and A.nativeTone(tone_name) or A.tone(tone_name), ts = textScale() * host_scale,
        nested = o.nested or false,
        native = native,
        page = o.page,
        page_heading = o.page_heading or false,
        bleed = (surface == "hero" or surface == "fullscreen"),
        sample = (ctx and ctx.preview) and true or false,
        refresh = ownRefresh(ctx),
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

-- The box a panel gets. Grids hand over a height; the start menu does not,
-- so the panel takes a height that suits its width there.
local function boxFor(def, ctx)
    local w = max(40, floor(tonumber(ctx.width) or 300))
    local h
    if ctx.height and ctx.height > 0 then
        h = floor(ctx.height)
    else
        h = floor(w * ((w < 760 and def.ratio_narrow) or def.ratio))
        if ctx.max_height and h > ctx.max_height then h = floor(ctx.max_height) end
    end
    return w, max(40, h)
end

-- Tap regions arrived in Bookshelf after micro-modules did. On a Bookshelf
-- without them every tap is a plain whole-card tap, so cards whose controls
-- are regions fall back to one sensible action (`def.plain_tap`).
local function declareRegions(ctx, c)
    if ctx.set_tap_regions then
        A.state.regions_ok = true
        pcall(ctx.set_tap_regions, c.regions)
    elseif not ctx.preview then
        A.state.regions_ok = A.state.regions_ok or false
    end
end

local function tapRegion(def, ctx)
    local region = ctx and ctx.tapped_region
    if region == nil and A.state.regions_ok == false and def.plain_tap then
        return def.plain_tap
    end
    return region
end

-- ════════════════════════════════════════════════════════════════════════════
-- Screen refresh in the full-screen view
-- ════════════════════════════════════════════════════════════════════════════
-- Bookshelf shows and updates its full-screen view with quiet partial updates
-- and, unlike its home screen, without the colour hint. That suits its own
-- grey text cards. Large coloured fills are another matter, on colour e-ink
-- most of all: without the hint the panel draws them washed out, and a quiet
-- update over whatever was on screen before leaves that showing through.
--
-- Look and colours > Screen refresh picks one of:
--   clean  (default) colour hint on; one flashing update when the view opens
--          and closes; turning a dashboard page, a card that redraws after a
--          tap, and the clock each minute get a ghost-clearing update (a page
--          turn flashes every so often, following KOReader's own "Full
--          refresh rate", as a book's pages do)
--   soft   colour hint on, never a flash
--   host   leave everything to Bookshelf
--
-- None of this draws anything. It asks KOReader for screen updates, and sets
-- the `dithered` flag on the view, which is how Bookshelf's own home screen
-- (and KOReader's cover browser) ask a colour panel for its colour waveform.

local REFRESH_MODES = { clean = true, soft = true, host = true }

-- Always Clean (there is no choice in the settings, and one stored by a
-- test build is ignored). A._refresh_mode can still set another for testing.
function A.refreshMode()
    local v = A._refresh_mode or "clean"
    return REFRESH_MODES[v] and v or "clean"
end

local function hasEink()
    local ok, Device = pcall(require, "device")
    return (ok and Device and Device.hasEinkScreen and Device:hasEinkScreen()) and true or false
end

-- A colour panel, with Bookshelf's own "Color panel dithering" switch left on.
local function colourHint()
    local Screen = A.screen()
    if not (Screen.isColorEnabled and Screen:isColorEnabled()) then return false end
    local ok, Store = pcall(require, "lib/bookshelf_settings_store")
    if ok and Store and Store.nilOrTrue then
        local ok2, on = pcall(Store.nilOrTrue, "color_panel_dithering")
        if ok2 then return on and true or false end
    end
    return true
end

-- The full-screen view a card is in, or nil. While that view is open its
-- cells are the ones in bw._hero_cells. Bookshelf labels the ctx it hands to
-- on_tap "hero" on every surface, so taps cannot go by ctx.surface.
local function overlayOf(ctx, from_tap)
    if type(ctx) ~= "table" or ctx.preview then return nil end
    local fs = ctx.bw and ctx.bw._micro_fullscreen
    if type(fs) ~= "table" then return nil end
    -- A Bookshelf that names the surface says so outright. One that does not
    -- (ctx.surface missing) still only renders grid cells for the full-screen
    -- view while that view is registered, so its presence is the answer.
    if not from_tap and ctx.surface ~= nil and ctx.surface ~= "fullscreen" then return nil end
    return fs
end

-- One flashing refresh of the whole screen, now. Clears whatever ghosting
-- has built up. (Tapping the clock does this; so does Diagnostics.)
function A.cleanScreen()
    pcall(function()
        A.count("cleans")
        require("ui/uimanager"):setDirty(nil, "full")
    end)
end

-- Where this card's cell was last painted on screen, or nil.
local function cellRect(ctx)
    local bw = ctx and ctx.bw
    local id = ctx and ctx.entry and ctx.entry.id
    local rec = bw and bw._hero_cells and id and bw._hero_cells[id]
    local cell = rec and rec.group and rec.group[rec.idx]
    local d = cell and cell.dimen
    if d and d.x and d.y and d.w and d.w > 0 and d.h and d.h > 0 then return d:copy() end
    return nil
end

local _attended = setmetatable({}, { __mode = "k" })

-- Called from every render. The first time one of these cards is drawn in a
-- full-screen view, set that view up (once per view; it is a new object each
-- time it opens).
local _seen_views = setmetatable({}, { __mode = "k" })
function A.attend(ctx)
    local fs = overlayOf(ctx)
    -- a newly opened full-screen view starts on this month again, with the
    -- reading list looked at afresh and its first page drawn whole at once
    if fs and not _seen_views[fs] then
        _seen_views[fs] = true
        A.state.month_offset = 0
        D._reading = nil
        D.hurry(0.35)
    end
    if not fs or _attended[fs] then return end
    local mode = A.refreshMode()
    if mode == "host" or not hasEink() then return end
    _attended[fs] = true
    A.state.minute_seen = {}
    A.count("views")
    pcall(function()
        local UIManager = require("ui/uimanager")
        local hint = colourHint()
        local Screen = A.screen()
        A.note("full-screen view opened: refresh", mode, "colour hint", hint, "night", Screen.night_mode and true or false,
            "hw dither", Screen.hw_dithering and true or false, "surface", tostring(ctx.surface))
        if hint then
            fs.dithered = true
            -- The flag is viral: KOReader applies it to refreshes of whatever
            -- is on screen while a flagged widget is in the window stack. If a
            -- book opens over this view, take it off (as Bookshelf does for
            -- its shelf), and put it back whenever the view itself is painted.
            local paint = fs.paintTo
            if type(paint) == "function" then
                fs.paintTo = function(self, ...)
                    if A.refreshMode() ~= "host" then self.dithered = true end
                    return paint(self, ...)
                end
            end
            local showing = fs.onShowingReader
            fs.onShowingReader = function(self, ...)
                self.dithered = nil
                if showing then return showing(self, ...) end
            end
        end
        -- Closing puts back what was underneath with another quiet update,
        -- which would leave these cards showing through it.
        local closing = fs.onCloseWidget
        fs.onCloseWidget = function(self, ...)
            local r
            if closing then r = closing(self, ...) end
            if A.refreshMode() == "clean" then
                pcall(function()
                    -- Bookshelf skips its page-turn wipe once after a full
                    -- refresh on colour panels; tell it one is coming.
                    if type(self.bw) == "table" and self.bw._rebuild then self.bw._full_refresh_pending = true end
                    A.count("flashes")
                    UIManager:setDirty(nil, "full")
                end)
            end
            return r
        end
        if mode == "clean" then
            -- This render is part of building the view, just before Bookshelf
            -- shows it with a quiet "ui" update. KOReader merges overlapping
            -- requests and keeps the stronger, so this makes that one update a
            -- flashing one instead of adding a second.
            A.count("flashes")
            UIManager:setDirty(nil, "full", nil, hint or nil)
        end
    end)
end

-- A card that is already on screen is about to be redrawn (a tap changed it,
-- or the dashboard turned a page). flash = the whole card changes; turn = a
-- dashboard page turn (a ghost-clearing update in either mode, which KOReader
-- promotes to a flash every "Full refresh rate" updates).
local function inkRefresh(ctx, flash, turn)
    local id = ctx and ctx.entry and ctx.entry.id
    if id then A.state.own_redraw[id] = true end
    local fs = overlayOf(ctx, true)
    if not fs or not hasEink() then return end
    local mode = A.refreshMode()
    if mode == "host" then return end
    local kind
    if turn then
        kind = "partial"
    elseif flash then
        kind = (mode == "clean") and "full" or "partial"
    elseif mode == "clean" then
        kind = "partial"
    end
    if not kind then return end
    pcall(function()
        local UIManager = require("ui/uimanager")
        local region = cellRect(ctx)
        -- No cell of this card in the view (it is drawn somewhere else, such
        -- as a menu opened over the view): nothing here to refresh.
        if not region then return end
        A.count(kind == "full" and "flashes" or "reinks")
        local hint = fs.dithered and true or false
        -- As a function it is asked for after the redraw has been painted,
        -- and merges with Bookshelf's own update of the same cell.
        UIManager:setDirty(nil, function() return kind, region, hint end)
    end)
end

-- Bookshelf redraws clock cards once a minute and refreshes the whole cell,
-- which for the Dashboard is nearly the whole screen, although only the clock
-- changed. When a render is that redraw and nothing else:
--   * the refresh is narrowed to the clock's strip. Bookshelf takes the area
--     to refresh from the outgoing cell's `dimen` straight after this render
--     returns; that cell is about to be thrown away, so its dimen is swapped
--     for the strip. (A page with no clock gets a corner dot.)
--   * in "clean" mode a second, ghost-clearing update of the strip follows a
--     moment later, so the old digits do not linger.
-- W, H: size of the widget this render returns; y, h: the clock's strip in it
-- (nil when this card shows no clock right now).
function A.clockRefresh(ctx, W, H, y, h)
    local fs = overlayOf(ctx)
    local id = ctx and ctx.entry and ctx.entry.id
    if not fs or not id then return end
    local now, day = os.date("%H:%M"), os.date("%Y%m%d")
    local last = A.state.minute_seen[id]
    A.state.minute_seen[id] = { minute = now, day = day }
    local own = A.state.own_redraw[id]
    A.state.own_redraw[id] = nil
    -- Not the minute tick: first draw, a redraw this card asked for, the same
    -- minute again, or a new day (when much more than the clock changes).
    if own or not last or last.minute == now or last.day ~= day then return end
    local mode = A.refreshMode()
    if mode == "host" or not hasEink() then return end
    pcall(function()
        local bw = ctx.bw
        local rec = bw._hero_cells and bw._hero_cells[id]
        local old = rec and rec.group and rec.group[rec.idx]
        local d = old and old.dimen
        if not (d and d.x and d.y and d.w and d.w > 0 and d.h and d.h > 0) then return end
        local Geom = require("ui/geometry")
        local strip
        if y then
            -- the widget sits centred in its cell
            local top = d.y + floor((d.h - H) / 2) + floor(y) - 4
            local bottom = min(d.y + d.h, top + floor(h) + 8)
            top = max(d.y, top)
            if bottom - top < 8 then return end
            strip = Geom:new{ x = d.x, y = top, w = d.w, h = bottom - top }
        else
            strip = Geom:new{ x = d.x, y = d.y, w = 2, h = 2 }
        end
        if strip.h < d.h then
            old.dimen = strip
            A.count("narrowed")
        end
        if y and mode == "clean" then
            local region = strip:copy()
            local hint = fs.dithered and true or false
            local UIManager = require("ui/uimanager")
            -- Later rather than together: merged with Bookshelf's own update
            -- it would replace that quick one instead of following it.
            UIManager:scheduleIn(0.3, function()
                if bw._micro_fullscreen == fs then
                    A.count("reinks")
                    UIManager:setDirty(nil, "partial", region, hint)
                end
            end)
        end
    end)
end

function A.render(name, ctx)
    local def = P[name]
    A.attend(ctx)
    local w, h = boxFor(def, ctx)
    local c = buildPanel(name, makeEnv(name, ctx, w, h))
    -- painted once and kept (see the paint cache in init.lua); not the
    -- clocks, which are a new picture every minute
    c.cache_me = not def.tick
    declareRegions(ctx, c)
    if def.tick then A.clockRefresh(ctx, c.w, c.h, 0, c.h) end
    return c
end

-- ─── what a tap does ─────────────────────────────────────────────────────────
-- A card can be set (long-press > When tapped) to run any action instead of
-- its own: a KOReader action, a plugin, a menu entry, Bookshelf's own. Stored
-- as Bookshelf's action entry, { label, action | plugin | menu_path |
-- internal }, and run by Bookshelf's own runner, as its Action module does.
-- The card's real buttons (Continue, Details, the pager, + and -) keep their job.

function A.tapAction(name)
    local e = A.get(name .. "_tap_action", nil)
    if type(e) == "table" and (type(e.action) == "table" or type(e.plugin) == "table"
        or type(e.menu_path) == "table" or e.internal) then
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
        local ok, Exec = pcall(require, "lib/bookshelf_action_exec")
        if ok and type(Exec) == "table" and Exec.dispatch then
            local ok2, err = pcall(Exec.dispatch, entry, ctx and ctx.bw)
            if not ok2 then A.log("tap action failed:", err) end
        elseif type(entry.action) == "table" then
            local okd, Dispatcher = pcall(require, "dispatcher")
            if okd and Dispatcher then pcall(Dispatcher.execute, Dispatcher, entry.action) end
        end
    end)
end
A.runTapAction = runTapAction

function A.onTap(name, ctx)
    local def = P[name]
    local region0 = tapRegion(def, ctx)
    local custom = customTap(name, region0)
    if custom then return runTapAction(custom, ctx) end
    if not def.tap then return end
    local region = region0
    local ok, err = pcall(def.tap, makeEnv(name, ctx, 0, 0), region)
    if not ok then A.log(name, "tap failed:", err) end
    if def.keep and def.keep(region) then inkRefresh(ctx) end
end

function A.keepOpen(name, ctx)
    local def = P[name]
    local region = tapRegion(def, ctx)
    if customTap(name, region) then return false end
    if def.keep then return def.keep(region) and true or false end
    return false
end

function A.showSettings(name, ctx)
    S.card(name, ctx, function() return makeEnv(name, ctx, 0, 0) end)
end

--- The Bookshelf module spec for one panel.
function A.module(name)
    local def = P[name]
    if not def then error("almanac: no panel named " .. tostring(name)) end
    return {
        key = "alm_" .. name, -- stored in the reader's layout; never change it
        title = A.NAME .. " \xC2\xB7 " .. def.title,
        summary = def.summary,
        wants_minute_tick = def.tick or nil,
        render = function(ctx) return A.render(name, ctx) end,
        on_tap = function(ctx) return A.onTap(name, ctx) end,
        keep_open = function(ctx) return A.keepOpen(name, ctx) end,
        show_settings = function(ctx) return A.showSettings(name, ctx) end,
    }
end

-- ════════════════════════════════════════════════════════════════════════════
-- Dashboard: several panels as tabbed pages in one module
-- ════════════════════════════════════════════════════════════════════════════
-- Bookshelf's grid gives every row the same height and has no pages in the
-- full-screen view. Laying the panels out here instead lets each row have
-- its own height and puts a tab bar underneath.

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
    calendar = 0.9, cover_week = 0.3, quote2 = 0.25, quote3 = 0.25, quote4 = 0.25,
}
-- The order cards are offered in when editing a page.
A.DASH_CARDS = { "banner", "continue", "activity", "week_rings", "month_rings", "month_totals", "month_chart",
                 "when_read", "goal", "bookclub", "tbr", "genres", "year_covers", "week", "year_chart",
                 "year_time", "heatmap", "finished", "longest_year", "longest_month", "deadline",
                 "trends", "challenge", "forecast", "control", "compare",
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
    -- A theme with its own page colour: paint it, out to the edges of the cell.
    local c = A.canvas{ w = w, h = h, plain = true, bleed = page_look ~= nil, fill = page_look and page_bg or nil }
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
        c:frame(bx, by, bar_w, bar_h, bar_h / 2, bw_, page_fg, page_bg, page_bg)
        local inner = bar_w - bar_h * 0.5
        local cell = inner / #tabs
        local size = max(10, floor(bar_h * 0.36 * ts + 0.5))
        -- a tab name too long for its cell (longer words in some languages)
        -- makes every tab's text a little smaller rather than cutting it off
        local widest = 0
        for _, tab in ipairs(tabs) do widest = max(widest, c:text(tab.label, size, { bold = true }).w) end
        if widest > cell - 6 then size = max(10, floor(size * (cell - 10) / widest)) end
        local fill = A.shown(dark and th.gold or th.wine)
        local on_fill = A.shown(dark and th.ink or th.paper)
        for i, tab in ipairs(tabs) do
            local cx = bx + bar_h * 0.25 + (i - 0.5) * cell
            local active = tab.kind == "page" and tab.page == page_i
            local t_tab = c:text(tab.label, size, { bold = active, max_w = cell - 6,
                color = active and on_fill or A.mix(page_fg, page_bg, 0.38) })
            if active then
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
        local refresh = ownRefresh(ctx)
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
        local env = { w = w, h = head_h, ts = ts }
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
            local env = makeEnv(name, ctx, width, rh, { nested = true, slot = 1, page = page_look, page_heading = heading })
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
    summary = A.tr("All the %1 cards as tabbed pages. Best alone in the full-screen view.", A.NAME),
    -- Square modules get the card's full inner width, and one on its own
    -- fills the whole grid, which is what a page of panels needs.
    aspect = "square",
    hero_only = true,
    wants_minute_tick = true,
}

function Dashboard.render(ctx)
    local w = max(80, floor(tonumber(ctx.width) or 400))
    local h = (ctx.height and ctx.height > 0) and floor(ctx.height) or floor(w * 1.2)
    if ctx.max_height and h > ctx.max_height then h = floor(ctx.max_height) end
    if ctx.preview then
        return buildPanel("banner", makeEnv("banner", ctx, w, h))
    end
    A.attend(ctx)
    local ok, c = pcall(buildDashboard, ctx, w, h)
    if not ok then return errorCard("banner", w, h, c) end
    declareRegions(ctx, c)
    A.clockRefresh(ctx, w, h, c.clock_y, c.clock_h)
    return c
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

-- Without tap regions (an older Bookshelf) a tap anywhere turns the page.
local function dashRegion(ctx)
    local region = ctx and ctx.tapped_region
    if region == nil and A.state.regions_ok == false then
        local tabs = A.state.dash_tabs or {}
        local cur, first, nxt = tonumber(A.state.dash_page), nil, nil
        for i, t in ipairs(tabs) do
            if t.kind == "page" then
                first = first or i
                if nxt == true then nxt = i end
                if t.page == cur and nxt == nil then nxt = true end
            end
        end
        local i = (type(nxt) == "number" and nxt) or first
        return i and ("tab:" .. i) or nil
    end
    return region
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

return true
