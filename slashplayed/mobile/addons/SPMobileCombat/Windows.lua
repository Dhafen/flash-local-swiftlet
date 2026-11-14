local _, addon = ...
local frames = {
    "WorldMapFrame", "QuestFrame", "QuestLogFrame", "GossipFrame", "LootFrame",
    "ContainerFrameCombinedBags", "CharacterFrame", "PlayerSpellsFrame",
    "SpellBookFrame", "TalentFrame", "MerchantFrame", "BankFrame", "TradeFrame",
    "TaxiFrame", "MailFrame", "FriendsFrame", "CommunitiesFrame",
    "GameMenuFrame", "SettingsPanel", "PVEFrame",
}
local watched, original = {}, {}
local fitting

local function fit(frame)
    if fitting or InCombatLockdown() or not frame:IsShown()
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    -- Multi-anchor frames get their size from the client, including maximized maps.
    if frame:GetNumPoints() ~= 1 then return end
    local width, height = frame:GetSize()
    if not width or not height or width <= 0 or height <= 0 then return end
    local parent = frame:GetParent()
    local parentScale = parent and parent:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1
    if parentScale <= 0 then return end
    local screenWidth, screenHeight = UIParent:GetSize()
    original[frame] = original[frame] or frame:GetScale()
    local availableHeight = screenHeight - (frame == WorldMapFrame and 28 or 66)
    local scale = math.min(original[frame], (screenWidth - 28) / (width * parentScale),
                           availableHeight / (height * parentScale))
    if scale <= 0 then return end
    fitting = true
    if math.abs(frame:GetScale() - scale) > 0.001 then frame:SetScale(scale) end
    frame:SetClampedToScreen(true)
    fitting = false
end

local function watch(frame)
    if not frame or watched[frame] or not frame.HookScript
        or (frame.IsForbidden and frame:IsForbidden()) then return end
    watched[frame] = true
    frame:HookScript("OnShow", function(self)
        fit(self)
        if C_Timer then C_Timer.After(0, function() fit(self) end) end
    end)
end

function addon.fitWindows()
    local events = CreateFrame("Frame")
    local function refresh()
        for _, name in ipairs(frames) do watch(_G[name]) end
        for i = 1, 13 do watch(_G["ContainerFrame" .. i]) end
        for frame in pairs(watched) do fit(frame) end
    end
    for _, event in ipairs({ "ADDON_LOADED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", refresh)
    if type(ShowUIPanel) == "function" then
        hooksecurefunc("ShowUIPanel", function(frame)
            watch(frame)
            if watched[frame] then fit(frame) end
        end)
    end
    refresh()
end
