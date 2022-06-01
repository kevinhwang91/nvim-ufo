---@class UfoConfig
---@field open_fold_hl_timeout number
---@field provider_selector function
local config = {}

local function init()
    local ufo = require('ufo')
    ---@type UfoConfig
    local def = {
        open_fold_hl_timeout = 400,
        provider_selector = nil
    }
    config = vim.tbl_deep_extend('keep', ufo._config or {}, def)
    ufo._config = nil
end

init()

return config
