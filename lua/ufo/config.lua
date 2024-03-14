---@class UfoConfig
---@field provider_selector? function
---@field open_fold_hl_timeout number
---@field close_fold_kinds_for_ft table<string, UfoFoldingRangeKind[]>
---@field fold_virt_text_handler? UfoFoldVirtTextHandler A global virtual text handler, reference to `ufo.setFoldVirtTextHandler`
---@field enable_get_fold_virt_text boolean
---@field preview table
local def = {
    open_fold_hl_timeout = 400,
    provider_selector = nil,
    close_fold_kinds_for_ft = {default = {}},
    fold_virt_text_handler = nil,
    enable_get_fold_virt_text = false,
    preview = {
        win_config = {
            border = 'rounded',
            winblend = 12,
            winhighlight = 'Normal:Normal',
            maxheight = 20
        },
        mappings = {
            scrollB = '',
            scrollF = '',
            scrollU = '',
            scrollD = '',
            scrollE = '<C-E>',
            scrollY = '<C-Y>',
            jumpTop = '',
            jumpBot = '',
            close = 'q',
            switch = '<Tab>',
            trace = '<CR>'
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
---@param filetype string file type
---@param buftype string buffer type
---@return UfoProviderEnum|string[]|function|nil
---return a string type use ufo providers
---return a string in a table like a string type
---return empty string '' will disable any providers
---return `nil` will use default value {'lsp', 'indent'}
---@diagnostic disable-next-line: unused-function, unused-local
function Config.provider_selector(bufnr, filetype, buftype) end

local function init()
    local ufo = require('ufo')
    ---@type UfoConfig
    Config = vim.tbl_deep_extend('keep', ufo._config or {}, def)
    vim.validate({
        open_fold_hl_timeout = {Config.open_fold_hl_timeout, 'number'},
        provider_selector = {Config.provider_selector, 'function', true},
        close_fold_kinds_for_ft = {Config.close_fold_kinds_for_ft, 'table'},
        fold_virt_text_handler = {Config.fold_virt_text_handler, 'function', true},
        preview_mappings = {Config.preview.mappings, 'table'}
    })

    local preview = Config.preview
    for msg, key in pairs(preview.mappings) do
        if key == '' then
            preview.mappings[msg] = nil
        end
    end
    if Config.close_fold_kinds and not vim.tbl_isempty(Config.close_fold_kinds) then
        vim.notify('Option `close_fold_kinds` in `nvim-ufo` is deprecated, use `close_fold_kinds_for_ft` instead.',
            vim.log.levels.WARN)
        if not Config.close_fold_kinds_for_ft.default then
            Config.close_fold_kinds_for_ft.default = Config.close_fold_kinds
        end
    end
    ufo._config = nil
end

init()

return Config
