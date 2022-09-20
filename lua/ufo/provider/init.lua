local uv = vim.loop

local promise = require('promise')
local log     = require('ufo.lib.log')

---@class Provider UfoProvider
---@field modulePathPrefix string
---@field innerProviders string[]
---@field modules table
local Provider = {
    modulePathPrefix = 'ufo.provider.',
    innerProviders = {'lsp', 'treesitter', 'indent'}
}

local function needFallback(reason)
    return type(reason) == 'string' and reason:match('UfoFallbackException')
end

function Provider:getFunction(m)
    return type(m) == 'string' and self.modules[m].getFolds or m
end

---
---@param providers table
---@param bufnr number
---@return Promise
function Provider:requestFoldingRange(providers, bufnr)
    local main, fallback = providers[1], providers[2]
    local mainFunc = self:getFunction(main)

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
            local fallbackFunc = self:getFunction(fallback)
            if fallbackFunc then
                return {fallback, fallbackFunc(bufnr)}
            else
                return {main, nil}
            end
        else
            return promise.reject(reason)
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

function Provider:initialize()
    self.modules = setmetatable({}, {
    __index = function(t, k)
        local ok, res = pcall(require, self.modulePathPrefix .. k)
        assert(ok, ([[Can't find a module in `%s%s`]]):format(self.modulePathPrefix, k))
        rawset(t, k, res)
        return res
    end
    })
    return self
end

function Provider:dispose()
    for _, name in ipairs(self.innerProviders) do
        local module = _G.package.loaded[self.modulePathPrefix .. name]
        if module and module.dispose then
            module:dispose()
        end
    end
end

return Provider
