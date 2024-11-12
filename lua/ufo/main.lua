local M = {}
local cmd = vim.cmd
local api = vim.api

local event = require('ufo.lib.event')
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
    local gid = api.nvim_create_augroup('Ufo', {})
    api.nvim_create_autocmd({'BufWinEnter', 'TextChanged', 'BufWritePost'}, {
        group = gid,
        callback = function(ev)
            event:emit(ev.event, ev.buf)
        end
    })
    api.nvim_create_autocmd('WinClosed', {
        group = gid,
        callback = function(ev)
            event:emit(ev.event, tonumber(ev.file))
        end
    })
    api.nvim_create_autocmd('ModeChanged', {
        group = gid,
        pattern = '*:n',
        callback = function(ev)
            local previousMode = ev.match:match('(%a):')
            event:emit('ModeChangedToNormal', ev.buf, previousMode)
        end
    })
    api.nvim_create_autocmd('ColorScheme', {
        group = gid,
        callback = function(ev)
            event:emit(ev.event)
        end
    })
    api.nvim_create_autocmd('OptionSet', {
        group = gid,
        pattern = {'buftype', 'filetype', 'syntax', 'diff'},
        callback = function(ev)
            local match = ev.match
            local e
            if match == 'buftype' then
                e = 'BufTypeChanged'
            elseif match == 'filetype' then
                e = 'FileTypeChanged'
            elseif match == 'syntax' then
                e = 'SyntaxChanged'
            elseif match == 'diff' then
                event:emit('DiffModeChanged', api.nvim_get_current_win(), vim.v.option_new, vim.v.option_old)
                return
            else
                error([[Didn't match any events!]])
            end
            event:emit(e, ev.buf, vim.v.option_new, vim.v.option_old)
        end
    })
    return disposable:create(function()
        api.nvim_del_augroup_by_id(gid)
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
    local winid = utils.getWinByBuf(bufnr)
    if utils.isDiffOrMarkerFold(winid) then
        table.insert(msg, 'Fold method: ' .. vim.wo[winid].foldmethod)
        return msg
    end
    table.insert(msg, 'Fold Status: ' .. fb.status)
    local main = fb.providers[1]
    table.insert(msg, 'Main provider: ' .. (type(main) == 'function' and 'external' or main))
    if fb.providers[2] then
        table.insert(msg, 'Fallback provider: ' .. fb.providers[2])
    end
    table.insert(msg, 'Selected provider: ' .. (fb.selectedProvider or 'nil'))
    local curKind
    local curStartLine, curEndLine = 0, 0
    local kindSet = {}
    local lnum = api.nvim_win_get_cursor(winid)[1]
    for _, range in ipairs(fb.foldRanges) do
        local sl, el = range.startLine, range.endLine
        if curStartLine < sl and sl < lnum and lnum <= el + 1 then
            curStartLine, curEndLine = sl, el
            curKind = range.kind
        end
        if range.kind then
            kindSet[range.kind] = true
        end
    end
    local kinds = {}
    for kind in pairs(kindSet) do
        table.insert(kinds, kind)
    end
    table.insert(msg, 'Fold kinds: ' .. table.concat(kinds, ', '))
    if curStartLine ~= 0 or curEndLine ~= 0 then
        table.insert(msg, ('Cursor range: [%d, %d]'):format(curStartLine + 1, curEndLine + 1))
    end
    if curKind then
        table.insert(msg, 'Cursor kind: ' .. curKind)
    end
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
    local fs, fe = vim.v.foldstart, vim.v.foldend
    local winid = api.nvim_get_current_win()
    local virtText = decorator:getVirtTextAndCloseFold(winid, fs, fe, false)
    if utils.has10() then
        return virtText
    end
    local text
    if next(virtText) then
        text = ''
        for _, chunk in ipairs(virtText) do
            text = text .. chunk[1]
        end
        text = utils.expandTab(text, vim.bo.ts)
    end
    return text or utils.expandTab(api.nvim_buf_get_lines(0, fs - 1, fs, true)[1], vim.bo.ts)
end

return M
