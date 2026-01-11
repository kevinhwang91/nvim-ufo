local api = vim.api
local cmd = vim.cmd

local config = require('ufo.config')
local promise = require('promise')
local async = require('async')
local utils = require('ufo.utils')
local provider = require('ufo.provider')
local log = require('ufo.lib.log')
local event = require('ufo.lib.event')
local manager = require('ufo.fold.manager')
local disposable = require('ufo.lib.disposable')

---@class UfoFold
---@field initialized boolean
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
        if not utils.isWinValid(winid) or utils.isDiffOrMarkerFold(winid) then
            return
        end
        await(Fold.update(bufnr))
    end)
end

local function setFoldText(bufnr)
    if not config.override_foldtext then
        return
    end
    local winid = utils.getWinByBuf(bufnr)
    if not utils.isWinValid(winid) then
        return
    end
    utils.winCall(winid, function()
        cmd([[
            setl foldtext=v:lua.require'ufo.main'.foldtext()
            setl fillchars+=fold:\ ]])
    end)
end

function Fold.update(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = manager:get(bufnr)
    if not fb then
        return promise.resolve()
    end
    if manager:isFoldMethodsDisabled(fb) then
        if not pcall(fb.getRangesFromExtmarks, fb) then
            fb:resetFoldedLines(true)
        end
        return promise.resolve()
    end
    if fb.status == 'pending' and manager:applyFoldRanges(bufnr) ~= -1 then
        return promise.resolve()
    end

    local changedtick, ft, bt = fb:changedtick(), fb:filetype(), fb:buftype()
    fb:acquireRequest()

    local function dispose(resolved)
        ---@diagnostic disable-next-line: redefined-local
        local fb = manager:get(bufnr)
        if not fb then
            return false
        end
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

    log.info('providers:', fb.providers)
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
        fb.status = manager:applyFoldRanges(bufnr, ranges) == -1 and 'pending' or 'start'
    end, function(err)
        if not dispose(false) then
            return
        end
        return promise.reject(err)
    end)
end

---
---@param bufnr number
function Fold.get(bufnr)
    return manager:get(bufnr)
end

function Fold.buffers()
    return manager.buffers
end

function Fold.apply(bufnr, ranges, manual)
    return manager:applyFoldRanges(bufnr, ranges, manual)
end

function Fold.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if not manager:attach(bufnr) then
        return
    end
    log.debug('attach bufnr:', bufnr)
    setFoldText(bufnr)
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

local function handleDiffMode(winid, new, old)
    if old == new then
        return
    end
    if not utils.has10() then
        new, old = new == '1', old == '1'
    end
    if not new then
        local bufnr = api.nvim_win_get_buf(winid)
        local fb = manager:get(bufnr)

        if fb then
            fb:resetFoldedLines(true)

            -- TODO
            -- buffer go back normal mode from diff mode will disable `foldenable` if the foldmethod was
            -- `manual` before entering diff mode. Unfortunately, foldmethod will always be `manual` if
            -- enable ufo, `foldenable` will be disabled.

            -- `set foldenable` forcedly, feel free to open an issue if ufo is evil.
            promise.resolve():thenCall(function()
                if utils.isWinValid(winid) and vim.wo[winid].foldmethod == 'manual' then
                    utils.winCall(winid, function()
                        cmd('silent! %foldopen!')
                    end)
                    vim.wo[winid].foldenable = true
                end
            end)
            tryUpdateFold(bufnr)
        end
    end
end

---
---@param ns number
---@return UfoFold
function Fold:initialize(ns)
    if self.initialized then
        return self
    end
    self.initialized = true
    self.disposables = {}
    table.insert(self.disposables, disposable:create(function()
        self.initialized = false
    end))
    event:on('BufWinEnter', function(bufnr)
        bufnr = bufnr or api.nvim_get_current_buf()
        local fb = manager:get(bufnr)
        if not fb then
            return
        end
        setFoldText(bufnr)
        updateFoldDebounced(bufnr, true, true)
    end, self.disposables)
    event:on('BufWritePost', function(bufnr)
        updateFoldDebounced(bufnr, true)
    end, self.disposables)
    event:on('TextChanged', updateFoldDebounced, self.disposables)
    event:on('ModeChangedToNormal', function(bufnr, oldMode)
        local onlyPending = oldMode ~= 'i' and oldMode ~= 't'
        updateFoldDebounced(bufnr, true, onlyPending)
    end, self.disposables)
    event:on('BufAttach', Fold.attach, self.disposables)
    event:on('DiffModeChanged', handleDiffMode, self.disposables)
    table.insert(self.disposables, manager:initialize(ns, config.provider_selector,
        config.close_fold_kinds_for_ft, config.close_fold_current_line_for_ft))
    return self
end

function Fold:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

return Fold
