local phoneLayout = {}

function phoneLayout.enabled(saved, phone)
    if saved == nil then return phone == true end
    return saved == true
end

function phoneLayout.slot(index, width, height)
    local small = math.max(28, math.min(54, (width * 0.49 - 38) / 6, height * 0.15))
    local size = index == 1 and small + 4 or small
    local stride = small + 5
    local column = math.floor((index - 1) / 2)
    local row = (index - 1) % 2
    return width - 12 - (small + 4) / 2 - column * stride,
        12 + (small + 4) / 2 + row * stride, size
end

return phoneLayout
