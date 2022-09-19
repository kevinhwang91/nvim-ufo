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
---@field foldedLines table<number, UfoFoldedLine|boolean> A list of UfoFoldedLine or boolean
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

---
---@param winid number
---@param lnum number 1-index
---@return UfoFoldingRangeKind|''
function FoldBuffer:lineKind(winid, lnum)
    if utils.isDiffOrMarkerFold(winid) then
        return ''
    end
    local row = lnum - 1
    for _, range in ipairs(self.foldRanges) do
        if row >= range.startLine and row <= range.endLine then
            return range.kind
        end
    end
    return ''
end

function FoldBuffer:handleFoldedLinesChanged(first, last, lastUpdated)
    if self.foldedLineCount == 0 then
        return
    end
    local didOpen = false
    for i = first + 1, last do
        didOpen = self:openFold(i) or didOpen
    end
    if didOpen and lastUpdated > first then
        local winid = utils.getWinByBuf(self.bufnr)
        if winid ~= -1 then
            utils.winCall(winid, function()
                cmd(('sil! %d,%dfoldopen!'):format(first + 1, lastUpdated))
            end)
        end
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
---@return boolean
function FoldBuffer:openFold(lnum)
    local fl = self.foldedLines[lnum]
    if fl then
        fl:deleteVirtText()
        self.foldedLineCount = self.foldedLineCount - 1
        self.foldedLines[lnum] = false
    end
    return not not fl
end

---
---@param lnum number
---@param endLnum number
---@param text? string
---@param virtText? string
---@param width? number
---@return boolean
function FoldBuffer:closeFold(lnum, endLnum, text, virtText, width)
    local lineCount = self:lineCount()
    endLnum = math.min(endLnum, lineCount)
    if endLnum < lnum then
        return false
    end
    local fl = self.foldedLines[lnum]
    if fl then
        if width and fl:widthChanged(width) then
            fl.width = width
        end
        if text and fl:textChanged(text) then
            fl.text = text
        end
        if not width and not text then
            return false
        end
    else
        if self.foldedLineCount == 0 and lineCount ~= #self.foldedLines then
            self:resetFoldedLines()
        end
        fl = foldedline:new(self.bufnr, self.ns, text, width)
        self.foldedLineCount = self.foldedLineCount + 1
        self.foldedLines[lnum] = fl
    end
    fl:updateVirtText(lnum, endLnum, virtText)
    return true
end

function FoldBuffer:scanFoldedRanges(winid, s, e)
    local res = {}
    local stack = {}
    s, e = s or 1, e or self:lineCount()
    utils.winCall(winid, function()
        for i = s, e do
            local skip = false
            while #stack > 0 and i >= stack[#stack] do
                local endLnum = table.remove(stack)
                cmd(endLnum .. 'foldclose')
                skip = true
            end
            if not skip then
                local endLnum = utils.foldClosedEnd(winid, i)
                if endLnum ~= -1 then
                    table.insert(stack, endLnum)
                    table.insert(res, {i - 1, endLnum - 1})
                    cmd(i .. 'foldopen')
                end
            end
        end
    end)
    return res
end

return FoldBuffer
