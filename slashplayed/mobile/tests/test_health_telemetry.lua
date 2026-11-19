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
