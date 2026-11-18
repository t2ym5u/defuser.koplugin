local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local ConfirmBox      = require("ui/widget/confirmbox")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local Duo        = require("duo")
local ScreenBase = require("screen_base")

local Board      = lrequire("board")
local Widgets    = lrequire("board_widget")

local RULES_EN = [[
The Defuser — two readers, one alarm machine

An alarm machine is about to ring. The operator has it in front of them; the expert has its manual. Neither can stop it alone!

Starting
• One player taps New game → Start a game and reads the code aloud. The other taps New game → Join a game and types it. One is the operator (the machine), the other the expert (the manual). The manual's rules are drawn anew for every game.
• The difficulty is set by the player who starts (menu): 3, 4 or 5 modules.

Playing
• Operator: describe the machine — its serial number and each module (the tabs at the bottom). Do only what the expert tells you.
• Expert: find the right page of the manual and say what to do.
• Wires: the rules for that number of wires, read in order; the first one that applies says which wire to cut. Wires are counted from the top.
• Symbols: exactly one column of the manual holds all four symbols. Press them in that column's order, top to bottom.
• Dial: read the shape on the display and whether the lamp is lit; the manual's table gives the dial position. Turn the dial with − and +, then tap Set.

Every wrong move is a mistake; at the third one, the alarm rings. Stop every module to win.
]]

local RULES_FR = [[
Le désamorceur — deux liseuses, une machine à alarme

Une machine à alarme va sonner. L'opérateur l'a devant lui ; l'expert a son manuel. Aucun des deux ne peut l'arrêter seul !

Pour commencer
• Un joueur touche Nouvelle partie → Lancer une partie et lit le code à voix haute. L'autre touche Nouvelle partie → Rejoindre une partie et le saisit. L'un est l'opérateur (la machine), l'autre l'expert (le manuel). Les règles du manuel changent à chaque partie.
• La difficulté est celle du joueur qui lance (menu) : 3, 4 ou 5 modules.

Déroulement
• Opérateur : décrivez la machine — son numéro de série et chaque module (les onglets en bas). Ne faites que ce que l'expert vous dit.
• Expert : trouvez la bonne page du manuel et dites quoi faire.
• Fils : les règles pour ce nombre de fils, lues dans l'ordre ; la première qui s'applique dit quel fil couper. Les fils se comptent à partir du haut.
• Symboles : une seule colonne du manuel contient les quatre symboles. Appuyez-les dans l'ordre de cette colonne, de haut en bas.
• Cadran : lisez la forme de l'écran et si le voyant est allumé ; le tableau du manuel donne la position du cadran. Tournez le cadran avec − et +, puis touchez Valider.

Chaque mauvais geste est une erreur ; à la troisième, l'alarme sonne. Arrêtez tous les modules pour gagner.
]]

local LEVEL_NAMES = { "Easy", "Medium", "Hard" }
local PATTERN_WORDS = { solid = "solid", dashed = "dashed", dotted = "dotted", double = "double", thick = "thick" }
local TYPE_WORDS = { wires = "Wires", symbols = "Symbols", dial = "Dial" }

-- One wire rule as a sentence of the manual.
local function ruleText(rule)
    local c, a = rule.cond, rule.act
    local p = c.p and _(PATTERN_WORDS[c.p])
    local cond
    if c.kind == "none" then cond = T(_("If there is no %1 wire"), p)
    elseif c.kind == "one" then cond = T(_("If there is exactly one %1 wire"), p)
    elseif c.kind == "many" then cond = T(_("If there is more than one %1 wire"), p)
    elseif c.kind == "first" then cond = T(_("If the first wire is %1"), p)
    elseif c.kind == "last" then cond = T(_("If the last wire is %1"), p)
    elseif c.kind == "odd" then cond = _("If the serial number ends with an odd digit")
    else cond = _("Otherwise") end
    local act
    if a.kind == "nth" then act = T(_("cut wire number %1"), a.k)
    elseif a.kind == "last" then act = _("cut the last wire")
    elseif a.kind == "first_of" then act = T(_("cut the first %1 wire"), _(PATTERN_WORDS[a.p]))
    else act = T(_("cut the last %1 wire"), _(PATTERN_WORDS[a.p])) end
    return T(_("%1, %2."), cond, act)
end

local DefuserScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DefuserScreen:init()
    self.board = Board.load(self.plugin:loadState())
    self.module = 1
    self.page = "wires_a"
    ScreenBase.init(self)
end

function DefuserScreen:serializeState()
    return self.board and self.board:serialize() or nil
end

function DefuserScreen:save()
    self.plugin:saveState(self:serializeState())
end

function DefuserScreen:isRoundOver()
    return not self.board or (self.board.role == "operator" and self.board:isOver())
end

function DefuserScreen:rebuild()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function DefuserScreen:actionRows()
    local b = self.board
    if not b then return {} end
    if b.role == "expert" then
        local pages = {
            { id = "wires_a", text = _("Wires 3–4") }, { id = "wires_b", text = _("Wires 5–6") },
            { id = "symbols", text = _("Symbols") }, { id = "dial", text = _("Dial") },
        }
        local row = {}
        for _i, pg in ipairs(pages) do
            local id = pg.id
            row[#row + 1] = { text = (self.page == id and "▸ " or "") .. pg.text,
                              callback = function() self.page = id; self:rebuild() end }
        end
        if self:isLandscape() then return { { row[1], row[2] }, { row[3], row[4] } } end
        return { row }
    end
    local tabs = {}
    for m = 1, #b.modules do
        local label = tostring(m) .. (b.solved[m] and " ✓" or "")
        if m == self.module then label = "▸ " .. label end
        tabs[#tabs + 1] = { text = label, callback = function() self.module = m; self:rebuild() end }
    end
    local rows = { tabs }
    if b.modules[self.module].type == "dial" and not b.solved[self.module] then
        rows[#rows + 1] = {
            { text = "−", callback = function() self:onTurn(-1) end },
            { text = "+", callback = function() self:onTurn(1) end },
            { text = _("Set"), callback = function() self:onSet() end },
        }
    end
    return rows
end

function DefuserScreen:manualContent(w, h)
    local b = self.board
    local face = Font:getFace("infofont", 18)
    if self.page == "wires_a" or self.page == "wires_b" then
        local lines = { _("Wires are counted from the top. Read the rules in order: the first one that applies says which wire to cut.") }
        local from = self.page == "wires_a" and 3 or 5
        for n = from, from + 1 do
            lines[#lines + 1] = ""
            lines[#lines + 1] = T(_("%1 wires:"), n)
            for i, rule in ipairs(b.wire_rules[n]) do
                lines[#lines + 1] = T("%1. %2", i, ruleText(rule))
            end
        end
        return TextBoxWidget:new{ text = table.concat(lines, "\n"), face = face, width = w }
    end
    local intro = self.page == "symbols"
        and _("Exactly one column holds all four symbols of the module. Press them in that column's order, top to bottom.")
        or _("Find the shape on the display, then read the dial position for a lamp that is off or lit. Turn the dial there and tap Set.")
    local tb = TextBoxWidget:new{ text = intro, face = face, width = w }
    local pic = Widgets.ManualPicture:new{
        board = b, page = self.page, width = w,
        height = h - tb:getSize().h - Size.span.vertical_large,
        labels = { off = _("Lamp: off"), on = _("Lamp: lit") },
    }
    return VerticalGroup:new{ align = "center", tb, VerticalSpan:new{ width = Size.span.vertical_large }, pic }
end

function DefuserScreen:buildLayout()
    local title_bar = self:buildTitleBar(_("The Defuser"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Difficulty: %1"), _(LEVEL_NAMES[self.plugin:getSetting("level", 1)])),
              callback = function() self:openLevelMenu() end },
        }
        if self.board then
            items[#items + 1] = { text = _("Show the game code"), callback = function() self:showCode() end }
        end
        items[#items + 1] = self:makeRulesButtonConfig(RULES_EN, RULES_FR)
        return items
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:actionRows()),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local content
    local b = self.board
    if not b then
        content = TextBoxWidget:new{
            text = _("Each player needs a reader with this game. One starts a game and reads the code aloud; the other joins with that code."),
            face = Font:getFace("infofont"),
            width = math.min(budget_w, Device.screen:scaleBySize(500)),
            alignment = "center",
        }
    elseif b.role == "expert" then
        content = self:manualContent(budget_w, budget_h)
    else
        local mod = b.modules[self.module]
        local head = TextBoxWidget:new{
            text = T(_("Serial number: %1"), b.serial) .. "\n"
                .. T(_("Module %1: %2"), self.module, _(TYPE_WORDS[mod.type])),
            face = Font:getFace("infofont"),
            width = budget_w,
            alignment = "center",
        }
        local ph = budget_h - head:getSize().h - Size.span.vertical_large
        self.panel = Widgets.ModulePanel:new{
            board = b, index = self.module,
            width = math.min(budget_w, math.floor(ph * 1.25)), height = math.min(ph, math.floor(budget_w * 0.95)),
            onWire = function(w) self:onWire(w) end,
            onSymbol = function(sym) self:onSymbol(sym) end,
        }
        content = VerticalGroup:new{ align = "center", head, VerticalSpan:new{ width = Size.span.vertical_large }, self.panel }
    end
    local frame = FrameContainer:new{ padding = 0, margin = 0, bordersize = 0, content }

    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center", frame, HorizontalSpan:new{ width = self:getGutter() }, controls,
        })
    else
        self:buildPortraitLayout(title_bar, frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

local function duration(secs)
    secs = math.max(0, secs or 0)
    return T(_("%1 min %2 s"), math.floor(secs / 60), secs % 60)
end

function DefuserScreen:updateStatus(message)
    local b = self.board
    local status = message
    if not status then
        if not b then
            status = _("Start or join a game.")
        elseif b.role == "expert" then
            status = _("Expert: ask the operator what they see.")
        elseif b:isWon() then
            status = T(_("Machine stopped in %1!"), duration((b.finished or 0) - (b.started or 0)))
        elseif b:isLost() then
            status = _("Third mistake: the alarm rings!")
        else
            status = self:joinStatus(
                T(_("Modules stopped: %1/%2"), b:solvedCount(), #b.modules),
                T(_("Mistakes: %1/%2"), b.strikes, Board.MAX_STRIKES))
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Operator
-- ---------------------------------------------------------------------------

function DefuserScreen:after(res)
    local b = self.board
    if not res then return end
    b.started = b.started or os.time()
    if b:isOver() and not b.finished then b.finished = os.time() end
    self:save()
    if res == "ok" and not b:isWon() then
        -- On to the next module still running.
        for k = 1, #b.modules do
            local m = (self.module + k - 1) % #b.modules + 1
            if not b.solved[m] then self.module = m break end
        end
    end
    self:rebuild()
    self:refreshActionBar()
    if res == "wrong" then
        self:showMessage(b:isLost() and _("Third mistake: the alarm rings!")
            or T(_("Wrong! Mistake %1 of %2."), b.strikes, Board.MAX_STRIKES), 3)
    elseif res == "ok" then
        self:showMessage(b:isWon() and T(_("Machine stopped in %1!"), duration(b.finished - b.started))
            or _("Module stopped!"), 2)
    end
end

function DefuserScreen:onWire(w)
    local b = self.board
    if b:isOver() or b.solved[self.module] or (b.cut[self.module] or {})[w] then return end
    local m = self.module
    UIManager:show(ConfirmBox:new{
        text = T(_("Cut wire %1?"), w),
        ok_text = _("Cut"),
        ok_callback = function() self:after(b:cutWire(m, w)) end,
    })
end

function DefuserScreen:onSymbol(sym)
    self:after(self.board:pressSymbol(self.module, sym))
end

function DefuserScreen:onTurn(d)
    local b = self.board
    b.started = b.started or os.time()
    b:turnDial(self.module, d)
    self:save()
    self.panel:refresh(self)
end

function DefuserScreen:onSet()
    self:after(self.board:setDial(self.module))
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function DefuserScreen:onNewGame()
    Duo.newGameDialog{
        title     = _("The Defuser"),
        nvariants = #Board.LEVELS,
        variant   = self.plugin:getSetting("level", 1),
        variant_text = function(v) return T(_("Difficulty: %1"), _(LEVEL_NAMES[v])) end,
        roles = {
            { id = "operator", text = _("Operator (the machine)") },
            { id = "expert",   text = _("Expert (the manual)") },
        },
        on_start = function(game)
            self.board = Board.new{ seed = game.seed, level = game.variant, role = game.role, code = game.code }
            self.module, self.page = 1, "wires_a"
            self:save()
            self:rebuild()
        end,
    }
end

function DefuserScreen:showCode()
    local b = self.board
    self:showMessage(T(_("Game code: %1"), Duo.format(b.code)) .. "\n"
        .. T(_("Difficulty: %1"), _(LEVEL_NAMES[b.level])), 6)
end

function DefuserScreen:openLevelMenu()
    local dlg
    local buttons = {}
    for i, name in ipairs(LEVEL_NAMES) do
        buttons[#buttons + 1] = { {
            text = _(name),
            callback = function()
                UIManager:close(dlg)
                self.plugin:saveSetting("level", i)
            end,
        } }
    end
    dlg = ButtonDialog:new{ title = _("Difficulty of the games you start"), buttons = buttons }
    UIManager:show(dlg)
end

return DefuserScreen
