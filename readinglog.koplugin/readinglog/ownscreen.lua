--[[
Reading Log's own windows: places a card is shown that are not a Simple UI
or Bookshelf module.

  The full-screen dashboard   the Dashboard's pages on a screen of their own,
                              from Tools > Reading Log, a gesture, or on its
                              own when KOReader starts. Needs no other app.
  Zen OS widgets              every card, the Mini dashboard and the Dashboard
                              as widgets for ZenOS's (and Zen UI's) Home.

Both are a Box: a card drawn at a given size, which takes taps (the card's
buttons), long-presses (its settings) and, for the Dashboard, swipes (the
next or previous page), and redraws itself in place when the card asks
(host.lua hands the redraw to ctx.own).
]]

local A = ...
local T = A._
local D = A.D
local S = A.S
local H = A.host

local floor, max, min = math.floor, math.max, math.min

local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")

local function UIManager() return require("ui/uimanager") end
local function Device() return require("device") end
local function Screen() return Device().screen end

local ELLIPSIS = "\xE2\x80\xA6"

-- ════════════════════════════════════════════════════════════════════════════
-- Box: one card (or the Dashboard) drawn at w × h
-- ════════════════════════════════════════════════════════════════════════════

local Box = InputContainer:extend{
    name = "readinglog_box",
    panel = nil,       -- "dashboard" or a card's name
    mod_id = nil,      -- whose settings (text size, card height) and covers
    pfx = "readinglog_",
    w = 0, h = 0,
    swipes = false,    -- the Dashboard: a swipe turns the page
    own = nil,         -- { openBook, showDetails } of the place it is shown in
    hold_extra = nil,  -- function(box, rows, close) adding buttons to the long-press menu
    on_refresh = nil,  -- function(box, kind, region): put a redraw on screen
    alive = nil,       -- function(box) -> still on screen?
    pass_top = false,  -- on a home screen: leave taps in KOReader's menu zone (the top of the screen) to it
}

function Box:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    local function range() return self.dimen end
    self.ges_events = {
        ReadingLogTap = { GestureRange:new{ ges = "tap", range = range } },
        ReadingLogHold = { GestureRange:new{ ges = "hold", range = range } },
    }
    if self.swipes then
        self.ges_events.ReadingLogSwipe = { GestureRange:new{ ges = "swipe", range = range } }
    end
    self.sctx = { _screen_widget = self, pfx = self.pfx }
    self:build()
end

-- Is it still on screen? (the minute tick and the redraws ask)
function Box:isActive()
    if self._closed then return false end
    if self.alive then
        local ok, yes = pcall(self.alive, self)
        return ok and yes and true or false
    end
    return true
end

function Box:build()
    local ctx = A.cardCtx(self.mod_id, self.sctx, self.w, self.h)
    local box = self
    ctx.close_button = self.close_button
    ctx.own = {
        repaint = function(o) box:repaint(o) end,
        close = self.close and function() box:close() end or nil,
        openBook = self.own and self.own.openBook or nil,
        showDetails = self.own and self.own.showDetails or nil,
    }
    self.ctx = ctx
    local name = self.panel
    -- (full screen there's no home screen behind: the style's page colour
    -- stays, whatever's set for home screens)
    A._full_render = self.close_button and true or nil
    local ok, c = A.drawFor(self.mod_id, function()
        if name == "dashboard" then return A.Dashboard.render(ctx) end
        return A.render(name, ctx)
    end)
    A._full_render = nil
    if not ok or not c then
        c = A.errorCard(name == "dashboard" and "dashboard" or name, self.w, self.h, c)
    end
    self[1] = c
    self._key = D.changeKey and D.changeKey() or nil
    self:watchCovers()
end

-- A home screen can keep its page while a book is read (ZenOS does) and
-- just put it back on screen: when it's painted, a card whose figures have
-- changed since it was drawn draws itself again, a moment later.
function Box:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if not (D.changeKey and self._key) or self._recheck then return end
    local ok, k = pcall(D.changeKey)
    if ok and k ~= self._key then
        self._key = k
        self._recheck = true
        local box = self
        UIManager():scheduleIn(0.3, function()
            box._recheck = nil
            if box:isActive() then box:repaint({}) end
        end)
    end
end

-- Covers still being made when the card was drawn: looked for every couple of
-- seconds (for a minute), and the card redrawn once they are in.
function Box:watchCovers()
    local set = D.cover_pending[self.mod_id]
    if not set or next(set) == nil or self._watching then return end
    self._watching = true
    local check = A.coverWatcher(self.mod_id)
    local tries = 0
    local box = self
    local function poll()
        tries = tries + 1
        if not box:isActive() then box._watching = false; return end
        local ok, done = pcall(check, nil, box.sctx)
        if (ok and done) or tries >= 30 then box._watching = false; return end
        UIManager():scheduleIn(2, poll)
    end
    UIManager():scheduleIn(2, poll)
end

--- Draw the card again and put it on screen.
---   o.turn   a Dashboard page turn (a quick ghost-clearing update)
---   o.flash  the whole card changed
---   o.strip  { y, h }: only this band changed (the clock)
function Box:repaint(o)
    o = o or {}
    if not self:isActive() then return end
    self:build()
    local d = self.dimen
    local region = d and Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h } or nil
    if o.strip and region then
        region = Geom:new{ x = d.x, y = d.y + floor(o.strip.y or 0), w = d.w, h = max(1, floor(o.strip.h or d.h)) }
    end
    local kind = o.turn and "partial" or o.flash and "flashui" or "ui"
    if self.on_refresh then
        local ok = pcall(self.on_refresh, self, kind, region)
        if ok then return end
    end
    UIManager():setDirty(self.window or self, function() return kind, region end)
end

function Box:regionAt(ges)
    local d = self.dimen
    if not (ges and ges.pos and d and d.x) then return nil end
    return A.hitRegion(self.ctx._regions, ges.pos.x - d.x, ges.pos.y - d.y)
end

-- Is this tap in the strip along the top of the screen that opens KOReader's
-- menu (Zen's settings)? A card at the top of a home screen leaves those to it.
function Box:inMenuZone(ges)
    if not (self.pass_top and ges and ges.pos) then return false end
    local zone
    if self.pass_top == "zen" then
        -- ZenOS opens its menu from the top 7% of the screen
        zone = { x = 0, y = 0, w = 1, h = 0.07 }
    else
        pcall(function() zone = G_defaults:readSetting("DTAP_ZONE_MENU") end)
    end
    if type(zone) ~= "table" then zone = { x = 0, y = 0, w = 1, h = 1 / 8 } end
    local Screen = require("device").screen
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local x, y = ges.pos.x, ges.pos.y
    return y >= sh * (zone.y or 0) and y < sh * ((zone.y or 0) + (zone.h or 1 / 8))
        and x >= sw * (zone.x or 0) and x < sw * ((zone.x or 0) + (zone.w or 1))
end

function Box:onReadingLogTap(_, ges)
    if self:inMenuZone(ges) then return false end
    local ctx = self.ctx
    ctx.tapped_region = self:regionAt(ges)
    local ok, err = pcall(function()
        if self.panel == "dashboard" then A.Dashboard.on_tap(ctx) else A.onTap(self.panel, ctx) end
    end)
    ctx.tapped_region = nil
    if not ok then A.log("tap failed:", err) end
    return true
end

-- The Dashboard: swipe left for the next page, right for the one before.
function Box:turnPage(step)
    local tabs = A.state.dash_tabs
    if type(tabs) ~= "table" or #tabs < 2 then return false end
    local at
    for i, t in ipairs(tabs) do if t.kind == "page" and t.page == A.state.dash_page then at = i end end
    local to = (at or 1) + step
    if to < 1 then to = #tabs elseif to > #tabs then to = 1 end
    local ctx = self.ctx
    ctx.tapped_region = "tab:" .. to
    pcall(A.Dashboard.on_tap, ctx)
    ctx.tapped_region = nil
    return true
end

function Box:onReadingLogSwipe(_, ges)
    local dir = ges and ges.direction
    if dir == "west" then return self:turnPage(1) end
    if dir == "east" then return self:turnPage(-1) end
    if self.on_swipe then return self.on_swipe(self, dir) end
    return false
end

-- Long-press: the settings of the card under the finger (on the Dashboard),
-- or of this card, and the Dashboard's own.
function Box:onReadingLogHold(_, ges)
    local region = self:regionAt(ges)
    local name = self.panel
    if name == "dashboard" then
        name = type(region) == "string" and region:match("^([%w_]+)|") or nil
        if name and type(A.panels[name]) ~= "table" then name = nil end
    end
    self:showMenu(name)
    return true
end

function Box:showMenu(card)
    local ButtonDialog = require("ui/widget/buttondialog")
    local ctx = self.ctx
    local dialog
    local function close() if dialog then UIManager():close(dialog) end end
    local rows = {}
    if card then
        local nested = self.panel == "dashboard"
        rows[#rows + 1] = { { text = A.tr("%1 settings", A.panels[card].title) .. ELLIPSIS, callback = function()
            close()
            S.card(card, ctx, function()
                return A.makeEnv(card, ctx, 0, 0, nested and { nested = true, slot = 1 } or nil)
            end)
        end } }
    end
    if self.panel == "dashboard" then
        rows[#rows + 1] = { { text = T("Dashboard settings") .. ELLIPSIS, callback = function()
            close()
            A.Dashboard.show_settings(ctx)
        end } }
    end
    rows[#rows + 1] = { { text = T("Text size") .. ELLIPSIS, callback = function()
        close()
        self:textSizeDialog()
    end } }
    if self.hold_extra then pcall(self.hold_extra, self, rows, close) end
    rows[#rows + 1] = { { text = T("Close"), callback = close } }
    dialog = ButtonDialog:new{
        title = card and A.panels[card].title or A.NAME,
        title_align = "center", buttons = rows,
    }
    UIManager():show(dialog)
end

-- The reader's Text size for this card here (or the whole Dashboard).
function Box:textSizeDialog()
    local box = self
    local key = A.screenKey(self.pfx, self.mod_id, "text")
    S.open(self.ctx, T("Text size"), function(api)
        local cur = A.textSizePct(box.pfx, box.mod_id)
        local opts = {}
        for _, v in ipairs({ 80, 90, 100, 115, 130 }) do opts[#opts + 1] = { v, v .. "%" } end
        return {
            S.radio(api, { opts[1], opts[2], opts[3] }, cur, function(v) A.set(key, v ~= A.TEXT_DEF and v or nil) end),
            S.radio(api, { opts[4], opts[5] }, cur, function(v) A.set(key, v) end),
        }
    end)
end

A.Box = Box

-- Every Box on screen now, so a theme change redraws them (H.redrawAll).
local _boxes = setmetatable({}, { __mode = "k" })
local function track(box) _boxes[box] = true end
function A.redrawOwn()
    for box in pairs(_boxes) do
        if box:isActive() then pcall(box.repaint, box, { flash = true }) end
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- The full-screen dashboard
-- ════════════════════════════════════════════════════════════════════════════

local FULL_ID = A.ID_PREFIX .. "full"

local Window = Box:extend{
    name = "readinglog_dashboard",
    covers_fullscreen = true,
    panel = "dashboard",
    mod_id = FULL_ID,
    pfx = "readinglog_full_",
    swipes = true,
    close_button = true,
}

function Window:init()
    local Sc = Screen()
    self.w, self.h = Sc:getWidth(), Sc:getHeight()
    if Device():hasKeys() then
        self.key_events = { Close = { { Device().input.group.Back } } }
    end
    -- a book opened from a card: close first, then open it
    self.own = {
        openBook = function(fp)
            self:close()
            UIManager():nextTick(function() require("apps/reader/readerui"):showReader(fp) end)
        end,
    }
    self.on_swipe = function(box, dir)
        if dir == "south" then box:close() return true end
        return false
    end
    self.hold_extra = function(box, rows, close)
        rows[#rows + 1] = { { text = T("Close the dashboard"), callback = function() close(); box:close() end } }
    end
    Box.init(self)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    track(self)
end

function Window:close()
    if self._closed then return end
    self._closed = true
    if A._full == self then A._full = nil end
    UIManager():close(self, "flashui")
end

function Window:onClose() self:close() return true end
-- the gesture again, with the dashboard in front: close it
function Window:onReadingLogDashboard() self:close() return true end

-- The screen turned: draw it again at the new size.
function Window:onSetDimensions()
    local Sc = Screen()
    self.w, self.h = Sc:getWidth(), Sc:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self:build()
    UIManager():setDirty(self, "full")
end

function Window:onCloseWidget()
    self._closed = true
    if A._full == self then A._full = nil end
end

--- Open the full-screen dashboard (or bring the open one back to the front).
function A.openDashboard()
    if A._full and not A._full._closed then
        UIManager():setDirty(A._full, "full")
        return A._full
    end
    A.state.month_offset = 0
    A.state.year_offset = 0
    D.hurry(0.6)
    local win = Window:new{}
    A._full = win
    UIManager():show(win, "full")
    -- what the other pages need, worked out while the first one is read, so
    -- turning to them is quick (most of all on a slower e-reader)
    UIManager():scheduleIn(1.5, function()
        if A.dashboardOpen() then D.warm({ "year", "lengths", "sessions", "quote", "author_time", "cover_month" }) end
    end)
    return win
end

function A.closeDashboard()
    if A._full then A._full:close() end
end

function A.dashboardOpen() return A._full ~= nil and not A._full._closed end

-- ════════════════════════════════════════════════════════════════════════════
-- ZenOS (and Zen UI) Home widgets
-- ════════════════════════════════════════════════════════════════════════════
-- ZenOS lets plugins add widgets to its Home: a builder that returns a widget
-- of the size it is given, and a height in tenths of the Home (10 units on a
-- 4:3 screen; it lets the reader turn on only what fits). New widgets start
-- off: the reader turns them on in Zen Settings > Home > Widgets.

local ZEN_PREFIX = "readinglog."

-- The cards offered: the Dashboard, the Mini dashboard, then every card
-- (not the ornaments, which draw no card of their own).
local function zenCards()
    local out = {}
    for _, name in ipairs(A.MODULE_ORDER) do
        local def = A.panels[name]
        if name == "dashboard" or (type(def) == "table" and not def.bare) then out[#out + 1] = name end
    end
    return out
end

-- How many tenths of the Home a card takes: the reader's choice, else the
-- share of a page it takes on the Dashboard. The Dashboard starts at 9, not
-- the whole Home: Zen keeps one of its own widgets on at all times (the
-- smallest take a tenth), so a 10 could never be switched on; once it's on,
-- that widget can go and the Dashboard can be set to 10/10.
A.ZEN_SIZES = { 2, 3, 4, 5, 6, 8, 9, 10 }
local ZEN_OWN = { dashboard = 9, mini = 2, calendar = 8, trends = 6 }
function A.zenUnits(name)
    local v = tonumber(A.get("zen_units_" .. name, nil))
    if v then return A.clamp(floor(v), 1, 10) end
    if ZEN_OWN[name] then return ZEN_OWN[name] end
    local wgt = A.DASH_WEIGHT[name] or 0.3
    return A.clamp(floor(wgt * 10 + 0.5), 2, 6)
end

local function zenRegisterFn()
    return rawget(_G, "__ZENOS_REGISTER_HOME_ITEM") or rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")
end

function A.zenAvailable() return zenRegisterFn() ~= nil end

-- The newest widget of each card: an older one was thrown away when the Home
-- was built again, and must not redraw.
local _zen_latest = {}

local function homeShown()
    local RUI = package.loaded["apps/reader/readerui"]
    if RUI and RUI.instance then return false end
    return true
end

local function zenBuilder(name)
    local def_title = name == "dashboard" and A._("Dashboard") or A.panels[name].title
    return function(zctx)
        local w = max(40, floor(tonumber(zctx.width) or 400))
        local h = max(40, floor(tonumber(zctx.height) or 200))
        local box
        box = Box:new{
            panel = name,
            mod_id = A.ID_PREFIX .. "zen_" .. name,
            pfx = "zen_",
            w = w, h = h,
            swipes = name == "dashboard",
            pass_top = "zen",
            own = {
                openBook = type(zctx.openBook) == "function" and function(fp) zctx.openBook(fp) end or nil,
                showDetails = type(zctx.showBookMenu) == "function" and function(fp)
                    if not zctx.showBookMenu(fp) then error("no book menu") end
                end or nil,
            },
            alive = function(b) return _zen_latest[name] == b and homeShown() end,
            on_refresh = function(b, kind, region)
                if type(zctx.refreshRow) ~= "function" then error("no refreshRow") end
                -- Zen repaints the Home and puts it on screen in one go; a
                -- second, ghost-clearing update only when the whole card
                -- changed (not on a page turn: one screen update is quicker,
                -- above all on a slower e-reader)
                zctx.refreshRow(region)
                if kind == "flashui" then
                    UIManager():setDirty(nil, function() return kind, region end)
                end
            end,
            hold_extra = function(b, rows, close)
                rows[#rows + 1] = { { text = T("Height on Home") .. ELLIPSIS, callback = function()
                    close()
                    A.zenSizeDialog(name, def_title)
                end } }
            end,
        }
        _zen_latest[name] = box
        track(box)
        if name == "dashboard" then
            -- what the other pages need, worked out while the first is read,
            -- so turning to them is quick (once in a while, not on every redraw)
            local now = os.time()
            if not A._zen_warmed or now - A._zen_warmed > 600 then
                A._zen_warmed = now
                UIManager():scheduleIn(1.5, function()
                    if box:isActive() then D.warm({ "year", "lengths", "sessions", "quote", "author_time", "cover_month" }) end
                end)
            end
        end
        return box
    end
end

function A.zenSizeDialog(name, title)
    S.open(nil, title, function(api)
        local cur = A.zenUnits(name)
        local opts = {}
        for _, v in ipairs(A.ZEN_SIZES) do opts[#opts + 1] = { v, A.tr("%1/10", v) } end
        local rows = { S.header(T("Height on Zen's Home, in tenths of the screen")) }
        local function pick(v)
            A.set("zen_units_" .. name, v)
            A.zenRegister(true)
        end
        rows[#rows + 1] = S.radio(api, { opts[1], opts[2], opts[3], opts[4] }, cur, pick)
        rows[#rows + 1] = S.radio(api, { opts[5], opts[6], opts[7], opts[8] }, cur, pick)
        rows[#rows + 1] = S.header(T("Zen only shows the widgets that fit on its Home."))
        return rows
    end)
end

--- Tell ZenOS about every card. force: again, with the sizes changed.
function A.zenRegister(force)
    local reg = zenRegisterFn()
    if not reg then return false end
    if A._zen_with == reg and not force then return true end
    A._zen_with = reg
    for _, name in ipairs(zenCards()) do
        local title = name == "dashboard" and A._("Dashboard") or A.panels[name].title
        local ok, err = pcall(reg, ZEN_PREFIX .. name, zenBuilder(name), {
            label = A.NAME .. " \xC2\xB7 " .. title,
            size = A.zenUnits(name),
        })
        if not ok then A.log("zen: could not add", name, err) end
    end
    A.note("added", #zenCards(), "widgets to ZenOS's Home")
    return true
end

return true
