local _, addon = ...
local menu
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function icon(name) return "Interface\\Icons\\" .. name end

local function call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return false end
    fn(...)
    return true
end

local function panel(name)
    local frame = _G[name]
    if not frame then return false end
    if frame:IsShown() then HideUIPanel(frame) else ShowUIPanel(frame) end
    return true
end

local function tab(name, fallback)
    if not call(name) then panel(fallback) end
end

local function tile(parent, label, art, action)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropColor(0.10, 0.14, 0.19, 1)
    button:SetBackdropBorderColor(0.31, 0.39, 0.46, 1)
    button:SetHighlightTexture(WHITE)
    button:GetHighlightTexture():SetVertexColor(0.70, 0.84, 1, 0.12)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    if art then
        local image = button:CreateTexture(nil, "ARTWORK")
        image:SetSize(28, 28)
        image:SetPoint("TOP", 0, -8)
        image:SetTexture(icon(art))
        text:SetPoint("BOTTOM", 0, 7)
    else
        text:SetPoint("CENTER")
    end
    text:SetText(label)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", action)
    return button
end

function addon.createMenu(toggleCombat)
    menu = CreateFrame("Frame", "SPMobileMenu", UIParent, "BackdropTemplate")
    menu:SetPoint("CENTER")
    menu:SetFrameStrata("DIALOG")
    menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    menu:SetBackdropColor(0.045, 0.065, 0.09, 0.98)
    menu:SetBackdropBorderColor(0.34, 0.47, 0.59, 1)
    menu:Hide()
    tinsert(UISpecialFrames, menu:GetName())

    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -19)
    title:SetText("Game menu")
    local close = tile(menu, "Back", nil, function() menu:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -8)
    close:SetSize(70, 42)

    local entries = {
        { "Bags", "INV_Misc_Bag_08", function() call("ToggleAllBags") end },
        { "Map", "INV_Misc_Map_01", function() call("ToggleWorldMap") end },
        { "Quests", "INV_Misc_Note_01", function() if not call("ToggleQuestLog") then call("ToggleWorldMap") end end },
        { "Character", "INV_Shirt_White_01", function() call("ToggleCharacter", "PaperDollFrame") end },
        { "Spells", "INV_Misc_Book_09", function()
            if not call("ToggleSpellBook", BOOKTYPE_SPELL or "spell") then panel("PlayerSpellsFrame") end
        end },
        { "Talents", "Ability_Marksmanship", function() tab("ToggleTalentFrame", "PlayerSpellsFrame") end },
        { "Group", "Achievement_GuildPerk_EverybodysFriend", function()
            if not call("ToggleFriendsFrame", 3) then panel("FriendsFrame") end
        end },
        { "Chat", "INV_Letter_02", function() call("ChatFrame_OpenChat", "") end },
        { "Combat", "Ability_DualWield", toggleCombat },
        { "Settings", "INV_Misc_Gear_01", function()
            if SettingsPanel and SettingsPanel.Open then SettingsPanel:Open()
            elseif not panel("SettingsPanel") then panel("GameMenuFrame") end
        end },
    }
    local buttons = {}
    for i, entry in ipairs(entries) do
        local action = entry[3]
        buttons[i] = tile(menu, entry[1], entry[2], function()
            menu:Hide()
            action()
        end)
    end
    local function layout()
        local width = math.min(570, UIParent:GetWidth() - 24)
        local columns = width >= 410 and 5 or 3
        local rows = math.ceil(#buttons / columns)
        local height = math.min(72, (UIParent:GetHeight() - 76 - (rows - 1) * 8) / rows)
        local tileWidth = (width - 24 - (columns - 1) * 8) / columns
        menu:SetSize(width, 68 + rows * (height + 8))
        for i, button in ipairs(buttons) do
            button:ClearAllPoints()
            button:SetSize(tileWidth, height)
            button:SetPoint("TOPLEFT", 12 + ((i - 1) % columns) * (tileWidth + 8),
                            -56 - math.floor((i - 1) / columns) * (height + 8))
        end
    end
    menu:SetScript("OnShow", layout)
    menu:RegisterEvent("DISPLAY_SIZE_CHANGED")
    menu:RegisterEvent("UI_SCALE_CHANGED")
    menu:SetScript("OnEvent", function() if menu:IsShown() then layout() end end)
    local trigger = tile(UIParent, "Menu", nil, function() menu:SetShown(not menu:IsShown()) end)
    trigger:SetFrameStrata("LOW")
    trigger:SetSize(78, 48)
    trigger:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 10)
    return trigger, menu
end
