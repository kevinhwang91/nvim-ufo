local api = vim.api
local fn = vim.fn

local render = require('ufo.render')
local FloatWin = require('ufo.preview.floatwin')

--- Singleton
---@class UfoPreviewWinBar : UfoPreviewFloatWin
---@field winid number
---@field bufnr number
---@field virtTextId number
local WinBar = setmetatable({}, {__index = FloatWin})

function WinBar:build()
    return {
        relative = 'win',
        win = self:floatWinid(),
        focusable = false,
        anchor = 'NW',
        style = 'minimal',
        width = self.width,
        height = 1,
        row = 0,
        col = 0,
        noautocmd = true,
        zindex = self.zindex + 1
    }
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
    self.virtTextId = render.setVirtText(self.bufnr, self.ns, 0, self.virtText, 10, self.virtTextId)
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
        local bufnr = fn.bufnr('^UfoPreviewWinBar$')
        if bufnr > 0 then
            self.bufnr = bufnr
        else
            self.bufnr = api.nvim_create_buf(false, true)
            api.nvim_buf_set_name(self.bufnr, 'UfoPreviewWinBar')
        end
        vim.bo[self.bufnr].bufhidden = 'hide'
        WinBar:open(self.bufnr, wopts)
        local wo = vim.wo[self.winid]
        wo.winhl = 'Normal:UfoPreviewWinBar'
        wo.winblend = self.winblend
    end
    self:update()
    return self.winid
end

return WinBar
