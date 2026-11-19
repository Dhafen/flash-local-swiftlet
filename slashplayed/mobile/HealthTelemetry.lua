-- Read only public numerical health data. Do not inspect protected values.
local function spReadHealthPercent(unit)
    local restricted = false
    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if not ok then return nil end
        if type(issecretvalue) == "function" and issecretvalue(value) then
            restricted = true
            return nil
        end
        if type(canaccessvalue) == "function" and not canaccessvalue(value) then
            restricted = true
            return nil
        end
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            return nil
        end
        return value
    end
    local function result(p)
        return math.floor(p * 100 + 0.5)
    end
    -- Modern public API returns a normalized 0..1 fraction without a curve.
    local percent = read(UnitHealthPercent, unit)
    if percent ~= nil and percent >= 0 and percent <= 1 then
        return result(percent)
    end
    -- Fallback for clients exposing unprotected absolute health values.
    local current = read(UnitHealth, unit)
    local capacity = read(UnitHealthMax, unit)
    if current ~= nil and capacity ~= nil and capacity > 0 and current >= 0 and current <= capacity then
        return result(current / capacity)
    end
    if restricted then return nil, "restricted" end
    return nil, "unavailable"
end

-- Health is optional. All decision flags must be public and known.
-- 255 is an explicit unknown sentinel, never a fabricated percentage.
local function spAIState()
    if not SPPhoneTouchRects then return "" end
    local stage = 1
    local function unavailable(code) return string.char(65, 73, 0, code, 0, 0) end
    local function boolValue(value)
        if type(issecretvalue) == "function" and issecretvalue(value) then error("restricted value") end
        if type(canaccessvalue) == "function" and not canaccessvalue(value) then error("restricted value") end
        if value == nil then return false end
        if type(value) == "boolean" then return value end
        if type(value) == "number" and (value == 0 or value == 1) then return value == 1 end
        error("unexpected boolean")
    end
    local function dead(unit)
        if type(UnitIsDeadOrGhost) == "function" then return boolValue(UnitIsDeadOrGhost(unit)) end
        if type(UnitIsDead) == "function" and type(UnitIsGhost) == "function" then
            return boolValue(UnitIsDead(unit)) or boolValue(UnitIsGhost(unit))
        end
        error("death API unavailable")
    end
    local ok, state = pcall(function()
        if not boolValue(UnitExists("player")) then return unavailable(1) end
        local flags = 1
        stage = 4
        if dead("player") then flags = flags + 2 end
        stage = 5
        local hasTarget = boolValue(UnitExists("target"))
        if hasTarget then
            flags = flags + 4
            stage = 6
            if boolValue(UnitCanAttack("player", "target")) and not boolValue(UnitIsPlayer("target")) then flags = flags + 8 end
            stage = 7
            if dead("target") then flags = flags + 16 end
        end
        stage = 9
        if boolValue(UnitAffectingCombat("player")) then flags = flags + 32 end
        stage = 10
        if type(IsMounted) ~= "function" then return unavailable(10) end
        if boolValue(IsMounted()) then flags = flags + 64 end
        stage = 11
        local hp = spReadHealthPercent("player") or 255
        local targetHP = hasTarget and (spReadHealthPercent("target") or 255) or 0
        return string.char(65, 73, flags, hp, targetHP, math.floor(GetTime() / 2) % 256)
    end)
    if not ok then return unavailable(stage) end
    return state
end
