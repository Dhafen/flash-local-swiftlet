local _, addon = ...
local rotation = addon.rotation
local modes = { "Recommended", "Manual", "Custom", "One button" }
local db, hint, panel, status, edit, modeButton
local currentSpell, currentTexture, powerBar, powerText
local defaultStatus = {
    "Tap the highlighted spell. Configure Hekili with /hekili.",
    "Your spell circles and action sets are available as configured.",
    "Order up to 12 spell IDs. The first usable, ready spell is highlighted.",
    "Assign a supported named macro to spell circle 1 on your current set.",
}

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function isReady(spell)
    local known = C_SpellBook and (C_SpellBook.IsSpellKnownOrOverridesKnown or C_SpellBook.IsSpellKnown) or IsPlayerSpell
    local isKnown = not known or known(spell)
    if not readable(isKnown) or not isKnown then return false end
    local usable = C_Spell.IsSpellUsable(spell)
    if not readable(usable) or not usable then return false end
    local range = C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(spell, "target")
    if not readable(range) or range == false then return false end
    local info = C_Spell.GetSpellCooldown(spell)
    if not info or not readable(info.startTime) or not readable(info.duration) then return false end
    if info.startTime == 0 or info.duration == 0 then return true end
    if C_Spell.GetSpellCharges then
        local charges = C_Spell.GetSpellCharges(spell)
        if charges and readable(charges.currentCharges) and charges.currentCharges > 0 then return true end
    end
    local gcd = C_Spell.GetSpellCooldown(61304)
    return gcd and readable(gcd.startTime) and readable(gcd.duration)
        and gcd.startTime == info.startTime and gcd.duration == info.duration
end

local function updateHint()
    if not db then return end
    local spell, texture
    if db.mode == 1 then
        local engine = Hekili and Hekili.Engine
        if engine and engine.Output and Hekili.DB and Hekili.DB.profile.enabled ~= false then
            spell, texture = rotation.recommended(engine.Output.Primary)
        end
    elseif db.mode == 3 then
        spell = rotation.firstReady(db.priorities, isReady)
        if spell then texture = C_Spell.GetSpellTexture(spell) end
    end
    currentSpell, currentTexture = spell, readable(texture) and texture or nil
end

-- Called by SPTouchBars once per refresh. Only visual state crosses the addon boundary.
function SPMobileCombatHint()
    updateHint()
    if db then return currentSpell, db.mode == 4 end
end

function SPMobileCombatShowHint(matched, editing)
    if not hint then return end
    local visible = not editing and (not panel:IsShown())
    hint:SetShown(visible and currentTexture ~= nil and not matched)
    if hint:IsShown() then hint.icon:SetTexture(currentTexture) end
    powerBar:SetShown(visible and db.mode ~= 2)
    if not powerBar:IsShown() then return end
    local value, maximum = UnitPower("player"), UnitPowerMax("player")
    if not readable(value) or not readable(maximum) or not maximum or maximum <= 0 then powerBar:Hide(); return end
    local _, token = UnitPowerType("player")
    local color = readable(token) and PowerBarColor and PowerBarColor[token]
    powerBar:SetStatusBarColor(color and color.r or 0.2, color and color.g or 0.7, color and color.b or 0.6)
    powerBar:SetMinMaxValues(0, maximum)
    powerBar:SetValue(value or 0)
    powerText:SetFormattedText("%d / %d", value or 0, maximum)
end

local function button(parent, title, w, h, point, anchor, relative, x, y, callback)
    local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    frame:SetSize(w, h)
    frame:SetPoint(point, anchor, relative, x, y)
    frame:SetText(title)
    frame:SetScript("OnClick", callback)
    return frame
end

local function syncPanel()
    modeButton:SetText(modes[db.mode])
    status:SetText(defaultStatus[db.mode])
    edit:SetText(table.concat(db.priorities, ", "))
end

local function selectMode(mode)
    if not db then return end
    db.mode = mode
    syncPanel()
end

local function togglePanel()
    if not db then return end
    if panel:IsShown() then panel:Hide(); return end
    syncPanel()
    panel:Show()
end

local function createUI()
    local toolbar = addon.createMenu(togglePanel)

    powerBar = CreateFrame("StatusBar", nil, UIParent)
    powerBar:SetSize(118, 14)
    powerBar:SetPoint("BOTTOMLEFT", toolbar, "TOPLEFT", 0, 5)
    powerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    powerBar:EnableMouse(false)
    powerText = powerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerText:SetPoint("CENTER")
    powerBar:Hide()

    hint = CreateFrame("Frame", nil, UIParent)
    hint:SetSize(44, 44)
    hint:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -108, 74)
    hint:EnableMouse(false)
    hint.icon = hint:CreateTexture(nil, "ARTWORK")
    hint.icon:SetAllPoints()
    hint:Hide()

    panel = CreateFrame("Frame", "SPMobileCombatPanel", UIParent, "BackdropTemplate")
    panel:SetSize(370, 220)
    panel:SetPoint("CENTER")
    panel:SetScript("OnShow", function(self)
        self:SetScale(math.max(0.1, math.min(1, (UIParent:GetWidth() - 16) / 370, (UIParent:GetHeight() - 16) / 220)))
    end)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    panel:SetBackdropColor(0.05, 0.08, 0.11, 0.98)
    tinsert(UISpecialFrames, panel:GetName())
    panel:Hide()
    modeButton = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    modeButton:SetPoint("TOP", 0, -12)
    button(panel, "Close", 62, 36, "TOPRIGHT", panel, "TOPRIGHT", -6, -4, function() panel:Hide() end)
    for index, mode in ipairs(modes) do
        local selected = index
        button(panel, mode, 88, 42, "TOPLEFT", panel, "TOPLEFT", 6 + (index - 1) * 90, -48,
               function() selectMode(selected) end)
    end
    status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOP", 0, -101)
    status:SetWidth(346)
    edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetSize(246, 40)
    edit:SetPoint("BOTTOMLEFT", 14, 12)
    edit:SetMaxLetters(150)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function save()
        local priorities = rotation.parse(edit:GetText())
        if not priorities then status:SetText("Enter up to 12 positive spell IDs, separated by commas."); return end
        db.priorities = priorities
        edit:ClearFocus()
        selectMode(3)
    end
    edit:SetScript("OnEnterPressed", save)
    button(panel, "Save IDs", 86, 42, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12, save)
    panel:SetScript("OnHide", function() edit:ClearFocus() end)
    button(panel, "Toggle phone wheel", 176, 36, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 60, function()
        if InCombatLockdown() then status:SetText("Finish combat before changing the wheel layout."); return end
        if not SPTouchBarsTogglePhoneArc then return end
        status:SetText(SPTouchBarsTogglePhoneArc() and "Phone wheel enabled." or "Saved layout restored.")
    end)
    button(panel, "Edit spell layout", 145, 36, "BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 60, function()
        if InCombatLockdown() then status:SetText("Finish combat before editing your spell layout."); return end
        panel:Hide()
        if SlashCmdList.SPTOUCHBARS then SlashCmdList.SPTOUCHBARS("") end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if type(SPMobileCombatDB) ~= "table" then SPMobileCombatDB = {} end
    db = SPMobileCombatDB
    if not modes[db.mode] then db.mode = 1 end
    if type(db.priorities) ~= "table" then db.priorities = {} end
    createUI()
    addon.fitWindows()
    events:UnregisterEvent("PLAYER_LOGIN")
end)

SLASH_SPMOBILECOMBAT1 = "/spcombat"
SlashCmdList.SPMOBILECOMBAT = togglePanel
