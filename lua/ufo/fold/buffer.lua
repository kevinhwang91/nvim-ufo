local api = vim.api

local utils = require('ufo.utils')
local log   = require('ufo.log')

---@class UfoFoldBuffer
---@field ns number
---@field openFoldHlTimeout number
---@field bufnr number
---@field winid? number
---@field lnum? number
---@field pending boolean
---@field version number
---@field foldRanges table
---@field foldedLines UfoFoldedLine[]
---@field providers table
---@field targetProvider string
local FoldBuffer = {
    ns = nil,
    openFoldHlTimeout = 0,
    pool = {}
}

---@class UfoFoldedLine
---@field id number
---@field lnum number
---@field width number
---@field virtText string
local FoldedLine = {}

function FoldedLine:new(lnum, width)
    local obj = setmetatable({}, self)
    self.__index = self
    obj.id = nil
    obj.lnum = lnum
    obj.width = width
    obj.virtText = nil
    return obj
end

---@param bufnr number
---@return UfoFoldBuffer
function FoldBuffer:new(bufnr)
    local obj = setmetatable({}, self)
    self.__index = self
    obj.bufnr = bufnr
    obj.winid = nil
    obj.lnum = nil
    obj.pending = false
    obj.providers = nil
    obj.targetProvider = nil
    obj.version = 0
    obj.foldRanges = {}
    obj.foldedLines = {}
    local old = self.pool[bufnr]
    if old then
        old:dispose()
    end
    self.pool[bufnr] = obj
    return obj
end

---
---@param bufnr number
---@return UfoFoldBuffer
function FoldBuffer:get(bufnr)
    return self.pool[bufnr]
end

function FoldBuffer:dispose()
    self.pool[self.bufnr] = nil
    api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
end

function FoldBuffer:resetFoldedLines()
    self.foldedLines = {}
    api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
end

---
---@param lnum number
---@return boolean
function FoldBuffer:hasClosed(lnum)
    local f = self.foldedLines[lnum]
    return f ~= nil
end

---
---@param winid number
function FoldBuffer:synchronize(winid)
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
                        api.nvim_buf_del_extmark(self.bufnr, self.ns, newLines[lnum].id)
                        newLines[lnum] = fl
                    else
                        api.nvim_buf_del_extmark(self.bufnr, self.ns, fl.id)
                    end
                else
                    newLines[lnum] = fl
                    fl.lnum = lnum
                end
            else
                if fs == -1 then
                    api.nvim_buf_del_extmark(self.bufnr, self.ns, fl.id)
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
---@param width number
---@return boolean
function FoldBuffer:foldedLineWidthChanged(lnum, width)
    local fl = self.foldedLines[lnum]
    if fl then
        return fl.width ~= width
    end
    return false
end

---
---@param lnum number
function FoldBuffer:openFold(lnum)
    local fl = self.foldedLines[lnum]
    if self.openFoldHlTimeout > 0 then
        local mark = api.nvim_buf_get_extmark_by_id(self.bufnr, self.ns, fl.id, {details = true})
        local row, details = mark[1], mark[3]
        if row and lnum == row + 1 then
            local endRow = details.end_row
            utils.highlightTimeout(self.bufnr, self.ns, 'UfoFoldedBg', row, endRow + 1,
                                   nil, self.openFoldHlTimeout)
        end
    end
    api.nvim_buf_del_extmark(self.bufnr, self.ns, fl.id)
    self.foldedLines[lnum] = nil
end

---
---@param lnum number
---@param endLnum number
---@param virtText string
---@param width number
function FoldBuffer:closeFold(lnum, endLnum, virtText, width)
    local fl = self.foldedLines[lnum]
    if fl then
        if self:foldedLineWidthChanged(lnum, width) then
            fl.width = width
        else
            return
        end
    else
        fl = FoldedLine:new(lnum, width)
    end
    fl.id = api.nvim_buf_set_extmark(self.bufnr, self.ns, lnum - 1, 0, {
        id = fl.id,
        end_row = endLnum - 1,
        end_col = 0,
        virt_text = virtText,
        virt_text_win_col = 0,
        hl_mode = 'combine'
    })
    fl.virtText = virtText
    self.foldedLines[lnum] = fl
end

function FoldBuffer:parseProviders()
    if not self.providerSelector then
        self.providers = {'lsp', 'indent'}
        return
    end
    local res
    local providers = self.providerSelector(self.bufnr, vim.bo[self.bufnr].ft)
    local t = type(providers)
    if t == 'nil' then
        res = {'lsp', 'indent'}
    elseif t == 'string' or t == 'function' then
        res = {providers}
    elseif t == 'table' then
        res = {}
        for _, m in ipairs(providers) do
            if #res == 2 then
                break
            end
            table.insert(res, m)
        end
    else
        res = {''}
    end
    self.providers = res
end

function FoldBuffer:isFoldMethodsDisabled()
    if not self.providers then
        self:parseProviders()
    end
    return self.providers[1] == ''
end

---
---@param namespace number
---@param openFoldHlTimeout number
---@param selector function
function FoldBuffer.initialize(namespace, openFoldHlTimeout, selector)
    FoldBuffer.ns = namespace
    FoldBuffer.openFoldHlTimeout = openFoldHlTimeout
    FoldBuffer.providerSelector = selector
end

function FoldBuffer.disposeAll()
    for _, fb in pairs(FoldBuffer.pool) do
        fb:dispose()
    end
end

return FoldBuffer
