local M = {}
local cmd = vim.cmd
local fn = vim.fn
local api = vim.api

local utils     = require('ufo.utils')
local log       = require('ufo.log')
local fold      = require('ufo.fold')
local decorator = require('ufo.decorator')
local highlight = require('ufo.highlight')
local event     = require('ufo.event')

local enabled

local function initEvents()
    cmd([[
        aug Ufo
            au!
            au BufEnter * lua require('ufo.event').emit('BufEnter')
            au InsertLeave * lua require('ufo.event').emit('InsertLeave')
            au BufWritePost * lua require('ufo.event').emit('BufWritePost')
            au WinClosed * lua require('ufo.event').emit('WinClosed')
            au ColorScheme * lua require('ufo.event').emit('ColorScheme')
        aug END
    ]])
end

local function destroyEvents()
    cmd([[
        au! Ufo
        aug! Ufo
    ]])
end

function M.enable()
    if enabled then
        return false
    end
    local ns = api.nvim_create_namespace('ufo')
    initEvents()
    highlight.initialize()
    fold.initialize(ns)
    decorator.initialize(ns)
    enabled = true
    return true
end

function M.disable()
    if not enabled then
        return false
    end
    destroyEvents()
    highlight.dispose()
    fold.dispose()
    decorator.dispose()
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
    local main = fb.providers[1]
    table.insert(msg, 'Main provider: ' .. (type(main) == 'function' and 'external' or main))
    if fb.providers[2] then
        table.insert(msg, 'Fallback provider: ' .. fb.providers[2])
    end
    table.insert(msg, 'Selected provider: ' .. fb.selectedProvider)
    return msg
end

function M.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    event.emit('BufEnter', bufnr)
end

function M.detach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = fold.get(bufnr)
    if fb then
        fb:dispose()
    end
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
