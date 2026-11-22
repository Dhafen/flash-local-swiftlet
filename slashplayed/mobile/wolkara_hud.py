"""Keep Forever unit health visible with native display-only setters."""
from pathlib import Path

HEALTH_DISPLAY = Path(__file__).with_name("HealthDisplay.lua").read_text(encoding="utf-8").strip()


def publish_applied_layout(source):
    original = '''        if type(saved) == "table" and saved.point then
            self:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
        else
            local d = type(default) == "function" and default() or default
            self:SetPoint(d[1], UIParent, d[2] or d[1], d[3] or 0, d[4] or 0)
        end'''
    if source.count(original) != 1:
        raise ValueError("Unexpected Wolkara PlaceSaved source")
    return source.replace(original, '''        local point, relativePoint, x, y
        if type(saved) == "table" and saved.point then
            point, relativePoint, x, y = saved.point, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0
        else
            local d = type(default) == "function" and default() or default
            point, relativePoint, x, y = d[1], d[2] or d[1], d[3] or 0, d[4] or 0
        end
        self:SetPoint(point, UIParent, relativePoint, x, y)
        return point, relativePoint, x, y''')


def protect_hud(source):
    changes = [
        ('local player, target', '''local player, target, healthGeometry
local PLAYER_WIDTH, PLAYER_HEIGHT, PLAYER_PORTRAIT_WIDTH, HEALTH_HEIGHT = 366, 66, 66, 24
local HEALTH_GUTTER = 6

local function placeHealthBar(bar, owner, left, inset)
    bar:SetPoint("TOPLEFT", owner, "TOPLEFT", left + inset, -20)
    bar:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -inset, -20)
end

local function markHealthBarEdge(bar, side, opposite, r, g)
    local edge = bar:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOP" .. opposite, bar, "TOP" .. side)
    edge:SetPoint("BOTTOM" .. opposite, bar, "BOTTOM" .. side)
    edge:SetWidth(HEALTH_GUTTER)
    edge:SetColorTexture(r, g, 1, 1)
end'''),
        ('frame:SetSize(width, unit == "player" and 66 or 58)',
         'frame:SetSize(width, unit == "player" and PLAYER_HEIGHT or 58)'),
        ('        left = 66', '        left = PLAYER_PORTRAIT_WIDTH'),
        ('local function Bar(parent, height, r, g, b)', 'local function Bar(parent, height, r, g, b, solidTrack)'),
        ('    ns.Box(bar, "BACKGROUND", 0, 0, 0, 0.55)',
         '    ns.Box(bar, "BACKGROUND", 0, 0, 0, solidTrack and 1 or 0.55)'),
        ('''    frame.health = Bar(frame, 24, 0.15, 0.75, 0.2)
    frame.health:SetPoint("TOPLEFT", 4 + left, -20)
    frame.health:SetPoint("TOPRIGHT", -4, -20)''',
         '''    frame.health = Bar(frame, HEALTH_HEIGHT, 0.15, 0.75, 0.2, unit == "player")
    placeHealthBar(frame.health, frame, left, unit == "player" and HEALTH_GUTTER or 4)
    if unit == "player" then
        markHealthBarEdge(frame.health, "LEFT", "RIGHT", 1, 0)
        markHealthBarEdge(frame.health, "RIGHT", "LEFT", 0, 1)
    end'''),
        ('''    player = Unit("WolkaraMobilePlayer", "player", 366, { "TOPLEFT", "TOPLEFT", 12, -10 })''',
         '''    player = Unit("WolkaraMobilePlayer", "player", PLAYER_WIDTH, { "TOPLEFT", "TOPLEFT", 12, -10 })
    -- This empty frame tracks only our layout. Its anchors never depend on the secure player button.
    healthGeometry = CreateFrame("Frame", "WolkaraMobileHealthGeometry", UIParent)
    healthGeometry:SetSize(PLAYER_WIDTH, PLAYER_HEIGHT)
    healthGeometry:SetClampedToScreen(true)
    healthGeometry:Hide()
    healthGeometry.crop = CreateFrame("Frame", nil, healthGeometry)
    healthGeometry.crop:SetHeight(HEALTH_HEIGHT)
    placeHealthBar(healthGeometry.crop, healthGeometry, PLAYER_PORTRAIT_WIDTH, 0)'''),
        ('''    for _, frame in ipairs({ player, target }) do
        frame:SetScale(scale)
        frame:PlaceSaved()
    end
    if on then player:Show() else player:Hide() end''',
         '''    healthGeometry:Hide()
    if InCombatLockdown() then return end
    player:SetScale(scale)
    local point, relativePoint, x, y = player:PlaceSaved()
    target:SetScale(scale)
    target:PlaceSaved()
    if on then player:Show() else player:Hide() end
    if on and not ns.editing and point then
        healthGeometry:SetScale(scale)
        healthGeometry:ClearAllPoints()
        healthGeometry:SetPoint(point, UIParent, relativePoint, x, y)
        healthGeometry:Show()
    end'''),
        ('''function Hud:SetEditing(on)
    player.glow:SetShown(on)''',
         '''function Hud:SetEditing(on)
    if on then healthGeometry:Hide() end
    player.glow:SetShown(on)'''),
        ('local function Short(value)', '''-- Check before comparing, formatting or indexing a protected value.
local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

''' + HEALTH_DISPLAY + '''

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
         '''    local rawHealth, rawMaxHealth = UnitHealth(unit), UnitHealthMax(unit)
    local health, maxHealth = Public(rawHealth), Public(rawMaxHealth)
    if health and maxHealth and maxHealth > 0 then
        spDisplayHealth(frame.health, health, maxHealth)
        if unit == "player" then
            frame.health.text:SetText(Short(health) .. " / " .. Short(maxHealth))
        else
            frame.health.text:SetText(math.floor(health * 100 / maxHealth + 0.5) .. " %")
        end
    else
        -- Native widgets may display protected values without inspecting them.
        local shown = spDisplayHealth(frame.health, rawHealth, rawMaxHealth)
        frame.health.text:SetText(shown and "" or "—")
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
