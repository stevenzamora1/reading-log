--[[
Reading Log settings: the dialogs behind long-press > "Module settings".

Each card has a short dialog of its own options, followed by the rows every
card shares: what a tap on it does, its colour, and "Look and colours" (theme,
accents, week start), which applies to all the cards at once.

Dialogs follow the pattern Bookshelf's own modules use: pick something, the
dialog closes, the card redraws, the dialog comes back with the new value.
]]

local A = ...
local T = A._
local D = A.D
local P = A.panels
local S = {}
A.S = S


local CHECK = "\xE2\x9C\x93 "
local ELLIPSIS = "\xE2\x80\xA6"

-- Redraw the card these settings belong to.
local function reload(ctx)
    D.invalidate()
    if ctx and ctx.menu and ctx.menu._reload then pcall(ctx.menu._reload, ctx.menu) end
end
S.reload = reload

-- Redraw every card: a theme or text-size change touches all of them. In the
-- grids that means asking Bookshelf to rebuild the grid; the start menu's
-- own reload already redraws the whole menu.
local function reloadAll(ctx)
    D.invalidate()
    local bw = ctx and ctx.bw
    if bw and ctx.surface == "hero" then
        local ok, HeroModules = pcall(require, "lib/bookshelf_hero_modules")
        if ok and HeroModules and HeroModules._rebuild and pcall(HeroModules._rebuild, bw) then return end
    end
    if ctx and ctx.menu and ctx.menu._reload then pcall(ctx.menu._reload, ctx.menu) end
end

-- A look shared by several cards (all the quote cards, both cover
-- calendars, every chart): one setting, and every card redraws.
local function sharedLook(api, ctx, title, key, options)
    local all = { changed = function() reloadAll(ctx); api.changed() end }
    return S.header(title), S.radio(all, options, A.get(key, options[1][1]),
        function(v) A.set(key, v ~= options[1][1] and v or nil) end)
end
local function chartLook(api, ctx)
    return sharedLook(api, ctx, T("Charts, on every card"), "chart_look",
        { { "plain", T("Plain") }, { "cozy", T("Book spines and hearts") } })
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

function S.header(text) return { { text = text, enabled = false } } end

-- A row of radio buttons. options = { { value, label }, ... }
function S.radio(api, options, current, on_pick)
    local row = {}
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
    local shown = (value == nil or value == "") and (o.empty_label or T("not set")) or shorten(value, 28)
    return { {
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
    return { {
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
                ok_text = T("Set date"),
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
    return { {
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
    return { {
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
        S.radio(api, { { "classic", T("Classic") }, { "scrapbook", T("Scrapbook") } }, env.cfg("look", "classic"),
            function(v) env.setcfg("look", v ~= "classic" and v or nil) end),
    }
end

ROWS.timeline = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "sky", T("Sky") } }, env.cfg("look", "plain"),
            function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

ROWS.trends = function(env, api)
    return {
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "notes", T("Sticky notes") } }, env.cfg("look", "plain"),
            function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

-- Default or Cute: every cute look at once. Each card can still be changed
-- on its own afterwards.
local CUTE = { { "ring_shape", "hearts" }, { "challenge_style", "flower" }, { "bookclub_look", "garden" },
    { "goal_look", "jar" }, { "quote_look", "paper" }, { "calendar_look", "polaroid" },
    { "continue_look", "scrapbook" }, { "trends_look", "notes" }, { "chart_look", "cozy" },
    { "timeline_look", "sky" }, { "forecast_look", "calendar" } }
A.CUTE = CUTE
function A.styleNow()
    local on = 0
    for _, kv in ipairs(CUTE) do if A.get(kv[1]) == kv[2] then on = on + 1 end end
    if on == #CUTE then return "cute" elseif on == 0 then return "default" end
    return "mixed"
end
function A.setStyle(v)
    for _, kv in ipairs(CUTE) do A.set(kv[1], v == "cute" and kv[2] or nil) end
end
function S.styleRows(api, ctx)
    local all = { changed = function() reloadAll(ctx); api.changed() end }
    local now = A.styleNow()
    return {
        S.header(T("Style")),
        S.radio(all, { { "default", T("Default") }, { "cute", T("Cute") } }, now, A.setStyle),
        S.header(now == "mixed" and T("Some cards have a look of their own.")
            or T("Cute turns on every card's cute look at once.")),
    }
end

-- Rings or hearts: one choice for every rings card (Activity, Week and Month
-- rings and the Mini dashboard), so changing it redraws them all.
function S.shapeRows(api, ctx)
    local all = { changed = function() reloadAll(ctx); api.changed() end }
    local rows = {
        S.header(T("Shape, for every rings card")),
        S.radio(all, { { "rings", T("Rings") }, { "hearts", T("Hearts") } }, A.get("ring_shape", "rings"),
            function(v) A.set("ring_shape", v ~= "rings" and v or nil) end),
    }
    if A.hearts() then
        rows[#rows + 1] = S.header(T("Heart colours"))
        rows[#rows + 1] = S.radio(all, { { "pink", T("Pink") }, { "card", T("Card colours") } }, A.get("heart_colors", "pink"),
            function(v) A.set("heart_colors", v ~= "pink" and v or nil) end)
        rows[#rows + 1] = S.header(T("A broken heart when you miss"))
        rows[#rows + 1] = S.radio(all, { { "any", T("Either goal") }, { "both", T("Both goals") } }, A.get("heart_broken", "any"),
            function(v) A.set("heart_broken", v ~= "any" and v or nil) end)
    end
    return rows
end

local function addAll(rows, more)
    for _, r in ipairs(more) do rows[#rows + 1] = r end
    return rows
end

ROWS.activity = function(env, api, ctx)
    local Store = select(2, pcall(require, "lib/bookshelf_settings_store"))
    local rows = {
        S.input(api, T("Pages a day"), env.cfg("page_goal", 30), function(v) env.setcfg("page_goal", v) end,
            { number = true, min = 1, max = 2000 }),
        S.input(api, T("Minutes a day"), D.dailyMinutesGoal(), function(v)
            if type(Store) == "table" and Store.save then pcall(Store.save, "micromodule_reading_goal_daily", v) end
            A.epoch = A.epoch + 1
        end, { number = true, min = 1, max = 1440, description = T("Shared with Bookshelf's Reading goals card.") }),
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
    return {
        S.input(api, T("Books this year"), target, function(v) D.setYearGoal(v) end,
            { number = true, min = 1, max = 1000, description = T("Shared with Bookshelf's Reading goals card.") }),
        S.input(api, T("Read outside KOReader"), other, function(v) D.setOtherBooks(v) end,
            { number = true, min = 0, max = 1000, description = T("Paper books, audiobooks or another reader. Added to this year's count.") }),
        S.header(T("Look")),
        S.radio(api, { { "number", T("Number") }, { "jar", T("Jar of hearts") } }, env.cfg("look", "number"),
            function(v) env.setcfg("look", v ~= "number" and v or nil) end),
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
            number = true, min = 1, max = 1000000,
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
    rows[#rows + 1] = S.radio(api, { { "ring", T("Ring") }, { "flower", T("Flower") } }, env.cfg("style", "ring"),
        function(v) env.setcfg("style", v ~= "ring" and v or nil) end)
    return rows
end

ROWS.forecast = function(env, api)
    return {
        S.header(T("Books listed")),
        S.radio(api, { { 1, "1" }, { 2, "2" }, { 3, "3" } }, tonumber(env.cfg("count", 3)) or 3,
            function(v) env.setcfg("count", v) end),
        S.header(T("Look")),
        S.radio(api, { { "plain", T("Plain") }, { "calendar", T("Desk calendar") } }, env.cfg("look", "plain"),
            function(v) env.setcfg("look", v ~= "plain" and v or nil) end),
    }
end

-- One Control centre button: its action, icon and name.
function S.controlButton(ctx, i, back)
    local function current() return A.controlButtons(8)[i] end
    S.open(ctx, A.tr("Button %1", i), function(api)
        local e = current()
        local rows = {}
        rows[#rows + 1] = S.header(T("Does: ") .. tostring(e.label or T("an action")))
        local ok, Chooser = pcall(require, "lib/bookshelf_action_chooser")
        if ok and type(Chooser) == "table" and Chooser.actionRows then
            local function close(fn) return function() api.close(); fn() end end
            local ok2, extra = pcall(Chooser.actionRows, close, function(fields)
                fields.icon = fields.icon or e.icon
                A.setControlButton(i, fields)
                S.reload(ctx)
                S.controlButton(ctx, i, back)
            end)
            if ok2 and type(extra) == "table" then
                for _, r in ipairs(extra) do rows[#rows + 1] = r end
            end
        end
        rows[#rows + 1] = { { text = T("Icon") .. ELLIPSIS, callback = function()
            api.close()
            local okl, Lib = pcall(require, "lib/bookshelf_icons_library")
            if not (okl and Lib and Lib.show) then return S.controlButton(ctx, i, back) end
            Lib:show(function(value)
                if value and value ~= "" then
                    local copy = {}
                    for k, v in pairs(current()) do copy[k] = v end
                    copy.icon = value
                    A.setControlButton(i, copy)
                    S.reload(ctx)
                end
                S.controlButton(ctx, i, back)
            end, { dynamic = false, svg = false })
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
        rows[#rows + 1] = S.input(api, T("Name"), e.label or "", function(v)
            local copy = {}
            for k, val in pairs(current()) do copy[k] = val end
            copy.label = v
            A.setControlButton(i, copy)
        end)
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
    local rows = {
        S.header(T("Buttons")),
        S.radio(api, { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" } }, count, function(v) env.setcfg("count", v) end),
        S.radio(api, { { 5, "5" }, { 6, "6" }, { 7, "7" }, { 8, "8" } }, count, function(v) env.setcfg("count", v) end),
    }
    local list = A.controlButtons(count)
    for i = 1, count do
        rows[#rows + 1] = { { text = i .. ". " .. tostring(list[i].label or T("an action")) .. ELLIPSIS, callback = function()
            api.close()
            S.controlButton(ctx, i, function() S.card("control", ctx, function() return A.makeEnv("control", ctx, 0, 0) end) end)
        end } }
    end
    rows[#rows + 1] = S.header(T("Front light"))
    rows[#rows + 1] = S.radio(api, { { true, T("Brightness shown") }, { false, T("Brightness hidden") } },
        env.cfg("brightness", true) ~= false, function(v) if v then env.setcfg("brightness", nil) else env.setcfg("brightness", false) end end)
    rows[#rows + 1] = S.radio(api, { { true, T("Warmth shown") }, { false, T("Warmth hidden") } },
        env.cfg("warmth", true) ~= false, function(v) if v then env.setcfg("warmth", nil) else env.setcfg("warmth", false) end end)
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
    rows[#rows + 1] = { { text = T("Control centre buttons") .. ELLIPSIS, callback = function()
        api.close()
        S.card("control", ctx, function() return A.makeEnv("control", ctx, 0, 0) end)
    end } }
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
        S.header(T("Counts every book in Bookshelf's library, every 15 minutes at most.")),
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
        { { "plain", T("Plain") }, { "paper", T("Notebook paper") } })
end
local function calendarLook(api, ctx)
    return sharedLook(api, ctx, T("Look, for both cover calendars"), "calendar_look",
        { { "plain", T("Plain") }, { "polaroid", T("Polaroids") } })
end

ROWS.quote = function(env, api, ctx)
    local h1, r1 = quoteLook(api, ctx)
    return {
        S.header(T("Shares its pick with Bookshelf's Quote of the day.")),
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
        S.radio(api, { { "classic", T("Classic") }, { "garden", T("Garden") } }, env.cfg("look", "classic"),
            function(v) env.setcfg("look", v ~= "classic" and v or nil) end),
    }
end

ROWS.week_rings = function(env, api, ctx)
    local Store = select(2, pcall(require, "lib/bookshelf_settings_store"))
    return addAll({
        S.input(api, T("Pages a day"), A.get("activity_page_goal", 30), function(v) A.set("activity_page_goal", v) end,
            { number = true, min = 1, max = 2000, description = T("Shared with the Activity rings card.") }),
        S.input(api, T("Minutes a day"), D.dailyMinutesGoal(), function(v)
            if type(Store) == "table" and Store.save then pcall(Store.save, "micromodule_reading_goal_daily", v) end
            A.epoch = A.epoch + 1
        end, { number = true, min = 1, max = 1440, description = T("Shared with Bookshelf's Reading goals card.") }),
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
            -- Cards placed on their own in Bookshelf's grids (not in the
            -- Dashboard): Bookshelf's card as theirs, or the theme's frame.
            S.header(T("Cards on their own")),
            S.radio(api, { { "native", T("Match Bookshelf") }, { "framed", T("Framed, in the theme") } },
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
        -- Bookshelf's version, from the _meta.lua beside the code that is running
        local shelf = safe(function()
            local Kit = require("lib/bookshelf_module_kit")
            local fn
            for _, v in pairs(Kit) do if type(v) == "function" then fn = v break end end
            local src = debug.getinfo(fn, "S").source:gsub("^@", "")
            return dofile(src:match("^(.*)/lib/[^/]*$") .. "/_meta.lua").version
        end, "?")
        local fs = ctx and ctx.bw and ctx.bw._micro_fullscreen
        local n = A.counts
        local lines = {
            A.NAME .. " " .. A.VERSION .. "  \xC2\xB7  Bookshelf " .. tostring(shelf),
            "KOReader " .. tostring(ko),
            tostring(Device.model or "?") .. "  \xC2\xB7  " .. Screen:getWidth() .. "x" .. Screen:getHeight()
                .. T("  \xC2\xB7  colour ") .. yn(safe(function() return Screen:isColorEnabled() end, false)),
            T("Night mode ") .. yn(Screen.night_mode) .. T("  \xC2\xB7  page looks ") .. (A.pageLooksDark() and T("dark") or T("light")),
            T("Hardware dithering ") .. yn(Screen.hw_dithering) .. T("  \xC2\xB7  avoid flashes ")
                .. yn(safe(function() return G_reader_settings:isTrue("avoid_flashing_ui") end, false)),
            T("Theme ") .. A.themeId() .. T("  \xC2\xB7  refresh ") .. A.refreshMode()
                .. T("  \xC2\xB7  in full-screen view: ") .. (fs and T("yes") or T("no")),
            T("Opened ") .. n.views .. T("  \xC2\xB7  flashes asked ") .. n.flashes .. T("  \xC2\xB7  clock re-inks ") .. n.reinks,
            T("Clock updates narrowed ") .. n.narrowed .. T("  \xC2\xB7  stray pixels stopped ") .. n.clipped,
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
-- or anything else KOReader or a plugin can do, picked with Bookshelf's own
-- action chooser (the one its Action module and start menu use).
local BUILTIN_TAPS = {
    { id = "stats_calendar_view", label = T("Reading calendar") },
    { id = "reading_progress", label = T("Reading progress") },
}

function S.tapLabel(name)
    local e = A.tapAction(name)
    if not e then return T("the card's own") end
    return e.label or T("an action")
end

function S.tapChooser(ctx, name, back)
    local def = P[name]
    S.open(ctx, def.title .. T(": when tapped"), function(api)
        local cur = A.tapAction(name)
        local cur_id = cur and type(cur.action) == "table" and next(cur.action) or nil
        local function done(entry)
            A.set(name .. "_tap_action", entry)
            api.close()
            if back then back() end
        end
        local rows = {}
        rows[#rows + 1] = { { text = (cur == nil and CHECK or "") .. T("The card's own: ") .. (def.does or T("as it comes")),
            callback = function() done(nil) end } }
        local row = {}
        for _, b in ipairs(BUILTIN_TAPS) do
            local on = cur ~= nil and cur_id == b.id and cur.builtin
            row[#row + 1] = { text = (on and CHECK or "") .. b.label, callback = function()
                done({ label = b.label, action = { [b.id] = true }, builtin = true })
            end }
        end
        rows[#rows + 1] = row
        local ok, Chooser = pcall(require, "lib/bookshelf_action_chooser")
        if ok and type(Chooser) == "table" and Chooser.actionRows then
            rows[#rows + 1] = S.header((cur and not cur.builtin) and (CHECK .. T("Now: ") .. tostring(cur.label or T("an action")))
                or T("Or anything else:"))
            local function close(fn) return function() api.close(); fn() end end
            local ok2, extra = pcall(Chooser.actionRows, close, function(fields)
                fields.builtin = nil
                A.set(name .. "_tap_action", fields)
                if back then back() end
            end)
            if ok2 and type(extra) == "table" then
                for _, r in ipairs(extra) do rows[#rows + 1] = r end
            end
        end
        rows[#rows + 1] = S.header(T("Buttons on the card (Continue, Details, +, \xE2\x88\x92) keep their own job."))
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
                        text = (active and CHECK or "") .. T("Set ") .. i,
                        callback = function()
                            if active then return end
                            api.close()
                            -- saving the entry redraws the card; then show the new set
                            ctx.config:set("alm_slot", i)
                            D.invalidate()
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

return S
