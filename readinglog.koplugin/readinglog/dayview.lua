--[[
dayview.lua — a day of the calendar, tapped.

A card over the screen with the day's date and one book read that day: its
cover, title, author and status, and what the day did (time read, pages, how
far through the book it got). With more than one book, arrows (or a swipe)
go through them. Tap the book to open it; tap the X, outside the card, or
Back to close it. Read the first time a day is tapped (see A.dayView in
init.lua).
]]

local A = ...
local T = A._
local D = A.D

local floor, max, min = math.floor, math.max, math.min

local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen

local STATUS = { reading = T("Reading"), finished = T("Finished"), on_hold = T("On hold") }

local View = InputContainer:extend{
    name = "readinglog_day",
    modal = true,
    -- (covers: dithered, and a flashing refresh going in, turning and
    -- closing; a plain one left the calendar ghosted under it, worst on a
    -- colour screen)
    dithered = true,
    ctx = nil,
    key = nil, -- "YYYY-MM-DD"
    list = nil,
    i = 1,     -- the book shown
}

-- An arrow, < (dir -1) or > (dir 1), centred on cx, cy.
local function chevron(c, cx, cy, r, dir, lw, col)
    c:polyline({ cx - dir * r * 0.5, cy - r, cx + dir * r * 0.5, cy, cx - dir * r * 0.5, cy + r }, lw, col)
end

-- The card, w wide, showing book self.i; returns the canvas. Every book is
-- drawn at the same height, so the card doesn't jump when turning.
local function draw(self, w)
    local s = w / 900
    local function px(v) return max(1, floor(v * s + 0.5)) end
    local tone = A.tone("ink")
    local list = self.list or {}
    local n = #list
    local muted = tone.muted or A.mix(tone.fg, tone.bg, 0.45)
    local rule = A.mix(tone.fg, tone.bg, 0.8)
    local pad = px(34)
    local head_h = px(96)
    local cov_w = floor(w * 0.26)
    local cov_h = floor(cov_w * 1.5)
    local info_h = px(230)
    local stats_h = px(130)
    local pager_h = n > 1 and px(100) or 0
    local h
    if n == 0 then
        h = head_h + px(140)
    else
        h = head_h + pad + cov_h + px(24) + info_h + stats_h + pager_h + px(16)
    end
    local c = A.canvas{ w = w, h = h, tone = tone, radius = px(28), border_w = max(2, px(3)) }

    -- the date, and the X
    local y, m, d = self.key:match("^(%d+)-(%d+)-(%d+)$")
    local when = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    c:label(A.date("%A", when) .. " " .. tonumber(d) .. " " .. A.date("%B", when), px(34), w / 2, head_h / 2,
        { bold = true, anchor = "c", valign = "mid", max_w = w - 2 * px(110) })
    local xr = px(20)
    local xc, yc = w - pad - xr, head_h / 2
    local lw = max(2, px(4))
    c:polyline({ xc - xr, yc - xr, xc + xr, yc + xr }, lw, tone.fg)
    c:polyline({ xc - xr, yc + xr, xc + xr, yc - xr }, lw, tone.fg)
    c:region("close", xc - xr * 2.5, 0, xr * 5, head_h)
    c:rect(pad, head_h - 1, w - 2 * pad, max(1, px(2)), rule)

    if n == 0 then
        c:label(T("Nothing read that day"), px(28), w / 2, head_h + px(70), { anchor = "c", valign = "mid", color = muted })
        return c
    end

    local e = list[self.i]
    -- the cover, in the middle (dressed by a downloaded style, as on Continue reading)
    local cy0 = head_h + pad
    local cx0 = floor((w - cov_w) / 2)
    c:cover(e.fp, cx0, cy0, cov_w, cov_h, { title = e.title, edge = tone.border or tone.bg })
    if A.packHas and A.packHas("bookCover") then
        A.packCall("bookCover", c, cx0, cy0, cov_w, cov_h, tone, { pct = e.pct or 0 })
    end
    -- title, author, status
    local iy = cy0 + cov_h + px(24)
    local tw = w - 2 * pad - px(40)
    local t_title = c:textbox(e.title or "", px(38), tw, 2, { bold = true, align = "center" })
    local t_author = e.author and e.author ~= "" and c:text(e.author, px(28), { color = muted, max_w = tw }) or nil
    local _, status = D.progress(e.fp)
    local st = status and STATUS[status] or nil
    local t_st = st and c:text(st, px(24), { max_w = tw - px(40) }) or nil
    local gap = px(10)
    local block = t_title.h + (t_author and (gap + t_author.h) or 0) + (t_st and (gap * 1.8 + t_st.h + px(16)) or 0)
    local ty = iy + max(0, (info_h - block) / 2)
    c:put(t_title, w / 2 - t_title.w / 2, ty)
    ty = ty + t_title.h
    if t_author then
        ty = ty + gap
        c:put(t_author, w / 2, ty, "c")
        ty = ty + t_author.h
    end
    if t_st then
        ty = ty + gap * 1.8
        local pw, ph = t_st.w + px(36), t_st.h + px(16)
        c:frame(w / 2 - pw / 2, ty, pw, ph, ph * 0.35, max(1, px(2)), tone.fg, tone.bg)
        c:put(t_st, w / 2, ty + ph / 2, "c", "mid")
    end
    c:region("book", pad, cy0, w - 2 * pad, cov_h + px(24) + info_h)

    -- what the day did
    local sy = iy + info_h
    c:rect(pad, sy, w - 2 * pad, max(1, px(2)), rule)
    local cells = {
        { A.fmtMinutes((e.secs or 0) / 60), T("Time read") },
        { A.thousands(e.pages or 0), T("Pages read") },
    }
    if e.pct then cells[#cells + 1] = { floor(e.pct * 100 + 0.5) .. "%", T("of the book") } end
    local cw = (w - 2 * pad) / #cells
    for k, cell in ipairs(cells) do
        local ccx = pad + cw * (k - 0.5)
        local t_v = c:text(cell[1], px(42), { bold = true, max_w = cw - px(16) })
        local t_l = c:text(cell[2], px(24), { color = muted, max_w = cw - px(16) })
        local vy = sy + (stats_h - t_v.h - px(6) - t_l.h) / 2
        c:put(t_v, ccx, vy, "c")
        c:put(t_l, ccx, vy + t_v.h + px(6), "c")
        if k > 1 then c:rect(floor(pad + cw * (k - 1)), sy + px(22), max(1, px(2)), stats_h - px(44), rule) end
    end

    -- with more than one book: ‹  2 of 3  ›
    if n > 1 then
        local py = sy + stats_h
        c:rect(pad, py, w - 2 * pad, max(1, px(2)), rule)
        local mid = py + pager_h / 2
        c:label(A.tr("%1 of %2", self.i, n), px(28), w / 2, mid, { bold = true, anchor = "c", valign = "mid" })
        local bw, bh = px(120), px(64)
        local r = px(16)
        local alw = max(2, px(5))
        for _, b in ipairs({ { "prev", pad, -1, self.i > 1 }, { "next", w - pad - bw, 1, self.i < n } }) do
            local id, bx, dir, on = b[1], b[2], b[3], b[4]
            local col = on and tone.fg or A.mix(tone.fg, tone.bg, 0.7)
            c:frame(bx, mid - bh / 2, bw, bh, bh / 2, max(1, px(2)), col, tone.bg)
            chevron(c, bx + bw / 2, mid, r, dir, alw, col)
            c:region(id, bx - px(10), py, bw + px(20), pager_h)
        end
    end
    return c
end

local function hit(regions, x, y)
    for _, r in ipairs(regions or {}) do
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r.id end
    end
    return nil
end

function View:layout()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w = min(floor(sw * 0.7), floor(sh * 0.5))
    self.card = draw(self, w)
    -- (a very small screen: a narrower card until it fits)
    while self.card.h > sh * 0.95 and w > sw * 0.5 do
        w = floor(w * 0.9)
        self.card = draw(self, w)
    end
    local ch = min(self.card.h, sh - 10)
    self.cx, self.cy = floor((sw - w) / 2), floor((sh - ch) / 2)
    self.card_dimen = Geom:new{ x = self.cx, y = self.cy, w = w, h = ch }
    self[1] = self.card
end

function View:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.i = A.clamp(self.i or 1, 1, math.max(1, #(self.list or {})))
    self:layout()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local function all() return self.dimen end
    self.ges_events = {
        ReadingLogDayTap = { GestureRange:new{ ges = "tap", range = all } },
        ReadingLogDayHold = { GestureRange:new{ ges = "hold", range = all } },
        ReadingLogDaySwipe = { GestureRange:new{ ges = "swipe", range = all } },
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            DayNext = { { Device.input.group.PgFwd } },
            DayPrev = { { Device.input.group.PgBack } },
        }
    end
end

function View:paintTo(bb, x, y)
    self.card:paintTo(bb, (x or 0) + self.cx, (y or 0) + self.cy)
end

-- Show another book of the day (step -1 or 1).
function View:turn(step)
    local n = #(self.list or {})
    local to = self.i + step
    if n < 2 or to < 1 or to > n then return false end
    self.i = to
    self:layout()
    UIManager:setDirty(self, "flashui", self.card_dimen, true)
    return true
end

function View:close()
    if self._closed then return end
    self._closed = true
    UIManager:close(self, "flashui", self.card_dimen, true)
end
function View:onClose() self:close() return true end
function View:onDayNext() self:turn(1) return true end
function View:onDayPrev() self:turn(-1) return true end
function View:onReadingLogDayHold() return true end

function View:onReadingLogDaySwipe(_, ges)
    local dir = ges and ges.direction
    if dir == "west" then self:turn(1)
    elseif dir == "east" then self:turn(-1)
    elseif dir == "south" then self:close() end
    return true
end

function View:onReadingLogDayTap(_, ges)
    local p = ges and ges.pos
    local region
    if p then region = hit(self.card.regions, p.x - self.cx, p.y - self.cy) end
    if region == "prev" then self:turn(-1) return true end
    if region == "next" then self:turn(1) return true end
    -- a tap inside the card that isn't on anything: leave it open
    if p and not region and self.card_dimen and self.card_dimen:contains(p) then return true end
    local e = region == "book" and self.list[self.i] or nil
    self:close()
    if e and e.fp then
        local ctx = self.ctx
        UIManager:nextTick(function() D.openBook(ctx, e.fp) end)
    end
    return true
end

--- Show the books read on day `key` ("YYYY-MM-DD"): list = that day's entries.
return function(ctx, key, list)
    local v = View:new{ ctx = ctx, key = key, list = list or {} }
    UIManager:show(v, "flashui", v.card_dimen, nil, nil, true)
    return v
end
