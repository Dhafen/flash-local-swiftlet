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

local function spAIHealthStatus(hp, reason)
    if hp ~= nil then return 0 end
    return reason == "restricted" and 2 or 1
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

local function spAIMovementBindings()
    -- Only advertise bindings explicitly confirmed by the client.
    local bits = 0
    if spAIBinding("W") == "MOVEFORWARD" then bits = bits + 1 end
    if spAIBinding("S") == "MOVEBACKWARD" then bits = bits + 2 end
    if spAIBinding("Q") == "STRAFELEFT" then bits = bits + 4
    elseif spAIBinding("A") == "STRAFELEFT" then bits = bits + 8 end
    if spAIBinding("E") == "STRAFERIGHT" then bits = bits + 16
    elseif spAIBinding("D") == "STRAFERIGHT" then bits = bits + 32 end
    return bits
end

local function spAITargetColumn()
    local ok, column = pcall(function()
        if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
        local directOK, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if not directOK then plate = nil end
        if not spAIReadable(plate) then return end
        -- Some clients only return a frame for its nameplate unit token.
        if not plate and type(UnitIsUnit) == "function" then
            for i = 1, 40 do
                local token = "nameplate" .. i
                local match = UnitIsUnit(token, "target")
                if spAIReadable(match) and (match == true or match == 1) then
                    plate = C_NamePlate.GetNamePlateForUnit(token)
                    break
                end
            end
        end
        if not spAIReadable(plate) or not plate or not plate.IsForbidden then return end
        local forbidden = plate:IsForbidden()
        if not spAIReadable(forbidden) or forbidden then return end
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

local spAICombatTarget, spAILootedTarget
local spAILootSlots = {}
-- Track only a slot whose entire reported source is the selected corpse.
-- A closed loot window by itself carries no success signal.
local function spAILootEvent(_, event, slot)
    if event == "LOOT_CLOSED" then spAILootSlots = {}; return end
    if event == "LOOT_SLOT_CLEARED" then
        if not spAIReadable(slot) or type(slot) ~= "number" then return end
        local source = spAILootSlots[slot]
        if source and source == spAICombatTarget then spAILootedTarget = source end
        spAILootSlots[slot] = nil
        return
    end
    spAILootSlots = {}
    local target = spAITargetIdentity()
    if not target or target ~= spAICombatTarget or type(GetNumLootItems) ~= "function"
        or type(GetLootSourceInfo) ~= "function" then return end
    local count = GetNumLootItems()
    if not spAIReadable(count) or type(count) ~= "number" then return end
    local function soleSource(guid, quantity, ...)
        return select("#", ...) == 0 and spAIReadable(guid) and type(guid) == "string" and guid == target
            and spAIReadable(quantity) and type(quantity) == "number" and quantity > 0
    end
    for i = 1, math.min(count, 100) do
        if soleSource(GetLootSourceInfo(i)) then spAILootSlots[i] = target end
    end
end

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    for _, event in ipairs({"LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED"}) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(...) pcall(spAILootEvent, ...) end)
end

local spAIMotionCounter, spAIMotionSource, spAIPositionEpoch = 0, 0, 0
local spAIAnchorX, spAIAnchorY, spAIAnchorMap
local spAIPreviousTarget, spAITargetEpoch = nil, 0
local function spAIFinite(value)
    return spAIReadable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function spAIPosition(unit)
    if type(UnitPosition) ~= "function" then return end
    local ok, x, y, _, map = pcall(UnitPosition, unit)
    if ok and spAIFinite(x) and spAIFinite(y) and spAIFinite(map) then return x, y, map end
end

local function spAIMotion(foeID)
    local source = 0
    local distance = 65535
    local x, y, map = spAIPosition("player")
    if map then
        source = 1
        if spAIAnchorMap ~= map then
            spAIPositionEpoch = spAIPositionEpoch % 255 + 1
            spAIAnchorX, spAIAnchorY, spAIAnchorMap = x, y, map
        else
            local dx, dy = x-spAIAnchorX, y-spAIAnchorY
            local displacement = dx*dx + dy*dy
            if displacement > 900 then
                spAIPositionEpoch = spAIPositionEpoch % 255 + 1
            elseif displacement >= 0.25 then
                spAIMotionCounter = (spAIMotionCounter + 1) % 256
            end
            if displacement >= 0.25 then spAIAnchorX, spAIAnchorY = x, y end
        end
        if foeID then
            local tx, ty, targetMap = spAIPosition("target")
            if map == targetMap then
                local dx, dy = x-tx, y-ty
                distance = math.min(65534, math.floor(4 * math.sqrt(dx*dx + dy*dy) + 0.5))
            end
        end
    end
    if source == 0 then
        spAIAnchorX, spAIAnchorY, spAIAnchorMap = nil, nil, nil
        if type(GetUnitSpeed) == "function" then
            local ok, speed = pcall(GetUnitSpeed, "player")
            if ok and spAIFinite(speed) then
                source = 2
                if spAIMotionSource == source and speed > 0.1 then
                    spAIMotionCounter = (spAIMotionCounter + 1) % 256
                end
            end
        end
    end
    spAIMotionSource = source
    return source, spAIMotionCounter, source == 1 and spAIPositionEpoch or 0, distance
end

-- Health is optional. All decision flags must be public and known.
-- 255 is an explicit unknown sentinel, never a fabricated percentage.
local function spAIState()
    if not SPPhoneTouchRects then return "" end
    local stage = 1
    local function unavailable(code) return string.char(65, 73, 0, code, 0, 0, 75, 0, 70, 0, 0, 0, 78, 0, 0, 255, 255, 0) end
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
        local hp, hpReason = spReadHealthPercent("player")
        local targetHP, targetHealth = 0, 3
        if hasTarget then
            local value, reason = spReadHealthPercent("target")
            targetHealth = spAIHealthStatus(value, reason)
            targetHP = value or 255
        end
        local meta = 128
        local rotation = spAIBinding("F12")
        if rotation then meta = meta + (rotation == "CLICK TactaraMainButton:LeftButton" and 1 or 2) end
        -- With bit 2 set, bit 0 selects F (set) or F10 (clear).
        local f = spAIBinding("F") == "INTERACTTARGET"
        if f or spAIBinding("F10") == "INTERACTTARGET" then
            meta = meta - (meta % 2) + (f and 5 or 4)
        end
        if hostile and not targetDead then meta = meta + 8 * spAITargetColumn() end
        if not targetDead and foeID == spAILootedTarget then spAILootedTarget = nil end
        if foeID ~= spAIPreviousTarget then
            spAITargetEpoch = spAITargetEpoch % 255 + 1
            spAIPreviousTarget = foeID
        end
        local motionSource, motionCounter, positionEpoch, distance = spAIMotion(foeID)
        local bindings = (spAIBinding("TAB") == "TARGETNEARESTENEMY" and 1 or 0)
            + (rotation == "CLICK TactaraMainButton:LeftButton" and 2 or 0)
        local looted = targetDead and foeID and foeID == spAILootedTarget and 1 or 0
        local healthStatus = 64 + spAIHealthStatus(hp, hpReason) * 4 + targetHealth * 16
        return string.char(65, 73, flags, hp or 255, targetHP, meta, 75, spAIMovementBindings(),
            70, motionSource, motionCounter, looted, 78, foeID and spAITargetEpoch or 0, positionEpoch,
            math.floor(distance / 256), distance % 256, bindings + healthStatus)
    end)
    if not ok then spAICombatTarget = nil; spAIPreviousTarget = nil; return unavailable(stage) end
    return state
end
