local cmd = vim.cmd
local fn = vim.fn

local utils = require('ufo.utils')

local function convertToFoldRanges(ranges, rowPairs)
    -- just check the last range only to filter out same ranges
    local lastStartLine, lastEndLine
    local foldRanges = {}
    local minLines = vim.wo.foldminlines
    for _, r in ipairs(ranges) do
        local startLine, endLine = r.startLine, r.endLine
        if not rowPairs[startLine] and endLine - startLine >= minLines and
            (lastStartLine ~= startLine or lastEndLine ~= endLine) then
            lastStartLine, lastEndLine = startLine, endLine
            table.insert(foldRanges, {startLine + 1, endLine + 1})
        end
    end
    return foldRanges
end

---@type UfoFoldDriverNonFFI|UfoFoldDriverFFI
local FoldDriver

local tmpname
local tmpFD

---@class UfoFoldDriverBase
---@field _tmpname string
---@field _tmpFD userdata
local FoldDriverBase = {}
FoldDriverBase.__index = FoldDriverBase

function FoldDriverBase:getTmpHandle()
    if not tmpFD then
        tmpFD = assert(io.open(tmpname, 'r'))
    end
    return tmpFD
end

function FoldDriverBase:getFoldsAndClosedInfo(winid)
    utils.winCall(winid, function()
        cmd('mkview! ' .. tmpname)
    end)
    local fd = self:getTmpHandle()
    fd:seek('set')
    local pairs = {}
    local closed = {}
    local lastLine
    local flag = 0
    for line in fd:lines() do
        if flag == 1 then
            local s, e = line:match('^(%d+),(%d+)fold$')
            if s then
                s, e = tonumber(s), tonumber(e)
                ---@diagnostic disable-next-line: need-check-nil
                pairs[s] = e
            elseif line == 'let &fdl = &fdl' then
                flag = 2
            end
        elseif flag == 2 then
            if line == 'normal! zc' then
                local s = tonumber(lastLine)
                if s then
                    table.insert(closed, s)
                end
            end
        else
            if flag == 0 and line == 'silent! normal! zE' then
                flag = 1
            end
        end
        lastLine = line
    end
    return pairs, closed
end

---@class UfoFoldDriverFFI:UfoFoldDriverBase
---@field _wffi UfoWffi
local FoldDriverFFI = {}
FoldDriverFFI.__index = FoldDriverFFI
setmetatable(FoldDriverFFI, FoldDriverBase)

function FoldDriverFFI:new(wffi)
    local o = setmetatable({}, self)
    self._wffi = wffi
    return o
end

---
---@param winid number
---@param ranges UfoFoldingRange
---@param rowPairs table<number, number>
function FoldDriverFFI:createFolds(winid, ranges, rowPairs)
    utils.winCall(winid, function()
        local wo = vim.wo
        local level = wo.foldlevel
        self._wffi.clearFolds(winid)
        local foldRanges = convertToFoldRanges(ranges, rowPairs)
        self._wffi.createFolds(winid, foldRanges)
        wo.foldmethod = 'manual'
        wo.foldenable = true
        wo.foldlevel = level
        foldRanges = {}
        for row, endRow in pairs(rowPairs) do
            table.insert(foldRanges, {row + 1, endRow + 1})
        end
        self._wffi.createFolds(winid, foldRanges)
    end)
end

---@class UfoFoldDriverNonFFI:UfoFoldDriverBase
local FoldDriverNonFFI = {}
FoldDriverNonFFI.__index = FoldDriverNonFFI
setmetatable(FoldDriverNonFFI, FoldDriverBase)

function FoldDriverNonFFI:new()
    local o = setmetatable({}, self)
    return o
end

---
---@param winid number
---@param ranges UfoFoldingRange
---@param rowPairs table<number, number>
function FoldDriverNonFFI:createFolds(winid, ranges, rowPairs)
    utils.winCall(winid, function()
        local level = vim.wo.foldlevel
        local cmds = {}
        local foldRanges = convertToFoldRanges(ranges, rowPairs)
        for _, r in ipairs(foldRanges) do
            table.insert(cmds, ('%d,%d:fold'):format(r[1], r[2]))
        end
        local view = utils.saveView(0)
        cmd('norm! zE')
        utils.restView(0, view)
        table.insert(cmds, 'setl foldmethod=manual')
        table.insert(cmds, 'setl foldenable')
        table.insert(cmds, 'setl foldlevel=' .. level)
        foldRanges = {}
        for row, endRow in pairs(rowPairs) do
            table.insert(foldRanges, {row + 1, endRow + 1})
        end
        table.sort(foldRanges, function(a, b)
            return a[1] == b[1] and a[2] < b[2] or a[1] > b[1]
        end)
        for _, r in ipairs(foldRanges) do
            table.insert(cmds, ('%d,%dfold'):format(r[1], r[2]))
        end
        cmd(table.concat(cmds, '|'))
    end)
end

local function init()
    tmpname = fn.tempname()
    if jit ~= nil then
        FoldDriver = FoldDriverFFI:new(require('ufo.wffi'))
    else
        FoldDriver = FoldDriverNonFFI:new()
    end
end

init()

return FoldDriver
