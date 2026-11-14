local model = assert(loadfile(arg[1]))()
local gcd = { startTime = 10, duration = 1.5 }
local short = { startTime = 10, duration = 1.2 }
local secret = {}
local function readable(value) return value ~= secret end
assert(not model.isOwnCooldown(gcd, gcd, readable))
assert(model.isOwnCooldown(short, gcd, readable))
assert(not model.isOwnCooldown({ startTime = 0, duration = 0 }, gcd, readable))
assert(not model.isOwnCooldown({ startTime = secret, duration = 30 }, gcd, readable))
assert(model.isOwnCooldown({ startTime = 10, duration = 30 }, gcd, readable))
assert(not model.isOwnCooldown({ startTime = 10, duration = 30, isEnabled = false }, gcd, readable))
assert(not model.blocksSpell(true, 1, readable))
assert(model.blocksSpell(true, 0, readable))
assert(model.blocksSpell(true, nil, readable))
assert(model.blocksSpell(true, secret, readable))
assert(not model.blocksSpell(false, 0, readable))
print("Spell cooldown, global cooldown and charges: PASS")
