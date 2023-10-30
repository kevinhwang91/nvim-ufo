local M = {}
local cmd = vim.cmd
local api = vim.api

local utils = require('ufo.utils')
local provider = require('ufo.provider')
local fold = require('ufo.fold')
local decorator = require('ufo.decorator')
local highlight = require('ufo.highlight')
local preview = require('ufo.preview')
local disposable = require('ufo.lib.disposable')
local bufmanager = require('ufo.bufmanager')

local enabled

---@type UfoDisposable[]
local disposables = {}

local function createEvents()
    cmd('aug Ufo')
    cmd([[
        au!
        au BufEnter * lua require('ufo.lib.event'):emit('BufEnter', vim.api.nvim_get_current_buf())
        au BufWinEnter * lua require('ufo.lib.event'):emit('BufWinEnter', vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
        au InsertLeave * lua require('ufo.lib.event'):emit('InsertLeave', vim.api.nvim_get_current_buf())
        au TextChanged * lua require('ufo.lib.event'):emit('TextChanged', vim.api.nvim_get_current_buf())
        au BufWritePost * lua require('ufo.lib.event'):emit('BufWritePost', vim.api.nvim_get_current_buf())
        au WinClosed * lua require('ufo.lib.event'):emit('WinClosed', tonumber(vim.fn.expand('<afile>')))
        au CmdlineLeave * lua require('ufo.lib.event'):emit('CmdlineLeave')
        au ColorScheme * lua require('ufo.lib.event'):emit('ColorScheme')
    ]])
    local bufOptSetArgs = 'vim.api.nvim_get_current_buf(), vim.v.option_new, vim.v.option_old'
    local winOptSetArgs = 'vim.api.nvim_get_current_win(), ' ..
        'tonumber(vim.v.option_new), tonumber(vim.v.option_old)'
    cmd(([[
        au OptionSet buftype silent! lua require('ufo.lib.event'):emit('BufTypeChanged', %s)
        au OptionSet filetype silent! lua require('ufo.lib.event'):emit('FileTypeChanged', %s)
    ]]):format(bufOptSetArgs, bufOptSetArgs, bufOptSetArgs))
    cmd(([[
        au OptionSet diff silent! lua require('ufo.lib.event'):emit('DiffModeChanged', %s)
    ]]):format(winOptSetArgs))
    cmd('aug END')

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

function M.enable()
    if enabled then
        return false
    end
    local ns = api.nvim_create_namespace('ufo')
    createCommand()
    disposables = {}
    table.insert(disposables, createEvents())
    table.insert(disposables, highlight:initialize())
    table.insert(disposables, provider:initialize())
    table.insert(disposables, decorator:initialize(ns))
    table.insert(disposables, fold:initialize(ns))
    table.insert(disposables, preview:initialize(ns))
    table.insert(disposables, bufmanager:initialize())
    enabled = true
    return true
end

function M.disable()
    if not enabled then
        return false
    end
    disposable.disposeAll(disposables)
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
    local kindSet = {}
    for _, range in ipairs(fb.foldRanges) do
        if range.kind then
            kindSet[range.kind] = true
        end
    end
    local kinds = {}
    for kind in pairs(kindSet) do
        table.insert(kinds, kind)
    end
    table.insert(msg, 'Fold kinds: ' .. table.concat(kinds, ', '))
    return msg
end

function M.hasAttached(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local buf = bufmanager:get(bufnr)
    return buf and buf.attached
end

function M.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    bufmanager:attach(bufnr)
end

function M.detach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    bufmanager:detach(bufnr)
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
    local curBufnr = api.nvim_get_current_buf()
    local buf = bufmanager:get(curBufnr)
    local text = buf and buf:lines(fs)[1] or api.nvim_buf_get_lines(curBufnr, fs - 1, fs, true)[1]
    return utils.expandTab(text, vim.bo.ts)
end

return M
