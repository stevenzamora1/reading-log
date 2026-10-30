--[[
Reading Log: shared code behind every Reading Log card, for both of the
home screens it runs on, Simple UI and Bookshelf.

The same cards are drawn for both. What differs is the app around them (where
the card colour, fonts, book records, goals and covers come from, how a card
redraws, how a book opens), and that goes through a host adapter:
  host.lua            Simple UI (and plain KOReader underneath)
  host_bookshelf.lua  Bookshelf, built on host.lua
Settings are one file for both, settings/readinglog.lua (store.lua).

Whoever loads this file says which app it is for:
  loadfile(".../readinglog/init.lua")("bookshelf")   the bookshelf_modules/ cards
  dofile(".../readinglog/init.lua")                  Simple UI (main.lua)
Each app gets its own copy of the kit in memory (Bookshelf's in
package.loaded.almanac_kit, Simple UI's in package.loaded.readinglog_kit), so
both can be used at once.

Ring designs and the idea of a tabbed reading dashboard: u/fishnoogz on
Reddit. Built for KOReader, Simple UI and Bookshelf.

Parts, each loaded once and attached to the same table:
  init.lua      this file: store, theme, drawing, text, the Canvas widget
  store.lua     the settings file, shared by both apps
  host*.lua     the app adapter (see above)
  data.lua      reading stats, book lists, covers
  panels.lua    one builder per card (banner, continue reading, rings, ...)
  settings.lua  each card's options, and the dialogs (page editor, picks)
  modules.lua   Simple UI: turns each panel into a Simple UI module; the dashboard
  menus.lua     Simple UI: the options as settings menu items
  bookshelf.lua Bookshelf: turns each panel into a micro-module spec; the dashboard

Why modules paint their own card: each card has its own colour, so it fills
its box with a rounded panel and draws on that.
]]

local HOST_KIND = ...
if HOST_KIND ~= "bookshelf" then HOST_KIND = "simpleui" end

local A = { VERSION = "1.4.0", NAME = "Reading Log" }
A.HOST_KIND = HOST_KIND
A.HOST = HOST_KIND == "bookshelf" and "Bookshelf" or "Simple UI"

A.dir = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."

A.i18n = dofile(A.dir .. "/i18n.lua")
local T = A.i18n.gettext
A._ = T
A.tr = A.i18n.format

local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt

-- ─── small utilities ─────────────────────────────────────────────────────────

function A.log(...)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.warn("[readinglog]", ...) end
end

-- A line in KOReader's own log (crash.log on a Kobo), for the few events
-- worth being able to look up afterwards.
function A.note(...)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.info("[readinglog]", ...) end
end

-- Counters shown in Look and colours > Diagnostics. Since this session started.
A.counts = { views = 0, flashes = 0, reinks = 0, narrowed = 0, clipped = 0, cleans = 0 }
function A.count(name) A.counts[name] = (A.counts[name] or 0) + 1 end

function A.round(n) return floor(n + 0.5) end
function A.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

-- Text from book metadata or typed by the reader can carry bytes the text
-- shaper chokes on (a C-level crash no pcall catches); see host.lua.
function A.safe(s)
    if type(s) ~= "string" then s = s == nil and "" or tostring(s) end
    return A.host.safeText(s)
end

function A.upper(s)
    s = A.safe(s)
    local ok, U = pcall(require, "ffi/utf8proc")
    if ok and U and U.uppercase_dumb then
        local ok2, r = pcall(U.uppercase_dumb, s)
        if ok2 and type(r) == "string" then return r end
    end
    return s:upper()
end

function A.screen() return require("device").screen end

-- ─── settings store ──────────────────────────────────────────────────────────
-- Reading Log keeps its settings in a file of its own,
-- settings/readinglog.lua, one for both apps (store.lua). On the first run,
-- settings saved by the older Bookshelf micro-modules are copied in.

function A.get(key, default)
    local ok, v = pcall(A.host.get, key)
    if ok and v ~= nil then return v end
    return default
end

function A.set(key, value)
    pcall(A.host.set, key, value)
    A.epoch = (A.epoch or 0) + 1
end

A.epoch = 0

-- ─── theme ───────────────────────────────────────────────────────────────────
-- Colour e-ink (Kaleido) shows about a third of the saturation of a phone
-- screen, sixteen levels per channel, and it is dark: a deep tinted fill
-- comes out as a muddy grey, and anything flat that is not one of those
-- sixteen levels is dithered into grain. Big dark areas are also where
-- ghosting shows most. So a theme is one surface colour (white, cream or
-- true black), colour is kept for accents, and every flat colour here is a
-- multiple of 17 per channel (an exact panel level, so no grain).
--
-- A theme: surface (the card), tint (a second, slightly different card),
-- fg (ink), border, page / page_fg (what the Dashboard paints behind its
-- cards), accent (the accent it starts with).
-- The two accents are the reader's: any two of A.ACCENTS. Each has a `deep`
-- form for light surfaces and a `bright` one for dark, and names the partner
-- that is used when no second accent has been chosen.

A.ACCENTS = {
    red     = { label = T("Red"),     deep = { 204, 34, 51 },  bright = { 255, 102, 102 }, pair = "blue" },
    orange  = { label = T("Orange"),  deep = { 221, 102, 0 },  bright = { 255, 170, 51 },  pair = "teal" },
    gold    = { label = T("Gold"),    deep = { 170, 119, 0 },  bright = { 255, 204, 51 },  pair = "red" },
    lime    = { label = T("Lime"),    deep = { 102, 153, 0 },  bright = { 187, 238, 68 },  pair = "purple" },
    green   = { label = T("Green"),   deep = { 17, 136, 68 },  bright = { 102, 221, 119 }, pair = "orange" },
    teal    = { label = T("Teal"),    deep = { 0, 136, 136 },  bright = { 85, 221, 221 },  pair = "orange" },
    sky     = { label = T("Sky"),     deep = { 0, 136, 204 },  bright = { 102, 204, 255 }, pair = "pink" },
    blue    = { label = T("Blue"),    deep = { 34, 102, 204 }, bright = { 102, 170, 255 }, pair = "red" },
    purple  = { label = T("Purple"),  deep = { 119, 68, 187 }, bright = { 187, 153, 255 }, pair = "gold" },
    magenta = { label = T("Magenta"), deep = { 187, 34, 153 }, bright = { 255, 119, 221 }, pair = "teal" },
    pink    = { label = T("Pink"),    deep = { 204, 51, 119 }, bright = { 255, 136, 187 }, pair = "sky" },
    brown   = { label = T("Brown"),   deep = { 136, 85, 34 },  bright = { 221, 170, 119 }, pair = "teal" },
    -- the Cyber theme's two: as bright as the panel goes
    neon    = { label = T("Neon yellow"), deep = { 170, 153, 0 }, bright = { 255, 238, 0 }, pair = "cyan" },
    cyan    = { label = T("Neon cyan"),   deep = { 0, 136, 170 }, bright = { 0, 238, 255 }, pair = "neon" },
    -- the Dark Academia theme's two
    oxblood = { label = T("Oxblood"), deep = { 122, 31, 31 }, bright = { 204, 102, 85 }, pair = "brass" },
    brass   = { label = T("Brass"),   deep = { 136, 102, 34 }, bright = { 212, 174, 92 }, pair = "oxblood" },
}
A.ACCENT_ORDER = { "red", "orange", "gold", "lime", "green", "teal", "sky", "blue", "purple", "magenta", "pink", "brown",
    "neon", "cyan", "oxblood", "brass" }
-- the accents that come with a theme of their own (left out of rounds of
-- colours, such as Reading trends' six)
A.THEME_ACCENTS = { neon = true, cyan = true, oxblood = true, brass = true }

local WHITE, BLACK = { 255, 255, 255 }, { 0, 0, 0 }

A.THEMES = {
    white = { label = T("White"), accent = "red",
              surface = WHITE, tint = { 238, 238, 238 }, fg = BLACK, border = BLACK,
              page = WHITE, page_fg = BLACK },
    dark  = { label = T("Dark"), accent = "gold",
              surface = BLACK, tint = { 34, 34, 34 }, fg = WHITE, border = { 119, 119, 119 }, thin = true,
              page = BLACK, page_fg = WHITE },
    paper = { label = T("Paper"), accent = "orange",
              surface = { 255, 238, 204 }, tint = { 238, 221, 170 }, fg = { 34, 17, 0 }, border = { 68, 51, 34 },
              page = { 255, 238, 204 }, page_fg = { 34, 17, 0 } },
    -- black and neon, cards with cut corners (drawn by cyber.lua). `own`: it
    -- needs its own page, so cards on their own are framed in it too.
    cyber = { label = T("Cyber"), accent = "neon",
              surface = BLACK, tint = { 17, 17, 34 }, fg = { 238, 238, 238 }, border = { 51, 68, 68 }, thin = true,
              page = BLACK, page_fg = { 238, 238, 238 }, cut = true, own = true },
    -- parchment cards on a dark study's page, in a serif, square corners with
    -- a thin brass rule inside the frame (drawn by academia.lua's looks)
    academia = { label = T("Dark Academia"), accent = "oxblood",
              surface = { 233, 223, 201 }, tint = { 242, 233, 212 }, fg = { 43, 33, 24 }, border = { 170, 150, 110 }, thin = true,
              page = { 28, 22, 18 }, page_fg = { 233, 223, 201 }, square = true, ruled = true, serif = true, own = true },
}
A.THEME_ORDER = { "white", "dark", "paper", "cyber", "academia" }
A.DEFAULT_THEME = "white"
-- names from earlier versions
local THEME_ALIAS = { noir = "dark" }

-- The four card styles of every theme. Earlier versions stored "plum" and
-- "wine"; those now mean the two plain styles.
A.TONES = { "ink", "paper", "tint", "tint2" }
local TONE_LABELS = { ink = T("Plain"), paper = T("Plain, accents swapped"), tint = T("Tinted"), tint2 = T("Tinted, accents swapped") }
local TONE_ALIAS = { plum = "ink", wine = "paper" }

function A.toneKey(name)
    name = TONE_ALIAS[name] or name
    if not TONE_LABELS[name] then name = "ink" end
    return name
end

function A.toneLabel(key) return TONE_LABELS[A.toneKey(key)] end

function A.themeId()
    local id = A.get("theme", A.DEFAULT_THEME)
    id = THEME_ALIAS[id] or id
    if not A.THEMES[id] then id = A.DEFAULT_THEME end
    return id
end

-- The two accent families in use: the reader's picks, else the theme's own
-- first accent and that accent's partner.
function A.accentIds()
    local th = A.THEMES[A.themeId()]
    local a = A.get("accent", nil)
    if not A.ACCENTS[a] then a = th.accent end
    local b = A.get("accent2", nil)
    if not A.ACCENTS[b] then b = A.ACCENTS[a].pair end
    return a, b
end

-- The current theme, with the handful of colours the Dashboard's own
-- furniture uses: gold (accent on a dark page), wine (accent on a light
-- page), ink and paper.
function A.theme()
    local th = A.THEMES[A.themeId()]
    local a1, a2 = A.accentIds()
    local fam, fam2 = A.ACCENTS[a1], A.ACCENTS[a2]
    return { label = th.label, page = th.page, page_fg = th.page_fg,
             gold = fam.bright, wine = fam.deep, gold2 = fam2.bright, wine2 = fam2.deep, ink = BLACK, paper = WHITE }
end

-- A Blitbuffer method, or nil when this KOReader has none by that name
-- (asking a picture for a member it lacks raises, so ask safely).
local function bbMethod(bb, name)
    local ok, fn = pcall(function() return bb[name] end)
    return ok and fn or nil
end
A.bbMethod = bbMethod

function A.mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

function A.luma(c) return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3] end

function A.night()
    local Screen = A.screen()
    return Screen.night_mode and true or false
end

function A.inverted(c) return { 255 - c[1], 255 - c[2], 255 - c[3] } end

-- How the page will LOOK: dark when the page colour is dark, and dark when
-- night mode turns a light page over.
function A.pageLooksDark()
    local bg = A.pageColors()
    return (A.luma(bg) < 128) ~= A.night()
end

-- Colour to paint so that it LOOKS like `rgb` on a canvas that is not
-- pre-inverted (the dashboard's own tab bar and headings).
function A.shown(rgb)
    if A.night() then return A.inverted(rgb) end
    return rgb
end

-- One card style: colours worked out from a surface, its ink and the two
-- accents. `fixed` = looks the same day and night (see Canvas).
local function buildTone(name, bg, fg, border, thin, cut, th)
    local dark = A.luma(bg) < 128
    local id1, id2 = A.accentIds()
    local a1 = dark and A.ACCENTS[id1].bright or A.ACCENTS[id1].deep
    local a2 = dark and A.ACCENTS[id2].bright or A.ACCENTS[id2].deep
    if name == "paper" or name == "tint2" then a1, a2 = a2, a1 end
    return {
        name = name, dark = dark, fixed = true,
        bg = bg, fg = fg, muted = A.mix(bg, fg, dark and 0.8 or 0.72),
        -- chart and calendar labels (months, days, axis figures): darker
        -- than muted, so small bold letters stay crisp on e-ink
        label = A.mix(bg, fg, dark and 0.88 or 0.82),
        accent = a1, accent2 = a2,
        track = A.mix(bg, fg, dark and 0.24 or 0.15),
        border = border, border_thin = thin,
        btn = a1, btn_fg = (A.luma(a1) > 140) and BLACK or WHITE,
        soft = A.mix(bg, fg, 0.12),
        -- the third series (streaks): the ink, or red in the Cyber theme
        series = { a1, a2, cut and (dark and { 255, 68, 102 } or { 204, 34, 68 }) or fg },
        -- for a missed day or "behind": red, whatever the accents
        alert = dark and { 255, 68, 102 } or { 204, 34, 68 },
        cut = cut or nil,
        -- square corners (Cyber, Dark Academia); a brass rule inside the frame
        square = (cut or (th and th.square)) and true or nil,
        ruled = th and th.ruled or nil,
    }
end

-- A card style in the theme's own colours: what the Dashboard's cards use.
function A.tone(name)
    name = A.toneKey(name)
    local th = A.THEMES[A.themeId()]
    local tinted = (name == "tint" or name == "tint2")
    return buildTone(name, tinted and th.tint or th.surface, th.fg, th.border, th.thin, th.cut, th)
end

-- A card style for a card on its own on the home screen: it takes the app's
-- own card colour and ink (Simple UI's background, or Bookshelf's card, with
-- the colours the reader gave that card) and draws no frame of its own, so
-- the card sits on the page like the app's own modules. Only the accents come
-- from the theme. Tinted styles keep a soft, frameless panel. Colours are
-- kept as they should LOOK; the canvas pre-inverts them at night like every
-- other card.
function A.nativeTone(name)
    name = A.toneKey(name)
    local bg, fg = A.pageColors()
    if A.night() then bg, fg = A.inverted(bg), A.inverted(fg) end
    local tinted = (name == "tint" or name == "tint2")
    if tinted then bg = A.mix(bg, fg, A.luma(bg) < 128 and 0.12 or 0.07) end
    local t = buildTone(name, bg, fg, nil, nil)
    t.native, t.panel = true, tinted
    return t
end

-- Whether cards on their own take the app's look (the default) or the
-- theme's framed cards.
function A.standaloneNative()
    if A.THEMES[A.themeId()].own then return false end
    return A.get("standalone", "native") ~= "framed"
end

-- The Cyber drawing kit (cyber.lua) when the theme has cut corners (the
-- Cyber theme), else nil: the page's own furniture follows it.
function A.cutTheme()
    return A.THEMES[A.themeId()].cut and A.cyber() or nil
end

-- The Dark Academia drawing kit (academia.lua) when the theme is Dark
-- Academia, else nil: the tabs follow it.
function A.academiaTheme()
    return A.THEMES[A.themeId()].ruled and A.academia() or nil
end

-- Whether the theme sets its cards in a serif (Dark Academia).
function A.serifTheme()
    return A.THEMES[A.themeId()].serif and true or false
end

-- The colour of the page the panel sits on (Simple UI's background, or
-- Bookshelf's card), the ink the app draws on it, and its muted ink. Read at
-- render time.
function A.pageColors()
    local ok, bg, fg, muted = pcall(A.host.pageColors)
    if ok and bg then return bg, fg, muted end
    return { 0xFF, 0xFF, 0xFF }, { 0, 0, 0 }, { 0x77, 0x77, 0x77 }
end

-- What the Dashboard paints behind and between its cards, as colours to
-- PAINT (night mode already allowed for): bg, fg, whether it will look dark,
-- an accent for headings, and `look` = the page colour as it should look when
-- the theme sets one (nil when the page is the app's own background).
function A.dashPage()
    local th = A.theme()
    if th.page then
        local dark = A.luma(th.page) < 128
        return A.shown(th.page), A.shown(th.page_fg), dark, A.shown(dark and th.gold or th.wine), th.page
    end
    local bg, fg = A.pageColors()
    local dark = A.pageLooksDark()
    return bg, fg, dark, A.shown(dark and th.gold or A.mix(th.gold, { 0, 0, 0 }, 0.42)), nil
end

-- ─── colours → Blitbuffer ────────────────────────────────────────────────────
-- Colours live as {r,g,b}. They become Blitbuffer colours at the last moment:
-- real colour on a colour screen, Rec.601 grey otherwise.

local _colcache, _colmode, _colcount = {}, nil, 0

-- Blitbuffer, loaded once (drawing asks for it a great many times).
local _BB
local function BBmod()
    if not _BB then _BB = require("ffi/blitbuffer") end
    return _BB
end

-- Whether the screen shows colour. Asked of the screen at the start of each
-- paint (see Canvas:paintTo) and kept, instead of once per colour.
local _is_color, _is_color_known = false, false
function A.colorMode(refresh)
    if refresh or not _is_color_known then
        local Screen = A.screen()
        _is_color = (Screen.isColorEnabled and Screen:isColorEnabled()) and true or false
        _is_color_known = true
    end
    return _is_color
end

function A.color(rgb, inv)
    local is_color
    if _is_color_known then is_color = _is_color else is_color = A.colorMode() end
    -- Edge blending makes many one-off shades; start over now and then.
    if _colmode ~= is_color or _colcount > 8192 then _colcache, _colmode, _colcount = {}, is_color, 0 end
    local r = floor(rgb[1] + 0.5); if r < 0 then r = 0 elseif r > 255 then r = 255 end
    local g = floor(rgb[2] + 0.5); if g < 0 then g = 0 elseif g > 255 then g = 255 end
    local b = floor(rgb[3] + 0.5); if b < 0 then b = 0 elseif b > 255 then b = 255 end
    if inv then r, g, b = 255 - r, 255 - g, 255 - b end
    local key = r * 65536 + g * 256 + b
    local c = _colcache[key]
    if c then return c end
    local Blitbuffer = _BB or BBmod()
    if is_color and Blitbuffer.ColorRGB32 then
        c = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    else
        c = Blitbuffer.Color8(floor(0.299 * r + 0.587 * g + 0.114 * b + 0.5))
    end
    _colcache[key] = c
    _colcount = _colcount + 1
    return c
end

-- paintRect flattens a colour to grey; paintRectRGB32 keeps it. Same choice
-- KOReader's own FrameContainer makes.
local function fillRect(bb, x, y, w, h, c)
    if w <= 0 or h <= 0 then return end
    local Blitbuffer = _BB or BBmod()
    if bb.paintRectRGB32 and Blitbuffer.isColor8 and not Blitbuffer.isColor8(c) then
        bb:paintRectRGB32(x, y, w, h, c)
    else
        bb:paintRect(x, y, w, h, c)
    end
end
A.fillRect = fillRect

-- One pixel, only if it is inside the bitmap. Blitbuffer's own setPixel does
-- no bounds check (rect fills and blits do), so a shape that hangs over the
-- edge of what it is painted into would otherwise write into whatever memory
-- sits beside the bitmap. bw, bh = the bitmap's size, read once per shape.
local function plot(bb, bw, bh, x, y, c)
    if x >= 0 and y >= 0 and x < bw and y < bh then
        bb:setPixel(x, y, c)
    else
        A.counts.clipped = A.counts.clipped + 1
        if A._oob then A._oob(x, y, bw, bh) end
    end
end

-- ─── drawing primitives ──────────────────────────────────────────────────────
-- All take {r,g,b} colours plus `inv` (see Canvas: night-mode compensation).
-- Edges are anti-aliased by mixing with the colour known to be underneath
-- (`under`), never by reading pixels back, so they behave the same whichever
-- way the device implements night mode.

local G = {}
A.G = G

function G.rect(bb, x, y, w, h, rgb, inv)
    fillRect(bb, floor(x), floor(y), floor(w), floor(h), A.color(rgb, inv))
end

-- `under` for a shape whose edges should blend with whatever is really
-- behind it (a picture showing through), read from the bitmap: a card over a
-- wallpaper. Used for card outlines only; everything inside a card blends
-- with the card's own colour as before.
A.BEHIND = { behind = true }
local BEHIND = A.BEHIND

-- Blend colour rgb (to be painted, night mode applied) by coverage cov over
-- the pixel already at x, y.
local function plotOver(bb, bw, bh, x, y, rgb, cov)
    if x < 0 or y < 0 or x >= bw or y >= bh then return end
    local ok, r, g, b = pcall(function()
        local c = bb:getPixel(x, y):getColorRGB32()
        return c.r, c.g, c.b
    end)
    if not ok then return end
    bb:setPixel(x, y, A.color({ r + (rgb[1] - r) * cov, g + (rgb[2] - g) * cov, b + (rgb[3] - b) * cov }, false))
end

-- Filled rounded rectangle. `under` = colour behind it, for the corner edges
-- (or BEHIND).
function G.rrect(bb, x, y, w, h, r, rgb, under, inv)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    if w <= 0 or h <= 0 then return end
    r = floor(min(r or 0, w / 2, h / 2))
    local c = A.color(rgb, inv)
    if r < 1 then fillRect(bb, x, y, w, h, c) return end
    local bw, bh = bb:getWidth(), bb:getHeight()
    fillRect(bb, x, y + r, w, h - 2 * r, c)
    for i = 0, r - 1 do
        local dy = r - i - 0.5
        local inset = r - sqrt(max(0, r * r - dy * dy))
        local full = ceil(inset)
        local cov = full - inset
        local yt, yb = y + i, y + h - 1 - i
        local span = w - 2 * full
        if span > 0 then
            fillRect(bb, x + full, yt, span, 1, c)
            fillRect(bb, x + full, yb, span, 1, c)
        end
        if under == BEHIND and cov > 0.02 and full >= 1 then
            local paint = inv and A.inverted(rgb) or rgb
            plotOver(bb, bw, bh, x + full - 1, yt, paint, cov)
            plotOver(bb, bw, bh, x + w - full, yt, paint, cov)
            plotOver(bb, bw, bh, x + full - 1, yb, paint, cov)
            plotOver(bb, bw, bh, x + w - full, yb, paint, cov)
        elseif under and cov > 0.02 and full >= 1 then
            local e = A.color(A.mix(under, rgb, cov), inv)
            plot(bb, bw, bh, x + full - 1, yt, e)
            plot(bb, bw, bh, x + w - full, yt, e)
            plot(bb, bw, bh, x + full - 1, yb, e)
            plot(bb, bw, bh, x + w - full, yb, e)
        end
    end
end

-- Outlined rounded rectangle: border colour outside, fill inside.
function G.frame(bb, x, y, w, h, r, bw, border, fill, under, inv)
    G.rrect(bb, x, y, w, h, r, border, under, inv)
    G.rrect(bb, x + bw, y + bw, w - 2 * bw, h - 2 * bw, max(0, r - bw), fill, border, inv)
end

function G.disc(bb, cx, cy, r, rgb, under, inv)
    if not (r > 0 and r < 4096 and cx == cx and cy == cy) then return end
    local c = A.color(rgb, inv)
    local bw, bh = bb:getWidth(), bb:getHeight()
    local x0, x1 = floor(cx - r - 1), ceil(cx + r + 1)
    for py = floor(cy - r - 1), ceil(cy + r + 1) do
        local dy = py + 0.5 - cy
        for px = x0, x1 do
            local dx = px + 0.5 - cx
            local cov = r + 0.5 - sqrt(dx * dx + dy * dy)
            if cov >= 1 then
                plot(bb, bw, bh, px, py, c)
            elseif cov > 0 and under then
                plot(bb, bw, bh, px, py, A.color(A.mix(under, rgb, cov), inv))
            end
        end
    end
end

-- Progress ring: a full track with an arc of `frac` drawn clockwise from
-- 12 o'clock, round caps at both ends. R = outer radius, t = thickness.
-- A thick line through points { x1, y1, x2, y2, ... } (a curve is just many
-- short segments). Each pixel's coverage is its distance from the nearest
-- segment, kept in a scratch buffer as the largest over all segments, so
-- joints and overlaps come out smooth instead of doubling up at the edges.
-- Everything is clipped to the bitmap first.
function G.polyline(bb, pts, lw, rgb, under, inv)
    local n = floor(#pts / 2)
    if n < 2 or not (lw > 0 and lw < 200) then return end
    local bw, bh = bb:getWidth(), bb:getHeight()
    local r = lw / 2
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, 2 * n, 2 do
        local x, y = pts[i], pts[i + 1]
        if x ~= x or y ~= y then return end -- NaN: nothing sensible to draw
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
    end
    local x0, x1 = max(0, floor(minx - r - 1)), min(bw - 1, ceil(maxx + r + 1))
    local y0, y1 = max(0, floor(miny - r - 1)), min(bh - 1, ceil(maxy + r + 1))
    if x1 < x0 or y1 < y0 then return end
    local W, H = x1 - x0 + 1, y1 - y0 + 1
    if W * H > 8000000 then return end
    local ffi = require("ffi")
    local cov = ffi.new("uint8_t[?]", W * H)
    local touched, nt = {}, 0 -- every pixel given any coverage, to compose only those
    for i = 1, 2 * n - 2, 2 do
        local ax, ay, bx2, by2 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        local dx, dy = bx2 - ax, by2 - ay
        local len2 = dx * dx + dy * dy
        local sx0 = max(x0, floor(min(ax, bx2) - r - 1))
        local sx1 = min(x1, ceil(max(ax, bx2) + r + 1))
        local sy0 = max(y0, floor(min(ay, by2) - r - 1))
        local sy1 = min(y1, ceil(max(ay, by2) + r + 1))
        for py = sy0, sy1 do
            local cy = py + 0.5
            local row = (py - y0) * W - x0
            for px = sx0, sx1 do
                local cx = px + 0.5
                local t = 0
                if len2 > 0 then
                    t = ((cx - ax) * dx + (cy - ay) * dy) / len2
                    if t < 0 then t = 0 elseif t > 1 then t = 1 end
                end
                local ex, ey = ax + t * dx - cx, ay + t * dy - cy
                local c = r + 0.5 - sqrt(ex * ex + ey * ey)
                if c > 0 then
                    local v = (c >= 1) and 255 or floor(c * 255)
                    local idx = row + px
                    local old = cov[idx]
                    if v > old then
                        if old == 0 then nt = nt + 1; touched[nt] = idx end
                        cov[idx] = v
                    end
                end
            end
        end
    end
    local solid = A.color(rgb, inv)
    for i = 1, nt do
        local idx = touched[i]
        local v = cov[idx]
        local py = y0 + floor(idx / W)
        local px = x0 + idx % W
        if v == 255 then
            plot(bb, bw, bh, px, py, solid)
        elseif under then
            plot(bb, bw, bh, px, py, A.color(A.mix(under, rgb, v / 255), inv))
        elseif v >= 128 then
            plot(bb, bw, bh, px, py, solid)
        end
    end
end

function G.ring(bb, cx, cy, R, t, frac, track, fill, under, inv)
    if not (R > 0 and R < 4096 and t > 0 and cx == cx and cy == cy) then return end
    frac = tonumber(frac) or 0
    if frac ~= frac then frac = 0 end
    frac = A.clamp(frac, 0, 1)
    local pi2 = 2 * math.pi
    local theta = frac * pi2
    local rm, cap = R - t / 2, t / 2
    local ex, ey = cx + rm * math.sin(theta), cy - rm * math.cos(theta)
    local sx, sy = cx, cy - rm
    local c_track, c_fill = A.color(track, inv), A.color(fill, inv)
    local bw, bh = bb:getWidth(), bb:getHeight()
    local atan2 = math.atan2
    local full = frac >= 0.999
    for py = floor(cy - R - 1), ceil(cy + R + 1) do
        local dy = py + 0.5 - cy
        local ro = (R + 1) * (R + 1) - dy * dy
        if ro > 0 then
            local half = sqrt(ro)
            local ri = (R - t - 1)
            local hole = (ri > 0 and ri * ri - dy * dy > 0) and sqrt(ri * ri - dy * dy) or 0
            for px = floor(cx - half), ceil(cx + half) do
                local dx = px + 0.5 - cx
                if dx > hole or dx < -hole or hole == 0 then
                    local d = sqrt(dx * dx + dy * dy)
                    local cov = min(R + 0.5 - d, d - (R - t) + 0.5)
                    if cov > 0 then
                        if cov > 1 then cov = 1 end
                        -- how much of this pixel belongs to the filled arc
                        local f
                        if full then
                            f = 1
                        else
                            local a = atan2(dx, -dy)
                            if a < 0 then a = a + pi2 end
                            if a <= theta then
                                f = 1
                            else
                                local d1 = cap + 0.5 - sqrt((px + 0.5 - sx) ^ 2 + (py + 0.5 - sy) ^ 2)
                                local d2 = cap + 0.5 - sqrt((px + 0.5 - ex) ^ 2 + (py + 0.5 - ey) ^ 2)
                                f = max(0, min(1, max(d1, d2)))
                            end
                        end
                        if cov >= 1 and f >= 1 then
                            plot(bb, bw, bh, px, py, c_fill)
                        elseif cov >= 1 and f <= 0 then
                            plot(bb, bw, bh, px, py, c_track)
                        else
                            local base = A.mix(track, fill, f)
                            if under and cov < 1 then base = A.mix(under, base, cov) end
                            plot(bb, bw, bh, px, py, A.color(base, inv))
                        end
                    end
                end
            end
        end
    end
end

-- Hearts and flowers are worked out pixel by pixel, which is slow next to a
-- ring. So each one is worked out once as runs of one colour along its rows
-- (most of a shape is flat colour), kept, and painted again from those runs
-- while nothing about it changes: the home screen redraws far more often
-- than you read a page. A run is x, y (from the shape's centre), length and
-- colour; a heart is a few hundred runs, a big flower a few thousand.
local _shapes, _shape_n, _shape_tick = {}, 0, 0
local SHAPE_MAX = 160

local function shapeRuns(key, render)
    _shape_tick = _shape_tick + 1
    local hit = _shapes[key]
    if hit then hit.used = _shape_tick return hit end
    local ffi = require("ffi")
    local cap, n = 512, 0
    local xs, ys = ffi.new("int16_t[?]", cap), ffi.new("int16_t[?]", cap)
    local ls, ks = ffi.new("int16_t[?]", cap), ffi.new("int32_t[?]", cap)
    local function push(x, y, len, k)
        if n >= cap then
            local nc = cap * 2
            local nx, ny = ffi.new("int16_t[?]", nc), ffi.new("int16_t[?]", nc)
            local nl, nk = ffi.new("int16_t[?]", nc), ffi.new("int32_t[?]", nc)
            ffi.copy(nx, xs, 2 * cap); ffi.copy(ny, ys, 2 * cap)
            ffi.copy(nl, ls, 2 * cap); ffi.copy(nk, ks, 4 * cap)
            xs, ys, ls, ks, cap = nx, ny, nl, nk, nc
        end
        xs[n], ys[n], ls[n], ks[n] = x, y, len, k
        n = n + 1
    end
    -- pixels come in left to right, row by row
    local run_k, run_x, run_y, run_n = -1, 0, 0, 0
    local rec = {}
    function rec.flush()
        if run_n > 0 then push(run_x, run_y, run_n, run_k) end
        run_k, run_n = -1, 0
    end
    -- len pixels of one colour from px (put = one pixel)
    function rec.run(px, py, len, r, g, b)
        local r8 = floor(r + 0.5); r8 = r8 < 0 and 0 or (r8 > 255 and 255 or r8)
        local g8 = floor(g + 0.5); g8 = g8 < 0 and 0 or (g8 > 255 and 255 or g8)
        local b8 = floor(b + 0.5); b8 = b8 < 0 and 0 or (b8 > 255 and 255 or b8)
        local k = r8 * 65536 + g8 * 256 + b8
        if k == run_k and py == run_y and run_x + run_n == px then
            run_n = run_n + len
        else
            rec.flush()
            run_k, run_x, run_y, run_n = k, px, py, len
        end
    end
    function rec.put(px, py, r, g, b) return rec.run(px, py, 1, r, g, b) end
    render(rec)
    rec.flush()
    hit = { n = n, xs = xs, ys = ys, ls = ls, ks = ks, used = _shape_tick }
    if _shape_n >= SHAPE_MAX then
        -- full: let go of the half used longest ago (not all of them, which
        -- would mean working every heart and flower out again at once)
        local ticks = {}
        for _, e in pairs(_shapes) do ticks[#ticks + 1] = e.used end
        table.sort(ticks)
        local cut = ticks[floor(#ticks / 2)] or 0
        for k, e in pairs(_shapes) do
            if e.used <= cut then _shapes[k] = nil; _shape_n = _shape_n - 1 end
        end
    end
    _shapes[key] = hit
    _shape_n = _shape_n + 1
    return hit
end

-- Paint kept runs with their centre at ox, oy, clipped to the bitmap. The
-- Blitbuffer colour of each run colour is worked out once and kept with the
-- runs (per night-mode inversion and colour mode).
local function paintRuns(bb, runs, ox, oy, inv)
    local bw, bh = bb:getWidth(), bb:getHeight()
    local scratch = { 0, 0, 0 }
    local xs, ys, ls, ks = runs.xs, runs.ys, runs.ls, runs.ks
    local mode = (inv and "i" or "n") .. (A.colorMode() and "c" or "g")
    local memo = runs[mode]
    if not memo then memo = {}; runs[mode] = memo end
    local last_k, col = -1, nil
    local Blitbuffer = _BB or BBmod()
    local rgb32 = bb.paintRectRGB32 and Blitbuffer.isColor8 and true or false
    for i = 0, runs.n - 1 do
        local y = oy + ys[i]
        if y >= 0 and y < bh then
            local x, len = ox + xs[i], ls[i]
            if x < 0 then len = len + x; x = 0 end
            if x + len > bw then len = bw - x end
            if len > 0 then
                local k = ks[i]
                if k ~= last_k then
                    col = memo[k]
                    if not col then
                        scratch[1], scratch[2], scratch[3] = floor(k / 65536), floor(k / 256) % 256, k % 256
                        col = A.color(scratch, inv)
                        memo[k] = col
                    end
                    last_k = k
                end
                if rgb32 and not Blitbuffer.isColor8(col) then
                    bb:paintRectRGB32(x, y, len, 1, col)
                else
                    bb:paintRect(x, y, len, 1, col)
                end
            end
        end
    end
end
A._shapeCount = function() return _shape_n end

local function rgbKey(c) return c and (c[1] .. "," .. c[2] .. "," .. c[3]) or "-" end

-- ─── hearts ──────────────────────────────────────────────────────────────────
-- The heart is Inigo Quilez's exact distance function for a heart (tip at
-- (0, 0), the dip between the lobes at (0, 1), y upwards), rounded a little.
-- Being a distance, it gives smooth edges and an outline of any thickness.

local SQ2_4 = sqrt(2) / 4
local function sdHeart(x, y)
    if x < 0 then x = -x end
    if y + x > 1 then
        local dx, dy = x - 0.25, y - 0.75
        return sqrt(dx * dx + dy * dy) - SQ2_4
    end
    local ay = y - 1
    local d1 = x * x + ay * ay
    local m = (x + y > 0) and 0.5 * (x + y) or 0
    local bx, by = x - m, y - m
    local d2 = bx * bx + by * by
    local d = sqrt(d1 < d2 and d1 or d2)
    if x > y then return d elseif x < y then return -d end
    return 0
end
A.sdHeart = sdHeart

local HEART_R = 0.07                                  -- rounding, in heart units
local HEART_W, HEART_H = 1.2071 + 2 * HEART_R, 1.1036 + 2 * HEART_R
local HEART_MID = 1.1036 / 2                          -- the middle of the box, from the tip
local INNER_K, INNER_Y = 0.5, 0.31                    -- the inner heart: its size and where its tip sits
-- the crack of a broken heart, top to bottom: { y, x }
local CRACK = { { 1.2, 0.0 }, { 1.0, 0.0 }, { 0.82, -0.08 }, { 0.62, 0.07 }, { 0.42, -0.06 }, { 0.22, 0.03 }, { -0.2, 0.0 } }
local function crackX(y)
    if y >= CRACK[1][1] then return 0 end
    for i = 2, #CRACK do
        local a, b = CRACK[i - 1], CRACK[i]
        if y >= b[1] then return b[2] + (a[2] - b[2]) * (y - b[1]) / (a[1] - b[1]) end
    end
    return 0
end
A.HEART_ASPECT = HEART_W / HEART_H

-- How full each part of the heart is, as a level from the tip: the level
-- that leaves `frac` of its area under it, so half full looks half full.
-- Worked out once per size (all of a month's hearts share one).
local _levels = {}
local function heartLevels(S, t, gap, nested)
    local key = floor(S * 100) .. ":" .. floor(t * 10) .. ":" .. floor(gap * 10) .. ":" .. tostring(nested)
    local hit = _levels[key]
    if hit then return hit end
    local rows = ceil(HEART_H * S)
    local cols = ceil(HEART_W * S)
    local band, inner = {}, {}
    local tot_b, tot_i = 0, 0
    for j = 0, rows - 1 do
        local hy = -HEART_R + (j + 0.5) / S
        local nb, ni = 0, 0
        for k = 0, cols - 1 do
            local hx = -HEART_W / 2 + (k + 0.5) / S
            local d_o = (sdHeart(hx, hy) - HEART_R) * S
            if d_o < -t then
                if nested then
                    local d_i = (sdHeart(hx / INNER_K, (hy - INNER_Y) / INNER_K) - HEART_R) * INNER_K * S
                    if d_i < -t then ni = ni + 1 elseif d_i > gap then nb = nb + 1 end
                else
                    nb = nb + 1
                end
            end
        end
        tot_b, tot_i = tot_b + nb, tot_i + ni
        band[j + 1], inner[j + 1] = tot_b, tot_i
    end
    hit = { band = band, inner = inner, tot_b = tot_b, tot_i = tot_i, rows = rows }
    local n = 0
    for _ in pairs(_levels) do n = n + 1 end
    if n >= 12 then _levels = {} end
    _levels[key] = hit
    return hit
end

-- frac of the area -> the level (heart units from the tip) it reaches
local function levelFor(cum, total, rows, S, frac)
    frac = tonumber(frac) or 0
    if frac ~= frac or frac <= 0 or total <= 0 then return -math.huge end
    if frac >= 1 then return math.huge end
    local want = frac * total
    local prev = 0
    for j = 1, rows do
        local cur = cum[j]
        if cur >= want then
            local part = (cur > prev) and (want - prev) / (cur - prev) or 1
            return -HEART_R + (j - 1 + part) / S
        end
        prev = cur
    end
    return math.huge
end

-- A heart filling up like a glass, in a box w x h centred on cx, cy.
-- o = { outer = 0..1 (how full), inner = 0..1 or nil (a second heart inside),
--       line = outline colour, line_in = the inner heart's outline colour,
--       fill, fill_in = their fill colours (default: the outline colours),
--       track = colour of what's still empty, t = outline px, gap = px between
--       the hearts, broken = split in two along a crack }
function G.heart(bb, cx, cy, w, h, o, under, inv)
    local S = min(w / HEART_W, h / HEART_H)
    if not (S > 2 and S < 4096 and cx == cx and cy == cy) then return end
    local nested = o.inner ~= nil
    local t = max(1, o.t or S * 0.06)
    local gap = max(1, o.gap or S * 0.05)
    local lv = heartLevels(S, t, gap, nested)
    local lev_o = levelFor(lv.band, lv.tot_b, lv.rows, S, o.outer)
    local lev_i = nested and levelFor(lv.inner, lv.tot_i, lv.rows, S, o.inner) or 0
    local tr, tg, tb = o.track[1], o.track[2], o.track[3]
    local lo = o.line
    local fo = o.fill or lo
    local li = o.line_in or lo
    local fi = o.fill_in or li
    local ur, ug, ub = under[1], under[2], under[3]
    local broken = o.broken
    local ca, sa, shift, half_gap = 1, 0, 0, 0
    if broken then
        local a = 0.085
        ca, sa = math.cos(a), math.sin(a)
        shift = 0
        half_gap = max(0.02, 1.1 / S)
    end
    local ox, oy = floor(cx), floor(cy)
    local key = table.concat({ "h", floor(S * 1000), floor(t * 100), floor(gap * 100), tostring(o.outer), tostring(o.inner),
        tostring(broken), rgbKey(o.track), rgbKey(lo), rgbKey(fo), rgbKey(li), rgbKey(fi), rgbKey(under),
        floor((cx - ox) * 100), floor((cy - oy) * 100) }, "|")
    local hw, hh = HEART_W * S / 2 + 2, HEART_H * S / 2 + 2
    if broken then hw, hh = hw + S * 0.2, hh + S * 0.05 end
    local x0, x1 = floor(cx - hw), ceil(cx + hw)
    local y0, y1 = floor(cy - hh), ceil(cy + hh)

    -- the colour at a point of the heart (heart units), and how much of the
    -- pixel the heart covers
    -- the inner heart and the gap around it, as a box: outside it, no need to ask
    local pad_u = (gap + 2) / S
    local ix0, ix1 = -(HEART_W / 2) * INNER_K - pad_u, (HEART_W / 2) * INNER_K + pad_u
    local iy0, iy1 = INNER_Y - HEART_R * INNER_K - pad_u, INNER_Y + (HEART_H - HEART_R) * INNER_K + pad_u
    local function shade(hx, hy)
        local d_o = (sdHeart(hx, hy) - HEART_R) * S
        local cov = 0.5 - d_o
        if cov <= 0 then return nil end
        if cov > 1 then cov = 1 end
        local f = (lev_o - hy) * S + 0.5
        f = f < 0 and 0 or (f > 1 and 1 or f)
        local r, g, b = tr + (fo[1] - tr) * f, tg + (fo[2] - tg) * f, tb + (fo[3] - tb) * f
        if nested and hx > ix0 and hx < ix1 and hy > iy0 and hy < iy1 then
            local d_i = (sdHeart(hx / INNER_K, (hy - INNER_Y) / INNER_K) - HEART_R) * INNER_K * S
            if d_i < gap + 1 then
                local fi_ = (lev_i - hy) * S + 0.5
                fi_ = fi_ < 0 and 0 or (fi_ > 1 and 1 or fi_)
                local ir, ig, ib = tr + (fi[1] - tr) * fi_, tg + (fi[2] - tg) * fi_, tb + (fi[3] - tb) * fi_
                local kl = d_i + t + 0.5
                kl = kl < 0 and 0 or (kl > 1 and 1 or kl)
                ir, ig, ib = ir + (li[1] - ir) * kl, ig + (li[2] - ig) * kl, ib + (li[3] - ib) * kl
                local kin = 0.5 - d_i
                kin = kin < 0 and 0 or (kin > 1 and 1 or kin)
                local gr, gg, gb = ur + (ir - ur) * kin, ug + (ig - ug) * kin, ub + (ib - ub) * kin
                local kb = d_i - gap + 0.5
                kb = kb < 0 and 0 or (kb > 1 and 1 or kb)
                r, g, b = gr + (r - gr) * kb, gg + (g - gg) * kb, gb + (b - gb) * kb
            end
        end
        local kl = d_o + t + 0.5
        kl = kl < 0 and 0 or (kl > 1 and 1 or kl)
        return r + (lo[1] - r) * kl, g + (lo[2] - g) * kl, b + (lo[3] - b) * kl, cov
    end

    local runs = shapeRuns(key, function(paint)
        for py = y0, y1 do
            local qy = HEART_MID + (cy - (py + 0.5)) / S
            for px = x0, x1 do
                local qx = (px + 0.5 - cx) / S
                local r, g, b, cov
                if broken then
                    -- each half tipped outwards about the tip, a gap along the crack
                    local lx, ly = qx + shift, qy
                    lx, ly = lx * ca + ly * sa, -lx * sa + ly * ca
                    local rx, ry = qx - shift, qy
                    rx, ry = rx * ca - ry * sa, rx * sa + ry * ca
                    -- the crack narrows to nothing at the tip
                    local gl = half_gap * min(1, max(0, ly / 0.6))
                    local gr_ = half_gap * min(1, max(0, ry / 0.6))
                    local kl = (crackX(ly) - gl - lx) * S + 0.5
                    local kr = (rx - crackX(ry) - gr_) * S + 0.5
                    if kl >= kr and kl > 0 then
                        r, g, b, cov = shade(lx, ly)
                        if cov and kl < 1 then cov = cov * kl end
                    elseif kr > 0 then
                        r, g, b, cov = shade(rx, ry)
                        if cov and kr < 1 then cov = cov * kr end
                    end
                else
                    r, g, b, cov = shade(qx, qy)
                end
                if cov and cov > 0.004 then
                    if cov < 1 then r, g, b = ur + (r - ur) * cov, ug + (g - ug) * cov, ub + (b - ub) * cov end
                    paint.put(px - ox, py - oy, r, g, b)
                end
            end
            paint.flush()
        end
    end)
    paintRuns(bb, runs, ox, oy, inv)
end

-- ─── a flower ────────────────────────────────────────────────────────────────
-- A peony from the front: ten big petals round the outside, eight in the
-- middle, six small ones and a heart in the centre, with two leaves behind.
-- `frac` colours it in petal by petal, from the centre outwards and clockwise
-- from the top; the rest stay outlines, like a colouring page.

local FLOWER_RINGS = {   -- inside out: petals, where each petal's middle sits, half its length and width (x R)
    { n = 6, c = 0.25, a = 0.21, b = 0.15, turn = 0, first = 1 },
    { n = 8, c = 0.40, a = 0.30, b = 0.21, turn = 0.5, first = 7 },
    { n = 10, c = 0.56, a = 0.41, b = 0.27, turn = 0, first = 15 },
}
local FLOWER_CORE = 0.15
local FLOWER_UNITS = 25
local FLOWER_LEAVES = { { ang = math.rad(155), r0 = 0.3, len = 0.88, wid = 0.24 },
                        { ang = math.rad(25), r0 = 0.3, len = 0.88, wid = 0.24 } }
local SPARKLES = { { 0.92, -0.8, 0.13 }, { -0.95, -0.62, 0.09 }, { 1.02, -0.38, 0.07 } }
A.FLOWER_UNITS = FLOWER_UNITS

-- o = { frac, fills = { inner, middle, outer, core } (petal colours), line
--       (outline of a coloured petal), empty_line, empty (inside a petal not
--       coloured yet), leaf, leaf_line, sparkle (drawn round it when full) }
function G.flower(bb, cx, cy, R, o, under, inv)
    if not (R > 4 and R < 4096 and cx == cx and cy == cy) then return end
    local frac = tonumber(o.frac) or 0
    if frac ~= frac then frac = 0 end
    local units = A.clamp(frac, 0, 1) * FLOWER_UNITS
    local t = max(1, R * 0.028)
    local ur, ug, ub = under[1], under[2], under[3]
    local line, eline, empty = o.line, o.empty_line, o.empty
    local er, eg, eb = empty[1], empty[2], empty[3]
    local leaf, leaf_line = o.leaf, o.leaf_line
    local spc = (frac >= 1) and o.sparkle or nil
    local PI = math.pi
    local atan2, cos, sin, abs = math.atan2, math.cos, math.sin, math.abs
    local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
    -- each ring's petals: the angle of each (as cos, sin) and how coloured it is
    local rings = {}
    for k, rg in ipairs(FLOWER_RINGS) do
        local step = 2 * PI / rg.n
        local list = {}
        for j = 0, rg.n - 1 do
            local phi = -PI / 2 + (rg.turn + j) * step
            list[j] = { cos(phi), sin(phi), A.clamp(units - (rg.first + j), 0, 1) }
        end
        rings[k] = { n = rg.n, turn = rg.turn, step = step, list = list, A = rg.a * R, B = rg.b * R, C = rg.c * R,
            reach = (rg.c + rg.a) * R + 2, fill = o.fills[k] }
    end
    local L1 = FLOWER_LEAVES[1]
    local L2 = FLOWER_LEAVES[2]
    local lc1, ls1, lc2, ls2 = cos(L1.ang), sin(L1.ang), cos(L2.ang), sin(L2.ang)
    local l_r0, l_len, l_wid = L1.r0 * R, L1.len * R, L1.wid * R
    local core_f = A.clamp(units, 0, 1)
    local core_r = FLOWER_CORE * R
    local core_fill = o.fills[4]

    -- the colour of the pixel so far (kept here, not returned: LuaJIT
    -- compiles that far better than three values handed back and forth)
    local r, g, b = 0, 0, 0
    -- one petal over the colour so far
    local function petal(ring, pt, dx, dy)
        local A_, B_ = ring.A, ring.B
        local u = dx * pt[1] + dy * pt[2] - ring.C
        local v = -dx * pt[2] + dy * pt[1]
        local un, vn = u / A_, v / B_
        local q2 = un * un + vn * vn
        if q2 > 1.5 then return end
        local q = sqrt(q2)
        -- a ruffled edge at the tip
        local thr = 1
        if un > 0 and q > 0 then
            local w = un / q
            thr = 1 - 0.08 * w * w * (0.5 - 0.5 * cos(7 * atan2(vn, un)))
        end
        local ga, gb = un / A_, vn / B_
        local grad = sqrt(ga * ga + gb * gb)
        local d = (q > 0 and grad > 0) and (q - thr) * q / grad or -B_
        local cov = 0.5 - d
        if cov <= 0 then return end
        if cov > 1 then cov = 1 end
        local f = pt[3]
        local pr, pg, pb, l
        if f > 0 then
            local fill = ring.fill
            -- coloured in from the tip, the part that shows
            local kf = f >= 1 and 1 or clamp01(f * 2 * A_ - (A_ - u) + 0.5)
            pr, pg, pb = er + (fill[1] - er) * kf, eg + (fill[2] - eg) * kf, eb + (fill[3] - eb) * kf
            l = line
        else
            pr, pg, pb = er, eg, eb
            l = eline
        end
        local kl = clamp01(d + t + 0.5)
        pr, pg, pb = pr + (l[1] - pr) * kl, pg + (l[2] - pg) * kl, pb + (l[3] - pb) * kl
        r, g, b = r + (pr - r) * cov, g + (pg - g) * cov, b + (pb - b) * cov
    end

    -- one leaf (along cos, sin) over the colour so far
    local function leafAt(lc, ls, dx, dy)
        local u = dx * lc + dy * ls - l_r0
        if u < -2 or u > l_len + 2 then return end
        local v = -dx * ls + dy * lc
        local uu = u < 0 and 0 or (u > l_len and l_len or u)
        local wv = l_wid * sin(PI * uu / l_len)
        local av = abs(v)
        if av > wv + 2 and u >= 0 and u <= l_len then return end
        local slope = l_wid * PI / l_len * cos(PI * uu / l_len)
        local d = (av - wv) / sqrt(1 + slope * slope)
        if u < 0 then d = max(d, -u) elseif u > l_len then d = max(d, u - l_len) end
        local cov = 0.5 - d
        if cov <= 0 then return end
        if cov > 1 then cov = 1 end
        local kl = clamp01(d + t + 0.5)
        -- the vein down the middle
        if u > l_len * 0.06 and u < l_len * 0.82 then
            local vein = clamp01(t * 0.45 - av + 0.5)
            if vein > kl then kl = vein end
        end
        local lr = leaf[1] + (leaf_line[1] - leaf[1]) * kl
        local lg = leaf[2] + (leaf_line[2] - leaf[2]) * kl
        local lb = leaf[3] + (leaf_line[3] - leaf[3]) * kl
        r, g, b = r + (lr - r) * cov, g + (lg - g) * cov, b + (lb - b) * cov
    end

    local reach = R * 1.24
    local ox, oy = floor(cx), floor(cy)
    local f = o.fills
    local key = table.concat({ "f", floor(R * 100), floor(units * 1000), rgbKey(f[1]), rgbKey(f[2]), rgbKey(f[3]), rgbKey(f[4]),
        rgbKey(line), rgbKey(eline), rgbKey(empty), rgbKey(leaf), rgbKey(leaf_line), rgbKey(spc), rgbKey(under),
        floor((cx - ox) * 100), floor((cy - oy) * 100) }, "|")
    local x0, x1 = floor(cx - reach), ceil(cx + reach)
    local y0, y1 = floor(cy - reach), ceil(cy + reach)
    local petal_reach = rings[#rings].reach
    local runs = shapeRuns(key, function(paint)
        for py = y0, y1 do
            local dy = py + 0.5 - cy
            for px = x0, x1 do
                local dx = px + 0.5 - cx
                local rr = sqrt(dx * dx + dy * dy)
                r, g, b = ur, ug, ub
                -- the leaves, behind everything
                if dy > -l_wid then
                    leafAt(lc1, ls1, dx, dy)
                    leafAt(lc2, ls2, dx, dy)
                end
                -- the petals, outside in; of each ring, the two either side of
                -- this point, each lying over the one before it
                if rr < petal_reach then
                    local theta = atan2(dy, dx)
                    for k = #rings, 1, -1 do
                        local ring = rings[k]
                        if rr <= ring.reach then
                            local n = ring.n
                            local j0 = floor((theta + PI / 2) / ring.step - ring.turn)
                            petal(ring, ring.list[j0 % n], dx, dy)
                            petal(ring, ring.list[(j0 + 1) % n], dx, dy)
                        end
                    end
                    -- the heart of the flower: fills from the bottom up
                    if rr < core_r + 1.5 then
                        local d = rr - core_r
                        local cov = clamp01(0.5 - d)
                        local kf = core_f >= 1 and 1 or (core_f <= 0 and 0 or clamp01(core_f * 2 * core_r - (core_r - dy) + 0.5))
                        local cr = er + (core_fill[1] - er) * kf
                        local cg = eg + (core_fill[2] - eg) * kf
                        local cb = eb + (core_fill[3] - eb) * kf
                        local l = core_f > 0 and line or eline
                        local kl = clamp01(d + t + 0.5)
                        cr, cg, cb = cr + (l[1] - cr) * kl, cg + (l[2] - cg) * kl, cb + (l[3] - cb) * kl
                        r, g, b = r + (cr - r) * cov, g + (cg - g) * cov, b + (cb - b) * cov
                    end
                end
                -- a finished flower sparkles
                if spc then
                    for i = 1, #SPARKLES do
                        local sp = SPARKLES[i]
                        local sx, sy, sr = abs(dx - sp[1] * R), abs(dy - sp[2] * R), sp[3] * R
                        if sx < sr + 1 and sy < sr + 1 then
                            local e = (sqrt(sx) + sqrt(sy)) / sqrt(sr)
                            local cov = clamp01((1 - e) * sr * 0.6 + 0.5)
                            if cov > 0 then r, g, b = r + (spc[1] - r) * cov, g + (spc[2] - g) * cov, b + (spc[3] - b) * cov end
                        end
                    end
                end
                if r ~= ur or g ~= ug or b ~= ub then paint.put(px - ox, py - oy, r, g, b) end
            end
            paint.flush()
        end
    end)
    paintRuns(bb, runs, ox, oy, inv)
end

-- ─── little drawings ─────────────────────────────────────────────────────────
-- A small picture made of a few smooth parts (ellipses, leaves, thick
-- strokes), each with a fill and an outline, painted back to front: the
-- dragonfly, the leaves and flowers of the book club's garden. Parts are in
-- units of `size` around the picture's centre, turned by `turn` radians.
--   { "e", x, y, a, b, rot, fill, line }   ellipse, half-axes a (along rot) and b
--   { "v", x, y, len, wid, rot, fill, line, vein }  leaf from (x, y) towards rot
--   { "s", x1, y1, x2, y2, r, fill }       stroke with round ends, no outline
--   { "*", x, y, r, fill }                 a four-pointed sparkle, no outline
--   { "r", x, y, hw, hh, rot, radius, fill, line }  rectangle, round corners
--   { "t", x1, y1, x2, y2, x3, y3, fill, line }       triangle
-- o = { lw = outline px, halo = px of sticker edge round the whole thing,
--       halo_col = its colour }

local function partKey(parts)
    local out = {}
    for i, p in ipairs(parts) do
        local f = {}
        for j, v in ipairs(p) do
            f[j] = type(v) == "table" and rgbKey(v) or (type(v) == "number" and string.format("%.3f", v) or tostring(v))
        end
        out[i] = table.concat(f, ",")
    end
    return table.concat(out, ";")
end

function G.sprite(bb, cx, cy, size, turn, parts, o, under, inv)
    if not (size > 1 and size < 4096 and cx == cx and cy == cy) or #parts == 0 then return end
    o = o or {}
    local lw = max(1, o.lw or size * 0.05)
    local halo = o.halo or 0
    local hcol = o.halo_col or under
    local ox, oy = floor(cx), floor(cy)
    local key = table.concat({ "s", floor(size * 100), floor((turn or 0) * 1000), floor(lw * 10), floor(halo * 10),
        rgbKey(hcol), rgbKey(under), floor((cx - ox) * 100), floor((cy - oy) * 100), partKey(parts) }, "|")
    -- how far the picture reaches from its centre
    local ext = 0
    for _, p in ipairs(parts) do
        local e
        if p[1] == "e" then e = sqrt(p[2] * p[2] + p[3] * p[3]) + max(p[4], p[5])
        elseif p[1] == "v" then e = sqrt(p[2] * p[2] + p[3] * p[3]) + p[4]
        elseif p[1] == "*" then e = sqrt(p[2] * p[2] + p[3] * p[3]) + p[4]
        elseif p[1] == "r" then e = sqrt(p[2] * p[2] + p[3] * p[3]) + sqrt(p[4] * p[4] + p[5] * p[5])
        elseif p[1] == "t" then
            e = max(sqrt(p[2] * p[2] + p[3] * p[3]), sqrt(p[4] * p[4] + p[5] * p[5]), sqrt(p[6] * p[6] + p[7] * p[7]))
        else e = max(sqrt(p[2] * p[2] + p[3] * p[3]), sqrt(p[4] * p[4] + p[5] * p[5])) + p[6] end
        if e > ext then ext = e end
    end
    local reach = ext * size + halo + 2
    local ct, st = math.cos(turn or 0), math.sin(turn or 0)
    local PI = math.pi
    local n = #parts
    -- each part's rotation, worked out once
    local rc, rs = {}, {}
    for i, p in ipairs(parts) do
        local r = (p[1] == "e" or p[1] == "v" or p[1] == "r") and p[6] or 0
        rc[i], rs[i] = math.cos(r), math.sin(r)
    end
    local ur, ug, ub = under[1], under[2], under[3]
    local dist = {}
    local HUGE = math.huge
    -- Where each part can show at all, as a box on screen (with room for the
    -- outline, the sticker edge and the approximate distances): pixels
    -- outside every box are never worked out. A rectangle part also knows,
    -- row by row, the stretch deep inside it that is plain fill.
    local function toPx(lx, ly)
        return cx + (lx * ct - ly * st) * size - 0.5, cy + (lx * st + ly * ct) * size - 0.5
    end
    local bx0, bx1, by0, by1 = {}, {}, {}, {}
    local deep = {}
    local pad = halo + lw + 3
    for i, p in ipairs(parts) do
        local kind = p[1]
        local xs_, ys_, grow = {}, {}, pad
        local function at(lx, ly) local X, Y = toPx(lx, ly); xs_[#xs_ + 1], ys_[#ys_ + 1] = X, Y end
        if kind == "r" then
            for _, sx in ipairs({ -1, 1 }) do
                for _, sy in ipairs({ -1, 1 }) do
                    local u, v = sx * p[4], sy * p[5]
                    at(p[2] + u * rc[i] - v * rs[i], p[3] + u * rs[i] + v * rc[i])
                end
            end
            local m = (lw + 1.5) / size
            local U, V = p[4] - p[7] - m, p[5] - p[7] - m
            if U > 0 and V > 0 then deep[i] = { U = U, V = V } end
        elseif kind == "s" then
            at(p[2], p[3]); at(p[4], p[5])
            grow = p[6] * size + pad
        elseif kind == "t" then
            at(p[2], p[3]); at(p[4], p[5]); at(p[6], p[7])
        elseif kind == "v" then
            at(p[2], p[3]); at(p[2] + p[4] * rc[i], p[3] + p[4] * rs[i])
            grow = (p[5] * size + pad) * 1.6 + 4
        elseif kind == "*" then
            at(p[2], p[3])
            local sr = p[4] * size
            local reach_ = sr * (1 + (halo + 1.5) / (0.6 * max(sr, 0.01))) ^ 2
            grow = reach_ + 3
        else -- "e"
            at(p[2], p[3])
            grow = (max(p[4], p[5]) * size + pad) * 1.6 + 4
        end
        local x0, x1, y0, y1 = HUGE, -HUGE, HUGE, -HUGE
        for j = 1, #xs_ do
            x0, x1 = min(x0, xs_[j]), max(x1, xs_[j])
            y0, y1 = min(y0, ys_[j]), max(y1, ys_[j])
        end
        bx0[i], bx1[i], by0[i], by1[i] = floor(x0 - grow), ceil(x1 + grow), floor(y0 - grow), ceil(y1 + grow)
    end
    -- the pixels px (this row) where |a * px + b| <= U
    local function span(a, b, U)
        if a > -1e-12 and a < 1e-12 then
            if b >= -U and b <= U then return -HUGE, HUGE end
            return 1, 0
        end
        local p1, p2 = (-U - b) / a, (U - b) / a
        if p1 > p2 then p1, p2 = p2, p1 end
        return ceil(p1 + 1e-6), floor(p2 - 1e-6)
    end
    local act, dlo, dhi = {}, {}, {}
    local runs = shapeRuns(key, function(paint)
        for py = floor(cy - reach), ceil(cy + reach) do
            local dy = (py + 0.5 - cy) / size
            -- the parts that reach this row, and the stretch of the row worth a look
            local rx0, rx1 = HUGE, -HUGE
            for i = 1, n do
                if py >= by0[i] and py <= by1[i] then
                    if bx0[i] < rx0 then rx0 = bx0[i] end
                    if bx1[i] > rx1 then rx1 = bx1[i] end
                end
                dlo[i], dhi[i] = 1, 0
                local dp_ = deep[i]
                if dp_ then
                    -- u, v of the part's own frame along this row: linear in px
                    local p = parts[i]
                    local lx0, ly0 = (0.5 - cx) / size * ct + dy * st, -(0.5 - cx) / size * st + dy * ct
                    local qx, qy = lx0 - p[2], ly0 - p[3]
                    local u0, v0 = qx * rc[i] + qy * rs[i], -qx * rs[i] + qy * rc[i]
                    local du = (ct * rc[i] - st * rs[i]) / size
                    local dv = -(ct * rs[i] + st * rc[i]) / size
                    local a1, b1 = span(du, u0, dp_.U)
                    local a2, b2 = span(dv, v0, dp_.V)
                    dlo[i], dhi[i] = max(a1, a2), min(b1, b2)
                end
            end
            local xa, xb = max(floor(cx - reach), rx0), min(ceil(cx + reach), rx1)
            local px = xa
            while px <= xb do
                local step = 1
                local any = false
                for i = 1, n do
                    local on = py >= by0[i] and py <= by1[i] and px >= bx0[i] and px <= bx1[i]
                    act[i] = on
                    if on then any = true end
                end
                -- deep inside the topmost rectangle here, and nothing over it: its fill
                local k = 0
                if any then
                    for i = n, 1, -1 do
                        if px >= dlo[i] and px <= dhi[i] then k = i break end
                    end
                    if k > 0 then
                        for j = k + 1, n do if act[j] then k = 0 break end end
                    end
                end
                if k > 0 then
                    -- and on along the row while that holds: up to the end of
                    -- the deep stretch or the next part over it
                    local e = min(dhi[k], xb)
                    for j = k + 1, n do
                        if py >= by0[j] and py <= by1[j] and bx0[j] > px and bx0[j] - 1 < e then e = bx0[j] - 1 end
                    end
                    step = e - px + 1
                    local fill = parts[k][8]
                    paint.run(px - ox, py - oy, step, fill[1], fill[2], fill[3])
                elseif any then
                local dx = (px + 0.5 - cx) / size
                local lx, ly = dx * ct + dy * st, -dx * st + dy * ct
                local dmin = HUGE
                for i = 1, n do
                    local p = parts[i]
                    local d
                    local kind = p[1]
                    if not act[i] then
                        d = HUGE
                    elseif kind == "e" then
                        local qx, qy = lx - p[2], ly - p[3]
                        local u, v = qx * rc[i] + qy * rs[i], -qx * rs[i] + qy * rc[i]
                        local a, b = p[4], p[5]
                        local un, vn = u / a, v / b
                        local q = sqrt(un * un + vn * vn)
                        local ga, gb = un / a, vn / b
                        local grad = sqrt(ga * ga + gb * gb)
                        d = (q > 0 and grad > 0) and (q - 1) * q / grad or -min(a, b)
                    elseif kind == "v" then
                        local qx, qy = lx - p[2], ly - p[3]
                        local u, v = qx * rc[i] + qy * rs[i], -qx * rs[i] + qy * rc[i]
                        local L, W = p[4], p[5]
                        local uu = u < 0 and 0 or (u > L and L or u)
                        local wv = W * math.sin(PI * uu / L)
                        local slope = W * PI / L * math.cos(PI * uu / L)
                        d = (math.abs(v) - wv) / sqrt(1 + slope * slope)
                        if u < 0 then d = max(d, -u) elseif u > L then d = max(d, u - L) end
                        dist[-i] = u                     -- kept for the vein
                        dist[-n - i] = v
                    elseif kind == "*" then
                        local sx, sy, sr = math.abs(lx - p[2]), math.abs(ly - p[3]), p[4]
                        d = ((sqrt(sx) + sqrt(sy)) / sqrt(sr) - 1) * sr * 0.6
                    elseif kind == "t" then
                        -- distance to the nearest edge, negative inside
                        local best = math.huge
                        local sgn = 0
                        local inside = true
                        for e = 0, 2 do
                            local ax, ay = p[2 + 2 * e], p[3 + 2 * e]
                            local bx2, by2 = p[2 + 2 * ((e + 1) % 3)], p[3 + 2 * ((e + 1) % 3)]
                            local ex, ey = bx2 - ax, by2 - ay
                            local len2 = ex * ex + ey * ey
                            local tt = len2 > 0 and ((lx - ax) * ex + (ly - ay) * ey) / len2 or 0
                            tt = tt < 0 and 0 or (tt > 1 and 1 or tt)
                            local fx, fy = ax + ex * tt - lx, ay + ey * tt - ly
                            local dd = sqrt(fx * fx + fy * fy)
                            if dd < best then best = dd end
                            local cr = ex * (ly - ay) - ey * (lx - ax)
                            if sgn == 0 then sgn = cr > 0 and 1 or -1
                            elseif (cr > 0 and sgn < 0) or (cr < 0 and sgn > 0) then inside = false end
                        end
                        d = inside and -best or best
                    elseif kind == "r" then
                        local qx, qy = lx - p[2], ly - p[3]
                        local u, v = qx * rc[i] + qy * rs[i], -qx * rs[i] + qy * rc[i]
                        local rad = p[7]
                        local ax, ay = math.abs(u) - (p[4] - rad), math.abs(v) - (p[5] - rad)
                        local ox_, oy_ = ax > 0 and ax or 0, ay > 0 and ay or 0
                        local inside = max(ax, ay)
                        d = sqrt(ox_ * ox_ + oy_ * oy_) + (inside < 0 and inside or 0) - rad
                    else
                        local ax, ay, bx2, by2 = p[2], p[3], p[4], p[5]
                        local ex, ey = bx2 - ax, by2 - ay
                        local len2 = ex * ex + ey * ey
                        local tt = len2 > 0 and ((lx - ax) * ex + (ly - ay) * ey) / len2 or 0
                        tt = tt < 0 and 0 or (tt > 1 and 1 or tt)
                        local fx, fy = ax + ex * tt - lx, ay + ey * tt - ly
                        d = sqrt(fx * fx + fy * fy) - p[6]
                    end
                    if d ~= HUGE then d = d * size end
                    dist[i] = d
                    if d < dmin then dmin = d end
                end
                if dmin < halo + 0.5 then
                    local r, g, b = ur, ug, ub
                    if halo > 0 then
                        local kh = halo + 0.5 - dmin
                        kh = kh > 1 and 1 or kh
                        r, g, b = r + (hcol[1] - r) * kh, g + (hcol[2] - g) * kh, b + (hcol[3] - b) * kh
                    end
                    for i = 1, n do
                        local d = dist[i]
                        local cov = 0.5 - d
                        if cov > 0 then
                            if cov > 1 then cov = 1 end
                            local p = parts[i]
                            local kind = p[1]
                            local fill, line
                            if kind == "*" then fill = p[5]
                            elseif kind == "r" or kind == "t" then fill, line = p[8], p[9]
                            elseif kind == "s" then fill = p[7]
                            else fill, line = p[7], p[8] end
                            local fr, fg, fb = fill[1], fill[2], fill[3]
                            if line then
                                local kl = d + lw + 0.5
                                -- a leaf's vein down its middle
                                if p[1] == "v" and p[9] then
                                    local u, v = dist[-i], dist[-n - i]
                                    if u > p[4] * 0.08 and u < p[4] * 0.8 then
                                        local kv = lw * 0.45 - math.abs(v) * size + 0.5
                                        if kv > kl then kl = kv end
                                    end
                                end
                                kl = kl < 0 and 0 or (kl > 1 and 1 or kl)
                                fr, fg, fb = fr + (line[1] - fr) * kl, fg + (line[2] - fg) * kl, fb + (line[3] - fb) * kl
                            end
                            r, g, b = r + (fr - r) * cov, g + (fg - g) * cov, b + (fb - b) * cov
                        end
                    end
                    paint.put(px - ox, py - oy, r, g, b)
                end
                end
                px = px + step
            end
            paint.flush()
        end
    end)
    paintRuns(bb, runs, ox, oy, inv)
end

-- ─── fonts and text ──────────────────────────────────────────────────────────
-- Everything here is sized in real pixels, derived from the panel's size.
-- KOReader's Font:getFace takes a size that it scales for the screen itself
-- (ceil(size * scale)), so convert back before asking.

local function dp(px)
    local Screen = A.screen()
    local scale = Screen:scaleBySize(1000000) / 1000000
    return max(1, (px - 0.5) / scale)
end

function A.face(px, o)
    o = o or {}
    px = max(8, floor(px + 0.5))
    -- (asked of Font:getFace as KOReader has it, before Simple UI's Global
    -- Text Size scales it: the cards are drawn to fit their box)
    if o.symbol then
        -- icon glyphs: KOReader's bundled Nerd Font symbols
        local Font = require("ui/font")
        local getFace = A.host.nativeGetFace() or Font.getFace
        local ok, face = pcall(getFace, Font, "symbols", dp(px))
        if ok and face then return face, false end
    end
    if o.mono then
        local Font = require("ui/font")
        local ok, face = pcall(Font.getFace, Font, "DroidSansMono.ttf", dp(px))
        if ok and face then return face, false end
    end
    if o.chess then
        -- chess pieces: KOReader's bundled FreeSerif has all twelve
        local Font = require("ui/font")
        local getFace = A.host.nativeGetFace() or Font.getFace
        local ok, face = pcall(getFace, Font, "FreeSerif.ttf", dp(px))
        if ok and face then return face, false end
    end
    if o.serif or (not o.mono and not o.symbol and not o.sans and A.serifTheme()) then
        local Font = require("ui/font")
        local name = o.bold and "NotoSerif-Bold.ttf" or (o.italic and "NotoSerif-Italic.ttf" or "NotoSerif-Regular.ttf")
        local getFace = A.host.nativeGetFace() or Font.getFace
        local ok, face = pcall(getFace, Font, name, dp(px))
        if ok and face then return face, false end
    end
    local ok, face, bold = pcall(A.host.face, dp(px), o)
    if ok and face then return face, bold end
    local Font = require("ui/font")
    return Font:getFace(o.bold and "tfont" or "cfont", dp(px)), false
end

-- Single-line text that keeps a colour ink a colour (see colourtext.lua).
local function textClass()
    return A.host.textClass()
end

-- Wrapped text that composites over whatever is behind it. KOReader's
-- TextBoxWidget paints an opaque box in a flattened grey, which shows as a
-- slab on a coloured card; this renders black-on-white once and uses that
-- bitmap as the coverage mask for the ink (the approach Bookshelf's own
-- TransparentTextBox takes, extended to keep a colour ink a colour).
local _MText
local function mtextClass()
    if _MText then return _MText end
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Blitbuffer = require("ffi/blitbuffer")
    _MText = TextBoxWidget:extend{ ink = nil }
    function _MText:init()
        self.ink = self.fgcolor or Blitbuffer.COLOR_BLACK
        self.fgcolor = Blitbuffer.COLOR_BLACK
        self.bgcolor = Blitbuffer.COLOR_WHITE
        TextBoxWidget.init(self)
    end
    function _MText:paintTo(bb, x, y)
        local m = self._bb
        if not m then return TextBoxWidget.paintTo(self, bb, x, y) end
        if self.dimen then self.dimen.x, self.dimen.y = x, y end
        local w, h = m:getWidth(), m:getHeight()
        m:invertRect(0, 0, w, h)
        local ok
        if bb.colorblitFromRGB32 and Blitbuffer.isColor8 and not Blitbuffer.isColor8(self.ink) then
            ok = pcall(bb.colorblitFromRGB32, bb, m, x, y, 0, 0, w, h, self.ink)
        else
            ok = pcall(bb.colorblitFrom, bb, m, x, y, 0, 0, w, h, self.ink)
        end
        m:invertRect(0, 0, w, h)
        if not ok then TextBoxWidget.paintTo(self, bb, x, y) end
    end
    return _MText
end

-- ─── paint cache ─────────────────────────────────────────────────────────────
-- A card is drawn from its list of drawing steps every time it is painted,
-- and most of the time that is the same picture again: the minute tick
-- repaints a page where only the clock changed, a tab you go back to shows
-- what it showed before, a menu closing repaints what was under it. So as a
-- card is built it also writes down what it draws (each shape with its size,
-- place and colours, each text with its font, which cover bitmap). The first
-- time it is painted the result is kept under that description; painted
-- again with the same description over the same background, the kept
-- picture is copied back instead of drawn. Anything that would change the
-- picture changes the description, so a kept picture is never out of date.
--
-- Only cards are kept (not every piece inside one), only while the screen is
-- neither rotated nor inverted in software (the copies are then straight
-- memory copies), and within about two screens' worth of pixels. Pictures
-- not used for ten minutes (while you read, say) are let go.

-- Appends a plain description of v to out (one token per entry; they are
-- joined with a separator): numbers, strings, booleans, and tables (lists and
-- options) by their contents. Anything else by identity (a cover bitmap stays
-- the same object while it is cached).
local function ser(v, out, depth)
    local t = type(v)
    if t == "number" or t == "string" then
        out[#out + 1] = v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "nil" then
        out[#out + 1] = "N"
    elseif t == "table" and depth < 6 then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do ser(v[i], out, depth + 1) end
        local keys
        for k in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
                keys = keys or {}
                keys[#keys + 1] = tostring(k)
            end
        end
        if keys then
            table.sort(keys)
            for _, k in ipairs(keys) do
                local val = v[k]
                if val == nil then val = v[tonumber(k)] end
                out[#out + 1] = k
                ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = tostring(v)
    end
end
A._ser = ser

local PC = { map = {}, n = 0, bytes = 0, tick = 0, hits = 0, misses = 0, swept = false }
A.PC = PC
local SWEEP_AFTER = 600

function A.paintCacheClear()
    for _, e in pairs(PC.map) do pcall(e.bb.free, e.bb) end
    PC.map, PC.n, PC.bytes = {}, 0, 0
end

-- About two screens' worth, in the bitmap's own bytes per pixel.
local function pcBudget(bb)
    local Screen = A.screen()
    local bpp = (bb.getBpp and bb:getBpp() or 32) / 8
    return floor(Screen:getWidth() * Screen:getHeight() * bpp * 2)
end

local function pcSweep()
    PC.swept = false
    local now = os.time()
    for k, e in pairs(PC.map) do
        if now - e.at > SWEEP_AFTER then
            pcall(e.bb.free, e.bb)
            PC.map[k] = nil
            PC.n, PC.bytes = PC.n - 1, PC.bytes - e.bytes
        end
    end
    if PC.n > 0 then
        PC.swept = true
        pcall(function() require("ui/uimanager"):scheduleIn(SWEEP_AFTER, pcSweep) end)
    end
end

local function pcPut(key, bb, samples, budget)
    local bytes = bb:getWidth() * bb:getHeight() * ((bb.getBpp and bb:getBpp() or 32) / 8)
    if bytes > budget then pcall(bb.free, bb) return end
    while PC.bytes + bytes > budget and PC.n > 0 do
        local old_k, old_e
        for k, e in pairs(PC.map) do
            if not old_e or e.used < old_e.used then old_k, old_e = k, e end
        end
        pcall(old_e.bb.free, old_e.bb)
        PC.map[old_k] = nil
        PC.n, PC.bytes = PC.n - 1, PC.bytes - old_e.bytes
    end
    PC.tick = PC.tick + 1
    PC.map[key] = { bb = bb, samples = samples, bytes = bytes, used = PC.tick, at = os.time() }
    PC.n, PC.bytes = PC.n + 1, PC.bytes + bytes
    if not PC.swept then
        PC.swept = true
        pcall(function() require("ui/uimanager"):scheduleIn(SWEEP_AFTER, pcSweep) end)
    end
end

-- A few pixels of what is under the card, so a kept picture is only used
-- over the same background it was painted on.
local SAMPLE_AT = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 }, { 0.5, 0 }, { 0.5, 1 }, { 0, 0.5 }, { 1, 0.5 } }
local function pcSamples(bb, x, y, w, h)
    local out = {}
    for i, p in ipairs(SAMPLE_AT) do
        local c = bb:getPixel(x + floor(p[1] * (w - 1)), y + floor(p[2] * (h - 1)))
        local ok, r, g, b = pcall(function()
            local x32 = c:getColorRGB32()
            return x32.r, x32.g, x32.b
        end)
        out[i] = ok and (r * 65536 + g * 256 + b) or tostring(c)
    end
    return table.concat(out, ",")
end

-- Whether pictures can be kept for painting into bb, at this rectangle.
local function pcUsable(bb, x, y, w, h)
    if A._no_paint_cache then return false end
    if not (bb.getRotation and bb.getInverse and bb.getType and bb.getBpp) then return false end
    if bb:getRotation() ~= 0 or bb:getInverse() ~= 0 or bb:getBpp() < 8 then return false end
    if w < 8 or h < 8 or x < 0 or y < 0 or x + w > bb:getWidth() or y + h > bb:getHeight() then return false end
    return true
end

-- Some cards draw a little past their own edges (washi tape over a corner,
-- a big title nudged left). Those are drawn straight onto the screen every
-- time instead, as before: a kept picture would cut them off. Found out the
-- first time, by drawing with a margin around the card and checking whether
-- anything in the margin changed.
local SPILL = 40
PC.spills, PC.spill_n = {}, 0
local _memcmp
local function memcmp()
    if _memcmp == nil then
        local ffi = require("ffi")
        pcall(ffi.cdef, "int memcmp(const void *s1, const void *s2, size_t n);")
        local ok = pcall(function() return ffi.C.memcmp end)
        _memcmp = ok and ffi.C.memcmp or false
    end
    return _memcmp
end
-- Do rows of a (from ax, ay) and b (from bx, by), w x h pixels, differ?
local function rowsDiffer(a, ax, ay, b, bx, by, w, h, bpp)
    if w <= 0 or h <= 0 then return false end
    local cmp = memcmp()
    if not cmp then return true end
    local ffi = require("ffi")
    local pa, pb = ffi.cast("uint8_t *", a.data), ffi.cast("uint8_t *", b.data)
    local sa, sb = tonumber(a.stride), tonumber(b.stride)
    local n = w * bpp
    for r = 0, h - 1 do
        if cmp(pa + (ay + r) * sa + ax * bpp, pb + (by + r) * sb + bx * bpp, n) ~= 0 then return true end
    end
    return false
end

-- ─── Canvas ──────────────────────────────────────────────────────────────────
-- One card. Things are placed at absolute pixel positions inside it, which
-- keeps layout and tap regions in the same coordinates.
--
-- Night mode: KOReader inverts the whole screen. A dark card would come out
-- pale, so a dark-toned canvas paints every colour pre-inverted and ends up
-- looking the same as by day. (The light "paper" card switches to a dark
-- variant at night for the same reason; see A.tone.) Covers are inverted
-- once more after they are drawn, so they keep their real colours.

local _Canvas
local function canvasClass()
    if _Canvas then return _Canvas end
    local Widget = require("ui/widget/widget")
    local Geom = require("ui/geometry")
    local C = Widget:extend{ w = 0, h = 0 }

    function C:init()
        self.ops = {}
        self.regions = {}
        self.owned = {}
        self.sig = {}
        self.dimen = Geom:new{ w = self.w, h = self.h }
        local Screen = A.screen()
        -- Night mode inverts the screen. Cards meant to look the same day and
        -- night (every dark card, and every card of the newer themes) are
        -- painted pre-inverted.
        local tone = self.tone
        self.inv = (Screen.night_mode and tone and (tone.dark or tone.fixed)) and true or false
        -- Colour that sits under this canvas, in the canvas's own colour
        -- space. `page` = the Dashboard's page colour as it should LOOK, when
        -- this card is on one; otherwise the app's own background.
        if self.page then
            self.under = self.inv and self.page or A.shown(self.page)
        else
            local page_bg = A.pageColors()
            self.under = self.inv and { 255 - page_bg[1], 255 - page_bg[2], 255 - page_bg[3] } or page_bg
        end
        self:mark("base", self.w, self.h, tone and tone.bg, tone and tone.border, self.radius, self.border_w,
            self.plain, self.fill, self.under, self.inv, self.bleed, { self.behind or false, tone and tone.cut or false })
    end

    -- Write down one drawing step (see the paint cache above): a tag and up
    -- to twelve values. (Fixed arguments rather than ..., which keeps it fast
    -- for cards that draw thousands of small steps.)
    function C:mark(tag, a, b, c, d, e, f, g, h, i, j, k, l)
        local sig = self.sig
        sig[#sig + 1] = tag
        ser(a, sig, 0); ser(b, sig, 0); ser(c, sig, 0); ser(d, sig, 0)
        ser(e, sig, 0); ser(f, sig, 0); ser(g, sig, 0); ser(h, sig, 0)
        ser(i, sig, 0); ser(j, sig, 0); ser(k, sig, 0); ser(l, sig, 0)
        self._key = nil
    end

    -- Everything this canvas draws, as one string (nested canvases included).
    function C:sigKey()
        local k = self._key
        if k then return k end
        local sig, out = self.sig, {}
        for i = 1, #sig do
            local e = sig[i]
            if type(e) == "table" then out[i] = e.sigKey and e:sigKey() or tostring(e)
            else out[i] = e end
        end
        k = table.concat(out, "\1")
        self._key = k
        return k
    end

    function C:getSize() return Geom:new{ w = self.w, h = self.h } end

    function C:col(rgb) return A.color(rgb, self.inv) end

    function C:op(fn) self.ops[#self.ops + 1] = fn end

    function C:rect(x, y, w, h, rgb)
        local inv = self.inv
        -- written down directly: some cards draw a great many of these
        local sig = self.sig
        local n = #sig
        sig[n + 1], sig[n + 2], sig[n + 3], sig[n + 4], sig[n + 5] = "r", x, y, w, h
        sig[n + 6], sig[n + 7], sig[n + 8], sig[n + 9] = rgb[1], rgb[2], rgb[3], inv and "i" or "-"
        self._key = nil
        self:op(function(bb, ox, oy) G.rect(bb, ox + x, oy + y, w, h, rgb, inv) end)
    end

    -- (the Cyber theme's cards have square corners throughout)
    function C:rrect(x, y, w, h, r, rgb, under)
        local inv = self.inv
        if self.tone and self.tone.square then r = 0 end
        under = under or (self.tone and self.tone.bg) or self.under
        self:mark("rr", x, y, w, h, r, rgb, under, inv)
        self:op(function(bb, ox, oy) G.rrect(bb, ox + x, oy + y, w, h, r, rgb, under, inv) end)
    end

    function C:frame(x, y, w, h, r, bw, border, fill, under)
        local inv = self.inv
        if self.tone and self.tone.square then r = 0 end
        under = under or (self.tone and self.tone.bg) or self.under
        self:mark("fr", x, y, w, h, r, bw, border, fill, under, inv)
        self:op(function(bb, ox, oy) G.frame(bb, ox + x, oy + y, w, h, r, bw, border, fill, under, inv) end)
    end

    function C:disc(cx, cy, r, rgb, under)
        local inv = self.inv
        under = under or (self.tone and self.tone.bg) or self.under
        self:mark("d", cx, cy, r, rgb, under, inv)
        self:op(function(bb, ox, oy) G.disc(bb, ox + cx, oy + cy, r, rgb, under, inv) end)
    end

    function C:ring(cx, cy, R, t, frac, track, fill)
        local inv = self.inv
        local under = (self.tone and self.tone.bg) or self.under
        self:mark("g", cx, cy, R, t, frac, track, fill, under, inv)
        self:op(function(bb, ox, oy) G.ring(bb, ox + cx, oy + cy, R, t, frac, track, fill, under, inv) end)
    end

    -- A small drawing made of parts; see G.sprite.
    function C:sprite(cx, cy, size, turn, parts, o)
        local inv = self.inv
        local under = (self.tone and self.tone.bg) or self.under
        self:mark("s", cx, cy, size, turn, parts, o, under, inv)
        self:op(function(bb, ox, oy) G.sprite(bb, ox + cx, oy + cy, size, turn, parts, o, under, inv) end)
    end

    -- A flower coloured in petal by petal; see G.flower for `o`.
    function C:flower(cx, cy, R, o)
        local inv = self.inv
        local under = (self.tone and self.tone.bg) or self.under
        self:mark("f", cx, cy, R, o, under, inv)
        self:op(function(bb, ox, oy) G.flower(bb, ox + cx, oy + cy, R, o, under, inv) end)
    end

    -- A heart filling up from the tip; see G.heart for `o`.
    function C:heart(cx, cy, w, h, o)
        local inv = self.inv
        local under = (self.tone and self.tone.bg) or self.under
        self:mark("h", cx, cy, w, h, o, under, inv)
        self:op(function(bb, ox, oy) G.heart(bb, ox + cx, oy + cy, w, h, o, under, inv) end)
    end

    -- A line through points { x1, y1, x2, y2, ... } in canvas coordinates.
    function C:polyline(pts, lw, rgb, under)
        local inv = self.inv
        under = under or (self.tone and self.tone.bg) or self.under
        self:mark("p", pts, lw, rgb, under, inv)
        self:op(function(bb, ox, oy)
            local moved = {}
            for i = 1, #pts, 2 do moved[i], moved[i + 1] = pts[i] + ox, pts[i + 1] + oy end
            G.polyline(bb, moved, lw, rgb, under, inv)
        end)
    end

    -- A single line of text. Returns { widget, w, h, base } without placing it.
    function C:text(str, px, o)
        o = o or {}
        local face, bold = A.face(px, o)
        local rgb = o.color or (self.tone and self.tone.fg) or { 0, 0, 0 }
        local txt = o.caps and A.upper(str) or A.safe(str)
        local tw = textClass():new{
            text = txt, face = face, bold = bold and true or false,
            fgcolor = self:col(rgb),
            max_width = o.max_w and max(8, floor(o.max_w)) or nil,
        }
        local sz = tw:getSize()
        self.owned[#self.owned + 1] = tw
        local d = { "t" }
        ser({ txt, face.hash or face.realname, face.size, bold and true or false, rgb, self.inv,
            o.max_w and max(8, floor(o.max_w)) or false }, d, 0)
        return { widget = tw, w = sz.w, h = sz.h, base = tw:getBaseline() or sz.h, px = px, sig = table.concat(d, "\1") }
    end

    -- Wrapped text, at most `lines` lines (ellipsis after that).
    function C:textbox(str, px, width, lines, o)
        o = o or {}
        local face, bold = A.face(px, o)
        local rgb = o.color or (self.tone and self.tone.fg) or { 0, 0, 0 }
        local lh = o.line_height or 0.18
        local line_px = floor((1 + lh) * face.size + 0.5)
        local tb = mtextClass():new{
            text = o.caps and A.upper(str) or A.safe(str),
            face = face, bold = bold and true or false,
            width = max(20, floor(width)),
            height = lines and (line_px * lines) or nil,
            height_adjust = lines and true or nil,
            height_overflow_show_ellipsis = lines and true or nil,
            line_height = lh,
            alignment = o.align or "left",
            fgcolor = self:col(rgb),
        }
        local sz = tb:getSize()
        self.owned[#self.owned + 1] = tb
        local d = { "b" }
        ser({ tb.text, face.hash or face.realname, face.size, bold and true or false, rgb, self.inv,
            max(20, floor(width)), lines or false, lh, o.align or "left" }, d, 0)
        return { widget = tb, w = sz.w, h = sz.h, base = sz.h, px = px, box = true, sig = table.concat(d, "\1") }
    end

    -- Place a text. anchor: "l" (default), "c", "r" relative to x.
    -- valign: "top" (default), "base" (y is the baseline), "mid" (y is the centre).
    function C:put(t, x, y, anchor, valign)
        if anchor == "r" then x = x - t.w elseif anchor == "c" then x = x - t.w / 2 end
        if valign == "base" then y = y - t.base elseif valign == "mid" then y = y - t.h / 2 end
        x, y = floor(x + 0.5), floor(y + 0.5)
        local w = t.widget
        self:mark("P", t.sig or tostring(w), x, y)
        self:op(function(bb, ox, oy) w:paintTo(bb, ox + x, oy + y) end)
        return x, y
    end

    -- Create and place in one go. Returns the text record.
    function C:label(str, px, x, y, o)
        o = o or {}
        local t = self:text(str, px, o)
        self:put(t, x, y, o.anchor, o.valign)
        return t
    end

    -- A book cover, cropped to fill w x h. `fp` may be nil (placeholder).
    -- o = { title = (shown when there is no cover), edge = border colour,
    --       border = width or false, top = crop from the top, not the middle }
    function C:cover(fp, x, y, w, h, o)
        o = o or {}
        x, y, w, h = floor(x), floor(y), floor(w), floor(h)
        if w < 4 or h < 2 then return end
        local tone = self.tone or A.tone("ink")
        local src = fp and A.D and A.D.cover(fp, w, h, o.top and "top" or nil) or nil
        local inv = self.inv
        local bw = o.border == false and 0 or max(1, floor((o.border or 1)))
        local edge = o.edge or tone.muted
        local title
        if not src and o.title and w >= 40 then
            title = self:textbox(o.title, max(9, floor(w / 8)), w - floor(w / 6), 4,
                { bold = true, color = tone.fg, align = "center" })
        end
        self:mark("c", fp or false, x, y, w, h, src and tostring(src) or false, o.top or false, bw, edge,
            title and title.sig or false, tone.track, inv)
        self:op(function(bb, ox, oy)
            local X, Y = ox + x, oy + y
            if src then
                local sw, sh = src:getWidth(), src:getHeight()
                local sx = max(0, floor((sw - w) / 2))
                local sy = o.top and 0 or max(0, floor((sh - h) / 2))
                local Screen = A.screen()
                if Screen.sw_dithering and bb.ditherblitFrom then
                    bb:ditherblitFrom(src, X, Y, sx, sy, min(w, sw), min(h, sh))
                else
                    bb:blitFrom(src, X, Y, sx, sy, min(w, sw), min(h, sh))
                end
                -- keep the cover's real colours when the screen is inverted
                if Screen.night_mode then bb:invertRect(X, Y, min(w, sw), min(h, sh)) end
            else
                G.rect(bb, X, Y, w, h, tone.track, inv)
                if title then
                    title.widget:paintTo(bb, X + floor((w - title.w) / 2), Y + floor((h - title.h) / 2))
                end
            end
            if bw > 0 then
                local c = A.color(edge, inv)
                fillRect(bb, X, Y, w, bw, c)
                fillRect(bb, X, Y + h - bw, w, bw, c)
                fillRect(bb, X, Y, bw, h, c)
                fillRect(bb, X + w - bw, Y, bw, h, c)
            end
        end)
    end

    -- A cover w x h turned by `angle` radians (a few degrees) about cx, cy.
    -- Turned with two shears, a row and then a column at a time, so it's
    -- all fast bitmap copies and nothing outside the picture is touched.
    function C:tilted(fp, cx, cy, w, h, angle, o)
        o = o or {}
        w, h = floor(w), floor(h)
        if w < 4 or h < 4 then return end
        local tone = self.tone or A.tone("ink")
        local src = fp and A.D and A.D.cover(fp, w, h, nil, true) or nil
        if not src then
            self:sprite(cx, cy, w, angle, { { "r", 0, 0, 0.5, 0.5 * h / w, 0, 0, tone.track, nil } }, { lw = 1 })
            if o.title and w >= 40 then
                local t = self:textbox(o.title, max(9, floor(w / 8)), w - floor(w / 6), 4,
                    { bold = true, color = tone.fg, align = "center" })
                self:put(t, cx, cy, "c", "mid")
            end
            return
        end
        self:mark("tc", fp, cx, cy, w, h, angle, tostring(src))
        self:op(function(bb, ox, oy)
            local Blitbuffer = require("ffi/blitbuffer")
            local sw, sh = src:getWidth(), src:getHeight()
            local sx0, sy0 = max(0, floor((sw - w) / 2)), max(0, floor((sh - h) / 2))
            local ww, hh = min(w, sw), min(h, sh)
            local sn = math.sin(angle)
            local Wt = ww + ceil(math.abs(sn) * hh) + 2
            local ok, tmp = pcall(Blitbuffer.new, Wt, hh, src:getType())
            if not ok or not tmp then return end
            -- first each row moves sideways
            local rowx = {}
            for y = 0, hh - 1 do
                local x0 = floor(Wt / 2 - ww / 2 - sn * (y + 0.5 - hh / 2) + 0.5)
                rowx[y] = x0
                tmp:blitFrom(src, x0, y, sx0, sy0 + y, ww, 1)
            end
            -- then each column moves up or down: only the rows that reach it
            local Screen = A.screen()
            local dither = Screen.sw_dithering and bb.ditherblitFrom
            local night = Screen.night_mode
            local CX, CY = ox + cx, oy + cy
            local bwid, bhei = bb:getWidth(), bb:getHeight()
            for x = 0, Wt - 1 do
                local ya, yb
                for y = 0, hh - 1 do
                    local x0 = rowx[y]
                    if x >= x0 and x < x0 + ww then
                        ya = ya or y
                        yb = y
                    end
                end
                if ya then
                    local u = x + 0.5 - Wt / 2
                    local X = floor(CX + u)
                    local Y = floor(CY + (ya - hh / 2) + sn * u + 0.5)
                    local skip = Y < 0 and -Y or 0
                    local n = min(yb - ya + 1 - skip, bhei - (Y + skip))
                    if X >= 0 and X < bwid and n > 0 then
                        if dither then
                            bb:ditherblitFrom(tmp, X, Y + skip, x, ya + skip, 1, n)
                        else
                            bb:blitFrom(tmp, X, Y + skip, x, ya + skip, 1, n)
                        end
                        -- keep the cover's real colours when the screen is inverted
                        if night then bb:invertRect(X, Y + skip, 1, n) end
                    end
                end
            end
            tmp:free()
        end)
    end

    -- A picture file (PNG, JPEG or SVG) fitted inside w x h, centred, keeping
    -- its shape and its transparency. o.tint: painted in that one colour
    -- instead (an icon). Returns false when it can't be read.
    function C:image(path, x, y, w, h, o)
        x, y, w, h = floor(x), floor(y), floor(w), floor(h)
        local tint = o and o.tint
        local src, straight = A.picture(path, w, h)
        if not src then return false end
        local mask = tint and A.pictureMask(path, w, h) or nil
        if tint and not mask then tint = nil end
        local sw, sh = src:getWidth(), src:getHeight()
        local ix, iy = x + floor((w - sw) / 2), y + floor((h - sh) / 2)
        if tint then
            local col = self:col(tint)
            self:mark("im", path, ix, iy, tostring(mask), tint, self.inv)
            self:op(function(bb, ox, oy)
                local BB = require("ffi/blitbuffer")
                if bb:getType() == BB.TYPE_BBRGB32 and bbMethod(bb, "colorblitFromRGB32") then
                    bb:colorblitFromRGB32(mask, ox + ix, oy + iy, 0, 0, sw, sh, col)
                else
                    bb:colorblitFrom(mask, ox + ix, oy + iy, 0, 0, sw, sh, col)
                end
            end)
            return true
        end
        self:mark("i", path, ix, iy, tostring(src))
        self:op(function(bb, ox, oy)
            local Screen = A.screen()
            local X, Y = ox + ix, oy + iy
            -- in night mode the screen is inverted after painting: blend the
            -- picture in true colours (like the covers keep theirs)
            local night = Screen.night_mode
            if night then bb:invertRect(X, Y, sw, sh) end
            if straight then
                -- an SVG: straight alpha
                if Screen.sw_dithering and bbMethod(bb, "ditheralphablitFrom") then
                    bb:ditheralphablitFrom(src, X, Y, 0, 0, sw, sh)
                else
                    bb:alphablitFrom(src, X, Y, 0, 0, sw, sh)
                end
            elseif Screen.sw_dithering and bbMethod(bb, "ditherpmulalphablitFrom") then
                bb:ditherpmulalphablitFrom(src, X, Y, 0, 0, sw, sh)
            elseif bbMethod(bb, "pmulalphablitFrom") then
                bb:pmulalphablitFrom(src, X, Y, 0, 0, sw, sh)
            else
                bb:blitFrom(src, X, Y, 0, 0, sw, sh)
            end
            if night then bb:invertRect(X, Y, sw, sh) end
        end)
        return true
    end

    function C:region(id, x, y, w, h, pad)
        pad = pad or 0
        self.regions[#self.regions + 1] = {
            id = id, x = floor(x - pad), y = floor(y - pad), w = floor(w + 2 * pad), h = floor(h + 2 * pad),
        }
    end

    -- Nest another canvas at (x, y). Its tap regions come along, prefixed.
    function C:sub(child, x, y, prefix)
        x, y = floor(x), floor(y)
        self.owned[#self.owned + 1] = child
        self:mark("S", x, y)
        self.sig[#self.sig + 1] = child
        self:op(function(bb, ox, oy) child:paintTo(bb, ox + x, oy + y, true) end)
        for _, r in ipairs(child.regions) do
            self.regions[#self.regions + 1] = {
                id = (prefix or "") .. r.id, x = r.x + x, y = r.y + y, w = r.w, h = r.h,
            }
        end
    end

    function C:paintTo(bb, x, y, nested)
        local w, h = self.w, self.h
        self.dimen = Geom:new{ x = x, y = y, w = w, h = h }
        if not nested then A.colorMode(true) end
        local px, py, pw, ph = x, y, w, h
        -- `bleed`: let the panel run to the edges of an offscreen buffer it is
        -- centred in with a small inset: Bookshelf's top panel and full-screen
        -- view paint modules that way (bookshelf.lua sets it). Simple UI does not.
        if self.bleed and not nested then
            local Screen = A.screen()
            local bw, bh = bb:getWidth(), bb:getHeight()
            local slack = Screen:scaleBySize(48)
            if (bw < Screen:getWidth() or bh < Screen:getHeight())
                    and bw - w >= 0 and bh - h >= 0 and bw - w <= slack and bh - h <= slack
                    and x == floor((bw - w) / 2) and y == floor((bh - h) / 2) then
                px, py, pw, ph = 0, 0, bw, bh
            end
        end
        if self.cache_me and pcUsable(bb, px, py, pw, ph) and not PC.spills[self:sigKey()] then
            return self:paintKept(bb, x, y, px, py, pw, ph)
        end
        self:draw(bb, x, y, px, py, pw, ph)
    end

    -- The card's background and drawing steps, the card at (x, y), its
    -- background filling (px, py, pw, ph).
    function C:draw(bb, x, y, px, py, pw, ph)
        if self.fill then G.rect(bb, px, py, pw, ph, self.fill, false) end
        local tone = self.tone
        if tone and not self.plain then
            local r = tone.square and 0 or (self.radius or 0)
            -- `behind`: the card sits on a picture; its corners blend with it
            local under = self.behind and BEHIND or self.under
            local CY = tone.cut and A.cyber()
            if CY then
                CY.frame(bb, px, py, pw, ph, r, self.border_w or 0, tone, under, self.inv)
            elseif tone.border and (self.border_w or 0) > 0 then
                G.frame(bb, px, py, pw, ph, r, self.border_w, tone.border, tone.bg, under, self.inv)
                if tone.ruled then
                    -- a thin brass rule a little inside the frame
                    local inset = self.border_w * 3 + 1
                    local lw = 1
                    local rc = A.color(A.ACCENTS.brass.deep, self.inv)
                    local x0, y0, x1, y1 = px + inset, py + inset, px + pw - inset, py + ph - inset
                    A.fillRect(bb, x0, y0, x1 - x0, lw, rc)
                    A.fillRect(bb, x0, y1 - lw, x1 - x0, lw, rc)
                    A.fillRect(bb, x0, y0, lw, y1 - y0, rc)
                    A.fillRect(bb, x1 - lw, y0, lw, y1 - y0, rc)
                end
            else
                G.rrect(bb, px, py, pw, ph, r, tone.bg, under, self.inv)
            end
        end
        for i = 1, #self.ops do self.ops[i](bb, x, y) end
    end

    -- Paint through the paint cache: copy a kept picture back, or draw over
    -- a copy of what is underneath, keep that, and put it on screen.
    function C:paintKept(bb, x, y, px, py, pw, ph)
        local Screen = A.screen()
        local key = table.concat({ self:sigKey(), pw, ph, x - px, y - py, tostring(bb:getType()),
            Screen.night_mode and "n" or "", Screen.sw_dithering and "d" or "", A.colorMode() and "c" or "" }, "\3")
        local samples = pcSamples(bb, px, py, pw, ph)
        local e = PC.map[key]
        if e and e.samples == samples then
            bb:blitFrom(e.bb, px, py, 0, 0, pw, ph)
            PC.tick = PC.tick + 1
            e.used, e.at = PC.tick, os.time()
            PC.hits = PC.hits + 1
            return
        end
        PC.misses = PC.misses + 1
        if e then
            pcall(e.bb.free, e.bb)
            PC.map[key] = nil
            PC.n, PC.bytes = PC.n - 1, PC.bytes - e.bytes
        end
        -- draw over a copy of what is underneath, with a margin round the card
        local bw, bh = bb:getWidth(), bb:getHeight()
        local ex, ey = max(0, px - SPILL), max(0, py - SPILL)
        local ew, eh = min(bw, px + pw + SPILL) - ex, min(bh, py + ph + SPILL) - ey
        local BB = BBmod()
        local ok, off = pcall(BB.new, ew, eh, bb:getType())
        if not ok or not off then return self:draw(bb, x, y, px, py, pw, ph) end
        off:blitFrom(bb, 0, 0, ex, ey, ew, eh)
        self:draw(off, x - ex, y - ey, px - ex, py - ey, pw, ph)
        local bpp = bb:getBpp() / 8
        local ix, iy = px - ex, py - ey
        local spilled = rowsDiffer(off, 0, 0, bb, ex, ey, ew, iy, bpp)                         -- above
            or rowsDiffer(off, 0, iy + ph, bb, ex, py + ph, ew, eh - iy - ph, bpp)            -- below
            or rowsDiffer(off, 0, iy, bb, ex, py, ix, ph, bpp)                                -- left
            or rowsDiffer(off, ix + pw, iy, bb, px + pw, py, ew - ix - pw, ph, bpp)           -- right
        if spilled then
            -- exactly what drawing straight onto bb gives; and from now on, that
            bb:blitFrom(off, ex, ey, 0, 0, ew, eh)
            off:free()
            if PC.spill_n > 256 then PC.spills, PC.spill_n = {}, 0 end
            PC.spills[self:sigKey()] = true
            PC.spill_n = PC.spill_n + 1
            return
        end
        bb:blitFrom(off, px, py, ix, iy, pw, ph)
        local ok2, keep = pcall(BB.new, pw, ph, bb:getType())
        if ok2 and keep then
            keep:blitFrom(off, 0, 0, ix, iy, pw, ph)
            pcPut(key, keep, samples, pcBudget(bb))
        end
        off:free()
    end

    function C:free()
        for _, wdg in ipairs(self.owned) do
            if wdg.free then pcall(wdg.free, wdg) end
        end
        self.owned, self.ops = {}, {}
    end

    _Canvas = C
    return C
end

--- A.canvas{ w=, h=, tone="ink"|table|nil, radius=, border_w=, bleed=bool, plain=bool }
-- Pictures for buttons, read once and kept scaled per size. Like the cover
-- cache this only drops its references, never frees a bitmap a card on
-- screen may still be drawing.
local _pics, _pic_order, _pic_miss = {}, {}, {}
function A.picture(path, w, h)
    if type(path) ~= "string" or path == "" or w < 4 or h < 4 then return nil end
    local ok_l, lfs = pcall(require, "libs/libkoreader-lfs")
    local mtime = ok_l and lfs and lfs.attributes(path, "modification")
    if not mtime then return nil end
    local key = path .. "\0" .. w .. "x" .. h .. "@" .. mtime
    local rec = _pics[key]
    if rec then return rec.bb, rec.straight, rec end
    if _pic_miss[key] then return nil end
    local straight = false
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        -- an SVG (KOReader's own icons are): drawn at the size wanted. It
        -- comes with straight alpha, the other pictures premultiplied.
        if path:lower():match("%.svg$") then
            local svg, is_straight = RenderImage:renderSVGImageFile(path, w, h)
            straight = is_straight and true or false
            return svg
        end
        local src = RenderImage:renderImageFile(path, false)
        if not src then return nil end
        local sw, sh = src:getWidth(), src:getHeight()
        local k = math.min(w / sw, h / sh)
        local tw, th = math.max(1, floor(sw * k + 0.5)), math.max(1, floor(sh * k + 0.5))
        if tw == sw and th == sh then return src end
        return RenderImage:scaleBlitBuffer(src, tw, th, true)
    end)
    if not ok or not bb then
        _pic_miss[key] = true
        A.log("picture", path, ok and "could not be read" or bb)
        return nil
    end
    rec = { bb = bb, straight = straight }
    _pics[key] = rec
    _pic_order[#_pic_order + 1] = key
    while #_pic_order > 24 do _pics[table.remove(_pic_order, 1)] = nil end
    return bb, straight, rec
end

-- A picture as a mask (its ink, from its transparency, or from how dark it
-- is when it has none), to paint in one colour: KOReader's icons, which are
-- black, take the colour of the button they're on. Worked out once.
function A.pictureMask(path, w, h)
    local bb, _, rec = A.picture(path, w, h)
    if not bb then return nil end
    if rec.mask then return rec.mask end
    local BB = require("ffi/blitbuffer")
    local ok, mask = pcall(function()
        local mw, mh = bb:getWidth(), bb:getHeight()
        local m = BB.new(mw, mh, BB.TYPE_BB8)
        local t = bb:getType()
        local has_alpha = (t == BB.TYPE_BBRGB32 or t == BB.TYPE_BB8A)
        for yy = 0, mh - 1 do
            for xx = 0, mw - 1 do
                local px = bb:getPixel(xx, yy)
                local a = has_alpha and px.alpha or (255 - px:getColor8().a)
                if a > 0 then m:setPixel(xx, yy, BB.Color8(a)) end
            end
        end
        return m
    end)
    if not ok then A.log("picture mask", path, mask) return nil end
    rec.mask = mask
    return mask
end

function A.canvas(o)
    local tone = o.tone
    if type(tone) == "string" then tone = A.tone(tone) end
    return canvasClass():new{
        w = max(1, floor(o.w)), h = max(1, floor(o.h)), tone = tone,
        radius = o.radius, border_w = o.border_w, bleed = o.bleed, plain = o.plain, page = o.page,
        fill = o.fill, behind = o.behind,
    }
end

-- ─── formatting helpers ──────────────────────────────────────────────────────

function A.fmtMinutes(mins)
    mins = max(0, floor((tonumber(mins) or 0) + 0.5))
    local h, m = floor(mins / 60), mins % 60
    local mu = A.i18n.minute_unit
    if h > 0 and m > 0 then return string.format("%d h %d %s", h, m, mu) end
    if h > 0 then return string.format("%d h", h) end
    return string.format("%d %s", m, mu)
end

-- 14894 -> "14,894"
function A.thousands(n)
    local str = tostring(floor((tonumber(n) or 0) + 0.5))
    local sign, digits = str:match("^(-?)(%d+)$")
    if not digits then return str end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    digits = digits:gsub(",", function() return A.i18n.thousands_separator end)
    return sign .. digits
end

function A.plural(n, one, many)
    return string.format("%d %s", n, A.i18n.ngettext(one, many, n))
end

-- Day/month names in the interface language: Reading Log's own catalogs
-- (i18n.lua), else KOReader's translations of os.date's English names.
function A.date(fmt, t) return A.i18n.date(fmt, t) end

function A.decimal(n)
    return (string.format("%.1f", n):gsub("%.", A.i18n.decimal_separator))
end

-- Days since the epoch for a local calendar date, anchored at noon so a DST
-- shift cannot move the boundary.
function A.dayNumber(y, m, d)
    return floor(os.time{ year = y, month = m, day = d, hour = 12 } / 86400)
end

function A.parseYmd(s)
    if type(s) ~= "string" then return nil end
    local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not y then return nil end
    return tonumber(y), tonumber(m), tonumber(d)
end

function A.todayYmd()
    local t = os.date("*t")
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day), t
end

-- ─── load the other parts ────────────────────────────────────────────────────

local function part(name)
    local chunk, err = loadfile(A.dir .. "/" .. name .. ".lua")
    if not chunk then error("almanac: cannot load " .. name .. ".lua: " .. tostring(err)) end
    return chunk(A)
end

part(HOST_KIND == "bookshelf" and "host_bookshelf" or "host")
-- English day and month names from KOReader's own translations (see i18n.lua)
A.i18n.localize = A.host.localizeDate
part("data")
part("panels")
-- the ornaments (no card): Books this year, Streak flame, Letter board,
-- Today's pages
part("ornaments")
part("settings")
part(HOST_KIND == "bookshelf" and "bookshelf" or "modules")

-- The Cyber look's drawing lives in cyber.lua, read the first time a card
-- asks for it: a Dashboard that never uses Cyber never loads it.
local _academia
function A.academia()
    if _academia == nil then
        local ok, r = pcall(part, "academia")
        _academia = (ok and type(r) == "table") and r or false
        if not _academia then A.log("dark academia look could not be loaded:", r) end
    end
    return _academia or nil
end

local _cyber
function A.cyber()
    if _cyber == nil then
        local ok, r = pcall(part, "cyber")
        _cyber = (ok and type(r) == "table") and r or false
        if not _cyber then A.log("cyber look could not be loaded:", r) end
    end
    return _cyber or nil
end
-- The reader panel (readerpanel.lua): read the first time the reader's
-- menu opens with it switched on.
local _rpanel
function A.readerPanel()
    if _rpanel == nil then
        local ok, r = pcall(part, "readerpanel")
        _rpanel = (ok and type(r) == "table") and r or false
        if not _rpanel then A.log("reader panel could not be loaded:", r) end
    end
    return _rpanel or nil
end

if HOST_KIND ~= "bookshelf" then part("menus") end

A.note(A.NAME .. " for " .. A.HOST, A.VERSION, "loaded from", A.dir)

return A
