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
