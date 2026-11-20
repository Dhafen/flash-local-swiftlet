local path = assert(arg[1])
local f = assert(io.open(path, "r"))
local source = f:read("*a")
f:close()
local read = assert(loadstring(source .. "\nreturn spReadHealthPercent"))()
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
assert(#packet == 6 and packet:byte(3) == 45 and packet:byte(4) == 255 and packet:byte(5) == 255)
UnitCanAttack = val(secret)
packet = state()
assert(packet:byte(3) == 0 and packet:byte(4) == 6)
UnitCanAttack = val(true)
UnitExists = function(unit) return unit == "player" end
packet = state()
assert(packet:byte(3) == 33 and packet:byte(4) == 255 and packet:byte(5) == 0)
reset(val(.2), nil, nil)
packet = state()
assert(packet:byte(4) == 20)
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
