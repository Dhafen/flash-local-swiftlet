local f = assert(io.open(assert(arg[1]), "r"))
local display = assert(loadstring(f:read("*a") .. "\nreturn spDisplayHealth"))()
f:close()
local secret = setmetatable({}, {
    __lt = function() error("protected") end,
    __add = function() error("protected") end,
    __tostring = function() error("protected") end,
})
local bar = {}
function bar:SetMinMaxValues(min, max) self.min, self.max = min, max end
function bar:SetValue(value) self.value = value end
assert(display(bar, secret, secret))
assert(rawequal(bar.value, secret) and rawequal(bar.max, secret))
assert(display(bar, 20, 100))
assert(bar.value == 20 and bar.max == 100)
function bar:SetValue(v) if rawequal(v, secret) then error("setter refused") end self.value = v end
assert(not display(bar, secret, 100))
assert(bar.value == 0 and bar.max == 1)
print("native health display tests passed")
