local api = vim.api
local fn  = vim.fn
local cmd = vim.cmd

local utils      = require('ufo.utils')
local config     = require('ufo.config')
local log        = require('ufo.lib.log')
local disposable = require('ufo.lib.disposable')

local foldbuffer = require('ufo.fold.buffer')
local render = require('ufo.render')

local initialized

---@class UfoDecorator
---@field ns number
---@field virtTextHandler? function[]
---@field disposables table
local Decorator = {}

local collection
local redrawType
local bufnrSet

local function unHandledFoldedLnums(fb, rows)
    local lastRow = rows[1]
    local folded = {}
    for i = 2, #rows do
        local lnum = lastRow + 1
        if rows[i] > lnum then
            if utils.foldClosed(0, lnum) == lnum then
                table.insert(folded, lnum)
            end
        elseif fb:hasClosed(lnum) then
            fb:openFold(lnum)
        end
        lastRow = rows[i]

    end

    local lnum = lastRow + 1
    if utils.foldClosed(0, lnum) == lnum then
        table.insert(folded, lnum)
    elseif fb:hasClosed(lnum) then
        fb:openFold(lnum)
    end
    return folded
end

---@diagnostic disable-next-line: unused-local
local function onStart(name, tick, redrawT)
    redrawType = redrawT
    collection = {}
    bufnrSet = {}
end

---@diagnostic disable-next-line: unused-local
local function onWin(name, winid, bufnr, topRow, botRow)
    local fb = foldbuffer:get(bufnr)
    if bufnrSet[bufnr] or not fb or not vim.wo[winid].foldenable then
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
    for winid, data in pairs(collection or {}) do
        local bufnr = data.bufnr
        local fb = foldbuffer:get(bufnr)
        if #data.rows > 0 then
            utils.winCall(winid, function()
                local folded = unHandledFoldedLnums(fb, data.rows)
                log.debug('folded:', folded)
                if #folded == 0 then
                    return
                end
                local textoff = utils.textoff(winid)
                local width = api.nvim_win_get_width(winid) - textoff
                local syntax = vim.bo[bufnr].syntax ~= ''
                if not nss then
                    nss = {}
                    for _, ns in pairs(api.nvim_get_namespaces()) do
                        if Decorator.ns ~= ns then
                            table.insert(nss, ns)
                        end
                    end
                end
                for i = 1, #folded do
                    local lnum = folded[i]
                    if not fb:hasClosed(lnum) or fb:foldedLineWidthChanged(lnum, width) then
                        needRedraw = 1
                        log.debug('need add/update folded:', lnum)
                        local endLnum = utils.foldClosedEnd(0, lnum)
                        local text = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
                        local handler = Decorator:getVirtTextHandler(bufnr)
                        local virtText = render.getVirtText(bufnr, text, width, lnum, syntax, nss)
                        virtText = handler(virtText, lnum, endLnum, width, utils.truncateStrByWidth, {
                            bufnr = bufnr,
                            winid = winid,
                            text = text
                        })
                        fb:closeFold(lnum, endLnum, virtText, width)
                    end
                end
            end)
        end
        local lnum = api.nvim_win_get_cursor(winid)[1]
        if redrawType == 40 then
            if winid == fb.winid and lnum == fb.lnum then
                mode = mode and mode or utils.mode()
                if mode == 'n' then
                    fb:synchronize(winid)
                    needRedraw = needRedraw and 3 or 2
                end
            end
        end
        fb.lnum = lnum
        fb.winid = winid
    end
    if needRedraw then
        log.debug('need redraw, type:', needRedraw)
        cmd('redraw')
    end
    collection = nil
    bufnrSet = nil
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

    table.insert(disposables, disposable:create(function()
        api.nvim_set_decoration_provider(namespace, {})
    end))
    local virtTextHandler = config.fold_virt_text_handler or self.defaultVirtTextHandler
    -- TODO
    -- how to clean up the wipeouted buffer, need refactor
    self.virtTextHandlers = setmetatable({}, {
        __index = function(tbl, bufnr)
            rawset(tbl, bufnr, virtTextHandler)
            return virtTextHandler
        end
    })
    self.disposables = disposables
    require('ufo.render')
    initialized = true
    return self
end

function Decorator:dispose()
    for _, item in ipairs(self.disposables) do
        item:dispose()
    end
    initialized = false
end

return Decorator
