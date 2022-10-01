local api = vim.api
local fn  = vim.fn
local cmd = vim.cmd

local promise    = require('promise')
local render     = require('ufo.render')
local utils      = require('ufo.utils')
local floatwin   = require('ufo.preview.floatwin')
local scrollbar  = require('ufo.preview.scrollbar')
local winbar     = require('ufo.preview.winbar')
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
    cursorMarkId = nil,
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
    local lnum = api.nvim_win_get_cursor(self.winid)[1]
    local fLnum, fWrow, col
    if bufnr == self.bufnr then
        fLnum, fWrow, col = floatwin.topline, 0, 0
        -- did scroll, do trace base on 2nd line
        if fLnum > 1 then
            fLnum = fLnum + 1
            fWrow = 1
        end
    else
        local floatCursor = api.nvim_win_get_cursor(floatWinid)
        fLnum = floatCursor[1]
        fWrow = fLnum - floatwin.topline
        lnum, col = api.nvim_win_get_cursor(self.winid)[1], floatCursor[2]
    end
    api.nvim_set_current_win(self.winid)
    local startLnum = utils.foldClosed(0, lnum)
    local lineSize = fWrow + wrow
    cmd('norm! m`zO')
    local fb = fold.get(self.bufnr)
    if fb then
        fb:syncFoldedLines(0)
    end
    lnum = startLnum + fLnum - 1
    local topline, topfill = utils.evaluateTopline(self.winid, lnum, lineSize)
    utils.restView(0, {
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
    floatwin:call(function()
        local ctrlTbl = {B = 0x02, D = 0x04, E = 0x05, F = 0x06, U = 0x15, Y = 0x19}
        cmd(('norm! %c'):format(ctrlTbl[char]))
    end)
    self:refresh()
end

function Preview:toggleCursor()
    local bufnr = api.nvim_get_current_buf()
    if self.bufnr == bufnr and self.lnum - self.foldedLnum > 0 then
        self.cursorMarkId = render.setLineHighlight(floatwin.bufnr, self.ns, self.lnum - self.foldedLnum,
                                                    'Visual', 1, self.cursorMarkId)
    elseif self.cursorMarkId then
        pcall(api.nvim_buf_del_extmark, floatwin.bufnr, self.ns, self.cursorMarkId)
        self.cursorMarkId = nil
    end
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
        self:toggleCursor()
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
            self:refresh()
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
    local view = utils.saveView(self.winid)
    self.bufnr = bufnr
    self.lnum = view.lnum
    self.col = view.col
    self.topline = view.topline
    self.foldedLnum = foldedLnum
    self:toggleCursor()
    table.insert(disposables, disposable:create(function()
        self.winid = nil
        self.bufnr = nil
        self.lnum = nil
        self.col = nil
        self.topline = nil
        self.foldedLnum = nil
        self.cursorMarkId = nil
        self.detachDisposables = nil
        api.nvim_buf_clear_namespace(floatwin.bufnr, self.ns, 0, -1)
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

function Preview:refresh()
    floatwin:refreshTopline()
    scrollbar:update()
    winbar:update()
end

---
---@param enter? boolean
---@param nextLineIncluded? boolean
---@return number? floatwinId
function Preview:peekFoldedLinesUnderCursor(enter, nextLineIncluded)
    local bufnr = api.nvim_get_current_buf()
    local fb = fold.get(bufnr)
    if not fb then
        -- buffer is detached
        return
    end
    local oLnum, oCol = unpack(api.nvim_win_get_cursor(0))
    local lnum = utils.foldClosed(0, oLnum)
    local fl = fb.foldedLines[lnum]
    if lnum == -1 or not fl then
        return
    end
    local endLnum = utils.foldClosedEnd(0, lnum)
    local winid = api.nvim_get_current_win()
    local kind = fb:lineKind(winid, lnum)
    local isAbove = kind == 'comment'
    if not isAbove and nextLineIncluded ~= false then
        endLnum = fb:lineCount() == endLnum and endLnum or (endLnum + 1)
    end
    floatwin.virtText = fl.virtText
    local text = fb:lines(lnum, endLnum)
    floatwin:display(api.nvim_get_current_win(), text, enter, isAbove)
    floatwin:call(function()
        if oLnum > lnum then
            api.nvim_win_set_cursor(0, {oLnum - lnum + 1, oCol})
            utils.zz()
        end
        cmd('norm! ze')
    end)
    floatwin:refreshTopline()
    -- it is relative to floating window, need to redraw to make floating window validate
    cmd('redraw')
    scrollbar:display()
    winbar:display()
    self:attach(bufnr, lnum)
    render.mapHighlightLimitByRange(bufnr, floatwin.bufnr,
                                    {lnum - 1, 0}, {endLnum - 1, #text[endLnum - lnum + 1]},
                                    text, self.ns)
    render.mapMatchByLnum(winid, floatwin.winid, lnum, endLnum)
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
    winbar:close()
end

function Preview.floatWinid()
    return floatwin.winid
end

function Preview:afterKey()
    local winid = api.nvim_get_current_win()
    if floatwin.winid == winid then
        self:refresh()
        return
    end
    if winid == self.winid then
        local view = utils.saveView(winid)
        if self.topline ~= view.topline or self.lnum ~= view.lnum or
            self.col ~= view.col then
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
    table.insert(disposables, winbar)
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
