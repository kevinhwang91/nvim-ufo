local M = {}
local cmd = vim.cmd
local api = vim.api

local utils      = require('ufo.utils')
local fold       = require('ufo.fold')
local decorator  = require('ufo.decorator')
local highlight  = require('ufo.highlight')
local preview    = require('ufo.preview')
local event      = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')

local enabled

---@type UfoDisposable[]
local disposables = {}

local function createEvents()
    cmd([[
        aug Ufo
            au!
            au BufEnter * lua require('ufo.lib.event'):emit('BufEnter')
            au InsertLeave * lua require('ufo.lib.event'):emit('InsertLeave')
            au TextChanged * lua require('ufo.lib.event'):emit('TextChanged')
            au BufWritePost * lua require('ufo.lib.event'):emit('BufWritePost')
            au WinClosed * lua require('ufo.lib.event'):emit('WinClosed')
            au CmdlineLeave * lua require('ufo.lib.event'):emit('CmdlineLeave')
            au ColorScheme * lua require('ufo.lib.event'):emit('ColorScheme')
        aug END
    ]])
    return disposable:create(function()
        cmd([[
            au! Ufo
            aug! Ufo
        ]])
    end)
end

local function createCommand()
    cmd([[
        com! UfoEnable lua require('ufo').enable()
        com! UfoDisable lua require('ufo').disable()
        com! UfoInspect lua require('ufo').inspect()
        com! UfoAttach lua require('ufo').attach()
        com! UfoDetach lua require('ufo').detach()
        com! UfoEnableFold lua require('ufo').enableFold()
        com! UfoDisableFold lua require('ufo').disableFold()
    ]])
end

local function deleteCommand()

end

function M.enable()
    if enabled then
        return false
    end
    local ns = api.nvim_create_namespace('ufo')
    createCommand()
    table.insert(disposables, createEvents())
    table.insert(disposables, highlight:initialize())
    table.insert(disposables, fold:initialize(ns))
    table.insert(disposables, decorator:initialize(ns))
    table.insert(disposables, preview:initialize(ns))
    enabled = true
    return true
end

function M.disable()
    if not enabled then
        return false
    end
    deleteCommand()
    for _, item in ipairs(disposables) do
        item:dispose()
    end
    enabled = false
    return true
end

function M.inspectBuf(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = fold.get(bufnr)
    if not fb then
        return
    end
    local msg = {}
    table.insert(msg, 'Buffer: ' .. bufnr)
    table.insert(msg, 'Fold Status: ' .. fb.status)
    local main = fb.providers[1]
    table.insert(msg, 'Main provider: ' .. (type(main) == 'function' and 'external' or main))
    if fb.providers[2] then
        table.insert(msg, 'Fallback provider: ' .. fb.providers[2])
    end
    table.insert(msg, 'Selected provider: ' .. (fb.selectedProvider or 'nil'))
    return msg
end

function M.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    fold.attach(bufnr)
    event:emit('BufEnter', bufnr)
end

function M.detach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = fold.get(bufnr)
    if fb then
        fb:dispose()
    end
    fold.detach(bufnr)
end

function M.enableFold(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local old = fold.setStatus(bufnr, 'start')
    fold.update(bufnr)
    return old
end

function M.disableFold(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    return fold.setStatus(bufnr, 'stop')
end

function M.foldtext()
    local fs = vim.v.foldstart
    local text = api.nvim_buf_get_lines(0, fs - 1, fs, false)[1]
    return utils.expandTab(text, vim.bo.ts)
end

return M
