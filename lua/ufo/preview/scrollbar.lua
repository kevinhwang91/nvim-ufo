local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local utils = require('ufo.utils')
local extmark = require('ufo.render.extmark')
local FloatWin = require('ufo.preview.floatwin')

--- Singleton
---@class UfoPreviewScrollBar : UfoPreviewFloatWin
---@field winid number
---@field bufnr number
---@field topline number
local ScrollBar = setmetatable({}, {__index = FloatWin})

function ScrollBar:build()
    local col, border = self.width, self.border
    if border == 'shadow' then
        col = col - 1
    end
    return {
        relative = 'win',
        win = self:floatWinid(),
        focusable = false,
        anchor = 'NW',
        style = 'minimal',
        width = 1,
        height = self.height,
        row = 0,
        col = col,
        noautocmd = true,
        zindex = self.zindex + 1
    }
end

function ScrollBar:floatBufnr()
    return FloatWin.bufnr
end

function ScrollBar:floatWinid()
    return FloatWin.winid
end

---
---@param topline? number
function ScrollBar:update(topline)
    if not self.showScrollBar then
        self.winid = nil
        return
    end
    if not topline then
        topline = utils.getWinInfo(self:floatWinid()).topline
    end
    self.topline = topline
    local barSize = math.ceil(self.height * self.height / self.lineCount)
    if barSize == self.height and barSize < self.lineCount then
        barSize = self.height - 1
    end

    local barPos = math.ceil(self.height * topline / self.lineCount)
    local size = barPos + barSize - 1
    if size == self.height then
        if self.topline + self.height - 1 < self.lineCount then
            barPos = barPos - 1
        end
    elseif size > self.height then
        barPos = self.height - barSize + 1
    end

    if self:borderHasRightLine() then
        local wopts = self:build()
        wopts.height = barSize
        wopts.row = wopts.row + barPos - 1
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
        vim.wo[self.winid].winhl = 'Normal:UfoPreviewThumb'
    else
        api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
        for i = 1, self.height do
            if i >= barPos and i < barPos + barSize then
                extmark.setHighlight(self.bufnr, self.ns, i - 1, 0, i - 1, 1, 'UfoPreviewThumb')
            end
        end
    end
end

function ScrollBar:display()
    if not self.showScrollBar then
        self:close()
        return
    end
    local wopts = self:build()
    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
    else
        local bufnr = fn.bufnr('^UfoPreviewScrollBar$')
        if bufnr > 0 then
            self.bufnr = bufnr
        else
            self.bufnr = api.nvim_create_buf(false, true)
            api.nvim_buf_set_name(self.bufnr, 'UfoPreviewScrollBar')
        end
        vim.bo[self.bufnr].modifiable = true
        vim.bo[self.bufnr].bufhidden = 'hide'
        -- it is relative to floating window, need to redraw to make floating window validate
        cmd('redraw')
        ScrollBar:open(self.bufnr, wopts)
        local wo = vim.wo[self.winid]
        wo.winhl = 'Normal:UfoPreviewSbar'
        wo.winblend = self.winblend
    end
    local lines = {}
    for _ = 1, self.height do
        table.insert(lines, ' ')
    end
    vim.bo[self.bufnr].modifiable = true
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, lines)
    vim.bo[self.bufnr].modifiable = false
    self:update()
    return self.winid
end

return ScrollBar
