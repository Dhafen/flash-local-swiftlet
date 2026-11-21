local frames, events, blocks, measured = {}, {}, {}, 0
UIParent = { GetWidth = function() return 1200 end, GetHeight = function() return 800 end,
    GetEffectiveScale = function() return 1 end }
local noop = function() end
local widget = {
    SetFrameStrata = noop, SetFrameLevel = noop, EnableMouse = noop, SetPoint = noop, SetHeight = noop,
    CreateTexture = function()
        local index = #blocks + 1
        blocks[index] = 0
        return {SetColorTexture = function(_, r, g, b) blocks[index] = r * 4 + g * 2 + b end,
            ClearAllPoints = noop, SetPoint = noop, SetSize = noop}
    end,
    GetWidth = UIParent.GetWidth,
    RegisterEvent = function(self, event) events[event] = self end,
    SetScript = function(self, event, handler) self[event] = handler end,
}
CreateFrame = function(_, name)
    local frame = setmetatable({}, {__index = widget})
    if name then frames[name] = frame end
    return frame
end
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
local strip = assert(frames.SPHoverStrip)
strip:OnUpdate(0.5)
assert(#SPHover.chunks() > 0 and forbiddenCalls == 0)

local function encodedFrame()
    local bytes, value, bits = {}, 0, 0
    for _, block in ipairs(blocks) do
        value, bits = value * 8 + block, bits + 3
        if bits >= 8 then
            bits = bits - 8
            local divisor = 2 ^ bits
            bytes[#bytes + 1], value = string.char(math.floor(value / divisor)), value % divisor
        end
    end
    return table.concat(bytes)
end
local listener = assert(events.ADDON_ACTION_FORBIDDEN)
listener:OnEvent("ADDON_ACTION_FORBIDDEN", "OtherAddon", "OtherFunction")
for _ = 2, 14 do strip:OnUpdate(0.02) end
assert(encodedFrame():sub(1, 2) ~= "AE", "events attributed to other add-ons are ignored")
listener:OnEvent("ADDON_ACTION_FORBIDDEN", "SPHover", "SetPreferredGamepadInteractTarget()")
for _ = 1, 16 do strip:OnUpdate(0.02) end
local frame = encodedFrame()
assert(frame:sub(1, 2) == "AE" and frame:sub(6, 7) == "AE" and frame:byte(9) == 1)
assert(frame:sub(11, 10 + frame:byte(10)) == "SetPreferredGamepadInteractTarget()")
print("iPhone SPHover startup scans its own eligible panel only")
