--[[
The Dark Academia look: parchment, brass, ink and candlelight.

This file is read only when something asks for it (A.academia() in
init.lua): a card whose Look is set to its Dark Academia option, or the
Dark Academia theme's tabs. A Dashboard that never uses it never loads it.

Everything here draws onto a Canvas: through its own shapes (c:rect,
c:ring, c:polyline, …), or through c:op with what it draws written down by
c:mark so the paint cache (init.lua) knows when a picture changed. Colours
are {r,g,b} as they should look; c.inv says whether the canvas is
pre-inverted for night mode, and A.color applies it.
]]

local A = ...
local floor, ceil, max, min, sqrt, abs = math.floor, math.ceil, math.max, math.min, math.sqrt, math.abs
local cos, sin, pi = math.cos, math.sin, math.pi
local round = A.round

local AC = {}

AC.INK = { 35, 48, 74 }           -- iron-gall ink
AC.SEPIA = { 90, 70, 48 }
AC.GOLD = { 176, 141, 60 }
AC.GOLD_LIGHT = { 230, 203, 134 }
AC.GOLD_DARK = { 90, 66, 18 }
AC.FRAME_DARK = { 74, 53, 16 }
AC.MAT = { 239, 230, 207 }
AC.WAX = { 250, 245, 232 }
AC.WAX_EDGE = { 140, 118, 80 }
AC.FLAME = { 232, 163, 58 }
AC.FLAME_IN = { 251, 231, 161 }
AC.FLAME_EDGE = { 181, 112, 30 }
AC.WASH = { 216, 199, 160 }
AC.SAND = { 196, 154, 85 }
AC.WOOD = { 90, 58, 38 }

-- brass, deep on a light card and bright on a dark one
local function brass(tone) return (tone and tone.dark) and A.ACCENTS.brass.bright or A.ACCENTS.brass.deep end
AC.brass = brass

local function under(c) return (c.tone and c.tone.bg) or c.under or { 255, 255, 255 } end

-- ─── painting pixels ─────────────────────────────────────────────────────────

-- A row painter: put(x, y, r, g, b) for neighbouring pixels of one row; runs
-- of one colour go down as one rectangle. flush() at the end of each row.
local function painter(bb, inv)
    local bw, bh = bb:getWidth(), bb:getHeight()
    local rx, ry, rn, rk, rc = 0, 0, 0, -1, nil
    local P = {}
    function P.flush()
        if rn > 0 and ry >= 0 and ry < bh then
            local x0, x1 = max(0, rx), min(bw, rx + rn)
            if x1 > x0 then A.fillRect(bb, x0, ry, x1 - x0, 1, A.color(rc, inv)) end
        end
        rn, rk = 0, -1
    end
    function P.put(x, y, r, g, b)
        local r8, g8, b8 = floor(r + 0.5), floor(g + 0.5), floor(b + 0.5)
        local k = r8 * 65536 + g8 * 256 + b8
        if k == rk and y == ry and rx + rn == x then
            rn = rn + 1
        else
            P.flush()
            rx, ry, rn, rk, rc = x, y, 1, k, { r8, g8, b8 }
        end
    end
    return P
end

local function blend(P, x, y, rgb, cov, und)
    if cov <= 0.02 then return end
    if cov >= 0.98 then P.put(x, y, rgb[1], rgb[2], rgb[3]) return end
    P.put(x, y, und[1] + (rgb[1] - und[1]) * cov, und[2] + (rgb[2] - und[2]) * cov, und[3] + (rgb[3] - und[3]) * cov)
end

-- A filled polygon (absolute points {x1, y1, x2, y2, ...}), its left and right
-- edges anti-aliased against `und`; `pattern(x, y)`, if given, colours each
-- inside pixel instead of rgb (hatching).
local function fillPoly(bb, pts, rgb, und, inv, pattern)
    local n = floor(#pts / 2)
    if n < 3 then return end
    local ymin, ymax = math.huge, -math.huge
    for i = 2, 2 * n, 2 do
        if pts[i] < ymin then ymin = pts[i] end
        if pts[i] > ymax then ymax = pts[i] end
    end
    local P = painter(bb, inv)
    local xs = {}
    for y = floor(ymin), ceil(ymax) - 1 do
        local yc = y + 0.5
        local k = 0
        for i = 1, n do
            local j = (i % n) + 1
            local x1, y1, x2, y2 = pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j]
            if (y1 <= yc and y2 > yc) or (y2 <= yc and y1 > yc) then
                k = k + 1
                xs[k] = x1 + (yc - y1) * (x2 - x1) / (y2 - y1)
            end
        end
        for i = k + 1, #xs do xs[i] = nil end
        table.sort(xs)
        for i = 1, k - 1, 2 do
            local xl, xr = xs[i], xs[i + 1]
            local il, ir = ceil(xl), floor(xr)
            if il > ir then
                blend(P, floor(xl), y, rgb, xr - xl, und)
            else
                if il > xl then blend(P, il - 1, y, rgb, il - xl, und) end
                for x = il, ir - 1 do
                    local col = pattern and pattern(x, y) or rgb
                    P.put(x, y, col[1], col[2], col[3])
                end
                if xr > ir then blend(P, ir, y, rgb, xr - ir, und) end
            end
            P.flush()
        end
    end
    P.flush()
end

-- A thin anti-aliased line (Xiaolin Wu), blended against `und`.
local function wuLine(P, x0, y0, x1, y1, rgb, und)
    local steep = abs(y1 - y0) > abs(x1 - x0)
    if steep then x0, y0, x1, y1 = y0, x0, y1, x1 end
    if x0 > x1 then x0, x1, y0, y1 = x1, x0, y1, y0 end
    local dx, dy = x1 - x0, y1 - y0
    local grad = (dx == 0) and 1 or dy / dx
    local y = y0 + grad * (floor(x0 + 0.5) - x0)
    for x = floor(x0 + 0.5), floor(x1 + 0.5) do
        local fy = floor(y)
        local f = y - fy
        if steep then
            blend(P, fy, x, rgb, 1 - f, und); P.flush()
            blend(P, fy + 1, x, rgb, f, und); P.flush()
        else
            blend(P, x, fy, rgb, 1 - f, und); P.flush()
            blend(P, x, fy + 1, rgb, f, und); P.flush()
        end
        y = y + grad
    end
end

-- A filled polygon on a canvas (points relative to the canvas), with an
-- anti-aliased outline when `edge` is given.
function AC.poly(c, pts, rgb, edge, lw)
    local inv, und = c.inv, under(c)
    c:mark("acP", pts, rgb, edge or false, und, inv)
    c:op(function(bb, ox, oy)
        local moved = {}
        for i = 1, #pts, 2 do moved[i], moved[i + 1] = pts[i] + ox, pts[i + 1] + oy end
        fillPoly(bb, moved, rgb, und, inv)
    end)
    if edge then
        local closed = {}
        for i = 1, #pts do closed[i] = pts[i] end
        closed[#closed + 1], closed[#closed + 2] = pts[1], pts[2]
        c:polyline(closed, lw or 1, edge)
    end
end

-- ─── a gilt frame ────────────────────────────────────────────────────────────

-- A cover hung in a gilt frame: a dark outer edge, a bevelled gold band with
-- rosettes at the corners, a cream mat, and the cover inside. Returns the
-- band's width.
function AC.frameCover(c, fp, x, y, w, h, o)
    o = o or {}
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    local s = min(w, h)
    local band = max(3, floor(s * 0.075))
    local mat = max(2, floor(s * (o.mat or 0.075)))
    local bev = max(1, floor(band * 0.22))
    c:rect(x, y, w, h, AC.FRAME_DARK)
    c:rect(x + 1, y + 1, w - 2, h - 2, AC.GOLD)
    c:rect(x + 1, y + 1, w - 2, bev, AC.GOLD_LIGHT)
    c:rect(x + 1, y + 1, bev, h - 2, AC.GOLD_LIGHT)
    c:rect(x + 1, y + h - 1 - bev, w - 2, bev, AC.GOLD_DARK)
    c:rect(x + w - 1 - bev, y + 1, bev, h - 2, AC.GOLD_DARK)
    local ix, iy = x + band, y + band
    local iw, ih = w - 2 * band, h - 2 * band
    c:rect(ix, iy, iw, ih, AC.GOLD_DARK)
    c:rect(ix + 1, iy + 1, iw - 2, ih - 2, AC.MAT)
    c:cover(fp, ix + 1 + mat, iy + 1 + mat, iw - 2 - 2 * mat, ih - 2 - 2 * mat, { title = o.title, edge = AC.SEPIA })
    if s >= 60 then
        local rr = max(2, band * 0.36)
        local k = floor(band / 2) + 1
        for _, p in ipairs({ { x + k, y + k }, { x + w - k, y + k }, { x + k, y + h - k }, { x + w - k, y + h - k } }) do
            c:disc(p[1], p[2], rr + 1, AC.GOLD_DARK, AC.GOLD)
            c:disc(p[1], p[2], rr, AC.GOLD_LIGHT, AC.GOLD_DARK)
        end
    end
    return band
end

-- A brass plate under a frame: the title in italic, a line in small type
-- under it. Returns its height.
function AC.placard(c, cx, y, w, title, sub, size)
    local t1 = c:text(title, size, { serif = true, italic = true, color = { 43, 33, 24 }, max_w = w - size })
    local t2 = sub and c:text(sub, floor(size * 0.72), { serif = true, color = { 62, 46, 20 }, max_w = w - size }) or nil
    local h = t1.h + (t2 and t2.h or 0) + floor(size * 0.35)
    c:rect(floor(cx - w / 2), floor(y), floor(w), floor(h), AC.GOLD_DARK)
    c:rect(floor(cx - w / 2) + 1, floor(y) + 1, floor(w) - 2, floor(h) - 2, { 201, 162, 74 })
    c:put(t1, cx, y + floor(size * 0.15), "c")
    if t2 then c:put(t2, cx, y + floor(size * 0.15) + t1.h - floor(size * 0.1), "c") end
    return h
end

-- ─── ink ─────────────────────────────────────────────────────────────────────

-- A dotted guide line from x to x + w at y.
local function guide(c, x, y, w, col, dot)
    local step = dot * 3
    for gx = x, x + w - dot, step do c:rect(floor(gx), floor(y), dot, max(1, floor(dot * 0.6)), col) end
end

-- A line of handwriting: a gentle wave of ink from x0 to x1 on baseline y.
local function inkWave(c, x0, x1, y, amp, lw, col)
    if x1 - x0 < 2 then return end
    local pts = {}
    local step = max(2, amp * 1.6)
    local k = 0
    for x = x0, x1, step do
        pts[#pts + 1] = x
        pts[#pts + 1] = y + ((k % 2 == 0) and -amp or amp) * 0.5
        k = k + 1
    end
    pts[#pts + 1], pts[#pts + 2] = x1, y
    c:polyline(pts, lw, col)
end

-- Progress as a written line, without a pen (the Book club's picks).
function AC.inkLine(c, x, y, w, h, frac, tone)
    local base = y + h / 2
    local dot = max(1, floor(h * 0.25))
    guide(c, x, base, w, A.mix(tone.bg, tone.fg, 0.3), dot)
    frac = A.clamp(frac or 0, 0, 1)
    if frac > 0 then
        local x1 = x + w * frac
        inkWave(c, x, x1, base, max(1, h * 0.35), max(1.5, h * 0.42), AC.INK)
        c:disc(x + max(1, h * 0.3), base, max(1.5, h * 0.4), AC.INK)
    end
end

-- The fountain pen, nib at (ex, ey), at angle `a` (radians, 0 = pointing
-- left along the line, the pen rising to the right), `len` long.
local function pen(c, ex, ey, a, len, barrel)
    local k = len / 150
    local ca, sa = cos(a), sin(a)
    local function P(u, v) return ex + (u * ca - v * sa) * k, ey + (u * sa + v * ca) * k end
    local function quad(u0, v0, u1, v1, col, edge)
        local ax, ay = P(u0, v0); local bx, by = P(u1, v0); local cx, cy = P(u1, v1); local dx, dy = P(u0, v1)
        AC.poly(c, { ax, ay, bx, by, cx, cy, dx, dy }, col, edge, 1)
    end
    -- the nib, a point widening to the grip
    local n1x, n1y = P(0, 0); local n2x, n2y = P(22, -5.5); local n3x, n3y = P(30, -6)
    local n4x, n4y = P(30, 6); local n5x, n5y = P(22, 5.5)
    AC.poly(c, { n1x, n1y, n2x, n2y, n3x, n3y, n4x, n4y, n5x, n5y }, { 201, 162, 74 }, AC.GOLD_DARK, 1)
    local s1x, s1y = P(4, 0); local s2x, s2y = P(18, 0)
    c:polyline({ s1x, s1y, s2x, s2y }, max(1, k * 1.2), AC.GOLD_DARK)
    quad(30, -6.5, 50, 6.5, { 27, 21, 18 })                 -- grip
    quad(50, -7.5, 54, 7.5, { 201, 162, 74 })               -- gold ring
    quad(54, -8, 120, 8, barrel)                            -- barrel
    quad(58, -5.5, 116, -3.5, A.mix(barrel, { 255, 255, 255 }, 0.25))
    quad(120, -8.5, 150, 8.5, { 27, 21, 18 })               -- cap end
    quad(113, -12, 149, -8.5, { 201, 162, 74 })             -- clip
end

-- Continue reading's progress: a line written in ink up to how far you've
-- read, the pen resting where you stopped; finished, the line ends in a
-- flourish and the pen is lifted. The box is x..x+w, y..y+h, the baseline
-- near its bottom; the pen rises into the box.
function AC.penBar(c, x, y, w, h, frac, tone)
    frac = A.clamp(frac or 0, 0, 1)
    local base = floor(y + h - max(2, h * 0.08))
    local dot = max(1, floor(h * 0.04))
    local lw = max(2, h * 0.065)
    guide(c, x, base, w, A.mix(tone.bg, tone.fg, 0.32), dot + 1)
    local len = min(h * 2.1, w * 0.42)
    local barrel = tone.accent
    if frac >= 0.995 then
        local x1 = x + w - h * 0.5
        inkWave(c, x + lw, x1, base, lw * 1.1, lw, AC.INK)
        local fl = {}
        local r = h * 0.18
        for i = 0, 18 do
            local t = i / 18 * 2 * pi
            fl[#fl + 1] = x1 + r * sin(t) * 1.1 + r * t * 0.12
            fl[#fl + 1] = base - r + r * cos(t)
        end
        c:polyline(fl, lw * 0.8, AC.INK)
        pen(c, x + w - len * 0.95, base - h * 0.42, -0.9, len, barrel)
    else
        local x1 = x + lw + (w - lw) * frac
        if frac > 0 then inkWave(c, x + lw, x1, base, lw * 1.1, lw, AC.INK) end
        c:disc(x + lw, base, lw * 1.1, AC.INK)
        pen(c, x1, base, -0.52, len, barrel)
    end
end

-- ─── brass dial (rings) ──────────────────────────────────────────────────────

-- A ring as an engraved brass dial: a thin brass bezel, tick marks, and the
-- arc inside it.
function AC.dial(c, cx, cy, R, t, frac, track, fill, tone)
    local br = brass(tone)
    local bz = max(1, floor(R * 0.045 + 0.5))
    c:ring(cx, cy, R, bz, 1, br, br)
    local gap = max(2, floor(R * 0.07))
    local R2 = R - bz - gap
    if R >= 22 then
        local n = 12
        local tr = max(0.8, R * 0.022)
        for i = 0, n - 1 do
            local a = i / n * 2 * pi
            c:disc(cx + sin(a) * (R - bz - gap * 0.5), cy - cos(a) * (R - bz - gap * 0.5), tr, A.mix(br, tone.bg, 0.15))
        end
        R2 = R2 - floor(gap * 0.4)
    end
    if R2 < 2 then return end
    c:ring(cx, cy, R2, max(2, min(t, R2) * 0.8), frac, track, fill)
end

-- ─── the pocket watch (rings) ────────────────────────────────────────────────

-- The rings as a pocket watch: one watch for each set of rings (today's
-- three on Activity rings, a day's two on the Week and Month cards). The
-- set's outermost ring, always drawn first, draws the case and the face;
-- every ring then washes the part of the face it has covered in its colour,
-- as a band, and adds a hand pointing where it has got to: pages the longest
-- hand, minutes, then the streak. Ticks, numerals and hands go on top of all
-- the bands. At a goal its band is a full circle and its hand is back at XII.
local FACE = { 250, 245, 232 }
local SCALE = 0.86      -- the rings' radii, shrunk to sit inside the case
local NUMERALS = { [0] = "XII", [3] = "III", [6] = "VI", [9] = "IX" }

-- The case, the crown and the face (the set's first ring).
local function watchCase(c, w, tone)
    local cx, cy, R = w.cx, w.cy, w.R
    local br = brass(tone)
    local dark = A.mix(br, { 0, 0, 0 }, 0.45)
    local cw, ch = max(3, floor(R * 0.2)), max(2, floor(R * 0.1))
    c:rect(floor(cx - cw / 2), floor(cy - R - ch * 0.6), cw, ch, br)
    c:disc(cx, cy, R, br)
    c:disc(cx, cy, R * 0.92, dark)
    c:disc(cx, cy, R * 0.92 - max(1, R * 0.015), FACE, dark)
    w.ink, w.dark = { 43, 33, 24 }, dark
    -- numerals on a face big enough to read them
    if R >= 70 then
        w.nums = {}
        local px = max(9, floor(R * 0.17))
        for h, txt in pairs(NUMERALS) do
            local a = h / 12 * 2 * pi
            local tx = c:text(txt, px, { serif = true, bold = true, color = w.ink })
            w.nums[#w.nums + 1] = { t = tx, x = cx + sin(a) * R * 0.6, y = cy - cos(a) * R * 0.6 }
            c:mark("acNum", tx.sig, cx, cy, R, h)
        end
    end
end

-- Ticks, numerals, hands and the centre pin: painted after every band, so
-- this op is moved to the end each time a ring adds a hand.
local function watchTop(c, w)
    local inv, cx, cy, R = c.inv, w.cx, w.cy, w.R
    local G = A.G
    local fn = function(bb, ox, oy)
        local x0, y0 = ox + cx, oy + cy
        local n = R >= 40 and 60 or 12
        for i = 0, n - 1 do
            local a = i / n * 2 * pi
            local long = (n == 12) or (i % 5 == 0)
            local r0 = R * (long and 0.82 or 0.86)
            local r1 = R * 0.9
            G.polyline(bb, { x0 + sin(a) * r0, y0 - cos(a) * r0, x0 + sin(a) * r1, y0 - cos(a) * r1 },
                long and max(1, R * 0.018) or max(0.6, R * 0.008), w.ink, FACE, inv)
        end
        for _, nm in ipairs(w.nums or {}) do
            nm.t.widget:paintTo(bb, floor(ox + nm.x - nm.t.w / 2 + 0.5), floor(oy + nm.y - nm.t.h / 2 + 0.5))
        end
        for _, hd in ipairs(w.hands) do
            local a = hd.frac * 2 * pi
            G.polyline(bb, { x0, y0, x0 + sin(a) * hd.len, y0 - cos(a) * hd.len }, hd.lw, hd.col, FACE, inv)
            if R >= 40 then G.disc(bb, x0 + sin(a) * hd.len, y0 - cos(a) * hd.len, hd.lw * 0.9, hd.col, FACE, inv) end
        end
        G.disc(bb, x0, y0, max(1.2, R * 0.05), w.dark, FACE, inv)
    end
    if w.op then
        for i = #c.ops, 1, -1 do
            if c.ops[i] == w.op then table.remove(c.ops, i) break end
        end
    end
    w.op = fn
    c:op(fn)
end

--- One ring of a set as part of a pocket watch: R, t as for c:ring.
function AC.watchRing(c, cx, cy, R, t, frac, track, fill, tone)
    local w = c._watch
    if not (w and w.cx == cx and w.cy == cy and R < w.R) then
        w = { cx = cx, cy = cy, R = R, hands = {} }
        c._watch = w
        watchCase(c, w, tone)
    end
    frac = A.clamp(tonumber(frac) or 0, 0, 1)
    local small = w.R < 40
    -- the band: the covered part of the face, washed in the ring's colour
    -- (stronger on the small faces of the Week and Month cards)
    local col = A.mix(FACE, fill, small and 0.62 or 0.38)
    local ro, bt = R * SCALE, max(1.5, t * SCALE * 0.9)
    if frac > 0 then
        local inv = c.inv
        c:mark("acBand", cx, cy, ro, bt, frac, col, inv)
        c:op(function(bb, ox, oy) A.G.ring(bb, ox + cx, oy + cy, ro, bt, frac, FACE, col, FACE, inv) end)
    end
    -- the hand: longest for the outer ring, a little thicker going in
    local i = #w.hands
    local lw = max(1, w.R * (0.022 + 0.012 * i))
    local hcol = frac > 0 and fill or A.mix(FACE, w.ink, 0.35)
    w.hands[#w.hands + 1] = { len = (R - t * 0.3) * SCALE, frac = frac, lw = lw, col = hcol }
    c:mark("acHand", cx, cy, R, frac, hcol, lw)
    watchTop(c, w)
end

-- ─── a candle (bars) ─────────────────────────────────────────────────────────

-- A bar as a candle in a brass holder, standing on `base`, h tall in all
-- (holder and wax), w wide, with a short wick. lit: a flame (today, this
-- month). (`out` is kept for callers; a put-out candle is just its wick.)
function AC.candle(c, cx, base, w, h, lit, out, tone)
    if h < 2 or w < 2 then return end
    local br = brass(tone)
    local brd = A.mix(br, { 0, 0, 0 }, 0.3)
    local hold = max(3, min(floor(h * 0.24), floor(w * 0.7)))
    local pan_h = max(2, floor(hold * 0.34))
    local pw = max(4, floor(w * 1.15))
    local foot_h = max(2, floor(hold * 0.3))
    local fw = max(3, floor(w * 0.85))
    c:rect(floor(cx - max(1, w * 0.13)), base - hold, max(2, floor(w * 0.26)), hold, brd)
    c:rrect(floor(cx - fw / 2), base - foot_h, fw, foot_h, foot_h / 2, br)
    c:rrect(floor(cx - pw / 2), base - hold - floor(pan_h / 2), pw, pan_h, pan_h / 2, br)
    local ww = max(2, floor(w * 0.78))
    local wax_h = h - hold
    local top = base - h
    -- a short wick: the top of the wax is the reading, not the wick
    local wick = max(1, min(4, floor(ww * 0.2)))
    if wax_h >= 2 then
        c:frame(floor(cx - ww / 2), top, ww, wax_h - floor(pan_h / 2) + 1, 0, 1, AC.WAX_EDGE, AC.WAX)
        if wax_h > ww then
            -- a drip down one side
            local dh = max(2, floor(min(wax_h * 0.25, ww * 0.9)))
            c:rrect(floor(cx - ww / 2) - 1, top + 1, max(2, floor(ww * 0.28)), dh, max(1, ww * 0.14), AC.WAX_EDGE)
            c:rrect(floor(cx - ww / 2), top + 1, max(1, floor(ww * 0.22)), dh - 1, max(1, ww * 0.11), AC.WAX)
        end
        c:rect(floor(cx - max(0.5, ww * 0.05)), top - wick, max(1, floor(ww * 0.1)), wick, { 43, 33, 24 })
    end
    if lit then
        local fh = max(6, min(w * 1.7, 46))
        local fwid = fh * 0.46
        local fy = top - wick * 0.4 - fh / 2
        c:disc(cx, fy, fh * 0.8, A.mix(tone.bg, AC.FLAME, 0.22))
        local function drop(scale, dy)
            local pts = {}
            for i = 0, 23 do
                local tt = i / 24 * 2 * pi
                pts[#pts + 1] = cx + fwid * scale * 0.65 * sin(tt) * sin(tt / 2)
                pts[#pts + 1] = fy + dy - fh * scale / 2 * cos(tt)
            end
            return pts
        end
        AC.poly(c, drop(1, 0), AC.FLAME, AC.FLAME_EDGE, 1)
        AC.poly(c, drop(0.5, fh * 0.2), AC.FLAME_IN)
    end
end

-- ─── the globe (year goal) ───────────────────────────────────────────────────

-- An icosahedron split twice into small triangles, tilted and turned, its
-- front faces in screen units (x right, y down, radius 1), sorted from the
-- bottom up. Worked out once.
local _geo
local function globeGeo()
    if _geo then return _geo end
    local g = (1 + sqrt(5)) / 2
    local function norm(p) local l = sqrt(p[1] * p[1] + p[2] * p[2] + p[3] * p[3]); return { p[1] / l, p[2] / l, p[3] / l } end
    local v = {}
    for i, p in ipairs({ { -1, g, 0 }, { 1, g, 0 }, { -1, -g, 0 }, { 1, -g, 0 }, { 0, -1, g }, { 0, 1, g }, { 0, -1, -g }, { 0, 1, -g },
        { g, 0, -1 }, { g, 0, 1 }, { -g, 0, -1 }, { -g, 0, 1 } }) do v[i] = norm(p) end
    local f = { { 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 }, { 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 },
        { 11, 8, 7 }, { 8, 2, 9 }, { 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 }, { 5, 10, 6 }, { 3, 5, 12 },
        { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 } }
    for _ = 1, 2 do
        local nf = {}
        local function mid(i, j)
            v[#v + 1] = norm({ (v[i][1] + v[j][1]) / 2, (v[i][2] + v[j][2]) / 2, (v[i][3] + v[j][3]) / 2 })
            return #v
        end
        for _, t in ipairs(f) do
            local a, b, cc = t[1], t[2], t[3]
            local ab, bc, ca = mid(a, b), mid(b, cc), mid(cc, a)
            nf[#nf + 1] = { a, ab, ca }; nf[#nf + 1] = { b, bc, ab }; nf[#nf + 1] = { cc, ca, bc }; nf[#nf + 1] = { ab, bc, ca }
        end
        f = nf
    end
    local ry, rx = 0.5, 0.41
    local P = {}
    for i, p in ipairs(v) do
        local x, y, z = p[1], p[2], p[3]
        local x1, z1 = x * cos(ry) + z * sin(ry), -x * sin(ry) + z * cos(ry)
        P[i] = { x1, y * cos(rx) - z1 * sin(rx), y * sin(rx) + z1 * cos(rx) }
    end
    local front = {}
    for _, t in ipairs(f) do
        if P[t[1]][3] + P[t[2]][3] + P[t[3]][3] > 0 then
            front[#front + 1] = { P[t[1]][1], -P[t[1]][2], P[t[2]][1], -P[t[2]][2], P[t[3]][1], -P[t[3]][2],
                key = P[t[1]][2] + P[t[2]][2] + P[t[3]][2] }
        end
    end
    table.sort(front, function(a, b) return a.key < b.key end)
    _geo = front
    return front
end

-- The year goal as an ink sketch of a tessellated globe on a brass stand: as
-- many of its triangles shaded in (hatched, from the bottom up) as the share
-- of the goal done; reached, it gets a brass equator. The globe is radius R
-- at cx, cy; the stand reaches about R * 0.45 below it.
function AC.globe(c, cx, cy, R, frac, tone)
    local br = brass(tone)
    local bg = under(c)
    local inv = c.inv
    local gap = max(2, floor(R * 0.08))
    local mt = max(2, floor(R * 0.04))
    -- the half meridian and the stand
    c:ring(cx, cy, R + gap + mt, mt, 0.5, bg, br)
    local st = max(2, floor(R * 0.07))
    c:rect(floor(cx - st / 2), floor(cy + R + gap), st, max(2, floor(R * 0.28)), A.mix(br, { 0, 0, 0 }, 0.25))
    local bw, bh = floor(R * 0.95), max(3, floor(R * 0.1))
    c:rrect(floor(cx - bw / 2), floor(cy + R + gap + R * 0.26), bw, bh, bh / 2, br)
    c:disc(cx, cy, R, AC.MAT)
    local tris = globeGeo()
    local n = round(A.clamp(frac or 0, 0, 1) * #tris)
    local ink = AC.SEPIA
    local wash = AC.WASH
    c:mark("acGl", cx, cy, R, n, inv)
    c:op(function(bb, ox, oy)
        local gx, gy = ox + cx, oy + cy
        local period = max(4, floor(R / 11))
        local line = A.mix(wash, ink, 0.6)
        local function hatch(x, y)
            return ((x + y) % period < max(1, period * 0.28)) and line or wash
        end
        for i = 1, n do
            local t = tris[i]
            fillPoly(bb, { gx + t[1] * R, gy + t[2] * R, gx + t[3] * R, gy + t[4] * R, gx + t[5] * R, gy + t[6] * R },
                wash, AC.MAT, inv, hatch)
        end
        local P = painter(bb, inv)
        for _, t in ipairs(tris) do
            local x1, y1, x2, y2, x3, y3 = gx + t[1] * R, gy + t[2] * R, gx + t[3] * R, gy + t[4] * R, gx + t[5] * R, gy + t[6] * R
            wuLine(P, x1, y1, x2, y2, ink, AC.MAT)
            wuLine(P, x2, y2, x3, y3, ink, AC.MAT)
            wuLine(P, x3, y3, x1, y1, ink, AC.MAT)
        end
        P.flush()
    end)
    local olw = max(1.5, R * 0.022)
    c:ring(cx, cy, R + olw / 2, olw, 1, tone.fg, tone.fg)
    if n >= #tris then
        local pts = {}
        for i = 0, 40 do
            local a = i / 40 * 2 * pi
            pts[#pts + 1] = cx + R * cos(a)
            pts[#pts + 1] = cy + R * 0.22 * sin(a)
        end
        c:polyline(pts, max(2, R * 0.035), br)
    end
end

-- ─── the hourglass (monthly challenge) ───────────────────────────────────────

-- The month's challenge as an hourglass, h tall at cx, cy: the sand falls as
-- you read towards the goal.
function AC.hourglass(c, cx, cy, h, frac, tone)
    frac = A.clamp(frac or 0, 0, 1)
    local br = brass(tone)
    local w = h * 0.62
    local bar = max(3, floor(h * 0.06))
    local top, bot = cy - h / 2, cy + h / 2
    c:rect(floor(cx - w / 2), floor(top), floor(w), bar, AC.WOOD)
    c:rect(floor(cx - w / 2), floor(bot - bar), floor(w), bar, AC.WOOD)
    local post = max(2, floor(h * 0.022))
    c:rect(floor(cx - w / 2 + post), floor(top + bar), post, floor(h - 2 * bar), br)
    c:rect(floor(cx + w / 2 - 2 * post), floor(top + bar), post, floor(h - 2 * bar), br)
    local g0, g1 = top + bar, bot - bar
    local gh = g1 - g0
    local wmax, neck = w * 0.36, max(1.5, w * 0.035)
    local function hw(u) return neck + (wmax - neck) * (abs(2 * u - 1) ^ 0.62) end
    local function side(u0, u1, steps)
        local L, R = {}, {}
        for i = 0, steps do
            local u = u0 + (u1 - u0) * i / steps
            local yy = g0 + gh * u
            L[#L + 1] = { cx - hw(u), yy }
            R[#R + 1] = { cx + hw(u), yy }
        end
        local pts = {}
        for i = 1, #L do pts[#pts + 1] = L[i][1]; pts[#pts + 1] = L[i][2] end
        for i = #R, 1, -1 do pts[#pts + 1] = R[i][1]; pts[#pts + 1] = R[i][2] end
        return pts
    end
    AC.poly(c, side(0, 1, 24), { 244, 236, 218 }, br, max(1, h * 0.012))
    -- sand still to fall at the top, fallen sand heaped at the bottom
    if frac < 1 then AC.poly(c, side(0.06 + 0.42 * frac, 0.47, 10), AC.SAND) end
    if frac > 0 then
        AC.poly(c, side(1 - 0.42 * frac, 0.985, 10), AC.SAND)
        if frac < 1 then c:rect(floor(cx - 0.5), floor(g0 + gh * 0.47), 1, floor(gh * (0.53 - 0.42 * frac)), AC.SAND) end
    end
end

-- ─── the chess board (monthly challenge) ────────────────────────────────────

-- The month's challenge plays out a real game from the usual starting
-- position: the Immortal Game, Anderssen against Kieseritzky, London 1851.
-- You have White. Its 45 moves (both sides) are spread over the challenge,
-- one every 2.2% or so, and the last, 23. Be7, is checkmate at 100%.
-- Each move: from square, to square (no castling, en passant or promotion in
-- this game).
AC.GAME = { "e2e4", "e7e5", "f2f4", "e5f4", "f1c4", "d8h4", "e1f1", "b7b5", "c4b5", "g8f6",
    "g1f3", "h4h6", "d2d3", "f6h5", "f3h4", "h6g5", "h4f5", "c7c6", "g2g4", "h5f6",
    "h1g1", "c6b5", "h2h4", "g5g6", "h4h5", "g6g5", "d1f3", "f6g8", "c1f4", "g5f6",
    "b1c3", "f8c5", "c3d5", "f6b2", "f4d6", "c5g1", "e4e5", "b2a1", "f1e2", "b8a6",
    "f5g7", "e8d8", "f3f6", "g8f6", "d6e7" }
-- the moves that give check (the last one mates)
AC.GAME_CHECKS = { [6] = true, [38] = true, [41] = true, [43] = true, [45] = true }
AC.GAME_NAME = "Anderssen \xE2\x80\x93 Kieseritzky, London 1851"

local START = { "RNBQKBNR", "PPPPPPPP", "", "", "", "", "pppppppp", "rnbqkbnr" }
-- solid glyphs (black pieces, and the fill of white ones), and the outlines
local SOLID = { k = "\xE2\x99\x9A", q = "\xE2\x99\x9B", r = "\xE2\x99\x9C", b = "\xE2\x99\x9D",
    n = "\xE2\x99\x9E", p = "\xE2\x99\x9F" }
local LINE = { k = "\xE2\x99\x94", q = "\xE2\x99\x95", r = "\xE2\x99\x96", b = "\xE2\x99\x97",
    n = "\xE2\x99\x98", p = "\xE2\x99\x99" }

AC.LIGHT_SQ = { 240, 231, 208 }
AC.DARK_SQ = { 158, 118, 78 }
AC.OXBLOOD = { 122, 31, 31 }
local PIECE_INK, PIECE_IVORY = { 28, 22, 18 }, { 250, 245, 232 }

--- How far the game has gone: 0..45 moves for frac 0..1.
function AC.chessStep(frac)
    local n = #AC.GAME
    return A.clamp(floor((frac or 0) * n + 1e-6), 0, n)
end

local function sqIndex(name) return name:byte(1) - 96, tonumber(name:sub(2)) end

--- The board after `ply` moves: board[file][rank] = piece letter (upper case
--- White, lower case Black) or nil.
function AC.chessBoard(ply)
    local board = {}
    for f = 1, 8 do board[f] = {} end
    for r = 1, 8 do
        local row = START[r]
        for f = 1, #row do board[f][r] = row:sub(f, f) end
    end
    for i = 1, ply do
        local m = AC.GAME[i]
        local ff, fr = sqIndex(m:sub(1, 2))
        local tf, tr = sqIndex(m:sub(3, 4))
        board[tf][tr], board[ff][fr] = board[ff][fr], nil
    end
    return board
end

-- A piece centred on a square: a solid glyph in `fill`, and for a white
-- piece its outline glyph in ink over it.
local function piece(c, letter, px, cx, cy)
    local kind = letter:lower()
    local white = letter ~= kind
    local t = c:text(SOLID[kind], px, { chess = true, color = white and PIECE_IVORY or PIECE_INK })
    c:put(t, cx, cy, "c", "mid")
    if white then
        local o = c:text(LINE[kind], px, { chess = true, color = PIECE_INK })
        c:put(o, cx, cy, "c", "mid")
    end
end

-- The black king knocked over: his glyph turned on its side, ivory with an
-- ink outline, on an oxblood square.
local function fallenKing(c, x, y, sq, px)
    c:rect(x, y, sq, sq, AC.OXBLOOD)
    local solid = c:text(SOLID.k, px, { chess = true, color = PIECE_IVORY })
    local line = c:text(LINE.k, px, { chess = true, color = PIECE_INK })
    local inv = c.inv
    c:mark("acKing", x, y, sq, solid.sig, line.sig, inv)
    c:op(function(bb, ox, oy)
        local BB = require("ffi/blitbuffer")
        local n = sq
        local tmp = BB.new(n, n, bb:getType())
        A.fillRect(tmp, 0, 0, n, n, A.color(AC.OXBLOOD, inv))
        local dx, dy = floor((n - solid.w) / 2), floor((n - solid.h) / 2)
        solid.widget:paintTo(tmp, dx, dy)
        line.widget:paintTo(tmp, dx, dy)
        local turned = tmp:rotatedCopy(90)
        bb:blitFrom(turned, ox + x, oy + y, 0, 0, n, n)
        turned:free()
        tmp:free()
    end)
end

--- The month's challenge as a chess board, `size` square, its top left at
--- x, y: the Immortal Game from the starting position, one move further for
--- every 2.2% or so, the last move lit in brass and a king in check marked;
--- at 100% White's checkmate, the black king knocked over. o.coords: the
--- files and ranks along the frame (when there is room). Returns the number
--- of moves shown, and whether it is mate.
function AC.chess(c, x, y, size, frac, tone, o)
    o = o or {}
    x, y, size = floor(x), floor(y), floor(size)
    local ply = AC.chessStep(frac)
    local mate = ply >= #AC.GAME
    local board = AC.chessBoard(ply)
    local br = brass(tone)
    local coords = o.coords ~= false and size >= 170
    local fw = max(2, floor(size * (coords and 0.075 or 0.035)))
    local sq = floor((size - 2 * fw) / 8)
    local inner = sq * 8
    fw = floor((size - inner) / 2)
    -- the frame: a dark edge, brass, a dark line inside
    c:rect(x, y, size, size, AC.FRAME_DARK)
    c:rect(x + 1, y + 1, size - 2, size - 2, br)
    local bx, by = x + fw, y + fw
    c:rect(bx - 1, by - 1, inner + 2, inner + 2, AC.FRAME_DARK)
    -- the last move, and a king in check (the side to move)
    local last = ply > 0 and AC.GAME[ply] or nil
    local lf, lr, tf, tr
    if last then
        lf, lr = sqIndex(last:sub(1, 2))
        tf, tr = sqIndex(last:sub(3, 4))
    end
    local check_k = (AC.GAME_CHECKS[ply] and not mate) and ((ply % 2 == 1) and "k" or "K") or nil
    for f = 1, 8 do
        for r = 1, 8 do
            local sx, sy = bx + (f - 1) * sq, by + (8 - r) * sq
            local col = ((f + r) % 2 == 0) and AC.DARK_SQ or AC.LIGHT_SQ
            if last and ((f == lf and r == lr) or (f == tf and r == tr)) then col = A.mix(col, AC.GOLD_LIGHT, 0.55) end
            if check_k and board[f][r] == check_k then col = A.mix(col, AC.OXBLOOD, 0.4) end
            c:rect(sx, sy, sq, sq, col)
        end
    end
    -- the pieces
    local px = max(8, floor(sq * 1.12))
    for f = 1, 8 do
        for r = 1, 8 do
            local p = board[f][r]
            if p then
                local sx, sy = bx + (f - 1) * sq, by + (8 - r) * sq
                if mate and p == "k" then
                    fallenKing(c, sx, sy, sq, px)
                else
                    piece(c, p, px, sx + sq / 2, sy + sq / 2)
                end
            end
        end
    end
    -- files and ranks on the frame
    if coords then
        local fpx = max(7, floor(fw * 0.62))
        for i = 1, 8 do
            c:label(string.char(96 + i), fpx, bx + (i - 0.5) * sq, y + size - fw / 2,
                { serif = true, anchor = "c", valign = "mid", color = AC.FRAME_DARK })
            c:label(tostring(i), fpx, x + fw / 2, by + (8 - i + 0.5) * sq,
                { serif = true, anchor = "c", valign = "mid", color = AC.FRAME_DARK })
        end
    end
    return ply, mate
end

-- ─── small marks ─────────────────────────────────────────────────────────────

-- Tally marks: `done` strokes in ink and the rest faded, in groups of five
-- (the fifth struck through the four), across w x h. Returns the width used.
function AC.tally(c, x, y, w, h, done, total, ink, faded)
    total = max(1, total)
    local groups = ceil(total / 5)
    local sp = h * 0.36
    local gw = 4 * sp + sp * 1.8
    local k = min(1, w / (groups * gw))
    sp = sp * k
    gw = gw * k
    local lw = max(1.5, h * 0.11 * k + 0.5)
    for i = 1, total do
        local g = floor((i - 1) / 5)
        local p = (i - 1) % 5
        local col = i <= done and ink or faded
        local gx = x + g * gw
        if p < 4 then
            local sx = gx + p * sp + sp * 0.3
            c:polyline({ sx, y + h * 0.08, sx + sp * 0.12, y + h * 0.92 }, lw, col)
        else
            c:polyline({ gx - sp * 0.1, y + h * 0.78, gx + 3.6 * sp, y + h * 0.2 }, lw, col)
        end
    end
    return groups * gw
end

-- A rubber stamp: the word in capitals inside a double rule. Returns w, h.
function AC.stamp(c, str, size, x, y, col)
    local t = c:text(str, size, { serif = true, bold = true, caps = true, color = col })
    local pad = max(3, floor(size * 0.35))
    local w, h = t.w + 2 * pad + 4, t.h + floor(size * 0.2) + 4
    local lw = max(1, floor(size * 0.08))
    c:frame(floor(x), floor(y), w, h, 0, lw, col, under(c))
    c:frame(floor(x) + lw + 1, floor(y) + lw + 1, w - 2 * lw - 2, h - 2 * lw - 2, 0, 1, col, under(c))
    c:put(t, x + w / 2, y + h / 2, "c", "mid")
    return w, h
end

-- A wax seal: a disc of wax with a raised ring.
function AC.seal(c, cx, cy, r, col)
    c:disc(cx, cy, r, col)
    c:ring(cx, cy, r * 0.68, max(1, r * 0.1), 1, A.mix(col, { 255, 255, 255 }, 0.22), A.mix(col, { 255, 255, 255 }, 0.22))
    c:disc(cx, cy, r * 0.32, A.mix(col, { 0, 0, 0 }, 0.18))
end

-- Engraved hatching under a line (points {x1, y1, ...}) down to `bottom`:
-- diagonal strokes of col, leaning one way (dir 1) or the other (-1).
function AC.hatch(c, pts, bottom, col, dir)
    local n = floor(#pts / 2)
    if n < 2 then return end
    local poly = {}
    for i = 1, 2 * n do poly[i] = pts[i] end
    poly[#poly + 1], poly[#poly + 2] = pts[2 * n - 1], bottom
    poly[#poly + 1], poly[#poly + 2] = pts[1], bottom
    local inv, und = c.inv, under(c)
    local line = A.mix(und, col, 0.55)
    dir = dir or 1
    c:mark("acH", poly, col, dir, und, inv)
    c:op(function(bb, ox, oy)
        local moved = {}
        for i = 1, #poly, 2 do moved[i], moved[i + 1] = poly[i] + ox, poly[i + 1] + oy end
        local period = 6
        fillPoly(bb, moved, und, und, inv, function(x, y)
            return (((x + dir * y) % period + period) % period < 1.2) and line or und
        end)
    end)
end

-- The sun as an engraver draws it: a ring with eight short rays.
function AC.sun(c, cx, cy, r, col)
    c:ring(cx, cy, r, max(1.5, r * 0.16), 1, col, col)
    for i = 0, 7 do
        local a = i / 8 * 2 * pi
        c:polyline({ cx + sin(a) * r * 1.35, cy - cos(a) * r * 1.35, cx + sin(a) * r * 1.8, cy - cos(a) * r * 1.8 },
            max(1.5, r * 0.16), col)
    end
end

-- A crescent moon.
function AC.moon(c, cx, cy, r, col)
    c:disc(cx, cy, r, col)
    c:disc(cx + r * 0.45, cy - r * 0.2, r * 0.82, under(c))
end

-- A small four-pointed star (now, on the celestial chart).
function AC.star(c, cx, cy, r, col)
    local q = r * 0.28
    AC.poly(c, { cx, cy - r, cx + q, cy - q, cx + r, cy, cx + q, cy + q, cx, cy + r, cx - q, cy + q, cx - r, cy, cx - q, cy - q }, col)
end

-- A small ornament: a diamond with a short rule either side.
function AC.ornament(c, cx, cy, size, col)
    local d = size * 0.32
    AC.poly(c, { cx, cy - d, cx + d, cy, cx, cy + d, cx - d, cy }, col)
    local lw = max(1, floor(size * 0.07))
    c:rect(floor(cx - size * 1.6), floor(cy - lw / 2), floor(size * 1.1), lw, col)
    c:rect(floor(cx + size * 0.5), floor(cy - lw / 2), floor(size * 1.1), lw, col)
end

return AC
