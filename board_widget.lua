local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local Board  = lrequire("board")
local Shapes = lrequire("shapes")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY  = Blitbuffer.COLOR_GRAY_9
local LIGHT = Blitbuffer.COLOR_GRAY_E

local function text(bb, str, face, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, math.huge, face, str, true, false)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2), cy + math.floor((m.y_top - m.y_bottom) / 2),
        face, str, true, false, color or BLACK)
end

local function paintSymbol(bb, sym, x, y, size)
    Shapes.paint(bb, Board.shapeOf(sym), Board.isFilled(sym), x, y, size)
end

-- A horizontal wire from x0 to x1 around cy, in its pattern; cut wires have
-- a gap in the middle.
local function paintWire(bb, pattern, x0, x1, cy, t, cut)
    local function seg(a, b)
        if pattern == "solid" then
            bb:paintRect(a, cy - math.floor(t / 2), b - a, t, BLACK)
        elseif pattern == "thick" then
            bb:paintRect(a, cy - math.floor(3 * t / 2), b - a, 3 * t, BLACK)
        elseif pattern == "double" then
            bb:paintRect(a, cy - math.floor(t / 2) - 2 * t, b - a, t, BLACK)
            bb:paintRect(a, cy - math.floor(t / 2) + 2 * t, b - a, t, BLACK)
        elseif pattern == "dashed" then
            local x = a
            while x < b do
                bb:paintRect(x, cy - math.floor(t / 2), math.min(5 * t, b - x), t + 1, BLACK)
                x = x + 8 * t
            end
        elseif pattern == "dotted" then
            local x = a + t
            while x < b - t do
                bb:paintCircle(x, cy, t, BLACK)
                x = x + 4 * t
            end
        end
    end
    if cut then
        local mid = math.floor((x0 + x1) / 2)
        seg(x0, mid - 4 * t)
        seg(mid + 4 * t, x1)
    else
        seg(x0, x1)
    end
end

-- ---------------------------------------------------------------------------
-- ModulePanel — one module of the machine, big enough to tap.
-- ---------------------------------------------------------------------------

local ModulePanel = InputContainer:extend{
    board  = nil,
    index  = 1,
    width  = 0,
    height = 0,
    onWire   = nil,   -- function(w)
    onSymbol = nil,   -- function(sym)
}

function ModulePanel:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.label_face = Font:getFace("cfont", math.max(14, math.floor(self.width / 22)))
    self.big_face = Font:getFace("cfont", math.max(20, math.floor(self.width / 8)))
    self.ges_events = {
        TapPanel = { GestureRange:new{ ges = "tap", range = function() return self.paint_rect end } },
    }
end

-- Where the clickable parts are, in panel coordinates.
function ModulePanel:layout()
    local mod = self.board.modules[self.index]
    local w, h = self.width, self.height
    local parts = {}
    if mod.type == "wires" then
        local n = #mod.wires
        local band = math.floor(h / (n + 1))
        local top = math.floor((h - band * n) / 2)
        for i = 1, n do
            parts[i] = { x = 0, y = top + (i - 1) * band, w = w, h = band }
        end
    elseif mod.type == "symbols" then
        local s = math.floor(math.min(w, h) * 0.42)
        local gap = math.floor(s * 0.12)
        local x0 = math.floor((w - 2 * s - gap) / 2)
        local y0 = math.floor((h - 2 * s - gap) / 2)
        for i = 1, 4 do
            local r, c = math.floor((i - 1) / 2), (i - 1) % 2
            parts[i] = { x = x0 + c * (s + gap), y = y0 + r * (s + gap), w = s, h = s }
        end
    end
    return parts
end

function ModulePanel:onTapPanel(_, ges)
    if not self.paint_rect then return false end
    local px, py = ges.pos.x - self.paint_rect.x, ges.pos.y - self.paint_rect.y
    local mod = self.board.modules[self.index]
    for i, p in ipairs(self:layout()) do
        if px >= p.x and px < p.x + p.w and py >= p.y and py < p.y + p.h then
            if mod.type == "wires" and self.onWire then self.onWire(i) end
            if mod.type == "symbols" and self.onSymbol then self.onSymbol(mod.shown[i]) end
            return true
        end
    end
    return true
end

function ModulePanel:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    local b, m = self.board, self.index
    local mod = b.modules[m]
    local w, h = self.width, self.height
    bb:paintRect(x, y, w, h, WHITE)
    local frame = math.max(2, math.floor(w / 150))
    bb:paintBorder(x, y, w, h, frame, BLACK)
    local t = math.max(3, math.floor(w / 110))

    if mod.type == "wires" then
        local cut = b.cut[m] or {}
        for i, p in ipairs(self:layout()) do
            local cy = y + p.y + math.floor(p.h / 2)
            text(bb, tostring(i), self.label_face, x + math.floor(w * 0.06), cy)
            -- Terminals at both ends.
            bb:paintRect(x + math.floor(w * 0.12), cy - 3 * t, 2 * t, 6 * t, GRAY)
            bb:paintRect(x + w - math.floor(w * 0.06) - 2 * t, cy - 3 * t, 2 * t, 6 * t, GRAY)
            paintWire(bb, mod.wires[i], x + math.floor(w * 0.12) + 2 * t, x + w - math.floor(w * 0.06) - 2 * t,
                cy, t, cut[i])
        end
    elseif mod.type == "symbols" then
        local done = b.progress[m] or 0
        local pressed = {}
        for i = 1, done do pressed[mod.answer[i]] = true end
        for i, p in ipairs(self:layout()) do
            local sym = mod.shown[i]
            local px, py = x + p.x, y + p.y
            bb:paintRect(px, py, p.w, p.h, pressed[sym] and LIGHT or WHITE)
            bb:paintBorder(px, py, p.w, p.h, pressed[sym] and 3 * t or t, BLACK)
            paintSymbol(bb, sym, px + math.floor(p.w * 0.15), py + math.floor(p.h * 0.15), math.floor(p.w * 0.7))
        end
    else
        -- Display with its shape, the lamp, and the dial's position.
        local ds = math.floor(math.min(w * 0.4, h * 0.45))
        local dx, dy = x + math.floor(w * 0.08), y + math.floor((h - ds) / 2)
        bb:paintRect(dx, dy, ds, ds, LIGHT)
        bb:paintBorder(dx, dy, ds, ds, t, BLACK)
        Shapes.paint(bb, Board.SHAPES[mod.shape], true, dx + math.floor(ds * 0.1), dy + math.floor(ds * 0.1),
            math.floor(ds * 0.8))
        local lr = math.floor(ds * 0.14)
        local lx, ly = dx + math.floor(ds / 2), dy - lr - 2 * t
        if ly - lr < y + t then ly = dy + ds + lr + 2 * t end
        bb:paintCircle(lx, ly, lr, BLACK)
        if not mod.lamp then bb:paintCircle(lx, ly, lr - t, WHITE) end
        local cx = x + math.floor(w * 0.72)
        local cy = y + math.floor(h / 2)
        local r = math.floor(math.min(w * 0.2, h * 0.32))
        bb:paintCircle(cx, cy, r, BLACK, t)
        text(bb, tostring(b:dialPosition(m)), self.big_face, cx, cy)
        -- Ticks for the 8 positions.
        for k = 0, Board.DIAL_POSITIONS - 1 do
            local a = 2 * math.pi * k / Board.DIAL_POSITIONS - math.pi / 2
            bb:paintCircle(cx + math.floor(math.cos(a) * (r + 3 * t)), cy + math.floor(math.sin(a) * (r + 3 * t)),
                math.max(2, math.floor(t * 0.8)), GRAY)
        end
    end

    if b.solved[m] then
        bb:lightenRect(x + frame, y + frame, w - 2 * frame, h - 2 * frame, 0.6)
        -- A big tick.
        local s = math.floor(math.min(w, h) * 0.3)
        local cx, cy = x + math.floor(w / 2), y + math.floor(h / 2)
        local th = math.max(4, math.floor(s / 7))
        for k = 0, math.floor(s * 0.4) do
            bb:paintRect(cx - math.floor(s * 0.4) + k, cy + k - math.floor(s * 0.1), th, th, BLACK)
        end
        for k = 0, math.floor(s * 0.8) do
            bb:paintRect(cx + k, cy + math.floor(s * 0.3) - k - math.floor(s * 0.1), th, th, BLACK)
        end
    end
end

function ModulePanel:refresh()
    UIManager:setDirty(self, function() return "ui", self.paint_rect or self.dimen end)
end

-- ---------------------------------------------------------------------------
-- ManualPicture — the manual's symbol columns or dial table.
-- ---------------------------------------------------------------------------

local ManualPicture = InputContainer:extend{
    board  = nil,
    page   = "symbols",   -- or "dial"
    width  = 0,
    height = 0,
    labels = nil,         -- { off = "...", on = "..." } for the dial table
}

function ManualPicture:init()
    if self.page == "symbols" then
        local cell = math.floor(math.min(self.width / Board.COLUMNS, self.height / (Board.COLUMN_SIZE + 0.8)))
        self.cell = cell
        self.dimen = Geom:new{ w = cell * Board.COLUMNS, h = math.floor(cell * (Board.COLUMN_SIZE + 0.8)) }
    else
        local rows = #Board.SHAPES + 1
        local cell = math.floor(math.min(self.width / 4, self.height / rows))
        self.cell = cell
        self.dimen = Geom:new{ w = cell * 4, h = cell * rows }
    end
    self.face = Font:getFace("cfont", math.max(14, math.floor(self.cell * 0.4)))
    self.small_face = Font:getFace("cfont", math.max(12, math.floor(self.cell * 0.28)))
end

function ManualPicture:paintTo(bb, x, y)
    local b, cell = self.board, self.cell
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self.page == "symbols" then
        local head = math.floor(cell * 0.8)
        for c = 1, Board.COLUMNS do
            local cx = x + (c - 1) * cell
            text(bb, tostring(c), self.face, cx + math.floor(cell / 2), y + math.floor(head / 2))
            for r = 1, Board.COLUMN_SIZE do
                paintSymbol(bb, b.columns[c][r], cx + math.floor(cell * 0.1), y + head + (r - 1) * cell + math.floor(cell * 0.1),
                    math.floor(cell * 0.8))
            end
            if c > 1 then bb:paintRect(cx, y + head, 1, Board.COLUMN_SIZE * cell, GRAY) end
        end
    else
        local col_w = math.floor(cell * 1.5)
        text(bb, self.labels.off, self.small_face, x + cell + math.floor(col_w / 2), y + math.floor(cell / 2))
        text(bb, self.labels.on, self.small_face, x + cell + col_w + math.floor(col_w / 2), y + math.floor(cell / 2))
        for s = 1, #Board.SHAPES do
            local ry = y + s * cell
            Shapes.paint(bb, Board.SHAPES[s], true, x + math.floor(cell * 0.15), ry + math.floor(cell * 0.15),
                math.floor(cell * 0.7))
            text(bb, tostring(b.dial[s][1]), self.face, x + cell + math.floor(col_w / 2), ry + math.floor(cell / 2))
            text(bb, tostring(b.dial[s][2]), self.face, x + cell + col_w + math.floor(col_w / 2), ry + math.floor(cell / 2))
            bb:paintRect(x, ry, self.dimen.w, 1, GRAY)
        end
    end
end

return { ModulePanel = ModulePanel, ManualPicture = ManualPicture }
