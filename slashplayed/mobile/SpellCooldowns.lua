local model = {}

function model.isOwnCooldown(info, gcd, readable)
    if not info or not readable(info) then return false end
    if readable(info.isEnabled) and (info.isEnabled == false or info.isEnabled == 0) then return false end
    if readable(info.isActive) and readable(info.isOnGCD)
        and type(info.isActive) == "boolean" and type(info.isOnGCD) == "boolean" then
        return info.isActive and not info.isOnGCD
    end
    if not readable(info.startTime) or not readable(info.duration)
        or type(info.startTime) ~= "number" or type(info.duration) ~= "number"
        or info.startTime <= 0 or info.duration <= 0 then return false end
    return not (gcd and readable(gcd.startTime) and readable(gcd.duration)
        and info.startTime == gcd.startTime and info.duration == gcd.duration)
end

function model.blocksSpell(own, charges, readable)
    return own and not (readable(charges) and type(charges) == "number" and charges > 0)
end

return model
