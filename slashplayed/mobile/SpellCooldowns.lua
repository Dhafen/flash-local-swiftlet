local model = {}

function model.isOwnCooldown(info, gcd, readable)
    if not info or not readable(info.startTime) or not readable(info.duration)
        or not readable(info.isEnabled) or info.isEnabled == false or info.isEnabled == 0
        or type(info.startTime) ~= "number" or type(info.duration) ~= "number"
        or info.startTime <= 0 or info.duration <= 0 then return false end
    return not (gcd and readable(gcd.startTime) and readable(gcd.duration)
        and info.startTime == gcd.startTime and info.duration == gcd.duration)
end

function model.blocksSpell(own, charges, readable)
    return own and not (readable(charges) and type(charges) == "number" and charges > 0)
end

return model
