--[[
Reading Log: reading dashboard cards for KOReader's home screens, Simple UI
and Bookshelf, from one plugin.

  Simple UI   When KOReader starts the plugin, every Reading Log card (and
              the Dashboard) is registered with Simple UI's module registry,
              the documented way for another plugin to add modules.
  Bookshelf   Bookshelf 6.0 and newer load the cards themselves from this
              plugin's bookshelf_modules/ folder (a "module pack"). Nothing
              to do here, except to clear away the older micro-modules copy
              if it is still installed, since Bookshelf would use that one.

Both use the same code (readinglog/) and the same settings file
(settings/readinglog.lua). This file also adds Reading Log to KOReader's
Tools menu: Open the dashboard, Styles and colours, Your reading (what counts
as finished, the week, a book's dates), the reader panel, and About and
updates.
]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local gettext = require("gettext")

local DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."

-- A Mac copying files onto the e-reader leaves a hidden "._" twin beside
-- each one (Finder's own data, not Lua). Bookshelf tries every .lua file in
-- bookshelf_modules/ and logs "micro-module failed to load" for each twin,
-- so they are removed from this plugin's own folder as KOReader loads it,
-- before Bookshelf looks for modules. Nothing outside the plugin is touched.
local function removeMacTwins(dir, lfs, depth, removed)
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            local path = dir .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "file" and name:sub(1, 2) == "._" then
                if os.remove(path) then removed[#removed + 1] = name end
            elseif mode == "directory" and depth < 3 and name:sub(1, 1) ~= "." then
                removeMacTwins(path, lfs, depth + 1, removed)
            end
        end
    end
    return removed
end
do
    local ok, removed = pcall(function()
        return removeMacTwins(DIR, require("libs/libkoreader-lfs"), 0, {})
    end)
    if ok and #removed > 0 then
        logger.info("[readinglog] removed", #removed, "hidden ._ files a Mac left in the plugin folder")
    end
end

-- The card kit for Simple UI, loaded once per KOReader session. (Bookshelf's
-- own copy is loaded by the bookshelf_modules/ files, as package.loaded.almanac_kit.)
local function kit()
    local A = package.loaded["readinglog_kit"]
    if A then return A end
    local ok, r = pcall(dofile, DIR .. "/readinglog/init.lua")
    if not ok or type(r) ~= "table" then
        logger.err("[readinglog] could not load the cards:", r)
        return nil
    end
    package.loaded["readinglog_kit"] = r
    return r
end

local function simpleUIThere()
    local ok, Registry = pcall(require, "modules/moduleregistry")
    return ok and type(Registry) == "table" and Registry.register and Registry or nil
end

-- Bookshelf's version ("6.0.4"), or nil when Bookshelf isn't running.
local function bookshelfVersion()
    local ok, v = pcall(function()
        local Kit = require("lib/bookshelf_module_kit")
        local fn
        for _, f in pairs(Kit) do if type(f) == "function" then fn = f break end end
        local src = debug.getinfo(fn, "S").source:gsub("^@", "")
        return dofile(src:match("^(.*)/lib/[^/]*$") .. "/_meta.lua").version
    end)
    return ok and type(v) == "string" and v or nil
end

local function majorOf(v) return tonumber(tostring(v or ""):match("^(%d+)")) or 0 end

-- Register every module with Simple UI. Safe to call again: done once per
-- registry (a Simple UI reloaded in place gets a new one, and is told again).
local function register()
    local Registry = simpleUIThere()
    if not Registry then return false end
    local A = kit()
    if not A then return false end
    if A._registered_with == Registry then return true end
    for _, m in ipairs(A.simpleUIModules()) do
        local ok2, err = pcall(Registry.register, m)
        if not ok2 then logger.warn("[readinglog] could not register", m.id, err) end
    end
    A._registered_with = Registry
    logger.info("[readinglog] registered", #A.simpleUIModules(), "modules with Simple UI")
    -- a screen already on display gets the modules placed on it drawn now
    local SE = package.loaded["engines/sui_screen_engine"]
    if SE and SE.liveScreenIds and SE.refreshAllLiveImmediate then
        local ok3, ids = pcall(SE.liveScreenIds)
        if ok3 and type(ids) == "table" and #ids > 0 then pcall(SE.refreshAllLiveImmediate, false) end
    end
    return true
end

-- Our own catalogs (readinglog/locales) first, then KOReader's.
local _cat
local function _(s)
    local A = package.loaded["readinglog_kit"] or package.loaded["almanac_kit"]
    local T = A and A._
    if not T then
        if _cat == nil then
            local ok, I = pcall(dofile, DIR .. "/readinglog/i18n.lua")
            _cat = ok and type(I) == "table" and I or false
        end
        T = _cat and _cat.gettext
    end
    if T then
        local t = T(s)
        if t ~= s then return t end
    end
    return gettext(s)
end

-- "%1" placeholders, filled in after translating
local function fmt(s, ...)
    local args = { ... }
    return (_(s):gsub("%%(%d+)", function(i)
        local v = args[tonumber(i)]
        return v == nil and ("%" .. i) or tostring(v)
    end))
end

-- ─── the older Bookshelf micro-modules copy ──────────────────────────────────
-- Reading Log used to be copied into settings/bookshelf/micromodules (the
-- alm_*.lua files and the almanac folder). Bookshelf prefers cards in that
-- folder to a plugin's, so while they are there the old version keeps
-- running. Offer to remove them (settings live elsewhere and are kept).

local function oldCopyDir()
    local ok, DataStorage = pcall(require, "datastorage")
    if not (ok and DataStorage) then return nil end
    return DataStorage:getSettingsDir() .. "/bookshelf/micromodules"
end

local function oldCopies()
    local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local dir = oldCopyDir()
    if not (lfs_ok and dir and lfs.attributes(dir, "mode") == "directory") then return nil end
    local files, kit_dir = {}, nil
    for name in lfs.dir(dir) do
        if name:match("^alm_.+%.lua$") then files[#files + 1] = dir .. "/" .. name end
    end
    if lfs.attributes(dir .. "/almanac/init.lua", "mode") == "file" then kit_dir = dir .. "/almanac" end
    if #files == 0 and not kit_dir then return nil end
    return { files = files, kit_dir = kit_dir, dir = dir }
end

-- The same "._" twins a Mac leaves next to the old copy's files (or left
-- behind after them, when the real files were deleted in Finder): Bookshelf
-- tries each as a card and logs "micro-module failed to load ... unexpected
-- symbol" for every one, each time its module list is built. Only the twins
-- of Reading Log's own files (._alm_*.lua, ._almanac) are removed.
local function removeOldTwins()
    local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local dir = oldCopyDir()
    if not (lfs_ok and dir and lfs.attributes(dir, "mode") == "directory") then return end
    local removed = 0
    for name in lfs.dir(dir) do
        if name:match("^%._alm_.+%.lua$") or name == "._almanac" then
            if os.remove(dir .. "/" .. name) then removed = removed + 1 end
        end
    end
    if removed > 0 then
        logger.info("[readinglog] removed", removed, "hidden ._ files a Mac left in", dir)
    end
end
pcall(removeOldTwins)

local function removeTree(path, lfs)
    if lfs.attributes(path, "mode") == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then removeTree(path .. "/" .. name, lfs) end
        end
        return lfs.rmdir(path)
    end
    return os.remove(path)
end

local function removeOldCopies(found)
    local lfs = require("libs/libkoreader-lfs")
    local left = 0
    for _, f in ipairs(found.files) do
        if not os.remove(f) then left = left + 1 end
    end
    if found.kit_dir then
        pcall(removeTree, found.kit_dir, lfs)
        if lfs.attributes(found.kit_dir, "mode") then left = left + 1 end
    end
    logger.info("[readinglog] removed the old micro-modules copy;", left, "left")
    return left == 0
end

local asked_old = false
local function offerOldRemoval()
    if asked_old then return end
    local found = oldCopies()
    if not found then return end
    -- only once Bookshelf can load the plugin's cards: an older one keeps
    -- the copy it has
    if majorOf(bookshelfVersion()) < 6 then return end
    asked_old = true
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = _("Reading Log is a plugin now. The older copy of its Bookshelf cards is still in koreader/settings/bookshelf/micromodules, and Bookshelf uses that one instead of the plugin's.") .. "\n\n"
            .. _("Remove the old copy? Your Reading Log settings are kept."),
        ok_text = _("Remove"),
        cancel_text = _("Not now"),
        ok_callback = function()
            local all = removeOldCopies(found)
            if all then
                local msg = _("The old copy is gone. Restart KOReader to load the plugin's cards.")
                if UIManager.askForRestart then
                    UIManager:askForRestart(msg)
                else
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{ text = msg })
                end
            else
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = fmt("Some files could not be removed. Delete the alm_*.lua files and the almanac folder in %1 by hand, then restart KOReader.", found.dir),
                })
            end
        end,
    })
end

-- ─── the reader panel ────────────────────────────────────────────────────────
-- Under the reader's top menu when it opens: the book, today's numbers,
-- the rings and buttons (readinglog/readerpanel.lua). Off until switched on
-- in Tools > Reading Log > Reader panel. While it is off, all this does is
-- read that one setting; the cards' code is only loaded once it is on.

local function store()
    local St = package.loaded["readinglog_store"]
    if St then return St end
    local ok, r = pcall(dofile, DIR .. "/readinglog/store.lua")
    return ok and type(r) == "table" and r or nil
end

local function panelOn()
    local St = store()
    if not St then return false end
    local ok, v = pcall(St.get, "panel_on")
    return ok and v == true
end

-- The panel's code, from whichever copy of the cards is loaded already.
local function panelCode()
    local A = package.loaded["readinglog_kit"] or package.loaded["almanac_kit"] or kit()
    return A and A.readerPanel and A.readerPanel() or nil, A
end

local function installPanelHook()
    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if not ok or type(TouchMenu) ~= "table" or TouchMenu._readinglog_panel_patched then return end
    TouchMenu._readinglog_panel_patched = true

    -- the reader's menu starts on the panel
    local orig_init = TouchMenu.init
    TouchMenu.init = function(menu, ...)
        orig_init(menu, ...)
        if not panelOn() then return end
        local RP = panelCode()
        if RP and RP.isReaderMenu(menu) then
            local ok2, err = pcall(RP.show, menu, true)
            if not ok2 then logger.warn("[readinglog] reader panel:", err) end
        end
    end

    -- tapping the open tab comes back to it
    local orig_switch = TouchMenu.switchMenuTab
    TouchMenu.switchMenuTab = function(menu, tab_num, ...)
        if not menu._readinglog_panel and menu.cur_tab == tab_num and panelOn() then
            local RP = panelCode()
            if RP and RP.isReaderMenu(menu) then
                local ok2, shown = pcall(RP.show, menu)
                if ok2 and shown then return end
            end
        end
        menu._readinglog_panel = nil
        return orig_switch(menu, tab_num, ...)
    end

    -- a tab's list drawn again (a page turn, a setting) replaces it
    local orig_update = TouchMenu.updateItems
    TouchMenu.updateItems = function(menu, ...)
        menu._readinglog_panel = nil
        return orig_update(menu, ...)
    end
end

-- Tools > Reading Log > Reader panel
local function panelMenu()
    local RP, A = panelCode()
    if not RP then return { { text = _("Reading Log could not be loaded."), enabled = false } } end
    local function on() return RP.enabled() end
    local items = {
        {
            text = _("Show it when the reader's menu opens"),
            help_text = _("Opens the reader's top menu on the book, today's numbers, your rings and buttons. Tap the open tab to come back to it from a tab's list."),
            checked_func = on,
            callback = function() RP.setEnabled(not RP.enabled()) end,
            separator = true,
        },
    }
    local parts = {}
    for pi = 1, #RP.PARTS do
        local p = RP.PARTS[pi]
        parts[#parts + 1] = {
            text = p.label,
            enabled_func = on,
            checked_func = function() return RP.partOn(p.key) end,
            callback = function() RP.setPart(p.key, not RP.partOn(p.key)) end,
        }
    end
    items[#items + 1] = { text = _("What it shows"), enabled_func = on, sub_item_table = parts }

    local function buttonMenu(i)
        local list = RP.editableButtons()
        local e = list[i]
        -- KOReader's action chooser (as for gestures) changes e.action in
        -- place and says so by setting `updated`. One action to a button:
        -- the one just picked replaces the one before (the newest is last
        -- in the order KOReader keeps once there are two).
        local caller = setmetatable({}, { __newindex = function(_, k, v)
            if not (k == "updated" and v) then return end
            local act = e.action
            local order = type(act) == "table" and type(act.settings) == "table" and act.settings.order
            if type(order) == "table" and #order > 1 then
                local keep = order[#order]
                e.action = { [keep] = act[keep] }
            end
            RP.saveButtons(list)
        end })
        local actions = {}
        local okd, Dispatcher = pcall(require, "dispatcher")
        if okd and Dispatcher and Dispatcher.addSubMenu then
            pcall(Dispatcher.addSubMenu, Dispatcher, caller, actions, e, "action")
        end
        -- the icon: a glyph, one of KOReader's own icons, or a picture of
        -- your own (a picture wins over the glyph while it is set)
        local glyphs = {}
        local names = {}
        for ni = 1, #A.S.ICON_ORDER do
            local n = A.S.ICON_ORDER[ni]
            names[#names + 1] = { n, A.S.ICONS[n] }
        end
        names[#names + 1] = { "sliders", RP.EXTRA_ICONS.sliders }
        names[#names + 1] = { "exit", RP.EXTRA_ICONS.exit }
        for gi = 1, #names do
            local pair = names[gi]
            local g = pair[2]
            glyphs[#glyphs + 1] = {
                text = g .. "   " .. pair[1],
                radio = true,
                checked_func = function() return not e.image and e.icon == g end,
                callback = function() e.icon, e.image = g, nil; RP.saveButtons(list) end,
            }
        end
        local function koIcons(touchmenu_instance)
            local ButtonDialog = require("ui/widget/buttondialog")
            local all = {}
            for ni = 1, #RP.KO_ICONS do all[#all + 1] = RP.KO_ICONS[ni] end
            local own = RP.ownIcons()
            for ni = 1, #own do all[#all + 1] = own[ni] end
            local dialog
            local rows, row = {}, {}
            for ni = 1, #all do
                local name = all[ni]
                local path = RP.koIconPath(name)
                if path then
                    row[#row + 1] = { icon = name, callback = function()
                        UIManager:close(dialog)
                        e.image = path
                        RP.saveButtons(list)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end }
                    if #row == 6 then rows[#rows + 1] = row; row = {} end
                end
            end
            if #row > 0 then rows[#rows + 1] = row end
            rows[#rows + 1] = { { text = _("Close"), callback = function() UIManager:close(dialog) end } }
            dialog = ButtonDialog:new{ title = _("KOReader's icons"), title_align = "center", buttons = rows }
            UIManager:show(dialog)
        end
        local function picture(touchmenu_instance)
            local okp, PathChooser = pcall(require, "ui/widget/pathchooser")
            if not okp then return end
            local St = store()
            local start = St and St.get("control_picture_dir") or nil
            if not start then
                local okds, DataStorage = pcall(require, "datastorage")
                start = okds and DataStorage:getDataDir() or "/"
            end
            UIManager:show(PathChooser:new{
                title = _("Pick a PNG, JPEG or SVG"),
                select_directory = false, select_file = true, show_files = true,
                path = start,
                file_filter = function(name)
                    local n = name:lower()
                    return n:match("%.png$") ~= nil or n:match("%.jpe?g$") ~= nil or n:match("%.svg$") ~= nil
                end,
                onConfirm = function(path)
                    e.image = path
                    RP.saveButtons(list)
                    if St then St.set("control_picture_dir", path:match("^(.*)/[^/]*$")) end
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end
        local icons = {
            { text = _("Glyph"), sub_item_table = glyphs },
            { text = _("KOReader's icons") .. "\xE2\x80\xA6", keep_menu_open = true, callback = koIcons },
            { text = _("A picture of your own (PNG, JPEG, SVG)") .. "\xE2\x80\xA6", keep_menu_open = true, callback = picture },
            {
                text_func = function()
                    local name = e.image and (e.image:match("([^/]+)$") or e.image)
                    return name and fmt("Showing: %1", name) or _("Showing the glyph")
                end,
                enabled_func = function() return e.image ~= nil end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    e.image = nil
                    RP.saveButtons(list)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                help_text = _("Tap to go back to the glyph."),
            },
        }
        return {
            { text = _("Action"), sub_item_table = actions },
            { text = _("Icon"), sub_item_table = icons },
            {
                text = _("Reset this button to default"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    RP.resetButton(i)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
        }
    end

    items[#items + 1] = {
        text_func = function() return fmt("Buttons: %1", RP.buttonCount()) end,
        enabled_func = on,
        sub_item_table_func = function()
            -- how many (a number to pick), then just the buttons in use
            local out = {}
            out[#out + 1] = {
                text_func = function() return fmt("How many: %1", RP.buttonCount()) end,
                keep_menu_open = true,
                separator = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("How many buttons"),
                        value = RP.buttonCount(), value_min = 0, value_max = RP.MAX_BUTTONS, value_step = 1,
                        ok_text = _("Set"),
                        callback = function(spin)
                            RP.setButtonCount(spin.value)
                            -- back up a level: opening Buttons again lists the new number
                            if touchmenu_instance then touchmenu_instance:backToUpperMenu() end
                        end,
                    })
                end,
            }
            for i = 1, RP.buttonCount() do
                out[#out + 1] = {
                    text_func = function()
                        local e = RP.editableButtons()[i]
                        local mark = e.image and A.S.ICONS.image or (e.icon or "")
                        return i .. ".  " .. mark .. "  " .. RP.buttonName(e)
                    end,
                    sub_item_table_func = function() return buttonMenu(i) end,
                }
            end
            return out
        end,
    }
    return items
end

-- ─── updates ─────────────────────────────────────────────────────────────────

local warned = false

-- Check for updates (see updater.lua), loaded when first needed.
local updater_mod
local function updater()
    if updater_mod == nil then
        local ok, mk = pcall(dofile, DIR .. "/updater.lua")
        local ok2, U = false, nil
        if ok and type(mk) == "function" then ok2, U = pcall(mk, DIR, _, fmt) end
        if not (ok2 and type(U) == "table") then
            logger.warn("[readinglog] updater could not be loaded:", ok and U or mk)
            updater_mod = false
        else
            updater_mod = U
        end
    end
    return updater_mod or nil
end
local auto_checked = false

-- ─── styles ──────────────────────────────────────────────────────────────────

-- The cards' code for Styles and colours...: Bookshelf's copy
-- when its cards are loaded, else Simple UI's, else Bookshelf's, loaded the
-- way its cards load it (so they share it).
local function stylesKit()
    local A = package.loaded["almanac_kit"]
    if A then return A end
    if simpleUIThere() then return kit() end
    local bs = bookshelfVersion()
    -- neither: the full-screen dashboard's (and ZenOS's) copy
    if not bs then return kit() end
    if majorOf(bs) < 6 then return nil end
    local ok, r = pcall(function()
        return assert(loadfile(DIR .. "/readinglog/init.lua"))("bookshelf")
    end)
    if not ok or type(r) ~= "table" then
        logger.err("[readinglog] could not load the cards:", r)
        return nil
    end
    package.loaded["almanac_kit"] = r
    return r
end

-- ─── the full-screen dashboard and ZenOS ─────────────────────────────────────

local function openDashboard()
    local A = kit()
    if A and A.openDashboard then
        local ok, err = pcall(A.openDashboard)
        if not ok then logger.warn("[readinglog] could not open the dashboard:", err) end
    end
end

local function toggleDashboard()
    local A = kit()
    if A and A.dashboardOpen and A.dashboardOpen() then A.closeDashboard() else openDashboard() end
end

-- Hand every card to ZenOS (or Zen UI), when it is there.
local function registerZen()
    if not (rawget(_G, "__ZENOS_REGISTER_HOME_ITEM") or rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")) then return false end
    local A = kit()
    if not (A and A.zenRegister) then return false end
    local ok, r = pcall(A.zenRegister)
    if not ok then logger.warn("[readinglog] could not add the ZenOS widgets:", r) end
    return ok and r
end

local function zenThere()
    return rawget(_G, "__ZENOS_REGISTER_HOME_ITEM") ~= nil or rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM") ~= nil
end


-- ─── the plugin ──────────────────────────────────────────────────────────────

local ReadingLog = WidgetContainer:extend{
    name = "readinglog",
    is_doc_only = false,
}

function ReadingLog:init()
    local in_book = self.ui and self.ui.document
    self:onDispatcherRegisterActions()
    -- The gesture reaches the plugin even with another screen in front (Simple
    -- UI's Home, a dialog): KOReader hands the events nobody in front took to
    -- the "active widgets" of the windows below.
    if self.ui and type(self.ui.active_widgets) == "table" then
        table.insert(self.ui.active_widgets, self)
    end
    if not register() then
        -- Simple UI may not be ready yet: try again once everything has started.
        -- (Without Simple UI or Bookshelf, the full-screen dashboard and the
        -- ZenOS widgets still work.)
        UIManager:nextTick(function()
            if register() or warned or in_book then return end
            local bs = bookshelfVersion()
            local text
            if bs and majorOf(bs) < 6 then
                text = _("Reading Log's cards need Bookshelf 6.0 or newer.")
            end
            if text then
                warned = true
                logger.warn("[readinglog]", text)
                local Notification = require("ui/widget/notification")
                UIManager:show(Notification:new{ text = text })
            end
        end)
    end
    if not in_book then
        UIManager:nextTick(function() pcall(offerOldRemoval) end)
    end
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    installPanelHook()
    -- ZenOS loads after Reading Log and says when it is ready (onZenOSReady);
    -- this catches one that was already there
    if zenThere() then registerZen() end
    if not auto_checked then
        auto_checked = true
        local U = updater()
        if U then pcall(U.autoCheck) end
    end
end

function ReadingLog:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not (ok and Dispatcher and Dispatcher.registerAction) then return end
    pcall(Dispatcher.registerAction, Dispatcher, "readinglog_dashboard", {
        category = "none", event = "ReadingLogDashboard", title = _("Reading Log dashboard"), general = true,
    })
end

function ReadingLog:onReadingLogDashboard()
    toggleDashboard()
    return true
end

-- A quote card asked to open its book at the highlight (D.openAtHighlight):
-- once the book is open, turn to it. The place you had reached stays on the
-- back stack, so KOReader's Back (or Go back to previous location) returns
-- you there.
function ReadingLog:onReaderReady()
    local j = package.loaded["readinglog_goto"]
    local ui = self.ui
    local file = ui and ui.document and ui.document.file
    if type(j) ~= "table" or not file then return end
    package.loaded["readinglog_goto"] = nil
    if j.fp ~= file or os.time() - (j.at or 0) > 120 then return end
    UIManager:nextTick(function()
        local ok, err = pcall(function()
            local Event = require("ui/event")
            if ui.link and ui.link.addCurrentLocationToStack then ui.link:addCurrentLocationToStack() end
            if ui.rolling and type(j.page) == "string" then
                ui:handleEvent(Event:new("GotoXPointer", j.page, type(j.pos0) == "string" and j.pos0 or j.page))
            elseif tonumber(j.page) then
                ui:handleEvent(Event:new("GotoPage", tonumber(j.page)))
            end
        end)
        if not ok then logger.warn("[readinglog] could not turn to the highlight:", err) end
    end)
end

function ReadingLog:onZenOSReady() registerZen() end
function ReadingLog:onZenUIReady() registerZen() end

function ReadingLog:addToMainMenu(menu_items)
    local items = {}
    items[#items + 1] = {
        text = _("Open the dashboard"),
        enabled_func = function() return kit() ~= nil end,
        callback = function() openDashboard() end,
        help_text = _("The dashboard on a screen of its own. Swipe left or right for the next page, swipe down to close it, long-press a card for its settings. It can also go on a gesture: Reading Log dashboard, under General."),
        separator = true,
    }
    -- A setting both apps share (Simple UI's and Bookshelf's cards): set it,
    -- then have both count and draw again
    local function anyKit() return package.loaded["readinglog_kit"] or package.loaded["almanac_kit"] or kit() end
    local function getShared(key, default)
        local A = anyKit()
        return A and A.get(key, default) or default
    end
    local function setShared(key, v)
        local A = anyKit()
        if not A then return end
        A.set(key, v)
        for _, k in ipairs({ "readinglog_kit", "almanac_kit" }) do
            local K = package.loaded[k]
            if type(K) == "table" and K.D then
                pcall(K.D.invalidate)
                pcall(K.host.redrawAll)
            end
        end
    end
    local function radio(key, v, label, default)
        return {
            text = label, radio = true,
            checked_func = function()
                local cur = getShared(key, default)
                return tostring(cur) == tostring(v)
            end,
            callback = function() setShared(key, v ~= default and v or nil) end,
        }
    end

    -- Styles and colours: the style, its accents, and the styles to download
    items[#items + 1] = {
        text = _("Styles and colours") .. "\xE2\x80\xA6",
        enabled_func = function() return stylesKit() ~= nil end,
        callback = function()
            local A = stylesKit()
            if A then A.S.look(nil, nil, { tools = true }) end
        end,
    }

    -- Your reading: what counts, the dates, the week
    items[#items + 1] = {
        text = _("Your reading"),
        sub_item_table_func = function()
            local finished = getShared("finished_by", "marked")
            if finished ~= "read" and finished ~= "either" then finished = "marked" end
            return {
                {
                    text = _("A book counts as finished when"),
                    sub_item_table = {
                        radio("finished_by", "marked", _("Marked finished"), "marked"),
                        radio("finished_by", "read", _("Read to the end"), "marked"),
                        radio("finished_by", "either", _("Either"), "marked"),
                    },
                    help_text = _("Marked finished: the way your home screen counts finished books, on the day it was marked. Read to the end: the reading statistics show you reached the last 1% of the book, on the day you got there, marked or not. Either: one or the other."),
                },
                {
                    text = _("Week starts on"),
                    sub_item_table = {
                        radio("week_start", 0, _("Follow KOReader"), 0),
                        radio("week_start", 2, _("Monday"), 0),
                        radio("week_start", 1, _("Sunday"), 0),
                    },
                },
                {
                    text = _("Change a book's dates") .. "\xE2\x80\xA6",
                    help_text = _("When you started a book and when you finished it, for when the reading statistics or your home screen have them wrong. Every card uses the dates you set here."),
                    keep_menu_open = true,
                    callback = function()
                        local A = anyKit()
                        if A and A.S and A.S.pickBookForDates then A.S.pickBookForDates(nil) end
                    end,
                },
            }
        end,
    }
    items[#items + 1] = {
        text = _("Reader panel"),
        sub_item_table_func = panelMenu,
        separator = true,
    }

    -- About and updates
    local function about()
        local meta_ok, meta = pcall(dofile, DIR .. "/_meta.lua")
        local version = meta_ok and type(meta) == "table" and meta.version or "?"
        local sui = simpleUIThere()
        local sui_v
        if sui then
            local A = kit()
            sui_v = A and A.host.version() or _("found")
        end
        local bs = bookshelfVersion()
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = fmt([[Reading Log %1

Simple UI: %2
Bookshelf: %3

With Simple UI: Simple UI Settings > Home Screen > Layout Editor (or Extra Custom Screens), open a page, tap Add Module and pick any "Reading Log · …" module. For the Dashboard, give it a page of its own and set its Top Margin to 0.

With Bookshelf (6.0 or newer): open its layout editor, tap + Add and pick the Reading Log cards.

With ZenOS: Zen Settings > Home > Widgets, and turn on the Reading Log ones.

On its own: Tools > Reading Log > Open the dashboard, or put "Reading Log dashboard" on a gesture.

Long-press a card for its settings.

Ring designs and the dashboard idea: u/fishnoogz on Reddit.]],
                version,
                sui_v or _("not found"),
                bs or _("not found")),
        })
    end
    items[#items + 1] = {
        text_func = function()
            local U = updater()
            local v = U and U.found()
            return v and fmt("About and updates (%1 is out)", v) or _("About and updates")
        end,
        sub_item_table = {
            {
                text_func = function()
                    local U = updater()
                    local v = U and U.found()
                    return v and fmt("Update available: %1", v) or _("Check for updates")
                end,
                enabled_func = function() return updater() ~= nil end,
                keep_menu_open = true,
                callback = function()
                    local U = updater()
                    if U then U.check() end
                end,
            },
            {
                text = _("Check for updates automatically"),
                help_text = _("Once a day at most, when you're already online. A new version is mentioned, never installed without asking."),
                checked_func = function()
                    local U = updater()
                    return U and U.autoEnabled() or false
                end,
                enabled_func = function() return updater() ~= nil end,
                keep_menu_open = true,
                callback = function()
                    local U = updater()
                    if U then U.setAuto(not U.autoEnabled()) end
                end,
                separator = true,
            },
            {
                text = _("Diagnostics") .. "\xE2\x80\xA6",
                enabled_func = function() return kit() ~= nil end,
                keep_menu_open = true,
                callback = function()
                    local A = kit()
                    if A and A.S.diagnostics then A.S.diagnostics(nil) end
                end,
            },
            { text = _("About"), keep_menu_open = true, callback = about },
        },
    }
    menu_items.readinglog = {
        text = _("Reading Log"),
        sorting_hint = "tools",
        sub_item_table = items,
    }
end

return ReadingLog
