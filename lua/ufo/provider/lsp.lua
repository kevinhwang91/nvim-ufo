local uv = vim.loop

local promise    = require('promise')
local utils      = require('ufo.utils')
local log        = require('ufo.lib.log')
local bufmanager = require('ufo.bufmanager')

---@class UfoLSPProvider
local LSP = {}

---@class UfoLSPProviderContext
---@field timestamp number
---@field count number

local provider
local hasProviders = {}


---@type table<string, UfoLSPProviderContext>
local providerContext = {}


local function hasInitialized()
    return provider and provider.initialized
end

local function initialize()
    return utils.wait(1500):thenCall(function()
        local cocInitlized = vim.g.coc_service_initialized
        local module
        if _G.package.loaded['vim.lsp'] and (not cocInitlized or cocInitlized ~= 1) then
            module = 'nvim'
        elseif cocInitlized and cocInitlized == 1 then
            module = 'coc'
        else
            module = 'fastfailure'
        end
        log.debug(('using %s as a lsp provider'):format(module))
        provider = require('ufo.provider.lsp.' .. module)
    end)
end

local function request(bufnr)
    local buf = bufmanager:get(bufnr)
    if not buf then
        return promise.resolve()
    end
    local bt = buf:buftype()
    if bt ~= '' and bt ~= 'acwrite' then
        return promise.resolve()
    end
    local ft = buf:filetype()
    local hasProvider = hasProviders[ft]
    local firstCheckFt = false
    if hasProvider == nil then
        local context = providerContext[ft]
        if not context then
            firstCheckFt = true
            providerContext[ft] = {timestamp = uv.hrtime(), count = 0}
        else
            -- after 120 seconds and count is greater than 5
            if uv.hrtime() - context.timestamp > 1.2e11 and context.count >= 5 then
                hasProviders[ft] = false
                hasProvider = false
                providerContext[ft] = nil
            end
        end
    end
    if provider.initialized and hasProvider ~= false then
        local p
        if firstCheckFt then
            -- wait for the server, is 200ms enough?
            p = utils.wait(200):thenCall(function()
                return provider.requestFoldingRange(bufnr)
            end)
        else
            p = provider.requestFoldingRange(bufnr)
        end
        if hasProvider == nil then
            p = p:thenCall(function(value)
                hasProviders[ft] = true
                providerContext[ft] = nil
                return value
            end, function(reason)
                local context = providerContext[ft]
                if context then
                    providerContext[ft].count = context.count + 1
                end
                return promise.reject(reason)
            end)
        end
        return p
    else
        return promise.reject('UfoFallbackException')
    end
end

function LSP.getFolds(bufnr)
    if not hasInitialized() then
        return initialize():thenCall(function()
            return request(bufnr)
        end)
    end
    return request(bufnr)
end

return LSP
