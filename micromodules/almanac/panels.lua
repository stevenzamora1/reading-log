--[[
Reading Log panels: one builder per card.

A builder takes `env` and returns a Canvas:
  env.w, env.h      the box to fill, in pixels
  env.tone          resolved card colours (see A.tone)
  env.ts            text-size multiplier (1 = normal; small text gets it all, see boost)
  env.cfg(key, d)   this card's saved setting
  env.refresh       call to redraw this card after a background read lands
  env.nested        true inside the dashboard (panel keeps its own rectangle)
  env.native        on its own in a Bookshelf grid: Bookshelf's card is the
                    card (no frame of our own; see A.nativeTone)
  env.slot          which saved set a slotted card uses (tbr / deadline)

Sizes are worked out from the box: `s` is how big the box is against the
card's reference design, and every length is a reference length times `s`.
]]

local A = ...
local T = A._
local D = A.D
local P = {}
A.panels = P
A.state = A.state or {}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local round = A.round

-- Smallest text worth drawing: about 1.2 mm on the screen in hand.
local function minFont()
    return max(9, floor(A.screen():scaleBySize(13) / 2))
end

-- How much of the text-size boost a font of reference size n gets: all of it
-- for small text (labels, captions, axis figures: the text that is hard to
-- read on e-ink), none for big text (titles, clock, big figures, which are
-- already easy to read and would otherwise crowd everything else off the
-- card), in between on a slope.
local function boost(n, ts)
    ts = ts or 1
    return 1 + (ts - 1) * A.clamp((36 - n) / 16, 0, 1)
end
A.textBoost = boost

-- Returns px(n) for lengths and fpx(n) for font sizes, both scaled by s.
local function scaler(s, ts)
    local floor_px = minFont()
    return function(n) return max(1, floor(n * s + 0.5)) end,
           function(n) return max(floor_px, floor(n * s * boost(n, ts) + 0.5)) end
end

local function card(env, s)
    local radius = max(4, round(32 * s))
    radius = min(radius, floor(min(env.w, env.h) / 4))
    if env.native then
        -- Bookshelf's card is the card: nothing drawn under the content,
        -- or a soft frameless panel for the tinted styles.
        return A.canvas{ w = env.w, h = env.h, tone = env.tone, radius = radius,
            plain = not env.tone.panel, bleed = env.bleed }
    end
    return A.canvas{
        w = env.w, h = env.h, tone = env.tone, radius = radius,
        border_w = env.tone.border and (env.tone.border_thin and max(1, round(2 * s)) or max(2, round(4 * s))) or 0,
        bleed = env.bleed and not env.nested,
        page = env.page,
    }
end

-- Two centred lines for a card with nothing to show yet.
local function emptyState(env, c, s, heading, line1, line2)
    local _, fpx = scaler(s, env.ts)
    local tone = env.tone
    local pad = round(36 * s)
    if heading then
        c:label(heading, fpx(22), pad, round(26 * s), { bold = true, caps = true, color = tone.accent, max_w = env.w - 2 * pad })
    end
    local t1 = c:text(line1, fpx(30), { bold = true, color = tone.fg, max_w = env.w - 2 * pad })
    local t2 = line2 and c:textbox(line2, fpx(22), env.w - 2 * pad, 2, { color = tone.muted, align = "center" }) or nil
    local total = t1.h + (t2 and (t2.h + round(6 * s)) or 0)
    local y = floor((env.h - total) / 2) + (heading and round(10 * s) or 0)
    c:put(t1, env.w / 2, y, "c")
    if t2 then c:put(t2, (env.w - t2.w) / 2, y + t1.h + round(6 * s)) end
    return c
end

local function monthLetter(m)
    return A.i18n.monthLetter(m)
end

local function shortMonth(m)
    return A.date("%b", os.time{ year = 2024, month = m, day = 15, hour = 12 })
end

-- The month the Monthly cards show: this one, or one the reader stepped back
-- to with the arrows on the Monthly page (A.state.month_offset, 0 to -12).
-- Returns year, month, whether it is this month.
function A.viewMonth()
    local off = A.clamp(floor(tonumber(A.state.month_offset) or 0), -(D.BACK_MONTHS or 12), 0)
    local t = os.date("*t")
    local vt = os.date("*t", os.time{ year = t.year, month = t.month + off, day = 1, hour = 12 })
    return vt.year, vt.month, off == 0
end

-- "September", or "September 2025" for a month of another year.
function A.monthTitle(y, m)
    local name = A.date("%B", os.time{ year = y, month = m, day = 15, hour = 12 })
    if y ~= tonumber(os.date("%Y")) then name = name .. " " .. y end
    return name
end

-- ════════════════════════════════════════════════════════════════════════════
-- Banner: clock, date, and a two-line name for the library
-- ════════════════════════════════════════════════════════════════════════════

P.banner = {
    does = T("flashes the screen clean"),
    title = T("Banner"), tone = "ink", ratio = 0.19, ratio_narrow = 0.42, tick = true,
    summary = T("Clock, date and your library's name, or today's reading at a glance. Works offline."),
}

-- Tapping the clock flashes the whole screen once: the manual cure for
-- ghosting, wherever it came from.
function P.banner.tap() A.cleanScreen() end

-- The time as text, and "PM" (or nil) for a twelve-hour clock.
local function clockText(now)
    if G_reader_settings and G_reader_settings:isTrue("twelve_hour_clock") then
        return (os.date("%I:%M", now):gsub("^0", "")), os.date("%p", now)
    end
    return os.date("%H:%M", now), nil
end

-- Three looks, picked in the card's settings (Style):
--   heading  (default) like the Yearly and Monthly page headings: the date as
--            a small accent line over the time in big bold type, your two
--            lines the same way on the right. On the Dashboard it sits
--            straight on the page, with no card round it.
--   glance   the time and date, with today's pages, minutes and streak
--   classic  thin digits, a divider, serif lines
function P.banner.build(env)
    local style = env.cfg("style", "heading")
    if style == "classic" then return P.banner.classic(env) end
    if style == "glance" then return P.banner.glance(env) end
    return P.banner.heading(env)
end

function P.banner.heading(env)
    local w, h = env.w, env.h
    local s = min(h / 170, w / 700)
    local px, fpx = scaler(s, env.ts)
    local c, fg, accent, muted
    if env.nested then
        local page_bg, page_fg, _, page_accent = A.dashPage()
        fg, accent = page_fg, page_accent
        c = A.canvas{ w = w, h = h, plain = true }
        muted = A.mix(page_bg, page_fg, 0.72)
    else
        c = card(env, s)
        fg, accent, muted = env.tone.fg, env.tone.accent, env.tone.muted
    end
    local pad = env.nested and 0 or px(36)
    local now = os.time()
    local time_str, suffix = clockText(now)
    local kicker = A.date("%A", now) .. "  \xE2\x80\xA2  " .. tonumber(os.date("%d", now)) .. " " .. A.date("%B", now)
    local t_k = c:text(kicker, fpx(24), { bold = true, caps = true, color = accent })
    local t_t = c:text(time_str, fpx(84), { bold = true, color = fg })
    local t_suf = suffix and c:text(suffix, fpx(30), { bold = true, color = muted }) or nil
    local tight = round(t_t.h * 0.14)
    local block = t_k.h + t_t.h - tight
    local y = floor((h - block) / 2)
    c:put(t_k, pad, y)
    local ty = y + t_k.h - tight
    c:put(t_t, pad - round(t_t.px * 0.03), ty)
    if t_suf then c:put(t_suf, pad + t_t.w + px(10), ty + t_t.base, "l", "base") end
    local left_w = max(t_k.w, t_t.w + (t_suf and (t_suf.w + px(10)) or 0))

    -- your two lines, right-aligned, in the same small-over-big pattern
    local line1, line2 = env.cfg("line1", ""), env.cfg("line2", "")
    local room = w - 2 * pad - left_w - px(48)
    if room > px(120) and (line1 ~= "" or line2 ~= "") then
        local t1 = line1 ~= "" and c:text(line1, fpx(24), { bold = true, caps = true, color = muted, max_w = room }) or nil
        local f2 = fpx(50)
        local t2 = line2 ~= "" and c:text(line2, f2, { bold = true, color = fg }) or nil
        if t2 and t2.w > room then
            t2 = c:text(line2, max(minFont(), floor(f2 * max(0.55, room / t2.w))), { bold = true, color = fg, max_w = room })
        end
        -- the big line sits on the clock's baseline
        local base = ty + t_t.base
        if t2 then c:put(t2, w - pad, base, "r", "base") end
        if t1 then c:put(t1, w - pad, y + t_k.base, "r", "base") end
    end
    return c
end

function P.banner.glance(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(h / 200, w / 760)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local pad = px(36)
    local now = os.time()
    local time_str, suffix = clockText(now)
    local t_k = c:text(A.date("%A", now) .. "  \xE2\x80\xA2  " .. tonumber(os.date("%d", now)) .. " " .. A.date("%b", now),
        fpx(22), { bold = true, caps = true, color = tone.accent })
    local t_t = c:text(time_str, fpx(76), { bold = true, color = tone.fg })
    local t_suf = suffix and c:text(suffix, fpx(26), { bold = true, color = tone.muted }) or nil
    local tight = round(t_t.h * 0.14)
    local y = floor((h - (t_k.h + t_t.h - tight)) / 2)
    c:put(t_k, pad, y)
    local ty = y + t_k.h - tight
    c:put(t_t, pad - round(t_t.px * 0.03), ty)
    if t_suf then c:put(t_suf, pad + t_t.w + px(8), ty + t_t.base, "l", "base") end
    local left_w = max(t_k.w, t_t.w + (t_suf and (t_suf.w + px(8)) or 0))

    -- today at a glance: pages, minutes, streak (the Activity rings' figures)
    local st
    if env.sample then st = { today = { pages = 24, secs = 1560 }, streak = 5 }
    else st = D.stats(env.refresh) end
    local vals
    if st then
        vals = {
            { A.thousands(st.today.pages or 0), (st.today.pages == 1) and T("page today") or T("pages today"), tone.accent },
            { A.fmtMinutes((st.today.secs or 0) / 60), T("read today"), tone.accent2 },
            { tostring(st.streak or 0), A.i18n.ngettext("day streak", "day streak", st.streak or 0), tone.fg },
        }
    else
        local dash = st == false and "\xE2\x80\x94" or "\xE2\x80\xA6"
        vals = { { dash, T("pages today"), tone.accent }, { dash, T("read today"), tone.accent2 }, { dash, T("day streak"), tone.fg } }
    end
    local x0 = pad + left_w + px(40)
    local area = w - pad - x0
    if area < px(200) then return c end
    local cw = area / 3
    for i, v in ipairs(vals) do
        local cx = x0 + (i - 1) * cw
        local t_l = c:text(v[2], fpx(19), { bold = true, caps = true, color = tone.muted, max_w = cw - px(12) })
        local t_v = c:text(v[1], fpx(54), { bold = true, color = tone.fg, max_w = cw - px(12) })
        local bh = t_v.h + t_l.h - round(t_v.h * 0.12)
        local by = floor((h - bh) / 2)
        -- a short bar in the figure's colour, as on the Month totals card
        c:rrect(cx, by + round(t_v.h * 0.2), max(3, px(6)), bh - round(t_v.h * 0.3), max(2, px(3)), v[3], tone.bg)
        c:put(t_v, cx + px(18), by)
        c:put(t_l, cx + px(18), by + t_v.h - round(t_v.h * 0.12))
    end
    return c
end

function P.banner.classic(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(h / 210, w / 640)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local pad = px(40)
    local now = os.time()

    local twelve = G_reader_settings and G_reader_settings:isTrue("twelve_hour_clock")
    local time_str, suffix
    if twelve then
        time_str = (os.date("%I:%M", now):gsub("^0", ""))
        suffix = os.date("%p", now)
    else
        time_str = os.date("%H:%M", now)
    end
    local date_str = A.date("%A", now) .. ", " .. tonumber(os.date("%d", now)) .. " " .. A.date("%B", now)

    local line1 = env.cfg("line1", "")
    local line2 = env.cfg("line2", "")
    local has_right = (line1 ~= "" or line2 ~= "")

    local t_time = c:text(time_str, fpx(82), { color = tone.fg })
    local t_suf = suffix and c:text(suffix, fpx(28), { color = tone.muted, bold = true }) or nil
    local t_date = c:text(date_str, fpx(27), { color = tone.accent })
    local left_w = max(t_time.w + (t_suf and (t_suf.w + px(10)) or 0), t_date.w)

    -- The big digits carry a lot of built-in leading; pull the date up under them.
    local tighten = round(t_time.h * 0.16)
    local block_h = t_time.h + t_date.h - tighten
    local y0 = floor((h - block_h) / 2) - round(t_time.h * 0.03)

    local div_x = pad + left_w + px(44)
    local right_room = w - pad - (div_x + px(40))
    local t1, t2
    if has_right and right_room > px(150) then
        local f1, f2 = fpx(44), fpx(64)
        t1 = line1 ~= "" and c:text(line1, f1, { serif = true, color = tone.fg }) or nil
        t2 = line2 ~= "" and c:text(line2, f2, { serif = true, color = tone.fg }) or nil
        local need = max(t1 and t1.w or 0, t2 and t2.w or 0)
        if need > right_room then
            -- Shrink to fit, down to a size that still reads as a title (on a
            -- tall banner that is a long way down); past that, an ellipsis.
            local k = max(0.4, right_room / need)
            f1, f2 = max(minFont(), floor(f1 * k)), max(minFont(), floor(f2 * k))
            t1 = line1 ~= "" and c:text(line1, f1, { serif = true, color = tone.fg, max_w = right_room }) or nil
            t2 = line2 ~= "" and c:text(line2, f2, { serif = true, color = tone.fg, max_w = right_room }) or nil
        end
    else
        has_right = false
    end

    local lx = pad
    if not has_right then lx = floor((w - left_w) / 2) end
    c:put(t_time, lx, y0)
    if t_suf then c:put(t_suf, lx + t_time.w + px(10), y0 + t_time.base, "l", "base") end
    c:put(t_date, lx, y0 + t_time.h - tighten)

    if has_right then
        c:rect(div_x, 0, max(2, px(3)), h, tone.accent)
        local gap = t1 and t2 and -round((t2.h) * 0.14) or 0
        local rh = (t1 and t1.h or 0) + (t2 and t2.h or 0) + gap
        local ry = floor((h - rh) / 2)
        if t1 then c:put(t1, w - pad, ry, "r"); ry = ry + t1.h + gap end
        if t2 then c:put(t2, w - pad, ry, "r") end
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Continue reading
-- ════════════════════════════════════════════════════════════════════════════

-- ─── polaroids ───────────────────────────────────────────────────────────────
-- The Polaroid look: each day's cover in a white frame with a wide bottom
-- edge (the day's time read written on it), a little crooked, like photos
-- pinned to a board.

local POLA_M, POLA_B = 0.06, 0.27           -- the frame's sides and top, and its bottom (x its width)
local POLA_RATIO = POLA_M + 1.5 * (1 - 2 * POLA_M) + POLA_B
local function polaroidOn() return A.get("calendar_look", "plain") == "polaroid" end
local function polaroidLook(tone)
    if tone.dark then
        return { frame = { 238, 236, 230 }, edge = { 170, 170, 166 }, shadow = A.mix(tone.bg, { 0, 0, 0 }, 0.6),
            caption = { 24, 24, 24 }, photo_edge = { 120, 120, 118 } }
    end
    return { frame = { 255, 255, 253 }, edge = { 204, 204, 200 }, shadow = A.mix(tone.bg, { 0, 0, 0 }, 0.16),
        caption = { 24, 24, 24 }, photo_edge = { 128, 128, 126 } }
end
-- a different tilt for each day, 2 to 4 degrees either way, never straight
local TILTS = { -4, 3, -2, 4, -3, 2 }
local function tiltFor(day, month)
    return math.rad(TILTS[((day * 7 + month * 3) % 6) + 1])
end
A.polaroidLook = polaroidLook

-- One polaroid of width pw centred on cx, cy, turned by ang.
local function polaroid(c, cx, cy, pw, ang, book, caption, f_cap, px, L)
    local m, mb = pw * POLA_M, pw * POLA_B
    local photo_w = floor(pw - 2 * m)
    local photo_h = floor(photo_w * 1.5)
    local ph = pw * POLA_RATIO
    local sh = max(1, px(3)) / pw
    c:sprite(cx, cy, pw, ang, {
        { "r", sh * 0.6, sh, 0.5, 0.5 * POLA_RATIO, 0, 0.012, L.shadow, nil },
        { "r", 0, 0, 0.5, 0.5 * POLA_RATIO, 0, 0.012, L.frame, L.edge },
    }, { lw = 1 })
    -- the photo sits a little above the middle: the bottom edge is the wide one
    local d = (mb - m) / 2
    local pcx, pcy = cx + math.sin(ang) * d, cy - math.cos(ang) * d
    c:tilted(book.fp, pcx, pcy, photo_w, photo_h, ang, { title = book.title })
    -- a fine smooth line round the photo, so its turned edge isn't stepped
    local ex, ey = 0.5, 0.5 * photo_h / photo_w
    local er = max(0.6, px(1) * 0.75) / photo_w
    c:sprite(pcx, pcy, photo_w, ang, {
        { "s", -ex, -ey, ex, -ey, er, L.photo_edge }, { "s", ex, -ey, ex, ey, er, L.photo_edge },
        { "s", ex, ey, -ex, ey, er, L.photo_edge }, { "s", -ex, ey, -ex, -ey, er, L.photo_edge },
    }, { lw = 1 })
    if caption then
        -- written on the wide bottom edge, as big as it fits
        local cd = ph / 2 - mb / 2
        local size = f_cap
        local t = c:text(caption, size, { bold = true, color = L.caption })
        while t.w > photo_w and size > minFont() do
            size = max(minFont(), floor(size * 0.9))
            t = c:text(caption, size, { bold = true, color = L.caption })
        end
        c:put(t, cx - math.sin(ang) * cd, cy + math.cos(ang) * cd, "c", "mid")
    end
    return ph
end

-- ─── the club as a garden ────────────────────────────────────────────────────
-- Each pick's progress bar grows as a stem with leaves, a bud at its tip and
-- a flower at the end once it's read; a finished book gets a dragonfly
-- sticker on its cover.

local function gardenLook(tone)
    if tone.dark then
        return { stem = { 126, 192, 120 }, leaf = { 104, 172, 104 }, leaf_line = { 160, 218, 152 },
            track = A.mix(tone.bg, tone.fg, 0.22), petal = { 255, 160, 204 }, petal_line = { 255, 112, 176 },
            middle = { 255, 210, 90 }, middle_line = { 214, 150, 40 },
            wing = { 226, 244, 248 }, wing_line = { 70, 140, 160 }, body = { 40, 140, 160 }, body_line = { 18, 76, 96 },
            sticker = { 255, 255, 255 } }
    end
    return { stem = { 92, 156, 88 }, leaf = { 120, 178, 110 }, leaf_line = { 66, 124, 70 },
        track = tone.track, petal = { 240, 140, 182 }, petal_line = { 196, 60, 124 },
        middle = { 250, 200, 70 }, middle_line = { 200, 140, 30 },
        wing = { 218, 240, 244 }, wing_line = { 60, 128, 150 }, body = { 30, 122, 142 }, body_line = { 14, 70, 90 },
        sticker = { 255, 255, 255 } }
end

local function dragonflyParts(L)
    local W, WL, B, BL = L.wing, L.wing_line, L.body, L.body_line
    local rad = math.rad
    return {
        { "e", -0.40, -0.11, 0.40, 0.10, rad(8), W, WL },     -- forewings
        { "e", 0.40, -0.11, 0.40, 0.10, rad(-8), W, WL },
        { "e", -0.35, 0.07, 0.35, 0.095, rad(-14), W, WL },  -- hind wings
        { "e", 0.35, 0.07, 0.35, 0.095, rad(14), W, WL },
        { "e", 0, 0.45, 0.05, 0.40, 0, B, BL },               -- tail
        { "e", 0, -0.02, 0.085, 0.13, 0, B, BL },             -- thorax
        { "e", 0, -0.21, 0.105, 0.085, 0, B, BL },            -- head
    }
end

local function bloomParts(L)
    local parts = {}
    for k = 0, 4 do
        local a = math.rad(-90 + k * 72)
        parts[#parts + 1] = { "e", 0.34 * math.cos(a), 0.34 * math.sin(a), 0.34, 0.24, a, L.petal, L.petal_line }
    end
    parts[#parts + 1] = { "e", 0, 0, 0.2, 0.2, 0, L.middle, L.middle_line }
    return parts
end

local function budParts(L)
    local rad = math.rad
    return {
        { "e", 0.08, 0, 0.36, 0.22, 0, L.petal, L.petal_line },                 -- the bud, pointing right
        { "v", -0.18, 0, 0.42, 0.12, rad(-28), L.leaf, L.leaf_line, false },    -- and the leaves round its base
        { "v", -0.18, 0, 0.42, 0.12, rad(28), L.leaf, L.leaf_line, false },
    }
end

local function sproutParts(L)
    local rad = math.rad
    return {
        { "s", 0, 0.3, 0, -0.05, 0.06, L.stem },
        { "v", 0, -0.02, 0.55, 0.17, rad(-145), L.leaf, L.leaf_line, true },
        { "v", 0, -0.02, 0.62, 0.19, rad(-35), L.leaf, L.leaf_line, true },
    }
end

-- A pick's progress as a stem along x..x+w, in a row of height h from y.
local function gardenStem(c, x, y, w, h, pct, finished, px, L)
    local sy = y + h * 0.62                    -- the stem's line, a little below the middle
    local amp = max(1, px(3))
    local period = max(20, px(70))
    local bloom_r = floor(h * 0.48)
    local grow = w - bloom_r - px(4)
    local tip = x + grow * (finished and 1 or A.clamp(pct, 0, 1))
    local function wave(from, to, lw, col)
        if to - from < 1 then return end
        local pts = {}
        local steps = max(2, floor((to - from) / max(2, px(4))))
        for k = 0, steps do
            local xx = from + (to - from) * k / steps
            pts[#pts + 1] = xx
            pts[#pts + 1] = sy + amp * math.sin((xx - x) / period * 2 * math.pi)
        end
        c:polyline(pts, lw, col)
    end
    local function yAt(xx) return sy + amp * math.sin((xx - x) / period * 2 * math.pi) end
    -- where it will grow, faintly
    wave(tip, x + grow, max(1, px(2)), L.track)
    if pct <= 0 and not finished then
        local sz = h * 0.85
        c:sprite(x + sz * 0.45, sy - sz * 0.28, sz, 0, sproutParts(L), { lw = max(1, px(2)) })
        return
    end
    wave(x, tip, max(2, px(5)), L.stem)
    -- leaves along what has grown, one up, one down
    local step = max(px(30), floor(h * 0.85))
    local leaf = h * 0.55
    local up = true
    local lx = x + px(14)
    while lx < tip - px(14) do
        local turn = up and math.rad(-48) or math.rad(48)
        c:sprite(lx, yAt(lx), leaf, 0, { { "v", 0, 0, 1, 0.34, turn, L.leaf, L.leaf_line, true } }, { lw = max(1, px(2)) })
        lx = lx + step
        up = not up
    end
    if finished then
        c:sprite(x + w - bloom_r, yAt(x + grow) - bloom_r * 0.35, bloom_r * 2, 0, bloomParts(L), { lw = max(1, px(2)) })
    else
        local bud = h * 0.85
        c:sprite(tip + bud * 0.3, yAt(tip), bud, 0, budParts(L), { lw = max(1, px(2)) })
    end
end

-- A dragonfly sticker on the top right of a finished book's cover.
local function dragonflySticker(c, x, y, cover_w, cover_h, px, L)
    local size = max(px(24), cover_w * 0.34)
    c:sprite(x + cover_w - size * 0.62, y + size * 0.62, size, math.rad(35), dragonflyParts(L),
        { lw = max(1, px(2)), halo = max(2, px(4)), halo_col = L.sticker })
end
A.gardenLook, A.dragonflyParts = gardenLook, dragonflyParts

-- ─── charts: book spines on a shelf, hills with hearts ───────────────────────
-- The cozy chart look: each bar is a book standing on a wooden shelf (pastel,
-- two bands near its ends, the best one with a heart on top), and each line
-- has a soft hill under it, hearts on its points and a flower on the last.

local function cozyOn() return A.get("chart_look", "plain") == "cozy" end
local SPINES = { { 244, 170, 192 }, { 168, 204, 236 }, { 188, 224, 186 }, { 248, 212, 148 }, { 206, 186, 236 },
    { 246, 190, 158 } }
local WOOD, WOOD_EDGE = { 200, 154, 106 }, { 146, 104, 66 }
local function spineColour(i, tone)
    local p = SPINES[(i - 1) % #SPINES + 1]
    return tone.dark and A.mix(tone.bg, p, 0.72) or p
end
local function cozyHeart(tone)
    if tone.dark then return { 255, 136, 187 }, { 255, 200, 224 } end
    return { 236, 110, 160 }, { 176, 36, 98 }
end
-- the shelf the books stand on: x..x+w, its top at y; returns its thickness
local function shelf(c, x, y, w, px, tone)
    local th = max(4, px(9))
    c:rrect(x - px(4), y, w + px(8), th, max(1, px(2)), tone.dark and A.mix(tone.bg, WOOD, 0.72) or WOOD)
    c:rect(x - px(4), y + th - max(1, px(2)), w + px(8), max(1, px(2)), WOOD_EDGE)
    return th
end
-- one book standing at x with its foot on `base`, bw wide and bh tall
local function spineUp(c, x, base, bw, bh, col, px)
    if bh < 1 or bw < 1 then return end
    local top = base - bh
    local r = max(1, min(px(4), floor(min(bw, bh) * 0.2)))
    if bw >= 5 and bh >= 5 then
        c:frame(x, top, bw, bh, r, 1, A.mix(col, { 0, 0, 0 }, 0.3), col)
    else
        c:rect(x, top, bw, bh, col)
    end
    -- two thin bands near the ends, where there's room for them
    local band = A.mix(col, { 0, 0, 0 }, 0.24)
    local bt = max(1, px(2))
    if bw >= max(5, px(8)) then
        local inset = max(px(5), floor(bh * 0.12))
        if bh >= px(28) then
            c:rect(x + 1, top + inset, bw - 2, bt, band)
            c:rect(x + 1, base - inset - bt, bw - 2, bt, band)
        elseif bh >= px(14) then
            c:rect(x + 1, top + floor(bh * 0.3), bw - 2, bt, band)
        end
    end
end
-- one book lying flat from x, len long and th thick (the compare card)
local function spineFlat(c, x, y, len, th, col, px)
    if len < 1 or th < 1 then return end
    local r = max(1, min(px(4), floor(min(len, th) * 0.2)))
    c:frame(x, y, len, th, r, 1, A.mix(col, { 0, 0, 0 }, 0.3), col)
    local band = A.mix(col, { 0, 0, 0 }, 0.24)
    local bt = max(1, px(2))
    if len >= px(40) then
        local inset = max(px(6), floor(len * 0.05))
        c:rect(x + inset, y + 1, bt, th - 2, band)
        c:rect(x + len - inset - bt, y + 1, bt, th - 2, band)
    end
end
-- a heart sitting on top of a bar centred at cx whose top is y
local function bestHeart(c, cx, y, size, tone, px)
    local fill, line = cozyHeart(tone)
    c:heart(cx, y - size * 0.5 - max(1, px(2)), size, size, { outer = 1, line = line, fill = fill, track = fill,
        t = max(1, px(2)) })
end
-- a soft hill under a line: pts = { x1, y1, x2, y2, ... }, down to `bottom`
local function hill(c, pts, bottom, col)
    local n = floor(#pts / 2)
    if n < 2 then return end
    for i = 1, 2 * n - 2, 2 do
        local xa, ya, xb, yb = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        local x0, x1 = floor(xa + 0.5), floor(xb + 0.5)
        for x = x0, x1 - 1 do
            local t = (xb > xa) and ((x + 0.5 - xa) / (xb - xa)) or 0
            local y = floor(ya + (yb - ya) * t + 0.5)
            if bottom - y > 0 then c:rect(x, y, 1, bottom - y, col) end
        end
    end
end
-- a heart on a point of a line
local function pointHeart(c, x, y, size, col, px)
    c:heart(x, y, size, size, { outer = 1, line = A.mix(col, { 0, 0, 0 }, 0.3), fill = col, track = col,
        t = max(1, px(2)) })
end
A.cozyOn = cozyOn

-- ─── Continue reading as a scrapbook ─────────────────────────────────────────
-- The cover as a polaroid taped to the card, and the progress bar as a vine.

local function scrapOn() return A.get("continue_look", "classic") == "scrapbook" end
local function scrapLook(tone)
    local L = polaroidLook(tone)
    L.tape, L.tape_line = { 248, 206, 220 }, { 226, 160, 186 }
    if tone.dark then L.tape, L.tape_line = { 214, 150, 176 }, { 240, 190, 210 } end
    return L
end

-- The scrapbook cover in the box x, y, w, h (where the plain cover goes).
local function scrapCover(c, x, y, w, h, book, px, L)
    local ang = math.rad(-3)
    local pw = min(w * 0.98 / 1.05, h * 0.96 / (POLA_RATIO + 0.05))
    local ph = pw * POLA_RATIO
    local cx, cy = x + w / 2, y + h / 2 + px(2)
    polaroid(c, cx, cy, pw, ang, book, nil, nil, px, L)
    -- washi tape across the top
    c:sprite(cx - pw * 0.02, cy - ph / 2 + px(2), pw * 0.62, math.rad(-5),
        { { "r", 0, 0, 0.5, 0.12, 0, 0.02, L.tape, L.tape_line } }, { lw = 1 })
end

P.continue = {
    does = T("opens the book"),
    title = T("Continue reading"), tone = "paper", ratio = 0.36, ratio_narrow = 0.62,
    summary = T("Books in progress, with cover and time left. Works offline."),
}

local SAMPLE_READING = {
    { title = "Carrie", author = "Stephen King", pct = 0.20, left_min = 282 },
    { title = "The Haunting of Hill House", author = "Shirley Jackson", pct = 0.46, left_min = 190 },
}

local function readingNow(env)
    if env.sample then return SAMPLE_READING end
    return D.reading(tonumber(env.cfg("count", 5)) or 5)
end

function P.continue.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local stacked = (w / h) < 1.9
    local s = stacked and min(w / 546, h / 400) or min(h / 400, w / 760)
    local px = scaler(s, env.ts)
    local c = card(env, s)
    local list = readingNow(env)
    if #list == 0 then
        return emptyState(env, c, s, T("Continue reading"), T("Nothing in progress"),
            T("Open a book and it shows up here."))
    end
    local idx = A.clamp(tonumber(A.state.continue_idx) or 1, 1, #list)
    A.state.continue_idx = idx
    local book = list[idx]
    -- the picker's sample render must not disturb what a tap on the live card opens
    if not env.sample then A.state.continue_fp = book.fp end

    local floor_px = minFont()
    local function f(n) return max(floor_px, floor(n * s * boost(n, env.ts) + 0.5)) end
    local edge = tone.border or tone.muted
    local pct_txt = string.format("%d%%", floor(book.pct * 100 + 0.5))
    local left_txt = book.left_min and (A.fmtMinutes(book.left_min) .. T(" left")) or nil
    local scrap = scrapOn() and scrapLook(tone) or nil
    local gl = scrap and gardenLook(tone) or nil
    local bar_h = scrap and max(px(20), px(36)) or max(4, px(10))
    -- how long this book has been on the go, from the first session the
    -- statistics recorded, and the time spent reading it so far
    local days_n, book_secs
    if env.sample then
        days_n, book_secs = 12, 4 * 3600 + 25 * 60
    else
        local _
        days_n, _, book_secs = D.dayOfBook(env.refresh, book.fp)
    end
    local span_txt, time_txt
    if days_n then
        span_txt = A.plural(days_n, "day", "days") .. T(" of reading")
        if book_secs and book_secs >= 60 then time_txt = A.fmtMinutes(book_secs / 60) .. T(" read") end
    end

    -- progress bar, "20%  ...  4 h left", and the two buttons, in a column
    -- x..x+width whose bottom edge is `bottom`. Returns the y it starts at.
    local function footer(x, width, bottom, with_buttons)
        local btn_h = f(58)
        local t_pct = c:text(pct_txt, f(26), { bold = true, color = tone.fg })
        local t_left = left_txt and c:text(left_txt, f(24), { bold = true, color = tone.muted, max_w = width - t_pct.w - f(20) }) or nil
        local y_btn = bottom - btn_h
        local y_row = (with_buttons and (y_btn - px(12)) or bottom) - t_pct.h
        local y_bar = y_row - px(8) - bar_h
        if scrap then
            gardenStem(c, x, y_bar, width, bar_h, A.clamp(book.pct, 0, 1), book.pct >= 0.995, px, gl)
        else
            c:rrect(x, y_bar, width, bar_h, bar_h / 2, tone.track)
            c:rrect(x, y_bar, max(bar_h, round(width * A.clamp(book.pct, 0, 1))), bar_h, bar_h / 2, tone.btn, tone.track)
        end
        c:put(t_pct, x, y_row)
        if t_left then c:put(t_left, x + width, y_row + t_pct.base, "r", "base") end
        if with_buttons then
            local two = width >= f(28) * 13
            local bgap = px(16)
            local w1 = two and floor((width - bgap) / 2) or width
            c:rrect(x, y_btn, w1, btn_h, btn_h / 2, tone.btn)
            c:label(T("Continue"), f(28), x + w1 / 2, y_btn + btn_h / 2,
                { bold = true, color = tone.btn_fg, anchor = "c", valign = "mid" })
            c:region("open", x, y_btn, w1, btn_h, px(6))
            if two then
                local x2, w2 = x + w1 + bgap, width - w1 - bgap
                c:frame(x2, y_btn, w2, btn_h, btn_h / 2, max(2, px(4)), tone.border or tone.fg, tone.bg)
                c:label(T("Details"), f(28), x2 + w2 / 2, y_btn + btn_h / 2,
                    { bold = true, color = tone.fg, anchor = "c", valign = "mid" })
                c:region("details", x2, y_btn, w2, btn_h, px(6))
            end
        end
        return y_bar
    end

    -- "CONTINUE READING" on the left, the "1 / 3 >" pager on the right.
    -- Returns the y below the row.
    local function header(x, width, y)
        local pill_h = f(46)
        local used = 0
        if #list > 1 then
            local t_pg = c:text(string.format("%d / %d  \xE2\x80\xBA", idx, #list), f(22), { bold = true, color = tone.fg })
            local pw = t_pg.w + f(36)
            local pxx = x + width - pw
            c:frame(pxx, y, pw, pill_h, pill_h / 2, max(2, px(3)), tone.border or tone.fg, tone.bg)
            c:put(t_pg, pxx + pw / 2, y + pill_h / 2, "c", "mid")
            c:region("next", pxx, y, pw, pill_h, px(14))
            used = pw + px(14)
        end
        -- the label is the first thing to go when the column is narrow
        local t_label = c:text(T("Continue reading"), f(24), { bold = true, caps = true, color = tone.accent })
        if t_label.w <= width - used then
            c:put(t_label, x, y + pill_h / 2, "l", "mid")
        elseif used == 0 then
            c:label(T("Reading"), f(24), x, y + pill_h / 2,
                { bold = true, caps = true, color = tone.accent, valign = "mid", max_w = width })
        end
        return y + pill_h
    end

    -- "4 days of reading  ·  2 h 14 m read" as the line after one whose
    -- baseline is prev_base (font prev_px), in a column x..x+width, if its
    -- letters stay above limit_y. Lines are spaced by baseline, not by the
    -- text boxes, whose built-in leading would waste the room. Returns
    -- whether it was drawn.
    local function spanLine(x, width, prev_base, prev_px, limit_y)
        if not span_txt then return false end
        local t_a = c:text(span_txt, f(25), { bold = true, color = tone.accent2 })
        local base = prev_base + floor(max(prev_px, t_a.px) * 1.2 + 0.5)
        if base + t_a.px * 0.28 > limit_y or t_a.w > width then return false end
        c:put(t_a, x, base, "l", "base")
        if time_txt then
            local t_b = c:text("  \xC2\xB7  " .. time_txt, f(25), { bold = true, color = tone.muted })
            if t_a.w + t_b.w <= width then c:put(t_b, x + t_a.w, base, "l", "base") end
        end
        return true
    end

    if stacked then
        -- Squarer card: cover and titles on top, bar and buttons full width below.
        local pad = px(30)
        local inner = w - 2 * pad
        local y_bar = footer(pad, inner, h - pad, h >= f(58) * 5)
        local top_h = y_bar - px(18) - pad
        local cover_h = max(8, top_h)
        local cover_w = round(cover_h * 2 / 3)
        if cover_w > inner * 0.34 then
            cover_w = round(inner * 0.34)
            cover_h = round(cover_w * 1.5)
        end
        if scrap then
            scrapCover(c, pad, pad, cover_w, cover_h, book, px, scrap)
        else
            c:cover(book.fp, pad, pad, cover_w, cover_h, { title = book.title, edge = edge })
        end
        c:region("open", pad, pad, cover_w, cover_h)
        local tx = pad + cover_w + px(24)
        local tw = w - pad - tx
        local y = header(tx, tw, pad) + px(8)
        local room = pad + top_h - y
        local t_author = book.author and c:text(book.author, f(24), { color = tone.muted, max_w = tw }) or nil
        local t_title = c:textbox(book.title, f(34), tw, 2, { bold = true, color = tone.fg })
        if t_title.h + (t_author and t_author.h or 0) > room then
            t_title = c:textbox(book.title, f(34), tw, 1, { bold = true, color = tone.fg })
        end
        if t_title.h <= room then
            c:put(t_title, tx, y)
            local prev_base, prev_px = y + t_title.base, t_title.px
            if t_author and t_title.h + t_author.h <= room then
                c:put(t_author, tx, y + t_title.h)
                prev_base, prev_px = y + t_title.h + t_author.base, t_author.px
            end
            spanLine(tx, tw, prev_base, prev_px, pad + top_h)
        end
        return c
    end

    -- Wide card: cover on the left, everything else in a column beside it.
    local pad_x, pad_y = px(40), px(26)
    local cover_h = h - 2 * pad_y
    local cover_w = round(cover_h * 2 / 3)
    if scrap then
        scrapCover(c, pad_x, pad_y, cover_w, cover_h, book, px, scrap)
    else
        c:cover(book.fp, pad_x, pad_y, cover_w, cover_h, { title = book.title, edge = edge })
    end
    c:region("open", pad_x, pad_y, cover_w, cover_h)
    local tx = pad_x + cover_w + px(38)
    local tw = w - tx - pad_x
    local y = header(tx, tw, pad_y + px(4)) + px(6)
    local t_title = c:text(book.title, f(44), { bold = true, color = tone.fg })
    if t_title.w > tw then t_title = c:text(book.title, f(36), { bold = true, color = tone.fg, max_w = tw }) end
    local t_author = book.author and c:text(book.author, f(28), { color = tone.muted, max_w = tw }) or nil
    local bottom = h - pad_y
    local need = t_title.h + f(58) + f(26) * 1.4 + bar_h + px(40)
    local with_buttons = (bottom - y) >= need
    local y_bar = footer(tx, tw, bottom, with_buttons)
    c:put(t_title, tx, y)
    local prev_base, prev_px = y + t_title.base, t_title.px
    local author_y = y + t_title.h - px(8)
    if t_author and author_y + t_author.h <= y_bar - px(6) then
        c:put(t_author, tx, author_y)
        prev_base, prev_px = author_y + t_author.base, t_author.px
    end
    -- "4 days of reading  ·  2 h 14 m read" under the author; on a short card,
    -- the days alone at the right-hand end of the author's line
    if not spanLine(tx, tw, prev_base, prev_px, y_bar - px(4)) and span_txt and t_author then
        local t_a = c:text(span_txt, f(25), { bold = true, color = tone.accent2 })
        if t_author.w + px(24) + t_a.w <= tw and author_y + t_author.h <= y_bar - px(6) then
            c:put(t_a, tx + tw, prev_base, "r", "base")
        end
    end
    return c
end

function P.continue.tap(env, region)
    local fp = A.state.continue_fp
    if region == "next" then
        A.state.continue_idx = (tonumber(A.state.continue_idx) or 1) + 1
        local list = readingNow(env)
        if A.state.continue_idx > #list then A.state.continue_idx = 1 end
        return
    end
    if not fp then return end
    if region == "details" then D.showDetails(env.ctx, fp) else D.openBook(env.ctx, fp) end
end

function P.continue.keep(region) return region == "next" end
function P.continue.controls(region) return region == "open" or region == "details" or region == "next" end

-- ════════════════════════════════════════════════════════════════════════════
-- Activity rings: pages, minutes, streak
-- ════════════════════════════════════════════════════════════════════════════

P.activity = {
    does = T("opens reading progress"),
    title = T("Activity rings"), tone = "plum", ratio = 0.61, ratio_narrow = 0.61,
    summary = T("Today's pages, minutes and streak as rings. Needs the statistics plugin."),
}

local SAMPLE_STATS = {
    today = { pages = 24, secs = 1560 }, streak = 5, best = 21, week_pages = 262, week_secs = 15120,
    week = {
        { pages = 140, secs = 5400, wday = 2 }, { pages = 121, secs = 4800, wday = 3 },
        { pages = 1, secs = 120, wday = 4, today = true }, { pages = 0, secs = 0, wday = 5, future = true },
        { pages = 0, secs = 0, wday = 6, future = true }, { pages = 0, secs = 0, wday = 7, future = true },
        { pages = 0, secs = 0, wday = 1, future = true },
    },
    days = {},
}

local function statsFor(env)
    if env.sample then return SAMPLE_STATS end
    return D.stats(env.refresh)
end

-- ─── hearts instead of rings ─────────────────────────────────────────────────
-- One setting for every rings card: two hearts, one inside the other, that
-- fill up like a glass. The outer one with pages, the inner one with time.

local function hearts() return A.get("ring_shape", "rings") == "hearts" end
A.hearts = hearts

-- The colours of the two hearts (pages, time): pinks, or the card's own.
local function heartColors(tone)
    if A.get("heart_colors", "pink") ~= "pink" then return tone.series[1], tone.series[2] end
    if tone.dark then return { 255, 136, 187 }, { 255, 196, 222 } end
    return { 228, 96, 152 }, { 190, 30, 100 }
end
A.heartColors = heartColors

-- What's still empty inside a heart: lighter than a ring's track.
local function heartTrack(tone) return A.mix(tone.bg, tone.track, 0.6) end

-- Whether a day that's over gets a broken heart: when a goal was missed, or
-- only when both were.
local function heartBroken(fp, fm)
    if A.get("heart_broken", "any") == "both" then return fp < 1 and fm < 1 end
    return fp < 1 or fm < 1
end
A.heartBroken = heartBroken

-- One day's hearts in a d x d box. o = { future, past (the day is over),
-- single (no room for the inner heart) }
local function dayHeart(c, cx, cy, d, tone, fp, fm, o)
    local single = o.single
    if o.future then
        c:heart(cx, cy, d, d, { outer = 0, inner = (not single) and 0 or nil, line = tone.track, track = tone.bg })
        return
    end
    local c1, c2 = heartColors(tone)
    c:heart(cx, cy, d, d, { outer = fp, inner = (not single) and fm or nil, line = c1, line_in = c2,
        track = heartTrack(tone), broken = o.past and heartBroken(fp, fm) or nil })
end

function P.activity.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = statsFor(env)
    if st == false then
        return emptyState(env, c, s, T("Activity"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(30)
    local t_label = c:label(T("Activity"), fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent })
    c:label(T("Today"), fpx(22), w - pad, px(24), { color = tone.accent2, anchor = "r" })

    local pages = st and st.today.pages or 0
    local mins = st and floor(st.today.secs / 60 + 0.5) or 0
    local streak = st and st.streak or 0
    local page_goal = max(1, tonumber(env.cfg("page_goal", 30)) or 30)
    local min_goal = D.dailyMinutesGoal()
    local streak_goal = max(1, tonumber(env.cfg("streak_goal", 7)) or 7)

    local top = px(24) + t_label.h + px(10)
    local avail = h - top - px(22)
    local R = min(px(118), floor(avail / 2), floor(w * 0.24))
    local cx, cy = pad + R, top + floor(avail / 2)
    local t = max(3, round(R * 0.215))
    local gap = max(1, round(R * 0.055))
    local cols = tone.series
    if hearts() then
        local c1, c2 = heartColors(tone)
        cols = { c1, c2, tone.series[3] }
        c:heart(cx, cy, 2 * R, 2 * R, { outer = pages / page_goal, inner = mins / min_goal, line = c1, line_in = c2,
            track = heartTrack(tone) })
    else
        c:ring(cx, cy, R, t, pages / page_goal, tone.track, cols[1])
        c:ring(cx, cy, R - t - gap, t, mins / min_goal, tone.track, cols[2])
        c:ring(cx, cy, R - 2 * (t + gap), t, streak / streak_goal, tone.track, cols[3])
    end

    local lines = {
        st and A.plural(pages, "page", "pages") or "\xE2\x80\xA6",
        st and (A.fmtMinutes(mins) .. T(" read")) or "\xE2\x80\xA6",
        st and (streak > 0 and (T("Streak ") .. A.plural(streak, "day", "days")) or T("No streak yet")) or "\xE2\x80\xA6",
    }
    local tx = cx + R + px(34)
    local room = w - pad - tx
    local size = fpx(29)
    local texts
    for _ = 1, 3 do
        texts = {}
        local widest = 0
        for i, str in ipairs(lines) do
            texts[i] = c:text(str, size, { bold = true, color = cols[i] })
            widest = max(widest, texts[i].w)
        end
        if widest <= room or size <= minFont() then break end
        size = max(minFont(), floor(size * max(0.6, room / widest)))
    end
    local step = max(texts[1].h + px(4), px(57))
    step = min(step, floor((2 * R) / 3))
    local y = cy - step
    for i = 1, 3 do
        c:put(texts[i], tx, y + (i - 1) * step, "l", "mid")
    end
    return c
end

function P.activity.tap(env)
    D.dispatch(env.cfg("tap", "reading_progress"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Year goal
-- ════════════════════════════════════════════════════════════════════════════

P.goal = {
    does = T("nothing"),
    title = T("Year goal"), tone = "wine", ratio = 0.61, ratio_narrow = 0.61,
    summary = T("Books finished this year against your goal. Works offline."),
}

local function yearFor(env)
    if env.sample then
        return { year = os.date("*t").year, month = os.date("*t").month, total = 29, months = {}, list = {}, genres = {
            { name = T("Horror"), n = 7 }, { name = T("Literary Fiction"), n = 7 }, { name = T("Thriller"), n = 7 } } }
    end
    return D.year(env.refresh)
end

-- ─── the year goal as a jar of hearts ────────────────────────────────────────
-- One heart drops into the jar for each book finished; the jar holds the
-- year's goal. Past the goal the lid pops off and the hearts heap up over
-- the rim.

local function jarLook(tone)
    if tone.dark then
        return { glass_line = { 128, 160, 176 }, glass = A.mix(tone.bg, { 90, 124, 140 }, 0.3), shine = { 210, 230, 238 },
            lid = { 255, 136, 187 }, lid_line = { 255, 196, 222 },
            hearts = { { 255, 120, 180 }, { 255, 88, 156 }, { 255, 172, 210 } }, heart_line = { 150, 40, 90 },
            sparkle = { 255, 210, 90 } }
    end
    return { glass_line = { 146, 176, 190 }, glass = A.mix(tone.bg, { 205, 228, 238 }, 0.45), shine = { 255, 255, 255 },
        lid = { 236, 126, 176 }, lid_line = { 186, 48, 116 },
        hearts = { { 236, 110, 160 }, { 212, 62, 120 }, { 246, 162, 198 } }, heart_line = { 176, 36, 98 },
        sparkle = { 236, 170, 30 } }
end
local function jarOn() return A.get("goal_look", "number") == "jar" end
A.jarLook = jarLook

-- The rows of hearts that fit w x h, filled from the bottom: the heart size
-- and each slot's centre, n slots at least.
local function heartSlots(w, h, n)
    local hw = min(w / 2, h / 1.2)
    for _ = 1, 60 do
        local rh = hw * 0.8
        local rows = max(1, floor((h - hw) / rh) + 1)
        local cap = 0
        for j = 0, rows - 1 do
            local k = (j % 2 == 0) and floor(w / hw) or floor((w - hw / 2) / hw)
            cap = cap + max(1, k)
        end
        if cap >= n or hw < 4 then break end
        hw = hw * 0.95
    end
    local rh = hw * 0.8
    local slots = {}
    local j = 0
    while #slots < 400 do
        local y = h - hw / 2 - j * rh
        if y < hw * 0.4 then break end
        local odd = j % 2 == 1
        local k = odd and floor((w - hw / 2) / hw) or floor(w / hw)
        k = max(1, k)
        local spare = w - k * hw - (odd and hw / 2 or 0)
        for m = 0, k - 1 do
            slots[#slots + 1] = { (odd and hw / 2 or 0) + spare / 2 + m * hw + hw / 2, y }
        end
        j = j + 1
    end
    return hw, slots
end

-- A jar in the box x, y, w, h holding `done` of `target` hearts.
local function drawJar(c, x, y, w, h, done, target, px, L)
    -- a very big goal: a heart for every few books
    local per = target > 150 and math.ceil(target / 150) or 1
    local goal_n = math.ceil(target / per)
    local have = floor(done / per)
    local over = have > goal_n
    local box_top = y
    if over then
        -- room above the rim for the heap and the lid
        y, h = y + floor(h * 0.2), h - floor(h * 0.2)
    end
    local bw = max(2, px(4))
    local lid_h = max(px(10), floor(h * 0.085))
    local neck_w = floor(w * 0.74)
    local neck_x = x + floor((w - neck_w) / 2)
    local neck_top = y + floor(lid_h * 0.6)
    local body_top = y + lid_h + max(px(6), floor(h * 0.04))
    local body_h = y + h - body_top
    local r = floor(w * 0.17)
    c:frame(neck_x, neck_top, neck_w, body_top - neck_top + bw, max(2, px(5)), bw, L.glass_line, L.glass)
    c:frame(x, body_top, w, body_h, r, bw, L.glass_line, L.glass)
    c:rect(neck_x + bw, body_top, neck_w - 2 * bw, bw, L.glass)
    -- a shine down the glass
    local sx = x + bw + max(2, floor(w * 0.1))
    c:polyline({ sx, body_top + r * 0.8, sx, body_top + body_h * 0.62 }, max(2, px(4)), L.shine)
    c:polyline({ sx, body_top + body_h * 0.7, sx, body_top + body_h * 0.76 }, max(2, px(4)), L.shine)
    -- the hearts, from the bottom
    local ipad = max(1, px(4))
    local ix, iy = x + bw + ipad, body_top + bw + ipad
    local iw, ih = w - 2 * (bw + ipad), body_h - 2 * (bw + ipad)
    local hw, slots = heartSlots(iw, ih, goal_n)
    local function heartAt(cx, cy, i)
        -- a little out of line, like a real pile
        local jx = ((i * 37) % 11 - 5) / 5 * hw * 0.06
        local jy = ((i * 53) % 7 - 3) / 3 * hw * 0.05
        local col = L.hearts[(i * 7) % 3 + 1]
        c:heart(cx + jx, cy + jy, hw * 0.98, hw * 0.98, { outer = 1, line = L.heart_line, fill = col, track = col,
            t = max(1, hw * 0.07) })
    end
    local n_in = min(have, #slots)
    for i = 1, n_in do heartAt(ix + slots[i][1], iy + slots[i][2], i) end
    -- past the goal: the hearts heap up over the rim, the lid off to one side
    local heaped = 0
    if over and have > #slots then
        local extra = have - #slots
        local rh = hw * 0.8
        local base = body_top - hw * 0.1
        local k = max(1, floor((neck_w - 2 * bw) / hw))
        local row = 0
        while extra > 0 and k >= 1 and base - row * rh - hw * 0.45 >= box_top do
            local cy = base - row * rh
            local x0 = x + w / 2 - k * hw / 2 + hw / 2
            for m = 0, k - 1 do
                if extra <= 0 then break end
                heaped = heaped + 1
                heartAt(x0 + m * hw, cy, n_in + heaped)
                extra = extra - 1
            end
            row = row + 1
            k = k - 1
        end
    end
    local lid_w = floor(w * 0.82)
    if over then
        -- the lid, popped off and resting on the heap
        c:sprite(x + w * 0.2, y - h * 0.03, floor(w * 0.7), math.rad(-22),
            { { "e", 0, 0, 0.5, 0.13, 0, L.lid, L.lid_line } }, { lw = max(1, px(3)) })
    else
        local lx = x + floor((w - lid_w) / 2)
        c:frame(lx, y, lid_w, lid_h, max(2, px(5)), max(1, px(3)), L.lid_line, L.lid)
        for k = 1, 5 do
            local gx = lx + floor(lid_w * k / 6)
            c:rect(gx, y + floor(lid_h * 0.25), max(1, px(2)), floor(lid_h * 0.5), L.lid_line)
        end
    end
    if have >= goal_n then
        local sz = w * 0.5
        c:sprite(x + w / 2, y + h * 0.45, sz, 0, {
            { "*", 1.12, -0.7, 0.16, L.sparkle }, { "*", -1.12, -0.35, 0.11, L.sparkle }, { "*", 1.05, 0.25, 0.08, L.sparkle },
        })
    end
end

function P.goal.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local strip = (w / h) > 2.6
    local s = strip and min(h / 200, w / 620) or min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local yr = yearFor(env)
    local t = os.date("*t")
    local pad = px(32)
    local jar = jarOn()
    local strip_jw = 0
    if jar and strip then strip_jw = min(floor((h - px(30)) * 0.72), floor(w * 0.16)) + px(30) end
    local t_label = c:label(tostring(t.year) .. T(" goal"), fpx(22), pad + strip_jw, px(22), { bold = true, caps = true, color = tone.accent })

    local target, other = D.yearGoal()
    if env.sample then target, other = 36, 0 end
    local done = (yr and yr.total or 0) + other

    local status
    local yday = tonumber(os.date("%j"))
    local leap = (t.year % 4 == 0 and (t.year % 100 ~= 0 or t.year % 400 == 0))
    local expected = target * yday / (leap and 366 or 365)
    local diff = done - expected
    if not yr then
        status = "\xE2\x80\xA6"
    elseif done > target then
        status = A.tr("Goal reached, +%1", done - target)
    elseif done >= target then
        status = T("Goal reached")
    elseif diff >= 1 then
        status = A.plural(floor(diff), "book", "books") .. T(" ahead")
    elseif diff <= -1 then
        status = A.plural(ceil(-diff), "book", "books") .. T(" behind")
    else
        status = T("On track")
    end

    local top = px(22) + t_label.h
    -- the jar on the left, everything else beside it
    local lx = pad
    if jar then
        local jy = strip and px(14) or (top + px(6))
        local jh = h - jy - px(16)
        local jw = min(floor(jh * 0.72), floor(w * (strip and 0.16 or 0.36)))
        jh = min(jh, floor(jw / 0.72))
        drawJar(c, pad, jy + floor((h - px(16) - jy - jh) / 2), jw, jh, done, target, px, jarLook(tone))
        lx = pad + jw + px(30)
    end
    local pill_h = fpx(56)
    local big_px = fpx(strip and 120 or (lx > pad and 120 or 150))
    local big = c:text(yr and tostring(done) or "\xE2\x80\xA6", big_px, { bold = true, color = tone.fg })
    local of_txt = T("of ") .. A.plural(target, "book", "books")

    -- where the pill goes, and the band the number is centred in
    local pill_x, pill_y, pill_w, band_bottom
    if strip then
        pill_w = min(floor(w * 0.42), px(420))
        pill_x, pill_y = w - pad - pill_w, floor((h - pill_h) / 2)
        band_bottom = h - px(10)
    else
        pill_x, pill_w = lx, w - pad - lx
        pill_y = h - px(26) - pill_h
        band_bottom = pill_y
        -- no room for both: the number wins
        if pill_y < top + big.h * 0.62 then pill_y, band_bottom = nil, h - px(10) end
    end

    local by = top + floor((band_bottom - top - big.h) / 2) - round(big.h * 0.02)
    c:put(big, lx - round(big_px * 0.04), by)
    local ox = lx + big.w + px(16)
    local limit = (strip and pill_x - px(16)) or (w - pad + px(8))
    local t_of = c:text(of_txt, fpx(28), { color = tone.accent2 })
    if ox + t_of.w > limit then t_of = c:text("/ " .. target, fpx(28), { color = tone.accent2 }) end
    if ox + t_of.w <= limit then
        c:put(t_of, ox, by + big.base - round(big_px * 0.02), "l", "base")
    end
    if pill_y then
        c:rrect(pill_x, pill_y, pill_w, pill_h, pill_h / 2, tone.btn)
        -- a smaller size before it gets cut short
        local size = fpx(26)
        for _ = 1, 3 do
            local probe = c:text(status, size, { bold = true, color = tone.btn_fg })
            if probe.w <= pill_w - px(30) or size <= minFont() then break end
            size = max(minFont(), floor(size * 0.88))
        end
        local t_st = c:text(status, size, { bold = true, color = tone.btn_fg, max_w = pill_w - px(30) })
        c:put(t_st, pill_x + pill_w / 2, pill_y + pill_h / 2, "c", "mid")
    end
    return c
end

-- A titled row of covers with a caption under each: the TBR shelf and the
-- recently-finished card. A very wide, short box moves the title to a column
-- on the left so the covers can use the full height.
--   o = { title=, dots=bool, counter=, counter_color=, tagline=, items=, max_n=, prefix= }
--   items[i] = { fp=, title=, label=, strong=bool }
-- Returns the files shown, in order (for the tap handler).
local function coverShelf(env, c, s, o)
    local w, h, tone = env.w, env.h, env.tone
    local px, fpx = scaler(s, env.ts)
    local pad = px(36)
    local items = o.items
    local probe = c:text("Ag", fpx(19), { bold = true })
    local has_labels = false
    for _, it in ipairs(items) do if it.label then has_labels = true end end
    local label_h = has_labels and (probe.h + px(10)) or px(6)
    local tagline = o.tagline or ""
    local area_x, area_w, top, avail_h

    if (w / h) > 3.4 then
        local lw = floor(w * 0.27)
        local y = px(24)
        local t_title = c:textbox(o.title, fpx(26), lw - pad, 2, { bold = true, caps = true, color = tone.fg })
        c:put(t_title, pad, y)
        y = y + t_title.h + px(6)
        if o.counter then
            local t = c:label(o.counter, fpx(24), pad, y, { bold = true, color = o.counter_color or tone.accent2, max_w = lw - pad })
            y = y + t.h + px(6)
        end
        if tagline ~= "" then
            local t_tag = c:textbox(tagline, fpx(20), lw - pad, 2, { color = tone.muted })
            if y + t_tag.h <= h - px(16) then c:put(t_tag, pad, y) end
        end
        area_x, area_w = lw + px(8), w - lw - px(8) - pad
        top = px(20)
        avail_h = h - top - label_h - px(16)
    else
        local hy = px(28)
        local t_title = c:text(o.title, fpx(26), { bold = true, caps = true, color = tone.fg, max_w = w * 0.6 })
        local tx = pad
        if o.dots then
            local dot = max(3, px(8))
            c:disc(pad + dot, hy + t_title.h / 2, dot, tone.accent)
            tx = pad + 2 * dot + px(12)
            c:disc(tx + t_title.w + px(12) + dot, hy + t_title.h / 2, dot, tone.accent)
        end
        c:put(t_title, tx, hy)
        if o.counter then
            c:label(o.counter, fpx(24), w - pad, hy + t_title.base,
                { bold = true, color = o.counter_color or tone.accent2, anchor = "r", valign = "base" })
        end
        local t_tag = tagline ~= "" and c:text(tagline, fpx(24), { bold = true, caps = true, color = tone.fg, max_w = w - 2 * pad }) or nil
        if t_tag then c:put(t_tag, w / 2, h - px(20) - t_tag.h, "c") end
        area_x, area_w = pad, w - 2 * pad
        top = hy + t_title.h + px(20)
        avail_h = h - top - label_h - (t_tag and (t_tag.h + px(14)) or 0) - px(20)
    end

    if #items == 0 then
        local cy = top + avail_h / 2
        local t1 = c:text(o.empty or T("Nothing here yet"), fpx(28), { bold = true, color = tone.fg, max_w = area_w })
        c:put(t1, area_x + area_w / 2, cy - t1.h / 2, "c")
        if o.empty_hint then
            c:label(o.empty_hint, fpx(22), area_x + area_w / 2, cy + t1.h / 2 + px(4),
                { color = tone.muted, anchor = "c", max_w = area_w })
        end
        return {}
    end
    if avail_h < 24 then return {} end

    local n = min(#items, o.max_n or 6)
    local gap = px(26)
    local min_cw = max(px(56), A.screen():scaleBySize(32))
    local ch = floor(avail_h)
    local cw = round(ch / 1.5)
    local fit_w = floor((area_w - (n - 1) * gap) / n)
    if fit_w < cw then
        if fit_w < min_cw then
            -- too many to show at a readable size: show fewer, not smaller
            n = A.clamp(floor((area_w + gap) / (min_cw + gap)), 1, n)
            fit_w = floor((area_w - (n - 1) * gap) / n)
        end
        cw = min(cw, fit_w)
        ch = round(cw * 1.5)
    end
    if n > 1 then gap = min(px(80), floor((area_w - n * cw) / (n - 1))) end
    local x0 = area_x + floor((area_w - (n * cw + (n - 1) * gap)) / 2)
    local cy0 = top + floor((avail_h - ch) / 2)
    local files = {}
    for i = 1, n do
        local b = items[i]
        local x = x0 + (i - 1) * (cw + gap)
        c:cover(b.fp, x, cy0, cw, ch, { title = b.title, edge = tone.border or tone.bg })
        if b.label then
            c:label(b.label, fpx(19), x + cw / 2, cy0 + ch + px(10),
                { bold = true, caps = true, anchor = "c", max_w = cw + gap * 0.8,
                  color = b.strong and tone.accent2 or tone.muted })
        end
        files[i] = b.fp or false
        c:region((o.prefix or "book:") .. i, x, cy0, cw, ch + label_h, px(4))
    end
    return files
end

-- ════════════════════════════════════════════════════════════════════════════
-- Shelf of covers from a collection (the "October TBR" card)
-- ════════════════════════════════════════════════════════════════════════════

P.tbr = {
    does = T("opens the book tapped"),
    title = T("TBR shelf"), tone = "paper", ratio = 0.41, ratio_narrow = 0.6, slots = true,
    summary = T("A row of covers from one of your collections. Works offline."),
}

-- Which collection the shelf shows: the chosen one, else a likely TBR.
function P.tbr.collection(env)
    local names, fav = D.collections()
    local want = env.cfg("coll", "")
    for _, n in ipairs(names) do if n == want then return n end end
    local month = os.date("%B"):lower()
    local best
    for _, n in ipairs(names) do
        local l = n:lower()
        if l:find("tbr", 1, true) and l:find(month, 1, true) then return n end
        if not best and (l:find("tbr", 1, true) or l:find("to be read", 1, true) or l:find("to read", 1, true)) then
            best = n
        end
    end
    return best or fav or names[1]
end

local function tbrBooks(env)
    if env.sample then
        local out = {}
        for i, t in ipairs{ "Carrie", "Needless Street", "Wayward Girls", "Ask for Andrea", "Come Closer", "HEX" } do
            out[i] = { title = t, label = (i == 1 or i == 5) and T("Digital") or T("Hardcopy"), strong = not (i == 1 or i == 5) }
        end
        return out, 6, T("October TBR")
    end
    local coll = P.tbr.collection(env)
    local files = coll and D.collection(coll) or {}
    local hard = env.cfg("hardcopy", "Hardcopy")
    local names = D.collections()
    local has_hard = false
    for _, n in ipairs(names) do if n == hard then has_hard = true end end
    local mode = env.cfg("labels", "auto")
    if mode == "auto" then mode = (has_hard and hard ~= coll) and "format" or "status" end
    local out, todo = {}, 0
    for _, fp in ipairs(files) do
        local pct, status = D.progress(fp)
        if status ~= "finished" then todo = todo + 1 end
        local info = D.info(fp)
        local label, strong
        if mode == "format" then
            strong = D.inCollection(hard, fp)
            label = strong and T("Hardcopy") or T("Digital")
        elseif mode == "none" then
            label = nil
        elseif status == "finished" then
            label, strong = T("Read"), true
        elseif pct and pct > 0 then
            label, strong = string.format("%d%%", floor(pct * 100 + 0.5)), true
        else
            label = T("To read")
        end
        out[#out + 1] = { fp = fp, title = info.title, label = label, strong = strong }
    end
    return out, todo, coll
end

function P.tbr.build(env)
    local w, h = env.w, env.h
    local s = min(h / 460, w / 900)
    if (w / h) > 3.4 then s = min(h / 300, w / 900) end
    local c = card(env, s)
    local books, todo, coll = tbrBooks(env)
    local title = env.cfg("title", "")
    if title == "" then
        title = env.sample and T("October TBR") or (A.date("%B") .. T(" TBR"))
    end
    local tagline = env.sample and T("It's spooky season") or env.cfg("tagline", "")
    local name = coll and D.collectionLabel(coll) or T("a collection")
    local files = coverShelf(env, c, s, {
        title = title, dots = true, counter = todo .. T(" to read"), tagline = tagline,
        items = books, max_n = A.clamp(tonumber(env.cfg("count", 6)) or 6, 2, 10),
        empty = T("No books here yet"), empty_hint = T("Add some to \xE2\x80\x9C") .. name .. "\xE2\x80\x9D.",
    })
    if not env.sample then A.state["tbr_files_" .. tostring(env.slot or 1)] = files end
    return c
end

function P.tbr.tap(env, region)
    local i = region and tonumber(region:match("^book:(%d+)$"))
    local files = A.state["tbr_files_" .. tostring(env.slot or 1)]
    local fp = i and files and files[i]
    if not fp then return end
    if env.cfg("tap", "open") == "details" then D.showDetails(env.ctx, fp) else D.openBook(env.ctx, fp) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- Top genres of the year
-- ════════════════════════════════════════════════════════════════════════════

P.genres = {
    does = T("nothing"),
    title = T("Top genres"), tone = "plum", ratio = 0.25, ratio_narrow = 0.52,
    summary = T("The genres you finished most this year. Works offline."),
}

function P.genres.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local rows = A.clamp(tonumber(env.cfg("count", 3)) or 3, 2, 6)
    local s = min(h / (104 + 57 * rows), w / 760)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local yr = yearFor(env)
    local pad = px(38)
    local t_head = c:label(T("Top genres"), fpx(22), pad, px(26), { bold = true, caps = true, color = tone.accent })
    local year = yr and yr.year or os.date("*t").year
    local sub = c:text(T("books finished in ") .. year, fpx(22), { bold = true, color = tone.muted })
    if pad + t_head.w + px(30) + sub.w <= w - pad then c:put(sub, w - pad, px(26), "r") end

    local list = yr and yr.genres or {}
    if yr == nil then
        c:label("\xE2\x80\xA6", fpx(30), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted })
        return c
    end
    if #list == 0 then
        c:label(T("Finish a book this year to see your genres"), fpx(24), w / 2, h / 2 + px(10),
            { anchor = "c", valign = "mid", color = tone.muted, max_w = w - 2 * pad })
        return c
    end
    rows = min(rows, #list)
    local top = px(26) + t_head.h + px(12)
    local area = h - top - px(22)
    local row_h = min(px(60), floor(area / rows))
    local y0 = top + floor((area - rows * row_h) / 2)
    local count_w = px(64)
    local name_w = min(floor(w * 0.32), px(330))
    local bx = pad + name_w
    local bmax = w - pad - count_w - bx
    local bar_h = max(4, px(14))
    local top_n = max(1, list[1].n)
    for i = 1, rows do
        local g = list[i]
        local col = tone.series[((i - 1) % #tone.series) + 1]
        local cy = y0 + (i - 1) * row_h + row_h / 2
        c:label(g.name, fpx(28), pad, cy, { bold = true, color = tone.fg, valign = "mid", max_w = name_w - px(16) })
        c:rrect(bx, cy - bar_h / 2, max(bar_h, round(bmax * g.n / top_n)), bar_h, bar_h / 2, col)
        c:label(tostring(g.n), fpx(26), w - pad, cy, { bold = true, color = col, anchor = "r", valign = "mid" })
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Year in covers: a stack of what you finished, month by month
-- ════════════════════════════════════════════════════════════════════════════

P.year_covers = {
    does = T("shows the book tapped (elsewhere: opens the reading calendar)"),
    title = T("Year in covers"), tone = "ink", ratio = 0.34, ratio_narrow = 0.7,
    summary = T("Every cover you finished this year, in the order you finished them. Works offline."),
}

-- The grid that shows n covers (2:3) biggest in a W x H area, `gap` apart
-- side by side, each row with a label lane `lane` px tall above it (the lane
-- is the space between rows). Returns rows, columns, cover width.
local function coverGrid(n, W, H, gap, lane)
    local best_r, best_c, best_w = 1, max(1, n), 0
    for rows = 1, min(max(1, n), 12) do
        local cols = ceil(n / rows)
        local cw = (W - (cols - 1) * gap) / cols
        local ch = (H - rows * lane) / rows
        local k = min(cw, ch / 1.5)
        if k > best_w then best_r, best_c, best_w = rows, cols, k end
    end
    return best_r, best_c, floor(best_w)
end

-- Layouts: "wall" (default) = every cover of the year as big as the card
-- allows, oldest first, with the month named where each month starts;
-- "months" = the earlier look, a small stack of covers over each month.
function P.year_covers.build(env)
    if env.cfg("layout", "wall") == "months" then return P.year_covers.months(env) end
    local w, h, tone = env.w, env.h, env.tone
    local s = min(h / 380, w / 640)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local yr = yearFor(env)
    if yr and yr.total == 0 and not env.sample then
        return emptyState(env, c, s, T("Year in covers"), T("No books finished yet"),
            T("Each book you finish this year adds its cover here."))
    end
    local pad = px(36)
    local t_head = c:label(T("Year in covers"), fpx(22), pad, px(26), { bold = true, caps = true, color = tone.accent })
    c:label(yr and (yr.total .. T(" finished")) or "\xE2\x80\xA6", fpx(24), w - pad, px(26) + t_head.base,
        { bold = true, color = tone.fg, anchor = "r", valign = "base" })
    if not yr then return c end

    -- oldest first, so the wall reads like the year: left to right, top down
    local all = {}
    if env.sample then
        local now_m = os.date("*t").month
        for m = 1, now_m do
            for _ = 1, (m % 3) + 1 do all[#all + 1] = { month = m } end
        end
    else
        for i = #yr.list, 1, -1 do all[#all + 1] = yr.list[i] end
    end

    local top = px(26) + t_head.base + px(14)
    local W, H = w - 2 * pad, h - top - px(22)
    local gap = max(2, px(10))
    -- room for a month name in capitals above each row
    local lane = round(fpx(19) * 0.74) + px(10)
    -- smallest cover worth showing: about 4 mm across on the screen in hand
    local min_cw = max(px(46), A.screen():scaleBySize(24))
    -- Too many to show at a readable size: the newest that fit, after a tile
    -- counting the rest.
    local n = #all
    local shown, more = n, 0
    local rows, cols, cw = coverGrid(n, W, H, gap, lane)
    if cw < min_cw and n > 1 then
        local per_row = max(1, floor((W + gap) / (min_cw + gap)))
        local fit_rows = max(1, floor(H / (lane + min_cw * 1.5)))
        shown = A.clamp(per_row * fit_rows - 1, 1, n - 1)
        more = n - shown
        rows, cols, cw = coverGrid(shown + 1, W, H, gap, lane)
    end
    cw = max(8, cw)
    local ch = floor(cw * 1.5)
    local cells = shown + (more > 0 and 1 or 0)
    cols = min(cols, cells)
    local block_w = cols * cw + (cols - 1) * gap
    local block_h = rows * (lane + ch)
    local x0 = pad + floor((W - block_w) / 2)
    local y0 = top + floor((H - block_h) / 2)
    local now = os.date("*t")
    local files = {}

    local function cell(i)
        local r, col = floor((i - 1) / cols), (i - 1) % cols
        return x0 + col * (cw + gap), y0 + r * (lane + ch) + lane, col
    end

    local k = 0
    if more > 0 then
        k = 1
        local x, y = cell(1)
        c:rrect(x, y, cw, ch, max(2, px(6)), tone.track)
        local t_n = c:text("+" .. more, fpx(cw > px(70) and 34 or 26), { bold = true, color = tone.fg, max_w = cw - 4 })
        local t_e = c:text(T("earlier"), fpx(19), { bold = true, color = tone.label })
        if t_e.w > cw - 4 then t_e = c:text(T("more"), fpx(17), { bold = true, color = tone.label }) end
        if t_e.w > cw - 4 then t_e = nil end
        local ty = y + floor((ch - t_n.h - (t_e and t_e.h or 0)) / 2)
        c:put(t_n, x + cw / 2, ty, "c")
        if t_e then c:put(t_e, x + cw / 2, ty + t_n.h, "c") end
    end
    local prev_m
    for j = more + 1, n do
        k = k + 1
        local it = all[j]
        local x, y, col = cell(k)
        c:cover(it.fp, x, y, cw, ch, { title = it.title, edge = tone.border or tone.bg })
        -- name the month where it starts, and again at the start of a row
        if it.month ~= prev_m or col == 0 then
            local is_now = (it.month == now.month)
            local fresh = it.month ~= prev_m
            local color = is_now and tone.accent or (fresh and tone.label or tone.muted)
            local room = cw + gap - px(6)
            local t = c:text(shortMonth(it.month), fpx(19), { bold = true, caps = true, color = color })
            if t.w > room then t = c:text(monthLetter(it.month), fpx(19), { bold = true, color = color }) end
            c:put(t, x, y - px(6), "l", "base")
        end
        prev_m = it.month
        if it.fp then
            files[k] = it.fp
            c:region("book:" .. k, x, y, cw, ch, px(3))
        end
    end
    if not env.sample then A.state.year_cover_files = files end
    return c
end

function P.year_covers.months(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(h / 380, w / 860)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local yr = yearFor(env)
    local pad = px(36)
    local t_head = c:label(T("Year in covers"), fpx(22), pad, px(26), { bold = true, caps = true, color = tone.accent })
    c:label(yr and (yr.total .. T(" finished")) or "\xE2\x80\xA6", fpx(24), w - pad, px(26) + t_head.base,
        { bold = true, color = tone.fg, anchor = "r", valign = "base" })

    local t_letter = c:text("M", fpx(22), { color = tone.muted })
    local base_y = h - px(22) - t_letter.h - px(22)
    c:rect(pad, base_y, w - 2 * pad, max(1, px(2)), A.mix(tone.bg, tone.accent, 0.8))

    local col_w = (w - 2 * pad) / 12
    local stack_w = floor(min(col_w * 0.74, px(74)))
    local t_count = c:text("8", fpx(22), { bold = true })
    local top_y = px(26) + t_head.h + px(8) + t_count.h + px(6)
    local max_h = base_y - px(3) - top_y
    local now_m = os.date("*t").month

    local max_n = 1
    local months = yr and yr.months or {}
    for m = 1, 12 do max_n = max(max_n, months[m] and #months[m] or 0) end
    local ch = round(stack_w * 1.5)
    local sl = max(3, round(ch * 0.21))
    local need = ch + (max_n - 1) * sl
    if need > max_h then
        local k = max_h / need
        ch = max(6, floor(ch * k))
        sl = max(2, floor(sl * k))
    end

    for m = 1, 12 do
        local cx = pad + (m - 1) * col_w + col_w / 2
        local is_now = (m == now_m)
        c:label(monthLetter(m), fpx(22), cx, base_y + px(14),
            { anchor = "c", color = is_now and tone.accent or tone.label, bold = true })
        if is_now then c:disc(cx, base_y + px(14) + t_letter.h + px(8), max(2, px(4)), tone.accent) end
        local list = months[m]
        if list and #list > 0 then
            local n = #list
            local sh = ch + (n - 1) * sl
            local x = floor(cx - stack_w / 2)
            local y = base_y - px(3) - sh
            c:cover(list[1].fp, x, y, stack_w, ch, { title = list[1].title, edge = tone.bg, top = true })
            for j = 2, n do
                local sy = y + ch + (j - 2) * sl
                c:cover(list[j].fp, x, sy, stack_w, sl, { edge = tone.bg, border = false })
                c:rect(x, sy, stack_w, 1, tone.bg)
            end
            c:label(tostring(n), fpx(22), cx, y - px(6) - t_count.h, { anchor = "c", bold = true, color = tone.accent })
        end
    end
    return c
end

function P.year_covers.tap(env, region)
    local i = region and tonumber(region:match("^book:(%d+)$"))
    local files = A.state.year_cover_files
    local fp = i and files and files[i]
    if fp then return D.showDetails(env.ctx, fp) end
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- This week, day by day
-- ════════════════════════════════════════════════════════════════════════════

P.week = {
    does = T("opens the reading calendar"),
    title = T("This week"), tone = "ink", ratio = 0.61, ratio_narrow = 0.61,
    summary = T("Pages or minutes read each day this week. Needs the statistics plugin."),
}

local DAY_LETTERS = {}
for day = 1, 7 do DAY_LETTERS[day] = A.i18n.dayLetter(day) end

function P.week.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = statsFor(env)
    if st == false then
        return emptyState(env, c, s, T("This week"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(30)
    local by_minutes = env.cfg("metric", "pages") == "minutes"
    local t_head = c:label(T("This week"), fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent })
    local total
    if not st then total = "\xE2\x80\xA6"
    elseif by_minutes then total = A.fmtMinutes(st.week_secs / 60)
    else total = A.plural(st.week_pages, "page", "pages") end
    c:label(total, fpx(24), w - pad, px(24) + t_head.base, { bold = true, color = tone.fg, anchor = "r", valign = "base" })

    local t_day = c:text("M", fpx(20), { bold = true })
    local cozy = cozyOn()
    local shelf_th = cozy and max(4, px(9)) or 0
    local base_y = h - px(22) - t_day.h - px(8) - shelf_th
    local top = px(24) + t_head.h + px(18)
    local area = max(4, base_y - top)
    local col_w = (w - 2 * pad) / 7
    local bar_w = max(4, floor(col_w * (cozy and 0.56 or 0.5)))
    local week = st and st.week or {}
    local top_v = 1
    local best_i, best_v = nil, 0
    for i = 1, 7 do
        local d = week[i]
        if d then
            local v = by_minutes and d.secs or d.pages
            top_v = max(top_v, v)
            if v > best_v then best_i, best_v = i, v end
        end
    end
    local heart_s = min(max(bar_w * 0.8, px(16)), px(32))
    if cozy then
        area = area - heart_s - px(2)
        shelf(c, pad, base_y, w - 2 * pad, px, tone)
    end
    for i = 1, 7 do
        local d = week[i] or { pages = 0, secs = 0, wday = ((D.weekStart() + i - 2) % 7) + 1, future = true }
        local v = by_minutes and d.secs or d.pages
        local cx = pad + (i - 1) * col_w + col_w / 2
        local x = floor(cx - bar_w / 2)
        if cozy then
            if v > 0 then
                local bh = min(area, max(px(10), round(area * v / top_v)))
                spineUp(c, x, base_y, bar_w, bh, d.today and tone.accent or spineColour(i, tone), px)
                if i == best_i then bestHeart(c, cx, base_y - bh, heart_s, tone, px) end
            end
        else
            local bh = v > 0 and max(bar_w, round(area * v / top_v)) or max(3, px(6))
            bh = min(bh, area)
            local col = v <= 0 and tone.track or (d.today and tone.accent or tone.accent2)
            c:rrect(x, base_y - bh, bar_w, bh, min(bar_w / 2, px(10)), col)
        end
        c:label(DAY_LETTERS[d.wday] or "", fpx(20), cx, base_y + shelf_th + px(8),
            { anchor = "c", bold = true, color = d.today and tone.accent or tone.label })
    end
    return c
end

function P.week.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Reading heatmap
-- ════════════════════════════════════════════════════════════════════════════

P.heatmap = {
    does = T("opens the reading calendar"),
    title = T("Reading heatmap"), tone = "plum", ratio = 0.27, ratio_narrow = 0.6,
    summary = T("A square for every day, brighter the more you read. Needs the statistics plugin."),
}

function P.heatmap.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(h / 300, w / 700)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = statsFor(env)
    if st == false then
        return emptyState(env, c, s, T("Reading heatmap"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(36)
    local t_head = c:label(T("Reading heatmap"), fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent })
    if st then
        local info = T("Streak ") .. st.streak .. T("  \xC2\xB7  Best ") .. st.best
        local t_info = c:text(info, fpx(22), { bold = true, color = tone.muted })
        if pad + t_head.w + px(24) + t_info.w <= w - pad then c:put(t_info, w - pad, px(24), "r") end
    end

    local t_m = c:text(shortMonth(3), fpx(17), { color = tone.muted })
    local grid_top = px(24) + t_head.h + px(8) + t_m.h + px(4)
    local grid_h = h - grid_top - px(24)
    local g = max(2, px(5))
    local cell = floor((grid_h - 6 * g) / 7)
    if cell < 3 then return c end
    local label_w = t_m.w + px(10)
    local weeks = floor((w - 2 * pad - label_w + g) / (cell + g))
    weeks = A.clamp(weeks, 4, 26)
    -- spread the columns across the width
    local gx = g
    if weeks > 1 then
        gx = min(g * 3, floor((w - 2 * pad - label_w - weeks * cell) / (weeks - 1)))
        gx = max(g, gx)
    end
    local grid_w = weeks * cell + (weeks - 1) * gx
    local x0 = pad + label_w + floor((w - 2 * pad - label_w - grid_w) / 2)

    local t = os.date("*t")
    local ws = D.weekStart()
    local back = (t.wday - ws) % 7
    local days = st and st.days or {}

    -- levels from the spread of the days on show
    local vals = {}
    local first_off = -((weeks - 1) * 7 + back)
    for off = first_off, 0 do
        local key = os.date("%Y-%m-%d", os.time{ year = t.year, month = t.month, day = t.day + off, hour = 12 })
        local d = days[key]
        if d and d.secs > 0 then vals[#vals + 1] = d.secs end
    end
    table.sort(vals)
    local function q(p) return vals[max(1, ceil(#vals * p))] or 0 end
    local q1, q2, q3 = q(0.25), q(0.5), q(0.75)
    local shades = {
        tone.track, A.mix(tone.track, tone.accent, 0.38), A.mix(tone.track, tone.accent, 0.62),
        A.mix(tone.track, tone.accent, 0.82), tone.accent,
    }
    local r = max(1, floor(cell * 0.22))
    local last_month
    for col = 0, weeks - 1 do
        local x = x0 + col * (cell + gx)
        for row = 0, 6 do
            local off = first_off + col * 7 + row
            if off <= 0 then
                local dt = os.time{ year = t.year, month = t.month, day = t.day + off, hour = 12 }
                local key = os.date("%Y-%m-%d", dt)
                local d = days[key]
                local v = d and d.secs or 0
                local lvl = 1
                if v > 0 then
                    if v <= q1 then lvl = 2 elseif v <= q2 then lvl = 3 elseif v <= q3 then lvl = 4 else lvl = 5 end
                end
                local y = grid_top + row * (cell + g)
                if off == 0 then
                    c:frame(x - 2, y - 2, cell + 4, cell + 4, r + 2, max(1, px(2)), tone.fg, shades[lvl])
                else
                    c:rrect(x, y, cell, cell, r, shades[lvl])
                end
                if row == 0 then
                    local mo = tonumber(os.date("%m", dt))
                    if mo ~= last_month then
                        if last_month ~= nil or tonumber(os.date("%d", dt)) <= 7 then
                            c:label(shortMonth(mo), fpx(18), x, grid_top - t_m.h - px(4), { bold = true, color = tone.label })
                        end
                        last_month = mo
                    end
                end
            end
        end
    end
    for _, row in ipairs{ 0, 2, 4, 6 } do
        local wd = ((ws - 1 + row) % 7) + 1
        c:label(DAY_LETTERS[wd], fpx(18), pad, grid_top + row * (cell + g) + cell / 2,
            { bold = true, color = tone.label, valign = "mid" })
    end
    return c
end

function P.heatmap.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Recently finished
-- ════════════════════════════════════════════════════════════════════════════

P.finished = {
    does = T("shows the book tapped"),
    title = T("Recently finished"), tone = "wine", ratio = 0.36, ratio_narrow = 0.6,
    summary = T("The last few books you finished this year. Works offline."),
}

function P.finished.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(h / 400, w / 860)
    if (w / h) > 3.4 then s = min(h / 300, w / 900) end
    local c = card(env, s)
    local yr = yearFor(env)
    local list = yr and yr.list or {}
    if env.sample then
        list = {}
        for i, tt in ipairs{ "Our Wives Under the Sea", "The Starless Sea", "Dark Matter", "Educated" } do
            list[i] = { title = tt, month = 10 - floor(i / 2), day = 3 * i }
        end
    end
    local items = {}
    for i, b in ipairs(list) do
        items[i] = { fp = b.fp, title = b.title, label = b.day .. " " .. shortMonth(b.month), strong = true }
    end
    local files = coverShelf(env, c, s, {
        title = T("Recently finished"), counter = yr and (yr.total .. T(" this year")) or nil,
        counter_color = tone.fg, items = items,
        max_n = A.clamp(tonumber(env.cfg("count", 6)) or 6, 2, 10),
        empty = yr == nil and "\xE2\x80\xA6" or T("Nothing finished yet this year"),
    })
    if not env.sample then A.state.finished_files = files end
    return c
end

function P.finished.tap(env, region)
    local i = region and tonumber(region:match("^book:(%d+)$"))
    local fp = i and A.state.finished_files and A.state.finished_files[i]
    if fp then D.showDetails(env.ctx, fp) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- Longest reads: the books that took longest, this year or this month
-- ════════════════════════════════════════════════════════════════════════════
-- Ranked by reading time (or by days, from the first session to the day the
-- book was marked finished). Each row: cover, title, a bar against the
-- longest, the ranking figure large and the other one small.

local function longestCard(period)
    local def = {
        does = T("shows the book tapped"),
        title = period == "month" and T("Longest reads (month)") or T("Longest reads (year)"),
        tone = period == "month" and "tint2" or "tint", ratio = 0.62, ratio_narrow = 0.75,
        summary = period == "month"
            and T("The books you finished this month that took longest, by reading time or days. Needs the statistics plugin.")
            or T("The books you finished this year that took longest, by reading time or days. Needs the statistics plugin."),
    }
    local state_key = "longest_files_" .. period

    local SAMPLE = {
        { title = "The Starless Sea", author = "Erin Morgenstern", secs = 61200, span = 34, read_days = 21 },
        { title = "A Little Life", author = "Hanya Yanagihara", secs = 50400, span = 41, read_days = 26 },
        { title = "Piranesi", author = "Susanna Clarke", secs = 19800, span = 9, read_days = 6 },
        { title = "Educated", author = "Tara Westover", secs = 16200, span = 12, read_days = 8 },
    }

    function def.build(env)
        local w, h, tone = env.w, env.h, env.tone
        local s = min(w / 546, h / 400)
        local px, fpx = scaler(s, env.ts)
        local c = card(env, s)
        local now = os.date("*t")
        local by = env.cfg("by", "time")
        local vy, vm = A.viewMonth()
        local when = period == "month" and A.monthTitle(vy, vm) or tostring(now.year)
        local rows
        if env.sample then
            rows = SAMPLE
        elseif period == "month" then
            rows = D.longest(env.refresh, vm, by, vy)
        else
            rows = D.longest(env.refresh, nil, by)
        end
        if rows == false then
            return emptyState(env, c, s, T("Longest reads"), T("No reading statistics"),
                T("Turn on KOReader's Reading statistics plugin."))
        end
        local pad = px(28)
        local t_head = c:label(T("Longest reads"), fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent })
        local t_when = c:text(when, fpx(21), { bold = true, color = tone.muted })
        if pad + t_head.w + px(16) + t_when.w <= w - pad then
            c:put(t_when, w - pad, px(22) + t_head.base, "r", "base")
        end
        local top = px(22) + t_head.h + px(14)
        if not rows then return c end
        if #rows == 0 then
            local msg = period == "month" and (T("Nothing finished in ") .. when) or T("Nothing finished this year yet")
            c:label(msg, fpx(24), w / 2, top + (h - top) / 2, { anchor = "c", valign = "mid", color = tone.muted, max_w = w - 2 * pad })
            return c
        end

        -- What one full row needs: title, bar, then author and second figure.
        local probe_t = c:text("Ag", fpx(22), { bold = true })
        local probe_s = c:text("Ag", fpx(19))
        local bar_h = max(3, px(8))
        local full_row = probe_t.h + px(12) + bar_h + px(8) + probe_s.h
        -- As many rows as fit at a readable height, no more than asked for,
        -- and no taller than a full row: spare room goes to a total underneath.
        local want = A.clamp(tonumber(env.cfg("count", 3)) or 3, 1, 6)
        local t_foot = c:text("Ag", fpx(19))
        local avail = h - top - px(20)
        local min_row = px(64)
        local gap = px(14)
        local n = min(want, #rows, max(1, floor((avail + gap) / (min_row + gap))))
        local row_h = A.clamp(floor((avail - gap * (n - 1)) / n), min_row, full_row)
        local show_foot = (avail - n * row_h - (n - 1) * gap) >= t_foot.h + px(16)
        local cover_h = row_h
        local cover_w = floor(cover_h * 0.66)
        local x_text = pad + cover_w + px(18)
        local text_w = w - pad - x_text
        local function fig(r)
            if by == "days" then return r.span end
            return r.secs
        end
        local top_v = 0
        for i = 1, n do top_v = max(top_v, fig(rows[i]) or 0) end
        top_v = max(top_v, 1)
        local files = {}
        for i = 1, n do
            local r = rows[i]
            local y = top + (i - 1) * (row_h + gap)
            files[i] = r.fp
            c:cover(r.fp, pad, y, cover_w, cover_h, { title = r.title, edge = tone.muted })
            local big = by == "days" and A.plural(r.span, "day", "days") or A.fmtMinutes((r.secs or 0) / 60)
            local small = by == "days" and A.fmtMinutes((r.secs or 0) / 60) or A.plural(r.span, "day", "days")
            local t_big = c:text(big, fpx(26), { bold = true, color = tone.accent })
            local t_small = c:text(small, fpx(19), { bold = true, color = tone.muted })
            -- title on the first line, the figures to its right
            local t_title = c:text(r.title or "", fpx(22), { bold = true, color = tone.fg,
                max_w = max(px(40), text_w - t_big.w - px(14)) })
            c:put(t_title, x_text, y + px(2))
            c:put(t_big, w - pad, y + px(2) + t_title.base, "r", "base")
            -- A bar against the longest. Under it, the author and the second
            -- figure; in a short row the second figure goes beside the bar.
            local bar_y = y + px(2) + t_title.h + px(10)
            local sub_y = bar_y + bar_h + px(8)
            local roomy = sub_y + t_small.h <= y + row_h + px(4)
            local bar_w = roomy and text_w or (text_w - t_small.w - px(14))
            if bar_y + bar_h <= y + row_h and bar_w > px(30) then
                c:rrect(x_text, bar_y, bar_w, bar_h, bar_h / 2, tone.track)
                local fw = max(bar_h, floor(bar_w * (fig(r) or 0) / top_v))
                c:rrect(x_text, bar_y, fw, bar_h, bar_h / 2, tone.accent)
                if not roomy then c:put(t_small, w - pad, bar_y + bar_h / 2, "r", "mid") end
            end
            if roomy then
                local author = (r.author and r.author ~= "") and c:text(r.author, fpx(19), { color = tone.muted,
                    max_w = max(px(40), text_w - t_small.w - px(14)) }) or nil
                if author then c:put(author, x_text, sub_y) end
                c:put(t_small, w - pad, sub_y, "r")
            end
            c:region("book:" .. i, pad, y, w - 2 * pad, row_h)
        end
        if show_foot then
            -- the whole period: how many books, how much reading in them
            local secs = 0
            for _, r in ipairs(rows) do secs = secs + (r.secs or 0) end
            local line = A.plural(#rows, "book", "books") .. T(" finished  \xC2\xB7  ")
                .. A.fmtMinutes(secs / 60) .. T(" read in them")
            c:label(line, fpx(19), pad, h - px(20), { valign = "base", color = tone.muted, max_w = w - 2 * pad })
        end
        if not env.sample then A.state[state_key] = files end
        return c
    end

    function def.tap(env, region)
        local i = region and tonumber(region:match("^book:(%d+)$"))
        local fp = i and A.state[state_key] and A.state[state_key][i]
        if fp then D.showDetails(env.ctx, fp) end
    end
    return def
end

P.longest_year = longestCard("year")
P.longest_month = longestCard("month")

-- ════════════════════════════════════════════════════════════════════════════
-- Finish by: a real book against a date (a library loan, say)
-- ════════════════════════════════════════════════════════════════════════════

P.deadline = {
    does = T("opens its book"),
    title = T("Finish by"), tone = "wine", ratio = 0.61, ratio_narrow = 0.61, slots = true,
    summary = T("Pages a day to finish a book by a date. Works offline."),
}

function P.deadline.state(env)
    local fp = env.cfg("book", "")
    local y, m, d = A.parseYmd(env.cfg("due", ""))
    if fp == "" or not y then return nil end
    local t = os.date("*t")
    local today = A.dayNumber(t.year, t.month, t.day)
    local due = A.dayNumber(y, m, d)
    local sy, sm, sd = A.parseYmd(env.cfg("since", ""))
    local since = sy and A.dayNumber(sy, sm, sd) or today
    local pct, status, pages = D.progress(fp)
    pct = A.clamp(tonumber(pct) or 0, 0, 1)
    if status == "finished" then pct = 1 end
    local info = D.info(fp)
    local days_left = due - today
    local st = {
        fp = fp, title = info.title, label = env.cfg("label", T("Finish by")),
        pct = pct, pages = tonumber(pages), days_left = days_left,
        due_txt = d .. " " .. shortMonth(m), done = pct >= 0.995,
    }
    local span = max(1, due - since)
    st.expected = A.clamp((today - since) / span, 0, 1)
    local divisor = max(1, days_left + 1) -- today still counts
    if st.pages and st.pages > 0 then
        st.per_day = ceil(st.pages * (1 - pct) / divisor)
        st.unit = T("pages a day")
    else
        st.per_day = ceil(100 * (1 - pct) / divisor)
        st.unit = T("% a day")
    end
    return st
end

function P.deadline.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st
    if env.sample then
        st = { title = "Piranesi", label = T("Library loan"), pct = 0.71, days_left = 12, due_txt = T("21 Oct"),
               expected = 0.6, per_day = 7, unit = T("pages a day") }
    else
        st = P.deadline.state(env)
    end
    if not st then
        return emptyState(env, c, s, T("Finish by"), T("Pick a book and a date"),
            T("Long-press this card, then Module settings."))
    end
    if not env.sample then A.state["deadline_fp_" .. tostring(env.slot or 1)] = st.fp end
    local pad = px(32)
    local head = st.label ~= "" and st.label or T("Finish by")
    head = (head:lower() == T("finish by")) and (T("Finish by ") .. st.due_txt) or (head .. T("  \xC2\xB7  due ") .. st.due_txt)
    local t_head = c:label(head, fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent, max_w = w - 2 * pad })
    local t_title = c:label(st.title, fpx(32), pad, px(24) + t_head.h + px(4), { bold = true, color = tone.fg, max_w = w - 2 * pad })

    local pill_h = fpx(52)
    local pill_y = h - px(24) - pill_h
    local bar_h = max(4, px(12))
    local bar_y = pill_y - px(18) - bar_h
    local top = px(24) + t_head.h + px(4) + t_title.h
    local big_txt, unit_txt
    if st.done then big_txt, unit_txt = T("Done"), ""
    elseif st.days_left < 0 then big_txt, unit_txt = tostring(-st.days_left), (st.days_left == -1 and T("day over") or T("days over"))
    elseif st.days_left == 0 then big_txt, unit_txt = T("Today"), ""
    else big_txt, unit_txt = tostring(st.days_left), (st.days_left == 1 and T("day left") or T("days left")) end
    local room = bar_y - px(6) - top
    local big_px = min(fpx(92), floor(room * 0.8))
    local big = c:text(big_txt, big_px, { bold = true, color = tone.fg })
    local by = top + floor((room - big.h) / 2)
    c:put(big, pad - round(big_px * 0.04), by)
    local ux = pad + big.w + px(14)
    if unit_txt ~= "" then
        c:label(unit_txt, fpx(26), ux, by + big.base - round(big_px * 0.02), { color = tone.accent2, valign = "base" })
    end
    if not st.done and st.days_left >= 0 then
        local t_rate = c:text(tostring(st.per_day), fpx(40), { bold = true, color = tone.fg })
        local t_unit = c:text(st.unit, fpx(20), { bold = true, color = tone.muted })
        local rx = w - pad
        if rx - max(t_rate.w, t_unit.w) > ux + px(150) * (unit_txt ~= "" and 1 or 0.2) then
            local ry = by + floor((big.h - t_rate.h - t_unit.h) / 2) + px(4)
            c:put(t_rate, rx, ry, "r")
            c:put(t_unit, rx, ry + t_rate.h - px(4), "r")
        end
    end

    local bwid = w - 2 * pad
    c:rrect(pad, bar_y, bwid, bar_h, bar_h / 2, tone.track)
    c:rrect(pad, bar_y, max(bar_h, round(bwid * st.pct)), bar_h, bar_h / 2, tone.accent, tone.track)
    if not st.done then
        local mx = pad + round(bwid * st.expected)
        c:rect(mx - 1, bar_y - px(5), max(2, px(3)), bar_h + px(10), tone.fg)
    end

    local status
    if st.done then status = T("Finished")
    elseif st.days_left < 0 then status = T("Past due  \xC2\xB7  ") .. floor(st.pct * 100 + 0.5) .. T("% read")
    elseif st.pct + 0.02 >= st.expected then status = T("On pace  \xC2\xB7  ") .. floor(st.pct * 100 + 0.5) .. T("% read")
    else status = T("Behind  \xC2\xB7  ") .. floor(st.pct * 100 + 0.5) .. T("% read") end
    c:rrect(pad, pill_y, bwid, pill_h, pill_h / 2, tone.btn)
    c:label(status, fpx(24), w / 2, pill_y + pill_h / 2,
        { bold = true, color = tone.btn_fg, anchor = "c", valign = "mid", max_w = bwid - px(30) })
    return c
end

function P.deadline.tap(env)
    local fp = A.state["deadline_fp_" .. tostring(env.slot or 1)]
    if fp then D.openBook(env.ctx, fp) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- Book club: this month's picks from one collection, and how much of the
-- whole list is read
-- ════════════════════════════════════════════════════════════════════════════

P.bookclub = {
    does = T("opens the pick tapped"),
    title = T("Book club"), tone = "ink", ratio = 0.27, ratio_narrow = 0.62,
    summary = T("This month's picks from your book club collection, and how many are read. Works offline."),
}

-- The collection that holds the club's books: the chosen one, else one named
-- like "bookclub 2026" (this year's first), else any "book club" collection.
function P.bookclub.collection(env)
    local names = D.collections()
    local want = env.cfg("coll", "")
    for _, n in ipairs(names) do if n == want then return n end end
    local year = tostring(os.date("*t").year)
    local best
    for _, n in ipairs(names) do
        local squashed = (n:lower():gsub("[%s%-_]", ""))
        if squashed:find("bookclub", 1, true) then
            if n:find(year, 1, true) then return n end
            best = best or n
        end
    end
    return best
end

-- "YYYY-MM" for the month `offset` months from now.
function P.bookclub.monthKey(offset)
    local t = os.date("*t")
    local when = os.time{ year = t.year, month = t.month + (offset or 0), day = 1, hour = 12 }
    return os.date("%Y-%m", when), when
end

-- Every book in the collection with its progress, and this month's picks.
-- Picks are the ones ticked in the settings for this month; until some are
-- ticked, whatever from the collection is being read right now stands in.
function P.bookclub.state(env)
    local coll = P.bookclub.collection(env)
    if not coll then return nil end
    local files = D.collection(coll) or {}
    local by_fp, books, done = {}, {}, 0
    for i, fp in ipairs(files) do
        local pct, status = D.progress(fp)
        pct = A.clamp(tonumber(pct) or 0, 0, 1)
        local finished = status == "finished"
        if finished then done = done + 1 end
        local info = D.info(fp)
        books[i] = {
            fp = fp, title = info.title, author = info.author,
            pct = finished and 1 or pct, finished = finished,
            started = status == "reading" or (pct > 0 and pct < 0.995),
        }
        by_fp[fp] = books[i]
    end
    local all = env.cfg("picks", nil)
    local chosen = type(all) == "table" and all[P.bookclub.monthKey(0)] or nil
    local picks, auto = {}, false
    if type(chosen) == "table" then
        for _, fp in ipairs(chosen) do
            if by_fp[fp] then picks[#picks + 1] = by_fp[fp] end
        end
    end
    if #picks == 0 then
        auto = true
        for _, b in ipairs(books) do
            if b.started and not b.finished then picks[#picks + 1] = b end
        end
    end
    return { coll = coll, books = books, total = #books, done = done, picks = picks, auto = auto }
end

function P.bookclub.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = h / 300
    if w < 760 * s then s = w / 760 end
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st
    if env.sample then
        st = { coll = "bookclub 2026", total = 12, done = 7, books = {}, picks = {
            { title = "The Haunting of Hill House", author = "Shirley Jackson", pct = 0.46, started = true },
            { title = "HEX", author = "Thomas Olde Heuvelt", pct = 0 },
        } }
    else
        st = P.bookclub.state(env)
    end
    if not st then
        return emptyState(env, c, s, T("Book club"), T("No book club collection yet"),
            T("Make a collection called \xE2\x80\x9Cbookclub ") .. os.date("%Y") .. T("\xE2\x80\x9D and add your books to it."))
    end
    local pad = px(36)
    local month = A.date("%B")
    local title = env.cfg("title", T("Book club"))
    if title == "" then title = T("Book club") end

    -- header: "BOOK CLUB · OCTOBER", and how long the month has left
    local t = os.date("*t")
    local last = os.date("*t", os.time{ year = t.year, month = t.month + 1, day = 0, hour = 12 }).day
    local left = last - t.day
    local t_left = c:text(left == 0 and T("Last day") or (A.plural(left, "day", "days") .. T(" left")), fpx(22), { bold = true, color = tone.muted })
    local t_head = c:label(title .. "  \xC2\xB7  " .. month, fpx(22), pad, px(24),
        { bold = true, caps = true, color = tone.accent, max_w = w - 2 * pad - t_left.w - px(20) })
    c:put(t_left, w - pad, px(24) + t_head.base, "r", "base")

    -- along the bottom: one segment per book in the collection, filled for
    -- each one finished, with the count beside it
    local t_count = c:text(st.done .. T(" of ") .. st.total .. T(" read"), fpx(22), { bold = true, color = tone.fg })
    local bar_h = max(5, px(16))
    local bar_y = h - px(24) - bar_h
    c:put(t_count, w - pad, bar_y + bar_h / 2, "r", "mid")
    local bwid = w - 2 * pad - t_count.w - px(18)
    if st.total > 0 and st.total <= 40 then
        local sgap = max(2, px(6))
        local seg = (bwid - (st.total - 1) * sgap) / st.total
        if seg < bar_h * 0.6 then
            sgap = max(1, floor(sgap / 2))
            seg = (bwid - (st.total - 1) * sgap) / st.total
        end
        for i = 1, st.total do
            local x0 = pad + round((i - 1) * (seg + sgap))
            local x1 = pad + round((i - 1) * (seg + sgap) + seg)
            c:rrect(x0, bar_y, max(2, x1 - x0), bar_h, bar_h / 2, i <= st.done and tone.accent or tone.track)
        end
    else
        c:rrect(pad, bar_y, bwid, bar_h, bar_h / 2, tone.track)
        if st.total > 0 and st.done > 0 then
            c:rrect(pad, bar_y, max(bar_h, round(bwid * st.done / st.total)), bar_h, bar_h / 2, tone.accent, tone.track)
        end
    end
    bwid = w - 2 * pad

    -- this month's picks, side by side
    local garden = env.cfg("look", "classic") == "garden"
    local gl = garden and gardenLook(tone) or nil
    local top = px(24) + t_head.h + px(14)
    local area_h = bar_y - px(20) - top
    local picks = st.picks
    local max_n = (w / h) < 1.9 and 2 or 3
    local n = min(#picks, max_n)
    local files = {}
    if n == 0 or area_h < px(60) then
        local line
        if st.total == 0 then
            line = T("Add your club's books to \xE2\x80\x9C") .. D.collectionLabel(st.coll) .. "\xE2\x80\x9D"
        elseif n == 0 then
            line = T("Choose ") .. month .. T("'s books in Module settings")
        end
        if line and area_h >= px(30) then
            c:label(line, fpx(24), w / 2, top + area_h / 2, { anchor = "c", valign = "mid", color = tone.muted, max_w = bwid })
        end
    else
        local gap = px(30)
        local col_w = floor((bwid - (n - 1) * gap) / n)
        for i = 1, n do
            local b = picks[i]
            local x = pad + (i - 1) * (col_w + gap)
            local cover_h = floor(area_h)
            local cover_w = round(cover_h * 2 / 3)
            if cover_w > col_w * 0.38 then
                cover_w = round(col_w * 0.38)
                cover_h = round(cover_w * 1.5)
            end
            local cy = top + floor((area_h - cover_h) / 2)
            c:cover(b.fp, x, cy, cover_w, cover_h, { title = b.title, edge = tone.muted })
            if garden and b.finished then dragonflySticker(c, x, cy, cover_w, cover_h, px, gl) end
            local tx = x + cover_w + px(20)
            local tw = col_w - cover_w - px(20)
            -- bottom of the column: status over a small progress bar (or a stem)
            local mb_h = garden and max(px(20), min(px(44), floor(cover_h * 0.3))) or max(4, px(9))
            local status = b.finished and T("Finished") or (b.pct > 0 and string.format("%d%%", floor(b.pct * 100 + 0.5)) or T("Not started"))
            local t_status = c:text(status, fpx(22), { bold = true, max_w = tw,
                color = (b.finished and tone.accent) or (b.pct > 0 and tone.fg) or tone.muted })
            -- the words run the cover's height, so a short cover (a narrow
            -- card) has its title beside it rather than above it
            local mb_y = cy + cover_h - mb_h
            if garden then
                gardenStem(c, tx, mb_y, tw, mb_h, b.pct, b.finished, px, gl)
            else
                c:rrect(tx, mb_y, tw, mb_h, mb_h / 2, tone.track)
                if b.pct > 0 then
                    c:rrect(tx, mb_y, max(mb_h, round(tw * b.pct)), mb_h, mb_h / 2, tone.accent, tone.track)
                end
            end
            local st_y = mb_y - px(6) - t_status.h
            c:put(t_status, tx, st_y)
            -- top of the column: title, then author if there is room
            local room = st_y - px(4) - cy
            local t_title = c:textbox(b.title, fpx(n == 1 and 34 or 28), tw, 2, { bold = true, color = tone.fg })
            if t_title.h > room then t_title = c:textbox(b.title, fpx(n == 1 and 34 or 28), tw, 1, { bold = true, color = tone.fg }) end
            if t_title.h <= room then
                c:put(t_title, tx, cy - px(2))
                local t_author = b.author and c:text(b.author, fpx(21), { color = tone.muted, max_w = tw }) or nil
                if t_author and t_title.h + t_author.h <= room then c:put(t_author, tx, cy - px(2) + t_title.h) end
            end
            files[i] = b.fp or false
            c:region("pick:" .. i, x, top, col_w, area_h, px(4))
        end
    end
    if not env.sample then A.state.bookclub_files = files end
    return c
end

function P.bookclub.tap(env, region)
    local i = region and tonumber(region:match("^pick:(%d+)$"))
    local fp = i and A.state.bookclub_files and A.state.bookclub_files[i]
    if fp then D.openBook(env.ctx, fp) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- Week rings: a pair of rings for each day of the week, and daily averages
-- ════════════════════════════════════════════════════════════════════════════

P.week_rings = {
    does = T("opens the reading calendar"),
    title = T("Week rings"), tone = "plum", ratio = 0.61, ratio_narrow = 0.61,
    summary = T("Pages and minutes rings for each day this week, with daily averages. Needs the statistics plugin."),
}

function P.week_rings.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = statsFor(env)
    if st == false then
        return emptyState(env, c, s, T("This week"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(28)
    local cols = tone.series
    if hearts() then cols = { heartColors(tone) } end
    -- the same daily goals as the Activity rings card
    local page_goal = max(1, tonumber(A.get("activity_page_goal", 30)) or 30)
    local min_goal = D.dailyMinutesGoal()
    local week = st and st.week or {}

    local t_head = c:label(T("This week"), fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent })
    if st then
        local total = A.plural(st.week_pages, "page", "pages") .. "  \xC2\xB7  " .. A.fmtMinutes(st.week_secs / 60)
        local t_total = c:text(total, fpx(21), { bold = true, color = tone.muted })
        if pad + t_head.w + px(20) + t_total.w > w - pad then
            t_total = c:text(A.plural(st.week_pages, "page", "pages"), fpx(21), { bold = true, color = tone.muted })
        end
        if pad + t_head.w + px(20) + t_total.w <= w - pad then
            c:put(t_total, w - pad, px(22) + t_head.base, "r", "base")
        end
    end

    -- averages along the bottom, over the days of the week so far
    local elapsed = 0
    for i = 1, 7 do if week[i] and not week[i].future then elapsed = elapsed + 1 end end
    elapsed = max(1, elapsed)
    local avg_pages = st and floor(st.week_pages / elapsed + 0.5) or nil
    local avg_mins = st and (st.week_secs / 60 / elapsed) or nil
    local half = floor((w - 2 * pad) / 2)
    local t_v1 = c:text(avg_pages and A.plural(avg_pages, "page", "pages") or "\xE2\x80\xA6", fpx(27),
        { bold = true, color = cols[1], max_w = half - px(8) })
    local t_v2 = c:text(avg_mins and A.fmtMinutes(avg_mins) or "\xE2\x80\xA6", fpx(27),
        { bold = true, color = cols[2], max_w = half - px(8) })
    local t_c1 = c:text(T("a day on average"), fpx(18), { bold = true, color = tone.muted, max_w = half - px(8) })
    local t_c2 = c:text(T("a day on average"), fpx(18), { bold = true, color = tone.muted, max_w = half - px(8) })
    local tighten = round(t_v1.h * 0.12)
    local stats_y = h - px(18) - (t_v1.h + t_c1.h - tighten)
    c:put(t_v1, pad, stats_y)
    c:put(t_c1, pad, stats_y + t_v1.h - tighten)
    c:put(t_v2, pad + half + px(8), stats_y)
    c:put(t_c2, pad + half + px(8), stats_y + t_v1.h - tighten)

    -- day letters, then one pair of rings under each
    local t_l = c:text("M", fpx(20), { bold = true })
    local letters_y = px(22) + t_head.h + px(10)
    local rings_top = letters_y + t_l.h + px(8)
    local ring_area = stats_y - px(12) - rings_top
    local col_w = (w - 2 * pad) / 7
    local d = min(floor(col_w * 0.9), floor(ring_area))
    if d >= 10 then
        local R = d / 2
        local t = max(2, round(R * 0.27))
        local gap = max(1, round(R * 0.08))
        local cy = rings_top + ring_area / 2
        local ws = D.weekStart()
        for i = 1, 7 do
            local day = week[i] or { pages = 0, secs = 0, wday = ((ws + i - 2) % 7) + 1, future = true }
            local cx = pad + (i - 0.5) * col_w
            c:label(DAY_LETTERS[day.wday] or "", fpx(20), cx, letters_y,
                { anchor = "c", bold = true, color = day.today and tone.accent or tone.label })
            local fp = day.future and 0 or day.pages / page_goal
            local fm = day.future and 0 or (day.secs / 60) / min_goal
            if hearts() then
                dayHeart(c, cx, cy, d, tone, fp, fm, { future = day.future, past = not day.future and not day.today })
            else
                -- a ring with nothing in it is all track: no start dot
                c:ring(cx, cy, R, t, fp, tone.track, fp > 0 and cols[1] or tone.track)
                c:ring(cx, cy, R - t - gap, t, fm, tone.track, fm > 0 and cols[2] or tone.track)
                local hole = R - 2 * t - 2 * gap
                if fp >= 1 and fm >= 1 and hole >= 2 then
                    -- both goals met: fill the middle
                    c:disc(cx, cy, max(1.5, hole * 0.7), cols[3])
                end
            end
        end
    end
    return c
end

function P.week_rings.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Month rings: the same two rings for every day of this month, as a calendar
-- ════════════════════════════════════════════════════════════════════════════

P.month_rings = {
    does = T("opens the reading calendar"),
    title = T("Month rings"), tone = "plum", ratio = 0.82, ratio_narrow = 0.9,
    summary = T("Pages and minutes rings for each day this month, laid out as a calendar. Needs the statistics plugin."),
}

function P.month_rings.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 450)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local st = statsFor(env)
    local now = os.date("*t")
    -- the month shown: this one, or one stepped back to on the Monthly page
    local year, month, current = A.viewMonth()
    if env.sample then year, month, current = now.year, now.month, true end
    local month_name = A.monthTitle(year, month)
    if st == false then
        return emptyState(env, c, s, month_name, T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(28)
    local cols = tone.series
    if hearts() then cols = { heartColors(tone) } end
    -- the same daily goals as the Activity and Week rings cards
    local page_goal = max(1, tonumber(A.get("activity_page_goal", 30)) or 30)
    local min_goal = D.dailyMinutesGoal()

    -- the month, day by day; a past month has every day behind it
    local today = current and now.day or 99
    local n_days = tonumber(os.date("%d", os.time{ year = year, month = month + 1, day = 0, hour = 12 })) or 30
    local first_wday = tonumber(os.date("%w", os.time{ year = year, month = month, day = 1, hour = 12 })) + 1
    local ws = D.weekStart()
    local offset = (first_wday - ws) % 7
    local n_rows = ceil((offset + n_days) / 7)
    local days = st and st.days or {}
    local function dayRec(d)
        if env.sample then
            -- a believable month for the picker's preview
            if d > today then return { pages = 0, secs = 0 } end
            local v = (d * 37) % 11
            return { pages = v * 7, secs = v * 380 }
        end
        return days[string.format("%04d-%02d-%02d", year, month, d)] or { pages = 0, secs = 0 }
    end
    local sum_pages, sum_secs = 0, 0
    for d = 1, min(today, n_days) do
        local rec = dayRec(d)
        sum_pages, sum_secs = sum_pages + (rec.pages or 0), sum_secs + (rec.secs or 0)
    end

    local t_head = c:label(month_name, fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent })
    -- Top right: the averages per day over the month so far, each in the
    -- colour of its ring ("86 pages  1 h 35 m  a day"). Shortened, then
    -- dropped, when the card is too narrow for them beside the month.
    local elapsed = max(1, min(today, n_days))
    do
        local dots = "\xE2\x80\xA6"
        local v_pages = st and A.plural(floor(sum_pages / elapsed + 0.5), "page", "pages") or dots
        local v_time = st and A.fmtMinutes(sum_secs / 60 / elapsed) or dots
        local f_v = fpx(23)
        local function try(parts)
            local items, width = {}, 0
            for i, p in ipairs(parts) do
                local t = c:text(p[1], p[3] or f_v, { bold = true, color = p[2] })
                items[i] = t
                width = width + t.w + (i > 1 and px(14) or 0)
            end
            if pad + t_head.w + px(20) + width > w - pad then return false end
            local x = w - pad - width
            for i, t in ipairs(items) do
                if i > 1 then x = x + px(14) end
                c:put(t, x, px(22) + t_head.base, "l", "base")
                x = x + t.w
            end
            return true
        end
        local _ = try({ { v_pages, cols[1] }, { v_time, cols[2] }, { T("a day"), tone.muted, fpx(19) } })
            or try({ { v_pages, cols[1] }, { v_time, cols[2] } })
            or try({ { v_pages, cols[1] } })
    end
    local stats_y = h - px(12)

    -- weekday letters, then one row of rings per week
    local t_l = c:text("M", fpx(19), { bold = true })
    local letters_y = px(22) + t_head.h + px(8)
    local grid_top = letters_y + t_l.h + px(6)
    local grid_h = stats_y - grid_top
    local col_w = (w - 2 * pad) / 7
    local row_h = grid_h / n_rows
    local today_col = current and (((offset + today - 1) % 7) + 1) or 0
    for i = 1, 7 do
        local wday = ((ws + i - 2) % 7) + 1
        local is_today = (i == today_col)
        c:label(DAY_LETTERS[wday] or "", fpx(19), pad + (i - 0.5) * col_w, letters_y,
            { anchor = "c", bold = true, color = is_today and tone.accent or tone.label })
    end
    -- as big as the cell allows, leaving a little air (and room for the
    -- short bar under today)
    local d_ring = min(floor(col_w * 0.9), floor(row_h * 0.86))
    if d_ring >= 8 then
        local R = d_ring / 2
        local two = R >= 13            -- room for both rings; below that, pages only
        local t = two and max(2, round(R * 0.27)) or max(2, round(R * 0.38))
        local gap = max(1, round(R * 0.08))
        for d = 1, n_days do
            local slot = offset + d - 1
            local cx = pad + ((slot % 7) + 0.5) * col_w
            local cy = grid_top + (floor(slot / 7) + 0.5) * row_h
            local rec = dayRec(d)
            local future = d > today
            local fp = future and 0 or (rec.pages or 0) / page_goal
            local fm = future and 0 or ((rec.secs or 0) / 60) / min_goal
            if hearts() then
                dayHeart(c, cx, cy, d_ring, tone, fp, fm, { future = future, past = d < today, single = not two })
            else
                -- a ring with nothing in it is all track: no start dot
                c:ring(cx, cy, R, t, fp, tone.track, fp > 0 and cols[1] or tone.track)
                if two then
                    c:ring(cx, cy, R - t - gap, t, fm, tone.track, fm > 0 and cols[2] or tone.track)
                    local hole = R - 2 * t - 2 * gap
                    if fp >= 1 and fm >= 1 and hole >= 2 then c:disc(cx, cy, max(1.5, hole * 0.7), cols[3]) end
                elseif fm >= 1 and R - t >= 3 then
                    -- one ring only: the minutes goal shows as a filled middle
                    c:disc(cx, cy, max(1.5, (R - t) * 0.6), cols[2])
                end
            end
            if current and d == today then
                -- today: a short bar under its rings
                local bar_w, bar_h = max(4, round(R * 0.9)), max(2, round(R * 0.14))
                local by = cy + R + max(1, round((row_h - d_ring) * 0.2))
                if by + bar_h <= grid_top + grid_h + px(8) then
                    c:rrect(cx - bar_w / 2, by, bar_w, bar_h, bar_h / 2, tone.fg)
                end
            end
        end
    end
    return c
end

function P.month_rings.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Year chart: books finished and pages read, month by month, as two lines
-- ════════════════════════════════════════════════════════════════════════════

P.year_chart = {
    does = T("lists a month's books"),
    title = T("Books and pages"), tone = "ink", ratio = 0.4, ratio_narrow = 0.62,
    summary = T("Books finished and pages read each month this year, as two lines. Tap a month for its books."),
}

local MONTH_LETTERS = {}
for month = 1, 12 do MONTH_LETTERS[month] = monthLetter(month) end

-- A step for an axis with four divisions that reaches `top`: 1, 2, 2.5 or 5
-- times a power of ten.
local function niceStep(top)
    if not (top and top > 0) then return 1 end
    local raw = top / 4
    local mag = 10 ^ floor(math.log10(raw))
    for _, k in ipairs{ 1, 2, 2.5, 5, 10 } do
        if k * mag >= raw then return k * mag end
    end
    return 10 * mag
end

-- Points along a smooth curve through (xs[i], ys[i]) that never swings past
-- its neighbouring values (monotone cubic, Fritsch-Carlson), so a month with
-- nothing in it stays on the axis instead of dipping below it.
local function smoothPoints(xs, ys, steps)
    local n = #xs
    local out = {}
    if n == 0 then return out end
    if n == 1 then return { xs[1], ys[1], xs[1], ys[1] } end
    local d, m = {}, {}
    for i = 1, n - 1 do d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) end
    m[1], m[n] = d[1], d[n - 1]
    for i = 2, n - 1 do
        if d[i - 1] * d[i] <= 0 then m[i] = 0 else m[i] = (d[i - 1] + d[i]) / 2 end
    end
    for i = 1, n - 1 do
        if d[i] == 0 then
            m[i], m[i + 1] = 0, 0
        else
            local a, b = m[i] / d[i], m[i + 1] / d[i]
            local q = a * a + b * b
            if q > 9 then
                local t = 3 / math.sqrt(q)
                m[i], m[i + 1] = t * a * d[i], t * b * d[i]
            end
        end
    end
    for i = 1, n - 1 do
        local x0, x1, y0, y1 = xs[i], xs[i + 1], ys[i], ys[i + 1]
        local hx = x1 - x0
        for k = (i == 1) and 0 or 1, steps do
            local t = k / steps
            local t2, t3 = t * t, t * t * t
            local y = (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * hx * m[i]
                + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * hx * m[i + 1]
            out[#out + 1] = x0 + t * hx
            out[#out + 1] = y
        end
    end
    return out
end

local SAMPLE_BOOKS = { 0, 0, 0, 0, 2, 5, 9, 5, 10, 3, 0, 0 }
local SAMPLE_PAGES = { 0, 0, 0, 0, 820, 2340, 3760, 3300, 3180, 1420, 0, 0 }

function P.year_chart.build(env)
    local w, h, tone = env.w, env.h, env.tone
    -- sized like the other cards: by width, unless the card is short
    local s = min(w / 900, h / 330)
    if w < 760 then s = min(w / 600, h / 380) end
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local cols = tone.series
    local Screen = A.screen()
    if not (Screen.isColorEnabled and Screen:isColorEnabled()) then
        -- in greys the two accents look alike: ink for books, a light grey for pages
        cols = { tone.fg, A.mix(tone.bg, tone.fg, 0.45) }
    end
    local now = os.date("*t")
    local cur = now.month
    local mode = env.cfg("pages", "read")

    -- the figures, month by month
    local books, pages = {}, {}
    local have_pages = true
    if env.sample then
        for m = 1, 12 do books[m], pages[m] = SAMPLE_BOOKS[m], SAMPLE_PAGES[m] end
        cur = 10
    else
        local yr = D.year(env.refresh)
        for m = 1, 12 do
            local list = yr and yr.months and yr.months[m] or {}
            books[m] = #list
            local p = 0
            for _, it in ipairs(list) do p = p + (tonumber(it.pages) or 0) end
            pages[m] = p
        end
        if mode == "read" then
            local st = statsFor(env)
            if st and st.month_pages then
                for m = 1, 12 do pages[m] = st.month_pages[m] or 0 end
            else
                have_pages = false
            end
        end
    end
    local total_b, total_p, max_b, max_p = 0, 0, 0, 0
    for m = 1, cur do
        total_b, total_p = total_b + books[m], total_p + pages[m]
        max_b, max_p = max(max_b, books[m]), max(max_p, pages[m])
    end

    local pad = px(28)
    -- header: what it is on the left, the year's totals as a legend on the right
    local t_head = c:label(T("Books and pages"), fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent })
    local dot_r = max(3, px(7))
    local function legend(parts)
        local items, width = {}, 0
        for _, part in ipairs(parts) do
            local t = c:text(part[1], fpx(21), { bold = true, color = tone.fg })
            items[#items + 1] = { t = t, col = part[2] }
            width = width + 2 * dot_r + px(8) + t.w
        end
        return items, width + px(18) * (#items - 1)
    end
    local parts = { { A.plural(total_b, "book", "books"), cols[1] } }
    if have_pages then parts[2] = { A.thousands(total_p) .. T(" pages"), cols[2] } end
    local items, lw_total = legend(parts)
    if pad + t_head.w + px(24) + lw_total > w - pad then
        -- too long beside the title: numbers only
        parts = { { tostring(total_b), cols[1] } }
        if have_pages then parts[2] = { A.thousands(total_p), cols[2] } end
        items, lw_total = legend(parts)
    end
    if pad + t_head.w + px(24) + lw_total <= w - pad then
        local x = w - pad - lw_total
        local base = px(22) + t_head.base
        for _, it in ipairs(items) do
            c:disc(x + dot_r, base - it.t.base * 0.36, dot_r, it.col)
            x = x + 2 * dot_r + px(8)
            c:put(it.t, x, base, "l", "base")
            x = x + it.t.w + px(18)
        end
    end

    -- the axes: four divisions, both scales on the same grid lines
    local step_b = max(1, ceil(max_b / 4))
    local top_b = 4 * step_b
    local step_p = niceStep(max(max_p, 400))
    local top_p = 4 * step_p
    local f_axis = fpx(18)
    local left, right = {}, {}
    local wl, wr = 0, 0
    for i = 0, 4 do
        left[i] = c:text(tostring(i * step_b), f_axis, { bold = true, color = tone.label })
        wl = max(wl, left[i].w)
        if have_pages then
            local v = i * step_p
            local label = v >= 10000 and (A.thousands(v / 1000) .. "k") or A.thousands(v)
            right[i] = c:text(label, f_axis, { bold = true, color = tone.label })
            wr = max(wr, right[i].w)
        end
    end
    local t_m = c:text("M", fpx(19), { bold = true })
    local plot_top = px(22) + t_head.h + px(18) + floor(left[0].h / 2)
    local plot_bottom = h - px(16) - t_m.h - px(8)
    local x0 = pad + wl + px(12)
    local x1 = w - pad - (have_pages and (wr + px(12)) or px(6))
    if plot_bottom - plot_top < px(30) or x1 - x0 < 12 * 6 then return c end
    local ph = plot_bottom - plot_top
    local grid_w = max(1, px(2))
    for i = 0, 4 do
        local y = plot_bottom - ph * i / 4
        c:rect(x0, floor(y + 0.5) - floor(grid_w / 2), x1 - x0, grid_w, i == 0 and A.mix(tone.track, tone.fg, 0.35) or tone.track)
        c:put(left[i], x0 - px(12), y, "r", "mid")
        if right[i] then c:put(right[i], x1 + px(12), y, "l", "mid") end
    end

    -- months along the bottom: short names when they fit, else initials
    local xs = {}
    for m = 1, 12 do xs[m] = x0 + (x1 - x0) * (m - 1) / 11 end
    local col_w = (x1 - x0) / 11
    local names, widest = {}, 0
    for m = 1, 12 do
        names[m] = A.date("%b", os.time{ year = now.year, month = m, day = 1, hour = 12 })
        local t = c:text(names[m], fpx(19), { bold = true })
        widest = max(widest, t.w)
    end
    if widest > col_w * 0.92 then names = MONTH_LETTERS end
    for m = 1, 12 do
        local is_cur = (m == cur)
        c:label(names[m], fpx(19), xs[m], plot_bottom + px(8),
            { anchor = "c", bold = true, color = is_cur and tone.fg or tone.label })
        -- tapping a month lists the books finished in it
        local rx = (m == 1) and x0 - col_w / 2 or xs[m] - col_w / 2
        c:region("month:" .. m, rx, plot_top, col_w, plot_bottom - plot_top + px(8) + t_m.h)
    end

    -- the two lines, up to this month; pages underneath, books on top
    local lw = max(2, round(4.5 * s))
    local dot = max(2.5, 6 * s)
    local cozy = cozyOn()
    local function curve(values, top)
        local ys = {}
        local xs_c = {}
        for m = 1, cur do
            xs_c[m] = xs[m]
            ys[m] = plot_bottom - ph * min(1, values[m] / top)
        end
        return xs_c, ys, smoothPoints(xs_c, ys, 16)
    end
    local pxs, pys, ppts
    if have_pages then pxs, pys, ppts = curve(pages, top_p) end
    local bxs, bys, bpts = curve(books, top_b)
    if cozy then
        -- soft hills under the lines, pages behind books
        if ppts then hill(c, ppts, floor(plot_bottom), A.mix(tone.bg, cols[2], tone.dark and 0.3 or 0.16)) end
        hill(c, bpts, floor(plot_bottom), A.mix(tone.bg, cols[1], tone.dark and 0.3 or 0.16))
    end
    if ppts then c:polyline(ppts, lw, cols[2]) end
    c:polyline(bpts, lw, cols[1])
    if cozy then
        local hs = max(px(12), dot * 3.2)
        local gl = gardenLook(tone)
        if pxs then for m = 1, cur - 1 do pointHeart(c, pxs[m], pys[m], hs, cols[2], px) end end
        for m = 1, cur - 1 do pointHeart(c, bxs[m], bys[m], hs, cols[1], px) end
        -- the latest month: a heart for pages, a flower for books
        if pxs then pointHeart(c, pxs[cur], pys[cur], hs * 1.2, cols[2], px) end
        c:sprite(bxs[cur], bys[cur], hs * 1.9, 0, bloomParts(gl), { lw = max(1, px(2)) })
    else
        if pxs then for m = 1, cur do c:disc(pxs[m], pys[m], dot, cols[2]) end end
        for m = 1, cur do c:disc(bxs[m], bys[m], dot, cols[1]) end
    end
    return c
end

function P.year_chart.tap(env, region)
    local m = region and tonumber(region:match("^month:(%d+)$"))
    if not m then return end
    return A.listFinished(env, tonumber(os.date("%Y")), m)
end

-- A dialog listing the books finished in month m of year y; tap one for its details.
function A.listFinished(env, y, m)
    local list = D.finishedIn(nil, y, m) or {}
    local month_name = A.monthTitle(y, m)
    local S = A.S
    S.open(env.ctx, T("Finished in ") .. month_name, function(api)
        local rows = {}
        if #list == 0 then rows[1] = S.header(T("No books finished in ") .. month_name) end
        for _, it in ipairs(list) do
            local label = A.safe(it.title or it.fp:match("([^/]+)$") or "?")
            if it.author and it.author ~= "" then label = label .. "  \xC2\xB7  " .. A.safe(it.author) end
            rows[#rows + 1] = { { text = label, callback = function()
                api.close()
                D.showDetails(env.ctx, it.fp)
            end } }
        end
        return rows
    end)
end

-- ════════════════════════════════════════════════════════════════════════════
-- Bar charts: time read month by month, pages read day by day
-- ════════════════════════════════════════════════════════════════════════════

-- "142 h" for a big total, "4 h 12 m" for a small one
local function hoursText(secs)
    secs = tonumber(secs) or 0
    if secs >= 10 * 3600 then return A.thousands(floor(secs / 3600 + 0.5)) .. " h" end
    return A.fmtMinutes(secs / 60)
end

-- 2.5 -> "2.5", 3 -> "3"
local function figure(v)
    if v == floor(v) then return A.thousands(v) end
    return A.decimal(v)
end

-- A dashed line from x0 to x1 at y.
local function dashed(c, x0, x1, y, lw, dash, gap, rgb)
    local x = x0
    while x < x1 do
        c:rect(x, y - floor(lw / 2), min(dash, x1 - x), lw, rgb)
        x = x + dash + gap
    end
end

-- A bar chart in the box (o.x, o.y, o.w, o.h) of canvas c: the value axis on
-- the left with four grid lines, one bar per slot, labels under the bars.
--   o.n          number of slots
--   o.values[i]  the figure, or nil for a slot still to come (no bar)
--   o.labels[i]  text under slot i, or nil
--   o.current    the slot drawn in the first accent (this month, today)
--   o.fmt(v)     an axis figure
--   o.floor_top  the axis reaches at least this
--   o.average    optional: a dashed line at this value
--   o.avg_label  what to call it on the chart ("average 42")
--   o.mark       optional: text over the current bar
--   o.region     optional: a tap region per slot, named o.region .. i
local function barChart(c, tone, s, ts, o)
    local px, fpx = scaler(s, ts)
    local n = o.n
    local top_v = o.floor_top or 1
    for i = 1, n do
        local v = o.values[i]
        if v then top_v = max(top_v, v) end
    end
    local step = niceStep(top_v)
    local top = 4 * step
    local f_axis = fpx(18)
    local ylab, wl = {}, 0
    for i = 0, 4 do
        ylab[i] = c:text(o.fmt(i * step), f_axis, { bold = true, color = tone.label })
        wl = max(wl, ylab[i].w)
    end
    local t_x = c:text("0", fpx(19), { bold = true })
    local cozy = cozyOn()
    local shelf_th = cozy and max(4, px(9)) or 0
    local plot_top = o.y + floor(ylab[4].h / 2)
    local plot_bottom = o.y + o.h - t_x.h - px(8) - shelf_th
    local x0 = o.x + wl + px(12)
    local x1 = o.x + o.w
    if plot_bottom - plot_top < px(24) or x1 - x0 < n * 3 then return end
    local ph = plot_bottom - plot_top
    local grid_w = max(1, px(2))
    for i = 0, 4 do
        local gy = floor(plot_bottom - ph * i / 4 + 0.5)
        if not (cozy and i == 0) then
            c:rect(x0, gy - floor(grid_w / 2), x1 - x0, grid_w, i == 0 and A.mix(tone.track, tone.fg, 0.35) or tone.track)
        end
        c:put(ylab[i], x0 - px(12), gy, "r", "mid")
    end
    local col_w = (x1 - x0) / n
    local bar_w = max(2, floor(col_w * (o.bar_k or (cozy and 0.72 or 0.6))))
    if cozy then shelf(c, x0, floor(plot_bottom + 0.5), x1 - x0, px, tone) end
    -- the best slot gets a heart
    local best_i, best_v = nil, 0
    if cozy then
        for i = 1, n do
            local v = o.values[i]
            if v and v > best_v then best_i, best_v = i, v end
        end
    end
    local heart_s = min(max(bar_w * 1.25, px(14)), px(30))
    local radius = min(floor(bar_w / 2), px(6))
    local base = floor(plot_bottom + 0.5) - floor(grid_w / 2)
    local stub = max(2, px(4))
    for i = 1, n do
        local cx = x0 + (i - 0.5) * col_w
        local bx = floor(cx - bar_w / 2)
        local v = o.values[i]
        local is_cur = (i == o.current)
        if v then
            local bh = (v > 0) and max(stub, round(ph * min(1, v / top))) or 0
            if bh > 0 and cozy then
                spineUp(c, bx, floor(plot_bottom + 0.5), bar_w, bh, is_cur and tone.accent or spineColour(i, tone), px)
                if i == best_i then
                    bestHeart(c, cx, floor(plot_bottom + 0.5) - bh, heart_s, tone, px)
                    bh = bh + heart_s + px(2)
                end
            end
            if bh > 0 then
                if not cozy then
                    local col = is_cur and tone.accent or tone.accent2
                    -- rounded on top, square where it stands on the axis
                    local r = min(radius, floor(bh / 2))
                    c:rrect(bx, base - bh, bar_w, bh, r, col, tone.bg)
                    if bh > r and r > 0 then c:rect(bx, base - r, bar_w, r, col) end
                end
                if is_cur and o.mark then
                    -- Just over the bar. The figure is wider than a bar, so it
                    -- is slid sideways (centred, or starting at the bar's left
                    -- or right edge) to whichever position clears the bars it
                    -- spans lowest: usually towards the empty months still to
                    -- come, rather than lifting it over a taller neighbour.
                    local t_m = c:text(o.mark, fpx(19), { bold = true, color = tone.accent })
                    local function reachAt(mx)
                        local reach = base - bh
                        for j = 1, n do
                            local jx = x0 + (j - 0.5) * col_w
                            local vj = o.values[j]
                            if j ~= i and vj and vj > 0 and jx + bar_w / 2 >= mx - px(4) and jx - bar_w / 2 <= mx + t_m.w + px(4) then
                                local hj = max(stub, round(ph * min(1, vj / top))) + ((j == best_i) and (heart_s + px(2)) or 0)
                                reach = min(reach, base - hj)
                            end
                        end
                        return reach
                    end
                    local best_x, best_reach
                    for _, mx in ipairs{ cx - t_m.w / 2, bx, bx + bar_w - t_m.w } do
                        mx = A.clamp(mx, x0, x1 - t_m.w)
                        local rr = reachAt(mx)
                        if not best_reach or rr > best_reach + 1 then best_x, best_reach = mx, rr end
                    end
                    local my = best_reach - px(6) - t_m.h
                    if my >= o.y - px(4) then c:put(t_m, best_x, my) end
                end
            end
        end
        local lab = o.labels[i]
        if lab then
            c:label(lab, fpx(19), cx, plot_bottom + shelf_th + px(8),
                { anchor = "c", bold = true, color = is_cur and tone.fg or tone.label })
        end
        if o.region then c:region(o.region .. i, cx - col_w / 2, plot_top, col_w, o.y + o.h - plot_top) end
    end
    if o.average and o.average > 0 then
        local ay = floor(plot_bottom - ph * min(1, o.average / top) + 0.5)
        local lw = max(2, px(3))
        dashed(c, x0, x1, ay, lw, px(10), px(7), tone.fg)
        if o.avg_label then
            -- named at its right-hand end, on a patch of card so bars and grid
            -- lines do not run through the words; below the line near the top
            local t = c:text(o.avg_label, fpx(19), { bold = true, color = tone.fg })
            local ty = ay - lw - px(4) - t.h
            if ty < o.y then ty = ay + lw + px(4) end
            local tx = x1 - t.w
            c:rect(tx - px(8), ty, t.w + px(8), t.h, tone.bg)
            c:put(t, tx, ty)
        end
    end
end

-- The figures a card header shows on the right: bold text, with optional
-- muted text before it, right-aligned at x and sitting on baseline y.
-- Returns false (and draws nothing) when it would run into `left_edge`.
local function headerRight(c, tone, fpx, parts, x, y, left_edge)
    local items, width = {}, 0
    for i, p in ipairs(parts) do
        local t = c:text(p[1], fpx(21), { bold = true, color = p[2] == "muted" and tone.muted or tone.fg })
        items[i] = { t = t, dash = p.dash }
        width = width + t.w + (p.dash and (fpx(21) * 1.6) or 0) + (i > 1 and fpx(10) or 0)
    end
    if x - width < left_edge then return false end
    local cx = x - width
    for i, it in ipairs(items) do
        if i > 1 then cx = cx + fpx(10) end
        if it.dash then
            local dw = floor(fpx(21) * 1.6)
            dashed(c, cx, cx + dw - fpx(6), floor(y - it.t.base * 0.36), max(2, round(fpx(21) / 7)),
                max(3, floor(dw / 4)), max(2, floor(dw / 7)), tone.fg)
            cx = cx + dw
        end
        c:put(it.t, cx, y, "l", "base")
        cx = cx + it.t.w
    end
    return true
end

-- ─── Time read, month by month ──────────────────────────────────────────────

P.year_time = {
    does = T("lists a month's books"),
    title = T("Time read by month"), tone = "ink", ratio = 0.62, ratio_narrow = 0.75,
    summary = T("Hours read each month this year, as bars. Tap a month for its books. Needs the statistics plugin."),
}

local SAMPLE_MONTH_SECS = { 0, 0, 0, 0, 30600, 52200, 77400, 64800, 61200, 23400, 0, 0 }

function P.year_time.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 400)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local now = os.date("*t")
    local cur, secs = now.month, {}
    if env.sample then
        cur = 10
        for m = 1, 12 do secs[m] = SAMPLE_MONTH_SECS[m] end
    else
        local st = statsFor(env)
        if st == false then
            return emptyState(env, c, s, T("Time read"), T("No reading statistics"),
                T("Turn on KOReader's Reading statistics plugin."))
        end
        for m = 1, 12 do secs[m] = st and st.month_secs and st.month_secs[m] or 0 end
    end
    local pad = px(28)
    local t_head = c:label(T("Time read"), fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent })
    local total = 0
    for m = 1, cur do total = total + secs[m] end
    local base = px(22) + t_head.base
    if not headerRight(c, tone, fpx, { { tostring(now.year), "muted" }, { hoursText(total) } }, w - pad, base, pad + t_head.w + px(16)) then
        headerRight(c, tone, fpx, { { hoursText(total) } }, w - pad, base, pad + t_head.w + px(16))
    end

    -- hours on the axis; months under the bars, short names when they fit
    local values, labels = {}, {}
    for m = 1, 12 do values[m] = (m <= cur) and secs[m] / 3600 or nil end
    local col_w = (w - 2 * pad) / 12 * 0.86
    local widest = 0
    for m = 1, 12 do
        labels[m] = shortMonth(m)
        widest = max(widest, c:text(labels[m], fpx(19), { bold = true }).w)
    end
    if widest > col_w * 0.92 then
        for m = 1, 12 do labels[m] = MONTH_LETTERS[m] end
    end
    local top = px(22) + t_head.h + px(22)
    barChart(c, tone, s, env.ts, {
        x = pad, y = top, w = w - 2 * pad, h = h - top - px(18),
        n = 12, values = values, labels = labels, current = cur, bar_k = 0.62,
        floor_top = 4, fmt = function(v) return figure(v) .. " h" end,
        mark = secs[cur] > 0 and hoursText(secs[cur]) or nil, region = "month:",
    })
    return c
end

function P.year_time.tap(env, region) return P.year_chart.tap(env, region) end

-- ─── Pages (or time) read each day this month ───────────────────────────────

P.month_chart = {
    does = T("opens the reading calendar"),
    title = T("Pages per day"), tone = "ink", ratio = 0.4, ratio_narrow = 0.62,
    summary = T("Pages (or time) read each day this month, as bars, with your daily average. Needs the statistics plugin."),
}

function P.month_chart.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 900, h / 330)
    if w < 760 then s = min(w / 600, h / 380) end
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local by_time = env.cfg("metric", "pages") == "time"
    local now = os.date("*t")
    local year, month, current = A.viewMonth()
    if env.sample then year, month, current = now.year, now.month, true end
    local n_days = tonumber(os.date("%d", os.time{ year = year, month = month + 1, day = 0, hour = 12 })) or 30
    -- a past month has all its days behind it
    local today = current and now.day or n_days
    local st = statsFor(env)
    if st == false then
        return emptyState(env, c, s, by_time and T("Time per day") or T("Pages per day"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local values, total = {}, 0
    for d = 1, n_days do
        if d <= today then
            local rec
            if env.sample then
                local v = (d * 37) % 11
                rec = { pages = v * 9, secs = v * 520 }
            else
                rec = st and st.days and st.days[string.format("%04d-%02d-%02d", year, month, d)] or {}
            end
            local v = by_time and (rec.secs or 0) / 60 or (rec.pages or 0)
            values[d] = v
            total = total + v
        end
    end
    local avg = total / max(1, today)

    local pad = px(28)
    local t_head = c:label(by_time and T("Time per day") or T("Pages per day"), fpx(22), pad, px(22),
        { bold = true, caps = true, color = tone.accent })
    local base = px(22) + t_head.base
    local tot_txt = by_time and A.fmtMinutes(total) or A.plural(floor(total + 0.5), "page", "pages")
    local avg_txt = T("average ") .. (by_time and A.fmtMinutes(avg) or A.thousands(avg))
    local left_edge = pad + t_head.w + px(20)
    if st then
        if not headerRight(c, tone, fpx, { { A.monthTitle(year, month), "muted" }, { tot_txt } }, w - pad, base, left_edge) then
            headerRight(c, tone, fpx, { { tot_txt } }, w - pad, base, left_edge)
        end
    end

    -- day numbers: the 1st, every fifth day, and today
    local labels = {}
    for d = 1, n_days do
        if d == 1 or d % 5 == 0 then labels[d] = tostring(d) end
    end
    if current then
        for d = today - 2, today + 2 do
            if d ~= today and d >= 1 and d <= n_days then labels[d] = nil end
        end
        labels[today] = tostring(today)
    end
    local top = px(22) + t_head.h + px(18)
    barChart(c, tone, s, env.ts, {
        x = pad, y = top, w = w - 2 * pad, h = h - top - px(16),
        n = n_days, values = values, labels = labels, current = current and today or nil, bar_k = 0.58,
        floor_top = by_time and 60 or 20, average = st and avg > 0 and avg or nil, avg_label = avg_txt,
        fmt = by_time and function(v)
            if v >= 60 and v % 60 == 0 then return figure(v / 60) .. " h" end
            return figure(v) .. " m"
        end or figure,
    })
    return c
end

function P.month_chart.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Month totals: books finished, time spent reading, pages read this month
-- ════════════════════════════════════════════════════════════════════════════

P.month_totals = {
    does = T("lists this month's books"),
    title = T("Month totals"), tone = "ink", ratio = 0.82, ratio_narrow = 0.9,
    summary = T("Books finished, time spent reading and pages read this month. Needs the statistics plugin."),
}

function P.month_totals.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local wide = w / h > 1.7
    -- sized like Month rings, its usual neighbour, so the two headers match
    local s = wide and min(w / 900, h / 300) or min(w / 546, h / 450)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local now = os.date("*t")
    local year, month, current = A.viewMonth()
    if env.sample then year, month, current = now.year, now.month, true end
    local n_days = tonumber(os.date("%d", os.time{ year = year, month = month + 1, day = 0, hour = 12 })) or 30
    local books, secs, pages
    if env.sample then
        books, secs, pages = 3, 45600, 1234
    else
        local st = statsFor(env)
        local list = D.finishedIn(env.refresh, year, month)
        books = list and #list or nil
        if st then
            local ms = D.monthStats(st, year, month)
            secs, pages = ms.secs, ms.pages
        end
        if st == false then secs, pages = false, false end
    end
    local pad = px(30)
    local month_name = A.monthTitle(year, month)
    local t_head = c:label(month_name, fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent })
    -- (on the Dashboard the page heading already says which day it is)
    local t_day = c:text(current and (T("day ") .. now.day .. T(" of ") .. n_days) or A.plural(n_days, "day", "days"),
        fpx(21), { bold = true, color = tone.muted })
    if not env.nested and pad + t_head.w + px(16) + t_day.w <= w - pad then
        c:put(t_day, w - pad, px(24) + t_head.base, "r", "base")
    end
    local dots = "\xE2\x80\xA6"
    local stats_off = T("turn on Reading statistics")
    local blocks = {
        { value = books and tostring(books) or dots, label = (books == 1) and T("book finished") or T("books finished"),
          col = tone.fg, region = "books" },
        { value = secs == false and "\xE2\x80\x94" or (secs and A.fmtMinutes(secs / 60) or dots),
          label = secs == false and stats_off or T("spent reading"), col = tone.accent2 },
        { value = pages == false and "\xE2\x80\x94" or (pages and A.thousands(pages) or dots),
          label = pages == false and stats_off or ((pages == 1) and T("page read") or T("pages read")), col = tone.accent },
    }
    local top = px(24) + t_head.h + px(14)
    local bottom = h - px(22)
    local stripe = max(3, px(8))
    if wide then
        -- three columns
        local cw = (w - 2 * pad) / 3
        for i, b in ipairs(blocks) do
            local x = pad + (i - 1) * cw
            local inner = cw - px(24)
            local t_l = c:text(b.label, fpx(22), { bold = true, color = tone.muted, max_w = inner })
            local size = min(fpx(64), floor((bottom - top - t_l.h) * 0.9))
            local t_v = c:text(b.value, size, { bold = true, color = tone.fg })
            if t_v.w > inner then t_v = c:text(b.value, max(minFont(), floor(size * inner / t_v.w)), { bold = true, color = tone.fg }) end
            local y = top + floor((bottom - top - t_v.h - t_l.h) / 2)
            c:rrect(x, y + px(6), stripe, t_v.h + t_l.h - px(12), stripe / 2, b.col, tone.bg)
            c:put(t_v, x + stripe + px(16), y)
            c:put(t_l, x + stripe + px(16), y + t_v.h - px(4))
            if b.region then c:region(b.region, x, top, cw, bottom - top) end
        end
        return c
    end
    -- three rows, divided by thin lines
    local rh = (bottom - top) / 3
    local inner = w - 2 * pad - stripe - px(20)
    for i, b in ipairs(blocks) do
        local y0 = top + (i - 1) * rh
        if i > 1 then c:rect(pad, floor(y0), w - 2 * pad, max(1, px(2)), tone.track) end
        local t_l = c:text(b.label, fpx(23), { bold = true, color = tone.muted, max_w = inner })
        local size = min(fpx(70), floor((rh - t_l.h - px(16)) * 0.95))
        local t_v = c:text(b.value, size, { bold = true, color = tone.fg })
        if t_v.w > inner then t_v = c:text(b.value, max(minFont(), floor(size * inner / t_v.w)), { bold = true, color = tone.fg }) end
        local tight = round(t_v.h * 0.1)
        local block_h = t_v.h + t_l.h - tight
        local y = floor(y0 + (rh - block_h) / 2)
        c:rrect(pad, y + round(t_v.h * 0.16), stripe, block_h - round(t_v.h * 0.22), stripe / 2, b.col, tone.bg)
        c:put(t_v, pad + stripe + px(20), y)
        c:put(t_l, pad + stripe + px(20), y + t_v.h - tight)
        if b.region then c:region(b.region, pad, floor(y0), w - 2 * pad, floor(rh)) end
    end
    return c
end

function P.month_totals.tap(env, region)
    if region == "books" then
        local y, m = A.viewMonth()
        return A.listFinished(env, y, m)
    end
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- When you read: the hours of the day the reading happened
-- ════════════════════════════════════════════════════════════════════════════

P.when_read = {
    does = T("nothing"),
    title = T("When you read"), tone = "ink", ratio = 0.62, ratio_narrow = 0.75,
    summary = T("Which hours of the day you read in, over the month the Monthly page shows. Needs the statistics plugin."),
}

-- the four parts of the day, by starting hour
local DAY_PARTS = {
    { name = T("Morning"),   many = T("Mornings"),   from = 5,  to = 11 },
    { name = T("Afternoon"), many = T("Afternoons"), from = 12, to = 16 },
    { name = T("Evening"),   many = T("Evenings"),   from = 17, to = 20 },
    { name = T("Night"),     many = T("Nights"),     from = 21, to = 28 }, -- through 4 am
}
local function partOf(hr)
    for i, p in ipairs(DAY_PARTS) do
        if (hr >= p.from and hr <= p.to) or (hr + 24 >= p.from and hr + 24 <= p.to) then return i end
    end
    return 4
end

local function hourName(hr, short)
    local twelve = G_reader_settings and G_reader_settings:isTrue("twelve_hour_clock")
    if not twelve then return short and tostring(hr) or string.format("%02d:00", hr) end
    local h12 = hr % 12 == 0 and 12 or hr % 12
    if short then return h12 .. (hr < 12 and "a" or "p") end
    return h12 .. (hr < 12 and " am" or " pm")
end

local SAMPLE_HOURS = { [7] = 900, [8] = 1500, [12] = 1200, [13] = 600, [17] = 600, [18] = 1800, [19] = 2400,
    [20] = 3600, [21] = 4800, [22] = 4200, [23] = 1800, [0] = 600 }

function P.when_read.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 400)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    -- always the month the Monthly page shows (its arrows change it)
    local vy, vm = A.viewMonth()
    local hours = {}
    if env.sample then
        for hr = 0, 23 do hours[hr] = SAMPLE_HOURS[hr] or 0 end
    else
        local st = statsFor(env)
        if st == false then
            return emptyState(env, c, s, T("When you read"), T("No reading statistics"),
                T("Turn on KOReader's Reading statistics plugin."))
        end
        local src = st and D.monthStats(st, vy, vm).hours
        for hr = 0, 23 do hours[hr] = src and src[hr] or 0 end
    end
    local pad = px(28)
    local t_head = c:label(T("When you read"), fpx(22), pad, px(22), { bold = true, caps = true, color = tone.accent })
    local span = A.monthTitle(vy, vm)
    local t_span = c:text(span, fpx(21), { bold = true, color = tone.muted })
    if pad + t_head.w + px(16) + t_span.w <= w - pad then
        c:put(t_span, w - pad, px(22) + t_head.base, "r", "base")
    end

    local total, parts, peak_hr = 0, { 0, 0, 0, 0 }, 0
    for hr = 0, 23 do
        total = total + hours[hr]
        local p = partOf(hr)
        parts[p] = parts[p] + hours[hr]
        if hours[hr] > hours[peak_hr] then peak_hr = hr end
    end
    local top = px(22) + t_head.h + px(16)
    if total <= 0 then
        local msg = T("No reading in ") .. span
        c:label(msg, fpx(24), w / 2, top + (h - top) / 2, { anchor = "c", valign = "mid", color = tone.muted, max_w = w - 2 * pad })
        return c
    end
    local peak_part = 1
    for i = 2, 4 do if parts[i] > parts[peak_part] then peak_part = i end end
    local share = floor(100 * parts[peak_part] / total + 0.5)

    -- the headline: "Evenings", "41% of your reading · most at 9 pm"
    local t_big = c:text(DAY_PARTS[peak_part].many, fpx(40), { bold = true, color = tone.fg, max_w = w - 2 * pad })
    local sub = share .. T("% of your reading  \xC2\xB7  most at ") .. hourName(peak_hr)
    local t_sub = c:text(sub, fpx(21), { bold = true, color = tone.muted })
    if t_sub.w > w - 2 * pad then
        t_sub = c:text(share .. T("% of your reading"), fpx(21), { bold = true, color = tone.muted, max_w = w - 2 * pad })
    end
    local tight = round(t_big.h * 0.12)
    c:put(t_big, pad - round(t_big.px * 0.03), top - tight)
    local y = top - tight + t_big.h - tight
    c:put(t_sub, pad, y)
    y = y + t_sub.h + px(10)

    -- the four parts along the bottom, when there is room for them
    local t_pn = c:text("Ag", fpx(19), { bold = true })
    local t_pv = c:text("0%", fpx(24), { bold = true })
    local parts_h = t_pn.h + t_pv.h
    local bottom = h - px(20)
    -- (only when every name fits its quarter of the width)
    local widest_part = c:text(T("Afternoon"), fpx(19), { bold = true }).w
    local show_parts = (bottom - y) - parts_h - px(14) >= px(70) and widest_part <= (w - 2 * pad) / 4 - px(6)
    local hist_bottom = show_parts and (bottom - parts_h - px(14)) or bottom

    -- 24 bars, one per hour; the busiest part of the day in the first accent
    local t_hl = c:text("12a", fpx(18), { bold = true })
    local cozy = cozyOn()
    local shelf_th = cozy and max(4, px(9)) or 0
    local plot_bottom = hist_bottom - t_hl.h - px(6) - shelf_th
    local ph = plot_bottom - y
    if ph >= px(20) then
        local col_w = (w - 2 * pad) / 24
        local bar_w = max(2, floor(col_w * (cozy and 0.76 or 0.66)))
        local radius = min(floor(bar_w / 2), px(4))
        local top_v = 0
        for hr = 0, 23 do top_v = max(top_v, hours[hr]) end
        local heart_s = min(max(bar_w * 1.3, px(14)), px(26))
        if cozy then
            -- room for the heart over the busiest hour
            ph = ph - heart_s - px(2)
            shelf(c, pad, plot_bottom, w - 2 * pad, px, tone)
        else
            c:rect(pad, plot_bottom, w - 2 * pad, max(1, px(2)), A.mix(tone.track, tone.fg, 0.35))
        end
        for hr = 0, 23 do
            local cx = pad + (hr + 0.5) * col_w
            local v = hours[hr]
            if v > 0 then
                local bh = max(max(2, px(4)), round(ph * v / top_v))
                local bx = floor(cx - bar_w / 2)
                if cozy then
                    -- the busiest part of the day in full colour, the rest paler
                    local col = spineColour(hr + 1, tone)
                    if partOf(hr) ~= peak_part then col = A.mix(col, tone.bg, 0.45) end
                    spineUp(c, bx, plot_bottom, bar_w, bh, col, px)
                    if hr == peak_hr then bestHeart(c, cx, plot_bottom - bh, heart_s, tone, px) end
                else
                    local col = partOf(hr) == peak_part and tone.accent or tone.accent2
                    local r = min(radius, floor(bh / 2))
                    c:rrect(bx, plot_bottom - bh, bar_w, bh, r, col, tone.bg)
                    if bh > r and r > 0 then c:rect(bx, plot_bottom - r, bar_w, r, col) end
                end
            end
            if hr % 6 == 0 then
                c:label(hourName(hr, true), fpx(18), pad + hr * col_w, plot_bottom + shelf_th + px(6),
                    { bold = true, color = tone.label })
            end
        end
    end
    if show_parts then
        local cw = (w - 2 * pad) / 4
        local py = bottom - parts_h
        for i, p in ipairs(DAY_PARTS) do
            local x = pad + (i - 1) * cw
            local pct = floor(100 * parts[i] / total + 0.5)
            c:label(p.name, fpx(19), x, py, { bold = true, color = tone.label, max_w = cw - px(6) })
            c:label(pct .. "%", fpx(24), x, py + t_pn.h,
                { bold = true, color = i == peak_part and tone.accent or tone.fg })
        end
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Page heading (dashboard only): small line over a big title, no card
-- ════════════════════════════════════════════════════════════════════════════

-- nav (optional): { prev = bool, next = bool, today = bool } puts big month
-- buttons on the right: a Today button (only when away from this month) and
-- two arrow buttons, with tap regions now / prev / next. A button that has
-- nowhere to go is drawn faded.
function P.heading(env, kicker, title, nav)
    local w, h = env.w, env.h
    local bg, fg, dark, accent = A.dashPage()
    local c = A.canvas{ w = w, h = h, plain = true }
    local s = h / 150
    local px, fpx = scaler(s, env.ts)
    local room = w
    local btn = {}
    if nav then
        -- as big as the heading allows: thumb-sized on a Kobo
        local bs = max(32, floor(min(h * 0.8, w * 0.11)))
        local gap = max(8, floor(bs * 0.2))
        local x = w - bs
        btn.next = { x = x, w = bs }
        x = x - gap - bs
        btn.prev = { x = x, w = bs }
        if nav.today then
            local t_today = c:text(T("Today"), fpx(30), { bold = true })
            local tw = t_today.w + floor(bs * 0.7)
            x = x - floor(gap * 1.6) - tw
            btn.now = { x = x, w = tw }
        end
        btn.bs = bs
        room = x - px(24)
    end
    local t_k = kicker and c:text(kicker, fpx(24), { bold = true, caps = true, color = accent, max_w = room }) or nil
    local t_t = c:text(title, fpx(74), { bold = true, color = fg, max_w = room })
    local tight = round(t_t.h * 0.14)
    local total = (t_k and t_k.h or 0) + t_t.h - tight
    local y = floor((h - total) / 2)
    if t_k then c:put(t_k, 0, y); y = y + t_k.h - tight end
    c:put(t_t, -round(t_t.px * 0.03), y)
    if nav then
        local bs = btn.bs
        local by = floor((h - bs) / 2)
        local dim = A.mix(fg, bg, 0.7)
        local bw_ = max(3, floor(bs * 0.05))
        local function arrow(b, dir, on)
            local col = on and fg or dim
            c:frame(b.x, by, b.w, bs, floor(bs * 0.28), bw_, col, bg, bg)
            -- a thick chevron, drawn rather than typed, so it is bold at any size
            local cx, cy, a = b.x + b.w / 2, by + bs / 2, bs * 0.17
            local lw = max(3, bs * 0.085)
            local pts = (dir < 0) and { cx + a * 0.55, cy - a, cx - a * 0.45, cy, cx + a * 0.55, cy + a }
                or { cx - a * 0.55, cy - a, cx + a * 0.45, cy, cx - a * 0.55, cy + a }
            c:polyline(pts, lw, col, bg)
        end
        arrow(btn.prev, -1, nav.prev)
        arrow(btn.next, 1, nav.next)
        c:region("prev", btn.prev.x, by, btn.prev.w, bs, px(12))
        c:region("next", btn.next.x, by, btn.next.w, bs, px(12))
        if btn.now then
            -- "Today": the way back, in the colour of the selected tab
            local th = A.theme()
            local fill = A.shown(dark and th.gold or th.wine)
            local on_fill = A.shown(dark and th.ink or th.paper)
            local ph = floor(bs * 0.78)
            local py = floor((h - ph) / 2)
            c:rrect(btn.now.x, py, btn.now.w, ph, ph / 2, fill, bg)
            c:label(T("Today"), fpx(30), btn.now.x + btn.now.w / 2, py + ph / 2,
                { bold = true, anchor = "c", valign = "mid", color = on_fill })
            c:region("now", btn.now.x, by, btn.now.w, bs, px(12))
        end
    end
    return c
end

-- ════════════════════════════════════════════════════════════════════════════
-- Reading trends: the last 90 days against the year, like Apple's Fitness
-- ════════════════════════════════════════════════════════════════════════════

P.trends = {
    does = T("opens the reading progress view"),
    title = T("Reading trends"), tone = "ink", ratio = 0.6, ratio_narrow = 1.15,
    summary = T("Your last 90 days against your year, like the trends in Apple's Fitness app. Needs the statistics plugin."),
}

local TREND_GROUPS = {
    { id = "keep", title = T("Keep it going") },
    { id = "look", title = T("Worth a look") },
    { id = "more", title = T("Needs more data") },
}

local SAMPLE_TRENDS = {
    { id = "time", name = T("Time read"), unit = T("min/day"), recent = 107, base = 92, group = "keep" },
    { id = "pages", name = T("Pages"), unit = T("pages/day"), recent = 312, base = 268, group = "keep" },
    { id = "days", name = T("Reading days"), unit = T("days/week"), recent = 6.4, base = 5.9, group = "keep" },
    { id = "books", name = T("Books finished"), unit = T("books/month"), recent = 4.3, base = 3.6, group = "keep" },
    { id = "session", name = T("Session length"), unit = T("min/session"), recent = 24, base = 31, group = "look",
      hint = T("Your sittings are shorter lately. One long read a week helps.") },
    { id = "speed", name = T("Reading speed"), unit = T("pages/hr"), recent = 68, base = 74, group = "look",
      hint = T("Slower pages can just mean a denser book.") },
}

-- Six colours that read apart on colour e-ink, starting from the card's lead
-- accent and stepping round the palette.
local function trendColours(tone)
    local id1 = A.accentIds()
    local start = 1
    for i, id in ipairs(A.ACCENT_ORDER) do if id == id1 then start = i end end
    local out = {}
    for k = 0, 5 do
        local fam = A.ACCENTS[A.ACCENT_ORDER[(start - 1 + k * 2) % #A.ACCENT_ORDER + 1]]
        out[k + 1] = tone.dark and fam.bright or fam.deep
    end
    return out
end

local function trendValue(item, v)
    if v == nil then return "\xE2\x80\x93" end
    if item.id == "days" or item.id == "books" then return A.decimal(v) end
    return A.thousands(floor(v + 0.5))
end

-- The sticky notes' little drawings: a sprout growing (up), a leaf drooping
-- (down), a small sun (holding steady / not enough yet).
local function trendDoodle(c, cx, cy, r, dir, tone, px)
    local L = gardenLook(tone)
    local rad = math.rad
    if dir == "up" then
        c:sprite(cx, cy + r * 0.25, r * 2.1, 0, {
            { "s", 0, 0.42, 0, -0.06, 0.05, L.stem },
            { "v", 0, -0.02, 0.5, 0.17, rad(-150), L.leaf, L.leaf_line, true },
            { "v", 0, -0.04, 0.58, 0.19, rad(-30), L.leaf, L.leaf_line, true },
            { "e", 0, 0.46, 0.3, 0.07, 0, A.mix(L.leaf_line, { 120, 80, 40 }, 0.6) },
        }, { lw = max(1, px(2)) })
    elseif dir == "down" then
        local dry, dry_line = { 196, 176, 104 }, { 140, 120, 60 }
        c:sprite(cx, cy, r * 2.1, 0, {
            { "s", -0.3, -0.42, -0.06, -0.12, 0.045, dry_line },
            { "v", -0.08, -0.14, 0.62, 0.2, rad(62), dry, dry_line, true },
        }, { lw = max(1, px(2)) })
    else
        local sun = { 255, 204, 80 }
        local parts = { { "e", 0, 0, 0.22, 0.22, 0, sun, { 226, 160, 40 } } }
        for k = 0, 7 do
            local a = k * math.pi / 4
            parts[#parts + 1] = { "s", 0.32 * math.cos(a), 0.32 * math.sin(a), 0.44 * math.cos(a), 0.44 * math.sin(a), 0.045, sun }
        end
        c:sprite(cx, cy, r * 2, 0, parts, { lw = max(1, px(2)) })
    end
end

-- A chevron in a circle: up, down, or a dash for "not yet".
local function trendBadge(c, cx, cy, r, dir, col, disc)
    c:disc(cx, cy, r, disc)
    local a = r * 0.42
    local lw = max(2, r * 0.2)
    if dir == "up" then
        c:polyline({ cx - a, cy + a * 0.45, cx, cy - a * 0.5, cx + a, cy + a * 0.45 }, lw, col, disc)
    elseif dir == "down" then
        c:polyline({ cx - a, cy - a * 0.45, cx, cy + a * 0.5, cx + a, cy - a * 0.45 }, lw, col, disc)
    else
        c:rrect(floor(cx - a), floor(cy - lw / 2), floor(2 * a), max(2, floor(lw)), lw / 2, col, disc)
    end
end

function P.trends.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 760, h / 560)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local list
    if env.sample then list = SAMPLE_TRENDS else list = D.trends(env.refresh) end
    if list == false then
        return emptyState(env, c, s, T("Reading trends"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(36)
    local t_head = c:label(T("Trends"), fpx(22), pad, px(26), { bold = true, caps = true, color = tone.accent })
    local t_sub = c:text(T("Last 90 days vs your year"), fpx(20), { bold = true, color = tone.label })
    if pad + t_head.w + px(24) + t_sub.w <= w - pad then c:put(t_sub, w - pad, px(26) + t_head.base, "r", "base") end
    if not list then
        c:label("\xE2\x80\xA6", fpx(30), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted })
        return c
    end
    local cols = trendColours(tone)
    local colour = {}
    for i, def in ipairs(D.TREND_DEFS) do colour[def.id] = cols[i] end
    local groups = {}
    for _, g in ipairs(TREND_GROUPS) do
        local items = {}
        for _, it in ipairs(list) do if it.group == g.id then items[#items + 1] = it end end
        if #items > 0 then groups[#groups + 1] = { id = g.id, title = g.title, items = items } end
    end

    local top = px(26) + t_head.h + px(10)
    local W, H = w - 2 * pad, h - top - px(24)
    local gap = max(4, px(14))
    local ncol = (W >= 2 * A.screen():scaleBySize(140)) and 2 or 1
    local t_sec = c:text(T("Keep"), fpx(26), { bold = true })
    local sec_h = t_sec.h + px(4)
    local hint_size = fpx(19)
    local t_hint = c:text("Ag", hint_size, {})
    local base_h = px(104)

    -- Plan: section titles, and "worth a look" tiles across the full width
    -- with a hint, while that fits; then plain tiles; then smaller tiles.
    -- rich: "worth a look" tiles across the full width with their hint;
    -- look_wide: across the full width without it
    local look_wide = true
    local function plan(rich, titles, tile_h)
        local total, rows = 0, {}
        for gi, g in ipairs(groups) do
            if titles then total = total + sec_h end
            local wide = (rich or look_wide) and g.id == "look"
            local per = wide and 1 or ncol
            local n_rows = math.ceil(#g.items / per)
            local th = (wide and rich) and (tile_h + t_hint.h * 2 + px(4)) or tile_h
            total = total + n_rows * th + (n_rows - 1) * gap
            if gi < #groups then total = total + gap + px(4) end
            rows[gi] = { per = per, th = th, wide = wide and rich }
        end
        return total, rows
    end
    local function rowsAndGaps(L)
        local n_rows, n_gaps = 0, 0
        for gi, g in ipairs(groups) do
            local r = math.ceil(#g.items / L[gi].per)
            n_rows = n_rows + r
            n_gaps = n_gaps + r - 1 + (gi < #groups and 1 or 0)
        end
        return n_rows, n_gaps
    end
    -- Try the richest layout first; each may shrink its tiles a little (section
    -- titles matter more than big tiles) before the next, plainer one is tried.
    local configs = {
        { rich = true, wide = true, titles = true },
        { rich = false, wide = true, titles = true },
        { rich = false, wide = false, titles = true },
        { rich = false, wide = false, titles = false },
    }
    local rich, titles, tile_h, total, layout
    for ci, cf in ipairs(configs) do
        rich, look_wide, titles, tile_h = cf.rich, cf.wide, cf.titles, base_h
        total, layout = plan(rich, titles, tile_h)
        if total > H then
            local n_rows, n_gaps = rowsAndGaps(layout)
            local floor_h = (ci == #configs) and px(40) or px(72)
            local th = floor(tile_h - (total - H) / max(1, n_rows)) - 1
            if ci == #configs then
                th = floor((H - n_gaps * gap - (#groups - 1) * px(4)) / max(1, n_rows))
            end
            if th >= floor_h then
                tile_h = th
                total, layout = plan(rich, titles, tile_h)
            elseif ci == #configs then
                tile_h = floor_h
                total, layout = plan(rich, titles, tile_h)
            end
        end
        if total <= H then break end
    end
    if total > H then
        -- a very small card: as many tiles as fit, the best news first
        local max_rows = max(1, floor((H + gap) / (tile_h + gap)))
        local keep_n = max_rows * ncol
        local cut, n = {}, 0
        for _, g in ipairs(groups) do
            local items = {}
            for _, it in ipairs(g.items) do
                if n < keep_n then items[#items + 1] = it; n = n + 1 end
            end
            if #items > 0 then cut[#cut + 1] = { id = g.id, title = g.title, items = items } end
        end
        groups = cut
        rich, look_wide, titles = false, false, false
        total, layout = plan(rich, titles, tile_h)
    end

    local tile_bg = A.mix(tone.bg, tone.fg, tone.dark and 0.14 or 0.07)
    local disc_bg = tone.dark and A.mix(tone.bg, tone.fg, 0.24) or tone.bg
    -- the Sticky notes look: each trend on a pastel note with a bit of tape
    local notes = A.get("trends_look", "plain") == "notes"
    local NOTE = { { 255, 240, 158 }, { 255, 214, 228 }, { 204, 240, 218 }, { 208, 226, 252 }, { 230, 216, 252 }, { 255, 224, 196 } }
    local note_i = 0
    local y = top + max(0, floor((H - total) / 2 * 0.4))
    for gi, g in ipairs(groups) do
        if titles then
            c:label(g.title, fpx(26), pad, y, { bold = true, color = tone.fg })
            y = y + sec_h
        end
        local L = layout[gi]
        local tw = floor((W - (L.per - 1) * gap) / L.per)
        for i, it in ipairs(g.items) do
            local col_i = (i - 1) % L.per
            local row_i = floor((i - 1) / L.per)
            local x = pad + col_i * (tw + gap)
            local ty = y + row_i * (L.th + gap)
            local th = L.th
            local note_bg
            if notes then
                note_i = note_i + 1
                local pastel = NOTE[(note_i - 1) % #NOTE + 1]
                note_bg = tone.dark and A.mix(tone.bg, pastel, 0.3) or pastel
                local sh = max(2, px(4))
                c:rrect(x + sh, ty + sh, tw, th, px(4), A.mix(tone.bg, { 0, 0, 0 }, tone.dark and 0.5 or 0.14))
                c:rrect(x, ty, tw, th, px(4), note_bg)
                -- a darker strip where the note is stuck down
                c:rect(x, ty, tw, max(2, px(5)), A.mix(note_bg, { 0, 0, 0 }, 0.06))
            else
                c:rrect(x, ty, tw, th, min(px(24), floor(tile_h / 3)), tile_bg)
            end
            local k = tile_h / base_h
            local r = floor(tile_h * 0.27)
            local col = (it.group == "more") and tone.muted or colour[it.id]
            local bx, by = x + px(16) + r, ty + floor(tile_h / 2)
            local dir = it.group == "keep" and "up" or (it.group == "look" and "down" or "flat")
            if notes then
                trendDoodle(c, bx, by, r, dir, tone, px)
            else
                trendBadge(c, bx, by, r, dir, col, disc_bg)
            end
            local tx = bx + r + px(18)
            local room = x + tw - tx - px(14)
            local f_name, f_val, f_unit = fpx(24 * k), fpx(36 * k), fpx(20 * k)
            local t_name = c:text(it.name, f_name, { color = tone.fg, max_w = room })
            local t_val = c:text(trendValue(it, it.recent), f_val, { bold = true, color = col })
            local t_unit = c:text(it.unit, f_unit, { bold = true, caps = true, color = col, max_w = max(8, room - t_val.w - px(6)) })
            local block = t_name.h + t_val.h - floor(t_val.h * 0.18)
            local ny = ty + floor((tile_h - block) / 2)
            local base_y = ny + t_name.h - floor(t_val.h * 0.18) + t_val.base
            if notes then
                -- a highlighter swoosh under the figure, a little wavy
                local sw = t_val.w + px(5) + t_unit.w + px(8)
                local sy = base_y - floor(t_val.px * 0.16)
                local lw_ = max(4, floor(t_val.px * 0.42))
                local deeper = tone.dark and A.mix(note_bg, { 255, 255, 255 }, 0.18)
                    or { note_bg[1] - (255 - note_bg[1]), note_bg[2] - (255 - note_bg[2]), note_bg[3] - (255 - note_bg[3]) }
                c:polyline({ tx - px(4), sy + px(2), tx + sw * 0.35, sy - px(1), tx + sw * 0.7, sy + px(1), tx + sw, sy - px(2) },
                    lw_, deeper, note_bg)
            end
            c:put(t_name, tx, ny)
            c:put(t_val, tx, base_y, "l", "base")
            c:put(t_unit, tx + t_val.w + px(5), base_y, "l", "base")
            -- the year's figure, when there is room for it
            if it.base and it.group ~= "more" then
                local t_year = c:text(T("year ") .. trendValue(it, it.base), fpx(19 * k), { bold = true, color = tone.label })
                local ex = tx + t_val.w + px(5) + t_unit.w + px(16)
                -- (clear of the folded corner on a sticky note)
                local rx = x + tw - px(14) - (notes and max(px(10), min(floor(th * 0.26), px(26))) or 0)
                if ex + t_year.w <= rx then c:put(t_year, rx, base_y, "r", "base") end
            end
            if L.wide and it.hint then
                local t_h = c:textbox(it.hint, hint_size, tw - (tx - x) - px(14), 2, { color = tone.muted })
                c:put(t_h, tx, ty + tile_h - px(6))
            end
            if notes then
                -- the bottom right corner folded over
                local f = max(px(10), min(floor(th * 0.26), px(26)))
                c:sprite(x + tw, ty + th, f, 0, {
                    { "t", -1, 0, 0, -1, 0, 0, A.mix(tone.bg, { 0, 0, 0 }, tone.dark and 0.5 or 0.14), nil },
                    { "t", -1, 0, 0, -1, -1, -1, A.mix(note_bg, { 0, 0, 0 }, tone.dark and 0.2 or 0.12),
                        A.mix(note_bg, { 0, 0, 0 }, 0.25) },
                }, { lw = 1 })
                -- a bit of tape across the top, a little crooked
                local tape_w = min(tw * 0.3, px(110))
                local turn = math.rad((note_i % 2 == 0) and 4 or -4)
                local tcol = (note_i % 2 == 0) and { 248, 206, 220 } or { 200, 232, 218 }
                c:sprite(x + tw - tape_w * 0.62, ty + px(1), tape_w, turn,
                    { { "r", 0, 0, 0.5, 0.16, 0, 0.02, tone.dark and A.mix(tone.bg, tcol, 0.55) or tcol,
                        A.mix(tcol, { 0, 0, 0 }, 0.15) } }, { lw = 1 })
            end
        end
        local n_rows = math.ceil(#g.items / L.per)
        y = y + n_rows * L.th + (n_rows - 1) * gap + gap + px(4)
    end
    return c
end

function P.trends.tap(env)
    D.dispatch(env.cfg("tap", "reading_progress"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Monthly challenge: one goal for the month, as a single ring
-- ════════════════════════════════════════════════════════════════════════════

P.challenge = {
    does = T("opens the reading calendar"),
    title = T("Monthly challenge"), tone = "ink", ratio = 0.61, ratio_narrow = 0.61,
    summary = T("One goal for the month, picked from your last three months or set by you. Needs the statistics plugin."),
}

local SAMPLE_CHALLENGE = {
    metric = "pages", target = 6000, done = 4210, frac = 4210 / 6000, n_days = 31, day = 18, left_days = 13,
    remaining = 1790, per_day = 128, complete = false, on_pace = true, auto_metric = true, auto_target = true,
}

-- ─── the challenge as a flower ───────────────────────────────────────────────
local PINK = { 246, 166, 200 }
local function flowerLook(tone)
    if tone.dark then
        return { fills = { { 255, 120, 180 }, { 255, 152, 200 }, { 255, 188, 216 }, { 255, 92, 160 } },
            line = { 255, 112, 176 }, empty_line = A.mix(tone.bg, PINK, 0.45), empty = A.mix(tone.bg, PINK, 0.14),
            leaf = { 104, 172, 104 }, leaf_line = { 156, 216, 150 }, sparkle = { 255, 210, 90 } }, { 255, 136, 187 }
    end
    return { fills = { { 222, 84, 148 }, { 236, 126, 176 }, PINK, { 196, 40, 112 } },
        line = { 190, 50, 120 }, empty_line = { 236, 170, 200 }, empty = A.mix(tone.bg, PINK, 0.16),
        leaf = { 120, 178, 110 }, leaf_line = { 70, 128, 72 }, sparkle = { 236, 170, 30 } }, { 190, 50, 120 }
end
local function flowerOn() return A.get("challenge_style", "ring") == "flower" end
A.flowerLook = flowerLook

local function challengeGoal(ch)
    if ch.metric == "minutes" then
        if ch.target >= 120 then return T("Read ") .. figure(floor(ch.target / 6 + 0.5) / 10) .. T(" hours") end
        return T("Read ") .. ch.target .. T(" minutes")
    end
    if ch.metric == "days" then return T("Read on ") .. ch.target .. T(" days") end
    return T("Read ") .. A.thousands(ch.target) .. T(" pages")
end

local function challengeDone(ch)
    if ch.metric == "minutes" then return hoursText(ch.done * 60) .. T(" of ") .. hoursText(ch.target * 60) end
    if ch.metric == "days" then return ch.done .. T(" of ") .. ch.target .. T(" days") end
    return A.thousands(ch.done) .. T(" of ") .. A.thousands(ch.target)
end

local function challengeNeed(ch)
    if ch.complete then
        local over = ch.done - ch.target
        if over <= 0 then return T("Challenge complete!") end
        if ch.metric == "minutes" then return T("Done, ") .. hoursText(over * 60) .. T(" over") end
        if ch.metric == "days" then return T("Done, ") .. A.plural(over, "day", "days") .. T(" over") end
        return T("Done, ") .. A.thousands(over) .. T(" over")
    end
    if ch.metric == "days" then
        return T("Read on ") .. ch.remaining .. T(" of the ") .. (ch.left_days + 1) .. T(" days left")
    end
    if ch.metric == "minutes" then return A.fmtMinutes(math.ceil(ch.per_day)) .. T(" a day to go") end
    return A.plural(math.ceil(ch.per_day), "page", "pages") .. T(" a day to go")
end

function P.challenge.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local ch
    if env.sample then
        ch = SAMPLE_CHALLENGE
    else
        ch = D.challenge(env.refresh, env.cfg("metric", "auto"), tonumber(env.cfg("target", nil)))
    end
    if ch == false then
        return emptyState(env, c, s, T("Monthly challenge"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(30)
    local month = A.date("%B")
    local t_label = c:label(month .. T(" challenge"), fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent })
    if not ch then
        c:label("\xE2\x80\xA6", fpx(30), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted })
        return c
    end
    local right = ch.complete and T("Done") or (ch.left_days == 0 and T("Last day") or (A.plural(ch.left_days, "day", "days") .. T(" left")))
    local t_right = c:text(right, fpx(22), { bold = true, color = tone.label })
    if pad + t_label.w + px(16) + t_right.w <= w - pad then c:put(t_right, w - pad, px(24) + t_label.base, "r", "base") end

    local col = ({ pages = tone.series[1], minutes = tone.series[2], days = tone.series[3] })[ch.metric] or tone.accent
    local top = px(24) + t_label.h + px(10)
    local avail = h - top - px(22)
    local R = min(px(118), floor(avail / 2), floor(w * 0.24))
    local cx, cy = pad + R, top + floor(avail / 2)
    local pct = floor(ch.frac * 100 + 0.5)
    local flower = flowerOn()
    if flower then
        -- a peony coloured in petal by petal; the leaves reach a little past R
        local look
        look, col = flowerLook(tone)
        look.frac = ch.frac
        c:flower(cx, cy, floor(R * 0.9), look)
    else
        local t = max(4, round(R * 0.25))
        c:ring(cx, cy, R, t, min(1, ch.frac), tone.track, col)
        c:label(pct .. "%", fpx(34 * R / px(118)), cx, cy, { bold = true, anchor = "c", valign = "mid", color = tone.fg })
    end

    local tx = cx + R + px(34)
    local room = w - pad - tx
    local lines = {
        { challengeGoal(ch), 30, tone.fg, true },
        { challengeDone(ch) .. (flower and ("  \xC2\xB7  " .. pct .. "%") or ""), 24, col, true },
        { challengeNeed(ch), 21, ch.complete and col or tone.muted, true },
    }
    local status = (not ch.complete) and (ch.on_pace and T("On pace") or T("Behind pace")) or nil
    local size_k = 1
    local texts
    for _ = 1, 4 do
        texts = {}
        local widest = 0
        for i, l in ipairs(lines) do
            texts[i] = c:text(l[1], max(minFont(), floor(fpx(l[2]) * size_k)), { bold = l[4], color = l[3] })
            widest = max(widest, texts[i].w)
        end
        if widest <= room then break end
        size_k = size_k * max(0.6, room / widest)
    end
    local t_status
    if status then
        t_status = c:text(status, max(minFont(), floor(fpx(20) * size_k)), { bold = true,
            color = ch.on_pace and tone.btn_fg or tone.fg })
    end
    local gap_l = px(10)
    local pill_h = t_status and (t_status.h + px(8)) or 0
    local n_lines = 3
    local function height()
        local hsum = 0
        for i = 1, n_lines do hsum = hsum + texts[i].h end
        return hsum + (n_lines - 1) * gap_l + (t_status and (pill_h + gap_l) or 0)
    end
    -- a short card: let the pace pill go, then the last line
    local room_h = h - top - px(12)
    if height() > room_h then t_status = nil end
    if height() > room_h then n_lines = 2 end
    local total = height()
    local y = max(top, cy - floor(total / 2))
    for i = 1, n_lines do
        c:put(texts[i], tx, y)
        y = y + texts[i].h + gap_l
    end
    if t_status then
        local pw = t_status.w + px(24)
        c:rrect(tx, y, pw, pill_h, pill_h / 2, ch.on_pace and col or tone.track)
        c:put(t_status, tx + pw / 2, y + pill_h / 2, "c", "mid")
    end
    -- on a wide card: the running total against a straight line to the target
    local widest = 0
    for i = 1, 3 do widest = max(widest, texts[i].w) end
    local gx0 = tx + widest + px(60)
    local gx1 = w - pad
    if gx1 - gx0 >= px(240) and ch.series and #ch.series > 0 then
        local t_day = c:text("31", fpx(19), { bold = true })
        local gy0 = top + px(34)
        local gy1 = h - px(22) - t_day.h - px(8)
        local top_v = max(ch.target, ch.done) * 1.08
        local function X(d) return gx0 + (gx1 - gx0) * d / ch.n_days end
        local function Y(v) return gy1 - (gy1 - gy0) * v / top_v end
        c:rect(gx0, gy1, gx1 - gx0, max(1, px(2)), tone.track)
        local lw = max(2, px(3))
        local t_goal = c:text("goal", fpx(19), { bold = true, color = tone.label })
        dashed(c, gx0, gx1 - t_goal.w - px(10), floor(Y(ch.target)), max(1, px(2)), px(10), px(8), tone.label)
        c:put(t_goal, gx1, floor(Y(ch.target)), "r", "mid")
        -- the pace line: where the total should be by each day
        local pts = { X(0), Y(0), X(ch.n_days), Y(ch.target) }
        local n = 24
        local dash_pts = {}
        for k = 0, n do
            local f = k / n
            dash_pts[#dash_pts + 1] = pts[1] + (pts[3] - pts[1]) * f
            dash_pts[#dash_pts + 1] = pts[2] + (pts[4] - pts[2]) * f
        end
        for k = 1, #dash_pts - 2, 4 do
            c:polyline({ dash_pts[k], dash_pts[k + 1], dash_pts[k + 2], dash_pts[k + 3] }, max(1, px(2)), tone.label)
        end
        local line = { X(0), Y(0) }
        for d = 1, #ch.series do
            line[#line + 1] = X(d)
            line[#line + 1] = Y(ch.series[d])
        end
        if cozyOn() then
            hill(c, line, floor(gy1), A.mix(tone.bg, col, tone.dark and 0.3 or 0.16))
            c:polyline(line, lw, col)
            c:sprite(X(#ch.series), Y(ch.series[#ch.series]), max(px(26), px(30)), 0, bloomParts(gardenLook(tone)),
                { lw = max(1, px(2)) })
        else
            c:polyline(line, lw, col)
            c:disc(floor(X(#ch.series)), floor(Y(ch.series[#ch.series])), max(3, px(7)), col)
        end
        c:label("1", fpx(19), gx0, gy1 + px(8), { bold = true, color = tone.label })
        c:label(tostring(ch.n_days), fpx(19), gx1, gy1 + px(8), { bold = true, anchor = "r", color = tone.label })
    end
    return c
end

function P.challenge.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Finish forecast: when the books in progress will be done at your pace
-- ════════════════════════════════════════════════════════════════════════════

P.forecast = {
    does = T("opens the book tapped"),
    title = T("Finish forecast"), tone = "ink", ratio = 0.61, ratio_narrow = 0.61,
    summary = T("When you'll finish the books you're reading at your recent pace, and where your year is heading."),
}

local function whenText(fc)
    if not fc then return "\xE2\x80\x93", T("Read a little to get a forecast") end
    if fc.days <= 0 then return T("Today"), T("at your pace") end
    if fc.days == 1 then return T("Tomorrow"), T("at your pace") end
    return A.date("%b", fc.when) .. " " .. tonumber(os.date("%d", fc.when)), T("in ") .. fc.days .. T(" days")
end

-- ─── the forecast as a desk calendar ─────────────────────────────────────────
-- The Calendar look: the finish date on a little tear-off calendar page,
-- the day circled with a heart, washi tape at the top; the other books get a
-- date sticker each.

local function calendarPageOn() return A.get("forecast_look", "plain") == "calendar" end
local function calPage(c, x, y, pw, ph, when, px, fpx, tone)
    local paper = { 255, 254, 250 }
    local band = { 232, 98, 142 }
    local fill, line = cozyHeart(tone)
    c:rrect(x + max(2, px(4)), y + max(2, px(5)), pw, ph, px(8), A.mix(tone.bg, { 0, 0, 0 }, tone.dark and 0.5 or 0.16))
    c:rrect(x, y, pw, ph, px(8), paper)
    local bh = floor(ph * 0.28)
    c:rrect(x, y, pw, bh, px(8), band, paper)
    c:rect(x, y + bh - px(8), pw, px(8), band)
    -- the tear line under the month
    local dash = max(2, px(5))
    for xx = x + px(6), x + pw - px(6) - dash, dash * 2 do c:rect(xx, y + bh + px(4), dash, max(1, px(2)), { 214, 210, 200 }) end
    c:label(A.upper(A.date("%b", when)), floor(bh * 0.62), x + pw / 2, y + bh / 2,
        { bold = true, anchor = "c", valign = "mid", color = { 255, 255, 255 } })
    -- the day, circled with a heart
    local cy = y + bh + (ph - bh) * 0.52
    local hs = min(pw * 0.86, (ph - bh) * 0.96)
    c:heart(x + pw / 2, cy, hs, hs, { outer = 0, line = fill, track = paper, t = max(2, px(4)) })
    local t_day = c:text(tostring(tonumber(os.date("%d", when))), floor((ph - bh) * 0.42), { bold = true, color = { 40, 40, 40 } })
    c:put(t_day, x + pw / 2, cy - (ph - bh) * 0.04, "c", "mid")
    -- washi tape across the top left corner
    c:sprite(x + pw * 0.08, y + pw * 0.06, pw * 0.55, math.rad(-40),
        { { "r", 0, 0, 0.5, 0.14, 0, 0.02, { 200, 232, 218 }, { 150, 200, 178 } } }, { lw = 1 })
    return line
end
local function dateSticker(c, xr, cy, txt, i, fpx, px, tone)
    local t = c:text(txt, fpx(21), { bold = true, color = { 50, 50, 50 } })
    local sw, sh = t.w + px(20), t.h + px(6)
    local col = spineColour(i, { dark = false, bg = tone.bg })
    c:rrect(xr - sw + px(2), cy - sh / 2 + px(3), sw, sh, sh * 0.3, A.mix(tone.bg, { 0, 0, 0 }, tone.dark and 0.5 or 0.14))
    c:frame(xr - sw, cy - sh / 2, sw, sh, sh * 0.3, 1, A.mix(col, { 0, 0, 0 }, 0.25), col)
    c:put(t, xr - sw / 2, cy, "c", "mid")
    return sw
end

function P.forecast.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 546, h / 335)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local books, avg, pace
    if env.sample then
        books = SAMPLE_READING
        avg = { secs = 6420, pages = 312 }
        pace = { done = 29, projected = 36, goal = 36 }
    else
        books = D.reading(3)
        local st = D.stats(env.refresh)
        avg = D.recentAverage(st)
        pace = D.yearPace(D.year(env.refresh))
    end
    if #books == 0 then
        return emptyState(env, c, s, T("Finish forecast"), T("Nothing in progress"),
            T("Open a book and its finish date shows here."))
    end
    local pad = px(30)
    local t_label = c:label(T("Finish forecast"), fpx(22), pad, px(24), { bold = true, caps = true, color = tone.accent })
    if avg.secs > 0 then
        local t_rate = c:text(T("at ") .. A.fmtMinutes(avg.secs / 60) .. T(" a day"), fpx(20), { bold = true, color = tone.label })
        if pad + t_label.w + px(16) + t_rate.w <= w - pad then c:put(t_rate, w - pad, px(24) + t_label.base, "r", "base") end
    end
    local top = px(24) + t_label.h + px(12)
    -- the year's pace along the bottom
    local foot_h = 0
    if pace and pace.projected then
        local txt = T("On pace for ") .. A.plural(pace.projected, "book", "books") .. T(" this year")
        local t_f = c:text(txt, fpx(21), { bold = true, color = tone.fg, max_w = w - 2 * pad })
        foot_h = t_f.h + px(14)
        c:put(t_f, pad, h - px(20) - t_f.h)
        if pace.goal and pace.projected >= pace.goal then
            local t_g = c:text(T("goal ") .. pace.goal, fpx(21), { bold = true, color = tone.accent2 })
            if pad + t_f.w + px(14) + t_g.w <= w - pad then c:put(t_g, w - pad, h - px(20) - t_f.h, "r") end
        end
    end
    local area_h = h - top - px(20) - foot_h
    local files = {}
    local count = A.clamp(tonumber(env.cfg("count", 3)) or 3, 1, 3)
    local others = min(#books - 1, count - 1)
    local wide = (w / h) >= 2.0 and others > 0
    local main_w = wide and floor((w - 2 * pad) * 0.5) or (w - 2 * pad)
    local row_h = px(48)
    -- the first book large: cover, title, the date
    local main = books[1]
    local fc = D.forecastFor(main, avg)
    local big, small = whenText(fc)
    local cov_h = min(area_h, floor(main_w * 0.3 * 1.5))
    local cov_w = floor(cov_h / 1.5)
    local room = main_w - cov_w - px(22)
    local t_title = c:textbox(main.title or "", fpx(26), room, 2, { bold = true, color = tone.fg })
    local t_big = c:text(big, fpx(46), { bold = true, color = tone.accent, max_w = room })
    local t_small = c:text(small, fpx(21), { bold = true, color = tone.muted, max_w = room })
    local block = t_title.h + px(6) + t_big.h + t_small.h
    local cal = calendarPageOn() and fc ~= nil
    local page_h = cal and min(px(150), floor(area_h - t_title.h - px(14))) or 0
    if cal and page_h < px(70) then cal = false end
    if cal then block = t_title.h + px(14) + page_h end
    local small_n = 0
    if not wide and others > 0 then
        small_n = A.clamp(floor((area_h - block - px(10)) / row_h), 0, others)
    end
    local main_h = area_h - small_n * row_h
    cov_h = min(cov_h, main_h)
    cov_w = floor(cov_h / 1.5)
    local cy0 = top + floor((main_h - cov_h) / 2)
    c:cover(main.fp, pad, cy0, cov_w, cov_h, { title = main.title, edge = tone.border or tone.bg })
    files[1] = main.fp or false
    local tx = pad + cov_w + px(22)
    local y = top + max(0, floor((main_h - block) / 2))
    c:put(t_title, tx, y)
    if cal then
        -- the date on a tear-off page, the weekday and "in 7 days" beside it
        y = y + t_title.h + px(14)
        page_h = min(page_h, main_h - (y - top))
        local page_w = floor(page_h * 0.88)
        calPage(c, tx, y, page_w, page_h, fc.when, px, fpx, tone)
        local sx = tx + page_w + px(20)
        local sroom = main_w - (sx - pad)
        if sroom > px(60) then
            local wd = fc.days <= 0 and T("Today") or (fc.days == 1 and T("Tomorrow") or A.date("%A", fc.when))
            local t_wd = c:text(wd, fpx(30), { bold = true, color = tone.accent, max_w = sroom })
            local t_in = c:text(small, fpx(21), { bold = true, color = tone.muted, max_w = sroom })
            local by_ = y + floor((page_h - t_wd.h - t_in.h) / 2)
            c:put(t_wd, sx, by_)
            c:put(t_in, sx, by_ + t_wd.h)
        end
    else
        y = y + t_title.h + px(6)
        c:put(t_big, tx, y)
        c:put(t_small, tx, y + t_big.h - floor(t_big.h * 0.08))
    end
    c:region("book:1", pad, top, main_w, main_h, px(4))
    -- the others, one line each: under the first, or beside it on a wide card
    local lx, lw, ly
    if wide then
        lx = pad + main_w + px(36)
        lw = w - pad - lx
        small_n = A.clamp(floor(area_h / row_h), 0, others)
        ly = top + floor((area_h - small_n * row_h) / 2)
    else
        lx, lw, ly = pad, w - 2 * pad, top + main_h
    end
    for i = 2, 1 + small_n do
        local b = books[i]
        local f2 = D.forecastFor(b, avg)
        local d_txt = f2 and (whenText(f2)) or "\xE2\x80\x93"
        local t_d = c:text(d_txt, fpx(22), { bold = true, color = tone.accent })
        local d_w = t_d.w
        if calendarPageOn() and f2 then d_w = c:text(d_txt, fpx(21), { bold = true }).w + px(20) end
        local t_n = c:text(b.title or "", fpx(22), { color = tone.fg, max_w = lw - d_w - px(20) })
        if not wide or i > 2 then c:rect(lx, ly, lw, max(1, px(2)), tone.track) end
        c:put(t_n, lx, ly + row_h / 2, "l", "mid")
        if calendarPageOn() and f2 then
            dateSticker(c, lx + lw, ly + row_h / 2, d_txt, i, fpx, px, tone)
        else
            c:put(t_d, lx + lw, ly + row_h / 2, "r", "mid")
        end
        files[i] = b.fp or false
        c:region("book:" .. i, lx, ly, lw, row_h)
        ly = ly + row_h
    end
    if not env.sample then A.state.forecast_files = files end
    return c
end

function P.forecast.tap(env, region)
    local i = region and tonumber(region:match("^book:(%d+)$"))
    local fp = i and A.state.forecast_files and A.state.forecast_files[i]
    if fp then D.openBook(env.ctx, fp) end
end

-- ════════════════════════════════════════════════════════════════════════════
-- Control centre: buttons for any action, and the front light
-- ════════════════════════════════════════════════════════════════════════════

P.control = {
    does = T("nothing (each button runs its own action)"),
    title = T("Control centre"), tone = "ink", ratio = 0.3, ratio_narrow = 0.62,
    summary = T("Buttons for any action you choose, with brightness and warmth. Works offline."),
}

local G = {
    wifi = "\xEE\xB2\xA8", night = "\xEE\xB2\x93", bulb = "\xEE\xB7\xA6", rotate = "\xEE\xAD\xB4",
    calendar = "\xEE\x9F\xAC", sleep = "\xEE\xAE\xB1", search = "\xEE\xA9\x88", sun = "\xEE\x9F\x9F",
    flame = "\xEF\x92\x90", puzzle = "\xEE\xAC\xB0",
}
A.GLYPH = G

A.CONTROL_DEFAULTS = {
    { label = T("Wi-Fi"), icon = G.wifi, action = { toggle_wifi = true } },
    { label = T("Night mode"), icon = G.night, action = { night_mode = true } },
    { label = T("Light"), icon = G.bulb, action = { toggle_frontlight = true } },
    { label = T("Rotate"), icon = G.rotate, action = { toggle_rotation = true } },
    { label = T("Calendar"), icon = G.calendar, action = { stats_calendar_view = true } },
    { label = T("Sleep"), icon = G.sleep, action = { suspend = true } },
    { label = T("Search"), icon = G.search, action = { file_search = true } },
    { label = T("Light settings"), icon = G.sun, action = { show_frontlight_dialog = true } },
}

--- The buttons the card shows: what was set for each slot, else the default.
function A.controlButtons(count)
    count = A.clamp(tonumber(count) or 6, 1, 8)
    local saved = A.get("control_buttons", nil)
    local out = {}
    for i = 1, count do
        local e = type(saved) == "table" and saved[i] or nil
        if type(e) ~= "table" or not (type(e.action) == "table" or type(e.plugin) == "table"
                or type(e.menu_path) == "table" or e.internal) then
            e = A.CONTROL_DEFAULTS[i]
        end
        out[i] = e
    end
    return out
end

function A.setControlButton(i, entry)
    local saved = A.get("control_buttons", nil)
    local list = {}
    if type(saved) == "table" then for k = 1, 8 do list[k] = saved[k] or false end end
    for k = 1, 8 do if list[k] == nil then list[k] = false end end
    list[i] = entry or false
    A.set("control_buttons", list)
end

-- A glyph, as large as fits a size x size box, centred on (cx, cy).
local function glyphAt(c, glyph, size, cx, cy, col)
    -- a glyph's ink is smaller than its line box, so size it by its width
    local g = (glyph and glyph ~= "") and glyph or G.puzzle
    local t = c:text(g, size, { symbol = true, color = col })
    if t.w > size * 1.05 then
        t = c:text(g, max(8, floor(size * size / t.w)), { symbol = true, color = col })
    end
    c:put(t, cx, cy, "c", "mid")
end

-- The buttons and the light bars, drawn inside (x0, y0, W, Hh) of canvas c.
-- o = { count, brightness, warmth, prefix (for tap regions), compact }
local function controlPanel(c, env, x0, y0, W, Hh, px, fpx, tone, o)
    local count = A.clamp(tonumber(o.count) or 6, 1, 8)
    local buttons = A.controlButtons(count)
    local light = env.sample and { has_light = true, has_warmth = true, level = 50, warmth = 30, on = true } or D.light()
    local prefix = o.prefix or ""
    local sliders = {}
    if light.has_light and o.brightness then
        sliders[#sliders + 1] = { id = "bright", glyph = G.sun, value = light.on and light.level or 0, col = tone.accent }
    end
    if light.has_warmth and o.warmth then
        -- warmth in a warm colour: orange, or red when orange already leads
        local fam = A.ACCENTS[(A.accentIds()) == "orange" and "red" or "orange"]
        sliders[#sliders + 1] = { id = "warm", glyph = G.flame, value = light.warmth,
            col = tone.dark and fam.bright or fam.deep }
    end
    local sgap = px(14)
    local slider_h = 0
    if #sliders > 0 then
        slider_h = o.compact and A.clamp(floor(Hh * 0.2), px(40), px(58)) or max(px(48), floor(Hh * 0.17))
    end
    -- a small panel keeps its buttons first and lets the bars go
    local min_btn = px(o.compact and 64 or 80)
    while #sliders > 0 and Hh - #sliders * (slider_h + sgap) < min_btn do table.remove(sliders) end
    local btn_h = Hh - #sliders * (slider_h + sgap)
    -- buttons: one row when it is wide enough, else two; in a small panel,
    -- as many as fit
    local min_cell = px(o.compact and 96 or 120)
    local per_row, rows = count, 1
    if W / count < min_cell or btn_h > W / count * 2.2 then
        rows = (btn_h >= 2 * min_btn) and 2 or 1
        per_row = math.ceil(count / rows)
    end
    if o.compact then
        per_row = A.clamp(min(per_row, floor(W / min_cell)), 1, 8)
        count = min(count, per_row * rows)
        rows = math.ceil(count / per_row)
    end
    local cell_w = W / per_row
    local row_h = floor((btn_h - (rows - 1) * px(10)) / rows)
    local t_lab = c:text("Ag", fpx(19), { bold = true })
    local label_h = t_lab.h
    local b = floor(min(cell_w * 0.78, row_h - label_h - px(6)))
    local show_labels = b >= px(40)
    if not show_labels then b = floor(min(cell_w * 0.78, row_h)) end
    b = max(16, b)
    local tile = A.mix(tone.bg, tone.fg, tone.dark and 0.16 or 0.08)
    for i = 1, count do
        local e = buttons[i]
        local r_i = floor((i - 1) / per_row)
        local c_i = (i - 1) % per_row
        local n_in_row = (r_i == rows - 1) and (count - per_row * (rows - 1)) or per_row
        local row_w = n_in_row * cell_w
        local cx = x0 + (W - row_w) / 2 + (c_i + 0.5) * cell_w
        local block = b + (show_labels and (px(6) + label_h) or 0)
        local by = y0 + r_i * (row_h + px(10)) + floor((row_h - block) / 2)
        local on = (not env.sample) and D.toggleState(e) or nil
        -- a picture of the reader's own: just the picture, the size of the
        -- whole button, with no tile behind it. Otherwise the tile and icon.
        local drawn = e.image and c:image(e.image, cx - b / 2, by, b, b)
        if not drawn then
            c:rrect(floor(cx - b / 2), by, b, b, floor(b * 0.28), on and tone.btn or tile)
            glyphAt(c, e.icon or "", floor(b * 0.62), cx, by + b / 2, on and tone.btn_fg or tone.fg)
        end
        if show_labels then
            -- a picture has no tile to light up: its name takes the accent while it's on
            c:label(e.label or "", fpx(19), cx, by + b + px(6), { bold = true, anchor = "c",
                color = (drawn and on) and tone.btn or tone.label, max_w = cell_w - px(6) })
        end
        c:region(prefix .. "btn:" .. i, cx - cell_w / 2, by - px(4), cell_w, block + px(8))
    end
    -- the light: an icon, minus, ten steps, plus, the level
    local sy = y0 + Hh - #sliders * (slider_h + sgap) + sgap
    local right = x0 + W
    for _, sl in ipairs(sliders) do
        local mid = sy + slider_h / 2
        local ib = slider_h
        glyphAt(c, sl.glyph, floor(ib * 0.72), x0 + ib / 2, mid, sl.col)
        local t_val = c:text("100%", fpx(24), { bold = true })
        local val_w = t_val.w
        local bsz = floor(slider_h * 0.8)
        local x = x0 + ib + px(12)
        -- a narrow panel: the level goes first, then the minus and plus
        local show_val, show_pm = true, true
        if right - x - 2 * bsz - val_w - px(56) < px(120) then show_val = false; val_w = 0 end
        if right - x - 2 * bsz - px(42) < px(100) then show_pm = false; bsz = 0 end
        local function roundBtn(bx, sign, id)
            c:disc(bx + bsz / 2, mid, bsz / 2, tile)
            local a = bsz * 0.22
            local lw = max(2, floor(bsz * 0.09))
            c:rect(floor(bx + bsz / 2 - a), floor(mid - lw / 2), floor(2 * a), lw, tone.fg)
            if sign > 0 then c:rect(floor(bx + bsz / 2 - lw / 2), floor(mid - a), lw, floor(2 * a), tone.fg) end
            c:region(prefix .. sl.id .. ":" .. id, bx, sy, bsz, slider_h, px(4))
        end
        if show_pm then roundBtn(x, -1, "-") end
        local seg_x0 = x + (show_pm and (bsz + px(14)) or 0)
        local plus_x = right - (show_val and (val_w + px(14)) or 0) - bsz
        if show_pm then roundBtn(plus_x, 1, "+") end
        local seg_x1 = plus_x - (show_pm and px(14) or 0)
        local n = 10
        local sgap2 = max(2, px(6))
        local seg_w = (seg_x1 - seg_x0 - (n - 1) * sgap2) / n
        local seg_h = max(6, floor(slider_h * 0.42))
        local lit = floor(sl.value / 10 + 0.5)
        if seg_w >= 2 then
            for k = 1, n do
                local sx0 = floor(seg_x0 + (k - 1) * (seg_w + sgap2))
                local sx1 = floor(seg_x0 + (k - 1) * (seg_w + sgap2) + seg_w)
                c:rrect(sx0, floor(mid - seg_h / 2), max(2, sx1 - sx0), seg_h, floor(seg_h / 3), k <= lit and sl.col or tone.track)
                c:region(prefix .. sl.id .. ":" .. k, sx0 - sgap2 / 2, sy, (sx1 - sx0) + sgap2, slider_h)
            end
        end
        if show_val then
            c:label(sl.value .. "%", fpx(24), right, mid, { bold = true, anchor = "r", valign = "mid", color = tone.fg })
        end
        sy = sy + slider_h + sgap
    end
end

-- A tap on a Control centre button or light step (region without prefix).
local function controlTap(env, region, count)
    if type(region) ~= "string" then return end
    local i = tonumber(region:match("^btn:(%d+)$"))
    if i then
        local e = A.controlButtons(count)[i]
        if e then
            A.runTapAction(e, env.ctx)
            -- show the button's new state once the action has run
            local refresh = env.refresh
            if refresh then require("ui/uimanager"):scheduleIn(1, function() pcall(refresh) end) end
        end
        return
    end
    local which, step = region:match("^(%a+):(.+)$")
    if which ~= "bright" and which ~= "warm" then return end
    local light = D.light()
    local cur = which == "bright" and (light.on and light.level or 0) or light.warmth
    local v
    if step == "-" then v = cur - 10 elseif step == "+" then v = cur + 10 else v = (tonumber(step) or 0) * 10 end
    v = A.clamp(floor(v / 10 + 0.5) * 10, which == "bright" and 10 or 0, 100)
    if which == "bright" then D.setLight(v) else D.setWarmth(v) end
end

function P.control.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 1000, h / 300, 1.6)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local pad = px(26)
    controlPanel(c, env, pad, pad, w - 2 * pad, h - 2 * pad, px, fpx, tone, {
        count = env.cfg("count", 6),
        brightness = env.cfg("brightness", true) ~= false,
        warmth = env.cfg("warmth", true) ~= false,
    })
    return c
end

function P.control.controls(region)
    return type(region) == "string" and (region:match("^btn:") or region:match("^bright:") or region:match("^warm:")) ~= nil
end

function P.control.keep(region)
    return type(region) == "string" and (region:match("^bright:") or region:match("^warm:")) ~= nil
end

function P.control.tap(env, region)
    controlTap(env, region, env.cfg("count", 6))
end

-- ════════════════════════════════════════════════════════════════════════════
-- This week vs last week: a sentence and two bars, like Apple Health
-- ════════════════════════════════════════════════════════════════════════════

P.compare = {
    does = T("opens the reading calendar"),
    title = T("This week vs last"), tone = "ink", ratio = 0.62, ratio_narrow = 0.75,
    summary = T("Your average a day this week against last week (or month, or year), like Apple Health. Needs the statistics plugin."),
}

local SAMPLE_COMPARE = {
    time = { period = "week", metric = "time", this = 52, last = 41, dir = "up", label_this = T("This week"), label_last = T("Last week"),
        sentence = T("You're averaging more minutes a day this week than last week.") },
    pages = { period = "week", metric = "pages", this = 268, last = 301, dir = "down", label_this = T("This week"), label_last = T("Last week"),
        sentence = T("You're averaging fewer pages a day this week than last week.") },
}

local function compareData(env, metric)
    if env.sample then return SAMPLE_COMPARE[metric] end
    return D.compare(env.refresh, env.cfg("period", "week"), metric)
end

local function compareValue(cmp, v)
    if v == nil then return "\xE2\x80\x93" end
    return A.thousands(floor(v + 0.5))
end

-- One measure: the heading, the sentence, then a figure and a bar for each
-- period. Returns the height used.
local function compareBlock(c, cmp, x, y, w, h, px, fpx, tone, compact)
    local col = cmp.metric == "pages" and tone.series[1] or tone.series[2]
    local unit = cmp.metric == "pages" and T("pages/day") or T("min/day")
    local yy = y
    if not compact then
        local glyph = cmp.metric == "pages" and "\xEE\x9E\xBD" or "\xEE\xB0\x9A"
        local t_icon = c:text(glyph, fpx(30), { symbol = true, color = col })
        local t_title = c:text(cmp.metric == "pages" and T("Pages") or T("Time read"), fpx(28), { bold = true, color = col })
        c:put(t_icon, x, yy + t_title.h / 2, "l", "mid")
        c:put(t_title, x + t_icon.w + px(10), yy)
        yy = yy + t_title.h + px(8)
    end
    local t_sent = c:textbox(cmp.sentence, fpx(compact and 21 or 28), w, compact and 2 or 3, { bold = true, color = tone.fg })
    c:put(t_sent, x, yy)
    yy = yy + t_sent.h + px(compact and 8 or 14)
    if not compact then
        c:rect(x, yy, w, max(1, px(2)), tone.track)
        yy = yy + px(16)
    end
    local top_v = max(cmp.this or 0, cmp.last or 0, 1e-9)
    local rows = { { cmp.this, cmp.label_this, true }, { cmp.last, cmp.label_last, false } }
    -- fit the two rows into what is left
    local left = y + h - yy
    local f_big, f_unit, f_bar = fpx(compact and 30 or 56), fpx(compact and 18 or 26), fpx(compact and 18 or 24)
    local t_probe = c:text("8", f_big, { bold = true })
    local bar_h = max(px(compact and 26 or 44), c:text("Ag", f_bar, { bold = true }).h + px(6))
    local row_h = t_probe.h + bar_h + px(compact and 4 or 14)
    if 2 * row_h > left then
        local k = max(0.6, left / (2 * row_h))
        f_big, f_unit, f_bar = max(minFont(), floor(f_big * k)), max(minFont(), floor(f_unit * k)), max(minFont(), floor(f_bar * k))
        bar_h = max(px(18), floor(bar_h * k))
    end
    for _, r in ipairs(rows) do
        local v, label, current = r[1], r[2], r[3]
        local t_v = c:text(compareValue(cmp, v), f_big, { bold = true, color = tone.fg })
        local t_u = c:text(unit, f_unit, { bold = true, color = tone.muted })
        c:put(t_v, x, yy)
        c:put(t_u, x + t_v.w + px(8), yy + t_v.base, "l", "base")
        local by = yy + t_v.h - floor(t_v.h * 0.06)
        -- no figure yet: a grey stub with the label greyed beside it
        local bw_ = v and max(bar_h, floor(w * v / top_v)) or bar_h
        local cozy = cozyOn()
        if cozy then
            local fill = not v and tone.track or (current and spineColour(1, tone) or A.mix(spineColour(2, tone), tone.bg, 0.25))
            spineFlat(c, x, by, bw_, bar_h, fill, px)
        else
            local fill = (v and current) and col or tone.track
            c:rrect(x, by, bw_, bar_h, floor(bar_h * 0.22), fill)
        end
        -- the label inside its bar, or just past a bar too short to hold it
        local probe = c:text(label or "", f_bar, { bold = true })
        local inside = v ~= nil and bw_ >= probe.w + px(32)
        local l_col = not v and tone.muted or (inside and current and not cozy) and tone.btn_fg or tone.fg
        local t_l = c:text(label or "", f_bar, { bold = true, color = l_col,
            max_w = max(8, w - px(28) - (inside and 0 or bw_)) })
        c:put(t_l, inside and (x + px(16)) or (x + bw_ + px(12)), by + bar_h / 2, "l", "mid")
        yy = by + bar_h + px(compact and 6 or 16)
    end
    return yy - y
end

function P.compare.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 600, h / 420)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local which = env.cfg("show", "time")
    local metrics = which == "both" and { "time", "pages" } or { which == "pages" and "pages" or "time" }
    local first = compareData(env, metrics[1])
    if first == false then
        return emptyState(env, c, s, T("This week vs last"), T("No reading statistics"),
            T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(34)
    if not first then
        c:label("\xE2\x80\xA6", fpx(30), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted })
        return c
    end
    -- both measures side by side on a wide card, one above the other on a
    -- tall one, else just the first
    local W, H = w - 2 * pad, h - 2 * pad
    if #metrics == 2 and w / h >= 1.6 then
        local cw = floor((W - px(40)) / 2)
        compareBlock(c, first, pad, pad, cw, H, px, fpx, tone)
        local second = compareData(env, metrics[2])
        if second then compareBlock(c, second, pad + cw + px(40), pad, cw, H, px, fpx, tone) end
    elseif #metrics == 2 and h / w >= 1.3 then
        local bh = floor((H - px(30)) / 2)
        compareBlock(c, first, pad, pad, W, bh, px, fpx, tone)
        local second = compareData(env, metrics[2])
        if second then compareBlock(c, second, pad, pad + bh + px(30), W, bh, px, fpx, tone) end
    else
        compareBlock(c, first, pad, pad, W, H, px, fpx, tone)
    end
    return c
end

function P.compare.tap(env)
    D.dispatch(env.cfg("tap", "stats_calendar_view"))
end

-- ════════════════════════════════════════════════════════════════════════════
-- Mini dashboard: one row of small cards for the top of the home screen
-- ════════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════════
-- Library: what you own, read and haven't started; authors; a random pick;
-- a quote from your highlights; today's sittings
-- ════════════════════════════════════════════════════════════════════════════

P.library = {
    does = T("nothing"),
    title = T("Library stats"), tone = "ink", ratio = 0.36, ratio_narrow = 0.6,
    summary = T("How many books you own, have read, are reading and haven't started."),
}

local SAMPLE_LIBRARY = { total = 412, counts = { finished = 168, reading = 4, on_hold = 6, unread = 234 } }

-- The four parts of the library, in the order they are drawn.
local function libraryParts(tone, counts)
    local parts = {
        { key = "finished", label = T("Read"), n = counts.finished or 0, col = tone.series[1] },
        { key = "reading", label = T("Reading"), n = counts.reading or 0, col = tone.series[2] },
        { key = "on_hold", label = T("On hold"), n = counts.on_hold or 0, col = tone.label },
        { key = "unread", label = T("Not started"), n = counts.unread or 0, col = tone.track },
    }
    if parts[3].n == 0 then table.remove(parts, 3) end
    return parts
end

-- The bar split into the parts, x..x+w.
local function libraryBar(c, parts, total, x, y, w, bh, tone)
    c:rrect(x, y, w, bh, bh / 2, tone.track)
    local xx = x
    for i, p in ipairs(parts) do
        if p.key ~= "unread" and p.n > 0 then
            local pw = (i == #parts) and (x + w - xx) or max(bh, floor(w * p.n / max(1, total) + 0.5))
            pw = min(pw, x + w - xx)
            if pw > 0 then c:rrect(xx, y, pw, bh, bh / 2, p.col, tone.track) end
            xx = xx + pw
        end
    end
end

function P.library.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 1000, h / 340)
    if w < 760 then s = min(w / 560, h / 420) end
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local lib = env.sample and SAMPLE_LIBRARY or D.library(env.refresh)
    if lib == false then
        return emptyState(env, c, s, T("Library"), T("No library found"), T("Needs Bookshelf's library and the cover browser."))
    end
    local pad = px(38)
    local W = w - 2 * pad
    local t_head = c:label(T("Library"), fpx(24), pad, pad, { bold = true, caps = true, color = tone.accent, max_w = W * 0.6 })
    if not lib then
        c:label(T("Counting your books\xE2\x80\xA6"), fpx(26), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted })
        return c
    end
    local total = lib.total or 0
    local parts = libraryParts(tone, lib.counts)
    local read_pct = total > 0 and floor((lib.counts.finished or 0) * 100 / total + 0.5) or 0
    local t_tot = c:text(A.thousands(total) .. T(" books  \xC2\xB7  ") .. read_pct .. T("% read"), fpx(24), { bold = true, color = tone.fg })
    if t_head.w + t_tot.w + px(20) > W then t_tot = c:text(A.thousands(total) .. T(" books"), fpx(24), { bold = true, color = tone.fg }) end
    if t_head.w + t_tot.w + px(20) <= W then c:put(t_tot, w - pad, pad + t_head.base, "r", "base") end
    local y = pad + t_head.h + px(14)
    local t_line = c:textbox(T("You've read ") .. read_pct .. T("% of your library."), fpx(30), W, 1, { bold = true, color = tone.fg })
    local bh = max(8, px(26))
    -- the figures: one row of up to four, or two rows of two when narrow
    local cols = (W / #parts >= px(190)) and #parts or 2
    local rows_n = math.ceil(#parts / cols)
    local t_big = c:text("8", fpx(56), { bold = true })
    local t_small = c:text("Ag", fpx(22), { bold = true })
    local fig_h = t_big.h + t_small.h
    local need = t_line.h + px(14) + bh + px(22) + rows_n * fig_h + (rows_n - 1) * px(10)
    local room = h - pad - y
    -- the sentence only on a roomy card: the figures matter more
    local show_line = need + t_line.h <= room
    if not show_line then need = need - t_line.h - px(14) end
    local k = 1
    if need > room then k = max(0.55, room / need) end
    y = y + max(0, floor((room - need * k) / 2))
    if show_line then
        c:put(t_line, pad, y)
        y = y + t_line.h + px(14)
    end
    libraryBar(c, parts, total, pad, y, W, max(6, floor(bh * k)), tone)
    y = y + floor(bh * k) + floor(px(22) * k)
    local cw = W / cols
    for i, p in ipairs(parts) do
        local col_i = (i - 1) % cols
        local row_i = floor((i - 1) / cols)
        local x = pad + col_i * cw
        local yy = y + row_i * floor((fig_h + px(10)) * k)
        local t_n = c:text(A.thousands(p.n), max(minFont(), floor(fpx(56) * k)), { bold = true, color = tone.fg, max_w = cw - px(8) })
        c:put(t_n, x, yy)
        local dot = max(4, floor(px(16) * k))
        local ly = yy + t_n.h
        local t_l = c:text(p.label, max(minFont(), floor(fpx(22) * k)), { bold = true, color = tone.label, max_w = cw - dot - px(18) })
        local dc = p.key == "unread" and (tone.border or tone.label) or p.col
        if p.key == "unread" then
            c:frame(x, ly + t_l.h / 2 - dot / 2, dot, dot, dot / 2, max(1, px(3)), dc, tone.bg)
        else
            c:rrect(x, ly + t_l.h / 2 - dot / 2, dot, dot, dot / 2, dc)
        end
        c:put(t_l, x + dot + px(10), ly)
    end
    return c
end

P.authors = {
    does = T("nothing"),
    title = T("Most-read authors"), tone = "ink", ratio = 0.5, ratio_narrow = 0.75,
    summary = T("The authors you've read most, by books finished or by hours read."),
}

local SAMPLE_AUTHORS = {
    books = { { name = "Stephen King", n = 9 }, { name = "Grady Hendrix", n = 5 }, { name = "Shirley Jackson", n = 4 },
              { name = "Gillian Flynn", n = 3 }, { name = "Tana French", n = 3 } },
    time = { { name = "Stephen King", n = 151200 }, { name = "Grady Hendrix", n = 70200 }, { name = "Tana French", n = 52200 },
             { name = "Shirley Jackson", n = 39600 }, { name = "Gillian Flynn", n = 32400 } },
}

local function authorValue(by, n)
    if by == "time" then return hoursText(n) end
    return A.plural(n, "book", "books")
end

function P.authors.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 600, h / 420)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local by = env.cfg("by", "books") == "time" and "time" or "books"
    local list = env.sample and SAMPLE_AUTHORS[by] or D.authors(env.refresh, by)
    if list == false then
        return emptyState(env, c, s, T("Most-read authors"), T("Nothing to count yet"),
            by == "time" and T("Needs the Reading statistics plugin.") or T("Needs Bookshelf's library."))
    end
    local pad = px(36)
    local W = w - 2 * pad
    local t_head = c:label(T("Most-read authors"), fpx(24), pad, pad, { bold = true, caps = true, color = tone.accent, max_w = W })
    local t_by = c:text(by == "time" and T("by time") or T("by books"), fpx(22), { bold = true, color = tone.label })
    if t_head.w + t_by.w + px(20) <= W then c:put(t_by, w - pad, pad + t_head.base, "r", "base") end
    if not list then return c end
    if #list == 0 then
        c:label(by == "time" and T("No reading time yet") or T("No finished books yet"), fpx(26), w / 2, h / 2,
            { anchor = "c", valign = "mid", bold = true, color = tone.muted, max_w = W })
        return c
    end
    local want = tonumber(env.cfg("count", 5)) or 5
    local top = pad + t_head.h + px(14)
    local room = h - pad - top
    local t_probe = c:text("Ag", fpx(26), { bold = true })
    local bar_h = max(4, px(10))
    local row_h = t_probe.h + bar_h + px(14)
    local n = min(want, #list, max(1, floor((room + px(14)) / row_h)))
    if n * row_h > room + px(14) then row_h = floor((room + px(14)) / n) end
    local hi = max(1, list[1].n)
    local yy = top + max(0, floor((room - n * row_h + px(14)) / 2))
    for i = 1, n do
        local a = list[i]
        local col = i == 1 and tone.series[1] or tone.series[2]
        local t_v = c:text(authorValue(by, a.n), fpx(24), { bold = true, color = tone.fg })
        local t_rank = c:text(tostring(i), fpx(26), { bold = true, color = col })
        local nx = pad + max(t_rank.w, px(26)) + px(14)
        local t_n = c:text(a.name, fpx(26), { bold = true, color = tone.fg, max_w = w - pad - nx - t_v.w - px(16) })
        c:put(t_rank, pad, yy)
        c:put(t_n, nx, yy)
        c:put(t_v, w - pad, yy + t_n.base, "r", "base")
        local by_ = yy + t_n.h + px(2)
        local bw_ = w - pad - nx
        c:rrect(nx, by_, bw_, bar_h, bar_h / 2, tone.track)
        c:rrect(nx, by_, max(bar_h, floor(bw_ * a.n / hi)), bar_h, bar_h / 2, col, tone.track)
        yy = yy + row_h
    end
    return c
end

P.pick = {
    does = T("opens the book"),
    title = T("Random pick"), tone = "paper", ratio = 0.5, ratio_narrow = 0.75,
    summary = T("A book you haven't started, picked from your library, a collection, genres or authors. Only the next book of a series."),
}

local SAMPLE_PICK = { fp = nil, title = "The Salt Crown", authors = { "Mara Vell" }, genres = { T("Fantasy") },
    series = "The Shadow Saga", num = 3, status = "unread" }

local PICK_WHEN = { day = T("Today's pick"), week = T("This week's pick"), month = T("This month's pick"), tap = T("Random pick") }

-- The settings the pick reads, wherever it is drawn (its card or the Mini
-- dashboard): the pick card's own saved values.
local function pickCfg(key, default) return A.get("pick_" .. key, default) end
local function pickSet(key, value) A.set("pick_" .. key, value) end

local function pickChoices()
    local coll
    local name = pickCfg("coll", "")
    if type(name) == "string" and name ~= "" then
        coll = {}
        for _, fp in ipairs(D.collection(name) or {}) do coll[fp] = true end
    end
    return { coll = coll, genres = pickCfg("genres", nil), authors = pickCfg("authors", nil) }
end

--- The book picked for now: book, library, candidates. nil while the library
--- loads, false without one. Keeps the pick for its day, week or month while
--- it is still unstarted (and still matches the choices).
function A.pickNow(refresh)
    local lib = D.library(refresh)
    if not lib then return lib end
    local cands = D.pickCandidates(lib.books, pickChoices())
    local period = D.pickPeriod(pickCfg("every", "week"))
    local st = pickCfg("state", nil)
    if type(st) ~= "table" then st = {} end
    if st.period == period and st.fp then
        for _, b in ipairs(cands) do if b.fp == st.fp then return b, lib, cands end end
    end
    local n = (st.period == period) and (tonumber(st.n) or 0) or 0
    local b = D.pickAt(cands, period, n, st.fp)
    local fp = b and b.fp or nil
    if st.period ~= period or st.fp ~= fp or (tonumber(st.n) or 0) ~= n then
        pickSet("state", { period = period, n = n, fp = fp })
    end
    return b, lib, cands
end

--- "Another": step to the next pick for this period.
function A.pickAgain()
    local lib = D.library()
    if not lib then return end
    local cands = D.pickCandidates(lib.books, pickChoices())
    local period = D.pickPeriod(pickCfg("every", "week"))
    local st = pickCfg("state", nil)
    if type(st) ~= "table" then st = {} end
    local n = ((st.period == period) and (tonumber(st.n) or 0) or 0) + 1
    local b = D.pickAt(cands, period, n, st.fp)
    pickSet("state", { period = period, n = n, fp = b and b.fp or nil })
    A.state.pick_fp = b and b.fp or A.state.pick_fp
end

-- "Book 3 of 4 · The Shadow Saga"
local function seriesText(lib, b)
    if not (b and b.series) then return nil end
    local num, of = D.seriesPlace(lib and lib.books or {}, b)
    if num then
        local shown = num == floor(num) and tostring(floor(num)) or tostring(num)
        return T("Book ") .. shown .. ((of and of >= num) and (T(" of ") .. of) or "") .. "  \xC2\xB7  " .. b.series
    end
    return b.series
end

function P.pick.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 600, h / 420)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local b, lib
    if env.sample then
        b, lib = SAMPLE_PICK, { books = { SAMPLE_PICK, { series = "The Shadow Saga", num = 4 } } }
    else
        b, lib = A.pickNow(env.refresh)
    end
    if b == false or (lib and not b) then
        return emptyState(env, c, s, T("Random pick"), T("Nothing to pick"),
            lib and T("No unstarted books match your choices.") or T("Needs Bookshelf's library."))
    end
    local pad = px(32)
    if b == nil then
        c:label(T("Random pick"), fpx(22), pad, pad, { bold = true, caps = true, color = tone.accent })
        c:label(T("Looking through your books\xE2\x80\xA6"), fpx(24), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted })
        return c
    end
    if not env.sample then A.state.pick_fp = b.fp end
    local cov_h = h - 2 * pad
    local cov_w = floor(cov_h / 1.5)
    if cov_w > (w - 2 * pad) * 0.42 then cov_w = floor((w - 2 * pad) * 0.42); cov_h = floor(cov_w * 1.5) end
    local cy = floor((h - cov_h) / 2)
    c:cover(b.fp, pad, cy, cov_w, cov_h, { title = b.title, edge = tone.border or tone.muted })
    c:region("open", pad, cy, cov_w, cov_h)
    local tx = pad + cov_w + px(26)
    local tw = w - pad - tx
    local btn_h = fpx(54)
    local y = pad
    local kick = PICK_WHEN[pickCfg("every", "week")] or T("Random pick")
    local k_px = fpx(22)
    local k_full = c:text(kick, k_px, { bold = true, caps = true })
    -- a longer heading (some languages) gets smaller before it is cut short
    if k_full.w > tw then k_px = max(minFont(), floor(k_px * tw / k_full.w)) end
    local t_k = c:text(kick, k_px, { bold = true, caps = true, color = tone.accent, max_w = tw })
    local by_ = h - pad - btn_h
    local with_btns = by_ - y >= btn_h * 2.2
    if not with_btns then by_ = h - pad end
    c:put(t_k, tx, y)
    y = y + t_k.h + px(8)
    local room = by_ - px(12) - y
    local t_title = c:textbox(b.title or "", fpx(32), tw, 3, { bold = true, color = tone.fg })
    if t_title.h > room * 0.6 then t_title = c:textbox(b.title or "", fpx(32), tw, 2, { bold = true, color = tone.fg }) end
    if t_title.h > room then t_title = c:textbox(b.title or "", fpx(28), tw, 1, { bold = true, color = tone.fg }) end
    local lines = { t_title }
    if b.authors and b.authors[1] then
        lines[#lines + 1] = c:text(table.concat(b.authors, ", "), fpx(24), { color = tone.muted, max_w = tw })
    end
    local ser = seriesText(lib, b)
    if ser then lines[#lines + 1] = c:textbox(ser, fpx(22), tw, 2, { bold = true, color = tone.accent2 }) end
    if b.genres and b.genres[1] then
        lines[#lines + 1] = c:text(table.concat(b.genres, ", ", 1, min(#b.genres, 3)), fpx(21), { bold = true, color = tone.label, max_w = tw })
    end
    for _, t in ipairs(lines) do
        if y + t.h > by_ - px(6) then break end
        c:put(t, tx, y)
        y = y + t.h + px(6)
    end
    if with_btns then
        local bgap = px(14)
        local fb = fpx(26)
        local pb = px(22)
        local t_o, t_a, need
        for _ = 1, 3 do
            t_o = c:text(T("Open"), fb, { bold = true, color = tone.btn_fg })
            t_a = c:text(T("Another"), fb, { bold = true, color = tone.fg })
            need = t_o.w + t_a.w + 4 * pb + bgap
            if need <= tw or fb <= minFont() then break end
            fb = max(minFont(), floor(fb * 0.88))
        end
        local two = need <= tw
        local cap = fpx(26) * 8
        local extra = two and floor((tw - need) / 2) or 0
        local w1 = two and min(cap, t_o.w + 2 * pb + extra) or tw
        c:rrect(tx, by_, w1, btn_h, btn_h / 2, tone.btn)
        c:put(t_o, tx + w1 / 2, by_ + btn_h / 2, "c", "mid")
        c:region("open", tx, by_, w1, btn_h, px(6))
        if two then
            local x2 = tx + w1 + bgap
            local w2 = min(cap, t_a.w + 2 * pb + extra)
            c:frame(x2, by_, w2, btn_h, btn_h / 2, max(2, px(4)), tone.border or tone.fg, tone.bg)
            c:put(t_a, x2 + w2 / 2, by_ + btn_h / 2, "c", "mid")
            c:region("another", x2, by_, w2, btn_h, px(6))
        end
    end
    return c
end

function P.pick.tap(env, region)
    if region == "another" then A.pickAgain() return end
    local fp = A.state.pick_fp
    if not fp then return end
    if pickCfg("tap", "open") == "details" then D.showDetails(env.ctx, fp) else D.openBook(env.ctx, fp) end
end
function P.pick.keep(region) return region == "another" end
function P.pick.controls(region) return region == "open" or region == "another" end

P.quote = {
    does = T("opens the book"),
    title = T("Quote of the day"), tone = "tint2", ratio = 0.34, ratio_narrow = 0.6,
    summary = T("One of your own highlights each day, with the book it came from. Uses Bookshelf's quote of the day."),
}

local SAMPLE_QUOTE = { text = T("The rooms go on further than anyone has walked, and every one of them is patient."),
    title = "Piranesi", author = "Susanna Clarke", chapter = T("Chapter 1") }

-- "Piranesi, Susanna Clarke": the cover browser's title and author when it
-- has them (the quote carries the sidecar's, or the file name).
local function quoteSource(q, title_only)
    local title, author = q.title, q.author
    if q.filepath then
        local info = D.info(q.filepath)
        if info and info.title and info.title ~= "" then title = info.title end
        if info and info.author and info.author ~= "" then author = info.author end
    end
    title = title or ""
    if title_only or not author or author == "" then return title end
    return title .. ", " .. author
end

-- The largest text size the quote fits at, down to a floor.
local function fitQuote(c, text, w, room, top_px, floor_px, tone)
    local size = top_px
    while true do
        local line = floor(size * 1.25)
        local lines = max(1, floor(room / line))
        local t = c:textbox(text, size, w, lines, { bold = true, color = tone.fg })
        local probe = c:textbox(text, size, w, nil, { bold = true })
        if probe.h <= room or size <= floor_px then return t end
        size = max(floor_px, floor(size * 0.9))
    end
end

-- ─── notebook paper ──────────────────────────────────────────────────────────
-- The quote cards' Notebook paper look: a sheet of lined paper with a margin
-- line and punched holes, the quote written on the lines, washi tape across
-- the top corners.

local function paperOn() return A.get("quote_look", "plain") == "paper" end
local function paperLook(tone)
    if tone.dark then
        return { paper = { 40, 40, 46 }, rule = { 64, 84, 116 }, margin = { 150, 70, 96 }, edge = { 70, 70, 78 },
            tape = { 214, 150, 176 }, tape_line = { 240, 190, 210 }, tape2 = { 120, 180, 160 }, tape2_line = { 170, 220, 200 } }
    end
    return { paper = { 255, 254, 248 }, rule = { 176, 206, 234 }, margin = { 236, 146, 166 }, edge = { 214, 212, 204 },
        tape = { 248, 200, 216 }, tape_line = { 228, 160, 186 }, tape2 = { 196, 230, 214 }, tape2_line = { 150, 200, 178 } }
end
A.paperLook = paperLook

-- A quote card: heading and Another at the top, the words as large as they
-- fit, the source underneath. o = { head, text, source, sub (a line under the
-- source), extra (smaller text under the words), mark (false: no quote mark),
-- fp (what a tap opens) }
local function drawQuote(env, c, s, o)
    local w, h, tone = env.w, env.h, env.tone
    local px, fpx = scaler(s, env.ts)
    local pad = px(38)
    local left = pad
    local paper = paperOn() and paperLook(tone) or nil
    local sheet = px(14)
    if paper then
        -- the sheet, its holes and its margin line
        c:rrect(sheet, sheet, w - 2 * sheet, h - 2 * sheet, px(6), paper.edge)
        c:rrect(sheet + 1, sheet + 1, w - 2 * sheet - 2, h - 2 * sheet - 2, px(5), paper.paper)
        local hole_r = max(3, px(8))
        local hx = sheet + px(22)
        for k = 1, 3 do
            local hy = sheet + (h - 2 * sheet) * k / 4
            c:disc(hx, hy, hole_r + 1, paper.edge, paper.paper)
            c:disc(hx, hy, hole_r, tone.bg, paper.edge)
        end
        c:rect(sheet + px(48), sheet + 1, max(2, px(3)), h - 2 * sheet - 2, paper.margin)
        pad = px(46)
        left = sheet + px(62)
    end
    local W = w - left - pad
    local t_head = c:label(o.head, fpx(22), left, pad, { bold = true, caps = true, color = tone.accent, max_w = W * 0.6 })
    local pill_h = fpx(50)
    local t_an = c:text(T("Another"), fpx(22), { bold = true, color = tone.fg })
    local pw = t_an.w + fpx(48)
    if t_head.w + pw + px(20) <= W then
        local pxx = w - pad - pw
        local py = pad + t_head.h / 2 - pill_h / 2
        c:frame(pxx, py, pw, pill_h, pill_h / 2, max(2, px(3)), tone.border or tone.fg, paper and paper.paper or tone.bg,
            paper and paper.paper or nil)
        c:put(t_an, pxx + pw / 2, py + pill_h / 2, "c", "mid")
        c:region("another", pxx, py, pw, pill_h, px(12))
    end
    local function tape()
        if not paper then return end
        -- washi tape over the top corners
        local tl = max(px(40), floor(min(w, h) * 0.2))
        c:sprite(sheet + px(6), sheet + px(4), tl, math.rad(-38),
            { { "r", 0, 0, 0.5, 0.16, 0, 0.02, paper.tape, paper.tape_line } }, { lw = 1 })
        c:sprite(w - sheet - px(6), sheet + px(4), tl, math.rad(38),
            { { "r", 0, 0, 0.5, 0.16, 0, 0.02, paper.tape2, paper.tape2_line } }, { lw = 1 })
    end
    if not o.text then
        if o.waiting then
            c:label(o.waiting, fpx(24), w / 2, h / 2, { anchor = "c", valign = "mid", color = tone.muted, max_w = W })
        end
        tape()
        return c
    end
    local t_src = c:text("\xE2\x80\x94 " .. (o.source or ""), fpx(24), { bold = true, color = tone.label, max_w = W })
    local t_sub = o.sub and c:text(o.sub, fpx(20), { bold = true, color = tone.accent2, max_w = W }) or nil
    local foot = t_src.h + (t_sub and (t_sub.h + px(4)) or 0)
    local top = pad + t_head.h + px(10)
    local mark = (o.mark ~= false) and c:text("\xE2\x80\x9C", fpx(96), { bold = true, color = tone.accent }) or nil
    local qx = left + (mark and (floor(mark.w * 0.9) + px(10)) or 0)
    local tw = w - pad - qx
    local t_extra = o.extra and c:textbox(o.extra, fpx(22), tw, 3, { color = tone.muted }) or nil
    local extra_h = t_extra and (t_extra.h + px(10)) or 0
    local room = h - pad - foot - px(14) - top - extra_h
    if t_extra and room < fpx(26) * 2 then
        room, extra_h, t_extra = room + extra_h, 0, nil
    end
    local t_q = fitQuote(c, o.text, tw, room, fpx(36), fpx(22), tone)
    local block = t_q.h + extra_h
    local yy = top + max(0, floor((room + extra_h - block) / 2))
    local sy = min(h - pad - foot, yy + block + px(14))
    if paper then
        -- the ruled lines, one under each line of the quote and on down the page
        local lpx = floor(1.18 * t_q.px + 0.5)
        local first = yy + lpx - floor(t_q.px * 0.12)
        while first - lpx > top do first = first - lpx end
        local lw = max(2, px(2))
        local ry = first
        local snapped = false
        while ry < h - sheet - px(10) do
            c:rect(sheet + px(48) + px(5), ry, w - 2 * sheet - px(48) - px(7), lw, paper.rule)
            -- the source written on the first free line under the quote
            if not snapped and ry - t_src.base - px(2) >= yy + block + px(6) then
                snapped = true
                sy = min(sy, ry - t_src.base - px(2))
                if ry - t_src.base - px(2) <= h - pad - foot then sy = ry - t_src.base - px(2) end
            end
            ry = ry + lpx
        end
    end
    if mark then c:put(mark, left, yy - floor(mark.h * 0.12)) end
    c:put(t_q, qx, yy)
    if t_extra then c:put(t_extra, qx, yy + t_q.h + px(10)) end
    c:put(t_src, qx, sy)
    if t_sub then c:put(t_sub, qx, sy + t_src.h + px(4)) end
    tape()
    c:region("open", 0, 0, w, h)
    return c
end

local function quoteScale(w, h)
    if w < 760 then return min(w / 560, h / 400) end
    return min(w / 1000, h / 340)
end

function P.quote.build(env)
    local w, h = env.w, env.h
    local s = quoteScale(w, h)
    local c = card(env, s)
    local q
    if env.sample then q = SAMPLE_QUOTE
    elseif not D.hasQuotes() then
        return emptyState(env, c, s, T("Quote of the day"), T("Needs a newer Bookshelf"), T("Update Bookshelf to show your highlights here."))
    else
        q = D.quote(env.refresh)
    end
    if q == false or (q and not q.text) then
        return emptyState(env, c, s, T("Quote of the day"), T("No highlights yet"),
            T("Highlight a line while you read and it can show up here."))
    end
    if q and not env.sample then A.state.quote_fp = q.filepath end
    return drawQuote(env, c, s, { head = T("Quote of the day"), text = q and q.text, source = q and quoteSource(q) })
end

function P.quote.tap(env, region)
    if region == "another" then D.nextQuote() return end
    local fp = A.state.quote_fp
    if fp then D.openBook(env.ctx, fp) end
end
function P.quote.keep(region) return region == "another" end
function P.quote.controls(region) return region == "another" end

-- ════════════════════════════════════════════════════════════════════════════
-- Quote of the day 2, 3 and 4: more random highlights, each card with a pick
-- of its own. They never show the same highlight as each other or as Quote of
-- the day, and Another on one leaves the rest alone.
-- ════════════════════════════════════════════════════════════════════════════

local MORE_QUOTES = { "quote2", "quote3", "quote4" }

for i, name in ipairs(MORE_QUOTES) do
    P[name] = {
        does = T("opens the book"),
        title = A.tr("Quote of the day %1", i + 1), tone = "tint2", ratio = 0.34, ratio_narrow = 0.6,
        summary = T("Another random highlight of yours each day, never the same one as your other quote cards."),
    }
end

local function bookSource(fp)
    local info = D.info(fp)
    local title, author = info and info.title or "", info and info.author
    if author and author ~= "" then return title .. ", " .. author end
    return title
end

-- Every highlight in the reading history in one list: { {fp, e}, ... }.
local function allHighlights(hl)
    if not hl._flat then
        local flat = {}
        for _, b in ipairs(hl.books) do
            for _, e in ipairs(b.list) do flat[#flat + 1] = { fp = b.fp, e = e } end
        end
        hl._flat = flat
    end
    return hl._flat
end

local function sameText(a, b)
    local function norm(t) return (t:gsub("%s+", " "):match("^%s*(.-)%s*$")):sub(1, 200) end
    return type(a) == "string" and type(b) == "string" and norm(a) == norm(b)
end

-- Where a card is in today's shuffled list: its own place once Another was
-- tapped today, else its own starting place (each card starts on another one).
local function quotePos(name, day)
    local st = A.get(name .. "_state", nil)
    if type(st) == "table" and st.day == day and tonumber(st.pos) then return tonumber(st.pos) end
    for i, n in ipairs(MORE_QUOTES) do if n == name then return i - 1 end end
    return 0
end

-- From place `from` on, the first one not `taken` and not the highlight
-- Quote of the day is showing.
local function freePlace(flat, order, taken, from)
    local count = #flat
    local q = D.quotePeek()
    local qtext = q and q.text
    local p = from % count
    for _ = 1, count do
        if not taken[p] and not sameText(flat[order[p + 1]].e.text, qtext) then return p end
        p = (p + 1) % count
    end
    return from % count
end

-- Where every quote card is today, settled in order: each skips the places
-- of the cards before it (so two never show the same highlight).
local function quotePlaces(flat, order, day)
    local taken, places = {}, {}
    for _, n in ipairs(MORE_QUOTES) do
        local p = freePlace(flat, order, taken, quotePos(n, day))
        taken[p], places[n] = true, p
    end
    return places
end

-- Another: the next highlight in today's list that no other card is showing.
-- The other cards are kept where they are, so only this one changes.
function A.quoteAgain(name)
    local hl = D.highlights()
    local flat = hl and allHighlights(hl)
    if not flat or #flat == 0 then return end
    local day = os.date("%Y-%m-%d")
    local order = D.dayOrder(#flat, day)
    local places = quotePlaces(flat, order, day)
    local taken = {}
    for _, n in ipairs(MORE_QUOTES) do
        if n ~= name then
            local p = places[n]
            taken[p] = true
            if quotePos(n, day) ~= p then A.set(n .. "_state", { day = day, pos = p }) end
        end
    end
    A.set(name .. "_state", { day = day, pos = freePlace(flat, order, taken, places[name] + 1) })
end

for _, name in ipairs(MORE_QUOTES) do
    P[name].build = function(env)
        local s = quoteScale(env.w, env.h)
        local c = card(env, s)
        local head = T("Quote of the day")
        if env.sample then
            return drawQuote(env, c, s, { head = head, text = SAMPLE_QUOTE.text,
                source = SAMPLE_QUOTE.title .. ", " .. SAMPLE_QUOTE.author })
        end
        local hl = D.highlights(env.refresh)
        if not hl then
            return drawQuote(env, c, s, { head = head, waiting = T("Finding your highlights\xE2\x80\xA6") })
        end
        local flat = allHighlights(hl)
        if #flat == 0 then
            return emptyState(env, c, s, head, T("No highlights yet"),
                T("Highlight a line while you read and it can show up here."))
        end
        local day = os.date("%Y-%m-%d")
        local order = D.dayOrder(#flat, day)
        local pick = flat[order[quotePlaces(flat, order, day)[name] + 1]]
        A.state[name .. "_fp"], A.state[name .. "_text"] = pick.fp, pick.e.text
        return drawQuote(env, c, s, { head = head, text = pick.e.text, source = bookSource(pick.fp) })
    end
    P[name].tap = function(env, region)
        if region == "another" then A.quoteAgain(name) return end
        local fp = A.state[name .. "_fp"]
        if fp then D.openBook(env.ctx, fp) end
    end
    P[name].keep = function(region) return region == "another" end
    P[name].controls = function(region) return region == "another" end
end

P.timeline = {
    does = T("opens the reading calendar"),
    title = T("Today's timeline"), tone = "ink", ratio = 0.36, ratio_narrow = 0.6,
    summary = T("When you read today: each sitting on a line through the day, and the book it was."),
}

local function sampleToday()
    local t = os.date("*t")
    local function at(hh, mm) return os.time{ year = t.year, month = t.month, day = t.day, hour = hh, min = mm } end
    return { sittings = {
        { start = at(7, 10), stop = at(7, 32), secs = 1300, title = "Carrie", book = 1 },
        { start = at(12, 40), stop = at(13, 5), secs = 1500, title = "The Haunting of Hill House", book = 2 },
        { start = at(21, 15), stop = at(22, 20), secs = 3900, title = "Carrie", book = 1 },
    } }
end

local function clockShort(t)
    local tt = os.date("*t", t)
    local hh = tt.hour % 12
    if hh == 0 then hh = 12 end
    return string.format("%d:%02d", hh, tt.min) .. (tt.hour < 12 and " am" or " pm")
end

local function hourMark(hr)
    if hr == 0 or hr == 24 then return "12a" end
    if hr == 12 then return "12p" end
    return (hr % 12) .. (hr < 12 and "a" or "p")
end

-- The day as a line, sittings as blocks along it. Returns the colour of each book.
local function timelineTrack(c, day, x, y, w, bh, px, fpx, tone, labels)
    local t = os.date("*t")
    local d0 = os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
    local first_hr = 6
    for _, sit in ipairs(day.sittings) do first_hr = min(first_hr, os.date("*t", sit.start).hour) end
    local from = d0 + first_hr * 3600
    local span = 24 * 3600 - first_hr * 3600
    local function xAt(when) return x + w * A.clamp((when - from) / span, 0, 1) end
    c:rrect(x, y, w, bh, bh / 2, tone.track)
    local colours, order = {}, 0
    local pal = { tone.series[1], tone.series[2], tone.accent, tone.label }
    for _, sit in ipairs(day.sittings) do
        local k = sit.book or sit.title or 0
        if not colours[k] then order = order + 1; colours[k] = pal[(order - 1) % #pal + 1] end
        local x1, x2 = xAt(sit.start), xAt(max(sit.stop, sit.start + 60))
        local bw_ = max(bh * 0.5, x2 - x1)
        c:rrect(min(x1, x + w - bw_), y, bw_, bh, min(bh / 2, bw_ / 2), colours[k], tone.track)
    end
    -- now
    local now = os.time()
    if now > from then
        local nx = xAt(now)
        c:rect(floor(nx - max(1, px(2))), y - px(8), max(2, px(4)), bh + px(16), tone.fg)
    end
    if labels then
        local marks = {}
        for hr = first_hr, 24, 6 do marks[#marks + 1] = hr end
        if marks[#marks] ~= 24 then marks[#marks + 1] = 24 end
        for i, hr in ipairs(marks) do
            local mx = xAt(d0 + hr * 3600)
            local anchor = (i == 1 and "l") or (i == #marks and "r") or "c"
            c:label(hourMark(hr), fpx(19), mx, y + bh + px(6), { bold = true, color = tone.label, anchor = anchor })
        end
    end
    return colours
end

-- ─── the timeline as a sky ───────────────────────────────────────────────────
-- The Sky look: the day as a strip of sky from a sun in the morning to a moon
-- and stars at night; each daytime sitting a cloud, each evening one a star,
-- bigger the longer it was, and a little heart over "now".

local function skyOn() return A.get("timeline_look", "plain") == "sky" end
local SKY = {   -- hour, colour
    { 0, { 54, 62, 108 } }, { 5, { 120, 118, 168 } }, { 6, { 250, 214, 190 } }, { 8, { 206, 230, 248 } },
    { 15, { 192, 224, 248 } }, { 17.5, { 250, 210, 176 } }, { 19, { 236, 160, 150 } }, { 20.5, { 128, 120, 176 } },
    { 22, { 70, 78, 128 } }, { 24, { 44, 50, 94 } },
}
local function skyAt(hr)
    for i = 2, #SKY do
        local a, b = SKY[i - 1], SKY[i]
        if hr <= b[1] then return A.mix(a[2], b[2], (hr - a[1]) / (b[1] - a[1])) end
    end
    return SKY[#SKY][2]
end
local CLOUD, CLOUD_EDGE = { 255, 255, 255 }, { 150, 168, 188 }
local STAR, STAR_EDGE = { 255, 230, 130 }, { 214, 170, 50 }
local function cloudParts()
    return {
        { "e", 0, 0.12, 0.5, 0.2, 0, CLOUD },
        { "e", -0.26, 0.04, 0.24, 0.2, 0, CLOUD },
        { "e", 0.04, -0.1, 0.28, 0.27, 0, CLOUD },
        { "e", 0.3, 0.04, 0.2, 0.17, 0, CLOUD },
    }
end
local function starParts() return { { "*", 0, 0, 0.5, STAR } } end
-- a sitting's little picture: a cloud by day, a star by night
local function sittingIcon(c, cx, cy, size, night, px)
    if night then
        c:sprite(cx, cy, size, 0, starParts(), { halo = max(1, px(2)), halo_col = STAR_EDGE })
    else
        c:sprite(cx, cy, size * 1.5, 0, cloudParts(), { halo = max(1, px(2)), halo_col = CLOUD_EDGE })
    end
end

local function skyTrack(c, day, x0, y, w0, sh, px, fpx, tone, labels)
    -- the sun just before the strip, the moon just after it
    local icon = floor(sh * 0.78)
    local x, w = x0 + icon + px(10), w0 - 2 * (icon + px(10))
    local t = os.date("*t")
    local d0 = os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
    local first_hr = 6
    for _, sit in ipairs(day.sittings) do first_hr = min(first_hr, os.date("*t", sit.start).hour) end
    local from = d0 + first_hr * 3600
    local span = 24 * 3600 - first_hr * 3600
    local function xAt(when) return x + w * A.clamp((when - from) / span, 0, 1) end
    local function hourAtX(xx) return first_hr + (24 - first_hr) * (xx - x) / w end
    -- the sky, a column at a time, with round ends
    local r = floor(sh * 0.32)
    local step = max(1, px(2))
    for xx = floor(x), floor(x + w) - 1, step do
        local d = min(xx - x, x + w - xx - 1)
        local inset = 0
        if d < r then inset = floor(r - math.sqrt(max(0, r * r - (r - d) * (r - d))) + 0.5) end
        c:rect(xx, y + inset, step, sh - 2 * inset, skyAt(hourAtX(xx + step / 2)))
    end
    -- a few stars in the night sky
    local night_x = xAt(d0 + 21 * 3600)
    if x + w - night_x > sh then
        for k = 1, 6 do
            local sx = night_x + (x + w - night_x - sh * 0.9) * ((k * 0.37) % 1)
            local sy = y + sh * (0.22 + ((k * 0.53) % 1) * 0.56)
            c:sprite(sx, sy, sh * (0.12 + (k % 3) * 0.04), 0, { { "*", 0, 0, 0.5, { 236, 236, 250 } } })
        end
    end
    -- the sun in the morning, the moon at night
    local sun = { 255, 204, 80 }
    local sun_parts = { { "e", 0, 0, 0.26, 0.26, 0, sun, { 226, 160, 40 } } }
    for k = 0, 7 do
        local a = k * math.pi / 4
        sun_parts[#sun_parts + 1] = { "s", 0.36 * math.cos(a), 0.36 * math.sin(a), 0.48 * math.cos(a), 0.48 * math.sin(a), 0.05, sun }
    end
    c:sprite(x0 + icon / 2, y + sh / 2, icon, 0, sun_parts, { lw = max(1, px(2)) })
    local mx = x0 + w0 - icon / 2
    local moon = tone.dark and { 250, 240, 200 } or { 236, 214, 120 }
    c:sprite(mx, y + sh / 2, icon * 0.9, 0, {
        { "e", 0, 0, 0.4, 0.4, 0, moon, { 196, 170, 80 } },
        { "e", 0.2, -0.12, 0.33, 0.33, 0, tone.bg },
    }, { lw = max(1, px(2)) })
    -- the sittings: clouds by day, stars by night, bigger the longer
    for _, sit in ipairs(day.sittings) do
        local hr = os.date("*t", sit.start).hour
        local night = hr >= 19 or hr < 5
        local mins = (sit.secs or 0) / 60
        local size = sh * A.clamp(0.42 + mins / 120, 0.42, 0.95)
        local cx = (xAt(sit.start) + xAt(max(sit.stop, sit.start + 60))) / 2
        cx = A.clamp(cx, x + size * 0.6, x + w - size * 0.6)
        sittingIcon(c, cx, y + sh / 2, size, night, px)
    end
    -- now: a thin line through the sky and a little heart over it
    local now = os.time()
    if now > from then
        local nx = xAt(now)
        c:rect(floor(nx - max(1, px(1))), y, max(2, px(3)), sh, { 255, 255, 255 })
        local hs = max(px(14), sh * 0.32)
        local fill, line = cozyHeart(tone)
        c:heart(nx, y - hs * 0.55, hs, hs, { outer = 1, line = line, fill = fill, track = fill, t = max(1, px(2)) })
    end
    if labels then
        local marks = {}
        for hr = first_hr, 24, 6 do marks[#marks + 1] = hr end
        if marks[#marks] ~= 24 then marks[#marks + 1] = 24 end
        for i, hr in ipairs(marks) do
            local mxx = xAt(d0 + hr * 3600)
            local anchor = (i == 1 and "l") or (i == #marks and "r") or "c"
            c:label(hourMark(hr), fpx(19), mxx, y + sh + px(6), { bold = true, color = tone.label, anchor = anchor })
        end
    end
    return {}
end

function P.timeline.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 1000, h / 340)
    if w < 760 then s = min(w / 560, h / 420) end
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local day = env.sample and sampleToday() or D.today(env.refresh)
    if day == false then
        return emptyState(env, c, s, T("Today's timeline"), T("No reading statistics"), T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(36)
    local W = w - 2 * pad
    local t_head = c:label(T("Today"), fpx(24), pad, pad, { bold = true, caps = true, color = tone.accent, max_w = W * 0.5 })
    if not day then return c end
    local secs = 0
    for _, sit in ipairs(day.sittings) do secs = secs + sit.secs end
    local n = #day.sittings
    local right = n > 0 and (A.fmtMinutes(secs / 60) .. "  \xC2\xB7  " .. A.plural(n, T("sitting"), T("sittings"))) or T("Nothing read yet")
    local t_r = c:text(right, fpx(24), { bold = true, color = n > 0 and tone.fg or tone.muted })
    if t_head.w + t_r.w + px(20) <= W then c:put(t_r, w - pad, pad + t_head.base, "r", "base") end
    local sky = skyOn()
    local y = pad + t_head.h + px(sky and 30 or 22)
    local bh = sky and max(16, px(56)) or max(8, px(34))
    local colours = sky and skyTrack(c, day, pad, y, W, bh, px, fpx, tone, true)
        or timelineTrack(c, day, pad, y, W, bh, px, fpx, tone, true)
    y = y + bh + px(6) + c:text("12a", fpx(19), { bold = true }).h + px(12)
    -- the sittings, newest first, as many as fit
    local t_probe = c:text("Ag", fpx(24), { bold = true })
    local row_h = t_probe.h + px(2)
    local fit = floor((h - floor(pad * 0.6) - y + px(8)) / row_h)
    if n == 0 then
        if fit >= 1 then
            c:label(T("Open a book and each sitting shows up here."), fpx(22), pad, y, { color = tone.muted, max_w = W })
        end
    else
        local cols = (W >= px(sky and 820 or 1100) and fit < n) and 2 or 1
        local cw = (W - (cols - 1) * px(30)) / cols
        local shown = min(n, fit * cols)
        for i = 1, shown do
            local sit = day.sittings[n - i + 1]
            local col_i = floor((i - 1) / fit)
            local row_i = (i - 1) % fit
            local x = pad + col_i * (cw + px(30))
            local yy = y + row_i * row_h
            local dot = max(4, px(16))
            local k = sit.book or sit.title or 0
            if sky then
                -- the sitting's cloud or star beside its time
                local hr = os.date("*t", sit.start).hour
                dot = max(px(14), floor(t_probe.h * 0.8))
                sittingIcon(c, x + dot / 2, yy + t_probe.h / 2, dot * 0.9, hr >= 19 or hr < 5, px)
            else
                c:rrect(x, yy + t_probe.h / 2 - dot / 2, dot, dot, dot / 2, colours[k] or tone.accent)
            end
            local t_when = c:text(clockShort(sit.start), fpx(24), { bold = true, color = tone.fg })
            local t_len = c:text(A.fmtMinutes(sit.secs / 60), fpx(24), { bold = true, color = tone.label })
            local tx = x + dot + px(12)
            c:put(t_when, tx, yy)
            c:put(t_len, x + cw, yy, "r")
            local bx = tx + max(t_when.w, c:text("10:00 pm", fpx(24), { bold = true }).w) + px(18)
            local room = x + cw - t_len.w - px(16) - bx
            if room > px(60) and sit.title then
                c:label(sit.title, fpx(24), bx, yy, { color = tone.muted, max_w = room })
            end
        end
    end
    return c
end

function P.timeline.tap(env) D.dispatch("stats_calendar_view") end

-- ════════════════════════════════════════════════════════════════════════════
-- Cover calendar: each day of the month with the cover of the book you read
-- most that day, and the same for this week. Tap a day for its books.
-- ════════════════════════════════════════════════════════════════════════════

P.calendar = {
    does = T("opens a day's books"),
    title = T("Cover calendar"), tone = "ink", ratio = 1.05, ratio_narrow = 1.2,
    summary = T("Every day this month with the cover of the book you read most that day. Tap a day for its books. Needs the statistics plugin."),
}

P.cover_week = {
    does = T("opens a day's books"),
    title = T("Week in covers"), tone = "ink", ratio = 0.42, ratio_narrow = 0.6,
    summary = T("This week with the cover of the book you read each day. Tap a day for its books. Needs the statistics plugin."),
}

-- A month or week of made-up reading for the module picker's preview.
local function sampleCoverDays(from_t, n)
    local titles = { "Carrie", "The Haunting of Hill House", "Piranesi" }
    local out = {}
    for i = 0, n - 1 do
        if (i * 7) % 5 ~= 1 then
            local d = os.date("%Y-%m-%d", from_t + i * 86400 + 43200)
            out[d] = { { title = titles[(floor(i / 4) % 3) + 1], secs = 1200 + (i * 613) % 3600, pages = 20 + i } }
            if i % 6 == 2 then out[d][2] = { title = titles[((floor(i / 4) + 1) % 3) + 1], secs = 600, pages = 9 } end
        end
    end
    return out
end

local function dayKey(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end

-- One day, flat like the Cover Calendar plugin: a day with reading is its
-- cover (a second book fanned behind it, "+N" for more), centred with room
-- around it; a day without is just its number. Today's number sits on a
-- pill, and today's cover gets a bar underneath.
local function coverCell(c, x, y, w, h, day_n, books, o, px, fpx, tone)
    local is_today, future = o.today, o.future
    if books and books[1] and o.polaroid then
        local L = o.polaroid
        local ratio = o.ratio or 0.84
        local bar = max(3, px(6))
        local below = is_today and (bar + px(5)) or 0
        local two = books[2] ~= nil
        local ang = o.tilt or 0
        -- as big as fits, with room to turn (and for a second one behind)
        -- (a little over the cell's height is fine: pinned photos overlap)
        local pw = min(w * ratio / (1.05 + (two and 0.13 or 0)), (h * ratio - below) * 1.07 / (POLA_RATIO + 0.04))
        local ph = pw * POLA_RATIO
        local cx = x + w / 2 - (two and pw * 0.07 or 0)
        local cy = y + (h - below) / 2
        if two then polaroid(c, cx + pw * 0.15, cy + pw * 0.03, pw, -ang * 1.2, books[2], nil, nil, px, L) end
        local cap_px = max(minFont(), floor(pw * POLA_B * 0.66))
        polaroid(c, cx, cy, pw, ang, books[1], o.caption, cap_px, px, L)
        if #books > 2 and o.num_px then
            local t_more = c:text("+" .. (#books - 2), o.num_px, { bold = true, color = tone.btn_fg })
            local mw, mh = t_more.w + px(10), t_more.h
            local mx, my = cx + pw * 0.5 + (two and pw * 0.15 or 0) - mw + px(2), cy + ph * 0.5 - mh + px(2)
            c:rrect(mx, my, mw, mh, mh * 0.3, tone.label)
            c:put(t_more, mx + mw / 2, my + mh / 2, "c", "mid")
        end
        local box = { x = floor(cx - pw / 2), y = floor(cy - ph / 2), w = floor(pw + (two and pw * 0.15 or 0)), h = floor(ph), captioned = true }
        if is_today then
            c:rrect(cx - pw * 0.4, cy + ph / 2 + px(6), pw * 0.8, bar, bar / 2, tone.accent)
            box.h = box.h + px(6) + bar
        end
        return box
    end
    if books and books[1] then
        local ratio = o.ratio or 0.84
        local bar = max(3, px(6))
        local room_w, room_h = w * ratio, h * ratio - (is_today and (bar + px(5)) or 0)
        local two = books[2] ~= nil
        local fan = two and max(3, floor(min(room_w, room_h * 2 / 3) * 0.13)) or 0
        -- a 2:3 cover that fits the room, leaving space for the fanned one
        local ch = min(room_h - fan / 2, (room_w - fan) * 1.5)
        local cw = floor(ch * 2 / 3)
        ch = floor(ch)
        local bx = floor(x + (w - cw - fan) / 2)
        local by = floor(y + (h - ch - fan / 2 - (is_today and (bar + px(5)) or 0)) / 2)
        if two then
            c:cover(books[2].fp, bx + fan, by + floor(fan / 2), cw, ch, { title = books[2].title, edge = tone.border or tone.track })
        end
        c:cover(books[1].fp, bx, by, cw, ch, { title = books[1].title, edge = tone.border or tone.track })
        if #books > 2 and o.num_px then
            local t_more = c:text("+" .. (#books - 2), o.num_px, { bold = true, color = tone.btn_fg })
            local mw, mh = t_more.w + px(10), t_more.h
            local mx, my = bx + cw + fan - mw + px(4), by + ch + floor(fan / 2) - mh + px(4)
            c:rrect(mx, my, mw, mh, mh * 0.3, tone.label)
            c:put(t_more, mx + mw / 2, my + mh / 2, "c", "mid")
        end
        local bh = ch + floor(fan / 2)
        if is_today then
            c:rrect(bx, by + bh + px(5), cw + fan, bar, bar / 2, tone.accent)
            bh = bh + px(5) + bar
        end
        return { x = bx, y = by, w = cw + fan, h = bh }
    end
    local t_n = c:text(tostring(day_n), o.num_px, { bold = true,
        color = is_today and tone.btn_fg or (future and A.mix(tone.bg, tone.label, 0.45) or tone.label) })
    if is_today then
        local pw, ph = t_n.w + px(18), t_n.h + px(6)
        c:rrect(x + (w - pw) / 2, y + (h - ph) / 2, pw, ph, ph * 0.35, tone.btn)
    end
    c:put(t_n, x + w / 2, y + h / 2, "c", "mid")
end

local function calendarDays(env, which)
    if env.sample then
        if which == "week" then
            local t = os.date("*t")
            local back = (t.wday - D.weekStart()) % 7
            return sampleCoverDays(os.time{ year = t.year, month = t.month, day = t.day - back, hour = 0 }, back + 1)
        end
        local y, m = A.viewMonth()
        return sampleCoverDays(os.time{ year = y, month = m, day = 1, hour = 0 }, tonumber(os.date("%d")) or 20)
    end
    return D.coverDays(env.refresh, which)
end

local function periodTotals(days)
    local secs, pages, seen, n = 0, 0, {}, 0
    for _, list in pairs(days or {}) do
        for _, e in ipairs(list) do
            secs = secs + (e.secs or 0)
            pages = pages + (e.pages or 0)
            local k = e.fp or e.title
            if k and not seen[k] then seen[k] = true; n = n + 1 end
        end
    end
    return n, secs, pages
end

-- The month in three figures across the top: pages, books, time read.
local function calendarStats(c, days, x, y, W, px, fpx, tone)
    local n, secs, pages = periodTotals(days)
    local figs = {
        { A.thousands(pages), T("Pages read"), tone.series[1] },
        { tostring(n), T("Books read"), tone.series[2] },
        { hoursText(secs), T("Time read"), tone.fg },
    }
    -- one line: each figure with its label beside it, the three spread out
    local f_big, f_small = fpx(32), fpx(19)
    local items, total = {}, 0
    for i, f in ipairs(figs) do
        local t_v = c:text(f[1], f_big, { bold = true, color = f[3] })
        local t_l = c:text(f[2], f_small, { bold = true, color = tone.label })
        items[i] = { t_v, t_l }
        total = total + t_v.w + px(10) + t_l.w
    end
    if total > W * 0.94 then
        -- too narrow for the labels: the figures alone
        for _, it in ipairs(items) do it[2] = nil end
    end
    local h_line = items[1][1].h
    local cw = W / 3
    for i, it in ipairs(items) do
        local t_v, t_l = it[1], it[2]
        local wi = t_v.w + (t_l and (px(10) + t_l.w) or 0)
        local ix = (i == 1 and x) or (i == 3 and (x + W - wi)) or (x + cw + (cw - wi) / 2)
        c:put(t_v, ix, y)
        if t_l then c:put(t_l, ix + t_v.w + px(10), y + t_v.base, "l", "base") end
    end
    return h_line
end

function P.calendar.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 1100, h / 1150)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local days = calendarDays(env, "month")
    if days == false then
        return emptyState(env, c, s, T("Cover calendar"), T("No reading statistics"), T("Turn on KOReader's Reading statistics plugin."))
    end
    local y_v, m_v, current = A.viewMonth()
    local pad = px(20)
    local W = w - 2 * pad
    local top = pad
    -- the month and its arrows: the card's own, unless it sits on a Dashboard
    -- page whose title already shows them
    if not (env.nested and env.page_heading) then
        -- wide buttons, easy to hit: Today (when you've stepped away), back, forward
        local pill = fpx(60)
        local aw = floor(pill * 1.7)
        local bw_ = max(2, px(3))
        local function button(label_t, x_right, width, id)
            c:frame(x_right - width, top, width, pill, pill / 2, bw_, tone.border or tone.fg, tone.bg)
            c:put(label_t, x_right - width / 2, top + pill / 2, "c", "mid")
            c:region(id, x_right - width, top, width, pill, px(8))
            return x_right - width - px(14)
        end
        local ax = w - pad
        if not current then
            ax = button(c:text("\xE2\x80\xBA", fpx(46), { bold = true, color = tone.fg }), ax, aw, "next")
        end
        if (tonumber(A.state.month_offset) or 0) > -D.BACK_MONTHS then
            ax = button(c:text("\xE2\x80\xB9", fpx(46), { bold = true, color = tone.fg }), ax, aw, "prev")
        end
        if not current then
            local t_today = c:text(T("Today"), fpx(24), { bold = true, color = tone.fg })
            ax = button(t_today, ax, max(aw, t_today.w + fpx(44)), "now")
        end
        local t_head = c:label(A.monthTitle(y_v, m_v), fpx(26), pad, top + pill / 2,
            { bold = true, caps = true, color = tone.accent, valign = "mid", max_w = max(px(60), ax - pad) })
        if not current then c:region("now", pad, top, t_head.w, pill, px(8)) end
        top = top + pill + px(10)
    end
    -- the month in figures
    if days and h >= px(700) then
        top = top + calendarStats(c, days, pad, top, W, px, fpx, tone) + px(12)
        c:rect(pad, top - px(5), W, max(1, px(2)), tone.track)
        top = top + px(6)
    end
    -- the days of the week
    local ws = D.weekStart()
    local g = max(2, px(6))
    local cw = (W - 6 * g) / 7
    local t_l = c:text("M", fpx(19), { bold = true })
    for i = 0, 6 do
        local wd = ((ws - 1 + i) % 7) + 1
        c:label(DAY_LETTERS[wd] or "", fpx(19), pad + i * (cw + g) + cw / 2, top, { bold = true, anchor = "c", color = tone.label })
    end
    top = top + t_l.h + px(4)
    if not days then return c end
    local n_days = tonumber(os.date("%d", os.time{ year = y_v, month = m_v + 1, day = 0, hour = 12 })) or 30
    local first_wday = tonumber(os.date("%w", os.time{ year = y_v, month = m_v, day = 1, hour = 12 })) + 1
    local offset = (first_wday - ws) % 7
    local n_rows = ceil((offset + n_days) / 7)
    local ch = (h - pad - top - (n_rows - 1) * g) / n_rows
    local now = os.date("*t")
    local num_px = max(minFont(), min(fpx(26), floor(cw * 0.24)))
    local time = env.cfg("time", true) ~= false
    local f_time = max(minFont(), min(fpx(18), floor(cw * 0.15)))
    local time_h = time and (c:text("0 m", f_time, { bold = true }).h) or 0
    local pola = polaroidOn() and polaroidLook(tone) or nil
    if pola then time_h = 0 end
    for d = 1, n_days do
        local slot = offset + d - 1
        local x = pad + (slot % 7) * (cw + g)
        local yy = top + floor(slot / 7) * (ch + g)
        local key = dayKey(y_v, m_v, d)
        local list = days[key]
        local is_today = current and d == now.day
        local future = current and d > now.day
        local secs = 0
        for _, e in ipairs(list or {}) do secs = secs + (e.secs or 0) end
        -- with the time on, the cover and its time are one block, centred
        -- (on a polaroid the time is written on it)
        local box = coverCell(c, floor(x), floor(yy), floor(cw), floor(ch - (list and time_h or 0)), d, list,
            { today = is_today, future = future, num_px = num_px, ratio = (time or pola) and 1 or 0.96,
              polaroid = pola, tilt = tiltFor(d, m_v), caption = (pola and time) and A.fmtMinutes(secs / 60) or nil,
              cap_px = f_time }, px, fpx, tone)
        if list and time and box and not box.captioned then
            c:label(A.fmtMinutes(secs / 60), f_time, x + cw / 2, box.y + box.h + px(1),
                { bold = true, anchor = "c", color = tone.label, max_w = cw })
        end
        if list then c:region("day:" .. key, x, yy, cw, ch) end
    end
    return c
end

-- This week in seven columns: the weekday and date, its cover, the time read.
local function weekStrip(c, env, days, x0, y0, W, H, px, fpx, tone, o)
    local ws = D.weekStart()
    local now = os.date("*t")
    local back = (now.wday - ws) % 7
    local g = max(2, px(o.compact and 6 or 10))
    local cw = (W - 6 * g) / 7
    local f_l = fpx(o.compact and 17 or 19)
    local f_d = fpx(o.compact and 20 or 24)
    local t_d = c:text("30", f_d, { bold = true })
    -- the weekday and date on one line, so the covers get the height
    local head_h = t_d.h
    local t_time = c:text("0 m", f_l, { bold = true })
    local pola = polaroidOn() and polaroidLook(tone) or nil
    local foot_h = (o.time and not pola) and (t_time.h + px(2)) or 0
    local cov_top = y0 + head_h + px(6)
    local cov_h = y0 + H - cov_top - foot_h
    -- covers narrower than the room is tall: the block is centred top to bottom
    local need_h = floor(cw * (pola and POLA_RATIO or 1.5) + 0.5) + px(6)
    if need_h < cov_h then
        local shift = floor((cov_h - need_h) / 2)
        y0, cov_top, cov_h = y0 + shift, cov_top + shift, need_h
    end
    for i = 0, 6 do
        local t = os.time{ year = now.year, month = now.month, day = now.day - back + i, hour = 12 }
        local dt = os.date("*t", t)
        local key = os.date("%Y-%m-%d", t)
        local cx = x0 + i * (cw + g) + cw / 2
        local is_today = i == back
        local future = i > back
        local t_n = c:text(tostring(dt.day), f_d, { bold = true,
            color = is_today and tone.btn_fg or (future and A.mix(tone.bg, tone.label, 0.45) or tone.fg) })
        local t_wd = c:text(DAY_LETTERS[dt.wday] or "", f_l, { bold = true, color = tone.label })
        local gap_l = px(6)
        local nw = is_today and (t_n.w + px(16)) or t_n.w
        local total = t_wd.w + gap_l + nw
        local ny = y0
        local nx = cx - total / 2 + t_wd.w + gap_l + nw / 2
        c:put(t_wd, cx - total / 2, y0 + t_d.h / 2, "l", "mid")
        if is_today then
            local pw, ph = t_n.w + px(16), t_n.h + px(2)
            c:rrect(nx - pw / 2, ny - px(1), pw, ph, ph * 0.35, tone.btn)
        end
        c:put(t_n, nx, ny, "c")
        local list = days and days[key]
        if list then
            local secs = 0
            for _, e in ipairs(list) do secs = secs + (e.secs or 0) end
            local box = coverCell(c, floor(cx - cw / 2), floor(cov_top), floor(cw), floor(cov_h), dt.day, list,
                { today = false, future = false, num_px = f_l, ratio = 1, polaroid = pola, tilt = tiltFor(dt.day, dt.month),
                  caption = (pola and o.time) and A.fmtMinutes(secs / 60) or nil, cap_px = f_l }, px, fpx, tone)
            if o.time and box and not box.captioned then
                c:label(A.fmtMinutes(secs / 60), f_l, cx, box.y + box.h + px(2),
                    { bold = true, anchor = "c", color = tone.label, max_w = cw + g })
            end
            c:region(o.prefix .. "day:" .. key, cx - cw / 2, y0, cw, H)
        end
    end
end

function P.cover_week.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = min(w / 1100, h / 460)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local days = calendarDays(env, "week")
    if days == false then
        return emptyState(env, c, s, T("Week in covers"), T("No reading statistics"), T("Turn on KOReader's Reading statistics plugin."))
    end
    local pad = px(22)
    local t_head = c:label(T("This week"), fpx(22), pad, pad, { bold = true, caps = true, color = tone.accent, max_w = (w - 2 * pad) * 0.6 })
    if days then
        local n, secs = periodTotals(days)
        local t_tot = c:text(A.plural(n, "book", "books") .. "  \xC2\xB7  " .. hoursText(secs), fpx(22), { bold = true, color = tone.label })
        if t_head.w + t_tot.w + px(20) <= w - 2 * pad then c:put(t_tot, w - pad, pad + t_head.base, "r", "base") end
    end
    local top = pad + t_head.h + px(8)
    weekStrip(c, env, days, pad, top, w - 2 * pad, h - pad - top, px, fpx, tone,
        { time = env.cfg("time", true) ~= false, prefix = "" })
    return c
end

-- A day's books in a list; a book opens it.
local function showDay(env, key)
    local which = env.name == "cover_week" and "week" or "month"
    local days = (which == "week" and D.coverDays(nil, "week")) or D.coverDays(nil, "month") or {}
    local list = days[key] or (D.coverDays(nil, which == "week" and "month" or "week") or {})[key]
    local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
    local when = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    A.S.open(env.ctx, A.date("%A %d %B", when), function(api)
        local rows = {}
        for _, e in ipairs(list or {}) do
            local line = e.title .. "  \xC2\xB7  " .. A.fmtMinutes((e.secs or 0) / 60) .. "  \xC2\xB7  " .. A.plural(e.pages or 0, "page", "pages")
            rows[#rows + 1] = { { text = line, enabled = e.fp ~= nil, callback = function()
                api.close()
                if e.fp then D.openBook(env.ctx, e.fp) end
            end } }
        end
        if #rows == 0 then rows[1] = A.S.header(T("Nothing read that day")) end
        return rows
    end)
end
A.showCoverDay = showDay

local function stepCalendar(region)
    local off = tonumber(A.state.month_offset) or 0
    if region == "prev" then A.state.month_offset = max(-D.BACK_MONTHS, off - 1)
    elseif region == "next" then A.state.month_offset = min(0, off + 1)
    elseif region == "now" then A.state.month_offset = 0 end
end

function P.calendar.tap(env, region)
    if type(region) ~= "string" then return end
    local key = region:match("^day:(.+)$")
    if key then return showDay(env, key) end
    stepCalendar(region)
end
function P.calendar.keep(region) return region == "prev" or region == "next" or region == "now" end
function P.calendar.controls(region)
    return type(region) == "string" and (region:match("^day:") ~= nil or P.calendar.keep(region))
end

function P.cover_week.tap(env, region)
    local key = type(region) == "string" and region:match("^day:(.+)$")
    if key then return showDay(env, key) end
end
function P.cover_week.controls(region) return type(region) == "string" and region:match("^day:") ~= nil end

P.mini = {
    does = T("depends on the part tapped"),
    title = T("Mini dashboard"), tone = "ink", ratio = 0.3, ratio_narrow = 0.5,
    summary = T("One row of small cards for the top of the home screen: what you're reading, today's rings and the Control centre, or others you pick."),
}

A.MINI_TILES = { "today", "control", "reading", "rings", "compare", "week", "challenge", "forecast", "goal",
    "timeline", "pick", "quote", "library", "coverweek" }
A.MINI_DEFAULT = { "today", "control" }
A.MINI_MAX = 3
A.MINI_LABEL = {
    today = T("Reading and today's rings"), reading = T("Continue reading"), rings = T("Activity rings"),
    control = T("Control centre"), compare = T("This week vs last"), week = T("Week rings"),
    challenge = T("Monthly challenge"), forecast = T("Finish forecast"), goal = T("Year goal"),
    timeline = T("Today's timeline"), pick = T("Random pick"), quote = T("Quote of the day"), library = T("Library stats"),
    coverweek = T("Week in covers"),
}
-- how much of the row each wants, and the least it can be drawn in (dp)
local MINI_WEIGHT = { today = 2.0, reading = 1.4, rings = 1.25, control = 1.45, compare = 1.5, week = 1.5,
    challenge = 1.15, forecast = 1.2, goal = 0.9, timeline = 1.6, pick = 1.4, quote = 1.8, library = 1.3, coverweek = 2.4 }
local MINI_MIN = { today = 250, reading = 170, rings = 115, control = 120, compare = 165, week = 180,
    challenge = 140, forecast = 140, goal = 105, timeline = 150, pick = 150, quote = 160, library = 150, coverweek = 230 }

--- The kinds of small card in the row, in order (three at most).
function A.miniTiles(env)
    local out, seen = {}, {}
    for i = 1, A.MINI_MAX do
        local v = env.cfg("tile" .. i, A.MINI_DEFAULT[i] or "none")
        if A.MINI_LABEL[v] and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    if #out == 0 then out = { "reading" } end
    return out
end

local MINI = {}

-- A small heading at the top of a tile; returns the y below it.
local function miniHead(c, text, x, y, w, fpx, tone, right)
    local t = c:label(text, fpx(19), x, y, { bold = true, caps = true, color = tone.accent, max_w = w })
    if right then
        local t_r = c:text(right, fpx(19), { bold = true, color = tone.label })
        if t.w + t_r.w + 12 <= w then c:put(t_r, x + w, y + t.base, "r", "base") end
    end
    return y + t.h
end

function MINI.reading(c, env, x, y, w, h, px, fpx, tone)
    local list = readingNow(env)
    local b = list[1]
    if not b then
        c:label(T("Nothing in progress"), fpx(22), x + w / 2, y + h / 2, { bold = true, anchor = "c", valign = "mid",
            color = tone.muted, max_w = w })
        return
    end
    local cov_h = h
    local cov_w = floor(cov_h / 1.5)
    if cov_w > w * 0.38 then cov_w = floor(w * 0.38); cov_h = floor(cov_w * 1.5) end
    local cy = y + floor((h - cov_h) / 2)
    c:cover(b.fp, x, cy, cov_w, cov_h, { title = b.title, edge = tone.border or tone.bg })
    local tx = x + cov_w + px(18)
    local room = x + w - tx
    local days = (not env.sample) and D.dayOfBook(env.refresh, b.fp) or 4
    local lines = {}
    local t_k = c:text(T("Continue reading"), fpx(18), { bold = true, caps = true, color = tone.accent, max_w = room })
    local t_title = c:textbox(b.title or "", fpx(26), room, 2, { bold = true, color = tone.fg })
    if t_title.h > h * 0.42 then t_title = c:textbox(b.title or "", fpx(26), room, 1, { bold = true, color = tone.fg }) end
    local t_author = b.author and c:text(b.author, fpx(20), { color = tone.muted, max_w = room }) or nil
    local pct = floor((b.pct or 0) * 100 + 0.5)
    local t_pct = c:text(pct .. "%" .. (days and ("  \xC2\xB7  " .. A.plural(days, "day", "days")) or ""), fpx(20),
        { bold = true, color = tone.fg, max_w = room })
    local t_left = b.left_min and c:text(A.fmtMinutes(b.left_min) .. T(" left"), fpx(20), { bold = true, color = tone.label,
        max_w = room }) or nil
    local bar_h = max(4, px(9))
    local gap = px(8)
    local function total()
        local sum = 0
        for _, t in ipairs(lines) do sum = sum + (t == "bar" and bar_h or t.h) end
        return sum + (#lines - 1) * gap
    end
    lines = { t_k, t_title, t_author or false, "bar", t_pct, t_left or false }
    local function clean()
        local out = {}
        for _, t in ipairs(lines) do if t then out[#out + 1] = t end end
        lines = out
    end
    clean()
    -- drop what does not fit: the kicker, then the author, then time left
    for _, drop in ipairs{ t_k, t_author, t_left } do
        if total() <= h then break end
        for i, t in ipairs(lines) do if t == drop then table.remove(lines, i) break end end
    end
    local yy = y + max(0, floor((h - total()) / 2))
    for _, t in ipairs(lines) do
        if t == "bar" then
            c:rrect(tx, yy, room, bar_h, bar_h / 2, tone.track)
            if pct > 0 then c:rrect(tx, yy, max(bar_h, floor(room * pct / 100)), bar_h, bar_h / 2, tone.accent, tone.track) end
            yy = yy + bar_h + gap
        else
            c:put(t, tx, yy)
            yy = yy + t.h + gap
        end
    end
    if not env.sample then A.state.mini_reading = b.fp end
    c:region("reading:open", x, y, w, h)
end

-- The book you are reading and today's rings, in one small card.
-- One card: the book you're reading, and under its progress a small row of
-- today's three rings with the pages, minutes and streak beside them.
function MINI.today(c, env, x, y, w, h, px, fpx, tone)
    local b = readingNow(env)[1]
    if not b then return MINI.rings(c, env, x, y, w, h, px, fpx, tone) end
    local st = statsFor(env)
    local cov_h = h
    local cov_w = floor(cov_h / 1.5)
    if cov_w > w * 0.36 then cov_w = floor(w * 0.36); cov_h = floor(cov_w * 1.5) end
    c:cover(b.fp, x, y + floor((h - cov_h) / 2), cov_w, cov_h, { title = b.title, edge = tone.border or tone.bg })
    local tx = x + cov_w + px(20)
    local room = x + w - tx
    local gap = px(8)

    -- the book
    local t_title = c:textbox(b.title or "", fpx(26), room, 2, { bold = true, color = tone.fg })
    if t_title.h > h * 0.3 then t_title = c:textbox(b.title or "", fpx(26), room, 1, { bold = true, color = tone.fg }) end
    local t_author = b.author and c:text(b.author, fpx(20), { color = tone.muted, max_w = room }) or nil
    local pct = floor((b.pct or 0) * 100 + 0.5)
    local pct_str = pct .. "%"
    if b.left_min then pct_str = pct_str .. "  \xC2\xB7  " .. A.fmtMinutes(b.left_min) .. T(" left") end
    local t_pct = c:text(pct_str, fpx(20), { bold = true, color = tone.label, max_w = room })
    local bar_h = max(4, px(9))

    -- today: three small rings and what they count
    local pages = st and st.today.pages or 0
    local mins = st and floor(st.today.secs / 60 + 0.5) or 0
    local streak = st and st.streak or 0
    local cols = tone.series
    if hearts() then
        local c1, c2 = heartColors(tone)
        cols = { c1, c2, tone.series[3] }
    end
    local f_fig = fpx(20)
    local figs = {
        { st and A.plural(pages, "page", "pages") or "\xE2\x80\xA6", cols[1] },
        { st and A.fmtMinutes(mins) or "\xE2\x80\xA6", cols[2] },
        { st and (streak > 0 and (T("Streak ") .. streak) or T("No streak")) or "\xE2\x80\xA6", cols[3] },
    }
    local t_sep = c:text("  \xC2\xB7  ", f_fig, { bold = true, color = tone.label })
    local ft = {}
    for i, f in ipairs(figs) do ft[i] = c:text(f[1], f_fig, { bold = true, color = f[2] }) end
    local dia = max(px(30), min(floor(h * 0.3), ft[1].h * 2))
    local fx_room = room - dia - px(14)
    -- the figures on one line when they fit, else two (pages and minutes, then the streak)
    local one = ft[1].w + ft[2].w + ft[3].w + 2 * t_sep.w <= fx_room
    if one and st then
        -- "2 m read" when there is room for the word
        local t_read = c:text(A.fmtMinutes(mins) .. T(" read"), f_fig, { bold = true, color = cols[2] })
        if ft[1].w + t_read.w + ft[3].w + 2 * t_sep.w <= fx_room then ft[2] = t_read end
    end
    local row_h = max(dia, one and ft[1].h or (ft[1].h * 2))

    local lines = { t_title, t_author or false, "bar", t_pct, "today" }
    local function size(list)
        local sum, n = 0, 0
        for _, t in ipairs(list) do
            if t then
                n = n + 1
                sum = sum + ((t == "bar") and bar_h or (t == "today") and row_h or t.h)
            end
        end
        return sum + (n - 1) * gap
    end
    -- too tall: the author goes first, then the time left
    if size(lines) > h then lines[2] = false end
    if size(lines) > h then lines[4] = false end
    local yy = y + max(0, floor((h - size(lines)) / 2))
    local row_y
    for _, t in ipairs(lines) do
        if t == "bar" then
            c:rrect(tx, yy, room, bar_h, bar_h / 2, tone.track)
            if pct > 0 then c:rrect(tx, yy, max(bar_h, floor(room * pct / 100)), bar_h, bar_h / 2, tone.accent, tone.track) end
            yy = yy + bar_h + gap
        elseif t == "today" then
            row_y = yy
            local R = floor(dia / 2)
            local cx, cy = tx + R, yy + row_h / 2
            local rt = max(2, round(R * 0.215))
            local rg = max(1, round(R * 0.055))
            local page_goal = max(1, tonumber(A.get("activity_page_goal", 30)) or 30)
            local streak_goal = max(1, tonumber(A.get("activity_streak_goal", 7)) or 7)
            if hearts() then
                local c1, c2 = heartColors(tone)
                c:heart(cx, cy, dia, dia, { outer = pages / page_goal, inner = mins / D.dailyMinutesGoal(),
                    line = c1, line_in = c2, track = heartTrack(tone) })
            else
                c:ring(cx, cy, R, rt, pages / page_goal, tone.track, cols[1])
                c:ring(cx, cy, R - rt - rg, rt, mins / D.dailyMinutesGoal(), tone.track, cols[2])
                c:ring(cx, cy, R - 2 * (rt + rg), rt, streak / streak_goal, tone.track, cols[3])
            end
            local fx = tx + dia + px(14)
            if one then
                local xx = fx
                for i = 1, 3 do
                    c:put(ft[i], xx, cy, "l", "mid"); xx = xx + ft[i].w
                    if i < 3 then c:put(t_sep, xx, cy, "l", "mid"); xx = xx + t_sep.w end
                end
            else
                local top = cy - ft[1].h
                c:put(ft[1], fx, top)
                local sep2 = c:text("  \xC2\xB7  ", f_fig, { bold = true, color = tone.label })
                if ft[1].w + sep2.w + ft[2].w <= fx_room then
                    c:put(sep2, fx + ft[1].w, top); c:put(ft[2], fx + ft[1].w + sep2.w, top)
                    c:put(ft[3], fx, cy)
                else
                    c:put(ft[3], fx, cy)
                end
            end
            yy = yy + row_h + gap
        elseif t then
            c:put(t, tx, yy)
            yy = yy + t.h + gap
        end
    end
    if not env.sample then A.state.mini_reading = b.fp end
    -- the first region that holds the tap wins: the rings row, then the rest
    if row_y then c:region("rings:", tx, row_y, room, row_h) end
    c:region("reading:open", x, y, w, h)
end

function MINI.compare(c, env, x, y, w, h, px, fpx, tone)
    local cmp = env.sample and SAMPLE_COMPARE.time or D.compare(env.refresh, A.get("compare_period", "week"),
        A.get("compare_show", "time") == "pages" and "pages" or "time")
    if not cmp then return end
    compareBlock(c, cmp, x, y, w, h, px, fpx, tone, true)
    c:region("compare:", x, y, w, h)
end

function MINI.rings(c, env, x, y, w, h, px, fpx, tone)
    local st = statsFor(env)
    local pages = st and st.today.pages or 0
    local mins = st and floor(st.today.secs / 60 + 0.5) or 0
    local streak = st and st.streak or 0
    local page_goal = max(1, tonumber(A.get("activity_page_goal", 30)) or 30)
    local min_goal = D.dailyMinutesGoal()
    local streak_goal = max(1, tonumber(A.get("activity_streak_goal", 7)) or 7)
    local cols = tone.series
    if hearts() then
        local c1, c2 = heartColors(tone)
        cols = { c1, c2, tone.series[3] }
    end
    local lines = {
        st and A.plural(pages, "page", "pages") or "\xE2\x80\xA6",
        st and (A.fmtMinutes(mins) .. T(" read")) or "\xE2\x80\xA6",
        st and (streak > 0 and (T("Streak ") .. streak) or T("No streak")) or "\xE2\x80\xA6",
    }
    local texts, widest = {}, 0
    for i, str in ipairs(lines) do
        texts[i] = c:text(str, fpx(22), { bold = true, color = cols[i] })
        widest = max(widest, texts[i].w)
    end
    -- the rings beside their figures while the rings can stay a fair size
    local R = floor(min(h / 2, (w - px(16) - widest) / 2))
    local with_text = R >= h * 0.22
    if not with_text then R = floor(min(h / 2, w / 2)) end
    local cx = with_text and (x + R) or (x + w / 2)
    local cy = y + h / 2
    local t = max(3, round(R * 0.215))
    local g = max(1, round(R * 0.055))
    if hearts() then
        c:heart(cx, cy, 2 * R, 2 * R, { outer = pages / page_goal, inner = mins / min_goal, line = cols[1], line_in = cols[2],
            track = heartTrack(tone) })
    else
        c:ring(cx, cy, R, t, pages / page_goal, tone.track, cols[1])
        c:ring(cx, cy, R - t - g, t, mins / min_goal, tone.track, cols[2])
        c:ring(cx, cy, R - 2 * (t + g), t, streak / streak_goal, tone.track, cols[3])
    end
    if with_text then
        local step = min(floor((2 * R) / 3), texts[1].h + px(6))
        for i = 1, 3 do c:put(texts[i], cx + R + px(16), cy + (i - 2) * step, "l", "mid") end
    end
    c:region("rings:", x, y, w, h)
end

function MINI.control(c, env, x, y, w, h, px, fpx, tone)
    controlPanel(c, env, x, y, w, h, px, fpx, tone, {
        count = A.get("control_count", 6), prefix = "control:", compact = true,
        brightness = A.get("control_brightness", true) ~= false,
        warmth = A.get("control_warmth", true) ~= false,
    })
end

function MINI.week(c, env, x, y, w, h, px, fpx, tone)
    local st = statsFor(env)
    local week = st and st.week or {}
    local cols = tone.series
    local page_goal = max(1, tonumber(A.get("activity_page_goal", 30)) or 30)
    local min_goal = D.dailyMinutesGoal()
    local top = miniHead(c, T("This week"), x, y, w, fpx, tone,
        st and (A.plural(st.week_pages, "page", "pages")) or nil) + px(8)
    local t_l = c:text("M", fpx(19), { bold = true })
    local col_w = w / 7
    local d = min(floor(col_w * 0.88), floor(y + h - top - t_l.h - px(6)))
    if d < 10 then return end
    local R = d / 2
    local rt = max(2, round(R * 0.27))
    local g = max(1, round(R * 0.08))
    local cy = top + t_l.h + px(6) + R
    local ws = D.weekStart()
    for i = 1, 7 do
        local day = week[i] or { pages = 0, secs = 0, wday = ((ws + i - 2) % 7) + 1, future = true }
        local cx = x + (i - 0.5) * col_w
        c:label(DAY_LETTERS[day.wday] or "", fpx(19), cx, top, { anchor = "c", bold = true,
            color = day.today and tone.accent or tone.label })
        local fp = day.future and 0 or day.pages / page_goal
        local fm = day.future and 0 or (day.secs / 60) / min_goal
        if hearts() then
            dayHeart(c, cx, cy, d, tone, fp, fm, { future = day.future, past = not day.future and not day.today,
                single = d < 26 })
        else
            c:ring(cx, cy, R, rt, fp, tone.track, fp > 0 and cols[1] or tone.track)
            c:ring(cx, cy, R - rt - g, rt, fm, tone.track, fm > 0 and cols[2] or tone.track)
        end
    end
    c:region("week:", x, y, w, h)
end

function MINI.challenge(c, env, x, y, w, h, px, fpx, tone)
    local ch = env.sample and SAMPLE_CHALLENGE or D.challenge(env.refresh, A.get("challenge_metric", "auto"),
        tonumber(A.get("challenge_target", nil)))
    if not ch then return end
    local col = ({ pages = tone.series[1], minutes = tone.series[2], days = tone.series[3] })[ch.metric] or tone.accent
    local R = floor(min(h / 2, w * 0.27))
    local cx, cy = x + R, y + h / 2
    local flower = flowerOn()
    local pct = floor(ch.frac * 100 + 0.5)
    if flower then
        local look
        look, col = flowerLook(tone)
        look.frac = ch.frac
        c:flower(cx, cy, floor(R * 0.88), look)
    else
        c:ring(cx, cy, R, max(3, round(R * 0.25)), min(1, ch.frac), tone.track, col)
        c:label(pct .. "%", fpx(24 * R / px(100)), cx, cy, { bold = true, anchor = "c", valign = "mid" })
    end
    local tx = cx + R + px(16)
    local room = x + w - tx
    local t1 = c:text(challengeGoal(ch), fpx(22), { bold = true, color = tone.fg, max_w = room })
    local t2 = c:text(challengeDone(ch) .. (flower and ("  \xC2\xB7  " .. pct .. "%") or ""), fpx(20),
        { bold = true, color = col, max_w = room })
    local t3 = c:text(ch.complete and T("Done!") or (ch.on_pace and T("On pace") or T("Behind pace")), fpx(19),
        { bold = true, color = tone.label, max_w = room })
    local total = t1.h + t2.h + t3.h + px(8)
    local yy = cy - total / 2
    c:put(t1, tx, yy); c:put(t2, tx, yy + t1.h + px(4)); c:put(t3, tx, yy + t1.h + t2.h + px(8))
    c:region("challenge:", x, y, w, h)
end

function MINI.forecast(c, env, x, y, w, h, px, fpx, tone)
    local books = env.sample and SAMPLE_READING or D.reading(1)
    local b = books[1]
    if not b then return end
    local avg = env.sample and { secs = 6420, pages = 312 } or D.recentAverage(D.stats(env.refresh))
    local big, small = whenText(D.forecastFor(b, avg))
    local top = miniHead(c, T("Finish forecast"), x, y, w, fpx, tone) + px(6)
    local t_t = c:text(b.title or "", fpx(21), { bold = true, color = tone.fg, max_w = w })
    local t_b = c:text(big, fpx(40), { bold = true, color = tone.accent, max_w = w })
    local t_s = c:text(small, fpx(19), { bold = true, color = tone.muted, max_w = w })
    local total = t_t.h + t_b.h + t_s.h
    local yy = top + max(0, floor((y + h - top - total) / 2))
    c:put(t_t, x, yy); c:put(t_b, x, yy + t_t.h); c:put(t_s, x, yy + t_t.h + t_b.h)
    if not env.sample then A.state.mini_forecast = b.fp end
    c:region("forecast:open", x, y, w, h)
end

function MINI.goal(c, env, x, y, w, h, px, fpx, tone)
    local yr = yearFor(env)
    local target, other = D.yearGoal()
    if env.sample then target, other = 36, 0 end
    local done = (yr and yr.total or 0) + other
    if jarOn() then
        local jh = h
        local jw = min(floor(jh * 0.72), floor(w * 0.4))
        jh = floor(jw / 0.72)
        drawJar(c, x, y + floor((h - jh) / 2), jw, jh, done, target, px, jarLook(tone))
        local tx = x + jw + px(16)
        local room = x + w - tx
        local t_n = c:text(tostring(done), fpx(56), { bold = true, color = tone.fg, max_w = room })
        local t_of = c:text(T("of ") .. target .. T(" books"), fpx(20), { bold = true, color = tone.accent, max_w = room })
        local yy = y + floor((h - t_n.h - t_of.h) / 2)
        c:put(t_n, tx, yy)
        c:put(t_of, tx, yy + t_n.h - round(t_n.h * 0.1))
        c:region("goal:", x, y, w, h)
        return
    end
    local top = miniHead(c, os.date("%Y") .. T(" goal"), x, y, w, fpx, tone) + px(6)
    local t_n = c:text(tostring(done), fpx(64), { bold = true, color = tone.fg })
    local t_of = c:text(T("of ") .. target .. T(" books"), fpx(21), { bold = true, color = tone.accent, max_w = w })
    local bar_h = max(5, px(12))
    local total = t_n.h + t_of.h + px(10) + bar_h
    local yy = top + max(0, floor((y + h - top - total) / 2))
    c:put(t_n, x - round(t_n.px * 0.03), yy)
    c:put(t_of, x, yy + t_n.h - round(t_n.h * 0.1))
    local by = yy + t_n.h + t_of.h + px(6)
    c:rrect(x, by, w, bar_h, bar_h / 2, tone.track)
    if done > 0 then c:rrect(x, by, max(bar_h, floor(w * min(1, done / target))), bar_h, bar_h / 2, tone.accent, tone.track) end
    c:region("goal:", x, y, w, h)
end

function MINI.timeline(c, env, x, y, w, h, px, fpx, tone)
    local day = env.sample and sampleToday() or D.today(env.refresh)
    if not day then return end
    local secs = 0
    for _, sit in ipairs(day.sittings) do secs = secs + sit.secs end
    local n = #day.sittings
    local top = miniHead(c, T("Today"), x, y, w, fpx, tone, n > 0 and A.plural(n, T("sitting"), T("sittings")) or nil) + px(6)
    local t_big = c:text(n > 0 and A.fmtMinutes(secs / 60) or T("Not yet"), fpx(40), { bold = true, color = n > 0 and tone.fg or tone.muted, max_w = w })
    local sky = skyOn()
    local bh = sky and max(10, px(40)) or max(6, px(22))
    local t_m = c:text("12a", fpx(17), { bold = true })
    local total = t_big.h + px(sky and 18 or 10) + bh + px(4) + t_m.h
    local yy = top + max(0, floor((y + h - top - total) / 2))
    c:put(t_big, x, yy)
    local track = sky and skyTrack or timelineTrack
    track(c, day, x, yy + t_big.h + px(sky and 18 or 10), w, bh, px, function(n_) return fpx(n_ * 0.9) end, tone, true)
    c:region("timeline:", x, y, w, h)
end

function MINI.pick(c, env, x, y, w, h, px, fpx, tone)
    local b, lib
    if env.sample then b, lib = SAMPLE_PICK, { books = { SAMPLE_PICK } } else b, lib = A.pickNow(env.refresh) end
    if not b then
        if lib then
            c:label(T("Nothing to pick"), fpx(22), x + w / 2, y + h / 2, { bold = true, anchor = "c", valign = "mid", color = tone.muted, max_w = w })
        end
        return
    end
    local cov_h = h
    local cov_w = floor(cov_h / 1.5)
    if cov_w > w * 0.38 then cov_w = floor(w * 0.38); cov_h = floor(cov_w * 1.5) end
    c:cover(b.fp, x, y + floor((h - cov_h) / 2), cov_w, cov_h, { title = b.title, edge = tone.border or tone.bg })
    local tx = x + cov_w + px(18)
    local room = x + w - tx
    local lines = {
        (function()
            local kick, k_px = PICK_WHEN[pickCfg("every", "week")] or T("Random pick"), fpx(18)
            local k_full = c:text(kick, k_px, { bold = true, caps = true })
            if k_full.w > room then k_px = max(minFont(), floor(k_px * room / k_full.w)) end
            return c:text(kick, k_px, { bold = true, caps = true, color = tone.accent, max_w = room })
        end)(),
        c:textbox(b.title or "", fpx(26), room, 2, { bold = true, color = tone.fg }),
    }
    if b.authors[1] then lines[#lines + 1] = c:text(b.authors[1], fpx(20), { color = tone.muted, max_w = room }) end
    local ser = seriesText(lib, b)
    if ser then lines[#lines + 1] = c:text(ser, fpx(19), { bold = true, color = tone.accent2, max_w = room }) end
    local total = 0
    for _, t in ipairs(lines) do total = total + t.h + px(4) end
    while total > h and #lines > 2 do total = total - lines[#lines].h - px(4); table.remove(lines) end
    local yy = y + max(0, floor((h - total) / 2))
    for _, t in ipairs(lines) do c:put(t, tx, yy); yy = yy + t.h + px(4) end
    if not env.sample then A.state.mini_pick = b.fp end
    c:region("pick:open", x, y, w, h)
end

function MINI.quote(c, env, x, y, w, h, px, fpx, tone)
    local q = env.sample and SAMPLE_QUOTE or (D.hasQuotes() and D.quote(env.refresh)) or nil
    if not q then
        if q == false or (not env.sample and not D.hasQuotes()) then
            c:label(T("No highlights yet"), fpx(22), x + w / 2, y + h / 2, { bold = true, anchor = "c", valign = "mid", color = tone.muted, max_w = w })
        end
        return
    end
    local t_src = c:text("\xE2\x80\x94 " .. quoteSource(q, true), fpx(19), { bold = true, color = tone.label, max_w = w })
    local mark = c:text("\xE2\x80\x9C", fpx(56), { bold = true, color = tone.accent })
    local qx = x + floor(mark.w * 0.9) + px(6)
    local t_q = fitQuote(c, q.text or "", x + w - qx, h - t_src.h - px(8), fpx(26), fpx(18), tone)
    local yy = y + max(0, floor((h - t_q.h - t_src.h - px(8)) / 2))
    c:put(mark, x, yy - floor(mark.h * 0.1))
    c:put(t_q, qx, yy)
    c:put(t_src, qx, yy + t_q.h + px(8))
    if not env.sample then A.state.mini_quote = q.filepath end
    c:region("quote:open", x, y, w, h)
end

function MINI.library(c, env, x, y, w, h, px, fpx, tone)
    local lib = env.sample and SAMPLE_LIBRARY or D.library(env.refresh)
    if not lib then return end
    local total = lib.total or 0
    local top = miniHead(c, T("Library"), x, y, w, fpx, tone, A.thousands(total) .. T(" books")) + px(6)
    local parts = libraryParts(tone, lib.counts)
    local bh = max(6, px(18))
    local t_n = c:text("8", fpx(34), { bold = true })
    local t_l = c:text("Ag", fpx(17), { bold = true })
    local block = bh + px(12) + t_n.h + t_l.h
    local yy = top + max(0, floor((y + h - top - block) / 2))
    libraryBar(c, parts, total, x, yy, w, bh, tone)
    yy = yy + bh + px(12)
    local shown = {}
    for _, p in ipairs(parts) do if p.key ~= "on_hold" then shown[#shown + 1] = p end end
    local cw = w / #shown
    for i, p in ipairs(shown) do
        local cx = x + (i - 1) * cw
        c:label(A.thousands(p.n), fpx(34), cx, yy, { bold = true, color = tone.fg, max_w = cw - px(4) })
        c:label(p.key == "unread" and T("To read") or p.label, fpx(17), cx, yy + t_n.h, { bold = true, color = tone.label, max_w = cw - px(4) })
    end
end

function MINI.coverweek(c, env, x, y, w, h, px, fpx, tone)
    local days = calendarDays(env, "week")
    if days == false then return end
    weekStrip(c, env, days, x, y, w, h, px, fpx, tone,
        { compact = true, time = false, prefix = "coverweek:" })
end

function P.mini.build(env)
    local w, h, tone = env.w, env.h, env.tone
    local s = A.clamp(min(h / 300, w / 1100), 0.5, 1.2)
    local px, fpx = scaler(s, env.ts)
    local c = card(env, s)
    local kinds = A.miniTiles(env)
    local pad = px(24)
    local W, Hh = w - 2 * pad, h - 2 * pad
    local gap = px(36)
    local sc = A.screen()
    -- as many as fit, in order
    while #kinds > 1 do
        local need = (#kinds - 1) * gap
        for _, k in ipairs(kinds) do need = need + sc:scaleBySize(MINI_MIN[k]) end
        if need <= W then break end
        table.remove(kinds)
    end
    local total = 0
    for _, k in ipairs(kinds) do total = total + MINI_WEIGHT[k] end
    local avail = W - (#kinds - 1) * gap
    local x = pad
    for i, k in ipairs(kinds) do
        local tw = (i == #kinds) and (pad + W - x) or floor(avail * MINI_WEIGHT[k] / total)
        if i > 1 then c:rect(x - floor(gap / 2), pad + px(8), max(1, px(2)), Hh - px(16), tone.track) end
        local ok, err = pcall(MINI[k], c, env, x, pad, tw, Hh, px, fpx, tone)
        if not ok then A.log("mini", k, err) end
        x = x + tw + gap
    end
    return c
end

local function miniSplit(region)
    if type(region) ~= "string" then return nil end
    return region:match("^(%a+):(.*)$")
end

function P.mini.controls(region)
    local kind = miniSplit(region)
    return kind == "control" or kind == "reading" or kind == "forecast" or kind == "pick" or kind == "quote"
        or kind == "coverweek"
end

function P.mini.keep(region)
    local kind, rest = miniSplit(region)
    return kind == "control" and (rest:match("^bright:") or rest:match("^warm:")) ~= nil
end

function P.mini.tap(env, region)
    local kind, rest = miniSplit(region)
    if kind == "coverweek" then
        local key = rest and rest:match("^day:(.+)$")
        if key then showDay({ name = "cover_week", ctx = env.ctx }, key) end
        return
    end
    if kind == "control" then return controlTap(env, rest, A.get("control_count", 6)) end
    if kind == "reading" then
        if A.state.mini_reading then D.openBook(env.ctx, A.state.mini_reading) end
        return
    end
    if kind == "forecast" then
        if A.state.mini_forecast then D.openBook(env.ctx, A.state.mini_forecast) end
        return
    end
    if kind == "pick" or kind == "quote" then
        local fp = A.state["mini_" .. kind]
        if fp then D.openBook(env.ctx, fp) end
        return
    end
    if kind == "timeline" then return D.dispatch("stats_calendar_view") end
    if kind == "rings" then return D.dispatch("reading_progress") end
    if kind == "week" or kind == "challenge" or kind == "compare" then return D.dispatch("stats_calendar_view") end
end

return P
