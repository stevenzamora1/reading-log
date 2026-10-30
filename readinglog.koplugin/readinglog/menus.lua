--[[
Reading Log settings as Simple UI menu items: what a long-press on a card (or
Simple UI's Settings > Modules) shows for it.

A card's own options come from its rows in settings.lua (S.ROWS), turned into
menu items here, so the options are written once:
  header + radio row   one choice, its current value on the right
  input                a row that opens a number spinner or a text prompt
  pick                 a choice from a list (a collection, a book)
  date                 a row that opens the date picker
  anything else        a row per button (e.g. "October's books…")
Every row is read again when the menu draws it, so the values shown are
always the saved ones.

The shared rows follow, in Simple UI's usual sections: Card height
(Proportions), Card colour and Look and colours (Appearance), When tapped
(Behaviour). Simple UI then adds its own Frame, Background, Top Margin and
Column Width.
]]

local A = ...
local D = A.D
local P = A.panels
local S = A.S
local H = A.host

local floor, max, min = math.floor, math.max, math.min
local tr = S.tr
local T = A._

local ELLIPSIS = "\xE2\x80\xA6"

local function Config() return H.try("infra/sui_config") end

local function shorten(v, n)
    v = tostring(v)
    if #v > n then return v:sub(1, n - 1) .. ELLIPSIS end
    return v
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- ─── item makers ─────────────────────────────────────────────────────────────

-- Rows here are built by hand rather than with Simple UI's own row makers:
-- those changed between Simple UI versions (2.7.5's choice row only takes a
-- fixed list), and a menu that crashes KOReader on a tap is the worst way to
-- find out. Only the plain menu-item fields every version reads are used:
-- text/text_func, value_func, sub_item_table_func, radio, checked_func,
-- keep_menu_open, callback.

-- A choice: options_fn() -> { { value, label } }, get() -> value, set(value).
-- shown(label) (optional) shortens the current choice shown on the right.
local function radioItem(title, options_fn, get, set, after, shown)
    local function list()
        local ok, opts = pcall(options_fn)
        return (ok and type(opts) == "table") and opts or {}
    end
    local function currentLabel()
        local ok, cur = pcall(get)
        if not ok then return "" end
        for _, o in ipairs(list()) do
            if o[1] == cur then return shorten(shown and shown(tostring(o[2])) or o[2], 26) end
        end
        return ""
    end
    return {
        text_func = function() return title end,
        value_func = currentLabel,
        mandatory_func = currentLabel,
        sub_item_table_func = function()
            local items = {}
            for _, o in ipairs(list()) do
                local value, label = o[1], tostring(o[2])
                items[#items + 1] = {
                    text = label,
                    radio = true,
                    keep_menu_open = true,
                    checked_func = function()
                        local ok, cur = pcall(get)
                        return ok and cur == value
                    end,
                    callback = function()
                        local ok, err = pcall(set, value)
                        if not ok then A.log("setting failed:", err) end
                        if after then pcall(after) end
                    end,
                }
            end
            if #items == 0 then items[1] = { text = tr("Nothing to choose from yet"), enabled = false } end
            return items
        end,
    }
end
S.radioItem = radioItem

-- Any number of options ticked (none ticked = any): options_fn() -> { { value,
-- label } }, get() -> list of values, set(list or nil).
local function multiItem(title, options_fn, get, set, any_label, after)
    local function cur()
        local ok, v = pcall(get)
        return (ok and type(v) == "table") and v or {}
    end
    local function has(v)
        for _, x in ipairs(cur()) do
            if tostring(x):lower() == tostring(v):lower() then return true end
        end
        return false
    end
    return {
        text_func = function() return title end,
        value_func = function()
            local list = cur()
            if #list == 0 then return any_label or tr("Any") end
            return shorten(table.concat(list, ", "), 22)
        end,
        sub_item_table_func = function()
            local items = { {
                text = any_label or tr("Any"),
                keep_menu_open = true,
                checked_func = function() return #cur() == 0 end,
                callback = function()
                    pcall(set, nil)
                    if after then pcall(after) end
                end,
                separator = true,
            } }
            local ok, opts = pcall(options_fn)
            for _, o in ipairs(ok and type(opts) == "table" and opts or {}) do
                local value = o[1]
                items[#items + 1] = {
                    text = tostring(o[2]),
                    keep_menu_open = true,
                    checked_func = function() return has(value) end,
                    callback = function()
                        local list = {}
                        for _, x in ipairs(cur()) do
                            if tostring(x):lower() ~= tostring(value):lower() then list[#list + 1] = x end
                        end
                        if not has(value) then list[#list + 1] = value end
                        local okc, err = pcall(set, #list > 0 and list or nil)
                        if not okc then A.log("setting failed:", err) end
                        if after then pcall(after) end
                    end,
                }
            end
            if #items == 1 then items[2] = { text = tr("Nothing to choose from yet"), enabled = false } end
            return items
        end,
    }
end

-- A number: a spinner.
local function numberItem(label, get, save, o, after)
    o = o or {}
    local lo, hi = o.min or 0, o.max or 9999
    local function raw()
        local ok, v = pcall(get)
        return ok and tonumber(v) or nil
    end
    local function value()
        local v = raw()
        return v and A.clamp(floor(v), lo, hi) or A.clamp(floor(o.start or o.default or lo), lo, hi)
    end
    return {
        text_func = function() return label end,
        value_func = function()
            if not raw() and o.empty_label then return shorten(o.empty_label, 22) end
            return tostring(value()) .. (o.unit or "")
        end,
        keep_menu_open = true,
        callback = function()
            local SpinWidget = require("ui/widget/spinwidget")
            local UIManager = require("ui/uimanager")
            UIManager:show(SpinWidget:new{
                title_text = label,
                info_text = o.description,
                value = value(),
                value_min = lo, value_max = hi,
                value_step = o.step or 1,
                value_hold_step = (o.step or 1) * 10,
                unit = o.unit,
                default_value = o.default,
                ok_text = tr("Save"),
                callback = function(spin)
                    local ok, err = pcall(save, A.clamp(floor(spin.value), lo, hi))
                    if not ok then A.log("setting failed:", err) end
                    if after then pcall(after) end
                end,
            })
        end,
    }
end

-- Text (or a number, without Simple UI's stepper): a prompt.
local function inputItem(label, get, save, o, after)
    o = o or {}
    if o.number then
        local item = numberItem(label, get, save, o, after)
        if item then return item end
    end
    return {
        text_func = function() return label end,
        value_func = function()
            local v = get()
            if v == nil or v == "" then return o.empty_label or tr("not set") end
            return shorten(v, 22)
        end,
        keep_menu_open = true,
        callback = function()
            local UIManager = require("ui/uimanager")
            local InputDialog = require("ui/widget/inputdialog")
            local cur = get()
            local dlg
            dlg = InputDialog:new{
                title = label,
                description = o.description,
                input = cur ~= nil and tostring(cur) or "",
                input_hint = o.hint,
                input_type = o.number and "number" or nil,
                -- several lines (the letter board's text)
                allow_newline = o.multiline or nil,
                buttons = { {
                    { text = tr("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
                    { text = tr("Save"), is_enter_default = true, callback = function()
                        local txt = dlg:getInputText() or ""
                        UIManager:close(dlg)
                        if o.number then
                            local n = tonumber(txt)
                            if not n then return end
                            n = floor(n)
                            if o.min and n < o.min then n = o.min end
                            if o.max and n > o.max then n = o.max end
                            save(n)
                        else
                            save(trim(txt))
                        end
                        if after then after() end
                    end },
                } },
            }
            UIManager:show(dlg)
            pcall(dlg.onShowKeyboard, dlg)
        end,
    }
end

-- A date: KOReader's date picker.
local function dateItem(label, get, save, after)
    return {
        text_func = function() return label end,
        value_func = function()
            local y, m, d = A.parseYmd(get())
            if not y then return tr("not set") end
            return d .. " " .. A.date("%b", os.time{ year = y, month = m, day = d, hour = 12 }) .. " " .. y
        end,
        keep_menu_open = true,
        callback = function()
            local UIManager = require("ui/uimanager")
            local DateTimeWidget = require("ui/widget/datetimewidget")
            local y, m, d = A.parseYmd(get())
            if not y then
                local t = os.date("*t")
                y, m, d = t.year, t.month, t.day
            end
            UIManager:show(DateTimeWidget:new{
                year = y, month = m, day = d,
                ok_text = tr("Set date"),
                title_text = label,
                callback = function(t)
                    save(string.format("%04d-%02d-%02d", t.year, t.month, t.day))
                    if after then after() end
                end,
            })
        end,
    }
end

-- ─── a card's rows as menu items ─────────────────────────────────────────────

local function noop() end

-- What a card's rows get as `api` when they are shown as a menu: the menu
-- stays open, so close and again do nothing; changed redraws the card.
local function menuApi(after)
    return { menu = true, close = noop, again = noop, changed = function() if after then pcall(after) end end }
end
S.menuApi = menuApi

--- Menu items for rows_fn() (a fresh set of rows each call; see S.ROWS).
function S.rowsMenu(rows_fn, after)
    local first = rows_fn() or {}
    local items = {}
    local header

    -- row i as it is now (values move on as the reader changes them)
    local function fresh(i, kind, label)
        local r = (rows_fn() or {})[i]
        local d = r and r._sui
        if d and d.kind == kind and (label == nil or d.label == label) then return d end
        return nil
    end

    local function flushHeader()
        if header then
            items[#items + 1] = { text = header, enabled = false }
            header = nil
        end
    end

    for i, row in ipairs(first) do
        local d = row._sui
        local kind = d and d.kind
        if kind == "header" then
            flushHeader()
            header = d.text
        elseif kind == "skip" then
            -- shown as part of the row before it
        elseif kind == "radio" then
            local title = d.title or header or tr("Choose")
            if d.title then flushHeader() end
            header = nil
            items[#items + 1] = radioItem(title,
                function() local x = fresh(i, "radio"); return x and x.options or d.options end,
                function() local x = fresh(i, "radio"); if x then return x.current end end,
                function(v) local x = fresh(i, "radio"); if x then x.on_pick(v) end end,
                after)
        elseif kind == "input" then
            flushHeader()
            items[#items + 1] = inputItem(d.label,
                function() local x = fresh(i, "input", d.label); if x then return x.value end end,
                function(v) local x = fresh(i, "input", d.label); if x then x.on_save(v) end end,
                d.o, after)
        elseif kind == "date" then
            flushHeader()
            items[#items + 1] = dateItem(d.label,
                function() local x = fresh(i, "date", d.label); if x then return x.value end end,
                function(v) local x = fresh(i, "date", d.label); if x then x.on_save(v) end end,
                after)
        elseif kind == "pick" then
            flushHeader()
            items[#items + 1] = radioItem(d.label,
                function() local x = fresh(i, "pick", d.label); return x and x.options or d.options end,
                function() local x = fresh(i, "pick", d.label); if x then return x.current end end,
                function(v) local x = fresh(i, "pick", d.label); if x then x.on_pick(v) end end,
                after)
        elseif kind == "multi" then
            flushHeader()
            items[#items + 1] = multiItem(d.label,
                function() local x = fresh(i, "multi", d.label); return x and x.options or d.options end,
                function() local x = fresh(i, "multi", d.label); return x and x.current or {} end,
                function(v) local x = fresh(i, "multi", d.label); if x then x.on_change(v) end end,
                d.any_label, after)
        elseif kind == "submenu" then
            flushHeader()
            local rows_of = d.rows_fn
            items[#items + 1] = {
                text = d.label,
                sub_item_table_func = function() return S.rowsMenu(rows_of, after) end,
            }
        else
            flushHeader()
            for j, b in ipairs(row) do
                if type(b) == "table" and b.text and b.callback and b.enabled ~= false then
                    -- the row as it is now: its name and what it does move on
                    -- with the settings (a Control centre button renamed)
                    local function now()
                        local r = (rows_fn() or {})[i]
                        local nb = type(r) == "table" and r[j] or nil
                        if type(nb) == "table" and nb.callback and nb.text then return nb end
                        return b
                    end
                    items[#items + 1] = {
                        text_func = function() return now().text end,
                        keep_menu_open = true,
                        callback = function() now().callback() end,
                    }
                end
            end
        end
    end
    flushHeader()
    return items
end

-- ─── shared rows ─────────────────────────────────────────────────────────────

local function toneOptions()
    local out = {}
    for _, t in ipairs(A.TONES) do out[#out + 1] = { t, A.toneLabel(t) } end
    return out
end

local function accentOptions(with_matched)
    local out = {}
    if with_matched then out[1] = { "matched", T("Matched to the first") } end
    for _, id in ipairs(A.ACCENT_ORDER) do out[#out + 1] = { id, A.ACCENTS[id].label } end
    return out
end

-- Default, Cute or Cyber: every cute (or cyber) look at once (shows none
-- when some cards have a look of their own). Cyber also picks its theme.
local function styleItem(after)
    return radioItem(T("Style"),
        function() return { { "default", T("Default") }, { "cute", T("Cute") }, { "cyber", T("Cyber") }, { "academia", T("Dark Academia") } } end,
        A.styleNow, A.setStyle, after)
end
S.styleItem = styleItem

--- "Look and colours": the theme and accents every card shares.
function S.lookMenu(mctx)
    local function after() S.reloadAll(mctx) end
    return {
        text = T("Look and colours"),
        sub_item_table_func = function()
            local themes = {}
            for _, id in ipairs(A.THEME_ORDER) do themes[#themes + 1] = { id, A.THEMES[id].label } end
            return {
                radioItem(T("Theme"), function() return themes end, A.themeId,
                    function(v) A.set("theme", v) end, after),
                styleItem(after),
                radioItem(T("Accent colour"), function() return accentOptions(false) end,
                    function() return (A.accentIds()) end,
                    function(v) A.set("accent", v) end, after),
                radioItem(T("Second accent"), function() return accentOptions(true) end,
                    function()
                        local v = A.get("accent2", nil)
                        return A.ACCENTS[v] and v or "matched"
                    end,
                    function(v) A.set("accent2", v ~= "matched" and v or nil) end, after),
                radioItem(T("Cards on their own"),
                    function() return { { "native", T("Match Simple UI") }, { "framed", T("Framed, in the theme") } } end,
                    function() return A.standaloneNative() and "native" or "framed" end,
                    function(v) A.set("standalone", v ~= "native" and v or nil) end, after),
                radioItem(T("Week starts on"),
                    function() return { { 0, T("Follow KOReader") }, { 2, T("Monday") }, { 1, T("Sunday") } } end,
                    function() return tonumber(A.get("week_start", 0)) or 0 end,
                    function(v) A.set("week_start", v ~= 0 and v or nil) end, after),
                { text = T("Diagnostics") .. ELLIPSIS, keep_menu_open = true,
                  callback = function() S.diagnostics(mctx) end },
            }
        end,
    }
end

local function tapItem(name, after)
    return radioItem(T("When tapped"),
        function() return S.tapOptions(name) end,
        function() return S.tapValue(name) end,
        function(v)
            local label
            for _, o in ipairs(S.tapOptions(name)) do
                if o[1] == v then label = o[3] or o[2] end
            end
            S.setTapValue(name, v, label)
        end,
        after,
        function(label)
            for _, o in ipairs(S.tapOptions(name)) do
                if o[2] == label then return o[1] == "own" and T("The card's own") or (o[3] or o[2]) end
            end
            return label
        end)
end

local function colourItem(name, env_fn, after)
    return radioItem(T("Card colour"), toneOptions,
        function() return env_fn().tone.name end,
        function(v) A.set(name .. "_tone", v) end, after)
end

local function heightItem(mctx, after)
    local key = A.screenKey(mctx.pfx, mctx.mod_id, "height")
    return numberItem(T("Card height"),
        function() return A.cardHeightPct(mctx.pfx, mctx.mod_id) end,
        function(v) A.set(key, v ~= A.HEIGHT_DEF and v or nil) end,
        { min = A.HEIGHT_MIN, max = A.HEIGHT_MAX, step = 5, unit = "%", default = A.HEIGHT_DEF,
          description = T("Height of this card, against the shape it was designed at.") .. "\n" .. T("100% is the default.") },
        after)
end

local function textItem(mctx, after, what)
    local key = A.screenKey(mctx.pfx, mctx.mod_id, "text")
    return numberItem(T("Text size"),
        function() return A.textSizePct(mctx.pfx, mctx.mod_id) end,
        function(v) A.set(key, v ~= A.TEXT_DEF and v or nil) end,
        { min = A.TEXT_MIN, max = A.TEXT_MAX, step = 5, unit = "%", default = A.TEXT_DEF,
          description = A.tr("Size of the text on %1. Small text grows fully, big figures and titles by half.", what) .. "\n" .. T("100% is the default.") },
        after)
end

-- Put a menu together in Simple UI's usual sections, or as one flat list.
local function assemble(ctx_menu, spec)
    local Cfg = Config()
    if ctx_menu and Cfg and Cfg.buildModuleMenu then
        local ok, items = pcall(Cfg.buildModuleMenu, spec, ctx_menu)
        if ok and type(items) == "table" then return items end
    end
    local flat = {}
    for _, part in ipairs({ spec.content or {}, (spec.appearance or {}).size or {},
                            (spec.appearance or {}).extra or {}, spec.behaviour or {} }) do
        for _, it in ipairs(part) do flat[#flat + 1] = it end
    end
    return flat
end

--- The settings of card `name`. o.nested = inside the Dashboard (no height or
--- set of its own there).
function S.cardMenu(name, mctx, ctx_menu, o)
    o = o or {}
    local def = P[name]
    if not def then return {} end
    local function env_fn()
        return A.makeEnv(name, mctx, 0, 0, o.nested and { nested = true, slot = 1 } or nil)
    end
    local function after() S.reload(mctx) end
    local api = menuApi(after)
    local content = S.rowsMenu(function()
        local fn = S.ROWS[name]
        if not fn then return {} end
        local ok, rows = pcall(fn, env_fn(), api, mctx)
        return ok and rows or {}
    end, after)
    if def.slots and not o.nested then
        table.insert(content, 1, radioItem(T("This card shows"),
            function() return { { 1, T("Set 1") }, { 2, T("Set 2") }, { 3, T("Set 3") } } end,
            function()
                local ok, v = pcall(mctx.config.get, mctx.config, "alm_slot", 1)
                return ok and tonumber(v) or 1
            end,
            function(v) mctx.config:set("alm_slot", v) end, after))
    end
    local spec = {
        content = (#content > 0) and content or nil,
        appearance = {
            size = (not o.nested) and { heightItem(mctx, after), textItem(mctx, after, T("this card")) } or nil,
            extra = { colourItem(name, env_fn, after), S.lookMenu(mctx) },
        },
        behaviour = { tapItem(name, after) },
    }
    if o.nested then return assemble(nil, spec) end
    return assemble(ctx_menu, spec)
end

--- The Dashboard's settings.
function S.dashboardMenu(mctx, ctx_menu)
    local function after() S.reload(mctx) end
    local key_h = A.screenKey(mctx.pfx, mctx.mod_id, "dash_height")
    local content = {
        { text = T("Pages and cards") .. ELLIPSIS, keep_menu_open = true,
          callback = function() A.dashEditPages(mctx, nil) end },
        styleItem(function() S.reloadAll(mctx) end),
        radioItem(T("Margin around the page"),
            function() return { { "none", T("None") }, { "small", T("Small") }, { "medium", T("Medium") } } end,
            function()
                local v = A.get("dash_margin", "small")
                return A.DASH_MARGINS[v] and v or "small"
            end,
            function(v) A.set("dash_margin", v ~= "small" and v or nil) end, after),
        {
            text = T("Card settings"),
            sub_item_table_func = function()
                local items, seen = {}, {}
                for _, page in ipairs(A.dashPages()) do
                    for _, r in ipairs(A.dashPageRows(page)) do
                        for _, name in ipairs(r.cards) do
                            if not seen[name] and P[name] then
                                seen[name] = true
                                items[#items + 1] = {
                                    text = P[name].title,
                                    sub_item_table_func = function()
                                        return S.cardMenu(name, mctx, nil, { nested = true })
                                    end,
                                }
                            end
                        end
                    end
                end
                return items
            end,
        },
        { text = T("Put the whole Dashboard back as it came") .. ELLIPSIS, keep_menu_open = true,
          callback = function()
              local UIManager = require("ui/uimanager")
              local ConfirmBox = require("ui/widget/confirmbox")
              UIManager:show(ConfirmBox:new{
                  text = T("Put every page, tab and row of the Dashboard back as it came?") .. "\n\n"
                      .. T("Pages you added are removed. Each card's own settings and the colours are kept."),
                  ok_text = T("Put back"),
                  ok_callback = function()
                      A.resetDashboard()
                      after()
                  end,
              })
          end },
    }
    local heights = { { "fill", T("Fill the page") } }
    for _, pct in ipairs({ 90, 80, 70, 60, 50 }) do heights[#heights + 1] = { pct, A.tr("%1% of the screen", pct) } end
    local spec = {
        content = content,
        appearance = {
            size = { radioItem(T("Height"), function() return heights end,
                function() return A.dashHeightMode(mctx.pfx, mctx.mod_id) end,
                function(v) A.set(key_h, v ~= "fill" and v or nil) end, after),
                textItem(mctx, after, T("all the Dashboard's cards")) },
            extra = { S.lookMenu(mctx) },
        },
    }
    return assemble(ctx_menu, spec)
end

return true
