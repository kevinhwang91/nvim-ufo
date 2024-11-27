local utils = require('ufo.utils')

local api = vim.api

---@class UfoWindow
---@field winid number
---@field bufnr number
---@field topRow number
---@field botRow number
---@field lastBufnr number
---@field foldbuffer UfoFoldBuffer
---@field lastCurLnum number
---@field lastCurFoldStart number
---@field lastCurFoldEnd number
---@field ns number
---@field cursorLineHighlight vim.api.keyset.hl_info
---@field foldedPairs table<number,number>
---@field foldedTextMaps table<number, table>
---@field lastTextWidth number
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
    o.ns = -1
    return o
end

--- Must invoke in on_win cycle
---@param bufnr number
---@param fb UfoFoldBuffer
---@param topRow number
---@param botRow number
function Window:onWin(bufnr, fb, topRow, botRow)
    self.lastBufnr = self.bufnr
    self.bufnr = bufnr
    self.foldbuffer = fb
    self.topRow = topRow
    self.botRow = botRow
    self.foldedPairs = {}
    self.foldedTextMaps = {}
    self.lastTextWidth = self:textWidth()
    self._cursor = nil
    self._width = nil
    self._concealLevel = nil
end

function Window:removeListOption(optionName, val)
    ---@type string
    local o = vim.wo[self.winid][optionName]
    local s, e = o:find(val, 1, true)
    if not s then
        return
    end
    local v = s == 1 and o:sub(e + 2) or o:sub(1, s - 2) .. o:sub(e + 1)
    vim.wo[self.winid][optionName] = v
end

function Window:appendListOption(optionName, val)
    ---@type string
    local o = vim.wo[self.winid][optionName]
    if o:len() == 0 then
        vim.wo[self.winid][optionName] = val
        return
    end
    if not o:find(val, 1, true) then
        vim.wo[self.winid][optionName] = o .. ',' .. val
    end
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

function Window:textWidthChanged()
    return self.lastTextWidth ~= self:textWidth()
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
    if not self.cursorLineHighlight then
        if utils.has10() then
            self.ns = api.nvim_get_hl_ns({winid = self.winid})
        end
        if self.ns > 0 then
            local hl = vim.api.nvim_get_hl(self.ns, {name = 'CursorLine'})
            if not next(hl) then
                hl = vim.api.nvim_get_hl(0, {name = 'CursorLine'})
                self.ns = 0
            end
            self.cursorLineHighlight = hl
            api.nvim_set_hl(self.ns, 'CursorLine', {
                link = 'UfoCursorFoldedLine',
                force = true
            })
        else
            if utils.has10() then
                self:appendListOption('winhl', 'CursorLine:UfoCursorFoldedLine')
            else
                -- TODO
                -- Upstream bug: `setl winhl` change curswant
                utils.winCall(self.winid, function()
                    local view = utils.saveView(0)
                    self:appendListOption('winhl', 'CursorLine:UfoCursorFoldedLine')
                    utils.restView(0, view)
                end)
            end
            self.cursorLineHighlight = {}
        end
        res = true
    end
    return res
end

function Window:clearCursorFoldedLineHighlight()
    local res = false
    if self.ns >= 0 then
        if self.cursorLineHighlight then
            local hl = vim.api.nvim_get_hl(self.ns, {name = 'CursorLine'})
            if next(hl) and hl.link == 'UfoCursorFoldedLine' then
                api.nvim_set_hl(self.ns, 'CursorLine', self.cursorLineHighlight)
            end
            self:removeListOption('winhl', 'CursorLine:UfoCursorFoldedLine')
            res = true
        end
    elseif self.cursorLineHighlight or self.lastBufnr ~= self.bufnr then
        self:removeListOption('winhl', 'CursorLine:UfoCursorFoldedLine')
        res = true
    end
    self.cursorLineHighlight = nil
    return res
end

return Window
