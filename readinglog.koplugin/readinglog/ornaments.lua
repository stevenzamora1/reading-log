--[[
Reading Log's ornaments: cards with no card, drawn straight onto the
wallpaper or standing among the books on Bookshelf's shelf, like Bookshelf's
own ornaments. Each is an object with a body of its own, so it reads on any
wallpaper, and each has a look for every style:

                   Default          Cute             Cyber          Dark Academia
  Books this year  books, figures   heart sticker    glitch         brass plaque
                   standing on top                   billboard
  Streak flame     a flame          heart on fire    neon flame     a candle
  Letter board     felt board       light box        LED marquee    chalkboard
  Today's pages    a till receipt   sticky note      heart monitor  library card
  Pages turned     flip counter     pink banner      data counter   open book

At the end, Lifetime pages: the Pages turned figure as an ordinary card,
for the Dashboard (it shares the Cyber pieces).

On the shelf they stand on the plank; elsewhere they sit in the middle of
their space. Cheap to draw: a handful of shapes and texts each, and the
letter board measures its words once, not once per size it tries.

They show what the figures say when drawn, and the home screen draws them
when it comes back from a book (today's figures take in what the open book
hasn't saved yet, see D.stats). On Bookshelf's top panel they also check
once a minute (poll) and redraw only when a figure they show has changed:
after midnight, or when a book closes and its reading lands in the database.
]]

local A = ...
local T = A._
local D = A.D
local P = A.panels

local floor, max, min = math.floor, math.max, math.min
local scaler, card, minFont = A.panelScaler, A.panelCard, A.minFont
local cyLook, acLook = A.cyLook, A.acLook

-- ─── shared ──────────────────────────────────────────────────────────────────

-- The biggest size (down from `size`) at which str fits max_w (and max_h).
local function fitText(c, str, size, max_w, o, max_h)
    local t = c:text(str, size, o)
    while (t.w > max_w or (max_h and t.h > max_h)) and size > minFont() do
        size = max(minFont(), floor(size * 0.9))
        t = c:text(str, size, o)
    end
    return t
end

-- Text with an outline (drawn round it first), for figures on any wallpaper.
local function outlined(c, str, size, x, y, fill, edge, o, anchor)
    o = o or {}
    local base = {}
    for k, v in pairs(o) do base[k] = v end
    base.color = edge
    local t_e = c:text(str, size, base)
    local d = max(1, floor(size * 0.03))
    for _, off in ipairs({ { -d, 0 }, { d, 0 }, { 0, -d }, { 0, d }, { d, d } }) do
        c:put(t_e, x + off[1], y + off[2], anchor or "c")
    end
    base.color = fill
    local t = c:text(str, size, base)
    c:put(t, x, y, anchor or "c")
    return t
end

-- A five-pointed star, r its outer radius.
local function star(c, cx, cy, r, col)
    local parts = {}
    local pt = {}
    for k = 0, 9 do
        local a = -math.pi / 2 + k * math.pi / 5
        local rr = (k % 2 == 0) and 0.5 or 0.2
        pt[k] = { rr * math.cos(a), rr * math.sin(a) }
    end
    for k = 0, 9 do
        local p1, p2 = pt[k], pt[(k + 1) % 10]
        parts[#parts + 1] = { "t", 0, 0, p1[1], p1[2], p2[1], p2[2], col, col }
    end
    c:sprite(cx, cy, 2 * r, 0, parts, { lw = 1 })
end

-- The object's box: w/h = aspect, as big as fits under a title of title_h;
-- standing at the bottom on the shelf, in the middle elsewhere.
local function objectBox(env, aspect, title_h, m)
    local w, h = env.w, env.h
    local avail_h = h - 2 * m - title_h
    local ow = min(w - 2 * m, floor(avail_h * aspect))
    local oh = min(avail_h, floor(ow / aspect))
    local block = title_h + oh
    local surface = env.ctx and env.ctx.surface
    local by = (surface == "shelf") and (h - m - block) or floor((h - block) / 2)
    return floor((w - ow) / 2), by + title_h, ow, oh, by
end

-- Which of an ornament's looks: the Cyber and Dark Academia ones come with
-- their drawing kits.
local function lookOf(key, cyber, academia, cute, plain)
    local CY = cyLook(key, cyber)
    if CY then return cyber, CY end
    local AC = acLook(key, academia)
    if AC then return academia, AC end
    if A.get(key, plain) == cute then return cute end
    return plain
end

local function plural(n, one, many) return A.plural(n, one, many) end
local function wordOf(n, one, many) return (A.plural(n or 0, one, many):gsub("^[%d,%. ]+", "")) end

-- ─── the Cyber looks' pieces ─────────────────────────────────────────────────

local CY_BLACK, CY_PANEL = { 6, 8, 10 }, { 12, 14, 20 }
local CY_YEL, CY_CYAN, CY_RED = { 243, 230, 0 }, { 0, 229, 255 }, { 255, 40, 70 }
local CY_DIM, CY_WHITE = { 36, 42, 52 }, { 236, 240, 244 }

local function withColor(o, col)
    local r = {}
    for k, v in pairs(o or {}) do r[k] = v end
    r.color = col
    return r
end

-- Neon tube text: the colour round a pale core.
local function neon(c, str, size, x, y, col, o, anchor, valign)
    local glow = c:text(str, size, withColor(o, col))
    local core = c:text(str, size, withColor(o, A.mix(col, { 255, 255, 255 }, 0.6)))
    local d = max(1, floor(size * 0.035))
    for _, q in ipairs({ { -d, 0 }, { d, 0 }, { 0, -d }, { 0, d }, { -d, -d }, { d, d }, { -d, d }, { d, -d } }) do
        c:put(glow, x + q[1], y + q[2], anchor, valign)
    end
    c:put(core, x, y, anchor, valign)
    return core
end

-- Colour split: a cyan copy right, a magenta one left, the text over them.
local function split(c, str, size, x, y, col, o, anchor, valign, shift)
    local MAG = A.cyber().MAGENTA
    shift = shift or max(1, floor(size * 0.045))
    c:put(c:text(str, size, withColor(o, CY_CYAN)), x + shift, y, anchor, valign)
    c:put(c:text(str, size, withColor(o, MAG)), x - shift, y, anchor, valign)
    local t = c:text(str, size, withColor(o, col))
    c:put(t, x, y, anchor, valign)
    return t
end

local function scanlines(c, x, y, w, h, col, step)
    for yy = y, y + h - 1, step do c:rect(x, yy, w, 1, col) end
end

-- A barcode, the same for the same seed.
local function barcode(c, x, y, w, h, col, seed)
    local xx = x
    seed = seed or 7
    while xx < x + w - 2 do
        seed = (seed * 1103515245 + 12345) % 2147483648
        local bw = 1 + (seed % 3)
        c:rect(xx, y, bw, h, col)
        xx = xx + bw + 1 + (floor(seed / 7) % 2)
    end
end

-- A flame as a neon tube: an outline of colour round a dark middle, and a
-- small inner tube of another colour.
local function neonFlame(c, cx, cy, S, col, inner, bg)
    c:sprite(cx, cy, S, 0, {
        { "e", 0, 0.18, 0.34, 0.34, 0, col, col },
        { "t", -0.298, 0.017, 0.317, 0.055, 0.05, -0.62, col, col },
        { "e", 0, 0.2, 0.28, 0.28, 0, bg, bg },
        { "t", -0.245, 0.06, 0.262, 0.09, 0.045, -0.47, bg, bg },
        { "e", 0, 0.3, 0.17, 0.17, 0, inner, inner },
        { "t", -0.15, 0.2, 0.16, 0.22, 0.03, -0.12, inner, inner },
        { "e", 0, 0.31, 0.11, 0.11, 0, bg, bg },
        { "t", -0.095, 0.24, 0.1, 0.25, 0.02, 0.03, bg, bg },
    }, { lw = 1 })
end

-- ════════════════════════════════════════════════════════════════════════════
-- Books this year
-- ════════════════════════════════════════════════════════════════════════════

P.books_year = {
    does = T("nothing"),
    title = T("Books this year"), tone = "ink", ratio = 0.8, ratio_narrow = 0.8, bare = true,
    start_w = 1, start_h = 1,
    summary = T("How many books you've finished this year, as an ornament with no card. Works offline."),
    poll = function()
        local yr = D.year()
        local _, other = D.yearGoal()
        return tostring(yr and yr.total) .. "+" .. tostring(other)
    end,
}

local ROMAN = { { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" },
    { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local function roman(n)
    local out = {}
    for _, p in ipairs(ROMAN) do
        while n >= p[1] do out[#out + 1] = p[2]; n = n - p[1] end
    end
    return table.concat(out)
end

-- dark cloth bindings, a gilt band each
local BINDINGS = { { 44, 56, 82 }, { 58, 82, 62 }, { 108, 44, 46 }, { 82, 62, 44 }, { 52, 50, 60 } }
local GILT = { 196, 162, 92 }
local PAGES = { 236, 228, 210 }
local IVORY = { 246, 240, 226 }
local DARK = { 34, 28, 24 }

function P.books_year.build(env)
    env.bare = true
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 300, h / 300)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local yr = A.yearFor(env)
    local _, other = D.yearGoal()
    if env.sample then other = 0 end
    local count = yr and ((yr.total or 0) + other) or nil
    local num = count and tostring(count) or "\xE2\x80\xA6"
    local year = tostring(os.date("*t").year)
    local title = env.cfg("title", "")
    if type(title) ~= "string" then title = "" end
    local look, kit = lookOf("books_year_look", "neon", "plaque", "heart", "stack")

    local m = max(2, px(6))
    local title_h, t_title = 0, nil
    if title ~= "" then
        local o = { bold = look ~= "plaque", serif = look == "plaque", caps = look == "neon" or nil, mono = look == "neon" or nil }
        t_title = fitText(c, title, fpx(22), w - 2 * m - px(24), o)
        title_h = t_title.h + px(14) + px(6)
    end
    local aspect = (look == "plaque" and 1.45) or (look == "neon" and 1.1) or (look == "stack" and 0.95) or 1.1
    local ox, oy, ow, oh, by = objectBox(env, aspect, title_h, m)
    if ow < 20 or oh < 20 then return c end

    -- the title's tag, above the object
    if t_title then
        local tw, th = t_title.w + px(24), t_title.h + px(14)
        local tx, ty = floor((w - tw) / 2), by
        if look == "neon" then
            kit.cutRect(c, tx, ty, tw, th, th * 0.35, tone.accent)
            local tt = fitText(c, title, t_title.px, tw - px(24), { bold = true, caps = true, mono = true, color = { 0, 0, 0 } })
            c:put(tt, tx + tw / 2, ty + th / 2, "c", "mid")
        elseif look == "plaque" then
            c:rrect(tx, ty, tw, th, px(4), kit.GOLD_DARK)
            c:rrect(tx + 1, ty + 1, tw - 2, th - 2, px(4), kit.GOLD)
            local tt = fitText(c, title, t_title.px, tw - px(24), { serif = true, color = kit.FRAME_DARK })
            c:put(tt, tx + tw / 2, ty + th / 2, "c", "mid")
        elseif look == "heart" then
            c:rrect(tx - px(3), ty - px(3), tw + px(6), th + px(6), (th + px(6)) / 2, { 255, 255, 255 })
            c:rrect(tx, ty, tw, th, th / 2, { 250, 212, 228 })
            local tt = fitText(c, title, t_title.px, tw - px(24), { bold = true, color = { 176, 36, 98 } })
            c:put(tt, tx + tw / 2, ty + th / 2, "c", "mid")
        else
            -- a small dark label with gilt letters, like a spine's
            c:rrect(tx, ty, tw, th, px(4), BINDINGS[1])
            c:frame(tx + max(1, px(3)), ty + max(1, px(3)), tw - 2 * max(1, px(3)), th - 2 * max(1, px(3)), px(2), 1, GILT, BINDINGS[1])
            local tt = fitText(c, title, t_title.px, tw - px(24), { bold = true, color = GILT })
            c:put(tt, tx + tw / 2, ty + th / 2, "c", "mid")
        end
    end

    if look == "heart" then
        local fill, line = A.cozyHeart({ dark = false })
        local hw = min(ow, oh * 1.08)
        local cx, cy = ox + ow / 2, oy + oh / 2
        local edge = max(3, floor(hw * 0.05))
        c:heart(cx, cy + edge * 0.3, hw, hw * 0.92, { outer = 1, line = { 255, 255, 255 }, fill = { 255, 255, 255 },
            track = { 255, 255, 255 }, t = 1 })
        c:heart(cx, cy, hw - 2 * edge, (hw - 2 * edge) * 0.92, { outer = 1, line = line, fill = fill, track = fill,
            t = max(2, floor(hw * 0.03)) })
        local inner = (hw - 2 * edge) * 0.58
        local room_h = (hw - 2 * edge) * 0.92 * 0.74
        local t_n = fitText(c, num, fpx(96), inner, { bold = true, color = { 255, 255, 255 } })
        local t_b = fitText(c, wordOf(count, "book", "books"), fpx(24), inner, { bold = true, color = { 255, 240, 246 } })
        local t_y = fitText(c, year, fpx(18), inner * 0.8, { bold = true, color = { 255, 226, 238 } })
        if t_n.h * 0.92 + t_b.h * 0.9 + t_y.h > room_h then t_y = nil end
        local blk = t_n.h * 0.92 + t_b.h * (t_y and 0.9 or 1) + (t_y and t_y.h or 0)
        local yy = cy - hw * 0.1 - blk / 2
        c:put(t_n, cx, yy, "c"); yy = yy + t_n.h * 0.92
        c:put(t_b, cx, yy, "c"); yy = yy + t_b.h * 0.9
        if t_y then c:put(t_y, cx, yy, "c") end
        local sp = { 255, 206, 84 }
        c:sprite(cx + hw * 0.47, cy - hw * 0.4, hw * 0.16, 0, { { "*", 0, 0, 0.5, sp } }, { halo = max(1, px(2)), halo_col = { 255, 255, 255 } })
        c:sprite(cx - hw * 0.5, cy + hw * 0.18, hw * 0.1, 0, { { "*", 0, 0, 0.5, sp } }, { halo = max(1, px(2)), halo_col = { 255, 255, 255 } })
    elseif look == "neon" then
        -- a glitch billboard: the count huge, split and sliced on a black
        -- screen with scanlines, 本 ("book") glowing behind, a tag, a barcode
        local CY = kit
        local MAG = CY.MAGENTA
        CY.cutRect(c, ox, oy, ow, oh, floor(min(ow, oh) * 0.1), CY_BLACK)
        local ip = max(4, floor(min(ow, oh) * 0.04))
        local ix, iy, iw, ih = ox + ip, oy + ip, ow - 2 * ip, oh - 2 * ip
        local t_k = fitText(c, "\xE6\x9C\xAC", fpx(80), iw * 0.4, { color = A.mix(CY_BLACK, MAG, 0.45) }, ih * 0.5)
        c:put(t_k, ix + iw - px(4), iy + px(2), "r")
        scanlines(c, ox, oy, ow, oh - floor(min(ow, oh) * 0.1), { 20, 22, 30 }, max(3, px(4)))
        local tag_w, tag_h = CY.chip(c, "BOOKS//" .. year, fpx(14), ix + px(4), iy + px(4), CY_YEL, CY_BLACK, { mono = true })
        local bar_h = max(6, px(12))
        local room = ih - tag_h - bar_h - px(18)
        local t_n = fitText(c, num, fpx(130), iw * 0.78, { mono = true, bold = true }, room)
        local nx, ny = ix + px(8), iy + tag_h + px(8) + floor((room - t_n.h) / 2)
        split(c, num, t_n.px, nx, ny, CY_WHITE, { mono = true, bold = true }, nil, nil, max(2, floor(t_n.px * 0.06)))
        -- glitch slices across the figures
        c:rect(nx - px(8), ny + floor(t_n.h * 0.36), floor(t_n.w * 0.45), max(1, px(2)), CY_CYAN)
        c:rect(nx + floor(t_n.w * 0.55), ny + floor(t_n.h * 0.58), floor(t_n.w * 0.6), max(1, px(2)), MAG)
        c:rect(nx + floor(t_n.w * 0.2), ny + floor(t_n.h * 0.74), floor(t_n.w * 0.2), max(1, px(2)), CY_YEL)
        barcode(c, ix + px(6), iy + ih - bar_h - px(2), floor(iw * 0.36), bar_h, CY_WHITE, count or 7)
        local t_lv = c:text("LV." .. num, fpx(14), { mono = true, bold = true, color = CY_YEL })
        c:put(t_lv, ix + iw - px(14), iy + ih - px(2) - t_lv.h, "r")
    elseif look == "plaque" then
        local AC = kit
        local r = max(3, floor(min(ow, oh) * 0.06))
        c:rrect(ox, oy, ow, oh, r, AC.GOLD_DARK)
        c:rrect(ox + max(2, px(4)), oy + max(2, px(4)), ow - 2 * max(2, px(4)), oh - 2 * max(2, px(4)), r, AC.GOLD)
        local b = max(4, floor(min(ow, oh) * 0.09))
        c:frame(ox + b, oy + b, ow - 2 * b, oh - 2 * b, max(2, r - 2), max(1, px(2)), AC.GOLD_LIGHT, AC.GOLD)
        local sr = max(2, floor(min(ow, oh) * 0.035))
        for _, p in ipairs({ { ox + b / 2 + 1, oy + b / 2 + 1 }, { ox + ow - b / 2 - 1, oy + b / 2 + 1 },
                { ox + b / 2 + 1, oy + oh - b / 2 - 1 }, { ox + ow - b / 2 - 1, oy + oh - b / 2 - 1 } }) do
            c:disc(p[1], p[2], sr, AC.GOLD_LIGHT)
            c:disc(p[1], p[2], max(1, sr - 1), AC.SAND)
            c:rect(floor(p[1] - sr * 0.7), floor(p[2]), max(2, floor(sr * 1.4)), 1, AC.GOLD_DARK)
        end
        local iw = ow - 2 * b - px(24)
        local ih = oh - 2 * b - px(10)
        local ink, shine = AC.FRAME_DARK, AC.GOLD_LIGHT
        local t_n = fitText(c, num, fpx(96), iw, { serif = true, bold = true, color = ink }, ih * 0.74)
        local t_n2 = c:text(num, t_n.px, { serif = true, bold = true, color = shine })
        local words = A.upper(T("volumes read")) .. " \xC2\xB7 " .. roman(tonumber(year) or 2026)
        local t_w = fitText(c, words, fpx(18), iw * 0.94, { serif = true, color = ink })
        if t_w.w > iw * 0.94 then
            words = roman(tonumber(year) or 2026)
            t_w = fitText(c, words, fpx(18), iw * 0.94, { serif = true, color = ink })
        end
        local t_w2 = c:text(words, t_w.px, { serif = true, color = shine })
        local orn = max(6, floor(t_w.h * 0.6))
        local with_orn = t_n.h + t_w.h + orn + px(4) <= ih
        local blk = t_n.h + t_w.h + (with_orn and (orn + px(4)) or 0)
        local yy = oy + floor((oh - blk) / 2)
        c:put(t_n2, ox + ow / 2, yy + 1, "c")
        c:put(t_n, ox + ow / 2, yy, "c")
        c:put(t_w2, ox + ow / 2, yy + t_n.h + 1, "c")
        c:put(t_w, ox + ow / 2, yy + t_n.h, "c")
        if with_orn then AC.ornament(c, ox + ow / 2, yy + t_n.h + t_w.h + px(4) + orn / 2, orn, AC.GOLD_DARK) end
    else
        -- a stack of books in dark cloth, gilt bands, and the year's figures
        -- standing on top of it in ivory
        local n = 4
        local stack_h = floor(oh * 0.5)
        local bh = floor(stack_h / n)
        local sw = floor(ow * 0.86)
        local sx = ox + floor((ow - sw) / 2)
        local base = oy + oh
        local widths = { 1, 0.92, 0.97, 0.88 }
        local shifts = { 0, 0.05, 0.015, 0.07 }
        local top_y, top
        for i = 1, n do
            local bw_ = floor(sw * widths[i])
            local bx = sx + floor(sw * shifts[i])
            local y0 = base - i * bh
            local col = BINDINGS[(i - 1) % #BINDINGS + 1]
            local edge = A.mix(col, { 0, 0, 0 }, 0.4)
            local r = max(1, floor(bh * 0.12))
            c:rrect(bx, y0, bw_, bh - 1, r, edge)
            c:rrect(bx + 1, y0 + 1, bw_ - 2, bh - 3, r, col)
            -- the pages along the far end, a gilt band near the spine end
            local pw = max(3, floor(bh * 0.42))
            c:rect(bx + bw_ - pw - max(2, floor(bh * 0.12)), y0 + max(2, floor(bh * 0.2)), pw,
                max(2, bh - 1 - 2 * max(2, floor(bh * 0.2))), PAGES)
            local gx = bx + max(4, floor(bw_ * 0.1))
            c:rect(gx, y0 + 1, max(1, floor(bh * 0.08)), bh - 3, GILT)
            c:rect(gx + max(2, floor(bh * 0.16)), y0 + 1, max(1, floor(bh * 0.08)), bh - 3, GILT)
            top_y, top = y0, { x = bx, w = bw_, col = col }
        end
        -- "books · 2026" in gilt on the top book
        local label = A.upper(wordOf(count, "book", "books")) .. " \xC2\xB7 " .. year
        local lx0 = top.x + max(4, floor(top.w * 0.1)) + max(4, floor(bh * 0.4))
        local lroom = top.w - (lx0 - top.x) - max(3, floor(bh * 0.42)) - max(6, floor(bh * 0.3))
        if lroom > px(30) then
            local t_l = fitText(c, label, max(minFont(), floor(bh * 0.5)), lroom, { bold = true, color = GILT })
            if t_l.w <= lroom then c:put(t_l, lx0 + lroom / 2, top_y + bh / 2, "c", "mid") end
        end
        -- the figures, standing on the top book
        local fig_h = top_y - oy
        local t_probe = fitText(c, num, fpx(130), sw * 0.8, { bold = true }, fig_h * 1.25)
        local size = t_probe.px
        local t_n = c:text(num, size, { bold = true, color = IVORY })
        local fx = top.x + top.w / 2
        local fy = top_y - t_n.base + 1
        -- a soft shadow on the book behind, then the outlined figures
        local sh = c:text(num, size, { bold = true, color = A.mix(top.col, { 0, 0, 0 }, 0.55) })
        c:put(sh, fx + max(2, floor(size * 0.05)), fy, "c")
        outlined(c, num, size, fx, fy, IVORY, DARK, { bold = true })
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Streak flame
-- ════════════════════════════════════════════════════════════════════════════

P.streak_flame = {
    does = T("nothing"),
    title = T("Streak flame"), tone = "ink", ratio = 1, ratio_narrow = 1, bare = true,
    start_w = 1, start_h = 1,
    summary = T("Your reading streak as a flame that grows the longer it runs, as an ornament with no card. Works offline."),
    poll = function()
        local st = D.stats()
        return tostring(type(st) == "table" and st.streak) .. "|" .. os.date("%Y-%m-%d")
    end,
}

local FLAME = { { 232, 92, 32 }, { 247, 158, 38 }, { 255, 226, 140 } }
local ASH = { { 150, 146, 142 }, { 186, 182, 178 }, { 222, 218, 214 } }

-- A flame: three teardrops, outer to core, size S (its height about 1.25 S).
local function flame(c, cx, cy, S, cols, lw, turn)
    local parts = {}
    -- one teardrop: a round bottom and a pointed top, k its size, dy lower
    local function drop(k, dy, col, line)
        parts[#parts + 1] = { "e", 0, 0.18 * k + dy, 0.34 * k, 0.34 * k, 0, col, line }
        -- the sides meet the round bottom where they touch it: no corner
        parts[#parts + 1] = { "t", -0.298 * k, 0.017 * k + dy, 0.317 * k, 0.055 * k + dy, 0.05 * k, -0.62 * k + dy, col, line }
    end
    drop(1, 0, cols[1], cols[1])
    drop(0.7, 0.1, cols[2], cols[2])
    drop(0.44, 0.19, cols[3], cols[3])
    c:sprite(cx, cy, S, turn or 0, parts, { lw = lw or max(1, S * 0.02) })
end

function P.streak_flame.build(env)
    env.bare = true
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 300, h / 300)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = A.statsFor(env)
    local streak = st and st.streak or nil
    local num = streak and tostring(streak) or "\xE2\x80\xA6"
    local lit = (streak or 0) > 0
    local look, kit = lookOf("streak_flame_look", "neon", "candle", "heart", "flame")
    -- the flame grows with the streak, full size at a month
    local grow = 0.72 + 0.28 * min(1, (streak or 0) / 30)
    local caption = lit and wordOf(streak, "day streak", "day streak") or T("No streak yet")

    local m = max(2, px(6))
    if look == "neon" then
        -- a neon sign hung on two wires: the flame as a pink tube with a cyan
        -- core (bigger the longer the streak), the days in a yellow tube
        local CY = kit
        local ox, oy, ow, oh = objectBox(env, 1.3, 0, m)
        local wire = floor(oh * 0.1)
        local wcol = { 90, 96, 110 }
        c:rect(ox + floor(ow * 0.25), oy, max(1, px(2)), wire, wcol)
        c:rect(ox + floor(ow * 0.75), oy, max(1, px(2)), wire, wcol)
        local py, ph = oy + wire, oh - wire
        local e = max(2, px(3))
        c:rrect(ox, py, ow, ph, px(6), { 26, 28, 36 })
        c:rrect(ox + e, py + e, ow - 2 * e, ph - 2 * e, px(5), CY_PANEL)
        local pink, cyan, yel = CY.MAGENTA, CY_CYAN, CY_YEL
        if not lit then pink, cyan, yel = { 96, 70, 90 }, { 60, 90, 100 }, { 110, 106, 70 } end
        local S = min(ow * 0.5, ph * 0.72) * (0.8 + 0.2 * grow)
        neonFlame(c, ox + ow * 0.3, py + ph / 2 + S * 0.05, S, pink, cyan, CY_PANEL)
        local tx = ox + ow * 0.72
        local cap = lit and A.upper(caption) or A.upper(T("No streak yet"))
        local t_n = fitText(c, num, fpx(90), ow * 0.38, { bold = true }, ph * 0.5)
        local t_l = fitText(c, cap, fpx(18), ow * 0.44, { bold = true, italic = true })
        local yy = py + floor((ph - t_n.h - t_l.h) / 2)
        neon(c, num, t_n.px, tx, yy, yel, { bold = true }, "c")
        neon(c, cap, t_l.px, tx, yy + t_n.h, cyan, { bold = true, italic = true }, "c")
        return c
    end
    if look == "candle" then
        -- a pillar candle in a brass chamberstick, taller the longer the
        -- streak, and an engraved plaque with the days
        local AC = kit
        local ox, oy, ow, oh = objectBox(env, 0.8, 0, m)
        local plaque_h = floor(oh * 0.24)
        local area = oh - plaque_h - px(4)
        local cx = ox + ow / 2
        local base = oy + area
        local cw = max(8, floor(min(ow * 0.26, area * 0.22)))
        local dish_h = max(4, floor(cw * 0.32))
        local dish_w = floor(cw * 2.3)
        local sock_h = max(3, floor(dish_h * 0.7))
        local fS = cw * 1.25
        local room = area - dish_h - sock_h - fS * 1.15
        local wax = max(floor(cw * 0.8), floor(room * (lit and (0.4 + 0.6 * grow) or 0.4)))
        local br, brd, brl = AC.GOLD, AC.GOLD_DARK, AC.GOLD_LIGHT
        -- the ring handle, the dish, the socket
        c:ring(cx + dish_w / 2 - dish_h * 0.2, base - dish_h * 1.1, dish_h * 0.95, max(2, dish_h * 0.32), 1, brd, brd)
        c:rrect(floor(cx - dish_w / 2), base - dish_h, dish_w, dish_h, dish_h / 2, brd)
        c:rrect(floor(cx - dish_w / 2) + 1, base - dish_h + 1, dish_w - 2, max(1, dish_h - 3), dish_h / 2, br)
        c:rect(floor(cx - dish_w / 2 + dish_h / 2), base - dish_h + 1, floor(dish_w - dish_h), 1, brl)
        local sw = floor(cw * 1.3)
        c:rrect(floor(cx - sw / 2), base - dish_h - sock_h + 1, sw, sock_h, max(1, floor(sock_h / 3)), brd)
        c:rrect(floor(cx - sw / 2) + 1, base - dish_h - sock_h + 2, sw - 2, max(1, sock_h - 2), max(1, floor(sock_h / 3)), br)
        -- the wax, a drip down its side, the wick
        local top = base - dish_h - sock_h + 2 - wax
        local wx = floor(cx - cw / 2)
        c:frame(wx, top, cw, wax, max(1, floor(cw * 0.1)), 1, AC.WAX_EDGE, AC.WAX)
        local dh = max(3, floor(min(wax * 0.4, cw * 1.1)))
        c:rrect(wx + floor(cw * 0.62), top + 1, max(2, floor(cw * 0.2)), dh, max(1, cw * 0.1), AC.WAX_EDGE)
        c:rrect(wx + floor(cw * 0.62) + 1, top + 1, max(1, floor(cw * 0.2) - 2), dh - 1, max(1, cw * 0.1), AC.WAX)
        local wick = max(2, floor(cw * 0.22))
        c:rect(floor(cx - max(1, cw * 0.05)), top - wick, max(1, floor(cw * 0.1)), wick, { 43, 33, 24 })
        if lit then
            flame(c, cx, top - wick - 0.52 * fS + fS * 0.12, fS, { { 214, 112, 36 }, { 242, 172, 64 }, { 255, 238, 176 } })
        end
        local py = oy + area + px(4)
        local pw = floor(ow * 0.86)
        local pxx = ox + floor((ow - pw) / 2)
        c:rrect(pxx, py, pw, plaque_h, px(4), brd)
        c:rrect(pxx + max(1, px(3)), py + max(1, px(3)), pw - 2 * max(1, px(3)), plaque_h - 2 * max(1, px(3)), px(3), br)
        local label = lit and (num .. " " .. caption) or T("No streak yet")
        local t_l = fitText(c, label, fpx(26), pw - px(20), { serif = true, bold = true, color = AC.FRAME_DARK }, plaque_h - px(8))
        local t_l2 = c:text(label, t_l.px, { serif = true, bold = true, color = brl })
        c:put(t_l2, pxx + pw / 2, py + plaque_h / 2 + 1, "c", "mid")
        c:put(t_l, pxx + pw / 2, py + plaque_h / 2, "c", "mid")
        return c
    end
    if look == "heart" then
        -- a heart sticker with little flames on top
        local ox, oy, ow, oh = objectBox(env, 1, 0, m)
        local fill, line = A.cozyHeart({ dark = false })
        local hw = min(ow * 0.95, oh / 1.36)
        local cx, cy = ox + ow / 2, oy + oh - hw * 0.47 - px(2)
        local edge = max(3, floor(hw * 0.05))
        local fl = lit and { { 244, 108, 150 }, { 250, 160, 120 }, { 255, 226, 150 } } or ASH
        -- a flame rising out of the heart's dip, bigger the longer the
        -- streak, with a white sticker edge like the heart's
        local S = hw * 0.5 * grow
        local fy = cy - hw * 0.3 - 0.52 * S
        c:sprite(cx, fy, S, 0, {
            { "e", 0, 0.18, 0.34, 0.34, 0, fl[1], fl[1] },
            { "t", -0.298, 0.017, 0.317, 0.055, 0.05, -0.62, fl[1], fl[1] },
        }, { lw = 1, halo = edge, halo_col = { 255, 255, 255 } })
        flame(c, cx, fy, S, fl)
        if lit then
            local sp = { 255, 206, 84 }
            c:sprite(cx + hw * 0.36, cy - hw * 0.58, hw * 0.14, 0, { { "*", 0, 0, 0.5, sp } }, { halo = max(1, px(2)), halo_col = { 255, 255, 255 } })
            c:sprite(cx - hw * 0.4, cy - hw * 0.5, hw * 0.1, 0, { { "*", 0, 0, 0.5, sp } }, { halo = max(1, px(2)), halo_col = { 255, 255, 255 } })
        end
        c:heart(cx, cy + edge * 0.3, hw, hw * 0.92, { outer = 1, line = { 255, 255, 255 }, fill = { 255, 255, 255 },
            track = { 255, 255, 255 }, t = 1 })
        c:heart(cx, cy, hw - 2 * edge, (hw - 2 * edge) * 0.92, { outer = 1, line = line, fill = lit and fill or { 214, 196, 204 },
            track = fill, t = max(2, floor(hw * 0.03)) })
        local inner = (hw - 2 * edge) * 0.55
        local t_n = fitText(c, num, fpx(80), inner, { bold = true, color = { 255, 255, 255 } }, hw * 0.34)
        local t_c = fitText(c, lit and caption or T("No streak yet"), fpx(20), inner, { bold = true, color = { 255, 240, 246 } })
        local blk = t_n.h * 0.92 + t_c.h
        local yy = cy - hw * 0.08 - blk / 2
        c:put(t_n, cx, yy, "c")
        c:put(t_c, cx, yy + t_n.h * 0.92, "c")
        return c
    end
    -- the flame, the figure in its heart, the days on a tag under it
    local ox, oy, ow, oh = objectBox(env, 0.82, 0, m)
    local tag_h = floor(oh * 0.17)
    local fh = oh - tag_h - px(6)
    local S = fh / 1.25 * grow
    local cx = ox + ow / 2
    local fy = oy + fh - S * 0.55
    flame(c, cx, fy, S, lit and FLAME or ASH)
    local t_n = fitText(c, num, fpx(90), S * 0.5, { bold = true }, S * 0.46)
    outlined(c, num, t_n.px, cx, fy + S * 0.2 - t_n.h / 2, { 255, 255, 255 }, A.mix(lit and FLAME[1] or ASH[1], { 0, 0, 0 }, 0.45),
        { bold = true })
    local label = lit and caption or T("No streak yet")
    local t_c = fitText(c, label, fpx(20), ow - px(24), { bold = true, color = IVORY }, tag_h - px(6))
    local tw = t_c.w + px(20)
    local ty = oy + oh - tag_h
    c:rrect(cx - tw / 2, ty, tw, tag_h, tag_h / 2, DARK)
    c:put(t_c, cx, ty + tag_h / 2, "c", "mid")
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Letter board: your own words
-- ════════════════════════════════════════════════════════════════════════════

P.letter_board = {
    does = T("nothing"),
    title = T("Letter board"), tone = "ink", ratio = 0.9, ratio_narrow = 0.9, bare = true,
    start_w = 1, start_h = 1,
    summary = T("A letter board with words of your own, as an ornament with no card. Works offline."),
}

local HAIR = "\xE2\x80\x8A"

-- Lines of words that fit max_w x max_h at the biggest size up to size:
-- every word is measured once at a reference size, and widths scale with
-- the size, so trying sizes costs no text drawing. Letters spaced out (a
-- letter board's) when they fit, else close together. Returns lines, size.
local function wrapFit(c, text, size, max_w, max_h, o, line_k, spaced)
    local REF = 100
    local line_h = c:text("Ag", REF, o).h
    local one_space = max(1, c:text("a a", REF, o).w - c:text("aa", REF, o).w)
    local function build(sp)
        local paras, wide = {}, {}
        for para in (text .. "\n"):gmatch("(.-)\n") do
            local words = {}
            for word in para:gmatch("%S+") do
                if sp then
                    local chars = {}
                    for ch in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
                    word = table.concat(chars, HAIR)
                end
                words[#words + 1] = word
                if not wide[word] then wide[word] = c:text(word, REF, o).w end
            end
            paras[#paras + 1] = words
        end
        return { paras = paras, wide = wide, space = one_space * (sp and 2 or 1), join = sp and "  " or " " }
    end
    local function lay(B, sz, force)
        local k = sz / REF
        local lines = {}
        for _, words in ipairs(B.paras) do
            local cur, cur_w = {}, 0
            if #words == 0 then lines[#lines + 1] = "" end
            for _, word in ipairs(words) do
                local ww = B.wide[word] * k
                if ww > max_w and not force then return nil end
                local add = (#cur > 0 and B.space * k or 0) + ww
                if #cur > 0 and cur_w + add > max_w then
                    lines[#lines + 1] = table.concat(cur, B.join)
                    cur, cur_w = { word }, ww
                else
                    cur[#cur + 1] = word
                    cur_w = cur_w + add
                end
            end
            if #cur > 0 then lines[#lines + 1] = table.concat(cur, B.join) end
        end
        if not force and #lines * line_h * k * line_k > max_h then return nil end
        return lines
    end
    for _, sp in ipairs(spaced and { true, false } or { false }) do
        local B = build(sp)
        local sz = size
        while true do
            local lines = lay(B, sz)
            if lines then return lines, sz end
            if sz <= minFont() then break end
            sz = max(minFont(), floor(sz * 0.92))
        end
    end
    return lay(build(false), minFont(), true), minFont()
end

function P.letter_board.build(env)
    env.bare = true
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 300, h / 300)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local text = env.cfg("text", nil)
    if type(text) ~= "string" or text:match("^%s*$") then text = T("So many books, so little time") end
    local stars = env.cfg("stars", true) ~= false
    local look, kit = lookOf("letter_board_look", "led", "chalk", "lightbox", "felt")
    local m = max(2, px(6))
    local ox, oy, ow, oh = objectBox(env, look == "led" and 1.18 or 1.12, 0, m)
    if ow < 30 or oh < 30 then return c end
    local fr = max(4, floor(min(ow, oh) * ((look == "felt" and 0.085) or (look == "led" and 0.05) or 0.07)))
    local ix, iy, iw, ih = ox + fr, oy + fr, ow - 2 * fr, oh - 2 * fr
    local o, ink, star_col, spaced, line_k
    local board_col = { 26, 26, 28 }
    if look == "led" then
        -- an LED marquee: a metal case with bolts, amber letters broken into
        -- dots by a dark grid laid over them (below)
        c:rrect(ox, oy, ow, oh, max(2, px(4)), { 40, 44, 52 })
        board_col = { 14, 10, 6 }
        c:rect(ix, iy, iw, ih, board_col)
        local br = max(2, floor(fr * 0.3))
        for _, q in ipairs({ { ox + fr / 2, oy + fr / 2 }, { ox + ow - fr / 2, oy + fr / 2 }, { ox + fr / 2, oy + oh - fr / 2 },
                { ox + ow - fr / 2, oy + oh - fr / 2 } }) do
            c:disc(q[1], q[2], br, { 110, 116, 128 })
        end
        o = { mono = true, bold = true, caps = true }
        ink, star_col, spaced, line_k = { 255, 176, 0 }, { 255, 176, 0 }, false, 1.0
    elseif look == "chalk" then
        c:rrect(ox, oy, ow, oh, max(2, px(4)), { 72, 46, 30 })
        c:frame(ox + max(2, floor(fr * 0.35)), oy + max(2, floor(fr * 0.35)), ow - 2 * max(2, floor(fr * 0.35)),
            oh - 2 * max(2, floor(fr * 0.35)), 0, max(1, px(2)), { 120, 84, 56 }, { 72, 46, 30 })
        board_col = { 38, 58, 48 }
        c:rect(ix, iy, iw, ih, board_col)
        -- a ledge with a stick of chalk
        c:rect(ox + floor(ow * 0.6), oy + oh - fr + max(1, floor(fr * 0.25)), floor(ow * 0.14), max(2, floor(fr * 0.4)), { 236, 234, 226 })
        o = { serif = true, italic = true }
        ink, star_col, spaced, line_k = { 232, 234, 226 }, { 214, 216, 206 }, false, 1.1
    elseif look == "lightbox" then
        c:rrect(ox, oy, ow, oh, max(4, fr), { 246, 166, 198 })
        c:rrect(ix, iy, iw, ih, max(2, floor(fr * 0.6)), { 255, 253, 250 })
        o = { bold = true, caps = true }
        ink, star_col, spaced, line_k = { 34, 30, 32 }, { 236, 110, 160 }, true, 1.15
    else
        -- pine frame, black felt with its grooves, white letters
        c:rect(ox, oy, ow, oh, { 150, 110, 64 })
        c:rect(ox + 1, oy + 1, ow - 2, oh - 2, { 214, 172, 114 })
        c:rect(ix - 1, iy - 1, iw + 2, ih + 2, { 170, 128, 76 })
        c:rect(ix, iy, iw, ih, { 26, 26, 28 })
        for yy = iy + max(2, px(4)), iy + ih - 1, max(3, px(5)) do c:rect(ix, yy, iw, 1, { 40, 40, 42 }) end
        o = { bold = true, caps = true }
        ink, star_col, spaced, line_k = { 242, 242, 238 }, { 242, 242, 238 }, true, 1.15
    end
    local pad = max(4, floor(iw * 0.08))
    local star_r = stars and max(3, floor(min(iw, ih) * 0.04)) or 0
    local lines, size = wrapFit(c, o.caps and A.upper(text) or text, fpx(40), iw - 2 * pad - 2 * star_r * 3.4, ih - 2 * pad, o,
        line_k, spaced)
    local tlines = {}
    local total = 0
    local oo = {}
    for k, v in pairs(o) do oo[k] = v end
    oo.color = ink
    oo.caps = nil
    for i, l in ipairs(lines) do
        tlines[i] = c:text(l, size, oo)
        total = total + tlines[i].h * line_k
    end
    local yy = iy + floor((ih - total) / 2)
    local first_x, last_right, last_y, first_y
    for i, t in ipairs(tlines) do
        local lx = ix + floor((iw - t.w) / 2)
        c:put(t, lx, yy)
        if i == 1 then first_x, first_y = lx, yy + t.h / 2 end
        last_right, last_y = lx + t.w, yy + t.h / 2
        yy = yy + floor(t.h * line_k)
    end
    if stars and first_x then
        -- as on a real board: an outline star before the words, a solid
        -- one after them
        local function deco(x, y, hollow)
            if look == "lightbox" then
                c:heart(x, y, star_r * 2.3, star_r * 2.1, { outer = 1, line = star_col, fill = star_col, track = star_col, t = 1 })
            else
                star(c, x, y, star_r * 1.2, star_col)
                if hollow then star(c, x, y + star_r * 0.06, star_r * 0.62, board_col) end
            end
        end
        deco(first_x - star_r * 2.5, first_y, true)
        deco(last_right + star_r * 2.5, last_y, false)
    end
    if look == "led" and size >= 18 then
        -- the dot grid: dark lines across the letters every few pixels (not
        -- on letters too small to stay readable through it)
        local step = max(3, floor(size / 6))
        for xx = ix, ix + iw - 1, step do c:rect(xx, iy, 1, ih, board_col) end
        for yy2 = iy, iy + ih - 1, step do c:rect(ix, yy2, iw, 1, board_col) end
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Today's pages
-- ════════════════════════════════════════════════════════════════════════════

P.pages_today = {
    does = T("nothing"),
    title = T("Today's pages"), tone = "ink", ratio = 1, ratio_narrow = 1, bare = true,
    start_w = 1, start_h = 1,
    summary = T("The pages you've read today, as an ornament with no card. Works offline."),
    poll = function()
        local st = D.stats()
        if type(st) ~= "table" then return tostring(st) end
        return table.concat({ st.today.pages, st.today.secs, st.streak, st.week_pages or 0, os.date("%Y-%m-%d") }, ",")
    end,
}

local PAPER = { 252, 251, 247 }
local PAPER_EDGE = { 186, 182, 172 }
local RECEIPT_INK = { 44, 44, 48 }

-- The last n days' pages, oldest first, today last: { t = time, pages = n }.
local function lastDays(st, n, env)
    local out = {}
    local now = os.date("*t")
    local sample = { 31, 18, 0, 42, 12, 27 }
    for k = n - 1, 0, -1 do
        local t = os.time{ year = now.year, month = now.month, day = now.day - k, hour = 12 }
        local pages
        if k == 0 then
            pages = st and st.today and st.today.pages or 0
        elseif env.sample then
            pages = sample[(k - 1) % #sample + 1]
        else
            local rec = st and st.days and st.days[os.date("%Y-%m-%d", t)]
            pages = rec and rec.pages or 0
        end
        out[#out + 1] = { t = t, pages = pages }
    end
    return out
end

function P.pages_today.build(env)
    env.bare = true
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 300, h / 300)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = A.statsFor(env)
    local pages = st and st.today and st.today.pages or nil
    local secs = st and st.today and st.today.secs or 0
    local streak = st and st.streak or 0
    local num = pages and tostring(pages) or "\xE2\x80\xA6"
    local look, kit = lookOf("pages_today_look", "counter", "card", "note", "receipt")
    local m = max(2, px(6))

    if look == "counter" then
        -- a heart monitor: a pulse line across a grid, one beat a day for
        -- the last week (taller the more you read, today's in magenta), and
        -- today's pages in big figures under it
        local CY = kit
        local MAG = CY.MAGENTA
        local ox, oy, ow, oh = objectBox(env, 1.15, 0, m)
        local cut = floor(min(ow, oh) * 0.12)
        CY.cutFrame(c, ox, oy, ow, oh, cut, max(2, px(3)), MAG, CY_PANEL)
        local ip = max(6, px(12))
        local gx, gy, gw, gh = ox + ip, oy + max(ip, floor(cut * 0.8)), ow - 2 * ip, floor(oh * 0.44)
        local step = max(6, px(14))
        for xx = gx, gx + gw, step do c:rect(xx, gy, 1, gh, { 22, 30, 38 }) end
        for yy = gy, gy + gh, step do c:rect(gx, yy, gw, 1, { 22, 30, 38 }) end
        local week = lastDays(st, 7, env)
        local top = 0
        for _, d in ipairs(week) do top = max(top, d.pages) end
        local base = gy + floor(gh * 0.66)
        local pts = { gx, base }
        local function pt(x, y) pts[#pts + 1] = x; pts[#pts + 1] = y end
        local seg = gw / #week
        for i, d in ipairs(week) do
            local sx = gx + (i - 1) * seg
            local amp = top > 0 and (d.pages / top) * gh * 0.6 or 0
            pt(sx + seg * 0.35, base)
            pt(sx + seg * 0.45, base - amp)
            pt(sx + seg * 0.55, base + amp * 0.3)
            pt(sx + seg * 0.65, base)
        end
        pt(gx + gw, base)
        c:polyline(pts, max(2, px(3)), CY_CYAN)
        local amp = top > 0 and (week[#week].pages / top) * gh * 0.6 or 0
        c:disc(gx + (#week - 1) * seg + seg * 0.45, base - amp, max(3, px(6)), MAG)
        local ny = gy + gh + px(8)
        local t_n = fitText(c, num, fpx(64), ow * 0.5, { mono = true, bold = true }, oh - (ny - oy) - ip)
        split(c, num, t_n.px, ox + ip + px(2), ny, CY_YEL, { mono = true, bold = true })
        local t_u = c:text("PG", fpx(18), { mono = true, bold = true, color = CY_YEL })
        c:put(t_u, ox + ip + px(6) + t_n.w, ny + t_n.h * 0.55)
        -- the label and the time read at the right, when there's room
        local room = ow - 2 * ip - px(12) - t_n.w - t_u.w - px(8)
        local t_l = fitText(c, "PULSE:READING", fpx(12), room, { mono = true, bold = true, color = MAG })
        local t_t = fitText(c, A.upper(A.fmtMinutes(secs / 60)), fpx(16), room, { mono = true, bold = true, color = CY_CYAN })
        if t_l.w <= room then c:put(t_l, ox + ow - ip, ny + px(4), "r") end
        if t_t.w <= room then c:put(t_t, ox + ow - ip, ny + px(8) + (t_l.w <= room and t_l.h or 0), "r") end
        return c
    end
    if look == "card" then
        -- a library card: the last few days' pages written in by hand,
        -- today's stamped
        local AC = kit
        local ox, oy, ow, oh = objectBox(env, 0.76, 0, m)
        local cream = { 243, 234, 214 }
        local brown = { 96, 72, 48 }
        c:frame(ox, oy, ow, oh, 0, 1, { 160, 138, 104 }, cream)
        local ip = max(4, floor(ow * 0.08))
        local iw = ow - 2 * ip
        local t_h = fitText(c, A.upper(T("Pages read")), fpx(20), iw, { serif = true, bold = true, color = brown })
        local y = oy + ip
        c:put(t_h, ox + ow / 2, y, "c")
        y = y + t_h.h + px(2)
        local rl = max(1, px(2))
        c:rect(ox + ip, y, iw, rl, AC.OXBLOOD)
        c:rect(ox + ip, y + rl + 1, iw, 1, AC.OXBLOOD)
        y = y + rl + 1 + max(2, px(4))
        local split = ox + ip + floor(iw * 0.55)
        local t_c1 = fitText(c, A.upper(T("Date")), fpx(12), split - ox - ip - px(4), { serif = true, color = brown })
        local t_c2 = fitText(c, A.upper(T("Pages")), t_c1.px, ox + ow - ip - split - px(6), { serif = true, color = brown })
        c:put(t_c1, ox + ip + px(2), y)
        c:put(t_c2, split + px(6), y)
        y = y + t_c1.h + px(2)
        -- as many rows as fit, today's at the bottom
        local bottom = oy + oh - ip
        local size = fpx(16)
        local row_h = floor(c:text("Ag", size, { serif = true, italic = true }).h * 1.3)
        local rows = min(7, floor((bottom - y) / row_h))
        while rows < 1 and size > minFont() do
            size = max(minFont(), floor(size * 0.85))
            row_h = floor(c:text("Ag", size, { serif = true, italic = true }).h * 1.3)
            rows = min(7, floor((bottom - y) / row_h))
        end
        rows = max(1, rows)
        row_h = max(row_h, min(floor(row_h * 1.25), floor((bottom - y) / rows)))
        local list = lastDays(st, rows, env)
        local blue, red = { 168, 186, 214 }, { 214, 168, 168 }
        c:rect(split, y - t_c1.h - px(2), 1, rows * row_h + t_c1.h + px(2), red)
        for i, d in ipairs(list) do
            local ry = y + (i - 1) * row_h
            c:rect(ox + ip, ry + row_h - 1, iw, 1, blue)
            local today = i == #list
            if today then
                -- the stamp when it fits the row (its size as AC.stamp works
                -- it out), else the word in red ink
                local stamp_px = max(minFont(), floor(size * 0.72))
                local t_s = c:text(T("Today"), stamp_px, { serif = true, bold = true, caps = true })
                local sw_ = t_s.w + 2 * max(3, floor(stamp_px * 0.35)) + 4
                local sh_ = t_s.h + floor(stamp_px * 0.2) + 4
                if sh_ <= row_h - 2 and sw_ <= split - ox - ip - px(2) then
                    AC.stamp(c, T("Today"), stamp_px, ox + ip, ry + row_h - 1 - sh_, AC.OXBLOOD)
                else
                    local t_d = fitText(c, T("Today"), size, split - ox - ip - px(4), { serif = true, bold = true, color = AC.OXBLOOD })
                    c:put(t_d, ox + ip + px(2), ry + row_h - 2 - t_d.base)
                end
            else
                local t_d = fitText(c, A.date("%d %b", d.t), size, split - ox - ip - px(4), { serif = true, italic = true, color = AC.INK })
                c:put(t_d, ox + ip + px(2), ry + row_h - 2 - t_d.base)
            end
            local figure = today and num or (d.pages > 0 and tostring(d.pages) or "\xE2\x80\x94")
            local t_n = fitText(c, figure, today and floor(size * 1.15) or size, ox + ow - ip - split - px(8),
                { serif = true, italic = true, bold = today or nil, color = AC.INK }, row_h)
            c:put(t_n, split + px(8), ry + row_h - 2 - t_n.base)
        end
        return c
    end
    if look == "note" then
        -- a sticky note with washi tape and a turned-up corner
        local ox, oy, ow, oh = objectBox(env, 1, 0, m)
        local note = { 255, 214, 228 }
        local sh = max(2, px(4))
        c:rect(ox + sh, oy + sh, ow - sh, oh - sh, A.mix(note, { 0, 0, 0 }, 0.35))
        c:rect(ox, oy, ow - sh, oh - sh, note)
        local fold = floor(ow * 0.16)
        local fx, fy = ox + ow - sh - fold, oy + oh - sh - fold
        c:sprite(fx + fold / 2, fy + fold / 2, fold, 0, {
            { "t", 0.5, -0.5, -0.5, 0.5, 0.5, 0.5, A.mix(note, { 0, 0, 0 }, 0.35), A.mix(note, { 0, 0, 0 }, 0.35) },
            { "t", 0.5, -0.5, -0.5, 0.5, -0.5, -0.5, A.mix(note, { 255, 255, 255 }, 0.4), A.mix(note, { 0, 0, 0 }, 0.2) },
        }, { lw = 1 })
        c:rect(ox + floor(ow * 0.32), oy - max(2, px(6)), floor(ow * 0.36), max(6, floor(oh * 0.1)), { 196, 228, 214 })
        local ink = { 130, 34, 80 }
        local t_n = fitText(c, num, fpx(110), ow * 0.72, { bold = true, color = ink }, oh * 0.46)
        local t_w = fitText(c, (pages or 0) == 1 and T("page today!") or T("pages today!"), fpx(24), ow * 0.8,
            { bold = true, color = ink })
        local blk = t_n.h * 0.95 + t_w.h
        local yy = oy + floor((oh - sh - blk) / 2)
        c:put(t_n, ox + (ow - sh) / 2, yy, "c")
        c:put(t_w, ox + (ow - sh) / 2, yy + t_n.h * 0.95, "c")
        c:heart(ox + floor(ow * 0.16), oy + floor(oh * 0.2), floor(ow * 0.12), floor(ow * 0.11),
            { outer = 1, line = { 236, 110, 160 }, fill = { 236, 110, 160 }, track = note, t = 1 })
        return c
    end
    -- a till receipt: the shop, the date, the lines, the total in big
    -- figures, a barcode, torn off at the bottom
    local ox, oy, ow, oh = objectBox(env, 0.68, 0, m)
    local tear = max(3, floor(ow * 0.035))
    local paper_h = oh - tear
    c:frame(ox, oy, ow, paper_h, 0, 1, PAPER_EDGE, PAPER)
    -- the torn edge: little half-discs of paper along the bottom, edged
    local step = tear * 2
    local n_sc = max(1, floor((ow - 2) / step))
    local x0 = ox + (ow - n_sc * step) / 2 + tear
    for i = 0, n_sc - 1 do c:disc(x0 + i * step, oy + paper_h - 1, tear + 1, PAPER_EDGE) end
    c:rect(ox + 1, oy + paper_h - tear - 2, ow - 2, tear + 1, PAPER)
    for i = 0, n_sc - 1 do c:disc(x0 + i * step, oy + paper_h - 1, tear, PAPER) end
    local ip = max(4, floor(ow * 0.09))
    local lw = ow - 2 * ip
    local o = { mono = true, color = RECEIPT_INK }
    -- one size for the lines: the longest one just fits
    local rows = {
        { A.upper(T("Time read")), A.upper(A.fmtMinutes(secs / 60)) },
        { A.upper(T("Streak")), tostring(streak) },
        { A.upper(T("This week")), st and st.week_pages and tostring(st.week_pages) or "\xE2\x80\xA6" },
    }
    local widest = 0
    for _, r in ipairs(rows) do widest = max(widest, c:text(r[1] .. "  " .. r[2], 100, o).w) end
    local size = max(minFont(), min(fpx(18), floor(100 * lw / max(1, widest))))
    -- lines a little closer than the text's own box, as a till prints them
    local lh = floor(c:text("Ag", size, o).h * 0.8)
    local top, bottom = oy + ip, oy + paper_h - tear - ip
    local t_shop = c:text(A.upper(A.NAME), size, { mono = true, bold = true, color = RECEIPT_INK, max_w = lw })
    local t_date = c:text(A.upper(A.date("%d %b %Y", os.time())), size, { mono = true, color = RECEIPT_INK, max_w = lw })
    local t_big = fitText(c, num, fpx(72), lw * 0.8, { mono = true, bold = true, color = RECEIPT_INK },
        (oy + paper_h - tear - ip - (oy + ip)) * 0.3)
    local t_unit = fitText(c, A.upper(T("Pages today")), size, lw, { mono = true, bold = true, color = RECEIPT_INK })
    local bar_h = max(px(10), floor(lh * 1.3))
    local dash_h = max(4, floor(lh * 0.6))
    -- what goes on, most wanted first: the figures and their words, the
    -- barcode, the shop and the date, then as many lines as fit
    local room = bottom - top
    local need = t_big.h + t_unit.h
    local with_bar = need + bar_h + px(6) <= room
    if with_bar then need = need + bar_h + px(6) end
    local with_head = need + 2 * lh + dash_h <= room
    if with_head then need = need + 2 * lh + dash_h end
    local n_rows = 0
    while n_rows < #rows and need + lh * (n_rows + 1) + dash_h <= room do n_rows = n_rows + 1 end
    if n_rows > 0 then need = need + lh * n_rows + dash_h end
    -- spread what's left over between the parts
    local gaps = 1 + (with_head and 1 or 0) + (n_rows > 0 and 1 or 0) + (with_bar and 1 or 0)
    local spare = max(0, floor((room - need) / gaps))
    local function dashes(yy)
        local dw = max(2, floor(size * 0.35))
        local xx = ox + ip
        while xx + dw <= ox + ip + lw do c:rect(xx, yy, dw, 1, RECEIPT_INK); xx = xx + dw * 2 end
    end
    local yy = top
    if with_head then
        c:put(t_shop, ox + ow / 2, yy, "c"); yy = yy + lh
        c:put(t_date, ox + ow / 2, yy, "c"); yy = yy + lh
        yy = yy + floor(spare / 2)
        dashes(yy + floor(dash_h / 2)); yy = yy + dash_h
    end
    if n_rows > 0 then
        if not with_head then yy = yy + floor(spare / 2) end
        for i = 1, n_rows do
            local r = rows[i]
            c:put(c:text(r[1], size, o), ox + ip, yy)
            c:put(c:text(r[2], size, o), ox + ip + lw, yy, "r")
            yy = yy + lh
        end
        dashes(yy + floor(dash_h / 2)); yy = yy + dash_h
        yy = yy + floor(spare / 2)
    elseif with_head then
        yy = yy + floor(spare / 2)
    end
    c:put(t_big, ox + ow / 2, yy, "c"); yy = yy + t_big.h
    c:put(t_unit, ox + ow / 2, yy, "c"); yy = yy + t_unit.h
    if with_bar then
        -- a barcode, the same for the same day
        local seed = tonumber(os.date("%Y%m%d")) or 1
        local xx = ox + ip
        local by = bottom - bar_h
        while xx < ox + ip + lw - 2 do
            seed = (seed * 1103515245 + 12345) % 2147483648
            local bw_ = 1 + (seed % 3)
            c:rect(xx, by, bw_, bar_h, RECEIPT_INK)
            xx = xx + bw_ + 1 + (floor(seed / 7) % 3)
        end
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Pages turned: every page you've read (or this year's)
-- ════════════════════════════════════════════════════════════════════════════

P.pages_turned = {
    does = T("nothing"),
    title = T("Pages turned"), tone = "ink", ratio = 0.8, ratio_narrow = 0.8, bare = true,
    start_w = 1, start_h = 1,
    summary = T("Every page you've turned, or this year's, as an ornament with no card. Works offline."),
    poll = function()
        local all = D.pagesTurned(nil, A.get("pages_turned_period", "all"))
        return tostring(type(all) == "table" and all.pages)
    end,
}

-- The number's characters: digits get a card (or a cell) each, the
-- thousands separators a narrow gap.
local function chars(str)
    local out = {}
    for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

-- The next round number past n (42,351 -> 50,000), for the Cyber look.
local function milestone(n)
    if n < 100 then return 100 end
    local k = 10 ^ (#tostring(floor(n)) - 1)
    return (floor(n / k) + 1) * k
end

function P.pages_turned.build(env)
    env.bare = true
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 300, h / 300)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local period = env.cfg("period", "all")
    local year = period == "year"
    local data
    if env.sample then
        data = { pages = year and 12846 or 48213, first = "2019-03-02" }
    else
        data = D.pagesTurned(env.refresh, period)
    end
    local n = type(data) == "table" and data.pages or nil
    local num = n and A.thousands(n) or "\xE2\x80\xA6"
    local first_year = type(data) == "table" and data.first and data.first:sub(1, 4) or nil
    local this_year = os.date("%Y")
    local look, kit = lookOf("pages_turned_look", "counter", "book", "worm", "flip")
    local m = max(2, px(6))
    local label = year and A.tr("pages turned in %1", this_year) or T("pages turned")

    -- the digits and separators of the number
    local cs = chars(num)
    local nd, ns = 0, 0
    for _, ch in ipairs(cs) do if ch:match("^%d$") then nd = nd + 1 else ns = ns + 1 end end
    if nd == 0 then nd = 1 end

    if look == "counter" then
        -- a data counter: the figures glitched like the Cyber clock, and a
        -- bar of segments to the next round number
        local CY = kit
        local MAG = CY.MAGENTA
        local tw = nd + (nd - 1) * 0.14 + ns * 0.22 + 0.7
        -- sized in two goes: the most room there is, then just the height
        -- the cells (as wide as fits) and the words need
        local ox, oy, ow, oh = objectBox(env, 1.2, 0, m)
        local ip = max(4, px(10))
        local head = A.upper(year and A.tr("pages turned in %1", this_year) or T("pages turned")):gsub(" ", "_")
        local t_h = fitText(c, head, fpx(16), ow - 2 * ip, { mono = true, bold = true, color = CY_CYAN })
        local t_probe = c:text("NEXT 0", fpx(13), { mono = true, bold = true })
        local bar_h = max(5, px(8))
        local function fixed(box_w, box_h)
            return ip + t_h.h + px(6) + px(8) + bar_h + px(4) + t_probe.h + max(ip, floor(min(box_w, box_h) * 0.09))
        end
        local u = max(6, min((ow - 2 * ip) / (tw - 0.7), (oh - fixed(ow, oh)) / 1.35))
        local need_h = fixed(ow, oh) + floor(u * 1.35)
        ox, oy, ow, oh = objectBox(env, ow / need_h, 0, m)
        -- the box may have come out bigger: the cells grow to it, and what's
        -- left over goes above and below
        u = max(6, min((ow - 2 * ip) / (tw - 0.7), (oh - fixed(ow, oh)) / 1.35))
        local slack = max(0, floor((oh - fixed(ow, oh) - floor(u * 1.35)) / 2))
        local cut = floor(min(ow, oh) * 0.1)
        CY.cutFrame(c, ox, oy, ow, oh, cut, max(2, px(3)), CY_CYAN, CY_PANEL)
        scanlines(c, ox + px(3), oy + px(3), ow - px(6), oh - px(6) - cut, { 18, 20, 28 }, max(3, px(4)))
        c:put(t_h, ox + ip, oy + ip + floor(slack / 2))
        -- the figures in white, glitched cyan and red, like the Cyber clock
        local ch_ = floor(u * 1.35)
        local cy = oy + ip + floor(slack / 2) + t_h.h + px(6) + floor(slack / 2)
        local t_n = fitText(c, num, fpx(130), ow - 2 * ip, { bold = true }, ch_ * 1.3)
        CY.glitch(c, num, t_n.px, ox + floor((ow - t_n.w) / 2), cy + floor((ch_ - t_n.h) / 2),
            { color = CY_WHITE, color2 = CY_CYAN, alert = CY_RED })
        -- the bar to the next round number
        local by = cy + ch_ + px(8)
        local nxt = milestone(n or 0)
        local frac = n and n / nxt or 0
        local bw = ow - 2 * ip
        CY.segbar(c, ox + ip, by, bw, bar_h, frac, 14, CY_YEL, CY_DIM)
        local ly = by + bar_h + px(4)
        local t_n = fitText(c, "NEXT " .. A.thousands(nxt), fpx(13), bw * 0.62, { mono = true, bold = true, color = MAG })
        c:put(t_n, ox + ip, ly)
        local right = (not year and first_year) and ("SINCE_" .. first_year) or (floor(frac * 100 + 0.5) .. "%")
        local t_r = c:text(right, t_n.px, { mono = true, bold = true, color = CY_CYAN })
        if t_n.w + t_r.w + px(10) <= bw then c:put(t_r, ox + ow - ip, ly, "r") end
        return c
    end

    if look == "book" then
        -- an open book on its leather cover, a red ribbon down the middle;
        -- the words on the left page, the figures written in on the right
        local AC = kit
        local ox, oy, ow, oh = objectBox(env, 1.45, 0, m)
        local cover, cover_dk = { 92, 52, 34 }, { 58, 32, 22 }
        local paper, paper_dk, paper_ln = { 243, 234, 214 }, { 214, 200, 170 }, { 226, 214, 190 }
        local e = max(3, floor(oh * 0.05))
        c:rrect(ox, oy + e, ow, oh - e, max(3, floor(e * 0.8)), cover_dk)
        c:rrect(ox + 1, oy + e + 1, ow - 2, oh - e - 2, max(3, floor(e * 0.8)), cover)
        local gx = ox + ow / 2
        local lx, rx = ox + e, ox + ow - e
        local top, bot = oy, oy + oh - e * 1.6
        local dip = oh * 0.06
        -- a page: its top and bottom edges curve down towards the gutter
        local function page(x0, x1, dy, col)
            local pts = {}
            local steps = 10
            for i = 0, steps do
                local t = i / steps
                local x = x0 + (x1 - x0) * t
                local k = (x1 > x0) and t or t          -- 0 at the outer edge, 1 at the gutter
                pts[#pts + 1] = x
                pts[#pts + 1] = top + dy + dip * k * k
            end
            for i = steps, 0, -1 do
                local t = i / steps
                local x = x0 + (x1 - x0) * t
                pts[#pts + 1] = x
                pts[#pts + 1] = bot + dy + dip * 0.6 * t * t
            end
            AC.poly(c, pts, col)
        end
        -- the page edges under each page (its thickness), then the pages
        page(lx - px(2), gx, px(3), paper_dk)
        page(rx + px(2), gx, px(3), paper_dk)
        page(lx, gx, 0, paper)
        page(rx, gx, 0, paper)
        -- the gutter's shadow
        for i = 0, 2 do
            c:rect(floor(gx - 1 - i * 2), floor(top + dip), 1, floor(bot - top), A.mix(paper, paper_dk, 0.8 - i * 0.25))
            c:rect(floor(gx + i * 2), floor(top + dip), 1, floor(bot - top), A.mix(paper, paper_dk, 0.8 - i * 0.25))
        end
        -- the ribbon
        local rw = max(4, floor(ow * 0.03))
        local ry0, ry1 = top + dip * 0.6, bot + dip + e * 1.3
        AC.poly(c, { gx - rw / 2, ry0, gx + rw / 2, ry0, gx + rw / 2, ry1, gx, ry1 - rw * 0.7, gx - rw / 2, ry1 }, AC.OXBLOOD)
        -- the left page: the words, an ornament, since when
        local pw = gx - lx
        local lcx = lx + pw / 2 + px(2)
        local words = A.upper(year and A.tr("pages turned in %1", this_year) or T("pages turned"))
        local lo = { serif = true, bold = true, color = AC.SEPIA }
        local t_l = fitText(c, words, fpx(18), pw * 0.78, lo)
        if t_l.w > pw * 0.8 then
            -- two lines: the words broken at the space nearest the middle
            local best, at = nil, nil
            for i in words:gmatch("() ") do
                local d = math.abs(i - #words / 2)
                if not best or d < best then best, at = d, i end
            end
            if at then
                local l1, l2 = words:sub(1, at - 1), words:sub(at + 1)
                local t1 = fitText(c, l1, fpx(18), pw * 0.78, lo)
                local t2 = fitText(c, l2, t1.px, pw * 0.78, lo)
                local sz = min(t1.px, t2.px)
                t1, t2 = c:text(l1, sz, lo), c:text(l2, sz, lo)
                -- one record standing for both lines
                local both = A.canvas{ w = max(t1.w, t2.w), h = t1.h + t2.h, tone = env.tone, plain = true }
                both:put(t1, both.w / 2, 0, "c")
                both:put(t2, both.w / 2, t1.h, "c")
                t_l = { two = both, w = both.w, h = both.h }
            end
        end
        local t_s
        if year then
            t_s = fitText(c, roman(tonumber(this_year) or 2026), fpx(15), pw * 0.7, { serif = true, color = AC.SEPIA })
        elseif first_year then
            t_s = fitText(c, A.tr("since %1", first_year), fpx(15), pw * 0.7, { serif = true, italic = true, color = AC.SEPIA })
        end
        -- (the ornament is about three times as wide as it's tall)
        local orn = max(6, floor(min((t_l.two and t_l.h / 2 or t_l.h) * 0.7, pw * 0.22)))
        local blk = t_l.h + orn + px(6) + (t_s and t_s.h or 0)
        local yy = top + dip * 0.5 + floor((bot - top - blk) / 2)
        if t_l.two then c:sub(t_l.two, floor(lcx - t_l.w / 2), floor(yy)) else c:put(t_l, lcx, yy, "c") end
        yy = yy + t_l.h + px(2)
        AC.ornament(c, lcx, yy + orn / 2, orn, AC.GOLD_DARK); yy = yy + orn + px(4)
        if t_s then c:put(t_s, lcx, yy, "c") end
        -- faint ruled lines low on the left page
        local ly = yy + (t_s and t_s.h or 0) + px(8)
        while ly < bot - px(10) do
            c:rect(floor(lx + pw * 0.14), floor(ly), floor(pw * 0.7), 1, paper_ln)
            ly = ly + max(6, px(12))
        end
        -- the right page: the figures in ink
        local rcx = gx + (rx - gx) / 2 - px(2)
        local t_n = fitText(c, num, fpx(80), pw * 0.8, { serif = true, bold = true, italic = true, color = AC.INK }, (bot - top) * 0.55)
        c:put(t_n, rcx, top + dip * 0.5 + (bot - top) / 2, "c", "mid")
        c:rect(floor(rcx - t_n.w * 0.4), floor(top + dip * 0.5 + (bot - top) / 2 + t_n.h * 0.42), floor(t_n.w * 0.8), 1, AC.INK)
        return c
    end

    if look == "worm" then
        -- a heart-pink banner with the figures, a sticker with a white edge
        local white = { 255, 255, 255 }
        local t_l0 = c:text(label .. "!", 20, { bold = true })
        -- wide enough for the words under the figures
        local aspect = max(1.5, min(2.4, t_l0.w / t_l0.h * 0.32))
        local ox, oy, ow, oh = objectBox(env, aspect, 0, m)
        local edge = max(2, floor(min(ow, oh) * 0.035))
        local bx, by, bw, bh = ox + edge, oy + edge, ow - 2 * edge, oh - 2 * edge
        local r = floor(min(bw, bh) / 4)
        c:rrect(ox, oy, ow, oh, r + edge, white)
        c:rrect(bx, by, bw, bh, r, { 244, 150, 186 })
        local lo = { bold = true, color = { 255, 236, 244 } }
        local t_l = fitText(c, label .. "!", fpx(22), bw * 0.84, lo)
        -- too small a banner for "pages turned in 2026!": just "pages turned!"
        if t_l.w > bw * 0.88 and year then t_l = fitText(c, T("pages turned") .. "!", fpx(22), bw * 0.84, lo) end
        local t_n = fitText(c, num, fpx(120), bw * 0.84, { bold = true, color = white }, (bh - t_l.h) * 0.8)
        local blk = t_n.h * 0.92 + t_l.h
        local yy = by + floor((bh - blk) / 2)
        c:put(t_n, bx + bw / 2, yy, "c")
        c:put(t_l, bx + bw / 2, yy + t_n.h * 0.92, "c")
        return c
    end

    -- a flip counter: a card for each digit, split across the middle where
    -- it flips, in a dark case, and a plate under it
    local tw = nd + (nd - 1) * 0.1 + ns * 0.2 + 0.44
    local case_h = 1.5 + 0.44
    local th = case_h + 0.2 + 0.62
    local ox, oy, ow, oh = objectBox(env, tw / th, 0, m)
    local u = min(ow / tw, oh / th)
    local cw_, ch_ = u, floor(u * 1.5)
    local case_w = floor(tw * u)
    local hx = ox + floor((ow - case_w) / 2)
    local hy = oy + floor((oh - th * u) / 2)
    local case_c, rim = { 28, 28, 30 }, { 70, 70, 74 }
    local r = max(2, floor(u * 0.16))
    c:rrect(hx, hy, case_w, floor(case_h * u), r, rim)
    c:rrect(hx + 1, hy + 1, case_w - 2, floor(case_h * u) - 2, r, case_c)
    local top_c, bot_c, ivory = { 64, 64, 68 }, { 50, 50, 54 }, { 242, 238, 228 }
    local t_d = fitText(c, "8", fpx(160), cw_ * 0.8, { bold = true }, ch_ * 1.3)
    local split_h = max(1, floor(u * 0.05))
    local x = hx + floor(0.22 * u)
    local y = hy + floor(0.22 * u)
    local placed = 0
    for _, chr in ipairs(cs) do
        if chr:match("^%d$") or chr == "\xE2\x80\xA6" then
            if placed > 0 then x = x + floor(u * 0.1) end
            local rr = max(1, floor(u * 0.08))
            local half = floor(ch_ / 2)
            c:rrect(x, y, cw_, half, rr, top_c)
            c:rrect(x, y + half, cw_, ch_ - half, rr, bot_c)
            c:rect(x + rr, y + 1, cw_ - 2 * rr, 1, A.mix(top_c, ivory, 0.18))
            local t = c:text(chr, t_d.px, { bold = true, color = ivory })
            c:put(t, x + cw_ / 2, y + ch_ / 2, "c", "mid")
            -- the split, cut through the figure, and its hinge pins
            c:rect(x, y + half - floor(split_h / 2), cw_, split_h, case_c)
            local pin = max(2, floor(u * 0.06))
            c:rect(x - 1, y + half - pin, max(2, floor(u * 0.05)), 2 * pin, rim)
            c:rect(x + cw_ - max(2, floor(u * 0.05)) + 1, y + half - pin, max(2, floor(u * 0.05)), 2 * pin, rim)
            x = x + cw_
            placed = placed + 1
        else
            x = x + floor(u * 0.2)
        end
    end
    -- the plate: what it counts
    local ply = hy + floor((case_h + 0.2) * u)
    local plh = floor(0.62 * u)
    local t_l = fitText(c, A.upper(label), fpx(22), case_w - px(16), { bold = true, color = ivory }, plh - 2)
    local plw = min(case_w, t_l.w + px(24))
    c:rrect(hx + floor((case_w - plw) / 2), ply, plw, plh, floor(plh / 2), case_c)
    c:put(t_l, hx + case_w / 2, ply + plh / 2, "c", "mid")
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Lifetime pages: the Pages turned figures as a card, for the Dashboard
-- ════════════════════════════════════════════════════════════════════════════
-- Every page turned in big figures, how many a day on average since the
-- first, a bar to the next round number, and this year's, this month's and
-- this week's pages beside it. A look for every style.

P.total_pages = {
    does = T("opens reading progress"),
    title = T("Lifetime pages"), tone = "ink", ratio = 0.5, ratio_narrow = 0.8,
    summary = T("Every page you've ever turned in KOReader, with this year's, this month's and this week's, and the next round number. Needs the statistics plugin."),
    poll = function()
        local all = D.pagesTurned()
        return tostring(type(all) == "table" and all.pages)
    end,
}

function P.total_pages.tap(env)
    D.dispatch(env.cfg("tap", "reading_progress"))
end

local PASTEL = { { 126, 206, 176 }, { 178, 156, 228 }, { 246, 168, 132 }, { 126, 186, 232 } }

function P.total_pages.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local tall = w < h * 1.25
    local s = tall and min(w / 320, h / 420) or min(w / 546, h / 280)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local look, kit = lookOf("total_pages_look", "counter", "ledger", "worm", "plain")
    local all, yr, st
    if env.sample then
        all, yr = { pages = 48213, first = "2019-03-02" }, { pages = 12846 }
        st = { month_pages = { [tonumber(os.date("%m"))] = 1904 }, week_pages = 262 }
    else
        all = D.pagesTurned(env.refresh)
        yr = D.pagesTurned(env.refresh, "year")
        st = A.statsFor(env)
    end
    local pad = px(tall and 22 or 30)
    local serif = look == "ledger" or nil
    local t_head = c:label(T("Lifetime pages turned"), fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent,
        serif = serif, max_w = w - 2 * pad })
    if all == false then
        c:label(T("No reading statistics yet"), fpx(22), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted, max_w = w - 2 * pad })
        return c
    end
    local n = type(all) == "table" and all.pages or nil
    local num = n and A.thousands(n) or "\xE2\x80\xA6"
    -- since when, and a day on average since then
    local first_t
    if type(all) == "table" and all.first then
        local y, mo, d = A.parseYmd(all.first)
        if y then first_t = os.time{ year = y, month = mo, day = d, hour = 12 } end
    end
    if first_t then
        local since = A.tr("since %1", A.date("%b %Y", first_t))
        local t_s = c:text(since, fpx(17), { color = tone.muted, serif = serif, italic = serif })
        if t_head.w + t_s.w + px(20) <= w - 2 * pad then c:put(t_s, w - pad, px(22) + t_head.base, "r", "base") end
    end
    local avg
    if n and first_t then
        local days = max(1, floor((os.time() - first_t) / 86400 + 0.5) + 1)
        avg = floor(n / days + 0.5)
    end
    local nxt = milestone(n or 0)
    local frac = n and n / nxt or 0

    local top = px(22) + t_head.h + px(12)
    local bx, by, bw, bh = pad, top, w - 2 * pad, h - top - px(20)
    if bw < 40 or bh < 30 then return c end
    -- the figures' block, and the rows' box beside it (or under it)
    local lw = tall and bw or floor(bw * 0.56)
    -- (the name, its short form for a narrow card, the Cyber code, the figure)
    local rows = {
        { T("This year"), T("Year"), "YEAR", yr and yr.pages },
        { T("This month"), T("Month"), "MONTH", st and st.month_pages and st.month_pages[tonumber(os.date("%m"))] },
        { T("This week"), T("Week"), "WEEK", st and st.week_pages },
    }

    -- the big figures
    local function bigNumber(x, y, maxw, maxh)
        if look == "counter" then
            -- in white, glitched cyan and red, like the Cyber clock
            local t_n = fitText(c, num, fpx(66), maxw, { bold = true }, maxh)
            kit.glitch(c, num, t_n.px, x - floor(t_n.px * 0.03), y, { color = tone.fg })
            return t_n.h
        end
        local col = tone.fg
        if look == "worm" then col = (A.cozyHeart(tone)) end
        local t_n = fitText(c, num, fpx(66), maxw, { bold = true, serif = serif, color = col }, maxh)
        c:put(t_n, x, y)
        if look == "ledger" then
            -- a double gilt rule under the figures
            local AC = kit
            local ry = y + t_n.base + max(2, px(5))
            c:rect(x, ry, t_n.w, max(1, px(2)), AC.GOLD)
            c:rect(x, ry + max(3, px(5)), floor(t_n.w * 0.6), 1, AC.GOLD)
        end
        return t_n.h
    end

    -- the bar to the next round number
    local function bar(x, y, bw2, bh2)
        if look == "counter" then
            kit.segbar(c, x, y, bw2, bh2, frac, A.clamp(floor(bw2 / max(6, px(14))), 8, 24), tone.accent, A.mix(tone.bg, tone.fg, 0.16))
        elseif look == "worm" then
            -- ten hearts that fill up like glasses
            local k = 10
            local hs = min(floor(bw2 / k * 0.82), bh2 * 2)
            local step = (bw2 - hs) / (k - 1)
            local fill, line = A.cozyHeart(tone)
            for i = 1, k do
                local f = A.clamp(frac * k - (i - 1), 0, 1)
                c:heart(x + hs / 2 + (i - 1) * step, y + bh2 / 2, hs, hs * 0.92, { outer = f, line = line, fill = fill,
                    track = A.mix(tone.bg, fill, 0.18), t = max(1, floor(hs * 0.1)) })
            end
        elseif look == "ledger" then
            local AC = kit
            local mid = y + floor(bh2 / 2)
            c:rect(x, mid, bw2, 1, A.mix(tone.bg, AC.GOLD, 0.5))
            local fw = floor(bw2 * frac)
            if fw > 0 then c:rect(x, mid - max(1, floor(bh2 / 4)), fw, max(2, floor(bh2 / 2)), AC.GOLD) end
            local r = max(3, floor(bh2 * 0.6))
            local cx = x + fw
            AC.poly(c, { cx, mid - r, cx + r, mid, cx, mid + r, cx - r, mid }, AC.GOLD_DARK)
        else
            c:rrect(x, y, bw2, bh2, bh2 / 2, tone.track)
            local fw = floor(bw2 * frac)
            if fw > 0 then c:rrect(x, y, max(bh2, fw), bh2, bh2 / 2, tone.accent) end
        end
    end

    -- one of the period rows
    local short = false   -- (decided once, for all the rows, below)
    local function row(i, r, x, y, rw, rh)
        local val = r[4] and A.thousands(r[4]) or "\xE2\x80\xA6"
        local function name(size, o) return c:text(short and r[2] or r[1], size, o) end
        if look == "counter" then
            local t_c = c:text(r[3], fpx(18), { mono = true, bold = true, color = tone.accent2 })
            local t_v = fitText(c, val, fpx(21), rw - t_c.w - px(14), { mono = true, bold = true, color = tone.fg })
            local base = y + floor((rh - max(t_c.h, t_v.h)) / 2) + max(t_c.base, t_v.base)
            c:put(t_c, x, base, "l", "base")
            c:put(t_v, x + rw, base, "r", "base")
            kit.segbar(c, x, y + rh - max(2, px(4)), rw, max(2, px(4)), n and r[4] and n > 0 and min(1, r[4] / n * 4) or 0,
                A.clamp(floor(rw / max(6, px(12))), 6, 20), A.mix(tone.bg, tone.accent2, 0.7), A.mix(tone.bg, tone.fg, 0.12))
            return
        end
        if look == "ledger" then
            local AC = kit
            local t_l = name(fpx(19), { serif = true, italic = true, color = tone.muted })
            local t_v = fitText(c, val, fpx(21), rw - t_l.w - px(24), { serif = true, bold = true, color = tone.fg })
            local base = y + floor((rh - t_v.h) / 2) + t_v.base
            c:put(t_l, x, base, "l", "base")
            c:put(t_v, x + rw, base, "r", "base")
            local dot = max(1, px(3))
            for xx = x + t_l.w + px(10), x + rw - t_v.w - px(10) - dot, dot * 3 do
                c:rect(floor(xx), base - dot, dot, dot, A.mix(tone.bg, tone.muted, 0.7))
            end
            if i > 1 then c:rect(x, y, rw, 1, A.mix(tone.bg, AC.GOLD, 0.55)) end
            return
        end
        if look == "worm" then
            local pastel = PASTEL[(i - 1) % #PASTEL + 1]
            local fillc = A.mix(tone.bg, pastel, tone.dark and 0.3 or 0.32)
            local ink = tone.dark and tone.fg or A.mix(pastel, { 0, 0, 0 }, 0.6)
            local ph = rh - max(2, px(6))
            c:rrect(x, y + floor((rh - ph) / 2), rw, ph, ph / 2, fillc)
            local ip = floor(ph * 0.4)
            local t_l = name(fpx(18), { bold = true, color = ink })
            local t_v = fitText(c, val, fpx(20), rw - 2 * ip - t_l.w - px(10), { bold = true, color = ink })
            c:put(t_l, x + ip, y + rh / 2, "l", "mid")
            c:put(t_v, x + rw - ip, y + rh / 2, "r", "mid")
            return
        end
        local t_l = name(fpx(17), { bold = true, caps = true, color = tone.label or tone.muted })
        local t_v = fitText(c, val, fpx(22), rw - t_l.w - px(14), { bold = true, color = tone.fg })
        local base = y + floor((rh - max(t_l.h, t_v.h)) / 2) + max(t_l.base, t_v.base)
        c:put(t_l, x, base, "l", "base")
        c:put(t_v, x + rw, base, "r", "base")
        if i > 1 then c:rect(x, y, rw, 1, tone.track) end
    end

    -- the figures' block: the number, a day on average, the bar, what's to go
    local o_small = { color = tone.muted, serif = serif, mono = (look == "counter") or nil }
    local t_avg = avg and fitText(c, A.tr("%1 a day on average", A.thousands(avg)), fpx(18), lw, o_small) or nil
    local togo = n and A.tr("%1 to go to %2", A.thousands(nxt - n), A.thousands(nxt)) or nil
    local t_go = togo and fitText(c, togo, fpx(16), lw, { color = tone.label or tone.muted, serif = serif,
        mono = (look == "counter") or nil }) or nil
    local bar_h = look == "worm" and max(10, px(18)) or max(4, px(look == "ledger" and 10 or 9))
    local small_h = (t_avg and t_avg.h or 0) + px(8) + bar_h + px(6) + (t_go and t_go.h or 0)
    local rows_h = 0
    local row_h = max(px(34), c:text("Ag", fpx(22)).h + px(10))
    if tall then rows_h = min(3, max(0, floor((bh * 0.56) / row_h))) * row_h end
    local num_room = (tall and (bh - rows_h - px(10)) or bh) - small_h
    if num_room < c:text("0", fpx(44), { bold = true }).h then
        -- short: no average line
        small_h = small_h - (t_avg and (t_avg.h + px(8)) or 0)
        t_avg = nil
        num_room = (tall and (bh - rows_h - px(10)) or bh) - small_h
    end
    local num_h = min(num_room, px(90))
    local block_h = num_h + small_h
    local yy = by + floor(((tall and (bh - rows_h - px(10)) or bh) - block_h) / 2)
    local used = bigNumber(bx, yy, lw, num_h)
    yy = yy + min(used, num_h) + px(4)
    if t_avg then c:put(t_avg, bx, yy); yy = yy + t_avg.h + px(8) end
    bar(bx, yy, lw, bar_h); yy = yy + bar_h + px(6)
    if t_go then c:put(t_go, bx, yy) end

    -- the rows
    local rx, ry, rw, rh
    if tall then
        rx, ry, rw, rh = bx, by + bh - rows_h, bw, rows_h
    else
        rx, rw = bx + lw + px(30), bw - lw - px(30)
        ry, rh = by, bh
    end
    local nrows = min(#rows, floor(rh / row_h))
    -- the short names for every row when a full one leaves its figure too
    -- little room (with the pills' own padding)
    local spare = (look == "worm") and floor(row_h * 0.8) + px(30) or px(30)
    for _, r in ipairs(rows) do
        local nm = c:text(r[1], fpx(19), { bold = true, serif = serif, italic = serif })
        local vl = c:text(r[4] and A.thousands(r[4]) or "0", fpx(22), { bold = true, serif = serif })
        if nm.w + vl.w + spare > rw then short = true end
    end
    if rw > px(80) and nrows > 0 then
        local g = tall and 0 or min(px(14), floor((rh - nrows * row_h) / max(1, nrows + 1)))
        local total = nrows * row_h + (nrows - 1) * g
        local y0 = ry + floor((rh - total) / 2)
        for i = 1, nrows do row(i, rows[i], rx, y0 + (i - 1) * (row_h + g), rw, row_h) end
    end
    return c
end

return true
