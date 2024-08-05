local uv = vim.loop

local foldingrange = require('ufo.model.foldingrange')
local bufmanager = require('ufo.bufmanager')
local utils = require('ufo.utils')
local event = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')

-- Provider implementation

---@class UfoMarkerProvider
---@field buffers table
---@field bufNum number
---@field disposables UfoDisposable[]
local Marker = {}

local OPEN = -1
local CLOSE = 1

---@class UfoMarkerBuffer
---@field buf UfoBuffer
---@field hrtime number
---@field version number
---@field markerLines number[]
---@field foldmarker string
local MarkerBuffer = {}
MarkerBuffer.__index = MarkerBuffer

function MarkerBuffer:new(buf)
    local o = self == MarkerBuffer and setmetatable({}, self) or self
    o.buf = buf
    o.hrtime = uv.hrtime()
    o.version = 0
    o.markerLines = {}
    return o
end

function MarkerBuffer:getMissHunks(lnum, endLnum)
    return self.buf:buildMissingHunk(self.markerLines, lnum, endLnum)
end

function MarkerBuffer:handleFoldedLinesChanged(first, last, lastUpdated)
    self.markerLines = self.buf:handleLinesChanged(self.markerLines, first, last, lastUpdated)
end

--- Function that returns folds for the provided buffer based in the markers
--- @param bufnr number Vim buffer number
--- @return UfoFoldingRange[]|nil Folds List of marker folds in the buffer, or `nil` if they can not be queried
function Marker.getFolds(bufnr)
    local winid = utils.getWinByBuf(bufnr)
    if winid < 0 then
        return
    end

    local self = Marker
    local mb = self:getBuffer(bufnr) or self:addBuffer(bufnr)
    if not mb then
        return
    end

    local buf = mb.buf
    local foldmarker = vim.wo[winid].foldmarker
    local hunks
    local cnt = buf:lineCount()
    if mb.foldmarker ~= foldmarker then
        mb.foldmarker = foldmarker
        hunks = {{1, cnt}}
    else
        hunks = mb:getMissHunks(1, cnt)
    end
    local markerLines = mb.markerLines
    local startPat, endPat = unpack(vim.split(foldmarker, ',', {plain = true}))
    for _, hunk in ipairs(hunks) do
        local startLnum, endLnum = hunk[1], hunk[2]
        local lines = buf:lines(startLnum, endLnum)
        for i, line in ipairs(lines) do
            -- open position start, close position start
            local ops, cps = 0, 0
            -- open position end, close position end
            local ope, cpe
            local j = 1
            local res = {}
            local len = #line
            while true do
                if ops <= len and j > ops then
                    ops, ope = line:find(startPat, j, true)
                    if not ops then
                        ops = len + 1
                    end
                end
                if cps <= len and j > cps then
                    cps, cpe = line:find(endPat, j, true)
                    if not cps then
                        cps = len + 1
                    end
                end
                if ops > len and cps > len then
                    break
                end
                if ops <= cps then
                    table.insert(res, OPEN)
                    j = ope + 1
                else
                    table.insert(res, CLOSE)
                    j = cpe + 1
                end
            end
            markerLines[startLnum + i - 1] = res
        end
    end

    mb.version = buf:changedtick()
    mb.hrtime = uv.hrtime()

    local ranges = {}
    local stack = {}
    for lnum, lmarkers in ipairs(markerLines) do
        for _, v in ipairs(lmarkers) do
            if v == OPEN then
                table.insert(stack, lnum)
            else
                local last = stack[#stack]
                if last then
                    table.remove(stack)
                    table.insert(ranges, foldingrange.new(last - 1, lnum - 1,
                        nil, nil, 'marker')
                    )
                end
            end
        end
    end

    while #stack > 0 do
        local last = table.remove(stack)
        table.insert(ranges, foldingrange.new(last - 1, cnt - 1,
            nil, nil, 'marker'))
    end

    return ranges
end

---
---@param bufnr number
---@return UfoMarkerBuffer
function Marker:getBuffer(bufnr)
    return self.buffers[bufnr]
end

function Marker:addBuffer(bufnr)
    local buf = bufmanager:get(bufnr)
    if not buf then
        return
    end
    self.buffers[bufnr] = MarkerBuffer:new(buf)
    if self.bufNum == 0 then
        self.eventsDisposables = self:createEvents()
    end
    self.bufNum = self.bufNum + 1
    return self.buffers[bufnr]
end

function Marker:removeBuffer(bufnr)
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

function Marker:createEvents()
    local disposables = {}
    event:on('BufLinesChanged', function(bufnr, changedtick, firstLine, lastLine, lastLineUpdated)
        local ib = self:getBuffer(bufnr)
        if ib then
            ib.markerLines = ib.buf:handleLinesChanged(ib.markerLines, firstLine, lastLine, lastLineUpdated)
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

function Marker:destroyEvents()
    disposable.disposeAll(self.eventsDisposables)
end

function Marker:dispose()
    self:destroyEvents()
    self:initialize()
end

function Marker:initialize()
    self.bufNum = 0
    self.buffers = {}
    self.eventsDisposables = {}
end

local function init()
    Marker:initialize()
end

init()

return Marker
