local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local utils = require('ufo.utils')

--- Singleton
---@class UfoPreviewFloatWin
---@field config table
---@field ns number
---@field winid number
---@field bufnr number
---@field bufferName string
---@field width number
---@field height number
---@field anchor string|'SW'|'NW'
---@field winblend number
---@field border string|'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[]
---@field lineCount number
---@field showScrollBar boolean
---@field topline number
---@field virtText UfoExtmarkVirtTextChunk[]
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

function FloatWin:build(winid, height, border, isAbove)
    local winfo = utils.getWinInfo(winid)
    local aboveLine = utils.winCall(winid, fn.winline) - 1
    local belowLine = winfo.height - aboveLine
    border = type(border) == 'string' and defaultBorder[border] or border
    self.border = vim.deepcopy(border)
    local row, col = 0, 0
    if isAbove then
        if aboveLine < height and belowLine > aboveLine then
            self.height = math.min(height, belowLine)
            row = aboveLine - self.height
        else
            self.height = math.min(height, aboveLine)
            row = 1
        end
    else
        if belowLine < height and belowLine < aboveLine then
            self.height = math.min(height, aboveLine)
            row = belowLine - self.height
        else
            if self:borderHasUpLine() and fn.screenrow() == 1 and aboveLine == 0 then
                self.border[1], self.border[2], self.border[3] = '', '', ''
            end
            self.height = math.min(height, belowLine)
            row = 0
        end
    end
    self.width = winfo.width - winfo.textoff
    if self:borderHasLeftLine() then
        col = col - 1
    end
    if not isAbove and self:borderHasUpLine() then
        row = row - 1
    end
    if self:borderHasRightLine() then
        self.width = self.width - 1
    end
    local anchor = isAbove and 'SW' or 'NW'
    return {
        border = self.border,
        relative = 'cursor',
        focusable = true,
        width = self.width,
        height = self.height,
        anchor = anchor,
        row = row,
        col = col,
        noautocmd = true,
        zindex = 51
    }
end

function FloatWin:validate()
    return utils.isWinValid(rawget(self, 'winid'))
end

function FloatWin.getConfig()
    local config = api.nvim_win_get_config(FloatWin.winid)
    local row, col = config.row, config.col
    -- row and col are a table value converted from the floating-point
    ---@diagnostic disable-next-line: need-check-nil
    config.row, config.col = tonumber(row[vim.val_idx]), tonumber(col[vim.val_idx])
    return config
end

function FloatWin:open(wopts, enter)
    if enter == nil then
        enter = false
    end
    self.winid = api.nvim_open_win(self:getBufnr(), enter, wopts)
    return self.winid
end

function FloatWin:close()
    if self:validate() then
        api.nvim_win_close(self.winid, true)
    end
    rawset(self, 'winid', nil)
end

function FloatWin:call(executor)
    utils.winCall(self.winid, executor)
end

function FloatWin:getBufnr()
    if utils.isBufLoaded(rawget(self, 'bufnr')) then
        return self.bufnr
    end
    local bufnr = fn.bufnr('^' .. self.bufferName .. '$')
    if bufnr > 0 then
        self.bufnr = bufnr
    else
        self.bufnr = api.nvim_create_buf(false, true)
        api.nvim_buf_set_name(self.bufnr, self.bufferName)
        vim.bo[self.bufnr].bufhidden = 'hide'
    end
    return self.bufnr
end

function FloatWin:setContent(text)
    vim.bo[self.bufnr].modifiable = true
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, text)
    vim.bo[self.bufnr].modifiable = false
    self.lineCount = #text
    self.showScrollBar = self.lineCount > self.height
    api.nvim_win_set_cursor(self.winid, {1, 0})
    cmd('norm! ze')
end

---
---@param winid number
---@param targetHeight number
---@param enter boolean
---@param isAbove boolean
---@param postHandle? fun()
---@return number
function FloatWin:display(winid, targetHeight, enter, isAbove, postHandle)
    local height = math.min(self.config.maxheight, targetHeight)
    local wopts = self:build(winid, height, self.config.border, isAbove)
    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
        if enter == true then
            api.nvim_set_current_win(self.winid)
        end
    else
        self:open(wopts, enter)
        self.winblend = self.config.winblend
        local wo = vim.wo[self.winid]
        wo.wrap = false
        wo.spell, wo.list = false, true
        wo.nu, wo.rnu = false, false
        wo.fen, wo.fdm, wo.fdc = false, 'manual', '0'
        wo.cursorline = enter == true
        wo.signcolumn, wo.colorcolumn = 'no', ''
        if wo.so == 0 then
            wo.so = 1
        end
        wo.winhl = self.config.winhighlight
        wo.winblend = self.winblend
    end
    if type(postHandle) == 'function' then
        postHandle()
    end
    return self.winid
end

function FloatWin:refreshTopline()
    self.topline = fn.line('w0', self.winid)
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
    self.bufferName = 'UfoPreviewFloatWin'
    self.config = config
    return self
end

function FloatWin:dispose()
    self:close()
    pcall(api.nvim_buf_delete, self.bufnr, {force = true})
    self.bufnr = nil
end

return FloatWin
