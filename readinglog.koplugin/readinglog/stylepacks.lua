--[[
Styles you can download: style packs.

A style pack is a folder in settings/readinglog/styles/<id>/ with a
style.lua (and, if it draws anything of its own, a draw.lua). It can:

  * bring its own theme: card, page, ink and frame colours, two accents,
    square or round corners, a serif;
  * pick a look for every card from the looks Reading Log already has
    (the Cute hearts, the Cyber segments, the Dark Academia pocket watch...);
  * draw the rings and the progress bars its own way (draw.lua).

style.lua returns:

  {
    api = 1,                       -- the version of this format
    id = "christmas",              -- the folder's name: a-z, 0-9 and _
    version = "1.0",
    name = "Christmas",  names = { es = "Navidad", ... },
    description = "...", descriptions = { es = "...", ... },
    author = "...",
    base = "cute",                 -- optional: start from a built-in style's looks
    looks = { quote_look = "paper", ... },   -- optional: card looks, by name
    theme = {                      -- optional
      surface = {r,g,b}, tint = {r,g,b}, fg = {r,g,b}, border = {r,g,b},
      page = {r,g,b}, page_fg = {r,g,b}, thin = bool, square = bool, serif = bool,
      accent  = "red" or { deep = {r,g,b}, bright = {r,g,b} },
      accent2 = "green" or { deep = ..., bright = ... },
    },
    draw = "draw.lua",             -- optional
  }

draw.lua returns a table of drawing functions, each optional:

  ring(c, cx, cy, R, t, frac, track, fill, tone, which)
      one ring of a rings card: centre, radius, thickness, how full (0..1),
      the empty colour and the filled colour. which = 1 for the pages ring
      (the first accent), 2 for the time ring (the second), 0 otherwise.
  bar(c, x, y, w, h, frac, tone, fill)
      a progress bar: a book's progress on Continue reading and Book club.
  challenge(c, cx, cy, R, frac, tone, fill)
      the Monthly challenge's centrepiece, in a circle of radius R (the
      percentage is written beside it).
  day(c, cx, cy, d, fp, fm, tone, o)
      one day of the Week and Month rings, in a d x d box: fp and fm are how
      far the day got to the pages and minutes goals (0..1 or more).
      o = { today, future, past, small }.
  goal(c, x, y, w, h, done, target, tone)
      the Year goal's picture, in the box on the card's left.
  chartBar(c, x, y, w, h, tone, fill, o)
      one bar of a bar chart (Time read by month, Pages per day, This week),
      standing on y + h. o = { current, i }.
  line(c, pts, xs, ys, n, lw, fill, tone, o)
      one line of the Books and pages chart: pts = { x1, y1, ... } along the
      curve, xs/ys the n points (months). o = { series = 1 books / 2 pages }.
  timeline(c, x, y, w, h, spans, now, tone)
      the strip of Today's timeline: spans = { { a, b, col } } as fractions of
      the strip, now (0..1, or nil).
  trendTile(c, x, y, w, h, tone, i)
      the tile behind one trend on Reading trends.
  trendBadge(c, cx, cy, r, dir, tone, fill)
      the round mark of a trend: dir is "up", "down" or "flat".
  calendarEmpty(c, x, y, w, h, n, tone, o)
      a calendar day with no reading: o = { today, future, num_px }.
  calendarCover(c, x, y, w, h, tone, o)
      called after a day's cover is drawn, to dress it: o = { today }.
  bookCover(c, x, y, w, h, tone, o)
      called after the cover on Continue reading is drawn, to dress it:
      o = { pct } (how far through the book, 0 to 1).
  tabBar(c, x, y, w, h, cells, tone)
      the Dashboard's row of tabs, along the bottom of its page: x, y, w, h
      is the whole row; cells = { { x, w, i, active, label_w, label_h } },
      one per tab. Draw the bar and mark the open tab; the names are written
      on top afterwards, centred in each cell (set cell.color to change a
      name's colour, cell.dx / cell.dy to move it right / down). tone is the page's colours.

  c is the card's canvas: c:ring, c:disc, c:rrect, c:frame, c:rect,
  c:polyline({x1,y1,x2,y2,...}, width, colour), c:heart, c:flower.
  Colours are {r,g,b} tables. Returning false draws the usual one instead.

Style files run with only math, string and table (no files, no network,
no os): a style can draw, nothing else. If one fails, the usual drawing is
used and the error goes to crash.log once.

Get more styles... (in Styles and colours) reads index.json from the
reading-log-styles repository on GitHub and downloads a style's files into
its folder.
]]

local A = ...
local T = A._
local K = {}
A.packs = K

K.API = 1
-- the styles live in a repository of their own
local REPO = "https://raw.githubusercontent.com/stevenzamora1/reading-log-styles/main/"
K.INDEX_URL = REPO .. "index.json"
K.FILES_URL = REPO

local installed = {}   -- id -> pack
local order = {}       -- ids, by name
local failed = {}      -- id -> true once its drawing has failed

local function settingsDir()
    local ok, DS = pcall(require, "datastorage")
    return ok and DS and DS:getSettingsDir() or "."
end

function K.dir() return settingsDir() .. "/readinglog/styles" end

local function lfs() return require("libs/libkoreader-lfs") end

local function ensureDir(path)
    local L = lfs()
    local acc = (path:sub(1, 1) == "/") and "" or nil
    for part in path:gmatch("[^/]+") do
        acc = acc and (acc .. "/" .. part) or part
        if L.attributes(acc, "mode") ~= "directory" then L.mkdir(acc) end
    end
    return L.attributes(path, "mode") == "directory"
end

-- Run a style file with nothing but math, string and table.
local function sandbox()
    return { math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, next = next,
             type = type, tostring = tostring, tonumber = tonumber, select = select, unpack = unpack,
             pcall = pcall, error = error, assert = assert }
end

local function runFile(path)
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    setfenv(chunk, sandbox())
    local ok, r = pcall(chunk)
    if not ok then return nil, r end
    if type(r) ~= "table" then return nil, path .. ": must return a table" end
    return r
end

local function isColour(c)
    return type(c) == "table" and #c == 3 and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

local function clampColour(c)
    local out = {}
    for i = 1, 3 do out[i] = math.max(0, math.min(255, math.floor(c[i] + 0.5))) end
    return out
end

-- The text in the interface language, from a pack's names/descriptions.
local function localized(base, by_lang)
    if type(by_lang) == "table" then
        local lang = (A.i18n and A.i18n.language) or "en"
        local v = by_lang[lang] or by_lang[(lang:match("^([^_]+)"))]
        if type(v) == "string" and v ~= "" then return v end
    end
    return type(base) == "string" and base or nil
end
K.localized = localized

-- Every look key Reading Log knows, with the values it accepts (the
-- built-in styles' looks, and "default").
local function knownLooks()
    local keys = {}
    for _, list in ipairs({ A.CUTE or {}, A.CYBER or {}, A.ACADEMIA or {} }) do
        for _, kv in ipairs(list) do
            keys[kv[1]] = keys[kv[1]] or { default = true }
            keys[kv[1]][kv[2]] = true
        end
    end
    -- the other shapes that aren't a style's own
    if keys.ring_shape then keys.ring_shape.dial = true; keys.ring_shape.rings = true end
    return keys
end

local function accentFrom(id, n, spec, label)
    if type(spec) == "string" then return A.ACCENTS[spec] and spec or nil end
    if type(spec) == "table" and isColour(spec.deep) and isColour(spec.bright) then
        local key = "pack_" .. id .. "_" .. n
        A.ACCENTS[key] = { label = (type(spec.label) == "string" and spec.label) or label,
            deep = clampColour(spec.deep), bright = clampColour(spec.bright) }
        A.THEME_ACCENTS[key] = true
        local seen = false
        for _, k in ipairs(A.ACCENT_ORDER) do if k == key then seen = true end end
        if not seen then A.ACCENT_ORDER[#A.ACCENT_ORDER + 1] = key end
        return key
    end
end

-- Check a style.lua and turn it into a pack. Returns pack or nil, reason.
function K.validate(id, spec, folder)
    if type(spec) ~= "table" then return nil, "not a table" end
    if spec.id ~= id then return nil, "id is not the folder's name" end
    if not tostring(id):match("^[a-z0-9_]+$") then return nil, "id must be a-z, 0-9 and _" end
    if (tonumber(spec.api) or 0) > K.API then return nil, "needs a newer Reading Log" end
    local name = localized(spec.name, spec.names) or id
    local pack = { id = id, version = tostring(spec.version or "1"), name = name,
                   description = localized(spec.description, spec.descriptions) or "",
                   author = type(spec.author) == "string" and spec.author or nil, folder = folder }
    -- looks: a built-in style's, then the pack's own
    local looks, known = {}, knownLooks()
    local base = ({ cute = A.CUTE, cyber = A.CYBER, academia = A.ACADEMIA })[spec.base]
    for _, kv in ipairs(base or {}) do looks[kv[1]] = kv[2] end
    if type(spec.looks) == "table" then
        for k, v in pairs(spec.looks) do
            if known[k] and type(v) == "string" and known[k][v] then
                looks[k] = (v ~= "default") and v or nil
            end
        end
    end
    pack.looks = {}
    for k, v in pairs(looks) do pack.looks[#pack.looks + 1] = { k, v } end
    table.sort(pack.looks, function(a, b) return a[1] < b[1] end)
    -- theme
    local th = spec.theme
    if type(th) == "table" then
        local need = { "surface", "fg", "page", "page_fg" }
        for _, k in ipairs(need) do
            if not isColour(th[k]) then return nil, "theme." .. k .. " must be {r,g,b}" end
        end
        local theme = {
            label = name, surface = clampColour(th.surface), fg = clampColour(th.fg),
            tint = clampColour(isColour(th.tint) and th.tint or th.surface),
            border = isColour(th.border) and clampColour(th.border) or clampColour(th.fg),
            page = clampColour(th.page), page_fg = clampColour(th.page_fg),
            thin = th.thin and true or nil, square = th.square and true or nil, serif = th.serif and true or nil,
            own = true, pack = id,
        }
        local a1 = accentFrom(id, 1, th.accent, name) or "red"
        local a2 = accentFrom(id, 2, th.accent2, name)
        if a1:match("^pack_") then A.ACCENTS[a1].pair = a2 or A.ACCENTS[a1].pair or "blue" end
        if a2 and a2:match("^pack_") then A.ACCENTS[a2].pair = A.ACCENTS[a2].pair or a1 end
        -- the theme's second accent (A.accentIds uses it while the first is the theme's)
        theme.accent, theme.accent2 = a1, a2
        pack.theme_id = "pack_" .. id
        A.THEMES[pack.theme_id] = theme
    end
    -- drawing
    if type(spec.draw) == "string" and spec.draw:match("^[%w_%-]+%.lua$") then
        local d, err = runFile(folder .. "/" .. spec.draw)
        if d then pack.draw = d else A.log("style", id, "drawing could not be loaded:", err) end
    end
    return pack
end

-- Read every installed pack.
function K.scan()
    installed, order = {}, {}
    local L = lfs()
    local dir = K.dir()
    if L.attributes(dir, "mode") ~= "directory" then return end
    for id in L.dir(dir) do
        local folder = dir .. "/" .. id
        if id:match("^[a-z0-9_]+$") and L.attributes(folder .. "/style.lua", "mode") == "file" then
            local spec, err = runFile(folder .. "/style.lua")
            local pack
            if spec then pack, err = K.validate(id, spec, folder) end
            if pack then
                installed[id] = pack
                order[#order + 1] = id
            else
                A.log("style", id, "could not be loaded:", err)
            end
        end
    end
    table.sort(order, function(a, b) return installed[a].name:lower() < installed[b].name:lower() end)
end

function K.get(id) return installed[id] end

-- The three styles built into Reading Log. They can be taken off the Style
-- list (and put back); their drawings stay in the plugin.
K.BUILTIN = { cute = true, cyber = true, academia = true }
K.BUILTIN_ORDER = { "cute", "cyber", "academia" }
local function builtinName(id)
    return ({ cute = T("Cute"), cyber = T("Cyber"), academia = T("Dark Academia") })[id] or id
end
K.builtinName = builtinName
function K.hidden(id)
    local h = A.get("styles_hidden", nil)
    return type(h) == "table" and h[id] == true or false
end
function K.setHidden(id, on)
    if on and A.styleNow and A.styleNow() == id then A.setStyle("default") end
    local h = A.get("styles_hidden", nil)
    local copy = {}
    if type(h) == "table" then for k, v in pairs(h) do copy[k] = v end end
    copy[id] = on and true or nil
    A.set("styles_hidden", next(copy) and copy or nil)
end
function K.ids() return order end

-- The pack whose style is on, if any.
function K.active()
    local id = A.get("style_pack", nil)
    return id and installed[id] or nil
end

-- One of the active pack's drawings, or nil.
function K.drawing(name)
    local p = K.active()
    if not p or not p.draw or failed[p.id] then return nil end
    local fn = p.draw[name]
    if type(fn) ~= "function" then return nil end
    return function(...)
        local ok, r = pcall(fn, ...)
        if not ok then
            failed[p.id] = true
            A.log("style", p.id, name, "drawing failed, using the usual one:", r)
            return false
        end
        return r ~= false
    end
end

local function same(a, b)
    return type(a) == "table" and type(b) == "table" and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

-- The Dashboard's tab bar, when the style draws one: true when it did (the
-- tab names and the tap areas are put on it here). x, y, w, h: the whole
-- row; page = { bg, fg, dark, accent, accent2 }; size: the names' size.
function A.packTabs(c, x, y, w, h, tabs, page_i, size, page)
    local draw = K.drawing("tabBar")
    if not draw then return false end
    local n = #tabs
    if n < 1 then return false end
    local floor, max = math.floor, math.max
    local tone = { bg = page.bg, fg = page.fg, dark = page.dark and true or false,
        muted = A.mix(page.fg, page.bg, 0.4), track = A.mix(page.fg, page.bg, 0.8),
        accent = page.accent, accent2 = page.accent2 or page.accent }
    -- the names, a size that fits every cell
    -- over a wallpaper: a plate behind the whole row, so the names stay readable
    if page.plate then c:rrect(floor(x), floor(y), floor(w), floor(h), floor(h * 0.3), page.bg, A.BEHIND) end
    local cw = w / n
    local room = cw - floor(h * 0.4)
    for _ = 1, 6 do
        local widest = 0
        for _, tab in ipairs(tabs) do widest = max(widest, c:text(tab.label, size, { bold = true }).w) end
        if widest <= room or size <= 12 then break end
        size = max(12, floor(size * room / widest))
    end
    local cells = {}
    for i, tab in ipairs(tabs) do
        local t = c:text(tab.label, size, { bold = true })
        cells[i] = { x = floor(x + (i - 1) * cw), w = floor(cw), i = i,
            active = tab.kind == "page" and tab.page == page_i or false,
            label_w = t.w, label_h = t.h }
    end
    if not draw(c, x, y, w, h, cells, tone) then return false end
    for i, tab in ipairs(tabs) do
        local cell = cells[i]
        local col = cell.color or (cell.active and tone.fg or tone.muted)
        local t = c:text(tab.label, size, { bold = cell.active, max_w = cell.w - 6, color = col })
        local cx = cell.x + cell.w / 2 + (cell.dx or 0)
        c:put(t, cx, y + h / 2 + (cell.dy or 0), "c", "mid")
        c:region("tab:" .. i, cell.x, y, cell.w, h)
    end
    return true
end

-- ringOf's hook: true when the pack drew the ring.
function A.packRing(c, cx, cy, R, t, frac, track, fill)
    local draw = K.drawing("ring")
    if not draw then return false end
    local tone = c.tone or A.tone("ink")
    local which = same(fill, tone.accent) and 1 or (same(fill, tone.accent2) and 2 or 0)
    return draw(c, cx, cy, R, t, frac, track, fill, tone, which)
end

-- The Monthly challenge's centrepiece: true when the pack drew it.
function A.packChallenge(c, cx, cy, R, frac, tone, fill)
    local draw = K.drawing("challenge")
    if not draw then return false end
    return draw(c, cx, cy, R, frac, tone, fill)
end

-- A progress bar's hook: true when the pack drew it.
function A.packBar(c, x, y, w, h, frac, tone, fill)
    local draw = K.drawing("bar")
    if not draw then return false end
    return draw(c, x, y, w, h, frac, tone, fill)
end

-- Any other drawing: whether the active pack has it, and call it (true when
-- it drew; false to draw the usual one).
function A.packHas(name) return K.drawing(name) ~= nil end
function A.packCall(name, ...)
    local draw = K.drawing(name)
    if not draw then return false end
    return draw(...)
end

-- ─── download ────────────────────────────────────────────────────────────────

local function get(url, sink)
    local http = require("socket.http")
    local socket = require("socket")
    local ok_su, socketutil = pcall(require, "socketutil")
    if ok_su then socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT) end
    local code, headers, status = socket.skip(1, http.request{
        url = url, method = "GET", sink = sink, redirect = true,
        headers = { ["User-Agent"] = "KOReader-ReadingLog-Styles" },
    })
    if ok_su then socketutil:reset_timeout() end
    if ok_su and (code == socketutil.TIMEOUT_CODE or code == socketutil.SSL_HANDSHAKE_CODE
            or code == socketutil.SINK_TIMEOUT_CODE) then
        return nil, "timed out"
    end
    if headers == nil then return nil, "no connection (" .. tostring(code or status) .. ")" end
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return true
end
K._get = get

-- The list of styles on GitHub: { styles = { {id, version, name, ...} } } or { error }.
function K.fetchIndex()
    local ltn12 = require("ltn12")
    local chunks = {}
    local ok, err = get(K.INDEX_URL, ltn12.sink.table(chunks))
    if not ok then return { error = err } end
    local ok_j, json = pcall(require, "json")
    if not ok_j then return { error = "no json" } end
    local ok_d, data = pcall(json.decode, table.concat(chunks))
    if not ok_d or type(data) ~= "table" or type(data.styles) ~= "table" then return { error = "could not read the list" } end
    local out = {}
    for _, s in ipairs(data.styles) do
        if type(s) == "table" and s.builtin and K.BUILTIN[s.id] then
            -- one of the three built in: listed, nothing to download
            out[#out + 1] = { id = s.id, builtin = true, version = tostring(s.version or ""),
                name = localized(s.name, s.names) or builtinName(s.id), description = localized(s.description, s.descriptions) or "",
                author = type(s.author) == "string" and s.author or nil, api = 1 }
        elseif type(s) == "table" and type(s.id) == "string" and s.id:match("^[a-z0-9_]+$") and type(s.files) == "table" then
            local files = {}
            for _, f in ipairs(s.files) do
                if type(f) == "string" and f:match("^[%w_%-]+%.[%w]+$") then files[#files + 1] = f end
            end
            local has_style = false
            for _, f in ipairs(files) do if f == "style.lua" then has_style = true end end
            if has_style then
                out[#out + 1] = { id = s.id, version = tostring(s.version or "1"), files = files,
                    name = localized(s.name, s.names) or s.id, description = localized(s.description, s.descriptions) or "",
                    author = type(s.author) == "string" and s.author or nil, api = tonumber(s.api) or 1 }
            end
        end
    end
    return { styles = out }
end

local function removeDir(path)
    local L = lfs()
    if L.attributes(path, "mode") ~= "directory" then return true end
    for f in L.dir(path) do
        if f ~= "." and f ~= ".." then
            local p = path .. "/" .. f
            if L.attributes(p, "mode") == "directory" then removeDir(p) else os.remove(p) end
        end
    end
    return os.remove(path) or L.rmdir(path)
end
K._removeDir = removeDir

-- Download a style's files into a new folder, check it, then put it in
-- place of the old one. Returns true, or nil and a reason.
function K.download(entry)
    local dir = K.dir()
    if not ensureDir(dir) then return nil, "can't make " .. dir end
    local tmp = dir .. "/." .. entry.id .. ".new"
    removeDir(tmp)
    lfs().mkdir(tmp)
    local ltn12 = require("ltn12")
    for _, f in ipairs(entry.files) do
        local fh = io.open(tmp .. "/" .. f, "wb")
        if not fh then removeDir(tmp); return nil, "can't write " .. f end
        local ok, err = get(K.FILES_URL .. entry.id .. "/" .. f, ltn12.sink.file(fh))
        if not ok then removeDir(tmp); return nil, f .. ": " .. tostring(err) end
    end
    return true, tmp
end

-- Put a downloaded folder in place (main process: it checks the style first).
function K.place(entry, tmp)
    local spec, err = runFile(tmp .. "/style.lua")
    if not spec then removeDir(tmp); return nil, err end
    if spec.id ~= entry.id then removeDir(tmp); return nil, "the style's id doesn't match" end
    if (tonumber(spec.api) or 0) > K.API then removeDir(tmp); return nil, T("This style needs a newer Reading Log.") end
    local final = K.dir() .. "/" .. entry.id
    removeDir(final)
    local ok, rerr = os.rename(tmp, final)
    if not ok then removeDir(tmp); return nil, tostring(rerr) end
    K.scan()
    if not installed[entry.id] then return nil, "it could not be loaded (see crash.log)" end
    return true
end

function K.remove(id)
    if K.active() and K.active().id == id then A.setStyle("default") end
    removeDir(K.dir() .. "/" .. id)
    K.scan()
end

-- ─── Get more styles... ──────────────────────────────────────────────────────

local function info(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

local function inBackground(text, fn, done)
    local UIManager = require("ui/uimanager")
    local ok_t, Trapper = pcall(require, "ui/trapper")
    if not (ok_t and Trapper and Trapper.wrap) then return done(fn()) end
    Trapper:wrap(function()
        local completed, r = Trapper:dismissableRunInSubprocess(fn, text)
        if completed then done(r) else info(T("Cancelled."), 3) end
    end)
end

local function newer(a, b)
    local function parts(v) local t = {} for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end return t end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end
K.newer = newer

local function showStyle(ctx, entry, back)
    local S = A.S
    local have = installed[entry.id]
    S.open(ctx, entry.name, function(api)
        local rows = {}
        if entry.description ~= "" then rows[#rows + 1] = S.header(entry.description) end
        rows[#rows + 1] = S.header(A.tr("Version %1", entry.version) .. (entry.author and ("  \xC2\xB7  " .. entry.author) or ""))
        local label = (not have and T("Download"))
            or (newer(entry.version, have.version) and A.tr("Update to %1", entry.version))
            or T("Download again")
        rows[#rows + 1] = { { text = label, callback = function()
            api.close()
            inBackground(A.tr("Downloading %1\xE2\x80\xA6", entry.name), function()
                local ok, r = K.download(entry)
                return { ok = ok, tmp = ok and r or nil, error = (not ok) and r or nil }
            end, function(r)
                local ok, err
                if r and r.ok then ok, err = K.place(entry, r.tmp) else err = r and r.error or "?" end
                if not ok then
                    info(A.tr("The style couldn't be installed: %1", tostring(err)), 6)
                    return
                end
                local ConfirmBox = require("ui/widget/confirmbox")
                require("ui/uimanager"):show(ConfirmBox:new{
                    text = A.tr("%1 is installed. Use it now?", entry.name),
                    ok_text = T("Use it"), cancel_text = T("Later"),
                    ok_callback = function() A.setStyle("pack:" .. entry.id); S.reloadAll(ctx) end,
                })
            end)
        end } }
        if have then
            rows[#rows + 1] = { { text = T("Remove this style"), callback = function()
                api.close()
                K.remove(entry.id)
                S.reloadAll(ctx)
                if back then back() end
            end } }
        end
        if back then rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } } end
        return rows
    end)
end

local function showBuiltin(ctx, entry, back)
    local S = A.S
    S.open(ctx, entry.name, function(api)
        local rows = {}
        if entry.description ~= "" then rows[#rows + 1] = S.header(entry.description) end
        rows[#rows + 1] = S.header(T("Built into Reading Log: nothing to download."))
        local hidden = K.hidden(entry.id)
        rows[#rows + 1] = { { text = hidden and T("Put back in the Style list") or T("Remove from the Style list"), callback = function()
            api.close()
            K.setHidden(entry.id, not hidden)
            S.reloadAll(ctx)
            if back then back() end
        end } }
        if back then rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } } end
        return rows
    end)
end

local function showList(ctx, list)
    local S = A.S
    local function again() showList(ctx, list) end
    S.open(ctx, T("Get more styles"), function(api)
        local rows = {}
        if #list == 0 then rows[#rows + 1] = S.header(T("No styles to download yet.")) end
        for _, e in ipairs(list) do
            if e.builtin then
                local state = "  \xC2\xB7  " .. T("built in") .. (K.hidden(e.id) and ("  \xC2\xB7  " .. T("hidden")) or "")
                rows[#rows + 1] = { { text = e.name .. state, callback = function() api.close(); showBuiltin(ctx, e, again) end } }
            else
                local have = installed[e.id]
                local state = (not have and "") or (newer(e.version, have.version) and ("  \xC2\xB7  " .. T("update")))
                    or ("  \xC2\xB7  " .. T("installed"))
                local too_new = (e.api or 1) > K.API
                rows[#rows + 1] = { { text = e.name .. state .. (too_new and ("  \xC2\xB7  " .. T("needs a newer Reading Log")) or ""),
                    enabled = not too_new,
                    callback = function() api.close(); showStyle(ctx, e, again) end } }
            end
        end
        -- installed styles that aren't on the list (made by hand)
        for _, id in ipairs(order) do
            local listed = false
            for _, e in ipairs(list) do if e.id == id then listed = true end end
            if not listed then
                local p = installed[id]
                rows[#rows + 1] = { { text = p.name .. "  \xC2\xB7  " .. T("installed") .. "  \xC2\xB7  " .. T("Remove"), callback = function()
                    api.close(); K.remove(id); S.reloadAll(ctx); again()
                end } }
            end
        end
        rows[#rows + 1] = S.header(T("Styles come from the reading-log-styles repository on GitHub."))
        return rows
    end)
end

-- "Your styles...": every style on this reader, no network needed. The
-- built-in ones can be taken off the Style list or put back; downloaded
-- ones can be deleted from the device.
function K.manage(ctx, back)
    local S = A.S
    local function again() K.manage(ctx, back) end
    S.open(ctx, T("Your styles"), function(api)
        local rows = { S.header(T("Built in")) }
        for _, id in ipairs(K.BUILTIN_ORDER) do
            local hidden = K.hidden(id)
            rows[#rows + 1] = { { text = builtinName(id) .. "  \xC2\xB7  " .. (hidden and T("Put back in the Style list") or T("Remove from the Style list")),
                callback = function()
                    api.close()
                    K.setHidden(id, not hidden)
                    S.reloadAll(ctx)
                    again()
                end } }
        end
        rows[#rows + 1] = S.header(T("Downloaded"))
        if #order == 0 then rows[#rows + 1] = S.header(T("No downloaded styles yet.")) end
        for _, id in ipairs(order) do
            local p = installed[id]
            rows[#rows + 1] = { { text = p.name .. "  \xC2\xB7  " .. A.tr("Version %1", p.version) .. "  \xC2\xB7  " .. T("Delete"),
                callback = function()
                    api.close()
                    local ConfirmBox = require("ui/widget/confirmbox")
                    require("ui/uimanager"):show(ConfirmBox:new{
                        text = A.tr("Delete %1 from this device? You can download it again later.", p.name),
                        ok_text = T("Delete"),
                        ok_callback = function() K.remove(id); S.reloadAll(ctx); again() end,
                        cancel_callback = function() again() end,
                    })
                end } }
        end
        rows[#rows + 1] = { { text = T("Get more styles") .. "\xE2\x80\xA6", callback = function() api.close(); K.browse(ctx) end } }
        if back then rows[#rows + 1] = { { text = T("Back"), callback = function() api.close(); back() end } } end
        return rows
    end)
end

function K.browse(ctx)
    local function go()
        inBackground(T("Looking for styles\xE2\x80\xA6"), K.fetchIndex, function(r)
            if not r or r.error then
                info(A.tr("Couldn't get the list of styles: %1", r and r.error or "?"), 5)
                return
            end
            showList(ctx, r.styles)
        end)
    end
    local ok_n, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_n and NetworkMgr and NetworkMgr.runWhenOnline then NetworkMgr:runWhenOnline(go) else go() end
end

pcall(K.scan)
return K
