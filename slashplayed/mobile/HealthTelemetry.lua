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

local function spAIReadable(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
        and not (type(canaccessvalue) == "function" and not canaccessvalue(value))
end

local function spAIBinding(key)
    if type(GetBindingAction) ~= "function" then return nil end
    local ok, value = pcall(GetBindingAction, key, true)
    if ok and spAIReadable(value) and type(value) == "string" then return value end
end

local function spAITargetColumn()
    local ok, column = pcall(function()
        if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        if not spAIReadable(plate) or not plate or not plate.IsForbidden or plate:IsForbidden() then return end
        local visible = plate:IsVisible()
        if not spAIReadable(visible) or not visible then return end
        local x = plate:GetCenter()
        local width = UIParent:GetWidth()
        if not spAIReadable(x) or not spAIReadable(width)
            or type(x) ~= "number" or type(width) ~= "number" or not (width > 0)
            or not (x >= 0 and x <= width) then return end
        return math.floor(0.5 + 14 * x / width) + 1
    end)
    return ok and column or 0
end

local function spAITargetIdentity()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, value = pcall(UnitGUID, "target")
    if ok and spAIReadable(value) and type(value) == "string" and value ~= "" then return value end
end

local spAICombatTarget
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
        local hostile, targetDead, foeID = false, false, nil
        local hasTarget = boolValue(UnitExists("target"))
        if hasTarget then
            flags = flags + 4
            stage = 6
            local npc = not boolValue(UnitIsPlayer("target"))
            hostile = npc and boolValue(UnitCanAttack("player", "target"))
            if hostile then flags = flags + 8 end
            stage = 7
            targetDead = dead("target")
            if targetDead then flags = flags + 16 end
            if npc then foeID = spAITargetIdentity() end
        end
        stage = 9
        local combat = boolValue(UnitAffectingCombat("player"))
        if combat then flags = flags + 32 end
        if not hasTarget or (not targetDead and not hostile) then spAICombatTarget = nil
        elseif not targetDead then
            if combat then spAICombatTarget = foeID
            elseif spAICombatTarget ~= foeID then spAICombatTarget = nil end
        elseif foeID and foeID == spAICombatTarget then flags = flags + 128 end
        stage = 10
        if type(IsMounted) ~= "function" then return unavailable(10) end
        if boolValue(IsMounted()) then flags = flags + 64 end
        stage = 11
        local hp = spReadHealthPercent("player") or 255
        local targetHP = hasTarget and (spReadHealthPercent("target") or 255) or 0
        local meta = 128
        local rotation = spAIBinding("F12")
        if rotation then meta = meta + (rotation == "CLICK TactaraMainButton:LeftButton" and 1 or 2) end
        -- With bit 2 set, bit 0 selects F (set) or F10 (clear).
        local f = spAIBinding("F") == "INTERACTTARGET"
        if f or spAIBinding("F10") == "INTERACTTARGET" then
            meta = meta - (meta % 2) + (f and 5 or 4)
        end
        if hostile and not targetDead then meta = meta + 8 * spAITargetColumn() end
        return string.char(65, 73, flags, hp, targetHP, meta)
    end)
    if not ok then spAICombatTarget = nil; return unavailable(stage) end
    return state
end
