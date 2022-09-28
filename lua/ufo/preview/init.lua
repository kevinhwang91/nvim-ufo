local api = vim.api
local fn  = vim.fn
local cmd = vim.cmd

local promise    = require('promise')
local render     = require('ufo.render')
local utils      = require('ufo.utils')
local floatwin   = require('ufo.preview.floatwin')
local scrollbar  = require('ufo.preview.scrollbar')
local keymap     = require('ufo.preview.keymap')
local event      = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local config     = require('ufo.config')
local fold       = require('ufo.fold')

local initialized

---@class UfoPreview
local Preview = {
    detachDisposables = nil,
    winid = nil,
    bufnr = nil,
    lnum = nil,
    col = nil,
    topline = nil,
    foldedLnum = nil,
    keyMessages = nil
}

function Preview:trace(bufnr)
    local floatWinid = floatwin.winid
    local fWinConfig = api.nvim_win_get_config(floatWinid)
    -- fWinConfig.row is a table value converted from a floating-point
    local wrow = tonumber(fWinConfig.row[vim.val_idx])
    if fWinConfig.anchor == 'SW' then
        wrow = wrow - fWinConfig.height
        if wrow < 0 then
            wrow = floatwin:borderHasUpLine() and 1 or 0
        else
            if floatwin:borderHasBottomLine() then
                wrow = wrow - 1
            end
        end
    else
        if floatwin:borderHasUpLine() then
            wrow = wrow + 1
        end
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
    local startLnum = utils.foldClosed(0, lnum)
    local fb = fold.get(self.bufnr)
    if fb then
        fb:openFold(startLnum)
    end
    local lineSize = fWrow + wrow
    cmd('norm! m`zO')
    lnum = startLnum + fLnum - 1
    local topline, topfill = utils.evaluateTopline(self.winid, lnum, lineSize)
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
    self:detach()
    local disposables = {}
    event:on('WinClosed', function()
        promise.resolve():thenCall(function()
            if not self.validate() then
                self:detach()
                self.close()
            end
        end)
    end, disposables)
    event:on('onBufRemap', onBufRemap, disposables)
    event:emit('setOpenFoldHl', false)
    table.insert(disposables, disposable:create(function()
        event:emit('setOpenFoldHl')
    end))

    self.winid = utils.getWinByBuf(bufnr)
    local winView = utils.winCall(self.winid, fn.winsaveview)
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
        self.detachDisposables = nil
    end))
    table.insert(disposables, keymap:attach(bufnr, floatwin.bufnr, self.ns, self.keyMessages, {
        trace = self.keyMessages.trace,
        switch = self.keyMessages.switch,
        close = self.keyMessages.close,
        ['2click'] = '<2-LeftMouse>'
    }))
    self.detachDisposables = disposables
end

function Preview:detach()
    if self.detachDisposables then
        disposable.disposeAll(self.detachDisposables)
    end
end

---
---@param enter? boolean
---@param nextLineIncluded? boolean
---@return number? floatwinId
function Preview:peekFoldedLinesUnderCursor(enter, nextLineIncluded)
    local curBufnr = api.nvim_get_current_buf()
    local fb = fold.get(curBufnr)
    if not fb then
        -- buffer is detached
        return
    end
    local oLnum = api.nvim_win_get_cursor(0)[1]
    local lnum = utils.foldClosed(0, oLnum)
    if lnum == -1 then
        return
    end
    local endLnum = utils.foldClosedEnd(0, lnum)
    if utils.isBufLoaded(floatwin.bufnr) then
        api.nvim_buf_clear_namespace(floatwin.bufnr, self.ns, 0, -1)
    end
    local curWinid = api.nvim_get_current_win()
    local kind = fb:lineKind(curWinid, lnum)
    local isAbove = kind == 'comment'
    if not isAbove and nextLineIncluded ~= false then
        endLnum = fb:lineCount() == endLnum and endLnum or (endLnum + 1)
    end
    local text = fb:lines(lnum, endLnum)
    floatwin:display(api.nvim_get_current_win(), text, enter, isAbove)
    utils.winCall(floatwin.winid, function()
        if oLnum > lnum then
            api.nvim_win_set_cursor(0, {oLnum - lnum + 1, 0})
            cmd('norm! zz')
        end
        cmd('norm! ze')
    end)
    render.mapHighlightLimitByRange(curBufnr, floatwin.bufnr,
                                    {lnum - 1, 0}, {endLnum - 1, #text[endLnum - lnum + 1]},
                                    text, self.ns)
    render.mapMatchByLnum(curWinid, floatwin.winid, lnum, endLnum)
    scrollbar:display()
    self:attach(curBufnr, lnum)
    return floatwin.winid
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
    table.insert(disposables, floatwin:initialize(namespace, conf.win_config))
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
