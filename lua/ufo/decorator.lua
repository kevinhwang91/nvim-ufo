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

local initialized

---@class UfoDecorator
---@field ns number
---@field hlNs number
---@field virtTextHandler? UfoFoldVirtTextHandler[]
---@field enableFoldEndVirtText boolean
---@field openFoldHlTimeout number
---@field openFoldHlEnabled boolean
---@field disposables table
local Decorator = {}

local collection
local redrawType
local bufnrSet
local lastContext

---@diagnostic disable-next-line: unused-local
local function onStart(name, tick, redrawT)
    redrawType = redrawT
    collection = {}
    bufnrSet = {}
end

---@diagnostic disable-next-line: unused-local
local function onWin(name, winid, bufnr, topRow, botRow)
    if bufnrSet[bufnr] or not fold.get(bufnr) or not vim.wo[winid].foldenable then
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
    local nss, mode
    local needRedraw = nil
    local ctx = {}
    local self = Decorator
    for winid, data in pairs(collection or {}) do
        local bufnr = data.bufnr
        local fb = fold.get(bufnr)
        if #data.rows > 0 then
            utils.winCall(winid, function()
                local folded = self:unHandledFoldedLnums(fb, data.rows)
                log.debug('unhandled folded lnum:', folded)
                if #folded == 0 then
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
                        needRedraw = 1
                        log.debug('need add/update folded lnum:', lnum)
                        local endLnum = utils.foldClosedEnd(0, lnum)

                        local handler = self:getVirtTextHandler(bufnr)
                        local virtTexts = config.enable_on_demand_virt_texts
                            and setmetatable({}, {
                                __index = function(_, _lnum)
                                    assert(lnum <= _lnum and _lnum <= endLnum, "Index out of folded range: " .. _lnum)
                                    local _text = fb:lines(_lnum)[1]
                                    return render.getVirtText(bufnr, _text, width, _lnum, syntax, nss)
                                end,
                            })
                            or render.getVirtText(bufnr, text, width, lnum, syntax, nss)
                        local endVirtText
                        if self.enableFoldEndVirtText then
                            local endText = fb:lines(endLnum)[1]
                            endVirtText = render.getVirtText(bufnr, endText, width, endLnum, syntax, nss)
                        end
                        local virtText = handler(virtTexts, lnum, endLnum, width, utils.truncateStrByWidth, {
                            bufnr = bufnr,
                            winid = winid,
                            text = text,
                            end_virt_text = endVirtText
                        })
                        fb:closeFold(lnum, endLnum, text, virtText, width)
                    end
                end
            end)
        end
        local lnum = api.nvim_win_get_cursor(winid)[1]
        if redrawType == 40 then
            local lastCtx = lastContext[bufnr] or {}
            if winid == lastCtx.winid and lnum == lastCtx.lnum then
                mode = mode and mode or utils.mode()
                if mode == 'n' then
                    fb:syncFoldedLines(winid)
                    needRedraw = needRedraw and 3 or 2
                end
            end
        end
        ctx[bufnr] = {lnum = lnum, winid = winid}
    end
    if needRedraw then
        log.debug('need redraw, type:', needRedraw)
        cmd('redraw')
    end
    collection = nil
    bufnrSet = nil
    lastContext = ctx
end

function Decorator:highlightOpenFold(fb, lnum)
    if self.openFoldHlEnabled then
        local fl = fb:foldedLine(lnum)
        local _, endLnum = fl:range()
        utils.highlightTimeout(fb.bufnr, self.hlNs, 'UfoFoldedBg', lnum - 1, endLnum,
                               nil, self.openFoldHlTimeout)
    end
end

function Decorator:unHandledFoldedLnums(fb, rows)
    local lastRow = rows[1]
    local folded = {}
    for i = 2, #rows do
        local lnum = lastRow + 1
        if rows[i] > lnum then
            if utils.foldClosed(0, lnum) == lnum then
                table.insert(folded, lnum)
            end
        elseif fb:lineIsClosed(lnum) then
            self:highlightOpenFold(fb, lnum)
            fb:openFold(lnum)
        end
        lastRow = rows[i]
    end

    local lnum = lastRow + 1
    if utils.foldClosed(0, lnum) == lnum then
        table.insert(folded, lnum)
    elseif fb:lineIsClosed(lnum) then
        self:highlightOpenFold(fb, lnum)
        fb:openFold(lnum)
    end
    return folded
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
    if initialized then
        return self
    end
    local disposables = {}
    api.nvim_set_decoration_provider(namespace, {
        on_start = onStart,
        on_win = onWin,
        on_line = onLine,
        on_end = onEnd
    })
    self.ns = namespace
    self.hlNs = api.nvim_create_namespace('ufo-hl')

    table.insert(disposables, disposable:create(function()
        api.nvim_set_decoration_provider(namespace, {})
    end))
    self.enableFoldEndVirtText = config.enable_fold_end_virt_text
    self.openFoldHlTimeout = config.open_fold_hl_timeout
    self.openFoldHlEnabled = self.openFoldHlTimeout > 0
    event:on('setOpenFoldHl', function(val)
        if type(val) == 'boolean' then
            self.openFoldHlEnabled = val
        else
            self.openFoldHlEnabled = self.openFoldHlTimeout > 0
        end
    end, disposables)

    local virtTextHandler = config.fold_virt_text_handler or self.defaultVirtTextHandler
    self.virtTextHandlers = setmetatable({}, {
        __index = function(tbl, bufnr)
            rawset(tbl, bufnr, virtTextHandler)
            return virtTextHandler
        end
    })
    event:on('BufDetach', function(bufnr)
        self.virtTextHandlers[bufnr] = nil
    end, disposables)
    self.disposables = disposables
    lastContext = {}
    initialized = true
    return self
end

function Decorator:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
    initialized = false
end

return Decorator
