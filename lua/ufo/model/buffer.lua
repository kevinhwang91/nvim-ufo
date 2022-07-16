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
    o._changedtick = api.nvim_buf_get_changedtick(bufnr)
    o._lines = nil
    o._lineCount = nil
    o._q = {}
    return o
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
            table.insert(self._q, {firstLine, lastLine, lastLineUpdated})
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
            self._lines = nil
            event:emit('BufReload', bufnr)
        end
    })
    ---@diagnostic enable: redefined-local, unused-local
    if self.attached then
        event:emit('BufAttach', self.bufnr)
    end
    return self.attached
end

function Buffer:buildMissingHunk()
    local hunks = {}
    local s, e
    local cnt = 0
    for i = 1, self._lineCount do
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
    return hunks, cnt
end

function Buffer:handleChanged()
    for _, q in ipairs(self._q) do
        local firstLine, lastLine, lastLineUpdated = q[1], q[2], q[3]
        local delta = lastLineUpdated - lastLine
        if delta == 0 then
            for i = firstLine + 1, lastLine do
                self._lines[i] = nil
            end
        elseif firstLine == lastLineUpdated then
            local ei = self._lineCount + delta
            for i = firstLine + 1, ei do
                self._lines[i] = self._lines[i - delta]
            end
            for i = ei + 1, self._lineCount do
                self._lines[i] = nil
            end
        else
            local newLines = {}
            for i = 1, firstLine do
                newLines[i] = self._lines[i]
            end
            local ni = firstLine + 1
            while ni <= lastLineUpdated do
                newLines[ni] = nil
                ni = ni + 1
            end
            for i = lastLine + 1, self._lineCount do
                newLines[ni] = self._lines[i]
                ni = ni + 1
            end
            self._lines = newLines
        end
        self._lineCount = self._lineCount + delta
    end
    self._q = {}
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
    if self._lineCount then
        self:handleChanged()
        return self._lineCount
    else
        return api.nvim_buf_line_count(self.bufnr)
    end
end

---@param lnum number
---@param endLnum? number
---@return string[]
function Buffer:lines(lnum, endLnum)
    local res = {}
    if not self._lines then
        self._lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, true)
        self._lineCount = #self._lines
        self._q = {}
    else
        self:handleChanged()
    end
    assert(self._lineCount >= lnum, 'index out of bounds')
    local hunks, cnt = self:buildMissingHunk()
    endLnum = endLnum and endLnum or lnum
    if endLnum < 0 then
        endLnum = self._lineCount + endLnum + 1
    end
    if cnt > self._lineCount / 4 and #hunks > 2 then
        self._lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, true)
    else
        for _, hunk in ipairs(hunks) do
            local hs, he = hunk[1], hunk[2]
            if hs <= lnum and lnum <= he or hs <= endLnum and endLnum <= he or
                lnum < hs or endLnum > he then
                local lines = api.nvim_buf_get_lines(self.bufnr, hs - 1, he, true)
                for i = hs, he do
                    self._lines[i] = lines[i - hs + 1]
                end
            end
        end
    end
    for i = lnum, endLnum do
        table.insert(res, self._lines[i])
    end
    return res
end

return Buffer
