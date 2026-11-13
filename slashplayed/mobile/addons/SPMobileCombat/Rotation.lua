local _, addon = ...
local rotation = {}
addon.rotation = rotation

function rotation.firstReady(priorities, available)
    for _, spell in ipairs(priorities) do
        if available(spell) then return spell end
    end
end

function rotation.parse(text)
    local result, seen = {}, {}
    for token in text:gmatch("[^,%s]+") do
        local spell = token:match("^%d+$") and tonumber(token)
        if not spell or spell < 1 or spell > 2147483647 then return nil end
        if not seen[spell] then
            if #result == 12 then return nil end
            result[#result + 1], seen[spell] = spell, true
        end
    end
    return result
end

function rotation.recommended(output)
    local rec = output and output.count > 0 and output.recs[1]
    local spell = rec and rec.actionID
    if type(spell) == "number" and spell > 0 then return spell, rec.texture end
    if rec then return nil, rec.texture end
end
