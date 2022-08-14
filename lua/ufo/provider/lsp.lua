local uv = vim.loop

local promise    = require('promise')
local utils      = require('ufo.utils')
local log        = require('ufo.lib.log')
local bufmanager = require('ufo.bufmanager')

local LSP               = {}
local provider
local hasProviders      = {}
local providerTimestamp = {}


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
    if hasProvider == nil then
        if not providerTimestamp[ft] then
            providerTimestamp[ft] = uv.hrtime()
        else
            -- after 20 seconds
            if uv.hrtime() - providerTimestamp[ft] > 2e10 then
                hasProviders[ft] = false
                hasProvider = false
                providerTimestamp[ft] = nil
            end
        end
    end
    if provider.initialized and hasProvider ~= false then
        local p = provider.requestFoldingRange(bufnr)
        if hasProvider == nil then
            p = p:thenCall(function(value)
                hasProviders[ft] = true
                providerTimestamp[ft] = nil
                return value
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
