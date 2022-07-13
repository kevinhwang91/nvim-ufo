local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local config   = require('ufo.config')
local promise  = require('promise')
local async    = require('async')
local utils    = require('ufo.utils')
local provider = require('ufo.provider')
local log      = require('ufo.lib.log')
local event    = require('ufo.lib.event')
local manager  = require('ufo.fold.manager')

local initialized

---@class UfoFold
---@field disposables UfoDisposable[]
local Fold = {}

local updateFoldDebounced

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
        local fb = manager:get(bufnr)
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
    local fb = manager:get(bufnr)
    if not fb then
        return
    end
    fb.status = 'start'
    if manager:isFoldMethodsDisabled(fb) then
        return promise.resolve()
    end
    local winid = fn.bufwinid(bufnr)
    if winid == -1 then
        fb.status = 'pending'
        return promise.resolve()
    elseif not vim.wo[winid].foldenable or utils.isDiffOrMarkerFold(winid) then
        return promise.resolve()
    end
    if manager:applyFoldRanges(fb, winid) then
        return promise.resolve()
    end

    local changedtick = fb:changedtick()
    fb:acquireRequest()
    return provider.requestFoldingRange(fb.providers, bufnr):thenCall(function(res)
        fb:releaseRequest()
        local selected, ranges = res[1], res[2]
        fb.selectedProvider = type(selected) == 'string' and selected or 'external'
        if not ranges or #ranges == 0 or not utils.isBufLoaded(bufnr) then
            return
        end
        if changedtick ~= fb:changedtick() and not fb:requested() then
            -- text is changed during asking folding ranges
            -- update again if no other requests
            log.debug('update fold for bufnr:', bufnr, 'again')
            updateFoldDebounced(bufnr, true)
            return
        end
        manager:applyFoldRanges(fb, fn.bufwinid(bufnr), ranges)
    end, function(err)
        fb:releaseRequest()
        error(err)
    end)
end

---
---@param bufnr number
function Fold.get(bufnr)
    return manager:get(bufnr)
end

function Fold.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if not manager:attach(bufnr) then
        return
    end
    log.debug('attach bufnr:', bufnr)
    cmd([[
        setl foldtext=v:lua.require'ufo.main'.foldtext()
        setl fillchars+=fold:\ ]])
    tryUpdateFold(bufnr)
end

function Fold.setStatus(bufnr, status)
    local fb = manager:get(bufnr)
    local old = ''
    if fb then
        old = fb.status
        fb.status = status
    end
    return old
end

updateFoldDebounced = (function()
    local lastBufnr
    local debounced = require('ufo.lib.debounce')(Fold.update, 300)
    return function(bufnr, flush)
        bufnr = bufnr or api.nvim_get_current_buf()
        local fb = manager:get(bufnr)
        if not fb or fb.status == 'stop' then
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

local function updateFoldFlush(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = manager:get(bufnr)
    if not fb then
        return
    end
    promise.resolve():thenCall(function()
        if fb.status ~= 'stop' and utils.mode() == 'n' then
            updateFoldDebounced(bufnr, true)
        end
    end)
end

local function updatePendingFold(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = manager:get(bufnr)
    if not fb then
        return
    end
    promise.resolve():thenCall(function()
        if utils.mode() == 'n' and fb.status == 'pending' then
            updateFoldDebounced(bufnr)
        end
    end)
end

local function diffWinClosed()
    local winid = tonumber(fn.expand('<afile>')) or api.nvim_get_current_win()
    if utils.isWinValid(winid) and utils.isDiffFold(winid) then
        for _, id in ipairs(api.nvim_tabpage_list_wins(0)) do
            if winid ~= id and utils.isDiffFold(id) then
                local bufnr = api.nvim_win_get_buf(id)
                local fb = manager:get(bufnr)
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
    event:on('BufEnter', updatePendingFold, disposables)
    event:on('InsertLeave', updateFoldFlush, disposables)
    event:on('TextChanged', updateFoldDebounced, disposables)
    event:on('BufWritePost', updateFoldFlush, disposables)
    event:on('CmdlineLeave', updatePendingFold, disposables)
    event:on('WinClosed', diffWinClosed, disposables)
    event:on('BufAttach', Fold.attach, disposables)
    table.insert(disposables, manager:initialize(ns, config.provider_selector))
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
