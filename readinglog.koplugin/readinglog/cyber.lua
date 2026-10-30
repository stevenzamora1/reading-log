--[[
The Cyber look: black and neon, cut corners, segments that light up.

This file is read only when something asks for it (A.cyber() in init.lua):
the Cyber theme's card frames, or a card whose Look is set to its Cyber
option. A Dashboard that never uses Cyber never loads it.

Everything here draws onto a Canvas through c:op, and writes what it draws
down with c:mark so the paint cache (init.lua) knows when a picture changed.
Colours are {r,g,b} as they should look; c.inv says whether the canvas is
pre-inverted for night mode, and A.color applies it.
]]

local A = ...
local floor, ceil, max, min, sqrt, atan2, pi = math.floor, math.ceil, math.max, math.min, math.sqrt, math.atan2, math.pi
local round = A.round

local CY = {}

CY.MAGENTA = { 255, 68, 221 }

-- ─── painting pixels ─────────────────────────────────────────────────────────

-- A row painter: put(x, y, rgb) for neighbouring pixels of one row; runs of
-- one colour go down as one rectangle. flush() at the end of each row.
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
    function P.span(x, y, n, rgb)
        if n <= 0 then return end
        P.flush()
        if y >= 0 and y < bh then
            local x0, x1 = max(0, x), min(bw, x + n)
            if x1 > x0 then A.fillRect(bb, x0, y, x1 - x0, 1, A.color(rgb, inv)) end
        end
    end
    return P
end

-- The colour already at x, y (as it should look), for edges over a picture.
-- (the caller keeps x, y inside the bitmap)
local function pixelAt(bb, x, y, inv)
    local px = bb:getPixel(x, y)
    if not px then return { 0, 0, 0 } end
    local c = px:getColorRGB32()
    local r, g, b = c.r, c.g, c.b
    if inv then return { 255 - r, 255 - g, 255 - b } end
    return { r, g, b }
end

-- Blend rgb over `under` (a colour, or A.BEHIND = what is in the bitmap) by cov.
local function edge(P, bb, x, y, rgb, cov, under, inv)
    if cov <= 0.02 then return end
    if cov >= 0.98 then P.put(x, y, rgb[1], rgb[2], rgb[3]) return end
    local u = under
    if u == A.BEHIND or not u then
        local bw, bh = bb:getWidth(), bb:getHeight()
        if x < 0 or y < 0 or x >= bw or y >= bh then return end
        u = pixelAt(bb, x, y, inv)
    end
    P.put(x, y, u[1] + (rgb[1] - u[1]) * cov, u[2] + (rgb[2] - u[2]) * cov, u[3] + (rgb[3] - u[3]) * cov)
end

-- A filled shape given row by row: span(j) returns the left and right edge
-- (fractional, relative to x) of row j, or nil for an empty row.
local function fillRows(bb, x, y, h, rgb, under, inv, span)
    local P = painter(bb, inv)
    for j = 0, h - 1 do
        local xl, xr = span(j)
        if xl and xr and xr > xl then
            local il, ir = ceil(xl), floor(xr)
            if il > ir then
                edge(P, bb, x + floor(xl), y + j, rgb, xr - xl, under, inv)
            else
                if il > xl then edge(P, bb, x + il - 1, y + j, rgb, il - xl, under, inv) end
                P.flush()
                P.span(x + il, y + j, ir - il, rgb)
                if xr > ir then edge(P, bb, x + ir, y + j, rgb, xr - ir, under, inv) end
            end
            P.flush()
        end
    end
end

-- A rectangle with its top-right and bottom-left corners cut off at 45°.
local function cutBox(bb, x, y, w, h, cut, rgb, under, inv)
    cut = min(cut, floor(w / 2), floor(h / 2))
    fillRows(bb, x, y, h, rgb, under, inv, function(j)
        local yc = j + 0.5
        local xl, xr = 0, w
        if yc > h - cut then xl = yc - (h - cut) end
        if yc < cut then xr = w - cut + yc end
        return xl, xr
    end)
end

-- ─── canvas pieces ───────────────────────────────────────────────────────────

local function under(c) return (c.tone and c.tone.bg) or c.under end

-- The Cyber theme's card: a thin frame with two corners cut off and a short
-- bar of the accent along the top-left edge. (Called by Canvas:draw.)
function CY.frame(bb, x, y, w, h, r, bw, tone, und, inv)
    local cut = max(6, floor((r or 12) * 0.75))
    local border = tone.border or tone.muted
    if bw > 0 then
        cutBox(bb, x, y, w, h, cut, border, und, inv)
        cutBox(bb, x + bw, y + bw, w - 2 * bw, h - 2 * bw, max(2, cut - floor(bw * 0.6)), tone.bg, border, inv)
    else
        cutBox(bb, x, y, w, h, cut, tone.bg, und, inv)
    end
    local tick_h = max(3, bw + 2)
    A.fillRect(bb, floor(x), floor(y), floor(min(w * 0.14, cut * 2.4)), tick_h, A.color(tone.accent, inv))
end

-- A frame with its top-right and bottom-left corners cut off (like the Cyber
-- theme's cards): bw of border round a fill.
function CY.cutFrame(c, x, y, w, h, cut, bw, border, fill)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    local inv, und = c.inv, under(c)
    c:mark("cyF", x, y, w, h, cut, bw, border, fill, und, inv)
    c:op(function(bb, ox, oy)
        cutBox(bb, ox + x, oy + y, w, h, cut, border, und, inv)
        cutBox(bb, ox + x + bw, oy + y + bw, w - 2 * bw, h - 2 * bw, max(2, cut - floor(bw * 0.6)), fill, border, inv)
    end)
end

-- A filled rectangle with its bottom-right corner cut (a Cyber button).
function CY.cutRect(c, x, y, w, h, cut, rgb)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    cut = min(floor(cut), floor(w / 2), floor(h / 2))
    local inv, und = c.inv, under(c)
    c:mark("cyR", x, y, w, h, cut, rgb, und, inv)
    c:op(function(bb, ox, oy)
        fillRows(bb, ox + x, oy + y, h, rgb, und, inv, function(j)
            local yc = j + 0.5
            if yc > h - cut then return 0, w - (yc - (h - cut)) end
            return 0, w
        end)
    end)
end

-- A parallelogram leaning right by `skew` pixels over its height.
function CY.slant(c, x, y, w, h, rgb, skew)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    skew = skew or floor(h * 0.35)
    local inv, und = c.inv, under(c)
    c:mark("cyS", x, y, w, h, skew, rgb, und, inv)
    c:op(function(bb, ox, oy)
        fillRows(bb, ox + x, oy + y, h, rgb, und, inv, function(j)
            local sh = skew * (1 - (j + 0.5) / h)
            return sh, sh + w - skew
        end)
    end)
end

-- A row of n slanted segments across w x h, the first lit ones `on`.
-- frac: how much is done (0..1). Returns nothing.
function CY.segbar(c, x, y, w, h, frac, n, on, off)
    n = max(1, floor(n))
    local gap = max(2, floor(h * 0.35))
    local seg = (w - (n - 1) * gap) / n
    if seg < 3 then
        n = max(1, floor((w + gap) / (3 + gap)))
        seg = (w - (n - 1) * gap) / n
    end
    local lit = (frac >= 1 and n) or (frac <= 0 and 0) or max(1, floor(frac * n + 0.5))
    local skew = min(floor(h * 0.45), floor(seg * 0.5))
    for i = 1, n do
        local sx = x + (i - 1) * (seg + gap)
        CY.slant(c, sx, y, seg + skew * 0.5, h, i <= lit and on or off, skew)
    end
end

-- Corner brackets round a box (covers): len long, thick wide.
function CY.brackets(c, x, y, w, h, rgb, len, thick)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    len, thick = max(4, floor(len)), max(1, floor(thick))
    c:rect(x, y, len, thick, rgb); c:rect(x, y, thick, len, rgb)
    c:rect(x + w - len, y, len, thick, rgb); c:rect(x + w - thick, y, thick, len, rgb)
    c:rect(x, y + h - thick, len, thick, rgb); c:rect(x, y + h - len, thick, len, rgb)
    c:rect(x + w - len, y + h - thick, len, thick, rgb); c:rect(x + w - thick, y + h - len, thick, len, rgb)
end

-- A cover in brackets: the cover inset a little, the brackets on the corners.
function CY.cover(c, fp, x, y, w, h, o)
    o = o or {}
    local tone = c.tone
    local thick = max(2, floor(min(w, h) * 0.035))
    local inset = thick + max(2, floor(min(w, h) * 0.04))
    c:cover(fp, x + inset, y + inset, w - 2 * inset, h - 2 * inset, { title = o.title, edge = tone.border or tone.muted })
    CY.brackets(c, x, y, w, h, o.color or tone.accent, max(6, min(w, h) * 0.16), thick)
end

-- A label on a block of colour (a chip): returns its width.
function CY.chip(c, str, size, x, y, bg, fg, o)
    o = o or {}
    local t = c:text(str, size, { bold = true, color = fg, caps = o.caps, mono = o.mono, max_w = o.max_w })
    local padx = max(3, floor(size * 0.35))
    local h = t.h + floor(size * 0.1)
    local w = t.w + 2 * padx
    if o.anchor == "r" then x = x - w elseif o.anchor == "c" then x = x - w / 2 end
    c:rect(floor(x), floor(y), floor(w), floor(h), bg)
    c:put(t, x + padx, y + h / 2, "l", "mid")
    return w, h
end

-- Text with the glitch: a cyan copy a little right, a red one a little left,
-- the text itself over them. Returns the text record (placed at x, y).
function CY.glitch(c, str, size, x, y, o)
    o = o or {}
    local tone = c.tone or A.tone("ink")
    local shift = max(1, floor(size * 0.04 + 0.5))
    local base = { bold = o.bold ~= false, caps = o.caps, max_w = o.max_w, mono = o.mono }
    local function rec(col)
        local r = {}
        for k, v in pairs(base) do r[k] = v end
        r.color = col
        return c:text(str, size, r)
    end
    local t1 = rec(o.color2 or tone.accent2)
    local t2 = rec(o.alert or tone.alert or { 255, 68, 102 })
    local t = rec(o.color or tone.fg)
    c:put(t1, x + shift, y, o.anchor, o.valign)
    c:put(t2, x - shift, y, o.anchor, o.valign)
    c:put(t, x, y, o.anchor, o.valign)
    return t
end

-- A diamond (a square on its point) of radius r at cx, cy: a point on a
-- Cyber line chart. Its edges blend with whatever is under it.
function CY.diamond(c, cx, cy, r, rgb)
    local inv = c.inv
    c:mark("cyD", cx, cy, r, rgb, inv)
    c:op(function(bb, ox, oy)
        local x0, y0 = floor(ox + cx - r), floor(oy + cy - r)
        local fx, fy = ox + cx - x0, oy + cy - y0
        fillRows(bb, x0, y0, ceil(2 * r) + 1, rgb, A.BEHIND, inv, function(j)
            local d = r - math.abs(j + 0.5 - fy)
            if d <= 0 then return nil end
            return fx - d, fx + d
        end)
    end)
end

-- A Cyber bar: a dim fill, outlined in its colour, with a heavier top edge.
function CY.bar(c, x, y, w, h, col, bg, lw)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    lw = max(1, floor(lw or 2))
    if w < 3 * lw + 2 or h < 2 * lw + 2 then c:rect(x, y, w, h, col) return end
    c:rect(x, y, w, h, A.mix(bg, col, 0.3))
    c:rect(x, y, lw, h, col)
    c:rect(x + w - lw, y, lw, h, col)
    c:rect(x, y, w, min(h, lw * 2), col)
end

-- Warning stripes: bands of col on bg leaning 45°, across w x h.
function CY.hazard(c, x, y, w, h, col, bg, band)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    band = max(2, floor(band or h / 4))
    local inv = c.inv
    c:mark("cyH", x, y, w, h, col, bg, band, inv)
    c:op(function(bb, ox, oy)
        local P = painter(bb, inv)
        local period = 2 * band
        for j = 0, h - 1 do
            local yy = oy + y + j
            P.span(ox + x, yy, w, bg)
            local k0 = floor(-(j + period) / period)
            local k1 = ceil((w + h) / period)
            for k = k0, k1 do
                local a0 = k * period + j
                local x0, x1 = max(0, a0), min(w, a0 + band)
                if x1 > x0 then P.span(ox + x + x0, yy, x1 - x0, col) end
            end
        end
        P.flush()
    end)
end

-- ─── segmented rings ─────────────────────────────────────────────────────────

local TAU = 2 * pi

local function segRing(bb, cx, cy, R, t, frac, n, track, fill, und, inv)
    local lit = (frac >= 1 and n) or (frac <= 0 and 0) or max(1, floor(frac * n + 0.5))
    local g = 0.3
    local x0, x1 = floor(cx - R - 1), ceil(cx + R + 1)
    local y0, y1 = floor(cy - R - 1), ceil(cy + R + 1)
    local inner = R - t
    local P = painter(bb, inv)
    local ur, ug, ub = und[1], und[2], und[3]
    for py = y0, y1 do
        local dy = py + 0.5 - cy
        for px = x0, x1 do
            local dx = px + 0.5 - cx
            local d = sqrt(dx * dx + dy * dy)
            local cr = R + 0.5 - d
            if cr > 0 then
                local ci = d - inner + 0.5
                if ci > 0 then
                    if cr > 1 then cr = 1 end
                    if ci > 1 then ci = 1 end
                    local a = atan2(dx, -dy)
                    if a < 0 then a = a + TAU end
                    local pos = a / TAU * n
                    local idx = floor(pos)
                    local f = pos - idx
                    local ed = min(f - g / 2, 1 - g / 2 - f) * (TAU * d / n)
                    local ca = ed + 0.5
                    if ca > 0 then
                        if ca > 1 then ca = 1 end
                        local cov = cr * ci * ca
                        local col = (idx < lit) and fill or track
                        P.put(px, py, ur + (col[1] - ur) * cov, ug + (col[2] - ug) * cov, ub + (col[3] - ub) * cov)
                    end
                end
            end
        end
        P.flush()
    end
end

-- A ring of n segments (24 by default), lit clockwise from the top.
function CY.segring(c, cx, cy, R, t, frac, track, fill, n)
    n = n or 24
    if R < 3 then return end
    -- small rings get fewer, bigger segments so the gaps still show
    n = max(8, min(n, floor(TAU * R / 13)))
    -- a little thinner than a plain ring, so the rings stand apart
    local t2 = max(2, t * 0.8)
    R, t = R - (t - t2) / 2, t2
    local inv, und = c.inv, under(c) or { 255, 255, 255 }
    frac = A.clamp(frac or 0, 0, 1)
    c:mark("cyG", cx, cy, R, t, frac, n, track, fill, und, inv)
    c:op(function(bb, ox, oy) segRing(bb, ox + cx, oy + cy, R, t, frac, n, track, fill, und, inv) end)
end

-- A ring as a sight: a thin outer circle with four ticks across it, and a
-- ring of segments inside, lit clockwise from the top. R is the outer edge.
function CY.reticle(c, cx, cy, R, frac, track, fill, line)
    if R < 8 then return CY.segring(c, cx, cy, R, max(2, R * 0.25), frac, track, fill) end
    local lw = max(1, floor(R * 0.022 + 0.5))
    local tl = max(4, floor(R * 0.15))
    local tw = max(2, lw * 2)
    local ro = R - floor(tl * 0.45)
    c:ring(cx, cy, ro, lw, 1, line, line)
    c:rect(floor(cx - tw / 2), floor(cy - ro - tl * 0.45), tw, tl, fill)
    c:rect(floor(cx - tw / 2), floor(cy + ro - tl * 0.55), tw, tl, line)
    c:rect(floor(cx - ro - tl * 0.45), floor(cy - tw / 2), tl, tw, line)
    c:rect(floor(cx + ro - tl * 0.55), floor(cy - tw / 2), tl, tw, line)
    local gap = max(3, floor(R * 0.08))
    local ri = ro - lw - gap
    CY.segring(c, cx, cy, ri, max(4, round(ri * 0.24)), frac, track, fill, 36)
    return ri
end

-- ─── the neural network (monthly challenge) ──────────────────────────────────

-- Five layers of nodes (3, 5, 5, 3 and one output). As the month's goal
-- fills, the signal moves through: each node's incoming links light one by
-- one, then the node itself, layer after layer. That is 75 steps, so the
-- picture moves on every 1.3% or so.
local LAYERS = { 3, 5, 5, 3, 1 }
local _net
local function netSteps()
    if _net then return _net end
    local nodes, first = {}, {}
    for li, n in ipairs(LAYERS) do
        first[li] = #nodes + 1
        for k = 1, n do nodes[#nodes + 1] = { li = li, k = k } end
    end
    local steps = {}
    for i, nd in ipairs(nodes) do
        if nd.li > 1 then
            for j = first[nd.li - 1], first[nd.li] - 1 do steps[#steps + 1] = { edge = true, a = j, b = i } end
        end
        steps[#steps + 1] = { node = i }
    end
    _net = { nodes = nodes, steps = steps }
    return _net
end
CY.NET_STEPS = #netSteps().steps

--- The network in the box x, y, w, h at `frac` of the goal. node: the lit
--- node colour, link: the lit link colour, track: what isn't lit yet.
function CY.neural(c, x, y, w, h, frac, node, link, track)
    local net = netSteps()
    local steps = net.steps
    local lit = A.clamp(floor((frac or 0) * #steps + 1e-6), 0, #steps)
    local done = lit >= #steps
    local r = max(2, min(h / 16, w / 26))
    local pad = r * 1.6
    local pos = {}
    local nl = #LAYERS
    for i, nd in ipairs(net.nodes) do
        local n = LAYERS[nd.li]
        local px = x + pad + (w - 2 * pad) * (nd.li - 1) / (nl - 1)
        local gapy = (h - 2 * pad) / 4
        local py = y + h / 2 + (nd.k - (n + 1) / 2) * gapy
        pos[i] = { px, py }
    end
    local on_node, on_edge = {}, {}
    for s = 1, lit do
        local st = steps[s]
        if st.node then on_node[st.node] = true else on_edge[st.a .. ">" .. st.b] = true end
    end
    -- links: the unlit ones first, faint, then the lit ones over them
    local faint = track
    local lw = max(1, floor(r * 0.22 + 0.5))
    for pass = 1, 2 do
        for _, st in ipairs(steps) do
            if st.edge then
                local on = on_edge[st.a .. ">" .. st.b] and true or false
                if (pass == 2) == on then
                    local a, b = pos[st.a], pos[st.b]
                    c:polyline({ a[1], a[2], b[1], b[2] }, on and lw or max(1, lw - 1), on and link or faint)
                end
            end
        end
    end
    -- the next node to light: a broken ring round it
    if not done then
        local nxt
        for s = lit + 1, #steps do if steps[s].node then nxt = steps[s].node break end end
        if nxt then
            local p = pos[nxt]
            CY.segring(c, p[1], p[2], r * 1.75, max(1, r * 0.28), 1, track, link, 10)
        end
    end
    -- nodes
    local out = #net.nodes
    for i, p in ipairs(pos) do
        if i == out and done then
            c:ring(p[1], p[2], r * 2.3, max(1, r * 0.25), 1, CY.MAGENTA, CY.MAGENTA)
            c:disc(p[1], p[2], r * 1.45, CY.MAGENTA)
        elseif on_node[i] then
            c:disc(p[1], p[2], r, node)
        else
            c:disc(p[1], p[2], r, track)
        end
    end
    return lit, done
end

return CY
