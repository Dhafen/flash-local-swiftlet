local callbacks, measured = {}, 0
UIParent = { GetWidth = function() return 1200 end, GetHeight = function() return 800 end,
    GetEffectiveScale = function() return 1 end }
local noop = function() end
local texture = { SetColorTexture = noop, ClearAllPoints = noop, SetPoint = noop, SetSize = noop }
local widget = {
    SetFrameStrata = noop, SetFrameLevel = noop, EnableMouse = noop, SetPoint = noop, SetHeight = noop,
    CreateTexture = function() return texture end, GetWidth = UIParent.GetWidth, RegisterEvent = noop,
    SetScript = function(_, event, handler) callbacks[event] = handler end,
}
CreateFrame = function() return widget end
GetPhysicalScreenSize = function() return 1200, 800 end
EnumerateFrames = function() error("iPhone startup enumerated unrelated UI frames") end
local forbiddenCalls = 0
local function forbidden() forbiddenCalls = forbiddenCalls + 1; error("restricted geometry") end
WorldMapFrame = {IsForbidden = function() return false end, IsVisible = function() return true end,
    GetRect = forbidden}
WolkaraMobileSettings = { IsForbidden = function() return false end, IsProtected = function() return false end,
    IsVisible = function() return true end, GetEffectiveScale = function() return 1 end,
    GetRect = function() measured = measured + 1; return 100, 100, 120, 150 end }
WolkaraMobileQuests = { IsForbidden = function() return false end, IsProtected = function() return true end,
    IsVisible = forbidden, GetRect = forbidden }

dofile(assert(arg[1], "Pass the staged SPHover.lua"))
local message = SPHover.scan()
assert(message:byte(1) == 0 and message:byte(2) == 1, "only the public Wolkara panel is encoded")
assert(measured == 1 and forbiddenCalls == 0)
callbacks.OnUpdate(widget, 0.5)
assert(#SPHover.chunks() > 0 and forbiddenCalls == 0)
local originalPrint, reported = print, {}
print = function(message) reported[#reported + 1] = message end
callbacks.OnEvent(widget, "ADDON_ACTION_FORBIDDEN", "OtherAddon", "OtherFunction")
callbacks.OnEvent(widget, "ADDON_ACTION_FORBIDDEN", "SPHover", "Frame:GetRect()")
callbacks.OnEvent(widget, "ADDON_ACTION_BLOCKED", "SPHover", "Frame:GetRect()")
print = originalPrint
assert(#reported == 1 and reported[1] == "SPHover blocked action: Frame:GetRect()")
print("iPhone SPHover startup scans its own eligible panel only")
