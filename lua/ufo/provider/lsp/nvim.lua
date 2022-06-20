local util    = require('vim.lsp.util')
local promise = require('promise')
local utils   = require('ufo.utils')
local async   = require('async')

---@class UfoLspNvimClient
---@field initialized boolean
local NvimClient = {
    initialized = true
}

function NvimClient.request(client, method, params, bufnr)
    return promise(function(resolve, reject)
        client.request(method, params, function(err, res)
            if err then
                reject(err)
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
        local _, client = next(clients)
        if not client then
            error('No provider')
        end
        local params = {textDocument = util.make_text_document_params(bufnr)}
        return NvimClient.request(client, 'textDocument/foldingRange',
                                  params, bufnr):thenCall(function(ranges)
            if not ranges then
                return {}
            end
            ranges = vim.tbl_filter(function(o)
                return (not kind or kind == o.kind) and o.startLine < o.endLine
            end, ranges)
            table.sort(ranges, function(a, b)
                return a.startLine == b.startLine and a.endLine < b.endLine or
                    a.startLine > b.startLine
            end)
            return ranges
        end)
    end)
end

return NvimClient
