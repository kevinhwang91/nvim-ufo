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
local log        = require('ufo.lib.log')
local event      = require('ufo.lib.event')

local initialized

---@class UfoFold
---@field ns number
---@field disposables UfoDisposable[]
local Fold = {}

local function scanFoldedRanges(bufnr, winid)
    local lineCount = api.nvim_buf_line_count(bufnr)
    local res = {}
    local stack = {}
    local openFmt, closeFmt = '%dfoldopen', '%dfoldclose'
    for i = 1, lineCount do
        local skip = false
        while #stack > 0 and i >= stack[#stack] do
            local endLnum = table.remove(stack)
            local c = closeFmt:format(endLnum)
            cmd(c)
            log.info(c)
            skip = true
        end
        if not skip then
            local endLnum = utils.foldClosedEnd(winid, i)
            if endLnum ~= -1 then
                table.insert(stack, endLnum)
                table.insert(res, {i - 1, endLnum - 1})
                local c = openFmt:format(i)
                cmd(c)
                log.info(c)
            end
        end
    end
    return res
end

local function applyFoldRanges(bufnr, winid, ranges, ns)
    if utils.mode() ~= 'n' or utils.isDiffOrMarkerFold(winid) then
        return false
    end
    local marks = api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {details = true})
    local rowPairs = {}
    for _, m in ipairs(marks) do
        local row, endRow = m[2], m[4].end_row
        rowPairs[row] = endRow
    end
    log.info('apply fold ranges:', ranges)
    log.info('apply fold rowPairs:', rowPairs)
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
        -- TODO
        -- buffer go back normal mode from diff mode will disable `foldenable` if the foldmethod was
        -- `manual` before entering diff mode. Unfortunately, foldmethod will always be `manual` if
        -- enable ufo, `foldenable` will be disabled.
        -- version will be `0` if never update folds for the buffer
        if fb.version > 0 then
            vim.wo[winid].foldenable = true
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
    elseif not vim.wo[winid].foldenable or utils.isDiffOrMarkerFold(winid) then
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
        if fb.version == 0 then
            -- TODO
            -- content may changed
            for _, range in ipairs(scanFoldedRanges(bufnr, winid)) do
                local row, endRow = range[1], range[2]
                fb:closeFold(row + 1, endRow + 1)
            end
        end
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

function Fold.attach(bufnr)
    foldbuffer.detachedBufSet[bufnr] = nil
end

function Fold.detach(bufnr)
    foldbuffer.detachedBufSet[bufnr] = true
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
    local debounced = require('ufo.lib.debounce')(Fold.update, 300)
    return function(bufnr, flush)
        bufnr = bufnr or api.nvim_get_current_buf()
        local fb = foldbuffer:get(bufnr)
        if not fb then
            return
        end
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
    if foldbuffer.detachedBufSet[bufnr] then
        return
    end
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

    ---@diagnostic disable: redefined-local, unused-local
    api.nvim_buf_attach(bufnr, false, {
        on_lines = function(name, bufnr, changedtick, firstLine, lastLine,
                            lastLineUpdated, byteCount)
            local fb = foldbuffer:get(bufnr)
            if not fb then
                log.debug('bufnr:', bufnr, 'has detached')
                return true
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

local function updatePendingFold(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = foldbuffer:get(bufnr)
    if not fb then
        return
    end
    promise.resolve():thenCall(function()
        if utils.mode() == 'n' then
            if fb.status == 'pending' then
                fb.status = 'start'
                updateFoldDebounced(bufnr)
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

---
---@param ns number
---@return UfoFold
function Fold:initialize(ns)
    if initialized then
        return self
    end
    local disposables = {}
    event:on('BufEnter', attach, disposables)
    event:on('InsertLeave', updateFoldFlush, disposables)
    event:on('TextChanged', updateFoldDebounced, disposables)
    event:on('BufWritePost', updateFoldFlush, disposables)
    event:on('CmdlineLeave', updatePendingFold, disposables)
    event:on('WinClosed', diffWinClosed, disposables)
    local d = foldbuffer:initialize(ns, config.open_fold_hl_timeout, config.provider_selector)
    table.insert(disposables, d)
    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        attach(api.nvim_win_get_buf(winid))
    end
    self.ns = ns
    self.disposables = disposables
    initialized = true
    return self
end

function Fold:dispose()
    for _, item in ipairs(self.disposables) do
        item:dispose()
    end
    initialized = false
end

return Fold
