local api = vim.api
local fn = vim.fn
local utils = require('ufo.utils')

--- Singleton
---@class UfoPreviewFloatWin
---@field config table
---@field ns number
---@field winid number
---@field bufnr number
---@field width number
---@field height number
---@field row number
---@field col number
---@field zindex number
---@field winblend number
---@field border string|'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[]
---@field lineCount number
---@field showScrollBar boolean
local FloatWin = {}

-- upLine, rightLine, bottomLine, LeftLine
local defaultBorder = {
    none    = {false, false, false, false},
    single  = {true, true, true, true},
    double  = {true, true, true, true},
    rounded = {true, true, true, true},
    solid   = {true, true, true, true},
    shadow  = {false, true, true, false},
}

local function borderHasLine(border, index)
    local tBorder = type(border)
    if tBorder == 'string' then
        return (defaultBorder[border])[index]
    elseif tBorder == 'table' then
        local s = border[2 * index]
        return s ~= ''
    end
end

function FloatWin:BorderHasUpLine()
    return borderHasLine(self.border, 1)
end

function FloatWin:BorderHasRightLine()
    return borderHasLine(self.border, 2)
end

function FloatWin:BorderHasBottomLine()
    return borderHasLine(self.border, 3)
end

function FloatWin:BorderHasLeftLine()
    return borderHasLine(self.border, 4)
end

function FloatWin:build(targetWinid, height, border)
    local winfo = utils.getWinInfo(targetWinid)
    local top = utils.winCall(targetWinid, fn.winline) - 1
    local bot = winfo.height - top
    self.border = border
    if bot < height and bot < top then
        self.height = math.min(height, top)
        self.row = math.min(2, bot - (self.border == 'none' and 0 or 1)) - self.height
    else
        self.height = math.min(height, bot)
        self.row = 0
    end
    self.col = 0
    self.width = winfo.width - winfo.textoff
    if self:BorderHasLeftLine() then
        self.col = self.col - 1
    end
    if self:BorderHasUpLine() then
        self.row = self.row - 1
    end
    if self:BorderHasRightLine() then
        self.width = self.width - 1
    end
    self.zindex = 51
    return {
        border = self.border,
        relative = 'cursor',
        focusable = true,
        width = self.width,
        height = self.height,
        anchor = 'NW',
        row = self.row,
        col = self.col,
        noautocmd = true,
        zindex = self.zindex
    }
end

function FloatWin:validate()
    return utils.isWinValid(rawget(self, 'winid'))
end

function FloatWin:open(bufnr, wopts, enter)
    if enter == nil then
        enter = false
    end
    self.winid = api.nvim_open_win(bufnr, enter, wopts)
    api.nvim_win_set_cursor(self.winid, {1, 0})
    return self.winid
end

function FloatWin:close()
    if self:validate() then
        api.nvim_win_close(self.winid, true)
    end
end

function FloatWin:display(targetWinid, height, text, enter)
    local wopts = self:build(targetWinid, height, self.config.border)
    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
        if enter == true then
            api.nvim_set_current_win(enter)
        end
    else
        local bufnr = fn.bufnr('^UfoPreviewFloatWin$')
        if bufnr > 0 then
            self.bufnr = bufnr
        else
            self.bufnr = api.nvim_create_buf(false, true)
            api.nvim_buf_set_name(self.bufnr, 'UfoPreviewFloatWin')
        end
        vim.bo[self.bufnr].bufhidden = 'hide'
        self:open(self.bufnr, wopts, enter)
        self.winblend = self.config.winblend
        local wo = vim.wo[self.winid]
        wo.wrap = false
        wo.spell, wo.list = false, false
        wo.nu, wo.rnu = false, false
        wo.fen, wo.fdm, wo.fdc = false, 'manual', '0'
        wo.cursorline = false
        wo.signcolumn, wo.colorcolumn = 'no', ''
        wo.winhl = self.config.winhighlight
        wo.winblend = self.winblend
        wo.sidescrolloff = 0
    end
    vim.bo[self.bufnr].modifiable = true
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, text)
    vim.bo[self.bufnr].modifiable = false
    self.lineCount = api.nvim_buf_line_count(self.bufnr)
    self.showScrollBar = self.lineCount > self.height
    return self.winid
end

function FloatWin:initialize(ns, config)
    self.ns = ns
    local border = config.border
    local tBorder = type(border)
    if tBorder == 'string' then
        if not defaultBorder[border] then
            error(([[border string must be one of {%s}]])
                :format(table.concat(vim.tbl_keys(defaultBorder), ',')))
        end
    elseif tBorder == 'table' then
        assert(#border == 8, 'only support 8 chars for the border')
    else
        error('error border config')
    end
    self.config = config
    return self
end

function FloatWin:dispose()
    pcall(api.nvim_buf_delete, self.bufnr, {force = true})
end

return FloatWin
