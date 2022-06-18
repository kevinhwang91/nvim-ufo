local cmd = vim.cmd
local fn  = vim.fn

local utils = require('ufo.utils')

local FoldDriver

---@class UfoFoldDriverFFI
local FoldDriverFFI = {}

function FoldDriverFFI:new(wffi)
    local o = setmetatable({}, self)
    self.__index = self
    self._wffi = wffi
    return o
end

function FoldDriverFFI:createFolds(winid, ranges, rowPairs)
    utils.winCall(winid, function()
        local foldRanges = {}
        local foldLevel = vim.wo.foldlevel
        self._wffi.clearFolds(winid)
        for _, f in ipairs(ranges) do
            local startLine, endLine = f.startLine, f.endLine
            if not rowPairs[startLine] then
                table.insert(foldRanges, {startLine + 1, endLine + 1})
            end
        end
        self._wffi.createFolds(winid, foldRanges)
        vim.wo.foldmethod = 'manual'
        vim.wo.foldenable = true
        vim.wo.foldlevel = foldLevel
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

function FoldDriverNonFFI:createFolds(winid, ranges, rowPairs)
    utils.winCall(winid, function()
        local cmds = {}
        for _, r in ipairs(ranges) do
            if not rowPairs[r.startLine] then
                table.insert(cmds, ('%d,%d:fold'):format(r.startLine + 1, r.endLine + 1))
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
            table.insert(cmds, ('%d,%d:fold'):format(r[1], r[2]))
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
