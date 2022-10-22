local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

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
local highlight  = require('ufo.highlight')

---@class UfoPreview
---@field initialized boolean
---@field disposables UfoDisposable[]
---@field detachDisposables UfoDisposable[]
---@field ns number
---@field winid number
---@field bufnr number
---@field lnum number
---@field col number
---@field topline number
---@field foldedLnum number
---@field foldedEndLnum number
---@field isAbove boolean
---@field cursorSignName string
---@field cursorSignId number
---@field keyMessages table<string, string>
local Preview = {}

function Preview:trace(bufnr)
    local fb = fold.get(self.bufnr)
    if not fb then
        return
    end
    local fWinConfig = floatwin.getConfig()
    local wrow = fWinConfig.row
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
    local fLnum, fWrow, col
    if bufnr == self.bufnr then
        fLnum, fWrow = floatwin.topline, 0
        -- did scroll, do trace base on 2nd line
        if fLnum > 1 then
            fLnum = fLnum + 1
            fWrow = 1
        end
    else
        local floatCursor = api.nvim_win_get_cursor(floatwin.winid)
        fLnum = floatCursor[1]
        fWrow = fLnum - floatwin.topline
        col = floatCursor[2]
    end
    local cursor = api.nvim_win_get_cursor(self.winid)
    api.nvim_set_current_win(self.winid)
    local lnum = utils.foldClosed(0, cursor[1]) + fLnum - 1
    local lineSize = fWrow + wrow
    cmd('norm! m`zO')
    fb:syncFoldedLines(self.winid)
    if bufnr == self.bufnr then
        local s
        s, col = fb:lines(lnum)[1]:find('^%s+%S')
        col = s and col - 1 or 0
    end
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
    self:viewChanged()
end

function Preview:toggleCursor()
    local bufnr = api.nvim_get_current_buf()
    local floatBufnr = floatwin:getBufnr()
    if self.bufnr == bufnr and self.lnum - self.foldedLnum > 0 then
        self.cursorSignId = fn.sign_place(self.cursorSignId or 0, 'UfoPreview',
                                          self.cursorSignName, floatBufnr,
                                          {lnum = self.lnum - self.foldedLnum + 1, priority = 1})
    elseif self.cursorSignId then
        pcall(fn.sign_unplace, 'UfoPreview', {buffer = floatBufnr})
        self.cursorSignId = nil
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
            self:viewChanged()
        end)
    elseif str == 'onKey' then
        promise.resolve():thenCall(function()
            Preview:afterKey()
        end)
    end
end

function Preview:attach(bufnr, winid, foldedLnum, foldedEndLnum, isAbove)
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

    local view = utils.saveView(winid)
    self.winid = winid
    self.bufnr = bufnr
    self.lnum = view.lnum
    self.col = view.col
    self.topline = view.topline
    self.foldedLnum = foldedLnum
    self.foldedEndLnum = foldedEndLnum
    self.isAbove = isAbove
    local floatBufnr = floatwin:getBufnr()
    table.insert(disposables, disposable:create(function()
        self.winid = nil
        self.bufnr = nil
        self.lnum = nil
        self.col = nil
        self.topline = nil
        self.foldedLnum = nil
        self.foldedEndLnum = nil
        self.isAbove = nil
        self.cursorSignId = nil
        self.detachDisposables = nil
        api.nvim_buf_clear_namespace(floatBufnr, self.ns, 0, -1)
        pcall(fn.sign_unplace, 'UfoPreview', {buffer = floatBufnr})
        if floatwin:validate() then
            fn.clearmatches(floatwin.winid)
        end
        self.cursorSignId = nil
    end))
    table.insert(disposables, keymap:attach(bufnr, floatBufnr, self.ns, self.keyMessages, {
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

function Preview:viewChanged()
    floatwin:refreshTopline()
    scrollbar:update()
    winbar:update()
end

function Preview:display(enter, handler)
    local height = self.foldedEndLnum - self.foldedLnum + 1
    floatwin:display(self.winid, height, enter, self.isAbove, handler)
    scrollbar:display()
    winbar:display()
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
    local winid = api.nvim_get_current_win()
    local endLnum = utils.foldClosedEnd(0, lnum)
    local kind = fb:lineKind(winid, lnum)
    local isAbove = kind == 'comment'
    if not isAbove and nextLineIncluded ~= false then
        endLnum = fb:lineCount() == endLnum and endLnum or (endLnum + 1)
    end
    self:attach(bufnr, winid, lnum, endLnum, isAbove)
    floatwin.virtText = fl.virtText
    local text = fb:lines(lnum, endLnum)
    self:display(enter, function()
        floatwin:setContent(text)
        if oLnum > lnum then
            floatwin:call(function()
                api.nvim_win_set_cursor(0, {oLnum - lnum + 1, oCol})
                utils.zz()
            end)
        end
        floatwin:refreshTopline()
    end)
    self:toggleCursor()
    render.mapHighlightLimitByRange(bufnr, floatwin:getBufnr(),
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
        self:viewChanged()
        return
    end
    if winid == self.winid then
        local view = utils.saveView(winid)
        if self.lnum ~= view.lnum or
            self.col ~= view.col then
            self.close()
        elseif self.foldedLnum ~= utils.foldClosed(self.winid, self.foldedLnum) then
            self.close()
        elseif self.topline ~= view.topline then
            if floatwin:validate() then
                self:display(false)
                self.topline = view.topline
            end
        end
    else
        self.close()
    end
end

function Preview:initialize(namespace)
    if self.initialized then
        return
    end
    self.initialized = true
    local conf = vim.deepcopy(config.preview)
    self.keyMessages = conf.mappings
    self.disposables = {}
    table.insert(self.disposables, disposable:create(function()
        self.initialized = false
    end))
    table.insert(self.disposables, floatwin:initialize(namespace, conf.win_config))
    table.insert(self.disposables, scrollbar:initialize())
    table.insert(self.disposables, winbar:initialize())
    self.ns = namespace
    self.cursorSignName = highlight.signNames()['UfoPreviewCursorLine']
    return self
end

function Preview:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

return Preview
