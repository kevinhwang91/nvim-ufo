local api = vim.api
local fn  = vim.fn
local cmd = vim.cmd

local utils      = require('ufo.utils')
local config     = require('ufo.config')
local log        = require('ufo.lib.log')
local disposable = require('ufo.lib.disposable')
local event      = require('ufo.lib.event')

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
---@field winSessionTbl table<number, table>
---@field disposables UfoDisposable
local Decorator = {}

local collection
local bufnrSet
local handlerErrorMsg

---@diagnostic disable-next-line: unused-local
local function onStart(name, tick)
    collection = {}
    bufnrSet = {}
end

---@diagnostic disable-next-line: unused-local
local function onWin(name, winid, bufnr, topRow, botRow)
    if api.nvim_get_current_buf() == bufnr then
        if api.nvim_get_current_win() ~= winid then
            return false
        end
    end
    local fb = fold.get(bufnr)
    if bufnrSet[bufnr] or not fb or fb.foldedLineCount == 0 and not vim.wo[winid].foldenable then
        collection[winid] = nil
        return false
    end
    collection[winid] = {
        winid = winid,
        bufnr = bufnr,
        rows = {}
    }
    bufnrSet[bufnr] = true
end

---@diagnostic disable-next-line: unused-local
local function onLine(name, winid, bufnr, row)
    table.insert(collection[winid].rows, row)
end

---@diagnostic disable-next-line: unused-local
local function onEnd(name, tick)
    local nss
    local needRedraw = false
    local self = Decorator
    self.curWinid = api.nvim_get_current_win()
    for winid, data in pairs(collection or {}) do
        if #data.rows > 0 then
            local bufnr = data.bufnr
            local fb = fold.get(bufnr)
            utils.winCall(winid, function()
                local folded
                folded, needRedraw = self:computeFoldedLnums(fb, winid, data.rows)
                log.debug('folded lnums:', folded, 'didOpen:', needRedraw)
                if #folded == 0 then
                    self:clearCursorFoldedLineHighlight(bufnr, winid)
                    return
                end
                local textoff = utils.textoff(winid)
                local width = api.nvim_win_get_width(winid) - textoff
                local syntax = vim.bo[bufnr].syntax ~= ''
                if not nss then
                    nss = {}
                    for _, ns in pairs(api.nvim_get_namespaces()) do
                        if self.ns ~= ns then
                            table.insert(nss, ns)
                        end
                    end
                end
                for i = 1, #folded do
                    local lnum = folded[i]
                    if fb:lineNeedRender(lnum, width) then
                        local text = fb:lines(lnum)[1]
                        needRedraw = true
                        log.debug('need add/update folded lnum:', lnum)
                        local endLnum = utils.foldClosedEnd(0, lnum)
                        local handler = self:getVirtTextHandler(bufnr)
                        local limitedText = utils.truncateStrByWidth(text, width)
                        local virtText = render.captureVirtText(bufnr, limitedText, lnum, syntax, nss)
                        local getFoldVirtText
                        if self.enableGetFoldVirtText then
                            getFoldVirtText = function(l)
                                assert(type(l) == 'number', 'expected a number, got ' .. type(l))
                                assert(lnum <= l and l <= endLnum,
                                       ('expected lnum range from %d to %d, got %d'):format(lnum, endLnum, l))
                                local line = fb:lines(l)[1]
                                return render.captureVirtText(bufnr, line, l, syntax, nss)
                            end
                        end
                        local endVirtText
                        if self.enableFoldEndVirtText then
                            local endText = fb:lines(endLnum)[1]
                            endVirtText = render.captureVirtText(bufnr, endText, endLnum, syntax, nss)
                        end
                        local ok, res = pcall(handler, virtText, lnum, endLnum, width,
                            utils.truncateStrByWidth, {
                                bufnr = bufnr,
                                winid = winid,
                                text = text,
                                end_virt_text = endVirtText,
                                get_fold_virt_text = getFoldVirtText
                            })
                        if ok then
                            fb:closeFold(lnum, endLnum, text, res, width)
                        else
                            fb:closeFold(lnum, endLnum, text, {{handlerErrorMsg, 'Error'}}, width)
                            log.error(res)
                        end
                    end
                end
                local cursor = api.nvim_win_get_cursor(winid)
                local curLnum = cursor[1]
                if fb:lineIsClosed(curLnum) then
                    self:setCursorFoldedLineHighlight(bufnr, winid, curLnum)
                else
                    self:clearCursorFoldedLineHighlight(bufnr, winid)
                end
            end)
            self.winSessionTbl[winid].bufnr = bufnr
        end
    end
    if needRedraw then
        cmd('redraw')
    end
    collection = nil
    bufnrSet = nil
    self.lastWinid = self.curWinid
end

function Decorator:setCursorFoldedLineHighlight(bufnr, winid, curLnum)
    local session = self.winSessionTbl[winid]
    if session.bufnr ~= bufnr or session.curFoldedLine == 0 then
        local winhl = vim.wo[winid].winhl
        if not winhl:find('UfoCursorFoldedLine', 1, true) then
            cmd('setl winhl+=CursorLine:UfoCursorFoldedLine')
        end
        session.curFoldedLine = curLnum
    end
end

function Decorator:clearCursorFoldedLineHighlight(bufnr, winid)
    local session = self.winSessionTbl[winid]
    if session.bufnr ~= bufnr or session.curFoldedLine > 0 then
        local winhl = vim.wo[winid].winhl
        if winhl:find('UfoCursorFoldedLine', 1, true) then
            cmd('setl winhl-=CursorLine:UfoCursorFoldedLine')
        end
        session.curFoldedLine = 0
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
        utils.winCall(winid, function()
            self:clearCursorFoldedLineHighlight(bufnr, winid)
        end)
        self.winSessionTbl[winid].curFoldedLine = 0
    end
end

function Decorator:highlightOpenFold(fb, winid, lnum)
    if self.openFoldHlEnabled and winid == self.lastWinid and api.nvim_get_mode().mode ~= 'c' then
        local fl = fb:foldedLine(lnum)
        local _, endLnum = fl:range()
        local _, winids = utils.getWinByBuf(fb.bufnr)
        local shared = winids ~= nil
        render.highlightLinesWithTimeout(shared and winid or fb.bufnr, 'UfoFoldedBg', self.hlNs,
                                         lnum, endLnum, self.openFoldHlTimeout, shared)
    end
end

function Decorator:computeFoldedLnums(fb, winid, rows)
    local lastRow = rows[1]
    local folded = {}
    local didOpen = false
    for i = 2, #rows do
        local lnum = lastRow + 1
        if rows[i] > lnum then
            if utils.foldClosed(0, lnum) == lnum then
                table.insert(folded, lnum)
            end
        elseif fb:lineIsClosed(lnum) then
            self:highlightOpenFold(fb, winid, lnum)
            didOpen = fb:openFold(lnum) or didOpen
        end
        lastRow = rows[i]
    end

    local lnum = lastRow + 1
    if utils.foldClosed(0, lnum) == lnum then
        table.insert(folded, lnum)
    elseif fb:lineIsClosed(lnum) then
        self:highlightOpenFold(fb, winid, lnum)
        didOpen = fb:openFold(lnum) or didOpen
    end

    if didOpen then
        fb:syncFoldedLines(winid)
    end
    return folded, didOpen
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
        on_end = onEnd
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
    ---@deprecated
    ---@diagnostic disable-next-line: undefined-field
    self.enableFoldEndVirtText = config.enable_fold_end_virt_text
    if self.enableFoldEndVirtText ~= nil then
        vim.notify('`enable_fold_end_virt_text` is deprecated, ' ..
            'please use `enable_get_fold_virt_text` instead and refer to `doc/example.lua` to use.',
            vim.log.levels.WARN)
    end
    self.openFoldHlTimeout = config.open_fold_hl_timeout
    self.openFoldHlEnabled = self.openFoldHlTimeout > 0
    event:on('setOpenFoldHl', function(val)
        if type(val) == 'boolean' then
            self.openFoldHlEnabled = val
        else
            self.openFoldHlEnabled = self.openFoldHlTimeout > 0
        end
    end, self.disposables)

    local virtTextHandler = config.fold_virt_text_handler or self.defaultVirtTextHandler
    self.virtTextHandlers = setmetatable({}, {
        __index = function(tbl, bufnr)
            rawset(tbl, bufnr, virtTextHandler)
            return virtTextHandler
        end
    })
    handlerErrorMsg = ([[!Error in user's handler, check out `%s`]]):format(log.path)
    self.winSessionTbl = setmetatable({}, {
        __index = function(tbl, winid)
            local res = {
                bufnr = 0,
                curFoldedLine = 0
            }
            rawset(tbl, winid, res)
            return res
        end
    })
    event:on('WinClosed', function(winid)
        self.winSessionTbl[winid] = nil
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
