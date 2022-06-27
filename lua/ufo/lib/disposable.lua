---@class UfoDisposable
---@field func fun()
local Disposable = {}

---
---@param func fun()
---@return UfoDisposable
function Disposable:new(func)
    local o = setmetatable({}, self)
    self.__index = self
    o.func = func
    return o
end

---
---@param func fun()
---@return UfoDisposable
function Disposable:create(func)
    return self:new(func)
end

function Disposable:dispose()
    self.func()
end

return Disposable
