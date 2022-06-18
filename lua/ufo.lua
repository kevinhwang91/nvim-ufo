local M = {}
local cmd = vim.cmd
local fn = vim.fn
local api = vim.api


function M.setup(opts)
    opts = opts or {}
    M._config = opts
    M.enable()
end

function M.goPreviousStartFold()
    return require('ufo.action').goPreviousStartFold()
end

function M.inspect(bufnr)
    local msg = require('ufo.main').inspectBuf(bufnr)
    if not msg then
        vim.notify(('Buffer %d has not been attached.'):format(bufnr), vim.log.levels.ERROR)
    else
        vim.notify(table.concat(msg, '\n'), vim.log.levels.INFO)
    end
end

function M.enable()
    require('ufo.main').enable()
end

function M.disable()
    require('ufo.main').disable()
end

function M.hasAttached(bufnr)
    return require('ufo.main').inspectBuf(bufnr) ~= nil
end

function M.attach(bufnr)
    require('ufo.main').attach(bufnr)
end

function M.detach(bufnr)
    require('ufo.main').detach(bufnr)
end

function M.getFoldingRange(providerName, bufnr)
    local ok, res = pcall(require, 'ufo.provider.' .. providerName)
    assert(ok, ([[Can't find %s provider]]):format(providerName))
    return res.getFolds(bufnr)
end

function M.setFoldVirtTextHandler(bufnr, handler)
    require('ufo.decorator').setVirtTextHandler(bufnr, handler)
end

return M
