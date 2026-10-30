--[[
Reading Log settings.

Each card's options are written once, as rows (S.header / S.radio / S.input /
S.pick / S.date), and shown two ways:
  * with Simple UI: as Simple UI menu items, in the module's long-press settings
    (S.cardMenu, S.dashboardMenu): a header and the radio row after it become
    one choice with its value on the right, an input a row that opens a text
    or number prompt, and so on;
  * as dialogs: with Bookshelf, every card's long-press "Module settings";
    with Simple UI, the few flows that are dialogs by nature (the Dashboard's
    page editor, the book club's picks, a month's books).
After the card's own options come the rows every card shares: what a tap on
it does, its colour, its height, and "Look and colours" (theme, accents, week
start), which applies to all the cards at once.
]]

local A = ...
local T = A._
local D = A.D
local P = A.panels
local S = {}
A.S = S

local tr = T
S.tr = T

local CHECK = "\xE2\x9C\x93 "
local ELLIPSIS = "\xE2\x80\xA6"

-- Redraw the card these settings belong to (in a settings menu: the menu and
-- the screen it was opened on).
local function reload(ctx)
    D.invalidate()
    A.host.repaint(ctx)
end
S.reload = reload

-- Redraw every card: a theme or accent change touches all of them.
local function reloadAll(ctx)
    D.invalidate()
    A.host.redrawAll(ctx)
    if ctx and ctx.menu_refresh then pcall(ctx.menu_refresh) end
end
S.reloadAll = reloadAll

-- A look shared by several cards (all the quote cards, both cover
-- calendars, every chart): one setting, and every card redraws.
local function sharedLook(api, ctx, title, key, options)
    return S.header(title), S.radio(api, options, A.get(key, options[1][1]),
        function(v) A.set(key, v ~= options[1][1] and v or nil); reloadAll(ctx) end)
end
local function chartLook(api, ctx)
    return sharedLook(api, ctx, T("Charts, on every card"), "chart_look",
        { { "plain", T("Plain") }, { "cozy", T("Book spines and hearts") }, { "neon", T("Neon") }, { "candles", T("Candles") } })
end

-- S.open(ctx, title, rows_fn, all): rows_fn(api) returns ButtonDialog rows.
--   api.again()   show this dialog again (nothing changed)
--   api.changed() redraw the card (every card when `all`), then show this dialog again
--   api.close()
function S.open(ctx, title, rows_fn, all)
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")
    local dialog
    local api = {}
    function api.close() if dialog then UIManager:close(dialog) end end
    function api.again() api.close(); S.open(ctx, title, rows_fn, all) end
    function api.changed()
        api.close()
        if all then reloadAll(ctx) else reload(ctx) end
        S.open(ctx, title, rows_fn, all)
    end
    local rows = rows_fn(api)
    rows[#rows + 1] = { { text = T("Close"), callback = function() api.close() end } }
    dialog = ButtonDialog:new{
        title = title, title_align = "center", width_factor = 0.86, buttons = rows,
    }
    UIManager:show(dialog)
end

function S.header(text) return { { text = text, enabled = false }, _sui = { kind = "header", text = text } } end

-- A row of radio buttons. options = { { value, label }, ... }
function S.radio(api, options, current, on_pick)
    local row = { _sui = { kind = "radio", options = options, current = current, on_pick = on_pick } }
    for _, opt in ipairs(options) do
        local active = opt[1] == current
        row[#row + 1] = {
            text = (active and CHECK or "") .. tostring(opt[2]),
            callback = function()
                if active then return end
                on_pick(opt[1])
                api.changed()
            end,
        }
    end
    return row
end

local function shorten(v, n)
    v = tostring(v)
    if #v > n then return v:sub(1, n - 1) .. ELLIPSIS end
    return v
end

-- "Label: value" row that opens a text or number prompt.
-- o = { hint=, number=bool, min=, max=, empty_label=, description= }
function S.input(api, label, value, on_save, o)
    o = o or {}
    local shown = (value == nil or value == "") and (o.empty_label or T("not set"))
        or shorten((tostring(value):gsub("\n", " / ")), 28)
    return { _sui = { kind = "input", label = label, value = value, on_save = on_save, o = o }, {
        text = label .. ": " .. shown,
        callback = function()
            api.close()
            local UIManager = require("ui/uimanager")
            local InputDialog = require("ui/widget/inputdialog")
            local input
            input = InputDialog:new{
                title = label,
                description = o.description,
                input = value ~= nil and tostring(value) or "",
                input_hint = o.hint,
                input_type = o.number and "number" or nil,
                -- several lines (the letter board's text)
                allow_newline = o.multiline or nil,
                buttons = { {
                    { text = T("Cancel"), id = "close", callback = function()
                        UIManager:close(input)
                        api.again()
                    end },
                    { text = T("Save"), is_enter_default = true, callback = function()
                        local txt = input:getInputText() or ""
                        UIManager:close(input)
                        if o.number then
                            local n = tonumber(txt)
                            if n then
                                n = math.floor(n)
                                if o.min and n < o.min then n = o.min end
                                if o.max and n > o.max then n = o.max end
                                on_save(n)
                            end
                        else
                            on_save((txt:gsub("^%s+", ""):gsub("%s+$", "")))
                        end
                        api.changed()
                    end },
                } },
            }
            UIManager:show(input)
            input:onShowKeyboard()
        end,
    } }
end

-- "Label: 4 Oct 2026" row that opens KOReader's date picker.
function S.date(api, label, value, on_save)
    local y, m, d = A.parseYmd(value)
    local shown = y and (d .. " " .. A.date("%b", os.time{ year = y, month = m, day = d, hour = 12 }) .. " " .. y) or T("not set")
    return { _sui = { kind = "date", label = label, value = value, on_save = on_save, shown = shown }, {
        text = label .. ": " .. shown,
        callback = function()
            api.close()
            local UIManager = require("ui/uimanager")
            local DateTimeWidget = require("ui/widget/datetimewidget")
            if not y then
                local t = os.date("*t")
                y, m, d = t.year, t.month, t.day
            end
            UIManager:show(DateTimeWidget:new{
                year = y, month = m, day = d,
                ok_text = tr("Set date"),
                title_text = label,
                callback = function(t)
                    on_save(string.format("%04d-%02d-%02d", t.year, t.month, t.day))
                    api.changed()
                end,
                cancel_callback = function() api.again() end,
            })
        end,
    } }
end

-- "Label: value" row that opens a list to pick one from.
-- options = { { value, label }, ... }
function S.pick(ctx, api, label, options, current, on_pick)
    local shown = T("not set")
    for _, opt in ipairs(options) do
        if opt[1] == current then shown = shorten(opt[2], 28) end
    end
    return { _sui = { kind = "pick", label = label, options = options, current = current, on_pick = on_pick }, {
        text = label .. ": " .. shown,
        callback = function()
            api.close()
            S.open(ctx, label, function(sub)
                local rows = {}
                for _, opt in ipairs(options) do
                    rows[#rows + 1] = { {
                        text = ((opt[1] == current) and CHECK or "") .. shorten(opt[2], 44),
                        callback = function()
                            on_pick(opt[1])
                            sub.close()
                            reload(ctx)
                            api.again()
                        end,
                    } }
                end
                if #rows == 0 then rows[1] = S.header(T("Nothing to choose from yet")) end
                -- replace the sub-dialog's own Close with "back to the card's settings"
                rows[#rows + 1] = { { text = T("Back"), callback = function() sub.close(); api.again() end } }
                return rows
            end)
        end,
    } }
end

-- "Label: a, b" row that opens a list to tick any number from (none = any).
-- options = { { value, label }, ... }; current = list of values.
function S.multi(ctx, api, label, options, current, on_change, any_label)
    current = type(current) == "table" and current or {}
    local shown = #current == 0 and (any_label or "any") or shorten(table.concat(current, ", "), 28)
    return { _sui = { kind = "multi", label = label, options = options, current = current, on_change = on_change,
                      any_label = any_label }, {
        text = label .. ": " .. shown,
        callback = function()
            api.close()
            local function show()
                S.open(ctx, label, function(sub)
                    local on = {}
                    for _, v in ipairs(current) do on[v:lower()] = true end
                    local rows, line = {}, {}
                    rows[#rows + 1] = { { text = ((#current == 0) and CHECK or "") .. (any_label or T("Any")), callback = function()
                        current = {}
                        on_change(nil)
                        sub.close(); show()
                    end } }
                    for _, opt in ipairs(options) do
                        local v = opt[1]
                        line[#line + 1] = {
                            text = (on[v:lower()] and CHECK or "") .. shorten(opt[2], 26),
                            callback = function()
                                local list = {}
                                for _, cur in ipairs(current) do if cur:lower() ~= v:lower() then list[#list + 1] = cur end end
                                if not on[v:lower()] then list[#list + 1] = v end
                                current = list
                                on_change(#list > 0 and list or nil)
                                sub.close(); show()
                            end,
                        }
                        if #line == 2 then rows[#rows + 1] = line; line = {} end
                    end
                    if #line > 0 then rows[#rows + 1] = line end
                    if #options == 0 then rows[#rows + 1] = S.header(T("Nothing to choose from yet")) end
                    rows[#rows + 1] = { { text = T("Back"), callback = function() sub.close(); reload(ctx); api.again() end } }
                    return rows
                end)
            end
            show()
        end,
    } }
end

-- ─── per-card rows ───────────────────────────────────────────────────────────


local function collectionOptions(with_none)
    local names = D.collections()
    local out = {}
    if with_none then out[1] = { "", with_none } end
    for _, n in ipairs(names) do out[#out + 1] = { n, D.collectionLabel(n) } end
    return out
end

local ROWS = {}

ROWS.banner = function(env, api)
    return {
        S.header(T("Style")),
        S.radio(api, { { "heading", T("Heading") }, { "glance", T("At a glance") }, { "classic", T("Classic") } },
            env.cfg("style", "heading"), function(v) env.setcfg("style", v) end),
        S.input(api, T("Top line"), env.cfg("line1", ""), function(v) env.setcfg("line1", v) end,
            { hint = T("e.g. Sam's"), empty_label = T("(hidden)") }),
        S.input(api, T("Bottom line"), env.cfg("line2", ""), function(v) env.setcfg("line2", v) end,
            { hint = T("e.g. My Library"), empty_label = T("(hidden)") }),
    }
end

ROWS.continue = function(env, api)
    return {
        S.header(T("How many books to cycle through")),
        S.radio(api, { { 3, "3" }, { 5, "5" }, { 8, "8" } }, tonumber(env.cfg("count", 5)) or 5,
            function(v) env.setcfg("count", v) end),
        S.header(T("Look")),
        S.radio(api, { { "classic", T("Classic") }, { "scrapbook", T("Scrapbook") }, { "hud", T("HUD") }, { "framed", T("Framed") } }, env.cfg("look", "classic"),
            function(v) env.setcfg("look", v ~= "classic" and v or nil) end),
    }
end

ROWS.timeline = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "sky", T("Sky") }, { "skyline", T("Skyline") }, { "celestial", T("Celestial") } }, env.cfg("look", "plain"),
            function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

ROWS.trends = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "notes", T("Sticky notes") }, { "diagnostics", T("Diagnostics") }, { "catalogue", T("Catalogue cards") } }, env.cfg("look", "plain"),
            function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

-- Default, Cute or Cyber: every card's look of that style at once. Each card
-- can still be changed on its own afterwards. Cyber also puts on the Cyber
-- theme (black, neon accents); the theme and accents from before come back
-- when another style is chosen.
local CUTE = { { "ring_shape", "hearts" }, { "challenge_style", "flower" }, { "bookclub_look", "garden" },
    { "goal_look", "jar" }, { "quote_look", "paper" }, { "calendar_look", "polaroid" },
    { "continue_look", "scrapbook" }, { "trends_look", "notes" }, { "chart_look", "cozy" },
    { "timeline_look", "sky" }, { "forecast_look", "calendar" }, { "device_look", "hearts" },
    { "books_year_look", "heart" }, { "streak_flame_look", "heart" }, { "letter_board_look", "lightbox" },
    { "pages_today_look", "note" }, { "pages_turned_look", "worm" },
    { "total_pages_look", "worm" } }
local CYBER = { { "ring_shape", "segments" }, { "challenge_style", "neural" }, { "bookclub_look", "stream" },
    { "goal_look", "terminal" }, { "quote_look", "terminal" }, { "calendar_look", "brackets" },
    { "continue_look", "hud" }, { "trends_look", "diagnostics" }, { "chart_look", "neon" },
    { "timeline_look", "skyline" }, { "forecast_look", "countdown" }, { "device_look", "monitor" },
    { "books_year_look", "neon" }, { "streak_flame_look", "neon" }, { "letter_board_look", "led" },
    { "pages_today_look", "counter" }, { "pages_turned_look", "counter" },
    { "total_pages_look", "counter" } }
local ACADEMIA = { { "ring_shape", "watch" }, { "challenge_style", "chess" }, { "bookclub_look", "ledger" },
    { "goal_look", "globe" }, { "quote_look", "manuscript" }, { "calendar_look", "gilt" },
    { "continue_look", "framed" }, { "trends_look", "catalogue" }, { "chart_look", "candles" },
    { "timeline_look", "celestial" }, { "forecast_look", "almanac" }, { "year_covers_look", "gallery" },
    { "device_look", "candle" }, { "books_year_look", "plaque" }, { "streak_flame_look", "candle" },
    { "letter_board_look", "chalk" }, { "pages_today_look", "card" }, { "pages_turned_look", "book" },
    { "total_pages_look", "ledger" } }
A.CUTE, A.CYBER, A.ACADEMIA = CUTE, CYBER, ACADEMIA
-- Looks added to a style after it first came out. A reader who already has
-- that style on gets the new look too (once), so the style stays whole
-- rather than turning "mixed" with an update.
local ADDED_LATER = { device_look = true, books_year_look = true, streak_flame_look = true,
    letter_board_look = true, pages_today_look = true, pages_turned_look = true,
    total_pages_look = true }
local function fillAddedLooks()
    -- (2: the ornaments' looks joined after the first round; 3: Pages
    -- turned; 4: Lifetime pages)
    if (tonumber(A.get("looks_filled", 0)) or 0) >= 4 then return end
    for _, list in ipairs({ CUTE, CYBER, ACADEMIA }) do
        local all = true
        for _, kv in ipairs(list) do
            if not ADDED_LATER[kv[1]] and A.get(kv[1]) ~= kv[2] then all = false break end
        end
        if all then
            for _, kv in ipairs(list) do
                if ADDED_LATER[kv[1]] and A.get(kv[1]) == nil then A.set(kv[1], kv[2]) end
            end
        end
    end
    A.set("looks_filled", 4)
end
A.fillAddedLooks = fillAddedLooks
pcall(fillAddedLooks)
-- the styles that come with a theme of their own
local STYLE_THEME = { cyber = "cyber", academia = "academia" }
local function countOn(list)
    local on = 0
    for _, kv in ipairs(list) do if A.get(kv[1]) == kv[2] then on = on + 1 end end
    return on
end
function A.styleNow()
    pcall(fillAddedLooks)
    local cute, cyber, acad = countOn(CUTE), countOn(CYBER), countOn(ACADEMIA)
    if cute == #CUTE then return "cute" end
    if cyber == #CYBER then return "cyber" end
    if acad == #ACADEMIA then return "academia" end
    if cute == 0 and cyber == 0 and acad == 0 then return "default" end
    return "mixed"
end
function A.setStyle(v)
    local list = (v == "cute" and CUTE) or (v == "cyber" and CYBER) or (v == "academia" and ACADEMIA) or nil
    for _, l in ipairs({ CUTE, CYBER, ACADEMIA }) do for _, kv in ipairs(l) do A.set(kv[1], nil) end end
    if list then for _, kv in ipairs(list) do A.set(kv[1], kv[2]) end end
    local own = STYLE_THEME[v]
    if own then
        -- the theme and accents from before (kept when going from one such
        -- style straight to the other)
        if not STYLE_THEME[A.themeId()] then
            A.set("style_before", { theme = A.get("theme", nil), accent = A.get("accent", nil), accent2 = A.get("accent2", nil) })
        end
        A.set("theme", own)
        A.set("accent", nil)
        A.set("accent2", nil)
    else
        -- leaving Cyber or Dark Academia: the theme and accents from before
        -- it, if the style picked the theme (one picked by hand stays)
        local before = A.get("style_before", nil)
        if type(before) == "table" and STYLE_THEME[A.themeId()] then
            A.set("theme", before.theme)
            A.set("accent", before.accent)
            A.set("accent2", before.accent2)
        end
        if before ~= nil then A.set("style_before", nil) end
    end
end
function S.styleRows(api, ctx)
    local now = A.styleNow()
    return {
        S.header(T("Style")),
        S.radio(api, { { "default", T("Default") }, { "cute", T("Cute") }, { "cyber", T("Cyber") }, { "academia", T("Dark Academia") } }, now,
            function(v) A.setStyle(v); reloadAll(ctx) end),
        S.header((now == "mixed" and T("Some cards have a look of their own."))
            or (now == "cyber" and T("Cyber turns on every card's cyber look at once, on a black page."))
            or (now == "academia" and T("Dark Academia turns on every card's dark academia look at once, on parchment."))
            or T("Cute turns on every card's cute look at once.")),
    }
end

-- Rings or hearts: one choice for every rings card (Activity, Week and Month
-- rings and the Mini dashboard), so changing it redraws them all.
function S.shapeRows(api, ctx)
    local function all_(fn) return function(v) fn(v); reloadAll(ctx) end end
    local all = api
    local cur = A.get("ring_shape", "rings")
    local pick = all_(function(v) A.set("ring_shape", v ~= "rings" and v or nil) end)
    local first = S.radio(all, { { "rings", T("Rings") }, { "hearts", T("Hearts") }, { "segments", T("Segments") } }, cur, pick)
    local second = S.radio(all, { { "dial", T("Brass dial") }, { "watch", T("Pocket watch") } }, cur, pick)
    -- as a menu, one choice of all five
    first._sui.options = { { "rings", T("Rings") }, { "hearts", T("Hearts") }, { "segments", T("Segments") },
        { "dial", T("Brass dial") }, { "watch", T("Pocket watch") } }
    second._sui = { kind = "skip" }
    local rows = { S.header(T("Shape, for every rings card")), first, second }
    if A.hearts() then
        rows[#rows + 1] = S.header(T("Heart colours"))
        rows[#rows + 1] = S.radio(all, { { "pink", T("Pink") }, { "card", T("Card colours") } }, A.get("heart_colors", "pink"),
            all_(function(v) A.set("heart_colors", v ~= "pink" and v or nil) end))
        rows[#rows + 1] = S.header(T("A broken heart when you miss"))
        rows[#rows + 1] = S.radio(all, { { "any", T("Either goal") }, { "both", T("Both goals") } }, A.get("heart_broken", "any"),
            all_(function(v) A.set("heart_broken", v ~= "any" and v or nil) end))
    end
    return rows
end

local function addAll(rows, more)
    for _, r in ipairs(more) do rows[#rows + 1] = r end
    return rows
end

ROWS.activity = function(env, api, ctx)
    local rows = {
        S.input(api, T("Pages a day"), env.cfg("page_goal", 30), function(v) env.setcfg("page_goal", v) end,
            { number = true, min = 1, max = 2000 }),
        S.input(api, T("Minutes a day"), D.dailyMinutesGoal(), function(v) D.setDailyMinutesGoal(v) end,
            { number = true, min = 1, max = A.host.GOALS.daily_max, description = A.host.GOALS.daily_note }),
    }
    if not A.hearts() then
        rows[#rows + 1] = S.header(T("Streak ring fills at"))
        rows[#rows + 1] = S.radio(api, { { 7, T("7 days") }, { 14, T("14 days") }, { 30, T("30 days") } },
            tonumber(env.cfg("streak_goal", 7)) or 7, function(v) env.setcfg("streak_goal", v) end)
    end
    return addAll(rows, S.shapeRows(api, ctx))
end

ROWS.goal = function(env, api)
    local target, other = D.yearGoal()
    local cur = env.cfg("look", "number")
    local pick = function(v) env.setcfg("look", v ~= "number" and v or nil) end
    local first = S.radio(api, { { "number", T("Number") }, { "jar", T("Jar of hearts") }, { "shards", T("Shards") } }, cur, pick)
    local second = S.radio(api, { { "terminal", T("Terminal") }, { "globe", T("Globe") } }, cur, pick)
    -- as a menu, one choice of all five
    first._sui.options = { { "number", T("Number") }, { "jar", T("Jar of hearts") }, { "shards", T("Shards") },
        { "terminal", T("Terminal") }, { "globe", T("Globe") } }
    second._sui = { kind = "skip" }
    local rows = {
        S.input(api, T("Books this year"), target, function(v) D.setYearGoal(v) end,
            { number = true, min = 1, max = A.host.GOALS.year_max, description = A.host.GOALS.year_note }),
        S.header(T("Look")),
        first, second,
    }
    if A.host.ownOtherBooks() then
        rows[#rows + 1] = S.input(api, T("Read outside KOReader"), other, function(v) D.setOtherBooks(v) end,
            { number = true, min = 0, max = 1000, description = T("Paper books, audiobooks or another reader. Added to this year's count.") })
    end
    return rows
end

ROWS.books_year = function(env, api)
    return {
        S.input(api, T("Title"), env.cfg("title", ""), function(v) env.setcfg("title", v ~= "" and v or nil) end,
            { hint = T("e.g. My library"), empty_label = T("(none)") }),
        S.header(T("Look")),
        S.radio(api, { { "stack", T("Book stack") }, { "heart", T("Heart sticker") }, { "neon", T("Glitch billboard") }, { "plaque", T("Brass plaque") } },
            env.cfg("look", "stack"), function(v) env.setcfg("look", v ~= "stack" and v or nil) end),
    }
end

ROWS.streak_flame = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "flame", T("Flame") }, { "heart", T("Heart on fire") }, { "neon", T("Neon flame") }, { "candle", T("Candle") } },
            env.cfg("look", "flame"), function(v) env.setcfg("look", v ~= "flame" and v or nil) end),
    }
end

ROWS.letter_board = function(env, api)
    local text = env.cfg("text", nil)
    return {
        S.input(api, T("Words"), text or T("So many books, so little time"), function(v)
            env.setcfg("text", (v ~= "" and v ~= T("So many books, so little time")) and v or nil)
        end,
            { multiline = true, description = T("Start a new line wherever you want the board to break.") }),
        S.header(T("Stars")),
        S.radio(api, { { true, T("Shown") }, { false, T("Hidden") } }, env.cfg("stars", true) ~= false,
            function(v)
                -- (false kept as false: "v and nil or false" would store nothing)
                if v == false then env.setcfg("stars", false) else env.setcfg("stars", nil) end
            end),
        S.header(T("Look")),
        S.radio(api, { { "felt", T("Felt letter board") }, { "lightbox", T("Light box") }, { "led", T("LED marquee") }, { "chalk", T("Chalkboard") } },
            env.cfg("look", "felt"), function(v) env.setcfg("look", v ~= "felt" and v or nil) end),
    }
end

ROWS.pages_today = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "receipt", T("Receipt") }, { "note", T("Sticky note") }, { "counter", T("Heart monitor") }, { "card", T("Library card") } },
            env.cfg("look", "receipt"), function(v) env.setcfg("look", v ~= "receipt" and v or nil) end),
    }
end

ROWS.pages_turned = function(env, api)
    return {
        S.header(T("Count")),
        S.radio(api, { { "all", T("All time") }, { "year", T("This year") } }, env.cfg("period", "all"),
            function(v) env.setcfg("period", v ~= "all" and v or nil) end),
        S.header(T("Look")),
        S.radio(api, { { "flip", T("Flip counter") }, { "worm", T("Pink banner") }, { "counter", T("Data counter") }, { "book", T("Open book") } },
            env.cfg("look", "flip"), function(v) env.setcfg("look", v ~= "flip" and v or nil) end),
    }
end

ROWS.total_pages = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "worm", T("Hearts") }, { "counter", T("Data counter") }, { "ledger", T("Ledger") } },
            env.cfg("look", "plain"), function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

ROWS.device = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "hearts", T("Hearts") }, { "monitor", T("System monitor") }, { "candle", T("Candle") } },
            env.cfg("look", "plain"), function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

ROWS.tbr = function(env, api, ctx)
    local coll = P.tbr.collection(env)
    return {
        S.pick(ctx, api, T("Collection"), collectionOptions(), coll, function(v) env.setcfg("coll", v) end),
        S.input(api, T("Title"), env.cfg("title", ""), function(v) env.setcfg("title", v) end,
            { hint = T("e.g. October TBR"), empty_label = T("(month) TBR") }),
        S.input(api, T("Line underneath"), env.cfg("tagline", ""), function(v) env.setcfg("tagline", v) end,
            { hint = T("e.g. It's spooky season"), empty_label = T("(none)") }),
        S.header(T("Covers in the row")),
        S.radio(api, { { 4, "4" }, { 5, "5" }, { 6, "6" }, { 8, "8" } }, tonumber(env.cfg("count", 6)) or 6,
            function(v) env.setcfg("count", v) end),
        S.header(T("Label under each cover")),
        S.radio(api, { { "auto", T("Auto") }, { "status", T("Progress") }, { "format", T("Digital / Hardcopy") }, { "none", T("None") } },
            env.cfg("labels", "auto"), function(v) env.setcfg("labels", v) end),
        S.pick(ctx, api, T("Hardcopy collection"), collectionOptions(), env.cfg("hardcopy", "Hardcopy"),
            function(v) env.setcfg("hardcopy", v) end),
        S.header(T("Tapping a cover")),
        S.radio(api, { { "open", T("Opens the book") }, { "details", T("Shows book details") } },
            env.cfg("tap", "open"), function(v) env.setcfg("tap", v) end),
    }
end

ROWS.genres = function(env, api)
    return {
        S.header(T("Genres to list")),
        S.radio(api, { { 3, "3" }, { 4, "4" }, { 5, "5" } }, tonumber(env.cfg("count", 3)) or 3,
            function(v) env.setcfg("count", v) end),
    }
end

ROWS.year_covers = function(env, api)
    return {
        S.header(T("Layout")),
        S.radio(api, { { "wall", T("Cover wall") }, { "months", T("Stacked by month") } }, env.cfg("layout", "wall"),
            function(v) env.setcfg("layout", v ~= "wall" and v or nil) end),
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "gallery", T("Gallery wall") } }, A.get("year_covers_look", "plain"),
            function(v) A.set("year_covers_look", v ~= "plain" and v or nil) end),
    }
end

ROWS.challenge = function(env, api)
    local metric = env.cfg("metric", "auto")
    local manual = tonumber(env.cfg("target", nil))
    local auto = D.challenge(nil, metric, nil)
    local unit = auto and T(auto.metric) or ""
    local rows = {
        S.header(T("The challenge counts")),
        S.radio(api, { { "auto", T("Auto") }, { "pages", T("Pages") }, { "minutes", T("Minutes") }, { "days", T("Reading days") } },
            metric, function(v) env.setcfg("metric", v ~= "auto" and v or nil) end),
        S.input(api, T("Target"), manual, function(v) env.setcfg("target", v) end, {
            number = true, min = 1, max = 1000000, start = auto and auto.target or nil,
            step = (auto and auto.metric == "days") and 1 or 10,
            empty_label = T("auto") .. (auto and (" (" .. A.thousands(auto.target) .. " " .. unit .. ")") or ""),
            description = A.tr("How many %1 to read this month.", unit ~= "" and unit or T("pages, minutes or days")),
        }),
    }
    if manual then
        rows[#rows + 1] = { { text = T("Use the automatic target"), callback = function()
            env.setcfg("target", nil)
            api.changed()
        end } }
    end
    rows[#rows + 1] = S.header(T("Auto takes turns month by month and aims a little above your last three months."))
    rows[#rows + 1] = S.header(T("Look"))
    local function setStyle(v) env.setcfg("style", v ~= "ring" and v or nil) end
    local cur = env.cfg("style", "ring")
    local first = S.radio(api, { { "ring", T("Ring") }, { "flower", T("Flower") }, { "reticle", T("Reticle") } }, cur, setStyle)
    local second = S.radio(api, { { "neural", T("Neural network") }, { "hourglass", T("Hourglass") }, { "chess", T("Chess board") } }, cur, setStyle)
    -- as a menu, one choice of all five
    first._sui.options = { { "ring", T("Ring") }, { "flower", T("Flower") }, { "reticle", T("Reticle") },
        { "neural", T("Neural network") }, { "hourglass", T("Hourglass") }, { "chess", T("Chess board") } }
    second._sui = { kind = "skip" }
    rows[#rows + 1] = first
    rows[#rows + 1] = second
    return rows
end

ROWS.forecast = function(env, api)
    return {
        S.header(T("Books listed")),
        S.radio(api, { { 1, "1" }, { 2, "2" }, { 3, "3" } }, tonumber(env.cfg("count", 3)) or 3,
            function(v) env.setcfg("count", v) end),
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "calendar", T("Desk calendar") }, { "countdown", T("Countdown") }, { "almanac", T("Almanac") } }, env.cfg("look", "plain"),
            function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

-- What a Control centre button can run: these KOReader actions (each with
-- an icon of its own) or any of Simple UI's Quick Actions. With Bookshelf, its
-- own action chooser and icon library instead (A.host.actionRows/pickIcon).
local GL = {
    wifi = "\xEE\xB2\xA8", night = "\xEE\xB2\x93", bulb = "\xEE\xB7\xA6", sun = "\xEE\x9F\x9F",
    flame = "\xEF\x92\x90", rotate = "\xEE\xAD\xB4", calendar = "\xEE\x9F\xAC", chart = "\xEE\xA0\xA7",
    sleep = "\xEE\xAE\xB1", search = "\xEE\xA9\x88", book = "\xEE\x9E\xBD", history = "\xEE\xA7\x99",
    star = "\xEE\xAF\x8D", heart = "\xEE\xA7\x90", library = "\xEE\xA8\xB0", folder = "\xEE\xA5\x8A",
    home = "\xEE\xA7\x9B", refresh = "\xEE\xAD\x8F", sync = "\xEE\xAF\xA5", power = "\xEE\xAC\xA4",
    battery = "\xEE\x9D\xB8", timer = "\xEE\xB0\x9A", bookmark = "\xEE\x9E\xBF", note = "\xEE\xAA\x9D",
    dictionary = "\xEE\xB4\x9C", translate = "\xEE\xB3\x89", tag = "\xEE\xAF\xB8", shuffle = "\xEE\xAE\x9C",
    download = "\xEE\xA1\xA1", contrast = "\xEE\xA2\x94", lock = "\xEE\xA8\xBD", eye = "\xEE\xA4\x87",
    image = "\xEE\xA7\xA8", coffee = "\xEE\xA1\xB5", headphones = "\xEE\xA7\x8A", wrench = "\xEE\xB2\xB6",
    puzzle = "\xEE\xAC\xB0",
}
S.ICON_ORDER = { "wifi", "night", "bulb", "sun", "flame", "rotate", "calendar", "chart", "sleep", "search",
    "book", "bookmark", "history", "star", "heart", "library", "folder", "home", "refresh", "sync", "power",
    "battery", "timer", "note", "dictionary", "translate", "tag", "shuffle", "download", "contrast", "lock",
    "eye", "image", "coffee", "headphones", "wrench", "puzzle" }
S.ICONS = GL

-- need = a Device check the action needs to do anything here
S.CONTROL_ACTIONS = {
    { id = "toggle_wifi", label = T("Wi-Fi"), icon = GL.wifi, need = "hasWifiToggle" },
    { id = "night_mode", label = T("Night mode"), icon = GL.night },
    { id = "toggle_frontlight", label = T("Light"), icon = GL.bulb, need = "hasFrontlight" },
    { id = "show_frontlight_dialog", label = T("Light settings"), icon = GL.sun, need = "hasFrontlight" },
    { id = "toggle_rotation", label = T("Rotate"), icon = GL.rotate },
    { id = "stats_calendar_view", label = T("Calendar"), icon = GL.calendar },
    { id = "reading_progress", label = T("Progress"), icon = GL.chart },
    { id = "suspend", label = T("Sleep"), icon = GL.sleep, need = "canSuspend" },
    { id = "file_search", label = T("Search"), icon = GL.search },
    { id = "open_previous_document", label = T("Last book"), icon = GL.book },
    { id = "history", label = T("History"), icon = GL.history },
    { id = "favorites", label = T("Favorites"), icon = GL.star },
    { id = "collections", label = T("Collections"), icon = GL.library },
    { id = "filemanager", label = T("Files"), icon = GL.folder },
    { id = "full_refresh", label = T("Refresh screen"), icon = GL.refresh },
    { id = "screenshot", label = T("Screenshot"), icon = GL.image },
    { id = "restart", label = T("Restart"), icon = GL.power, need = "canRestart" },
}

local function deviceCan(need)
    if not need then return true end
    local ok, Device = pcall(require, "device")
    if not (ok and Device and type(Device[need]) == "function") then return true end
    local ok2, yes = pcall(Device[need], Device)
    return (not ok2) or (yes and true or false)
end

--- { { entry, text } } for every action a button can be given.
function S.controlChoices()
    local out = {}
    for _, a in ipairs(S.CONTROL_ACTIONS) do
        if deviceCan(a.need) then
            out[#out + 1] = { { label = a.label, icon = a.icon, action = { [a.id] = true } }, a.icon .. "  " .. a.label }
        end
    end
    for _, qa in ipairs(A.host.quickActions()) do
        out[#out + 1] = { { label = qa.label, icon = GL.puzzle, qa = qa.id }, GL.puzzle .. "  " .. A.tr("Quick action: %1", qa.label) }
    end
    return out
end

local function sameAction(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if type(a.qa) == "string" or type(b.qa) == "string" then return a.qa == b.qa end
    local ka = type(a.action) == "table" and next(a.action)
    local kb = type(b.action) == "table" and next(b.action)
    return ka ~= nil and ka == kb
end

-- One Control centre button: its action, icon and name.
function S.controlButton(ctx, i, back)
    local function current() return A.controlButtons(8)[i] end
    local function again() S.controlButton(ctx, i, back) end
    local function changed(fields)
        local copy = {}
        for k, v in pairs(current()) do copy[k] = v end
        for k, v in pairs(fields) do copy[k] = v end
        A.setControlButton(i, copy)
        S.reload(ctx)
    end
    S.open(ctx, A.tr("Button %1", i), function(api)
        local e = current()
        local rows = {}
        rows[#rows + 1] = S.header((e.icon and (e.icon .. "  ") or "") .. tostring(e.label or T("an action")))
        -- Bookshelf: anything its action chooser offers, right here
        local bs_rows = A.host.actionRows and A.host.actionRows(
            function(fn) return function() api.close(); fn() end end,
            function(fields)
                fields.icon = fields.icon or e.icon
                A.setControlButton(i, fields)
                S.reload(ctx)
                again()
            end)
        if bs_rows then
            for _, r in ipairs(bs_rows) do rows[#rows + 1] = r end
        else
        rows[#rows + 1] = { { text = T("Action") .. ELLIPSIS, callback = function()
            api.close()
            S.open(ctx, A.tr("Button %1: action", i), function(sub)
                local list = {}
                for _, opt in ipairs(S.controlChoices()) do
                    list[#list + 1] = { {
                        text = (sameAction(opt[1], e) and CHECK or "") .. shorten(opt[2], 44),
                        callback = function()
                            sub.close()
                            -- a new action brings its own name and icon
                            local entry = {}
                            for k, v in pairs(opt[1]) do entry[k] = v end
                            A.setControlButton(i, entry)
                            S.reload(ctx)
                            again()
                        end,
                    } }
                end
                list[#list + 1] = { { text = tr("Back"), callback = function() sub.close(); again() end } }
                return list
            end)
        end } }
        end
        rows[#rows + 1] = { { text = T("Icon") .. ELLIPSIS, callback = function()
            api.close()
            -- Bookshelf: its icon library
            if A.host.pickIcon and A.host.pickIcon(function(icon)
                if icon then changed({ icon = icon }) end
                again()
            end) then return end
            S.open(ctx, A.tr("Button %1: icon", i), function(sub)
                local list, line = {}, {}
                for _, name in ipairs(S.ICON_ORDER) do
                    local g = GL[name]
                    line[#line + 1] = { text = ((e.icon == g) and CHECK or "") .. g, callback = function()
                        sub.close()
                        changed({ icon = g })
                        again()
                    end }
                    if #line == 6 then list[#list + 1] = line; line = {} end
                end
                if #line > 0 then list[#list + 1] = line end
                list[#list + 1] = { { text = tr("Back"), callback = function() sub.close(); again() end } }
                return list
            end)
        end } }
        -- a picture of your own instead of the icon: any PNG or JPEG on the device
        local pic_name = e.image and (e.image:match("([^/]+)$") or e.image)
        rows[#rows + 1] = { { text = (pic_name and (T("Picture: ") .. pic_name) or T("Use a picture")) .. ELLIPSIS,
            callback = function()
                api.close()
                local UIManager = require("ui/uimanager")
                local okp, PathChooser = pcall(require, "ui/widget/pathchooser")
                if not okp then return S.controlButton(ctx, i, back) end
                local start = A.get("control_picture_dir", nil)
                if not start then
                    local okd, DataStorage = pcall(require, "datastorage")
                    start = okd and DataStorage:getDataDir() or "/"
                end
                UIManager:show(PathChooser:new{
                    title = T("Pick a PNG or JPEG"),
                    select_directory = false, select_file = true, show_files = true,
                    path = start,
                    file_filter = function(name)
                        local n = name:lower()
                        return n:match("%.png$") ~= nil or n:match("%.jpe?g$") ~= nil
                    end,
                    onConfirm = function(path)
                        local copy = {}
                        for k, val in pairs(current()) do copy[k] = val end
                        copy.image = path
                        A.setControlButton(i, copy)
                        A.set("control_picture_dir", path:match("^(.*)/[^/]*$"))
                        S.reload(ctx)
                        S.controlButton(ctx, i, back)
                    end,
                })
            end } }
        if e.image then
            rows[#rows + 1] = { { text = T("Use the icon instead"), callback = function()
                local copy = {}
                for k, val in pairs(current()) do copy[k] = val end
                copy.image = nil
                A.setControlButton(i, copy)
                api.changed()
            end } }
        end
        rows[#rows + 1] = S.input(api, T("Name"), e.label or "", function(v) changed({ label = v }) end)
        rows[#rows + 1] = { { text = T("Put this button back as it came"), callback = function()
            A.setControlButton(i, nil)
            api.changed()
        end } }
        if back then
            rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        end
        return rows
    end)
end

ROWS.control = function(env, api, ctx)
    local count = A.clamp(tonumber(env.cfg("count", 6)) or 6, 1, 8)
    local function setCount(v) env.setcfg("count", v) end
    local four = S.radio(api, { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" } }, count, setCount)
    local eight = S.radio(api, { { 5, "5" }, { 6, "6" }, { 7, "7" }, { 8, "8" } }, count, setCount)
    -- as a menu, one choice of all eight
    four._sui.options = { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" }, { 7, "7" }, { 8, "8" } }
    eight._sui = { kind = "skip" }
    local rows = { S.header(T("Buttons")), four, eight }
    local list = A.controlButtons(count)
    -- from a settings menu the dialog closes back to the menu
    local back = (not api.menu) and function()
        S.card("control", ctx, function() return A.makeEnv("control", ctx, 0, 0) end)
    end or nil
    for i = 1, count do
        rows[#rows + 1] = { { text = i .. ". " .. tostring(list[i].label or T("an action")) .. ELLIPSIS, callback = function()
            api.close()
            S.controlButton(ctx, i, back)
        end } }
    end
    rows[#rows + 1] = S.header(T("Front light"))
    local bright = S.radio(api, { { true, T("Brightness shown") }, { false, T("Brightness hidden") } },
        env.cfg("brightness", true) ~= false, function(v) if v then env.setcfg("brightness", nil) else env.setcfg("brightness", false) end end)
    local warm = S.radio(api, { { true, T("Warmth shown") }, { false, T("Warmth hidden") } },
        env.cfg("warmth", true) ~= false, function(v) if v then env.setcfg("warmth", nil) else env.setcfg("warmth", false) end end)
    bright._sui.title, warm._sui.title = T("Brightness"), T("Warmth")
    rows[#rows + 1] = bright
    rows[#rows + 1] = warm
    return rows
end

ROWS.mini = function(env, api, ctx)
    local options = { { "none", T("Nothing") } }
    for _, k in ipairs(A.MINI_TILES) do options[#options + 1] = { k, A.MINI_LABEL[k] } end
    local rows = { S.header(T("Small cards, left to right (as many as fit)")) }
    for i = 1, A.MINI_MAX do
        rows[#rows + 1] = S.pick(ctx, api, T("Card ") .. i, options, env.cfg("tile" .. i, A.MINI_DEFAULT[i] or "none"),
            function(v) env.setcfg("tile" .. i, v) end)
    end
    local control = { { text = T("Control centre buttons") .. ELLIPSIS, callback = function()
        api.close()
        S.card("control", ctx, function() return A.makeEnv("control", ctx, 0, 0) end)
    end } }
    -- as a menu: the Control centre's own settings, one level down
    control._sui = { kind = "submenu", label = T("Control centre buttons"),
        rows_fn = function() return ROWS.control(A.makeEnv("control", ctx, 0, 0), api, ctx) end }
    rows[#rows + 1] = control
    addAll(rows, S.shapeRows(api, ctx))
    rows[#rows + 1] = S.header(T("Rings goals, the challenge and the buttons are shared with their own cards."))
    return rows
end

ROWS.compare = function(env, api)
    return {
        S.header(T("Compare")),
        S.radio(api, { { "week", T("This week") }, { "month", T("This month") }, { "year", T("This year") } },
            env.cfg("period", "week"), function(v) env.setcfg("period", v ~= "week" and v or nil) end),
        S.header(T("Shows")),
        S.radio(api, { { "time", T("Time read") }, { "pages", T("Pages") }, { "both", T("Both") } },
            env.cfg("show", "time"), function(v) env.setcfg("show", v ~= "time" and v or nil) end),
    }
end

ROWS.library = function(env, api)
    return {
        S.header(T("Counts every book in your home folder, every 15 minutes at most.")),
        { { text = T("Count again now"), callback = function()
            D.recountLibrary()
            api.changed()
        end } },
    }
end

ROWS.authors = function(env, api)
    return {
        S.header(T("Most read by")),
        S.radio(api, { { "books", T("Books finished") }, { "time", T("Time read") } }, env.cfg("by", "books"),
            function(v) env.setcfg("by", v ~= "books" and v or nil) end),
        S.header(T("Authors listed")),
        S.radio(api, { { 3, "3" }, { 5, "5" }, { 8, "8" } }, tonumber(env.cfg("count", 5)) or 5,
            function(v) env.setcfg("count", v ~= 5 and v or nil) end),
    }
end

ROWS.pick = function(env, api, ctx)
    local lib = D.library() or { books = {} }
    local function values(field)
        local out = {}
        for _, v in ipairs(D.libraryValues(lib, field)) do out[#out + 1] = { v.name, v.name .. " (" .. v.n .. ")" } end
        return out
    end
    local function choose(key) return function(v) env.setcfg(key, v) end end
    return {
        S.header(T("A new pick")),
        S.radio(api, { { "day", T("Every day") }, { "week", T("Every week") }, { "month", T("Every month") }, { "tap", T("When I tap Another") } },
            env.cfg("every", "week"), function(v) env.setcfg("every", v ~= "week" and v or nil) end),
        S.pick(ctx, api, T("Pick from"), collectionOptions(T("The whole library")), env.cfg("coll", ""), choose("coll")),
        S.multi(ctx, api, T("Only these genres"), values("genres"), env.cfg("genres", nil), choose("genres"), T("Any genre")),
        S.multi(ctx, api, T("Only these authors"), values("authors"), env.cfg("authors", nil), choose("authors"), T("Any author")),
        S.header(T("Only books you haven't started. In a series, only the next one.")),
        S.header(T("Tapping the cover")),
        S.radio(api, { { "open", T("Opens the book") }, { "details", T("Shows book details") } },
            env.cfg("tap", "open"), function(v) env.setcfg("tap", v ~= "open" and v or nil) end),
    }
end

local function quoteLook(api, ctx)
    return sharedLook(api, ctx, T("Look, for every quote card"), "quote_look",
        { { "plain", T("Plain") }, { "paper", T("Notebook paper") }, { "terminal", T("Terminal") }, { "manuscript", T("Manuscript") } })
end
local function calendarLook(api, ctx)
    return sharedLook(api, ctx, T("Look, for both cover calendars"), "calendar_look",
        { { "plain", T("Plain") }, { "polaroid", T("Polaroids") }, { "brackets", T("Brackets") }, { "gilt", T("Gilt frames") } })
end

ROWS.quote = function(env, api, ctx)
    local h1, r1 = quoteLook(api, ctx)
    return {
        S.header(T("A new highlight from your books each day.")),
        { { text = T("Show another quote"), callback = function()
            D.nextQuote()
            api.changed()
        end } },
        h1, r1,
    }
end

for _, name in ipairs{ "quote2", "quote3", "quote4" } do
    ROWS[name] = function(_, api, ctx)
        local h1, r1 = quoteLook(api, ctx)
        return {
            S.header(T("A pick of its own, never the same highlight as your other quote cards.")),
            { { text = T("Show another quote"), callback = function()
                A.quoteAgain(name)
                api.changed()
            end } },
            h1, r1,
        }
    end
end

ROWS.calendar = function(env, api, ctx)
    local h1, r1 = calendarLook(api, ctx)
    return {
        S.header(T("Time on each day")),
        S.radio(api, { { true, T("Shown") }, { false, T("Hidden") } }, env.cfg("time", true) ~= false,
            function(v) if v then env.setcfg("time", nil) else env.setcfg("time", false) end end),
        h1, r1,
    }
end
ROWS.cover_week = ROWS.calendar

ROWS.week = function(env, api)
    return {
        S.header(T("Bars show")),
        S.radio(api, { { "pages", T("Pages") }, { "minutes", T("Minutes") } }, env.cfg("metric", "pages"),
            function(v) env.setcfg("metric", v) end),
    }
end

ROWS.finished = function(env, api)
    return {
        S.header(T("Covers in the row")),
        S.radio(api, { { 4, "4" }, { 5, "5" }, { 6, "6" }, { 8, "8" } }, tonumber(env.cfg("count", 6)) or 6,
            function(v) env.setcfg("count", v) end),
    }
end

ROWS.deadline = function(env, api, ctx)
    local books = {}
    local seen = {}
    local cur = env.cfg("book", "")
    for _, b in ipairs(D.reading(8)) do
        books[#books + 1] = { b.fp, b.title }
        seen[b.fp] = true
    end
    if cur ~= "" and not seen[cur] then
        table.insert(books, 1, { cur, D.info(cur).title })
    end
    local today = A.todayYmd()
    return {
        S.pick(ctx, api, T("Book"), books, cur, function(v)
            env.setcfg("book", v)
            env.setcfg("since", today)
        end),
        S.date(api, T("Finish by"), env.cfg("due", ""), function(v)
            env.setcfg("due", v)
            if env.cfg("since", "") == "" then env.setcfg("since", today) end
        end),
        S.input(api, T("For"), env.cfg("label", T("Finish by")), function(v) env.setcfg("label", v) end,
            { hint = T("e.g. Library loan"), empty_label = T("(no label)") }),
        S.date(api, T("Counting from"), env.cfg("since", ""), function(v) env.setcfg("since", v) end),
    }
end

-- Tick which of the collection's books are the club's picks for a month.
-- The arrows step to other months, so next month's can be lined up early.
local function clubPicks(ctx, env, back)
    local offset = 0
    local function show()
        local key, when = P.bookclub.monthKey(offset)
        local label = A.date("%B", when) .. " " .. os.date("%Y", when)
        S.open(ctx, T("Book club picks"), function(sub)
            local st = P.bookclub.state(env)
            local all = env.cfg("picks", nil)
            if type(all) ~= "table" then all = {} end
            local chosen = {}
            for _, fp in ipairs(type(all[key]) == "table" and all[key] or {}) do chosen[fp] = true end
            local rows = { {
                { text = "\xE2\x80\xB9", callback = function() offset = offset - 1; sub.close(); show() end },
                { text = label, enabled = false },
                { text = "\xE2\x80\xBA", callback = function() offset = offset + 1; sub.close(); show() end },
            } }
            local books = st and st.books or {}
            for _, b in ipairs(books) do
                rows[#rows + 1] = { {
                    text = (chosen[b.fp] and CHECK or "") .. shorten(b.title, 40),
                    callback = function()
                        -- keep the picks in the collection's own order
                        local list = {}
                        for _, other in ipairs(books) do
                            local on = chosen[other.fp]
                            if other.fp == b.fp then on = not on end
                            if on then list[#list + 1] = other.fp end
                        end
                        local copy = {}
                        for k, v in pairs(all) do copy[k] = v end
                        copy[key] = (#list > 0) and list or nil
                        env.setcfg("picks", copy)
                        sub.changed()
                    end,
                } }
            end
            if #books == 0 then
                rows[#rows + 1] = S.header(st and T("No books in the collection yet") or T("No book club collection yet"))
            end
            rows[#rows + 1] = { { text = T("Back"), callback = function() sub.close(); back() end } }
            return rows
        end)
    end
    show()
end

ROWS.bookclub = function(env, api, ctx)
    local _, when = P.bookclub.monthKey(0)
    return {
        S.pick(ctx, api, T("Collection"), collectionOptions(), P.bookclub.collection(env),
            function(v) env.setcfg("coll", v) end),
        { { text = A.tr("%1's books", A.date("%B", when)) .. ELLIPSIS, callback = function()
            api.close()
            clubPicks(ctx, env, api.again)
        end } },
        S.input(api, T("Title"), env.cfg("title", T("Book club")), function(v) env.setcfg("title", v) end,
            { hint = T("e.g. Book club"), empty_label = T("Book club") }),
        S.header(T("Look")),
        S.radio(api, { { "classic", T("Classic") }, { "garden", T("Garden") }, { "stream", T("Data stream") }, { "ledger", T("Ledger") } }, env.cfg("look", "classic"),
            function(v) env.setcfg("look", v ~= "classic" and v or nil) end),
    }
end

ROWS.week_rings = function(env, api, ctx)
    return addAll({
        S.input(api, T("Pages a day"), A.get("activity_page_goal", 30), function(v) A.set("activity_page_goal", v) end,
            { number = true, min = 1, max = 2000, description = T("Shared with the Activity rings card.") }),
        S.input(api, T("Minutes a day"), D.dailyMinutesGoal(), function(v) D.setDailyMinutesGoal(v) end,
            { number = true, min = 1, max = A.host.GOALS.daily_max, description = A.host.GOALS.daily_note }),
    }, S.shapeRows(api, ctx))
end

ROWS.month_rings = ROWS.week_rings

ROWS.longest_year = function(env, api)
    return {
        S.header(T("Longest by")),
        S.radio(api, { { "time", T("Time read") }, { "days", T("Days taken") } }, env.cfg("by", "time"),
            function(v) env.setcfg("by", v) end),
        S.header(T("How many")),
        S.radio(api, { { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" } }, tonumber(env.cfg("count", 3)) or 3,
            function(v) env.setcfg("count", v) end),
    }
end
ROWS.longest_month = ROWS.longest_year

ROWS.month_chart = function(env, api)
    return {
        S.header(T("Bars show")),
        S.radio(api, { { "pages", T("Pages read") }, { "time", T("Time read") } }, env.cfg("metric", "pages"),
            function(v) env.setcfg("metric", v) end),
    }
end

ROWS.year_chart = function(env, api)
    return {
        S.header(T("Pages counted")),
        S.radio(api, { { "read", T("Read that month") }, { "books", T("Of the books finished") } },
            env.cfg("pages", "read"), function(v) env.setcfg("pages", v) end),
    }
end

S.ROWS = ROWS

-- ─── shared rows ─────────────────────────────────────────────────────────────

local function toneOptions()
    local out = {}
    for _, t in ipairs(A.TONES) do out[#out + 1] = { t, A.toneLabel(t) } end
    return out
end

-- A grid of the accent colours to pick one from. `auto_label` adds a first
-- choice that clears the setting (the second accent's "matched" option).
local function accentPicker(ctx, title, key, current, auto_label, back)
    S.open(ctx, title, function(api)
        local rows = {}
        local function choose(id)
            return function()
                A.set(key, id)
                api.close()
                reloadAll(ctx)
                back()
            end
        end
        if auto_label then
            rows[#rows + 1] = { { text = ((A.get(key, nil) == nil) and CHECK or "") .. auto_label, callback = choose(nil) } }
        end
        local row = {}
        for _, id in ipairs(A.ACCENT_ORDER) do
            row[#row + 1] = { text = ((id == current) and CHECK or "") .. A.ACCENTS[id].label, callback = choose(id) }
            if #row == 3 then rows[#rows + 1] = row; row = {} end
        end
        if #row > 0 then rows[#rows + 1] = row end
        rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        return rows
    end, true)
end

function S.look(ctx, back)
    local function again() S.look(ctx, back) end
    S.open(ctx, T("Look and colours"), function(api)
        local themes = {}
        for _, id in ipairs(A.THEME_ORDER) do themes[#themes + 1] = { id, A.THEMES[id].label } end
        local a1, a2 = A.accentIds()
        local matched = A.get("accent2", nil) == nil
        local rows = {
            S.header(T("Theme")),
            S.radio(api, themes, A.themeId(), function(v) A.set("theme", v) end),
            S.header(T("Style")),
            S.styleRows(api, ctx)[2],
            -- Two accent colours, used for labels, rings, bars and buttons.
            -- A card's own "Card colour" setting decides which of the two leads.
            { { text = T("Accent colour: ") .. A.ACCENTS[a1].label, callback = function()
                api.close()
                accentPicker(ctx, T("Accent colour"), "accent", a1, nil, again)
            end } },
            { { text = T("Second accent: ") .. A.ACCENTS[a2].label .. (matched and T(" (matched)") or ""), callback = function()
                api.close()
                accentPicker(ctx, T("Second accent"), "accent2", (not matched) and a2 or nil,
                    T("Matched to the first"), again)
            end } },
            -- Cards placed on their own on the home screen (not in the
            -- Dashboard): the app's own look, or the theme's frame.
            S.header(T("Cards on their own")),
            S.radio(api, { { "native", A.host.KIND == "bookshelf" and T("Match Bookshelf") or T("Match Simple UI") }, { "framed", T("Framed, in the theme") } },
                A.standaloneNative() and "native" or "framed",
                function(v) A.set("standalone", v ~= "native" and v or nil) end),
            S.header(T("Week starts on")),
            S.radio(api, { { 0, T("Follow KOReader") }, { 2, T("Monday") }, { 1, T("Sunday") } },
                tonumber(A.get("week_start", 0)) or 0, function(v) A.set("week_start", v ~= 0 and v or nil) end),
        }
        rows[#rows + 1] = { { text = T("Diagnostics") .. ELLIPSIS, callback = function()
            api.close()
            S.diagnostics(ctx, again)
        end } }
        if back then
            rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        end
        return rows
    end, true)
end

-- What this device and this session look like from here: the facts needed to
-- tell why something looks or refreshes the way it does on a screen nobody
-- but the reader can see. Nothing is changed by opening it.
function S.diagnostics(ctx, back)
    local function yn(v) return v and T("on") or T("off") end
    local function safe(fn, fallback)
        local ok, v = pcall(fn)
        if ok and v ~= nil then return v end
        return fallback
    end
    S.open(ctx, A.NAME .. T(" diagnostics"), function(api)
        local Screen = A.screen()
        local Device = safe(function() return require("device") end, {})
        local ko = safe(function() return require("version"):getCurrentRevision() end, "?")
        local host_v = safe(function() return A.host.version() end, "?")
        local n = A.counts
        local lines = {
            A.NAME .. " " .. A.VERSION .. "  \xC2\xB7  " .. A.HOST .. " " .. tostring(host_v),
            "KOReader " .. tostring(ko),
            tostring(Device.model or "?") .. "  \xC2\xB7  " .. Screen:getWidth() .. "x" .. Screen:getHeight()
                .. T("  \xC2\xB7  colour ") .. yn(safe(function() return Screen:isColorEnabled() end, false)),
            T("Night mode ") .. yn(Screen.night_mode) .. T("  \xC2\xB7  page looks ") .. (A.pageLooksDark() and T("dark") or T("light")),
            T("Hardware dithering ") .. yn(Screen.hw_dithering) .. T("  \xC2\xB7  avoid flashes ")
                .. yn(safe(function() return G_reader_settings:isTrue("avoid_flashing_ui") end, false)),
            "Theme " .. A.themeId() .. "  \xC2\xB7  cards on their own: " .. (A.standaloneNative() and (A.HOST .. " look") or "framed"),
            "Settings file: " .. tostring(safe(function() return require("datastorage"):getSettingsDir() end, "?")) .. "/readinglog.lua",
            "Screen cleans " .. n.cleans .. "  \xC2\xB7  stray pixels stopped " .. n.clipped,
        }
        local rows = {}
        for _, l in ipairs(lines) do rows[#rows + 1] = S.header(l) end
        rows[#rows + 1] = { { text = T("Flash the screen clean now"), callback = function()
            api.close()
            A.cleanScreen()
        end } }
        if back then
            rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        end
        return rows
    end)
end

-- What a tap on a card does: the card's own thing (open the book, list a
-- month's books, the reading calendar), the reading calendar or progress,
-- or any of Simple UI's Quick Actions (with Bookshelf: anything its action
-- chooser offers).
local BUILTIN_TAPS = {
    { id = "stats_calendar_view", label = T("Reading calendar") },
    { id = "reading_progress", label = T("Reading progress") },
}
S.BUILTIN_TAPS = BUILTIN_TAPS

function S.tapLabel(name)
    local e = A.tapAction(name)
    if not e then return T("the card's own") end
    return e.label or T("an action")
end

-- The current choice as one value: "own", a dispatcher name, or "qa:<id>".
function S.tapValue(name)
    local e = A.tapAction(name)
    if not e then return "own" end
    if type(e.qa) == "string" then return "qa:" .. e.qa end
    if type(e.action) == "table" then return (next(e.action)) or "own" end
    return "own"
end

function S.setTapValue(name, v, label)
    if v == "own" or v == nil then
        A.set(name .. "_tap_action", nil)
    elseif type(v) == "string" and v:sub(1, 3) == "qa:" then
        A.set(name .. "_tap_action", { label = label, qa = v:sub(4) })
    else
        A.set(name .. "_tap_action", { label = label, action = { [v] = true }, builtin = true })
    end
end

-- { { value, label } } for every choice.
function S.tapOptions(name)
    local def = P[name]
    local out = { { "own", A.tr("The card's own: %1", def and def.does or T("as it comes")) } }
    for _, b in ipairs(BUILTIN_TAPS) do out[#out + 1] = { b.id, b.label } end
    for _, qa in ipairs(A.host.quickActions()) do
        out[#out + 1] = { "qa:" .. qa.id, A.tr("Quick action: %1", qa.label), qa.label }
    end
    return out
end

-- With Bookshelf: the card's own job, the two built-in taps, or anything its
-- action chooser offers (the one its Action module and start menu use).
local function tapChooserBookshelf(ctx, name, back)
    local def = P[name]
    S.open(ctx, A.tr("%1: when tapped", def.title), function(api)
        local cur = A.tapAction(name)
        local cur_id = cur and type(cur.action) == "table" and next(cur.action) or nil
        local function done(entry)
            A.set(name .. "_tap_action", entry)
            api.close()
            if back then back() end
        end
        local rows = {}
        rows[#rows + 1] = { { text = (cur == nil and CHECK or "") .. A.tr("The card's own: %1", def.does or T("as it comes")),
            callback = function() done(nil) end } }
        local row = {}
        for _, b in ipairs(BUILTIN_TAPS) do
            local on = cur ~= nil and cur_id == b.id and cur.builtin
            row[#row + 1] = { text = (on and CHECK or "") .. b.label, callback = function()
                done({ label = b.label, action = { [b.id] = true }, builtin = true })
            end }
        end
        rows[#rows + 1] = row
        local extra = A.host.actionRows(function(fn) return function() api.close(); fn() end end, function(fields)
            fields.builtin = nil
            A.set(name .. "_tap_action", fields)
            if back then back() end
        end)
        if extra then
            rows[#rows + 1] = S.header((cur and not cur.builtin) and (CHECK .. T("Now: ") .. tostring(cur.label or T("an action")))
                or T("Or anything else:"))
            for _, r in ipairs(extra) do rows[#rows + 1] = r end
        end
        rows[#rows + 1] = S.header(T("Buttons on the card (Continue, Details, the tabs) keep their own job."))
        if back then
            rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        end
        return rows
    end)
end

function S.tapChooser(ctx, name, back)
    if A.host.actionRows then return tapChooserBookshelf(ctx, name, back) end
    local def = P[name]
    S.open(ctx, A.tr("%1: when tapped", def.title), function(api)
        local cur = S.tapValue(name)
        local rows = {}
        for _, opt in ipairs(S.tapOptions(name)) do
            rows[#rows + 1] = { { text = ((opt[1] == cur) and CHECK or "") .. shorten(opt[2], 44), callback = function()
                S.setTapValue(name, opt[1], opt[3] or opt[2])
                api.close()
                if back then back() end
            end } }
        end
        rows[#rows + 1] = S.header(T("Buttons on the card (Continue, Details, the tabs) keep their own job."))
        if back then
            rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
        end
        return rows
    end)
end

-- The settings dialog for one card. env_fn() builds a fresh env each time the
-- dialog is shown (tone and slot can change while it is open). `back`
-- (optional) returns to a parent dialog.
function S.card(name, ctx, env_fn, back)
    local def = P[name]
    local function show()
        S.open(ctx, def.title, function(api)
            local env = env_fn()
            local rows = ROWS[name] and ROWS[name](env, api, ctx) or {}
            if def.slots and not env.nested and ctx and ctx.config then
                rows[#rows + 1] = S.header(T("This card shows"))
                local row = {}
                for i = 1, 3 do
                    local active = env.slot == i
                    row[#row + 1] = {
                        text = (active and CHECK or "") .. A.tr("Set %1", i),
                        callback = function()
                            if active then return end
                            api.close()
                            ctx.config:set("alm_slot", i)
                            -- Bookshelf redraws the card when the entry is saved
                            if A.host.KIND == "bookshelf" then D.invalidate() else reload(ctx) end
                            show()
                        end,
                    }
                end
                rows[#rows + 1] = row
            end
            if name ~= "dashboard" then
                rows[#rows + 1] = { { text = T("When tapped: ") .. S.tapLabel(name) .. ELLIPSIS, callback = function()
                    api.close()
                    S.tapChooser(ctx, name, show)
                end } }
            end
            rows[#rows + 1] = S.header(T("Card colour"))
            local tones = toneOptions()
            local function pickTone(v) A.set(name .. "_tone", v) end
            rows[#rows + 1] = S.radio(api, { tones[1], tones[2] }, env.tone.name, pickTone)
            rows[#rows + 1] = S.radio(api, { tones[3], tones[4] }, env.tone.name, pickTone)
            rows[#rows + 1] = { { text = T("Look and colours") .. ELLIPSIS, callback = function()
                api.close()
                S.look(ctx, show)
            end } }
            if back then
                rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } }
            end
            return rows
        end)
    end
    show()
end

-- the chart look, on every card with a chart
for _, name in ipairs{ "year_time", "month_chart", "when_read", "week", "compare", "year_chart", "challenge" } do
    local own = ROWS[name]
    ROWS[name] = function(env, api, ctx)
        local rows = own and own(env, api, ctx) or {}
        local h1, r1 = chartLook(api, ctx)
        rows[#rows + 1] = h1
        rows[#rows + 1] = r1
        return rows
    end
end

-- (menu builders follow: settings_menu)

return S
