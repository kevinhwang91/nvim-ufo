local util = require('vim.lsp.util')
local promise = require('promise')
local utils = require('ufo.utils')
local async = require('async')
local log = require('ufo.lib.log')
local foldingrange = require('ufo.model.foldingrange')

---@class UfoLspNvimClient
---@field initialized boolean
local NvimClient = {
    initialized = true
}

local errorCodes = {
    -- Defined by JSON RPC
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    serverErrorStart = -32099,
    serverErrorEnd = -32000,
    ServerNotInitialized = -32002,
    UnknownErrorCode = -32001,
    -- Defined by the protocol.
    RequestCancelled = -32800,
    RequestFailed = -32803,
    ContentModified = -32801,
}

function NvimClient.request(client, method, params, bufnr)
    return promise(function(resolve, reject)
        client.request(method, params, function(err, res)
            if err then
                log.error('Received error in callback', err)
                log.error('Client:', client)
                log.error('All clients:', vim.lsp.get_active_clients({bufnr = bufnr}))
                local code = err.code
                if code == errorCodes.RequestCancelled or code == errorCodes.ContentModified or code == errorCodes.RequestFailed then
                    reject('UfoFallbackException')
                else
                    reject(err)
                end
            else
                resolve(res)
            end
        end, bufnr)
    end)
end

local function getClients(bufnr)
    local clients = vim.lsp.get_active_clients({bufnr = bufnr})
    return vim.tbl_filter(function(client)
        if vim.tbl_get(client.server_capabilities, 'foldingRangeProvider') then
            return true
        else
            return false
        end
    end, clients)
end

function NvimClient.requestFoldingRange(bufnr, kind)
    return async(function()
        if not utils.isBufLoaded(bufnr) then
            return
        end
        local clients = getClients(bufnr)
        if #clients == 0 then
            await(utils.wait(500))
            clients = getClients(bufnr)
        end
        -- TODO
        -- How to get the highest priority for the client?
        local client = clients[1]
        if not client then
            error('UfoFallbackException')
        end
        local params = {textDocument = util.make_text_document_params(bufnr)}
        return NvimClient.request(client, 'textDocument/foldingRange', params, bufnr)
            :thenCall(function(ranges)
                if not ranges then
                    return {}
                end
                ranges = vim.tbl_filter(function(o)
                    return (not kind or kind == o.kind) and o.startLine < o.endLine
                end, ranges)
                foldingrange.sortRanges(ranges)
                return ranges
            end)
    end)
end

return NvimClient
