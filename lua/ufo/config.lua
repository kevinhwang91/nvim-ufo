---@class UfoConfig
---@field provider_selector? function
---@field open_fold_hl_timeout number
---@field fold_virt_text_handler? function A global virtual text handler, reference to `ufo.setFoldVirtTextHandler`
---@field enable_fold_end_virt_text boolean
---@field preview table
local def = {
    open_fold_hl_timeout = 400,
    provider_selector = nil,
    fold_virt_text_handler = nil,
    enable_fold_end_virt_text = false,
    preview = {
        win_config = {
            border = 'rounded',
            winblend = 12,
            winhighlight = 'Normal:Normal'
        },
        mappings = {
            scrollB = '',
            scrollF = '',
            scrollU = '',
            scrollD = '',
            scrollE = '<C-E>',
            scrollY = '<C-Y>',
            close = 'q',
            switch = '<Tab>',
            trace = '<CR>',
        }
    }
}

---@type UfoConfig
local Config = {}


---@alias UfoProviderEnum
---| 'lsp'
---| 'treesitter'
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

local function init()
    local ufo = require('ufo')
    ---@type UfoConfig
    Config = vim.tbl_deep_extend('keep', ufo._config or {}, def)
    vim.validate({
        open_fold_hl_timeout = {Config.open_fold_hl_timeout, 'number'},
        provider_selector = {Config.provider_selector, 'function', true},
        fold_virt_text_handler = {Config.fold_virt_text_handler, 'function', true},
        preview_mappings = {Config.preview.mappings, 'table'}
    })

    local preview = Config.preview
    for msg, key in pairs(preview.mappings) do
        if key == '' then
            preview.mappings[msg] = nil
        end
    end
    ufo._config = nil
end

init()

return Config
