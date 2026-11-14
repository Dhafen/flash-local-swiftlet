-- Seed a new Wolkara layout from the character's existing actions.
-- The original SavedVariables and action bars are read only.
local _, ns = ...

local Setup = ns.Register("Slashplayed first-run setup", {})
local MAX_SLOTS = 12

local function action(kind, id, icon)
    if kind == "spell" or kind == "item" then
        if tonumber(id) and tonumber(id) > 0 then return { kind = kind, id = tonumber(id) } end
    elseif kind == "macro" then
        local name
        if type(id) == "number" then name, icon = GetMacroInfo(id) else name = id end
        if type(name) == "string" and name ~= "" then return { kind = kind, id = name, icon = icon } end
    end
end

local function collect(first, count, bindings)
    local entries = {}
    for index = first, first + count - 1 do
        local entry
        if bindings then
            local old = bindings[index]
            if type(old) == "table" then entry = action(old.kind, old.value, old.icon) end
        elseif GetActionInfo then
            entry = action(GetActionInfo(index))
        end
        if entry then entries[#entries + 1] = entry end
        if #entries == MAX_SLOTS then break end
    end
    return entries
end

local function seed(group, entries)
    for _, button in pairs(group.buttons) do
        if type(button) == "table" and button.entry then return end
    end
    if #entries == 0 then return end
    group.count = math.max(group.count, #entries)
    for index, entry in ipairs(entries) do
        group.buttons[index] = { entry = entry }
    end
end

function Setup:Layout()
    if ns.db.slashplayedSetup then return end
    local old = SPTouchBarsDB
    local bindings = type(old) == "table" and type(old.bindings) == "table" and old.bindings
    local page = GetActionBarPage and GetActionBarPage() or 1
    local right = bindings and collect(old.bank == 5 and 49 or 1, MAX_SLOTS, bindings) or {}
    local left = bindings and collect(61, MAX_SLOTS, bindings) or {}
    if #right == 0 then right = collect((page - 1) * MAX_SLOTS + 1, MAX_SLOTS) end
    if #left == 0 then left = collect(page == 2 and 1 or 13, MAX_SLOTS) end
    seed(ns.db.free, right)
    seed(ns.db.freeLeft, left)
    -- Retry on a later UI layout or action update for a brand-new character.
    ns.db.slashplayedSetup = #right > 0 or #left > 0
end

ns.On("ACTIONBAR_SLOT_CHANGED", function()
    if ns.db and not ns.db.slashplayedSetup then ns.Layout() end
end)
