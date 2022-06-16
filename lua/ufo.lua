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
    require('ufo.main').inspectBuf(bufnr)
end

function M.enable()
    require('ufo.main').enable()
end

function M.disable()
    require('ufo.main').disable()
end

function M.attach(bufnr)
    require('ufo.main').attach(bufnr)
end

function M.detach(bufnr)
    require('ufo.main').detach(bufnr)
end

function M.provider(name)
    local ok, res = pcall(require, 'ufo.provider.' .. name)
    assert(ok, ([[Can't find %s provider]]):format(name))
    return res
end

function M.setFoldVirtTextHandler(bufnr, handler)
    require('ufo.decorator').setVirtTextHandler(bufnr, handler)
end

return M
