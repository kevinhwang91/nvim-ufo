local cmd = vim.cmd
local fn  = vim.fn

local utils = require('ufo.utils')

---@type UfoFoldDriverNonFFI|UfoFoldDriverFFI
local FoldDriver

---@class UfoFoldDriverFFI
local FoldDriverFFI = {}

function FoldDriverFFI:new(wffi)
    local o = setmetatable({}, self)
    self.__index = self
    self._wffi = wffi
    return o
end

---
---@param winid number
---@param ranges UfoFoldingRange
---@param rowPairs table<number, number>
function FoldDriverFFI:createFolds(winid, ranges, rowPairs)
    utils.winCall(winid, function()
        local foldRanges = {}
        local wo = vim.wo[winid]
        local foldLevel = wo.foldlevel
        self._wffi.clearFolds(winid)
        -- just check the last range only to filter out same ranges
        local lastStartLine, lastEndLine
        for _, r in ipairs(ranges) do
            local startLine, endLine = r.startLine, r.endLine
            if not rowPairs[startLine] and
                (lastStartLine ~= startLine or lastEndLine ~= endLine) then
                lastStartLine, lastEndLine = startLine, endLine
                table.insert(foldRanges, {startLine + 1, endLine + 1})
            end
        end
        self._wffi.createFolds(winid, foldRanges)
        wo.foldmethod = 'manual'
        wo.foldenable = true
        wo.foldlevel = foldLevel
        foldRanges = {}
        for row, endRow in pairs(rowPairs) do
            table.insert(foldRanges, {row + 1, endRow + 1})
        end
        self._wffi.createFolds(winid, foldRanges)
    end)
end

---@class UfoFoldDriverNonFFI
local FoldDriverNonFFI = {}

function FoldDriverNonFFI:new()
    local o = setmetatable({}, self)
    self.__index = self
    return o
end

---
---@param winid number
---@param ranges UfoFoldingRange
---@param rowPairs table<number, number>
function FoldDriverNonFFI:createFolds(winid, ranges, rowPairs)
    utils.winCall(winid, function()
        local cmds = {}
        local lastStartLine, lastEndLine
        for _, r in ipairs(ranges) do
            local startLine, endLine = r.startLine, r.endLine
            if not rowPairs[startLine] and
                (lastStartLine ~= startLine or lastEndLine ~= endLine) then
                table.insert(cmds, ('%d,%d:fold'):format(startLine + 1, endLine + 1))
            end
        end
        local winView = fn.winsaveview()
        cmd('norm! zE')
        fn.winrestview(winView)
        local foldLevel = vim.wo.foldlevel
        table.insert(cmds, 'setl foldmethod=manual')
        table.insert(cmds, 'setl foldenable')
        table.insert(cmds, 'setl foldlevel=' .. foldLevel)
        local foldRanges = {}
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
    if jit ~= nil then
        FoldDriver = FoldDriverFFI:new(require('ufo.wffi'))
    else
        FoldDriver = FoldDriverNonFFI:new()
    end
end

init()

return FoldDriver
