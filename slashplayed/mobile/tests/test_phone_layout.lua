local layout = assert(loadfile(arg[1]))()
assert(layout.enabled(nil, true))
assert(not layout.enabled(nil, false))
assert(layout.enabled(true))
assert(not layout.enabled(false))
for _, screen in ipairs({ { 840, 400 }, { 640, 280 } }) do
    local w, h = screen[1], screen[2]
    for i = 1, 12 do
        local x, y, size = layout.slot(i, w, h)
        assert(x - size / 2 >= w / 2 and x + size / 2 <= w)
        assert(y - size / 2 >= 0 and y + size / 2 <= h * 0.60)
        for j = 1, i - 1 do
            local px, py, other = layout.slot(j, w, h)
            assert(math.abs(px - x) >= (size + other) / 2 or math.abs(py - y) >= (size + other) / 2)
        end
    end
end
print("Default mobile layout and 12 non-overlapping slots: PASS")
