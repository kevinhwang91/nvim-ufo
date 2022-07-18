local event = require('ufo.lib.event')

local api = vim.api

---@class UfoBuffer
---@field bufnr number
---@field attached boolean
local Buffer = {}

function Buffer:new(bufnr)
    local o = setmetatable({}, self)
    self.__index = self
    o.bufnr = bufnr
    o:reload()
    return o
end

function Buffer:reload()
    self._changedtick = api.nvim_buf_get_changedtick(self.bufnr)
    self._lines = {}
    for _ = 1, api.nvim_buf_line_count(self.bufnr) do
        table.insert(self._lines, false)
    end
end

function Buffer:dispose()
    self.attached = false
end

function Buffer:attach()
    local bt = self:buftype()
    if bt == 'terminal' or bt == 'prompt' then
        self.attached = false
        return self.attached
    end
    ---@diagnostic disable: redefined-local, unused-local
    self.attached = api.nvim_buf_attach(self.bufnr, false, {
        on_lines = function(name, bufnr, changedtick, firstLine, lastLine,
                            lastLineUpdated, byteCount)
            if not self.attached then
                event:emit('BufDetach', bufnr)
                return true
            end
            if firstLine == lastLine and lastLine == lastLineUpdated and byteCount == 0 then
                return
            end
            self._changedtick = changedtick
            lastLineUpdated = math.max(1, lastLineUpdated)
            self:handleChanged(firstLine, lastLine, lastLineUpdated)
            event:emit('BufLinesChanged', bufnr, changedtick, firstLine, lastLine,
                       lastLineUpdated, byteCount)
        end,
        on_changedtick = function(name, bufnr, changedtick)
            self._changedtick = changedtick
        end,
        on_detach = function(name, bufnr)
            event:emit('BufDetach', bufnr)
        end,
        on_reload = function(name, bufnr)
            self:reload()
            event:emit('BufReload', bufnr)
        end
    })
    ---@diagnostic enable: redefined-local, unused-local
    if self.attached then
        event:emit('BufAttach', self.bufnr)
    end
    return self.attached
end

---lower is less than or equal to lnum
---@param lnum number
---@param endLnum number
---@return table[]
function Buffer:buildMissingHunk(lnum, endLnum)
    local hunks = {}
    local s, e
    local cnt = 0
    for i = lnum, endLnum do
        if not self._lines[i] then
            cnt = cnt + 1
            if not s then
                s = i
            end
            e = i
        elseif e then
            table.insert(hunks, {s, e})
            s, e = nil, nil
        end
    end
    if e then
        table.insert(hunks, {s, e})
    end
    -- scan backward
    if #hunks > 0 then
        local firstHunks = hunks[1]
        local fhs = firstHunks[1]
        if fhs == lnum then
            local i = lnum - 1
            while i > 0 do
                if self._lines[i] then
                    break
                end
                i = i - 1
            end
            fhs = i + 1
            cnt = cnt + lnum - fhs
            firstHunks[1] = fhs
            lnum = fhs
        end
    end
    if cnt > (endLnum - lnum) / 4 and #hunks > 2 then
        hunks = {{lnum, endLnum}}
    end
    return hunks
end

function Buffer:handleChanged(firstLine, lastLine, lastLineUpdated)
    local delta = lastLineUpdated - lastLine
    if delta == 0 then
        for i = firstLine + 1, lastLine do
            self._lines[i] = false
        end
    elseif delta > 0 then
        for _ = 1, delta do
            table.insert(self._lines, firstLine + 1, false)
        end
    else
        for _ = 1, -delta do
            table.remove(self._lines, lastLineUpdated)
        end
        for i = firstLine + 1, lastLineUpdated do
            self._lines[i] = false
        end
    end
end

---
---@return number
function Buffer:changedtick()
    return self._changedtick
end

---
---@return string
function Buffer:filetype()
    if not self.ft then
        self.ft = vim.bo[self.bufnr].ft
    end
    return self.ft
end

---
---@return string
function Buffer:buftype()
    if not self.bt then
        self.bt = vim.bo[self.bufnr].bt
    end
    return self.bt
end

---
---@return number
function Buffer:lineCount()
    return #self._lines
end

---@param lnum number
---@param endLnum? number
---@return string[]
function Buffer:lines(lnum, endLnum)
    local lineCount = self:lineCount()
    assert(lineCount >= lnum, 'index out of bounds')
    local res = {}
    endLnum = endLnum and endLnum or lnum
    if endLnum < 0 then
        endLnum = lineCount + endLnum + 1
    end
    for _, hunk in ipairs(self:buildMissingHunk(lnum, endLnum)) do
        local hs, he = hunk[1], hunk[2]
        local lines = api.nvim_buf_get_lines(self.bufnr, hs - 1, he, true)
        for i = hs, he do
            self._lines[i] = lines[i - hs + 1]
        end
    end
    for i = lnum, endLnum do
        table.insert(res, self._lines[i])
    end
    return res
end

return Buffer
