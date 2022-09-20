local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local config     = require('ufo.config')
local promise    = require('promise')
local async      = require('async')
local utils      = require('ufo.utils')
local provider   = require('ufo.provider')
local log        = require('ufo.lib.log')
local event      = require('ufo.lib.event')
local manager    = require('ufo.fold.manager')
local disposable = require('ufo.lib.disposable')

local initialized

---@class UfoFold
---@field disposables UfoDisposable[]
local Fold = {}

local updateFoldDebounced

---@param bufnr number
---@return Promise
local function tryUpdateFold(bufnr)
    return async(function()
        local winid = utils.getWinByBuf(bufnr)
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

local function setFoldText()
    cmd([[
        setl foldtext=v:lua.require'ufo.main'.foldtext()
        setl fillchars+=fold:\ ]])
end

function Fold.update(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = manager:get(bufnr)
    if not fb then
        return promise.resolve()
    end
    fb.status = 'start'
    if manager:isFoldMethodsDisabled(fb) then
        if not pcall(fb.getRangesFromExtmarks, fb) then
            fb:resetFoldedLines(true)
        end
        return promise.resolve()
    end
    local winid = utils.getWinByBuf(bufnr)
    if winid == -1 then
        fb.status = 'pending'
        return promise.resolve()
    elseif not vim.wo[winid].foldenable or utils.isDiffOrMarkerFold(winid) then
        return promise.resolve()
    end
    if manager:applyFoldRanges(bufnr) then
        return promise.resolve()
    end

    local changedtick, ft, bt = fb:changedtick(), fb:filetype(), fb:buftype()
    fb:acquireRequest()

    local function dispose(resolved)
        fb:releaseRequest()
        local ok = ft == fb:filetype() and bt == fb:buftype()
        if ok then
            if resolved then
                ok = changedtick == fb:changedtick()
            end
        end
        local requested = fb:requested()
        if not ok and not requested then
            log.debug('update fold again for bufnr:', bufnr)
            updateFoldDebounced(bufnr)
        end
        return ok and not requested
    end

    return provider:requestFoldingRange(fb.providers, bufnr):thenCall(function(res)
        if not dispose(true) then
            return
        end
        local selected, ranges = res[1], res[2]
        fb.selectedProvider = type(selected) == 'string' and selected or 'external'
        log.info('selected provider:', fb.selectedProvider)
        if not ranges or #ranges == 0 or not utils.isBufLoaded(bufnr) then
            return
        end
        manager:applyFoldRanges(bufnr, ranges)
    end, function(err)
        if not dispose(false) then
            return
        end
        promise.reject(err)
    end)
end

---
---@param bufnr number
function Fold.get(bufnr)
    return manager:get(bufnr)
end

function Fold.apply(bufnr, ranges)
    return manager:applyFoldRanges(bufnr, ranges)
end

function Fold.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if not manager:attach(bufnr) then
        return
    end
    log.debug('attach bufnr:', bufnr)
    setFoldText()
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
    return function(bufnr, flush, onlyPending)
        bufnr = bufnr or api.nvim_get_current_buf()
        local fb = manager:get(bufnr)
        if not fb or utils.mode() ~= 'n' or
            onlyPending and fb.status ~= 'pending' or fb.status == 'stop' then
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

local function updatePendingFold(bufnr)
    promise.resolve():thenCall(function()
        updateFoldDebounced(bufnr, true, true)
    end)
end

local function diffWinClosed(winid)
    winid = winid or api.nvim_get_current_win()
    if utils.isWinValid(winid) and utils.isDiffFold(winid) then
        for _, id in ipairs(api.nvim_tabpage_list_wins(0)) do
            if winid ~= id and utils.isDiffFold(id) then
                local bufnr = api.nvim_win_get_buf(id)
                local fb = manager:get(bufnr)
                if fb then
                    fb:resetFoldedLines(true)
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
    event:on('BufEnter', function(bufnr)
        bufnr = bufnr or api.nvim_get_current_buf()
        local fb = manager:get(bufnr)
        if not fb then
            return
        end
        setFoldText()
        updatePendingFold(bufnr)
    end, disposables)
    event:on('InsertLeave', function(bufnr)
        updateFoldDebounced(bufnr, true)
    end, disposables)
    event:on('BufWritePost', function(bufnr)
        updateFoldDebounced(bufnr, true)
    end, disposables)
    event:on('TextChanged', updateFoldDebounced, disposables)
    event:on('CmdlineLeave', updatePendingFold, disposables)
    event:on('WinClosed', diffWinClosed, disposables)
    event:on('BufAttach', Fold.attach, disposables)
    table.insert(disposables, manager:initialize(ns, config.provider_selector,
                                                 config.close_fold_kinds))
    self.disposables = disposables
    initialized = true
    return self
end

function Fold:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
    initialized = false
end

return Fold
