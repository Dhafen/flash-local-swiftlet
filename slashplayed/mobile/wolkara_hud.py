"""Make Forever's restricted unit data optional in the mobile HUD."""


def protect_hud(source):
    changes = [
        ('local function Short(value)', '''-- Check before comparing, formatting or indexing a protected value.
local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Short(value)'''),
        ('            if not icon then break end',
         '''            icon, count, duration, expiration = Public(icon), Public(count), Public(duration), Public(expiration)
            if not icon then break end'''),
        ('local level = UnitLevel(unit)', 'local level = Public(UnitLevel(unit))'),
        ('(UnitName(unit) or "")', '(Public(UnitName(unit)) or "")'),
        ('''    local health, maxHealth = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
    frame.health:SetMinMaxValues(0, math.max(1, maxHealth))
    frame.health:SetValue(health)
    local percent = maxHealth > 0 and math.floor(health * 100 / maxHealth + 0.5) or 0
    if unit == "player" then
        frame.health.text:SetText(Short(health) .. " / " .. Short(maxHealth))
    else
        frame.health.text:SetText(percent .. " %")''',
         '''    local health, maxHealth = Public(UnitHealth(unit)), Public(UnitHealthMax(unit))
    if health and maxHealth and maxHealth > 0 then
        frame.health:SetMinMaxValues(0, maxHealth)
        frame.health:SetValue(health)
        if unit == "player" then
            frame.health.text:SetText(Short(health) .. " / " .. Short(maxHealth))
        else
            frame.health.text:SetText(math.floor(health * 100 / maxHealth + 0.5) .. " %")
        end
    else
        frame.health:SetMinMaxValues(0, 1)
        frame.health:SetValue(0)
        frame.health.text:SetText("—")
    end
    if unit ~= "player" then'''),
        ('GetComboPoints("player", "target") or 0', 'Public(GetComboPoints("player", "target")) or 0'),
        ('UnitPower(unit) or 0, UnitPowerMax(unit) or 0',
         'Public(UnitPower(unit)), Public(UnitPowerMax(unit))'),
        ('    if maxPower > 0 then', '    if power and maxPower and maxPower > 0 then'),
        ('PowerBarColor[UnitPowerType(unit)]', 'PowerBarColor[Public(UnitPowerType(unit)) or -1]'),
    ]
    for before, after in changes:
        if source.count(before) != 1:
            raise ValueError(f"Unexpected Wolkara HUD source near {before.splitlines()[0]}")
        source = source.replace(before, after)
    return source


def protect_cooldowns(source):
    anchor = "    if start and duration and duration > 0 and enable ~= 0 and enable ~= false then"
    if source.count(anchor) != 1:
        raise ValueError("Unexpected Wolkara cooldown source")
    return source.replace(anchor, """    -- A nil or protected cooldown has no usable timer for this HUD.
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration) or issecretvalue(enable)) then
        start, duration, enable = nil, nil, nil
    end
""" + anchor)
