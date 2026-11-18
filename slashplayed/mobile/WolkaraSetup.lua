-- One Wolkara HUD: use its tap-open rings, not the permanent side spell wheels.
-- Existing ring assignments and hidden side-wheel entries are never destroyed.
local _, ns = ...
local Setup = ns.Register("Slashplayed tap-open wheels", {})

local function copyMissing(group, wheel)
    local entries = wheel.entries
    local function already(entry)
        for _, old in pairs(entries) do
            if type(old) == "table" and old.kind == entry.kind and old.id == entry.id then return true end
        end
        return false
    end
    for index = 1, ns.MAX_FREE do
        local button = group.buttons[index]
        local entry = type(button) == "table" and button.entry
        if type(entry) == "table" and entry.kind and entry.id ~= nil and not already(entry) then
            for slot = 1, ns.MAX_SLOTS do
                if entries[slot] == nil then
                    local copy = {}
                    for k, v in pairs(entry) do copy[k] = v end
                    entries[slot] = copy
                    wheel.slots = math.max(wheel.slots, slot)
                    break
                end
            end
        end
    end
end

function Setup:Layout()
    local db = ns.db
    if not db or db.slashplayedTapWheels then return end
    -- The upstream legacy golden-wheel migration has already run. Preserve the
    -- user-configured ring slots, fill only empty slots from their previous HUD.
    copyMissing(db.free, db.wheels[1])
    copyMissing(db.freeLeft, db.wheels[2])
    db.wheels[1].enabled = true
    db.wheels[2].enabled = true
    db.free.count = 0
    db.freeLeft.count = 0
    db.slashplayedTapWheels = true
    if ns.MarkChanged then ns.MarkChanged() end
end
