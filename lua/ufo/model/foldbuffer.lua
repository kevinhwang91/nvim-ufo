local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local utils      = require('ufo.utils')
local buffer     = require('ufo.model.buffer')
local foldedline = require('ufo.model.foldedline')

---@class UfoFoldBuffer
---@field bufnr number
---@field buf UfoBuffer
---@field ns number
---@field status string|'start'|'pending'|'stop'
---@field version number
---@field requestCount number
---@field foldRanges UfoFoldingRange[]
---@field foldedLines UfoFoldedLine[]
---@field foldedLineCount number
---@field providers table
---@field scanned boolean
---@field selectedProvider string
local FoldBuffer = setmetatable({}, buffer)
FoldBuffer.__index = FoldBuffer

---@param buf UfoBuffer
---@return UfoFoldBuffer
function FoldBuffer:new(buf, ns)
    local o = setmetatable({}, self)
    self.__index = self
    o.bufnr = buf.bufnr
    o.buf = buf
    o.ns = ns
    o:reset()
    return o
end

function FoldBuffer:dispose()
    self:resetFoldedLines(true)
    self:reset()
end

function FoldBuffer:changedtick()
    return self.buf:changedtick()
end

function FoldBuffer:filetype()
    return self.buf:filetype()
end

function FoldBuffer:buftype()
    return self.buf:buftype()
end

function FoldBuffer:lineCount()
    return self.buf:lineCount()
end

---
---@param lnum number
---@param endLnum? number
---@return string[]
function FoldBuffer:lines(lnum, endLnum)
    return self.buf:lines(lnum, endLnum)
end

function FoldBuffer:reset()
    self.status = 'start'
    self.providers = nil
    self.selectedProvider = nil
    self.version = 0
    self.requestCount = 0
    self.foldRanges = {}
    self:resetFoldedLines()
    self.scanned = false
end

function FoldBuffer:resetFoldedLines(clear)
    self.foldedLines = {}
    self.foldedLineCount = 0
    for _ = 1, self:lineCount() do
        table.insert(self.foldedLines, false)
    end
    if clear then
        pcall(api.nvim_buf_clear_namespace, self.bufnr, self.ns, 0, -1)
    end
end

function FoldBuffer:foldedLine(lnum)
    local fl = self.foldedLines[lnum]
    if not fl then
        return
    end
    return fl
end

function FoldBuffer:handleFoldedLinesChanged(first, last, lastUpdated)
    if self.foldedLineCount == 0 then
        return
    end
    for i = first + 1, last do
        self:openFold(i)
    end
    self.foldedLines = self.buf:handleLinesChanged(self.foldedLines, first, last, lastUpdated)
end

function FoldBuffer:acquireRequest()
    self.requestCount = self.requestCount + 1
end

function FoldBuffer:releaseRequest()
    if self.requestCount > 0 then
        self.requestCount = self.requestCount - 1
    end
end

function FoldBuffer:requested()
    return self.requestCount > 0
end

---
---@param lnum number
---@return boolean
function FoldBuffer:lineIsClosed(lnum)
    return self:foldedLine(lnum) ~= nil
end

---
---@param lnum number
---@param width number
---@return boolean
function FoldBuffer:lineNeedRender(lnum, width)
    local fl = self:foldedLine(lnum)
    return not fl or not fl:hasVirtText() or fl:widthChanged(width)
end

---
---@param winid number
function FoldBuffer:syncFoldedLines(winid)
    for lnum, fl in ipairs(self.foldedLines) do
        if fl and utils.foldClosed(winid, lnum) == -1 then
            self:openFold(lnum)
        end
    end
end

function FoldBuffer:getRangesFromExtmarks()
    local res = {}
    if self.foldedLineCount == 0 then
        return res
    end
    local marks = api.nvim_buf_get_extmarks(self.bufnr, self.ns, 0, -1, {details = true})
    for _, m in ipairs(marks) do
        local row, endRow = m[2], m[4].end_row
        -- extmark may give backward range
        if row > endRow then
            error(('expected forward range, got row: %d, endRow: %d'):format(row, endRow))
        end
        table.insert(res, {row, endRow})
    end
    return res
end

---
---@param lnum number
function FoldBuffer:openFold(lnum)
    local fl = self.foldedLines[lnum]
    if fl then
        fl:deleteVirtText()
        self.foldedLineCount = self.foldedLineCount - 1
        self.foldedLines[lnum] = false
    end
end

---
---@param lnum number
---@param endLnum number
---@param text? string
---@param virtText? string
---@param width? number
function FoldBuffer:closeFold(lnum, endLnum, text, virtText, width)
    local fl = self.foldedLines[lnum]
    if fl then
        if width and fl:widthChanged(width) then
            fl.width = width
        end
        if text and fl:textChanged(text) then
            fl.text = text
        end
        if not width and not text then
            return
        end
    else
        fl = foldedline:new(self.bufnr, self.ns, text, width)
        self.foldedLineCount = self.foldedLineCount + 1
        self.foldedLines[lnum] = fl
    end
    fl:updateVirtText(lnum, endLnum, virtText)
end

function FoldBuffer:scanFoldedRanges(winid, s, e)
    local res = {}
    local stack = {}
    s, e = s or 1, e or self:lineCount()
    utils.winCall(winid, function()
        local winView = fn.winsaveview()
        for i = s, e do
            local skip = false
            while #stack > 0 and i >= stack[#stack] do
                local endLnum = table.remove(stack)
                api.nvim_win_set_cursor(winid, {endLnum, 0})
                cmd('norm! zc')
                skip = true
            end
            if not skip then
                local endLnum = utils.foldClosedEnd(winid, i)
                if endLnum ~= -1 then
                    table.insert(stack, endLnum)
                    table.insert(res, {i - 1, endLnum - 1})
                    api.nvim_win_set_cursor(winid, {i, 0})
                    cmd('norm! zo')
                end
            end
        end
        fn.winrestview(winView)
    end)
    return res
end

return FoldBuffer
