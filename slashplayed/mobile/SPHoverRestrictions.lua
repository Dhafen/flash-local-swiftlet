-- Observe the addon's own restriction events without affecting the game dialog.
local spHoverRestriction
local spHoverStage = "bootstrap"
do
    local events = CreateFrame("Frame")
    local function publicString(value)
        return type(value) == "string" and not (issecretvalue and issecretvalue(value))
            and not (canaccessvalue and not canaccessvalue(value))
    end
    events:SetScript("OnEvent", function(_, event, addon, action)
        if not publicString(addon) or addon ~= "SPHover" then return end
        if not publicString(action) or not action:match("^[A-Za-z0-9_:.() ]+$") then action = "unknown" end
        action = action:sub(1, 88 - #spHoverStage) .. " during " .. spHoverStage
        local kind = event == "ADDON_ACTION_FORBIDDEN" and 1 or 2
        spHoverRestriction = string.char(65, 69, 1, kind, #action) .. action
    end)
    spHoverStage = "ADDON_ACTION_FORBIDDEN"
    pcall(events.RegisterEvent, events, "ADDON_ACTION_FORBIDDEN")
    spHoverStage = "ADDON_ACTION_BLOCKED"
    pcall(events.RegisterEvent, events, "ADDON_ACTION_BLOCKED")
end
