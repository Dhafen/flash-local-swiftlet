local setup, changed = nil, 0
local ns = {
    MAX_FREE = 12, MAX_SLOTS = 12,
    Register = function(_, module) setup = module; return module end,
    MarkChanged = function() changed = changed + 1 end,
}
assert(loadfile(arg[1]))("WolkaraRoue", ns)
local function layout()
    local wheels = {}
    for i = 1, 4 do wheels[i] = { enabled = false, slots = 8, entries = {} } end
    return { wheels = wheels, free = { count = 4, buttons = {} }, freeLeft = { count = 4, buttons = {} } }
end
-- New character: just the two native tap-open wheels; no auto-import.
ns.db = layout()
setup:Layout()
assert(ns.db.free.count == 0 and ns.db.freeLeft.count == 0)
assert(ns.db.wheels[1].enabled and ns.db.wheels[2].enabled)
assert(not ns.db.wheels[3].enabled and not ns.db.wheels[4].enabled)
assert(next(ns.db.wheels[1].entries) == nil)
assert(ns.db.slashplayedTapWheels and changed == 1)
-- The player can subsequently opt into either side wheel; layout must not reset it.
ns.db.free.count = 3
ns.db.wheels[1].enabled = false
setup:Layout()
assert(ns.db.free.count == 3 and not ns.db.wheels[1].enabled and changed == 1)
-- Upgrade: preserve old and current slots, migrate without duplicate entries.
ns.db = layout()
local right = ns.db.free.buttons
local left = ns.db.freeLeft.buttons
local w1, w2 = ns.db.wheels[1], ns.db.wheels[2]
local existing = { kind = "spell", id = 11 }
w1.entries[1] = existing
right[1] = { entry = { kind = "spell", id = 11 } }
right[2] = { entry = { kind = "spell", id = 22 } }
left[4] = { entry = { kind = "tactara", id = "main", name = "One Button Rotation" } }
setup:Layout()
assert(w1.entries[1] == existing and w1.entries[2].id == 22)
assert(w1.entries[3] == nil)
assert(w2.entries[1].id == "main" and w2.entries[1].name == "One Button Rotation")
assert(right[2].entry.id == 22 and left[4].entry.id == "main")
assert(ns.db.free.count == 0 and ns.db.freeLeft.count == 0)
-- Full wheel: never discard overflow from the source or replace a saved slot.
ns.db = layout()
for i = 1, 12 do ns.db.wheels[1].entries[i] = { kind = "spell", id = i } end
ns.db.wheels[1].slots = 12
ns.db.free.buttons[1] = { entry = { kind = "item", id = 500 } }
setup:Layout()
assert(ns.db.wheels[1].entries[12].id == 12 and ns.db.free.buttons[1].entry.id == 500)
-- A previously hidden slot may be recovered as well; expand the ring only if needed.
ns.db = layout()
for i = 1, 8 do ns.db.wheels[1].entries[i] = { kind = "spell", id = i } end
ns.db.free.buttons[12] = { entry = { kind = "item", id = 300 } }
setup:Layout()
assert(ns.db.wheels[1].slots == 9 and ns.db.wheels[1].entries[9].id == 300)
print("Wolkara tap-open layout migration: PASS")
