local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local ns = {db = {hud = {enabled = true, scale = 100}}}
local hud, inCombat
function ns.Register(_, module) hud = module; return module end
function ns.On() end
function ns.Box(frame, _, _, _, _, alpha) frame.backdropAlpha = alpha end
function ns.Disc() return setmetatable({}, {__index = function() return function() end end}) end
ns.Label, ns.EditFrame, ns.Circle = ns.Disc, ns.Disc, function() end

local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetHeight(height) self.height = height end
function methods:SetWidth(width) self.width = width end
function methods:SetScale(scale) self.scale = scale end
function methods:SetPoint(...) self.anchors[#self.anchors + 1] = {...} end
function methods:ClearAllPoints() self.anchors = {} end
function methods:SetClampedToScreen(on) self.clamped = on end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:GetPoint() error("must not read a secure frame's anchors") end
function methods:GetRect() error("must not read a secure frame's rectangle") end
function methods:SetColorTexture(...) self.color = {...} end
local fakeFrame = {__index = function(_, key) return methods[key] or function() end end}
function methods:CreateTexture()
    local texture = setmetatable({anchors = {}}, fakeFrame)
    self.textures[#self.textures + 1] = texture
    return texture
end

UIParent = {}
CreateFrame = function(kind, name, parent, template)
    local frame = setmetatable({kind = kind, parent = parent, template = template or false, anchors = {},
        textures = {}, shown = true}, fakeFrame)
    if name then _G[name] = frame end
    return frame
end
InCombatLockdown = function() return inCombat == true end
UnitExists = function() return true end

local core = read(assert(arg[1]))
local movableStart = assert(core:find("function ns.Movable(frame, store, key, default)", 1, true))
local movableEnd = assert(core:find("function ns.DragHandle(handle, frame)", movableStart, true))
local loadChunk = loadstring or load
assert(loadChunk("local ns = ...\n" .. core:sub(movableStart, movableEnd - 1)))(ns)
assert(loadfile(assert(arg[2])))("WolkaraRoue", ns)
hud:Init()
hud.Refresh = function() end

local player, target = assert(WolkaraMobilePlayer), assert(WolkaraMobileTarget)
local geometry = assert(WolkaraMobileHealthGeometry)
local crop = geometry.crop
assert(geometry.kind == "Frame" and not geometry.template and geometry.parent == UIParent)
assert(crop.kind == "Frame" and not crop.template and crop.parent == geometry)
assert(geometry.clamped and not geometry.shown)
assert(geometry.width == player.width and geometry.height == player.height and crop.height == player.health.height)
for i, anchor in ipairs(crop.anchors) do
    local visibleAnchor = player.health.anchors[i]
    assert(anchor[2] == geometry and visibleAnchor[2] == player)
    for _, field in ipairs({1, 3, 5}) do assert(anchor[field] == visibleAnchor[field]) end
    local marker = player.health.textures[i]
    local side, outer = i == 1 and "LEFT" or "RIGHT", i == 1 and "RIGHT" or "LEFT"
    assert(marker.width == 6 and anchor[4] - visibleAnchor[4] == (i == 1 and -6 or 6))
    for index, point in ipairs({"TOP", "BOTTOM"}) do
        local position = marker.anchors[index]
        assert(position[1] == point .. outer and position[2] == player.health and position[3] == point .. side)
    end
    assert(table.concat(marker.color, ",") == (i == 1 and "1,0,1,1" or "0,1,1,1"))
end
assert(player.health.backdropAlpha == 1 and #player.health.textures == 2)
assert(target.health.backdropAlpha == 0.55 and #target.health.textures == 0, "the target bar keeps its existing style")

local function expectPlacement(point, relativePoint, x, y, scale)
    assert(geometry.shown and geometry.scale == player.scale and geometry.scale == scale)
    assert(#geometry.anchors == 1 and #player.anchors == 1)
    local anchor, visibleAnchor = geometry.anchors[1], player.anchors[1]
    assert(anchor[1] == point and anchor[2] == UIParent and anchor[3] == relativePoint)
    assert(anchor[4] == x and anchor[5] == y)
    for i = 1, 5 do assert(anchor[i] == visibleAnchor[i]) end
end

hud:Layout()
expectPlacement("TOPLEFT", "TOPLEFT", 12, -10, 1)
ns.db.hud.player = {point = "BOTTOMRIGHT", relativePoint = "CENTER", x = -31, y = 58}
ns.db.hud.scale = 150
hud:Layout()
expectPlacement("BOTTOMRIGHT", "CENTER", -31, 58, 1.5)

ns.editing = true
hud:SetEditing(true)
assert(not geometry.shown)
hud:Layout()
assert(not geometry.shown)
ns.editing = false
hud:Layout()
expectPlacement("BOTTOMRIGHT", "CENTER", -31, 58, 1.5)
ns.db.hud.enabled = false
hud:Layout()
assert(not geometry.shown and not player.shown)

ns.db.hud.enabled = true
inCombat = true
hud:Layout()
assert(not geometry.shown, "a deferred anchor cannot publish a new crop")
inCombat = false
hud:Layout()
expectPlacement("BOTTOMRIGHT", "CENTER", -31, 58, 1.5)
player.SetPoint = function() error("the requested HUD placement failed") end
assert(not pcall(hud.Layout, hud) and not geometry.shown)
print("Wolkara health geometry follows only applied public layout")
