local uv = vim.loop

local promise = require('promise')
local log     = require('ufo.lib.log')

---@class Provider UfoProvider
local Provider = {}

local modules = setmetatable({}, {
    __index = function(t, k)
        local ok, res = pcall(require, 'ufo.provider.' .. k)
        assert(ok, ([[Can't find a module in `ufo.provider.%s`]]):format(k))
        rawset(t, k, res)
        return res
    end
})

local function getFunction(m)
    return type(m) == 'string' and modules[m].getFolds or m
end

local function needFallback(reason)
    return type(reason) == 'string' and reason:match('UfoFallbackException')
end

---
---@param providers table
---@param bufnr number
---@return Promise
function Provider.requestFoldingRange(providers, bufnr)
    local main, fallback = providers[1], providers[2]
    local mainFunc = getFunction(main)

    local s
    if log.isEnabled('debug') then
        s = uv.hrtime()
    end
    local p = promise(function(resolve)
        resolve(mainFunc(bufnr))
    end):thenCall(function(value)
        return {main, value}
    end, function(reason)
        if needFallback(reason) then
            local fallbackFunc = getFunction(fallback)
            if fallbackFunc then
                return {fallback, fallbackFunc(bufnr)}
            else
                return {main, nil}
            end
        else
            error(reason)
        end
    end)
    if log.isEnabled('debug') then
        p = p:finally(function()
            log.debug(('requestFoldingRange(%s, %d) has elapsed: %dms')
                :format(vim.inspect(providers, {indent = '', newline = ' '}),
                        bufnr, (uv.hrtime() - s) / 1e6))
        end)
    end
    return p
end

return Provider
