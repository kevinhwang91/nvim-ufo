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

local defaultBorder = {
    none    = {'', '', '', '', '', '', '', ''},
    single  = {'┌', '─', '┐', '│', '┘', '─', '└', '│'},
    double  = {'╔', '═', '╗', '║', '╝', '═', '╚', '║'},
    rounded = {'╭', '─', '╮', '│', '╯', '─', '╰', '│'},
    solid   = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '},
    shadow  = {'', '', {' ', 'FloatShadowThrough'}, {' ', 'FloatShadow'},
               {' ', 'FloatShadow'}, {' ', 'FloatShadow'}, {' ', 'FloatShadowThrough'}, ''},
}

local function borderHasLine(border, index)
    local s = border[index]
    if type(s) == 'string' then
        return s ~= ''
    else
        return s[1] ~= ''
    end
end

function FloatWin:borderHasUpLine()
    return borderHasLine(self.border, 2)
end

function FloatWin:borderHasRightLine()
    return borderHasLine(self.border, 4)
end

function FloatWin:borderHasBottomLine()
    return borderHasLine(self.border, 6)
end

function FloatWin:borderHasLeftLine()
    return borderHasLine(self.border, 8)
end

function FloatWin:build(targetWinid, height, border, isAbove)
    local winfo = utils.getWinInfo(targetWinid)
    local aboveLine = utils.winCall(targetWinid, fn.winline) - 1
    local belowLine = winfo.height - aboveLine
    self.border = type(border) == 'string' and vim.deepcopy(defaultBorder[border]) or border
    if isAbove then
        if aboveLine < height and belowLine > aboveLine then
            self.height = math.min(height, belowLine)
            self.row = aboveLine - self.height
        else
            self.height = math.min(height, aboveLine)
            self.row = 1
        end
    else
        if belowLine < height and belowLine < aboveLine then
            self.height = math.min(height, aboveLine)
            self.row = belowLine - self.height
        else
            if self:borderHasUpLine() and fn.screenrow() == 1 and aboveLine == 0 then
                self.border[1], self.border[2], self.border[3] = '', '', ''
            end
            self.height = math.min(height, belowLine)
            self.row = 0
        end
    end
    self.col = 0
    self.width = winfo.width - winfo.textoff
    if self:borderHasLeftLine() then
        self.col = self.col - 1
    end
    if not isAbove and self:borderHasUpLine() then
        self.row = self.row - 1
    end
    if self:borderHasRightLine() then
        self.width = self.width - 1
    end
    local anchor = isAbove and 'SW' or 'NW'
    self.zindex = 51
    return {
        border = self.border,
        relative = 'cursor',
        focusable = true,
        width = self.width,
        height = self.height,
        anchor = anchor,
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
    self.winid = nil
end

function FloatWin:display(targetWinid, text, enter, isAbove)
    local height = math.min(self.config.maxheight, #text)
    local wopts = self:build(targetWinid, height, self.config.border, isAbove)
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
        wo.spell, wo.list = false, true
        wo.nu, wo.rnu = false, false
        wo.fen, wo.fdm, wo.fdc = false, 'manual', '0'
        wo.cursorline = enter == true
        wo.signcolumn, wo.colorcolumn = 'no', ''
        wo.winhl = self.config.winhighlight
        wo.winblend = self.winblend
    end
    vim.bo[self.bufnr].modifiable = true
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, text)
    vim.bo[self.bufnr].modifiable = false
    self.lineCount = #text
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
    self.winid = nil
    self.bufnr = nil
end

return FloatWin
