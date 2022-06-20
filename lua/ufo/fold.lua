local api = vim.api
local cmd = vim.cmd
local fn = vim.fn
local uv = vim.loop

local config     = require('ufo.config')
local promise    = require('promise')
local async      = require('async')
local utils      = require('ufo.utils')
local foldbuffer = require('ufo.fold.buffer')
local driver     = require('ufo.fold.driver')
local provider   = require('ufo.provider')
local log        = require('ufo.log')
local event      = require('ufo.event')

local initialized

---@class UfoFold
---@field ns number
---@field disposables table
local Fold = {}

local function applyFoldRanges(bufnr, winid, ranges, ns)
    if utils.mode() ~= 'n' or vim.wo[winid].foldmethod ~= 'manual' then
        return false
    end
    local marks = api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {details = true})
    local rowPairs = {}
    for _, m in ipairs(marks) do
        local row, endRow = m[2], m[4].end_row
        rowPairs[row] = endRow
    end
    driver:createFolds(winid, ranges, rowPairs)
    return true
end

---@param bufnr number
---@return Promise
local function tryUpdateFold(bufnr)
    return async(function()
        local winid = fn.bufwinid(bufnr)
        if not utils.isWinValid(winid) then
            return
        end
        -- some plugins may change foldmethod to diff
        await(utils.wait(50))
        local fb = foldbuffer:get(bufnr)
        if not fb or not utils.isWinValid(winid) or utils.isDiffOrMarkerFold(winid) then
            return
        end
        await(Fold.update(bufnr))
    end)
end

function Fold.update(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = foldbuffer:get(bufnr)
    local winid = fn.bufwinid(bufnr)
    if not fb or fb:isFoldMethodsDisabled() then
        return promise.resolve()
    elseif winid == -1 then
        fb.status = 'pending'
        return promise.resolve()
    elseif utils.isDiffOrMarkerFold(winid) then
        return promise.resolve()
    end
    local changedtick = api.nvim_buf_get_changedtick(bufnr)
    if changedtick == fb.version and fb.foldRanges then
        if not applyFoldRanges(bufnr, winid, fb.foldRanges, fb.ns) then
            fb.status = 'pending'
        end
        return promise.resolve()
    end

    local s
    if log.isEnabled('debug') then
        s = uv.hrtime()
    end
    return provider.requestFoldingRange(fb.providers, bufnr):thenCall(function(res)
        if log.isEnabled('debug') then
            log.debug(('requestFoldingRange(%s, %d) has elapsed: %dms')
                :format(vim.inspect(fb.providers, {indent = '', newline = ' '}),
                        bufnr, (uv.hrtime() - s) / 1e6))
        end
        local p, ranges = res[1], res[2]
        fb.selectedProvider = type(p) == 'string' and p or 'external'
        if not ranges or #ranges == 0 or not utils.isBufLoaded(bufnr) then
            return
        end
        winid = fn.bufwinid(bufnr)
        local newChangedtick = api.nvim_buf_get_changedtick(bufnr)
        fb.version = newChangedtick
        fb.foldRanges = ranges
        if winid == -1 then
            fb.status = 'pending'
        elseif changedtick == newChangedtick and not utils.isDiffOrMarkerFold(winid) then
            if not applyFoldRanges(bufnr, winid, ranges, fb.ns) then
                fb.status = 'pending'
            end
        end
    end)
end

---
---@param bufnr number
function Fold.get(bufnr)
    return foldbuffer:get(bufnr)
end

function Fold.setStatus(bufnr, status)
    local fb = foldbuffer:get(bufnr)
    local old = ''
    if fb then
        old = fb.status
        fb.status = status
    end
    return old
end

local updateFoldDebounced = (function()
    local lastBufnr
    local debounced = require('ufo.debounce')(Fold.update, 500)
    return function(bufnr, flush)
        if lastBufnr ~= bufnr then
            debounced:flush()
        end
        lastBufnr = bufnr
        debounced(bufnr)
        if flush then
            debounced:flush()
        end
    end
end)()

local function attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    log.debug('attach bufnr:', bufnr)
    local fb = foldbuffer:get(bufnr)
    if fb then
        if fb.status == 'pending' then
            fb.status = 'start'
            log.debug('handle the pending ranges for bufnr:', bufnr)
            Fold.update(bufnr):thenCall(function()
                if fb.status == 'pending' then
                    fb.status = 'start'
                    Fold.update(bufnr)
                end
            end)
        end
        return
    end

    local bt = vim.bo[bufnr].bt
    if bt == 'terminal' or bt == 'prompt' then
        return
    end

    fb = foldbuffer:new(bufnr)
    cmd([[
        setl foldtext=v:lua.require'ufo.main'.foldtext()
        setl fillchars+=fold:\ ]])

    if fb:isFoldMethodsDisabled() then
        return
    end
    ---@diagnostic disable: redefined-local, unused-local
    api.nvim_buf_attach(bufnr, false, {
        on_lines = function(name, bufnr, changedtick, firstLine, lastLine,
                            lastLineUpdated, byteCount)
            local fb = foldbuffer:get(bufnr)
            if not fb then
                log.debug('bufnr:', bufnr, 'has detached')
                return true
            end
            -- TODO
            -- can't skip select mode
            if fb.status == 'start' and utils.mode() == 'n' then
                updateFoldDebounced(bufnr)
            end
        end,
        on_detach = function(name, bufnr)
            local fb = foldbuffer:get(bufnr)
            if fb then
                fb:dispose()
            end
        end,
        on_reload = function(name, bufnr)
            foldbuffer:new(bufnr)
        end
    })
    ---@diagnostic enable: redefined-local, unused-local
    tryUpdateFold(bufnr)
end

local function updateFoldFlush(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = foldbuffer:get(bufnr)
    if not fb then
        return
    end
    promise.resolve():thenCall(function()
        if utils.mode() == 'n' then
            if fb.status == 'pending' then
                fb.status = 'start'
            end
            if fb.status == 'start' then
                updateFoldDebounced(bufnr, true)
            end
        end
    end)
end

local function diffWinClosed()
    local winid = tonumber(fn.expand('<afile>')) or api.nvim_get_current_win()
    if utils.isWinValid(winid) and utils.isDiffFold(winid) then
        for _, id in ipairs(api.nvim_tabpage_list_wins(0)) do
            if winid ~= id and utils.isDiffFold(id) then
                local bufnr = api.nvim_win_get_buf(id)
                local fb = foldbuffer:get(bufnr)
                if fb then
                    fb:resetFoldedLines()
                    tryUpdateFold(bufnr)
                end
            end
        end
    end
end

function Fold.initialize(ns)
    if initialized then
        return
    end
    local disposables = {}
    event.on('BufEnter', attach, disposables)
    event.on('InsertLeave', updateFoldFlush, disposables)
    event.on('BufWritePost', updateFoldFlush, disposables)
    event.on('CmdlineLeave', updateFoldFlush, disposables)
    event.on('WinClosed', diffWinClosed, disposables)
    foldbuffer.initialize(ns, config.open_fold_hl_timeout, config.provider_selector)
    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        attach(api.nvim_win_get_buf(winid))
    end
    Fold.ns = ns
    Fold.disposables = disposables
    initialized = true
end

function Fold.dispose()
    foldbuffer.disposeAll()
    for _, item in ipairs(Fold.disposables) do
        item.dispose()
    end
    initialized = false
end

return Fold
