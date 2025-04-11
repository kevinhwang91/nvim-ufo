local uv = vim.loop
local utils = require('ufo.utils')

---@class UfoDebounce
---@field timer userdata
---@field fn function
---@field args table
---@field wait number
---@field leading? boolean
---@overload fun(fn: function, wait: number, leading?: boolean): UfoDebounce
local Debounce = {}

---
---@param fn function
---@param wait number
---@param leading? boolean
---@return UfoDebounce
function Debounce:new(fn, wait, leading)
    utils.validate('fn', fn, 'function')
    utils.validate('wait', wait, 'number')
    utils.validate('leading', leading, 'boolean', true)

    local o = setmetatable({}, self)
    o.timer = nil
    o.fn = vim.schedule_wrap(fn)
    o.args = nil
    o.wait = wait
    o.leading = leading
    return o
end

function Debounce:call(...)
    local timer = self.timer
    self.args = {...}
    if not timer then
        ---@type userdata
        timer = uv.new_timer()
        self.timer = timer
        local wait = self.wait
        timer:start(wait, wait, self.leading and function()
            self:cancel()
        end or function()
            self:flush()
        end)
        if self.leading then
            self.fn(...)
        end
    else
        timer:again()
    end
end

function Debounce:cancel()
    local timer = self.timer
    if timer then
        if timer:has_ref() then
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
        end
        self.timer = nil
    end
end

function Debounce:flush()
    if self.timer then
        self:cancel()
        self.fn(unpack(self.args))
    end
end

Debounce.__index = Debounce
Debounce.__call = Debounce.call

return setmetatable(Debounce, {
    __call = Debounce.new
})
