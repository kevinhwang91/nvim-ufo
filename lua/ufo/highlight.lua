local cmd = vim.cmd
local api = vim.api
local fn = vim.fn

local event = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')

---@class UfoHighlight
local Highlight = {}
local initialized

---@type table<number|string, table>
local hlGroups

---@type table<string, string>
local signNames

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
            if not ok or hl[vim.type_idx] == vim.types.dictionary then
                hl = {}
            end
            rawset(tbl, k, hl)
            return hl
        end
    })
    local ok, hl = pcall(api.nvim_get_hl_by_name, 'Folded', termguicolors)
    if ok and hl.background then
        if termguicolors then
            cmd(('hi default UfoFoldedBg guibg=#%x'):format(hl.background))
        else
            cmd(('hi default UfoFoldedBg ctermbg=%d'):format(hl.background))
        end
    else
        cmd('hi default link UfoFoldedBg Visual')
    end
    ok, hl = pcall(api.nvim_get_hl_by_name, 'Normal', termguicolors)
    if ok and hl.foreground then
        if termguicolors then
            cmd(('hi default UfoFoldedFg guifg=#%x'):format(hl.foreground))
        else
            cmd(('hi default UfoFoldedFg ctermfg=%d'):format(hl.foreground))
        end
    else
        cmd('hi default UfoFoldedFg ctermfg=None guifg=None')
    end

    cmd([[
        hi default link UfoPreviewSbar PmenuSbar
        hi default link UfoPreviewThumb PmenuThumb
        hi default link UfoPreviewWinBar UfoFoldedBg
        hi default link UfoPreviewCursorLine Visual
        hi default link UfoFoldedEllipsis Comment
        hi default link UfoCursorFoldedLine CursorLine
    ]])
end

local function resetSignGroup()
    signNames = setmetatable({}, {
        __index = function(tbl, k)
            assert(fn.sign_define(k, {linehl = k}) == 0,
                   'Define sign name ' .. k .. 'failed')
            rawset(tbl, k, k)
            return k
        end
    })
    return disposable:create(function()
        for _, name in pairs(signNames) do
            pcall(fn.sign_undefine, name)
        end
    end)
end

function Highlight.hlGroups()
    if not initialized then
        Highlight:initialize()
    end
    return hlGroups
end

function Highlight.signNames()
    if not initialized then
        Highlight:initialize()
    end
    return signNames
end

---
---@return UfoHighlight
function Highlight:initialize()
    if initialized then
        return self
    end
    self.disposables = {}
    event:on('ColorScheme', resetHighlightGroup, self.disposables)
    resetHighlightGroup()
    table.insert(self.disposables, resetSignGroup())
    initialized = true
    return self
end

function Highlight:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
    initialized = false
end

return Highlight
