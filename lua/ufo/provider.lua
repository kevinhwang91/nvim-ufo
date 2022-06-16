local promise = require('promise')

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

function Provider.requestFoldingRange(providers, bufnr)
    local main, fallback = providers[1], providers[2]
    local mainFunc = getFunction(main)
    return promise.resolve(mainFunc(bufnr)):thenCall(function(value)
        return {main, value}
    end, function(reason)
        if reason == 'UfoFallbackException' then
            local fallbackFunc = getFunction(fallback)
            if fallbackFunc then
                return {fallback, fallbackFunc(bufnr)}
            end
        else
            error(reason)
        end
    end)
end

return Provider
