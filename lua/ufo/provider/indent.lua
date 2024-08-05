local uv = vim.loop

local foldingrange = require('ufo.model.foldingrange')
local event = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local bufmanager = require('ufo.bufmanager')

---@class UfoIndentProvider
---@field buffers table
---@field bufNum number
---@field disposables UfoDisposable[]
local Indent = {}

---@class UfoIndentBuffer
---@field buf UfoBuffer
---@field hrtime number
---@field version number
---@field levels number[]
---@field tabstop number
---@field shiftWidth number
local IndentBuffer = {}
IndentBuffer.__index = IndentBuffer

---
---@param buf UfoBuffer
---@return UfoIndentBuffer
function IndentBuffer:new(buf)
    local o = self == IndentBuffer and setmetatable({}, self) or self
    o.buf = buf
    o.hrtime = uv.hrtime()
    o.version = 0
    o.levels = {}
    return o
end

function IndentBuffer:getMissHunks(lnum, endLnum)
    return self.buf:buildMissingHunk(self.levels, lnum, endLnum)
end

function IndentBuffer:handleFoldedLinesChanged(first, last, lastUpdated)
    self.levels = self.buf:handleLinesChanged(self.levels, first, last, lastUpdated)
end

function Indent.getFolds(bufnr)
    local self = Indent
    local ib = self:getBuffer(bufnr) or self:addBuffer(bufnr)
    if not ib then
        return
    end
    local buf = ib.buf
    local ts, sw = vim.bo[bufnr].ts, vim.bo[bufnr].sw
    local hunks
    local cnt = buf:lineCount()
    if ts ~= ib.tabstop or sw ~= ib.shiftWidth then
        ib.tabstop, ib.shiftWidth = ts, sw
        hunks = {{1, cnt}}
    else
        hunks = ib:getMissHunks(1, cnt)
    end
    if sw == 0 then
        sw = ts
    end
    local levels = ib.levels
    for _, hunk in ipairs(hunks) do
        local startLnum, endLnum = hunk[1], hunk[2]
        local lines = buf:lines(startLnum, endLnum)
        for i, line in ipairs(lines) do
            local level = -1
            local n = 0
            for col = 1, #line do
                -- compare byte is slightly faster than a char in the string
                local b = line:byte(col, col)
                if b == 0x20 then
                    -- ' '
                    n = n + 1
                elseif b == 0x09 then
                    -- '\t'
                    n = n + (ts - (n % ts))
                else
                    level = math.ceil(n / sw)
                    break
                end
            end
            levels[startLnum + i - 1] = level
        end
    end

    ib.version = buf:changedtick()
    ib.hrtime = uv.hrtime()

    local ranges = {}
    local stack = {}

    local function pop(curLevel, lastLnum)
        while #stack > 0 do
            local data = stack[#stack]
            local level, lnum = data[1], data[2]
            if level >= curLevel then
                table.insert(ranges, foldingrange.new(lnum - 1, lastLnum - 1))
                table.remove(stack)
            else
                break
            end
        end
    end

    local lastLnum = 1
    local lastLevel = levels[1]
    for i, level in ipairs(levels) do
        if level >= 0 then
            if level > 0 and level > lastLevel then
                table.insert(stack, {lastLevel, lastLnum})
            elseif level < lastLevel then
                pop(level, lastLnum)
            end
            lastLevel = level
            lastLnum = i
        end
    end
    pop(0, lastLnum)
    return ranges
end

---
---@param bufnr number
---@return UfoIndentBuffer
function Indent:getBuffer(bufnr)
    return self.buffers[bufnr]
end

function Indent:addBuffer(bufnr)
    local buf = bufmanager:get(bufnr)
    if not buf then
        return
    end
    self.buffers[bufnr] = IndentBuffer:new(buf)
    if self.bufNum == 0 then
        self.eventsDisposables = self:createEvents()
    end
    self.bufNum = self.bufNum + 1
    return self.buffers[bufnr]
end

function Indent:removeBuffer(bufnr)
    if self.bufNum == 0 then
        return
    end
    local ib = self:getBuffer(bufnr)
    if ib then
        self.buffers[bufnr] = nil
        self.bufNum = self.bufNum - 1
        if self.bufNum == 0 then
            self:destroyEvents()
        end
    end
end

function Indent:createEvents()
    local disposables = {}
    event:on('BufLinesChanged', function(bufnr, changedtick, firstLine, lastLine, lastLineUpdated)
        local ib = self:getBuffer(bufnr)
        if ib then
            ib.levels = ib.buf:handleLinesChanged(ib.levels, firstLine, lastLine, lastLineUpdated)
            -- May become fallback provider, compare the version with changedtick to remove
            if changedtick > ib.version + 20 then
                -- 20s interval
                if uv.hrtime() - ib.hrtime > 20 * 1e9 then
                    self:removeBuffer(bufnr)
                end
            end
        end
    end, disposables)
    event:on('BufDetach', function(bufnr)
        self:removeBuffer(bufnr)
    end, disposables)
    event:on('BufReload', function(bufnr)
        self:removeBuffer(bufnr)
    end, disposables)
    return disposables
end

function Indent:destroyEvents()
    disposable.disposeAll(self.eventsDisposables)
end

function Indent:dispose()
    self:destroyEvents()
    self:initialize()
end

function Indent:initialize()
    self.bufNum = 0
    self.buffers = {}
    self.eventsDisposables = {}
end

local function init()
    Indent:initialize()
end

init()

return Indent
