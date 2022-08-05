local api = vim.api
local fn  = vim.fn
local cmd = vim.cmd

local promise    = require('promise')
local render     = require('ufo.render')
local utils      = require('ufo.utils')
local floatwin   = require('ufo.preview.floatwin')
local scrollbar  = require('ufo.preview.scrollbar')
local lsize      = require('ufo.model.linesize')
local keymap     = require('ufo.preview.keymap')
local event      = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local config     = require('ufo.config')
local log        = require('ufo.lib.log')
local bufmanager = require('ufo.bufmanager')

local initialized

---@class UfoPreview
local Preview = {
    winid = nil,
    bufnr = nil,
    lnum = nil,
    col = nil,
    topline = nil,
    foldedLnum = nil,
    keyMessages = nil
}

local function evaluateTopline(winid, line, lsizes)
    local topline
    local iStart, iEnd = line - 1, math.max(1, line - lsizes)
    local lsizeSum = 0
    local i = iStart
    local lsizeObj = lsize:new(winid)
    local len = lsizes - lsizeObj:fillSize(line)
    log.info('winid:', winid, 'line:', line, 'lsizes:', lsizes, 'len:', len)
    local size
    while lsizeSum < len and i >= iEnd do
        local lnum = utils.foldClosed(winid, i)
        log.info('lnum:', lnum, 'i:', i)
        if lnum == -1 then
            size = lsizeObj:size(i)
        else
            size = 1
            iEnd = math.max(1, iEnd + lnum - i)
            i = lnum
        end
        lsizeSum = lsizeSum + size
        log.info('size:', size, 'lsizeSum:', lsizeSum)
        topline = i
        i = i - 1
    end
    if not topline then
        topline = line
    end
    -- extraOff lines is need to be showed near the topline
    local topfill = lsizeObj:fillSize(topline)
    local extraOff = lsizeSum - len
    if extraOff > 0 then
        if topfill < extraOff then
            topline = topline + 1
        else
            topfill = topfill - extraOff
        end
    end
    log.info('topline:', topline, 'topfill:', topfill)
    return topline, topfill
end

function Preview:trace(bufnr)
    local floatWinid = floatwin.winid
    local fWinConfig = api.nvim_win_get_config(floatWinid)
    -- fWinConfig.row is a table value converted from a floating-point
    local wrow = tonumber(fWinConfig.row[vim.val_idx])
    if floatwin:borderHasUpLine() then
        wrow = wrow + 1
    end
    local fLnum, fCol, fWrow
    utils.winCall(floatWinid, function()
        local topline
        local winView = fn.winsaveview()
        fLnum, fCol, topline = winView.lnum, winView.col, winView.topline
        if bufnr == self.bufnr then
            fLnum = topline
        end
        fWrow = fLnum - topline
    end)
    api.nvim_set_current_win(self.winid)
    local lnum, col = api.nvim_win_get_cursor(self.winid)[1], fCol
    lnum = utils.foldClosed(0, lnum) + fLnum - 1
    local lineSize = fWrow + wrow
    cmd('norm! m`zO')
    local topline, topfill = evaluateTopline(self.winid, lnum, lineSize)
    fn.winrestview({
        lnum = lnum,
        col = col,
        topline = topline,
        topfill = topfill,
        curswant = utils.curswant(self.bufnr, lnum, col + 1)
    })
end

function Preview:scroll(char)
    if not self.validate() then
        return
    end
    utils.winCall(floatwin.winid, function()
        local ctrlTbl = {B = 0x02, D = 0x04, E = 0x05, F = 0x06, U = 0x15, Y = 0x19}
        cmd(('norm! %c'):format(ctrlTbl[char]))
        scrollbar:update()
    end)
end

local function onBufRemap(bufnr, str)
    local self = Preview
    if str == 'switch' then
        if bufnr == self.bufnr then
            api.nvim_set_current_win(floatwin.winid)
            vim.wo.cul = true
        else
            vim.wo.cul = false
            api.nvim_set_current_win(self.winid)
        end
    elseif str == 'trace' or str == '2click' then
        self:trace(bufnr)
    elseif str == 'close' then
        self:close()
    elseif str == 'scrollB' then
        self:scroll('B')
    elseif str == 'scrollF' then
        self:scroll('F')
    elseif str == 'scrollU' then
        self:scroll('U')
    elseif str == 'scrollD' then
        self:scroll('D')
    elseif str == 'scrollE' then
        self:scroll('E')
    elseif str == 'scrollY' then
        self:scroll('Y')
    elseif str == 'wheelUp' or str == 'wheelDown' then
        promise.resolve():thenCall(function()
            scrollbar:update()
        end)
    elseif str == 'onKey' then
        promise.resolve():thenCall(function()
            Preview:afterKey()
        end)
    end
end

function Preview:attach(bufnr, foldedLnum)
    local disposables = {}
    event:on('WinClosed', function()
        promise.resolve():thenCall(function()
            if not self.validate() then
                disposable.disposeAll(disposables)
                disposables = {}
                self.close()
            end
        end)
    end, disposables)
    event:on('onBufRemap', onBufRemap, disposables)
    event:emit('setOpenFoldHl', false)
    table.insert(disposables, disposable:create(function()
        event:emit('setOpenFoldHl')
    end))

    local winView = fn.winsaveview()
    self.winid = fn.bufwinid(bufnr)
    self.bufnr = bufnr
    self.lnum = winView.lnum
    self.col = winView.col
    self.topline = winView.topline
    self.foldedLnum = foldedLnum
    table.insert(disposables, disposable:create(function()
        self.winid = nil
        self.bufnr = nil
        self.lnum = nil
        self.col = nil
        self.topline = nil
        self.foldedLnum = nil
    end))
    table.insert(disposables, keymap:attach(bufnr, floatwin.bufnr, self.ns, self.keyMessages, {
        trace = self.keyMessages.trace,
        switch = self.keyMessages.switch,
        close = self.keyMessages.close,
        ['2click'] = '<2-LeftMouse>'
    }))
end

---
---@param maxHeight? number
---@param nextLineIncluded? boolean
---@param enter? boolean
---@return number? winid, number? bufnr
function Preview:peekFoldedLinesUnderCursor(maxHeight, nextLineIncluded, enter)
    local curBufnr = api.nvim_get_current_buf()
    local buf = bufmanager:get(curBufnr)
    if not buf then
        -- buffer is detached
        return
    end
    local lnum = api.nvim_win_get_cursor(0)[1]
    lnum = utils.foldClosed(0, lnum)
    if lnum == -1 then
        return
    end
    local endLnum = utils.foldClosedEnd(0, lnum)
    if floatwin.bufnr then
        api.nvim_buf_clear_namespace(floatwin.bufnr, self.ns, 0, -1)
    end
    if nextLineIncluded ~= false then
        endLnum = buf:lineCount() == endLnum and endLnum or (endLnum + 1)
    end
    local text = buf:lines(lnum, endLnum)
    local height = math.min(#text, maxHeight or 20)
    floatwin:display(api.nvim_get_current_win(), height, text, enter)
    utils.winCall(floatwin.winid, function()
        cmd('norm! ze')
    end)
    render.mapHighlightLimitByRange(curBufnr, floatwin.bufnr,
                                    {lnum - 1, 0}, {endLnum - 1, #text[endLnum - lnum + 1]},
                                    text, self.ns)
    promise.resolve():thenCall(function()
        scrollbar:display()
    end)
    self:attach(curBufnr, lnum)
    return floatwin.winid, floatwin.bufnr
end

function Preview.validate()
    local res = floatwin:validate()
    if floatwin.showScrollBar then
        res = res and scrollbar:validate()
    end
    return res
end

function Preview.close()
    floatwin:close()
    scrollbar:close()
end

function Preview.floatWinid()
    return floatwin.winid
end

function Preview:afterKey()
    local curWinid = api.nvim_get_current_win()
    if floatwin.winid == curWinid then
        local topline = fn.line('w0')
        if scrollbar.topline ~= topline then
            scrollbar:update(topline)
        end
        return
    end
    if curWinid == self.winid then
        local winView = fn.winsaveview()
        if self.topline ~= winView.topline or self.lnum ~= winView.lnum or
            self.col ~= winView.col then
            self.close()
        elseif self.foldedLnum ~= utils.foldClosed(self.winid, self.foldedLnum) then
            self.close()
        end
    else
        self.close()
    end
end

function Preview:initialize(namespace)
    if initialized then
        return
    end
    local conf = vim.deepcopy(config.preview)
    self.keyMessages = conf.mappings
    local disposables = {}
    table.insert(disposable, floatwin:initialize(namespace, conf.win_config))
    table.insert(disposables, scrollbar)
    self.ns = namespace
    self.disposables = disposables
    return self
end

function Preview:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
    initialized = false
end

return Preview
