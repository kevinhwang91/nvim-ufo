local uv = vim.loop

local promise = require 'promise'
local utils   = require 'ufo.utils'
local log     = require 'ufo.log'

local LSP               = {}
local provider
local hasProviders      = {}
local providerTimestamp = {}


local function hasInitialized()
    return provider and provider.initialized
end

local function initialize()
    return utils.wait(1000):thenCall(function()
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
    local ft = vim.bo[bufnr].ft
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
        local resolve
        if hasProvider == nil then
            resolve = function(value)
                hasProviders[ft] = true
                providerTimestamp[ft] = nil
                return value
            end
        end
        return provider.requestFoldingRange(bufnr):thenCall(resolve, function(reason)
            if reason:match('No provider') then
                return promise.reject('fallback')
            else
                error(reason)
            end
        end)
    else
        return promise.reject('fallback')
    end
end

function LSP.getFolds(bufnr)
    if not hasInitialized() then
        return initialize():thenCall(function()
            if not utils.isBufLoaded(bufnr) then
                return promise.resolve()
            end
            return request(bufnr)
        end)
    end
    return request(bufnr)
end

return LSP
