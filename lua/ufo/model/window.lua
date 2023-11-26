local utils = require('ufo.utils')

local api = vim.api
local cmd = vim.cmd

---@class UfoWindow
---@field winid number
---@field bufnr number
---@field lastBufnr number
---@field foldbuffer UfoFoldBuffer
---@field lastCurLnum number
---@field lastCurFoldStart number
---@field lastCurFoldEnd number
---@field isCurFoldHighlighted boolean
---@field foldedPairs table<number,number>
---@field foldedTextMaps table<number, table>
---@field _cursor number[]
---@field _width number
---@field _concealLevel boolean
local Window = {}
Window.__index = Window

function Window:new(winid)
    local o = self == Window and setmetatable({}, self) or self
    o.winid = winid
    o.bufnr = 0
    o.lastCurLnum = -1
    o.lastCurFoldStart = 0
    o.lastCurFoldEnd = 0
    o.isCurFoldHighlighted = false
    return o
end

--- Must invoke in on_win cycle
---@param bufnr number
---@param fb UfoFoldBuffer
function Window:onWin(bufnr, fb)
    self.lastBufnr = self.bufnr
    self.bufnr = bufnr
    self.foldbuffer = fb
    self.foldedPairs = {}
    self.foldedTextMaps = {}
    self._cursor = nil
    self._width = nil
    self._concealLevel = nil
end

function Window:cursor()
    if not self._cursor then
        self._cursor = api.nvim_win_get_cursor(self.winid)
    end
    return self._cursor
end

function Window:textWidth()
    if not self._width then
        local textoff = utils.textoff(self.winid)
        self._width = api.nvim_win_get_width(self.winid) - textoff
    end
    return self._width
end

function Window:concealLevel()
    if not self._concealLevel then
        self._concealLevel = vim.wo[self.winid].conceallevel
    end
    return self._concealLevel
end

function Window:foldEndLnum(fs)
    local fe = self.foldedPairs[fs]
    if not fe then
        fe = utils.foldClosedEnd(self.winid, fs)
        self.foldedPairs[fs] = fe
    end
    return fe
end

function Window:setCursorFoldedLineHighlight()
    local res = false
    if not self.isCurFoldHighlighted then
        -- TODO
        -- Upstream bug: Error in decoration provider (UNKNOWN PLUGIN).end
        require('promise').resolve():thenCall(function()
            utils.winCall(self.winid, function()
                cmd('setl winhl+=CursorLine:UfoCursorFoldedLine')
            end)
        end)
        self.isCurFoldHighlighted = true
        res = true
    end
    return res
end

function Window:clearCursorFoldedLineHighlight()
    local res = false
    if self.isCurFoldHighlighted or self.lastBufnr ~= 0 and self.lastBufnr ~= self.bufnr then
        utils.winCall(self.winid, function()
            cmd('setl winhl-=CursorLine:UfoCursorFoldedLine')
        end)
        self.isCurFoldHighlighted = false
        res = true
    end
    return res
end

return Window
