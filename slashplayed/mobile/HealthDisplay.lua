-- Native display only. Do not inspect, export, compare, or calculate with secrets.
local function spDisplayHealth(bar, current, capacity)
    local ok = pcall(function()
        bar:SetMinMaxValues(0, capacity)
        bar:SetValue(current)
    end)
    if not ok then
        -- Never leave a stale full-health display after a failed native update.
        pcall(function()
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
        end)
    end
    return ok
end
