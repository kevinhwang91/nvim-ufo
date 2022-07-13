local api = vim.api

local utils      = require('ufo.utils')
local disposable = require('ufo.lib.disposable')
local buffer     = require('ufo.model.buffer')
local foldedline = require('ufo.model.foldedline')

---@class UfoFoldBuffer: UfoBuffer
---@field bufnr number
---@field buf UfoBuffer
---@field ns number
---@field status string|'start'|'pending'|'stop'
---@field version number
---@field requestCount number
---@field foldRanges UfoFoldingRange[]
---@field foldedLines UfoFoldedLine[]
---@field providers table
---@field selectedProvider string
---@field disposables UfoDisposable
local FoldBuffer = setmetatable({}, buffer)
FoldBuffer.__index = FoldBuffer

---@param buf UfoBuffer
---@return UfoFoldBuffer
function FoldBuffer:new(buf, ns)
    local o = setmetatable(buf, self)
    self.__index = self
    o.ns = ns
    o.attached = true
    o:reset()
    o.disposables = {
        disposable:create(function()
            o:resetFoldedLines()
        end)
    }
    return o
end

function FoldBuffer:dispose()
    for _, item in ipairs(self.disposables) do
        item:dispose()
    end
end

function FoldBuffer:reset()
    self.status = 'start'
    self.providers = nil
    self.selectedProvider = nil
    self.version = 0
    self.requestCount = 0
    self.foldRanges = {}
    self.foldedLines = {}
end

function FoldBuffer:resetFoldedLines()
    self.foldedLines = {}
    pcall(api.nvim_buf_clear_namespace, self.bufnr, self.ns, 0, -1)
end

function FoldBuffer:foldedLine(lnum)
    return self.foldedLines[lnum]
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
    return not fl or not fl:hasVirtText() or fl:widthChanged(width) or
        fl:textChanged(self:lines(lnum)[1])
end

function FoldBuffer:maySyncFoldedLines(winid, lnum, text)
    local synced = false
    local fl = self:foldedLine(lnum)
    if fl and fl:textChanged(text) then
        self:syncFoldedLines(winid)
        synced = true
    end
    return synced
end

---
---@param winid number
function FoldBuffer:syncFoldedLines(winid)
    local newLines = {}
    for _, fl in pairs(self.foldedLines) do
        local mark = api.nvim_buf_get_extmark_by_id(self.bufnr, self.ns, fl.id, {})
        local row = mark[1]
        if row then
            local lnum = row + 1
            local fs = utils.foldClosed(winid, lnum)
            if fs == lnum then
                if newLines[lnum] then
                    -- the newLines[lnum] assigned from previous FoldedLine must be
                    -- fl.lnum ~= lnum, assign current FoldedLine to newLines[lnum]
                    -- and clear previous extmark
                    if fl.lnum == lnum then
                        newLines[lnum]:deleteVirtText()
                        newLines[lnum] = fl
                    else
                        fl:deleteVirtText()
                    end
                else
                    newLines[lnum] = fl
                    fl.lnum = lnum
                end
            else
                if fs == -1 then
                    fl:deleteVirtText()
                else
                    newLines[lnum] = fl
                    fl.lnum = lnum
                end
            end
        end
    end
    self.foldedLines = newLines
end

---
---@param lnum number
function FoldBuffer:openFold(lnum)
    local fl = self.foldedLines[lnum]
    fl:deleteVirtText()
    self.foldedLines[lnum] = nil
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
        fl = foldedline:new(self.bufnr, self.ns, lnum, text, width)
        self.foldedLines[lnum] = fl
    end
    fl:updateVirtText(lnum, endLnum, virtText)
end

return FoldBuffer
