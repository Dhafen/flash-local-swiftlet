local path = assert(arg[1])
local f = assert(io.open(path, "r"))
local source = f:read("*a")
f:close()
local read, playerPose = assert(loadstring(source .. "\nreturn spReadHealthPercent, spAIPlayerPose"))()
local secret = {}
issecretvalue = function(value) return value == secret end
canaccessvalue = function(value) return value ~= secret end
local function reset(p, h, m)
    UnitHealthPercent = p
    UnitHealth = h
    UnitHealthMax = m
end
local function val(v) return function() return v end end
local function check(expected, errorCode)
    local actual, why = read("player")
    assert(actual == expected, tostring(actual) .. " expected " .. tostring(expected))
    assert(why == errorCode, tostring(why) .. " expected " .. tostring(errorCode))
end
reset(val(.625), val(secret), val(secret)); check(63)
reset(val(0), nil, nil); check(0)
reset(val(1), nil, nil); check(100)
reset(nil, val(42), val(60)); check(70)
reset(val(secret), val(secret), val(100)); check(nil, "restricted")
reset(val(secret), val(50), val(secret)); check(nil, "restricted")
reset(val(5), val(0), val(0)); check(nil, "unavailable")
reset(function() error("API unavailable") end, val(80), val(100)); check(80)
reset(val(0/0), val(-1), val(100)); check(nil, "unavailable")
issecretvalue = nil
reset(val(secret), val(secret), val(100)); check(nil, "restricted")
print("health telemetry tests passed")
GetPlayerFacing = val(math.pi / 2)
local pose = assert(playerPose(-1.25, 2, 0, 7))
local expected = string.char(65, 80, 1, 3, 0, 0, 0, 0, 255, 255, 255, 251, 0, 0, 0, 8, 64, 7)
assert(pose == expected, "signed position, map zero and heading must survive encoding")
GetPlayerFacing = val(secret)
-- Retain coordinates if only the heading is restricted.
issecretvalue = function(value) return value == secret end
assert(assert(playerPose(0, 0, 1, 7)):byte(4) == 1)
assert(playerPose(secret, 0, 1, 7) == nil)
assert(playerPose(0, 0, 0, 0) == nil)

-- Flags must survive protected health but protected attackability must fail closed.
local state = assert(loadstring(source .. "\nreturn spAIState"))()
SPPhoneTouchRects = true
issecretvalue = function(value) return value == secret end
canaccessvalue = function(value) return value ~= secret end
UnitExists = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitCanAttack = function() return true end
UnitIsPlayer = function() return false end
UnitAffectingCombat = function() return true end
IsMounted = function() return false end
GetTime = function() return 2 end
reset(val(secret), val(secret), val(secret))
local packet = state()
assert(#packet == 18 and packet:byte(3) == 45 and packet:byte(4) == 255 and packet:byte(5) == 255)
assert(packet:byte(18) == 64 + 2 * 4 + 2 * 16, "report restricted player and target independently")
UnitCanAttack = val(secret)
packet = state()
assert(packet:byte(3) == 0 and packet:byte(4) == 6)
UnitCanAttack = val(true)
UnitExists = function(unit) return unit == "player" end
packet = state()
assert(packet:byte(3) == 33 and packet:byte(4) == 255 and packet:byte(5) == 0)
assert(packet:byte(18) == 64 + 2 * 4 + 3 * 16, "target absent is distinct from restricted")
reset(val(.2), nil, nil)
packet = state()
assert(packet:byte(4) == 20)
assert(packet:byte(18) == 64 + 3 * 16)
reset(nil, nil, nil)
assert(state():byte(18) == 64 + 1 * 4 + 3 * 16, "missing and restricted are distinct")
print("partial public game-state tests passed")

GetBindingAction = function(key, checkOverride)
    assert(checkOverride)
    if key == "F12" then return "CLICK TactaraMainButton:LeftButton" end
end
assert(state():byte(6)==129)
GetBindingAction = val("JUMP"); assert(state():byte(6)==130)
GetBindingAction = val(secret); assert(state():byte(6)==128)
GetBindingAction = nil; assert(state():byte(6)==128)
print("public F12 binding checks passed")

UnitExists = val(true)
UnitCanAttack = val(true)
UnitAffectingCombat = val(true)
UnitGUID = val("test-foe-A")
local targetDead = false
UnitIsDeadOrGhost = function(unit) return unit == "target" and targetDead end
local x = 100
local forbidden = false
local p = {
    IsForbidden = function() return forbidden end,
    IsVisible = val(true),
    GetCenter = function() return x, 60 end
}
UIParent = { GetWidth = val(200) }
C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        assert(unit == "target")
        return p
    end
}
GetBindingAction = function(key) if key == "F" then return "INTERACTTARGET" end end
reset(val(.9), nil, nil)
assert(state():byte(6) == 133 + 8 * 8)
x = secret
assert(state():byte(6) == 133)
x = 180
forbidden = true
assert(state():byte(6) == 133)
forbidden = false
assert(state():byte(6) > 133)
targetDead = true
UnitAffectingCombat = val(false)
UnitCanAttack = val(false)
assert(state():byte(3) == 149)
assert(state():byte(6) == 133)
GetBindingAction = function(key) if key == "F10" then return "INTERACTTARGET" end end
assert(state():byte(6) == 132)
UnitGUID = val("test-foe-B")
assert(state():byte(3) == 21)
UnitGUID = val(secret)
assert(state():byte(3) == 21)
print("public target columns and same-corpse checks passed")

targetDead = false
UnitCanAttack = val(true)
UnitGUID = val("test-foe-C")
C_NamePlate.GetNamePlateForUnit = function(unit)
    if unit == "target" then error("client requires a nameplate unit token") end
    if unit == "nameplate7" then return p end
end
UnitIsUnit = function(unit, target)
    assert(target == "target")
    if unit == "nameplate1" then return secret end
    return unit == "nameplate7"
end
assert(state():byte(6) > 132)
UnitIsUnit = val(secret)
assert(state():byte(6) == 132)
print("nameplate unit token fallback passed")

GetBindingAction = function(key, override)
    assert(override)
    local keys = { W = "MOVEFORWARD", S = secret, Q = "TURNLEFT", A = "STRAFELEFT", E = "STRAFERIGHT", D = "STRAFERIGHT" }
    return keys[key]
end
local bound = state()
assert(bound:byte(7) == 75 and bound:byte(8) == 1 + 8 + 16)
GetBindingAction = val(secret)
assert(state():byte(8) == 0)
print("public keyboard movement bindings passed")

local motionX = 1
UnitPosition = function() return motionX, 2, 3, 4 end
local stationary = state()
assert(stationary:byte(9) == 70 and stationary:byte(10) == 1)
assert(state():byte(11) == stationary:byte(11))
motionX = 2
assert(state():byte(11) ~= stationary:byte(11))
UnitPosition = val(secret)
GetUnitSpeed = val(4)
local moving = state()
assert(moving:byte(10) == 2 and state():byte(11) ~= moving:byte(11))
GetUnitSpeed = val(secret)
assert(state():byte(10) == 0)

local map, targetX, targetMap = 4, 11, 4
UnitPosition = function(unit)
    if unit == "target" then return targetX, 2, 3, targetMap end
    return motionX, 2, 3, map
end
GetBindingAction = function(key)
    if key == "TAB" then return "TARGETNEARESTENEMY" end
    if key == "F12" then return "CLICK TactaraMainButton:LeftButton" end
    if key == "F" then return "INTERACTTARGET" end
end
local nav = state()
assert(nav:byte(13) == 78 and nav:byte(14) ~= 0 and nav:byte(15) ~= 0)
assert(nav:byte(16) == 0 and nav:byte(17) == 36 and nav:byte(18) % 4 == 3)
targetX = secret
assert(state():byte(17) == 255)
targetX, targetMap = 11, 5
assert(state():byte(17) == 255)
map = 5
assert(state():byte(15) ~= nav:byte(15))
nav = state()
motionX = 80
assert(state():byte(15) ~= nav:byte(15))
UnitGUID = val("new-selected-target")
assert(state():byte(14) ~= nav:byte(14))
UnitGUID = val(secret)
assert(state():byte(14) == 0 and state():byte(17) == 255)

local lootEvent, lootState = assert(loadstring(source .. "\nreturn spAILootEvent, spAIState"))()
targetDead = false
UnitAffectingCombat = val(true)
UnitCanAttack = val(true)
UnitGUID = val("test-foe-loot")
lootState()
targetDead = true
UnitAffectingCombat = val(false)
UnitCanAttack = val(false)
assert(lootState():byte(12) == 0)
GetNumLootItems = val(1)
GetLootSourceInfo = function() return "another-foe", 1 end
lootEvent(nil, "LOOT_OPENED")
lootEvent(nil, "LOOT_SLOT_CLEARED", 1)
assert(lootState():byte(12) == 0)
GetLootSourceInfo = function() return "test-foe-loot", 1 end
lootEvent(nil, "LOOT_OPENED")
lootEvent(nil, "LOOT_CLOSED")
assert(lootState():byte(12) == 0)
lootEvent(nil, "LOOT_OPENED")
lootEvent(nil, "LOOT_SLOT_CLEARED", 1)
assert(lootState():byte(12) == 1)
UnitGUID = val("another-foe")
assert(lootState():byte(12) == 0)
print("movement and matched corpse loot feedback passed")

local corpseEvent, corpseState = assert(loadstring(source .. "\nreturn spAILootEvent, spAIState"))()
local selected = "test-corpse"
UnitGUID = function(unit)
    if unit == "player" then return "test-player" end
    if unit == "pet" then return "test-pet" end
    return selected
end
UnitIsInInteractRange = val(false)
UnitHasLootInteraction = val(true)
corpseEvent(nil, "PARTY_KILL", "other-player", selected)
assert(corpseState():byte(3) == 21)
corpseEvent(nil, "PARTY_KILL", secret, selected)
assert(corpseState():byte(3) == 21)
corpseEvent(nil, "PARTY_KILL", "test-player", "other-corpse")
assert(corpseState():byte(3) == 21)
corpseEvent(nil, "PARTY_KILL", "test-player", selected)
local corpse = corpseState()
assert(corpse:byte(3) == 149 and corpse:byte(12) == 2 + 8 + 16)
UnitIsInInteractRange = val(secret)
UnitHasLootInteraction = val(false)
assert(corpseState():byte(12) == 2 + 4)
GetLootSourceInfo = function() return selected, 1 end
corpseEvent(nil, "LOOT_OPENED")
corpseEvent(nil, "LOOT_SLOT_CLEARED", 1)
assert(corpseState():byte(12) == 1 + 2 + 4)
corpseEvent(nil, "PLAYER_TARGET_CHANGED")
local reselected = corpseState()
assert(reselected:byte(3) == 21 and reselected:byte(14) ~= corpse:byte(14))
selected = "pet-corpse"
corpseEvent(nil, "PARTY_KILL", "test-pet", selected)
assert(corpseState():byte(3) == 149)
GetTime = val(15)
assert(corpseState():byte(3) == 149, "observed selected corpse remains eligible out of range")
corpseEvent(nil, "PLAYER_TARGET_CHANGED")
selected = "never-observed-corpse"
corpseEvent(nil, "PARTY_KILL", "test-player", selected)
GetTime = val(28)
assert(corpseState():byte(3) == 21)
print("public kill attribution and corpse interaction evidence passed")
