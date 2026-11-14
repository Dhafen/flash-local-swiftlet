local function cooldown(button, spell, item, charges)
    button.globalCooldown:Clear()
    button.chargeCooldown:Clear()
    if spell then
        local gcd = C_Spell.GetSpellCooldown(61304)
        local info = C_Spell.GetSpellCooldown(spell)
        local own = model.isOwnCooldown(info, gcd, readable)
        local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spell, true)
        if duration and button.cooldown.SetCooldownFromDurationObject then
            button.cooldown:SetCooldownFromDurationObject(duration)
        elseif own then
            readableCooldown(button.cooldown, info)
        else
            button.cooldown:Clear()
        end
        local charge = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spell)
        if charge and button.chargeCooldown.SetCooldownFromDurationObject then
            button.chargeCooldown:SetCooldownFromDurationObject(charge)
        end
        -- The secondary overlay never displays text. Prefer the client's
        -- explicit GCD flag and compare only public timestamps as a fallback.
        local onGCD = info and info.isOnGCD
        if (readable(onGCD) and onGCD == true) or (not own and info and gcd
            and readable(info.startTime) and readable(info.duration)
            and readable(gcd.startTime) and readable(gcd.duration)
            and info.startTime == gcd.startTime and info.duration == gcd.duration) then
            readableCooldown(button.globalCooldown, gcd)
        end
        return model.blocksSpell(own, charges, readable)
    elseif item then
        local start, length, enabled = C_Container.GetItemCooldown(item)
        local info = { startTime = start, duration = length, isEnabled = enabled }
        readableCooldown(button.cooldown, info)
        return model.isOwnCooldown(info, nil, readable)
    end
    button.cooldown:Clear()
    return false
end
