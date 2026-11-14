local setup
local ns = {
    Register = function(_, module) setup = module; return module end,
    On = function() end,
}
assert(loadfile(arg[1]))("WolkaraRoue", ns)

local function layout()
    return { free = { count = 4, buttons = {} }, freeLeft = { count = 4, buttons = {} } }
end
function GetActionBarPage() return 2 end
function GetActionInfo(slot)
    if slot == 1 then return "item", 5 end
    if slot == 13 then return "spell", 25 end
end
function GetMacroInfo(id) assert(id == 7); return "My macro", 99 end

ns.db = layout()
setup:Layout()
assert(ns.db.free.buttons[1].entry.id == 25)
assert(ns.db.freeLeft.buttons[1].entry.id == 5)

SPTouchBarsDB = { bank = 5, bindings = {
    [1] = { kind = "spell", value = 100 },
    [49] = { kind = "macro", value = 7 },
    [61] = { kind = "spell", value = 456 },
} }
ns.db = layout()
setup:Layout()
assert(ns.db.free.buttons[1].entry.id == "My macro")
assert(ns.db.freeLeft.buttons[1].entry.id == 456)
assert(SPTouchBarsDB.bindings[49].value == 7)
ns.db.free.buttons[1] = nil
setup:Layout()
assert(not ns.db.free.buttons[1])

ns.db = layout()
ns.db.free.buttons[4] = { entry = { kind = "item", id = 123 } }
setup:Layout()
assert(not ns.db.free.buttons[1] and ns.db.free.buttons[4].entry.id == 123)

SPTouchBarsDB = nil
ns.db = layout()
GetActionInfo = function() end
setup:Layout()
assert(not ns.db.slashplayedSetup)
GetActionInfo = function() return "spell", 1 end
setup:Layout()
assert(ns.db.slashplayedSetup)
print("Wolkara first-run action import: PASS")
