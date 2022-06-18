---@class UfoConfig
---@field open_fold_hl_timeout number
---@field provider_selector function
---@field fold_virt_text_handler function
local Config = {}


---@alias UfoProviderEnum
---| 'lsp'
---| 'indent'

---
---@param bufnr number
---@param filetype string buffer filetype
---@return UfoProviderEnum|string[]|function|nil
---return a string type use ufo providers
---return a string in a table like a string type
---return empty string '' will disable any providers
---return `nil` will use default value {'lsp', 'indent'}
---@diagnostic disable-next-line: unused-function, unused-local
function Config.provider_selector(bufnr, filetype) end

---@class UfoFoldVirtTextHandlerContext
---@field bufnr number buffer for closed fold
---@field winid number window for closed fold
---@field text string text for the first line of closed fold

---run `:h nvim_buf_set_extmark` and search `virt_text` optional parameter for details
---@class ExtmarkVirtText
---@field text string
---@field highlight string|number

---@class UfoFoldVirtTextHandler
---Ufo actually uses a virtual text with `nvim_buf_set_extmark` to overlap the first line of
---closed fold
---@param virtText ExtmarkVirtText contained text and highlight captured by Ufo, reused by caller
---@param lnum number first line of closed fold, like `v:foldstart in foldtext()`
---@param endLnum number last line of closed fold, like `v:foldend in foldtext()`
---@param width number text area width, exclude the foldcolumn, signcolumn and numberwidth
---@param truncate fun(str: string, width: number): string truncate the str to become specific width,
---return width of string is equal or less than str's width.
---For example: '1': 1 cell, '你': 2 cells, '2': 1 cell, '好': 2 cells
---truncate('1你2好', 1) return '1'
---truncate('1你2好', 2) return '1'
---truncate('1你2好', 3) return '1你'
---truncate('1你2好', 4) return '1你2'
---truncate('1你2好', 5) return '1你2'
---truncate('1你2好', 6) return '1你2好'
---truncate('1你2好', 7) return '1你2好'
---truncate('1你2好', 8) return '1你2好'
---@param ctx UfoFoldVirtTextHandlerContext context for handler
---@return ExtmarkVirtText[]
---@diagnostic disable-next-line: unused-function, unused-local
function Config.fold_virt_text_handler(virtText, lnum, endLnum, width, truncate, ctx) end

local function init()
    local ufo = require('ufo')
    ---@type UfoConfig
    local def = {
        open_fold_hl_timeout = 400,
        provider_selector = nil,
        fold_virt_text_handler = nil,
    }
    Config = vim.tbl_deep_extend('keep', ufo._config or {}, def)
    ufo._config = nil
end

init()

return Config
