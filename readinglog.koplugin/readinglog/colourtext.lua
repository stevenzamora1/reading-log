--[[
colourtext.lua: KOReader's TextWidget, but a colour ink stays a colour.

TextWidget draws each glyph with bb:colorblitFrom, which flattens its colour
to one grey before it reaches the screen buffer. On a colour screen every
coloured label (accent headings, ring figures, pills) would come out grey.
KOReader's TextBoxWidget already switches to colorblitFromRGB32 for a colour
ink; this does the same for single lines.

Everything else is TextWidget's own: sizing, shaping, truncation. A grey ink,
a greyscale buffer, or a KOReader without the RGB32 blitter all go through
TextWidget's own paintTo, unchanged.

Adapted from bookshelf_colour_text.lua in Bookshelf by AndyHazz (AGPL-3.0).
]]

local TextWidget = require("ui/widget/textwidget")
if type(TextWidget) ~= "table" or type(TextWidget.extend) ~= "function"
        or type(TextWidget.paintTo) ~= "function" then
    return TextWidget
end

local ok_bb, Blitbuffer = pcall(require, "ffi/blitbuffer")
local ok_rt, RenderText = pcall(require, "ui/rendertext")
if not (ok_bb and ok_rt and Blitbuffer.isColor8) then return TextWidget end

local COLOUR_BB = {}
for _, name in ipairs({ "TYPE_BBRGB32", "TYPE_BBRGB24", "TYPE_BBRGB16" }) do
    if Blitbuffer[name] then COLOUR_BB[Blitbuffer[name]] = true end
end

local ColourText = TextWidget:extend{}

function ColourText:paintTo(bb, x, y)
    local c = self.fgcolor
    -- type(), not `c == nil`: a colour is FFI cdata, and comparing cdata with
    -- == runs Blitbuffer's own __eq, which errors on nil.
    if type(c) == "nil" or Blitbuffer.isColor8(c) or not bb.colorblitFromRGB32
            or not COLOUR_BB[bb:getType()] or not self.use_xtext then
        return TextWidget.paintTo(self, bb, x, y)
    end
    -- TextWidget:paintTo's xtext path, with the RGB32 blit.
    self:updateSize()
    if self._is_empty then return end
    if not self._xshaping then
        self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end,
                                               self._shape_idx_to_substitute_with_ellipsis)
    end
    local text_width = bb:getWidth() - x
    if self.max_width and self.max_width < text_width then text_width = self.max_width end
    local pen_x = 0
    local baseline = self.forced_baseline or self._baseline_h
    for _, xglyph in ipairs(self._xshaping) do
        if pen_x >= text_width then break end
        local face = self.face.getFallbackFont(xglyph.font_num)
        local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
        bb:colorblitFromRGB32(
            glyph.bb,
            x + pen_x + glyph.l + xglyph.x_offset,
            y + baseline - glyph.t - xglyph.y_offset,
            0, 0,
            glyph.bb:getWidth(), glyph.bb:getHeight(),
            c)
        pen_x = pen_x + xglyph.x_advance
    end
end

return ColourText
