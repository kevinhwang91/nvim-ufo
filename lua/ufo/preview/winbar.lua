local api = vim.api

local render = require('ufo.render')
local FloatWin = require('ufo.preview.floatwin')

--- Singleton
---@class UfoPreviewWinBar : UfoPreviewFloatWin
---@field winid number
---@field bufnr number
---@field bufferName string
---@field virtTextId number
---@field virtText UfoExtmarkVirtTextChunk[]
local WinBar = setmetatable({}, {__index = FloatWin})

function WinBar:build()
    local config = FloatWin.getConfig()
    local row, col, height = config.row, config.col, config.height
    local anchor, zindex = config.anchor, config.zindex
    if anchor == 'NW' then
        row = self:borderHasUpLine() and row + 1 or row
    else
        row = (self:borderHasBottomLine() and row - 1 or row) - height
        row = math.max(row, self:borderHasUpLine() and 1 or 0)
    end
    return vim.tbl_extend('force', config, {
        anchor = 'NW',
        height = 1,
        row = row,
        col = self:borderHasLeftLine() and col + 1 or col,
        style = 'minimal',
        noautocmd = true,
        focusable = false,
        border = 'none',
        zindex = zindex + 1
    })
end

function WinBar:floatWinid()
    return FloatWin.winid
end

function WinBar:update()
    if self.topline == 1 then
        self:close()
        return
    end
    if not self:validate() then
        self:display()
    end
    self.virtTextId = render.setVirtText(self.bufnr, self.ns, 0, 0, self.virtText, {
        id = self.virtTextId
    })
end

function WinBar:display()
    if self.topline == 1 then
        self:close()
        return
    end
    local wopts = self:build()
    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
    else
        WinBar:open(wopts)
        local wo = vim.wo[self.winid]
        wo.winhl = 'Normal:UfoPreviewWinBar'
        wo.winblend = self.winblend
    end
    self:update()
    return self.winid
end

function WinBar:initialize()
    self.bufferName = 'UfoPreviewWinBar'
    self.virtTextId = nil
    return self
end

return WinBar
