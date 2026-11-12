-- ---------------------------------------------------------------------------
-- board.lua — The Defuser: an alarm machine and its manual, one reader each.
-- Pure Lua (wording lives in the screen).
--
-- Both readers build the same game from the code (common/duo.lua): the
-- machine (a serial number and a few modules) and its manual, whose rules
-- are drawn anew for every game. The operator's reader shows the machine
-- and checks every action; the expert's reader shows the manual. The
-- operator describes, the expert reads out what to do. Three mistakes and
-- the alarm rings.
--
-- Modules:
--   wires    3 to 6 wires, each solid, dashed, dotted, double or thick.
--            The manual has a list of rules per number of wires; the first
--            rule that applies says which wire to cut.
--   symbols  4 symbols out of 14. The manual has 5 columns of 6 symbols;
--            exactly one column holds all four: press them in its order.
--   dial     a display showing a shape and a lamp, on or off. The manual's
--            table gives the dial position (1-8) for each shape and lamp.
-- ---------------------------------------------------------------------------

local Duo = require("duo")

local unpack = table.unpack or unpack

local Board = {}
Board.__index = Board

Board.PATTERNS = { "solid", "dashed", "dotted", "double", "thick" }
Board.SHAPES = { "circle", "square", "triangle_up", "triangle_down", "diamond", "plus", "cross" }
Board.TYPES = { "wires", "symbols", "dial" }
Board.MAX_STRIKES = 3
Board.DIAL_POSITIONS = 8
Board.COLUMNS, Board.COLUMN_SIZE = 5, 6

--   modules  how many modules the machine has
Board.LEVELS = {
    { id = "easy",   modules = 3 },
    { id = "medium", modules = 4 },
    { id = "hard",   modules = 5 },
}

local SERIAL_LETTERS = "ACEFHKMPRTVWXY"
local SERIAL_DIGITS = "23456789"

-- ---------------------------------------------------------------------------
-- Wire rules
--
-- A rule is { cond = { kind, p }, act = { kind, k | p } }.
--   cond kinds: none (no wire of pattern p), one (exactly one), many (more
--     than one), first (the first wire is p), last (the last wire is p),
--     odd (the serial number ends with an odd digit), always.
--   act kinds: nth (cut wire k), last (cut the last wire), first_of / last_of
--     (cut the first / last wire of the condition's pattern; only after a
--     condition that guarantees there is one).
-- ---------------------------------------------------------------------------

local function count(wires, p)
    local k = 0
    for _, w in ipairs(wires) do if w == p then k = k + 1 end end
    return k
end

function Board.condHolds(cond, wires, serial)
    local k = cond.p and count(wires, cond.p)
    if cond.kind == "none" then return k == 0 end
    if cond.kind == "one" then return k == 1 end
    if cond.kind == "many" then return k > 1 end
    if cond.kind == "first" then return wires[1] == cond.p end
    if cond.kind == "last" then return wires[#wires] == cond.p end
    if cond.kind == "odd" then return tonumber(serial:sub(-1)) % 2 == 1 end
    return true
end

function Board.actWire(act, wires)
    if act.kind == "nth" then return act.k end
    if act.kind == "last" then return #wires end
    if act.kind == "first_of" then
        for i, w in ipairs(wires) do if w == act.p then return i end end
    elseif act.kind == "last_of" then
        for i = #wires, 1, -1 do if wires[i] == act.p then return i end end
    end
end

-- The wire to cut: the first rule (for this number of wires) that applies.
function Board.wireToCut(rules, wires, serial)
    for _, rule in ipairs(rules[#wires]) do
        if Board.condHolds(rule.cond, wires, serial) then
            return Board.actWire(rule.act, wires), rule
        end
    end
end

local COND_KINDS = { "none", "one", "many", "first", "last", "odd" }

local function drawWireRules(rng, n)
    local rules, used = {}, {}
    while #rules < 3 do
        local kind = rng:pick(COND_KINDS)
        local p = kind ~= "odd" and rng:pick(Board.PATTERNS) or nil
        local key = kind .. (p or "")
        if not used[key] and not (kind == "odd" and used.odd_any) then
            used[key] = true
            if kind == "odd" then used.odd_any = true end
            local acts = { { kind = "nth", k = rng:random(n) }, { kind = "last" } }
            -- "If the first wire is dotted, cut the first dotted wire" would
            -- only be a long way to say "cut wire 1".
            if kind == "one" or kind == "many" or kind == "last" then
                acts[#acts + 1] = { kind = "first_of", p = p }
            end
            if kind == "one" or kind == "many" or kind == "first" then
                acts[#acts + 1] = { kind = "last_of", p = p }
            end
            rules[#rules + 1] = { cond = { kind = kind, p = p }, act = rng:pick(acts) }
        end
    end
    rules[#rules + 1] = { cond = { kind = "always" }, act = { kind = "nth", k = rng:random(n) } }
    return rules
end

-- ---------------------------------------------------------------------------
-- The game
-- ---------------------------------------------------------------------------

local function symbolOf(shape_i, filled) return (shape_i - 1) * 2 + (filled and 1 or 2) end
Board.symbolOf = symbolOf

function Board.shapeOf(sym) return Board.SHAPES[math.floor((sym - 1) / 2) + 1] end
function Board.isFilled(sym) return sym % 2 == 1 end

local function columnHasAll(col, syms)
    local set = {}
    for _, s in ipairs(col) do set[s] = true end
    for _, s in ipairs(syms) do if not set[s] then return false end end
    return true
end

-- The machine and the manual for (seed, level).
function Board.generate(seed, level)
    local lvl = Board.LEVELS[level] or Board.LEVELS[1]
    local rng = Duo.rng(seed, "defuser")
    local g = {}

    -- Serial: five letters or digits, then a digit.
    local chars = {}
    for _i = 1, 5 do
        local pool = rng:random(3) == 1 and SERIAL_DIGITS or SERIAL_LETTERS
        local j = rng:random(#pool)
        chars[#chars + 1] = pool:sub(j, j)
    end
    local j = rng:random(#SERIAL_DIGITS)
    chars[#chars + 1] = SERIAL_DIGITS:sub(j, j)
    g.serial = table.concat(chars)

    -- The manual.
    g.wire_rules = {}
    for n = 3, 6 do g.wire_rules[n] = drawWireRules(rng, n) end
    g.columns = {}
    for c = 1, Board.COLUMNS do
        local t = {}
        for s = 1, 14 do t[s] = s end
        rng:shuffle(t)
        g.columns[c] = { unpack(t, 1, Board.COLUMN_SIZE) }
    end
    g.dial = {}
    for s = 1, #Board.SHAPES do
        g.dial[s] = { rng:random(Board.DIAL_POSITIONS), rng:random(Board.DIAL_POSITIONS) }
    end

    -- The machine: every type once, then at random; in a shuffled order.
    local types = {}
    for _, t in ipairs(Board.TYPES) do types[#types + 1] = t end
    while #types < lvl.modules do types[#types + 1] = rng:pick(Board.TYPES) end
    rng:shuffle(types)
    g.modules = {}
    for _, t in ipairs(types) do
        local m = { type = t }
        if t == "wires" then
            m.wires = {}
            for _i = 1, rng:random(3, 6) do m.wires[#m.wires + 1] = rng:pick(Board.PATTERNS) end
            m.answer = Board.wireToCut(g.wire_rules, m.wires, g.serial)
        elseif t == "symbols" then
            -- Four symbols of one column that no other column holds together.
            for _try = 1, 200 do
                local c = rng:random(Board.COLUMNS)
                local idx = { 1, 2, 3, 4, 5, 6 }
                rng:shuffle(idx)
                local picked = {}
                for i = 1, 4 do picked[i] = idx[i] end
                table.sort(picked)
                local syms = {}
                for i = 1, 4 do syms[i] = g.columns[c][picked[i]] end
                local others = 0
                for c2 = 1, Board.COLUMNS do
                    if c2 ~= c and columnHasAll(g.columns[c2], syms) then others = others + 1 end
                end
                if others == 0 then
                    m.answer = syms      -- in the column's order
                    m.column = c
                    m.shown = { syms[1], syms[2], syms[3], syms[4] }
                    rng:shuffle(m.shown)
                    break
                end
            end
        else
            m.shape = rng:random(#Board.SHAPES)
            m.lamp = rng:random(2) == 1
            m.answer = g.dial[m.shape][m.lamp and 2 or 1]
            repeat m.start = rng:random(Board.DIAL_POSITIONS) until m.start ~= m.answer
        end
        g.modules[#g.modules + 1] = m
    end
    return g
end

-- o: seed, level, role ("operator" | "expert"), code, and the saved state.
function Board.new(o)
    local self = setmetatable({}, Board)
    self.seed  = o.seed or 0
    self.level = Board.LEVELS[o.level] and o.level or 1
    self.role  = o.role == "expert" and "expert" or "operator"
    self.code  = o.code
    local g = Board.generate(self.seed, self.level)
    for k, v in pairs(g) do self[k] = v end
    self.strikes  = o.strikes or 0
    self.solved   = o.solved or {}     -- [m] = true
    self.progress = o.progress or {}   -- symbols: presses done; dial: position
    self.cut      = o.cut or {}        -- [m] = { [wire] = true }
    self.started  = o.started
    self.finished = o.finished
    return self
end

function Board:serialize()
    return {
        seed = self.seed, level = self.level, role = self.role, code = self.code,
        strikes = self.strikes, solved = self.solved, progress = self.progress, cut = self.cut,
        started = self.started, finished = self.finished,
    }
end

function Board.load(t)
    if type(t) ~= "table" or type(t.seed) ~= "number" or not Board.LEVELS[t.level] then return nil end
    return Board.new(t)
end

function Board:solvedCount()
    local k = 0
    for i = 1, #self.modules do if self.solved[i] then k = k + 1 end end
    return k
end

function Board:isWon()
    return self:solvedCount() == #self.modules
end

function Board:isLost()
    return self.strikes >= Board.MAX_STRIKES
end

function Board:isOver()
    return self:isWon() or self:isLost()
end

function Board:strike()
    self.strikes = self.strikes + 1
end

-- Operator actions. Each returns "ok" (module solved), "good" (right, the
-- module goes on), "wrong" (a strike) or nil (nothing to do).

function Board:cutWire(m, w)
    local mod = self.modules[m]
    if self:isOver() or self.solved[m] or mod.type ~= "wires" then return nil end
    self.cut[m] = self.cut[m] or {}
    if self.cut[m][w] then return nil end
    self.cut[m][w] = true
    if w == mod.answer then
        self.solved[m] = true
        return "ok"
    end
    self:strike()
    return "wrong"
end

function Board:pressSymbol(m, sym)
    local mod = self.modules[m]
    if self:isOver() or self.solved[m] or mod.type ~= "symbols" then return nil end
    local done = self.progress[m] or 0
    for i = 1, done do if mod.answer[i] == sym then return nil end end
    if mod.answer[done + 1] == sym then
        self.progress[m] = done + 1
        if done + 1 == #mod.answer then
            self.solved[m] = true
            return "ok"
        end
        return "good"
    end
    self:strike()
    return "wrong"
end

function Board:dialPosition(m)
    return self.progress[m] or self.modules[m].start
end

function Board:turnDial(m, d)
    local mod = self.modules[m]
    if self:isOver() or self.solved[m] or mod.type ~= "dial" then return end
    local p = self:dialPosition(m)
    self.progress[m] = (p - 1 + d) % Board.DIAL_POSITIONS + 1
end

function Board:setDial(m)
    local mod = self.modules[m]
    if self:isOver() or self.solved[m] or mod.type ~= "dial" then return nil end
    if self:dialPosition(m) == mod.answer then
        self.solved[m] = true
        return "ok"
    end
    self:strike()
    return "wrong"
end

return Board
