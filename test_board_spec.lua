package.path = "./?.lua;./common/?.lua;" .. package.path
local Board = dofile("board.lua")

-- Plays the operator perfectly: what the manual says, nothing else.
local function solveAll(b)
    for m, mod in ipairs(b.modules) do
        if mod.type == "wires" then
            assert.equals("ok", b:cutWire(m, Board.wireToCut(b.wire_rules, mod.wires, b.serial)))
        elseif mod.type == "symbols" then
            -- the manual: the one column with all four, in its order
            local col
            for c = 1, Board.COLUMNS do
                local set = {}
                for _, s in ipairs(b.columns[c]) do set[s] = true end
                local all = true
                for _, s in ipairs(mod.shown) do if not set[s] then all = false end end
                if all then assert.is_nil(col); col = c end
            end
            local res
            for _, s in ipairs(b.columns[col]) do
                for _, t in ipairs(mod.shown) do
                    if s == t then res = b:pressSymbol(m, s) end
                end
            end
            assert.equals("ok", res)
        else
            local want = b.dial[mod.shape][mod.lamp and 2 or 1]
            while b:dialPosition(m) ~= want do b:turnDial(m, 1) end
            assert.equals("ok", b:setDial(m))
        end
    end
end

describe("machine and manual", function()
    it("can always be defused by following the manual, the same on both readers", function()
        for level, lvl in ipairs(Board.LEVELS) do
            for seed = 0, 60 do
                local op = Board.new{ seed = seed, level = level, role = "operator" }
                local ex = Board.new{ seed = seed, level = level, role = "expert" }
                assert.same(op.wire_rules, ex.wire_rules)
                assert.same(op.columns, ex.columns)
                assert.same(op.modules, ex.modules)
                assert.equals(lvl.modules, #op.modules)
                assert.matches("^[A-Z0-9]+%d$", op.serial)
                local types = {}
                for _, m in ipairs(op.modules) do
                    types[m.type] = true
                    assert.is_not_nil(m.answer, m.type .. " seed " .. seed)
                end
                for _, t in ipairs(Board.TYPES) do assert.is_true(types[t]) end
                solveAll(op)
                assert.is_true(op:isWon())
                assert.equals(0, op.strikes)
            end
        end
    end)

    it("ends every wire rule list with a rule that always applies, in range", function()
        for seed = 0, 30 do
            local g = Board.generate(seed, 1)
            for n = 3, 6 do
                local rules = g.wire_rules[n]
                assert.equals("always", rules[#rules].cond.kind)
                for _, r in ipairs(rules) do
                    if r.act.kind == "nth" then assert.is_true(r.act.k >= 1 and r.act.k <= n) end
                    if r.act.kind == "first_of" or r.act.kind == "last_of" then
                        assert.is_truthy(({ one = 1, many = 1, first = 1, last = 1 })[r.cond.kind])
                    end
                end
            end
        end
    end)

    it("draws a different manual for another code", function()
        local a, b = Board.generate(1, 1), Board.generate(2, 1)
        assert.are_not.same(a.columns, b.columns)
    end)
end)

describe("operator", function()
    it("gets a strike for a wrong move, and the alarm on the third", function()
        local b = Board.new{ seed = 5, level = 3 }
        local strikes = 0
        for m, mod in ipairs(b.modules) do
            if mod.type == "dial" and strikes < 3 then
                b:turnDial(m, 1)
                if b:dialPosition(m) ~= mod.answer then
                    assert.equals("wrong", b:setDial(m))
                    strikes = strikes + 1
                end
            elseif mod.type == "wires" and strikes < 3 then
                local w = mod.answer == 1 and 2 or 1
                assert.equals("wrong", b:cutWire(m, w))
                assert.is_nil(b:cutWire(m, w))
                strikes = strikes + 1
            end
        end
        assert.equals(strikes, b.strikes)
        while not b:isLost() do b:strike() end
        assert.is_true(b:isOver())
        assert.is_nil(b:cutWire(1, 1))
    end)

    it("keeps the symbols already pressed after a mistake", function()
        for seed = 0, 30 do
            local b = Board.new{ seed = seed, level = 1 }
            for m, mod in ipairs(b.modules) do
                if mod.type == "symbols" then
                    assert.equals("good", b:pressSymbol(m, mod.answer[1]))
                    assert.equals("wrong", b:pressSymbol(m, mod.answer[3]))
                    assert.equals(1, b.progress[m])
                    assert.equals("good", b:pressSymbol(m, mod.answer[2]))
                end
            end
        end
    end)

    it("saves and restores", function()
        local b = Board.new{ seed = 9, level = 2, role = "operator", code = "12345" }
        b:strike()
        local b2 = Board.load(b:serialize())
        assert.equals(1, b2.strikes)
        assert.same(b.modules, b2.modules)
        assert.is_nil(Board.load({ seed = 1, level = 7 }))
    end)
end)
