local root = assert(arg[1])
local private = {}
assert(loadfile(root .. "/SPMobileCombat/Rotation.lua"))("SPMobileCombat", private)
local rotation = assert(private.rotation)
local known = { [11] = true, [12] = true, [13] = true }
local usable = { [11] = false, [12] = true, [13] = true }
local function available(spell) return known[spell] and usable[spell] end
assert(rotation.firstReady({ 11, 12, 13 }, available) == 12)
assert(rotation.firstReady({ 11, 44 }, available) == nil)
local parsed = assert(rotation.parse("12, 11 12\n13"))
assert(#parsed == 3 and parsed[1] == 12 and parsed[2] == 11 and parsed[3] == 13)
assert(rotation.parse("12.5") == nil)
assert(rotation.parse("0") == nil)
assert(rotation.parse("1 2 3 4 5 6 7 8 9 10 11 12 13") == nil)
assert(#assert(rotation.parse("")) == 0)
assert(rotation.recommended({ count = 1, recs = { { actionID = 12, texture = 100 } } }) == 12)
assert(rotation.recommended({ count = 0, recs = { { actionID = 12 } } }) == nil)
assert(rotation.recommended({ count = 1, recs = { { actionID = -12, texture = 100 } } }) == nil)
print("Combat priority selection tests passed")
