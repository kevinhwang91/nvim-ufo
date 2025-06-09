local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local utils = require('ufo.utils')
local config = require('ufo.config')
local log = require('ufo.lib.log')
local disposable = require('ufo.lib.disposable')
local event = require('ufo.lib.event')

local window = require('ufo.model.window')
local fold = require('ufo.fold')
local render = require('ufo.render')

---@class UfoDecorator
---@field initialized boolean
---@field ns number
---@field hlNs number
---@field virtTextHandler? UfoFoldVirtTextHandler[]
---@field enableFoldEndVirtText boolean
---@field openFoldHlTimeout number
---@field openFoldHlEnabled boolean
---@field curWinid number
---@field lastWinid number
---@field virtTextHandlers table<number, function>
---@field winSessions table<number, UfoWindow>
---@field disposables UfoDisposable[]
local Decorator = {}

local collection
local bufnrSet
local namespaces
local handlerErrorMsg
local debounced

---@diagnostic disable-next-line: unused-local
local function onStart(name, tick)
    collection = {}
    bufnrSet = {}
    namespaces = {}
end

---@diagnostic disable-next-line: unused-local
local function onWin(name, winid, bufnr, topRow, botRow)
    local fb = fold.get(bufnr)
    if not fb or fb.foldedLineCount == 0 and not vim.wo[winid].foldenable or
        render.rendering(bufnr, winid) then
        -- vim.treesitter.highlighter._on_win will fire next redraw if parser done
        collection[winid] = nil
        return false
    end
    local self = Decorator
    local wses = self.winSessions[winid]
    wses:onWin(bufnr, fb, topRow, botRow)
    if bufnrSet[bufnr] == nil then
        collection[winid] = {}
    end
    bufnrSet[bufnr] = winid
end

---@diagnostic disable-next-line: unused-local
local function onLine(name, winid, bufnr, row)
    local rows = collection[winid]
    if rows then
        table.insert(rows, row)
    end
end

---@diagnostic disable-next-line: unused-local
local function onEnd(name, tick)
    local needRedraw = false
    local self = Decorator
    self.curWinid = api.nvim_get_current_win()
    for winid, rows in pairs(collection or {}) do
        if #rows > 0 then
            local wses = self.winSessions[winid]
            local fb, foldedPairs = wses.foldbuffer, wses.foldedPairs
            if self.curWinid == winid and not next(foldedPairs) then
                foldedPairs = self:computeFoldedPairs(rows)
            end
            local shared
            local didOpen = false
            for _, row in ipairs(rows) do
                local lnum = row + 1
                if not foldedPairs[lnum] and fb:lineIsClosed(lnum) then
                    if shared == nil then
                        local _, winids = utils.getWinByBuf(fb.bufnr)
                        shared = winids ~= nil
                    end
                    self:highlightOpenFold(fb, winid, lnum, shared)
                    didOpen = fb:openFold(lnum) or didOpen
                    if not shared then
                        needRedraw = didOpen or needRedraw
                    end
                end
            end
            if didOpen then
                fb:syncFoldedLines(winid)
            end
            local cursor = wses:cursor()
            local curLnum = cursor[1]
            local curFoldStart, curFoldEnd = 0, 0
            for fs, fe in pairs(foldedPairs) do
                local _, didClose = self:getVirtTextAndCloseFold(winid, fs, fe)
                if not utils.has10() then
                    needRedraw = needRedraw or didClose
                end
                if curFoldStart == 0 and fs <= curLnum and curLnum <= fe then
                    curFoldStart, curFoldEnd = fs, fe
                end
            end
            if not needRedraw then
                local lastCurLnum = wses.lastCurLnum
                local lastCurFoldStart, lastCurFoldEnd = wses.lastCurFoldStart, wses.lastCurFoldEnd
                if lastCurFoldStart ~= curFoldStart and
                    lastCurFoldStart < lastCurLnum and lastCurLnum <= lastCurFoldEnd and
                    lastCurFoldStart < curLnum and curLnum <= lastCurFoldEnd then
                    log.debug('Curosr under the stale fold range, should open fold.')
                    needRedraw = fb:openFold(lastCurFoldStart) or needRedraw
                end
            end
            local didHighlight = false
            if curLnum == curFoldStart then
                didHighlight = wses:setCursorFoldedLineHighlight()
            else
                didHighlight = wses:clearCursorFoldedLineHighlight()
            end
            needRedraw = needRedraw or didHighlight
            wses.lastCurFoldStart, wses.lastCurFoldEnd = curFoldStart, curFoldEnd
            wses.lastCurLnum = curLnum
        end
    end
    self.lastWinid = self.curWinid
    if needRedraw then
        log.debug('Need redraw.')
        if utils.has10() then
            api.nvim__redraw({valid = true, flush = true})
        else
            cmd('redraw')
        end
    end
    debounced()
end

local function silentOnEnd(...)
    local ok, msg = pcall(onEnd, ...)
    if not ok and (type(msg) ~= 'string' or not msg:match('Keyboard interrupt\n')) then
        error(msg, 0)
    end
end

function Decorator:resetCurosrFoldedLineHighlightByBuf(bufnr)
    -- TODO
    -- exit cmd window will throw E315: ml_get: invalid lnum: 1
    if api.nvim_buf_line_count(bufnr) == 0 then
        return
    end
    local id, winids = utils.getWinByBuf(bufnr)
    if id == -1 then
        return
    end
    for _, winid in ipairs(winids or {id}) do
        local wses = self.winSessions[winid]
        wses:clearCursorFoldedLineHighlight()
    end
end

function Decorator:highlightOpenFold(fb, winid, lnum, shared)
    if self.openFoldHlEnabled and winid == self.lastWinid and api.nvim_get_mode().mode ~= 'c' then
        local endLnum
        if not shared then
            local fl = fb:foldedLine(lnum)
            local _
            _, endLnum = fl:range()
            if endLnum == 0 then
                return
            end
        else
            endLnum = utils.foldClosedEnd(winid, lnum)
            if endLnum < 0 then
                return
            end
        end
        render.highlightLinesWithTimeout(shared and winid or fb.bufnr, 'UfoFoldedBg', self.hlNs,
            lnum, endLnum, self.openFoldHlTimeout, shared)
    end
end

function Decorator:computeFoldedPairs(rows)
    local lastRow = rows[1]
    local res = {}
    for i = 2, #rows do
        local lnum = lastRow + 1
        local curRow = rows[i]
        if curRow > lnum and utils.foldClosed(0, lnum) == lnum then
            res[lnum] = curRow
        end
        lastRow = curRow
    end

    local lnum = lastRow + 1
    if utils.foldClosed(0, lnum) == lnum then
        res[lnum] = utils.foldClosedEnd(0, lnum)
    end
    return res
end

function Decorator:getOtherNamespaces()
    if not next(namespaces) then
        for _, ns in pairs(api.nvim_get_namespaces()) do
            if self.ns ~= ns then
                table.insert(namespaces, ns)
            end
        end
    end
    return namespaces
end

function Decorator:removeStaleVirtText()
    local ok = false
    local bufs = {}
    local wins = api.nvim_list_wins()
    for _, winid in ipairs(wins) do
        local bufnr = api.nvim_win_get_buf(winid)
        if bufs[bufnr] then
            return false
        end
        bufs[bufnr] = true
    end
    for _, winid in ipairs(wins) do
        ---@type UfoWindow
        local wses = rawget(self.winSessions, winid)
        if wses and wses.foldbuffer then
            local fb, s, e = wses.foldbuffer, wses.topRow + 1, wses.botRow + 1
            ok = fb:openStaleFoldsByRange(s, e, self:getOtherNamespaces()) or ok
        end
    end
    return ok
end

function Decorator:getVirtTextAndCloseFold(winid, lnum, endLnum, doRender)
    local didClose = false
    local wses = self.winSessions[winid]
    if not wses then
        return {}, didClose
    end
    local bufnr, fb = wses.bufnr, wses.foldbuffer
    if endLnum then
        wses.foldedPairs[lnum] = endLnum
    end
    local ok, res = true, wses.foldedTextMaps[lnum]
    local fl = fb:foldedLine(lnum)
    local rendered = false
    if fl then
        if not res and not wses:textWidthChanged() then
            res = fl.virtText
        end
        rendered = fl:hasRendered()
    end
    if not res or not rendered then
        if not endLnum then
            endLnum = wses:foldEndLnum(lnum)
        end
        local text = fb:lines(lnum)[1]
        if not res then
            local handler = self:getVirtTextHandler(bufnr)
            local virtText
            local syntax = fb:syntax() ~= ''
            local concealLevel = wses:concealLevel()
            local nss = self:getOtherNamespaces()
            virtText = render.captureVirtText(bufnr, text, lnum, syntax, nss, concealLevel)
            local getFoldVirtText
            if self.enableGetFoldVirtText then
                getFoldVirtText = function(l)
                    local t = type(l)
                    assert(t == 'number', 'expected a number, got ' .. t)
                    assert(lnum <= l and l <= endLnum,
                        ('expected lnum range from %d to %d, got %d'):format(lnum, endLnum, l))
                    local line = fb:lines(l)[1]
                    return render.captureVirtText(bufnr, line, l, syntax, nss, concealLevel)
                end
            end
            local width = wses:textWidth()
            ok, res = pcall(handler, virtText, lnum, endLnum, width, utils.truncateStrByWidth, {
                bufnr = bufnr,
                winid = winid,
                text = text,
                get_fold_kind = function(l)
                    l = l == nil and lnum or l
                    local t = type(l)
                    assert(t == 'number', 'expected a number, got ' .. t)
                    return fb:lineKind(winid, l)
                end,
                get_fold_virt_text = getFoldVirtText
            })
            if not ok then
                log.error(res)
                res = {{handlerErrorMsg, 'Error'}}
            end
            wses.foldedTextMaps[lnum] = res
        end
        if bufnrSet[bufnr] == winid then
            if (doRender == nil or doRender == true) then
                if ok then
                    log.debug('Window:', winid, 'need add/update folded lnum:', lnum)
                    didClose = true
                end
                local nss = self:getOtherNamespaces()
                fb:closeFold(lnum, endLnum, res, nss)
            elseif ok then
                log.debug('Window:', winid, 'will add/update folded lnum:', lnum)
            end
        end
    end
    return res, didClose
end

---@diagnostic disable-next-line: unused-local
function Decorator.defaultVirtTextHandler(virtText, lnum, endLnum, width, truncate, ctx)
    local newVirtText = {}
    local suffix = ' ⋯ '
    local sufWidth = fn.strdisplaywidth(suffix)
    local targetWidth = width - sufWidth
    local curWidth = 0
    for _, chunk in ipairs(virtText) do
        local chunkText = chunk[1]
        local chunkWidth = fn.strdisplaywidth(chunkText)
        if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
        else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            local hlGroup = chunk[2]
            table.insert(newVirtText, {chunkText, hlGroup})
            chunkWidth = fn.strdisplaywidth(chunkText)
            -- str width returned from truncate() may less than 2nd argument, need padding
            if curWidth + chunkWidth < targetWidth then
                suffix = suffix .. (' '):rep(targetWidth - curWidth - chunkWidth)
            end
            break
        end
        curWidth = curWidth + chunkWidth
    end
    table.insert(newVirtText, {suffix, 'UfoFoldedEllipsis'})
    return newVirtText
end

function Decorator:setVirtTextHandler(bufnr, handler)
    bufnr = bufnr or api.nvim_get_current_buf()
    self.virtTextHandlers[bufnr] = handler
end

---
---@param bufnr number
---@return UfoFoldVirtTextHandler
function Decorator:getVirtTextHandler(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    return self.virtTextHandlers[bufnr]
end

---
---@param namespace number
---@return UfoDecorator
function Decorator:initialize(namespace)
    if self.initialized then
        return self
    end
    self.initialized = true
    api.nvim_set_decoration_provider(namespace, {
        on_start = onStart,
        on_win = onWin,
        on_line = onLine,
        on_end = silentOnEnd
    })
    self.ns = namespace
    self.hlNs = self.hlNs or api.nvim_create_namespace('')
    self.disposables = {}
    table.insert(self.disposables, disposable:create(function()
        self.initialized = false
        api.nvim_set_decoration_provider(namespace, {})
        for bufnr in ipairs(fold.buffers()) do
            self:resetCurosrFoldedLineHighlightByBuf(bufnr)
        end
    end))
    self.enableGetFoldVirtText = config.enable_get_fold_virt_text
    self.openFoldHlTimeout = config.open_fold_hl_timeout
    self.openFoldHlEnabled = self.openFoldHlTimeout > 0
    event:on('SetOpenFoldHl', function(val)
        if type(val) == 'boolean' then
            self.openFoldHlEnabled = val
        else
            self.openFoldHlEnabled = self.openFoldHlTimeout > 0
        end
    end, self.disposables)
    event:on('RenderHold', function()
        if self:removeStaleVirtText() then
            log.debug('Redraw in debounced function.')
            cmd('redraw!')
        end
    end, self.disposables)
    local virtTextHandler = config.fold_virt_text_handler or self.defaultVirtTextHandler
    self.virtTextHandlers = setmetatable({}, {
        __index = function(tbl, bufnr)
            rawset(tbl, bufnr, virtTextHandler)
            return virtTextHandler
        end
    })
    debounced = require('ufo.lib.debounce')(function()
        event:emit('RenderHold')
    end, 500)
    handlerErrorMsg = ([[!Error in user's handler, check out `%s`]]):format(log.path)
    self.winSessions = setmetatable({}, {
        __index = function(tbl, winid)
            local o = window:new(winid)
            rawset(tbl, winid, o)
            return o
        end
    })
    event:on('WinClosed', function(winid)
        self.winSessions[winid] = nil
    end, self.disposables)
    event:on('BufDetach', function(bufnr)
        self:resetCurosrFoldedLineHighlightByBuf(bufnr)
        self.virtTextHandlers[bufnr] = nil
    end, self.disposables)
    return self
end

function Decorator:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

return Decorator
