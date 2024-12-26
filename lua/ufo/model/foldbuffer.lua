local api = vim.api
local cmd = vim.cmd

local utils = require('ufo.utils')
local buffer = require('ufo.model.buffer')
local foldedline = require('ufo.model.foldedline')
local render = require('ufo.render')

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

function FoldBuffer:syntax()
    return self.buf:syntax()
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
---@param s number
---@param e number
---@param namespaces number[]
---@return boolean
function FoldBuffer:openStaleFoldsByRange(s, e, namespaces)
    local res = false
    for lnum = s, e do
        -- Async call, arguments may be invalid
        local ok, ids = pcall(render.getLineExtMarkIds, self.bufnr, lnum, namespaces)
        if ok then
            local fl = self.foldedLines[lnum]
            if fl and not fl:validExtIds(ids) then
                self:openFold(lnum)
                res = true
            end
        end
    end
    return res
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
    local folded = false
    local fl = self.foldedLines[lnum]
    if fl then
        folded = self.foldedLines[lnum] ~= nil
        fl:deleteExtmark()
        self.foldedLineCount = self.foldedLineCount - 1
        self.foldedLines[lnum] = false
    end
    return folded
end

---
---@param lnum number
---@param endLnum number
---@param virtText? string
---@param namespaces? number[]
---@return boolean
function FoldBuffer:closeFold(lnum, endLnum, virtText, namespaces)
    local lineCount = self:lineCount()
    endLnum = math.min(endLnum, lineCount)
    if endLnum < lnum then
        return false
    end
    local fl = self.foldedLines[lnum]
    if not fl then
        if self.foldedLineCount == 0 and lineCount ~= #self.foldedLines then
            self:resetFoldedLines()
        end
        fl = foldedline:new(self.bufnr, self.ns)
        self.foldedLineCount = self.foldedLineCount + 1
        self.foldedLines[lnum] = fl
    end
    local extIds
    if namespaces then
        extIds = render.getLineExtMarkIds(self.bufnr, lnum, namespaces)
    end
    fl:updateVirtText(lnum, endLnum, virtText, extIds)
    return true
end

--#region
-- function FoldBuffer:scanFoldedRanges(winid, s, e)
--     local res = {}
--     local stack = {}
--     s, e = s or 1, e or self:lineCount()
--     utils.winCall(winid, function()
--         for i = s, e do
--             local skip = false
--             while #stack > 0 and i >= stack[#stack] do
--                 local endLnum = table.remove(stack)
--                 cmd(endLnum .. 'foldclose')
--                 skip = true
--             end
--             if not skip then
--                 local endLnum = utils.foldClosedEnd(winid, i)
--                 if endLnum ~= -1 then
--                     table.insert(stack, endLnum)
--                     table.insert(res, {i - 1, endLnum - 1})
--                     cmd(i .. 'foldopen')
--                 end
--             end
--         end
--     end)
--     return res
-- end
--#endregion

return FoldBuffer
