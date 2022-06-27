local event = require('ufo.lib.event')
local cmd = vim.cmd
local api = vim.api

---@class UfoHighlight
local Highlight = {}
local initialized
local hlGroups

local function resetHighlightGroup()
    local termguicolors = vim.o.termguicolors
    hlGroups = setmetatable({}, {
        __index = function(tbl, k)
            local ok, hl
            if type(k) == 'number' then
                ok, hl = pcall(api.nvim_get_hl_by_id, k, termguicolors)
            else
                ok, hl = pcall(api.nvim_get_hl_by_name, k, termguicolors)
            end
            if not ok then
                hl = {}
            end
            rawset(tbl, k, hl)
            return hl
        end})
    local ok, hl = pcall(api.nvim_get_hl_by_name, 'Folded', termguicolors)
    if ok and hl.background then
        if termguicolors then
            cmd(('hi UfoFoldedBg guibg=#%x'):format(hl.background))
        else
            cmd(('hi UfoFoldedBg ctermbg=%d'):format(hl.background))
        end
    else
        cmd('hi default link UfoFoldedBg Visual')
    end
    ok, hl = pcall(api.nvim_get_hl_by_name, 'Normal', termguicolors)
    if ok and hl.foreground then
        if termguicolors then
            cmd(('hi UfoFoldedFg guifg=#%x'):format(hl.foreground))
        else
            cmd(('hi UfoFoldedFg ctermfg=%d'):format(hl.foreground))
        end
    else
        cmd('hi default UfoFoldedFg ctermfg=None guifg=None')
    end
    cmd('hi default link UfoFoldedEllipsis Comment')
end

function Highlight.hlGroups()
    return hlGroups
end

---
---@return UfoHighlight
function Highlight:initialize()
    if initialized then
        return
    end
    self.disposables = {}
    event:on('ColorScheme', resetHighlightGroup, self.disposables)
    resetHighlightGroup()
    initialized = true
    return self
end

function Highlight:dispose()
    for _, item in ipairs(self.disposables) do
        item:dispose()
    end
    initialized = false
end

return Highlight
