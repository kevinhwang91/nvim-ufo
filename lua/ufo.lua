local api = vim.api

---Export methods to the users, `require('ufo').method(...)`
---@class Ufo
local M = {}

---Peek the folded line under cursor, any motions in the normal window will close the floating window.
---@param enter? boolean enter the floating window, default value is false
---@param nextLineIncluded? boolean include the next line of last line of closed fold, default is true
---@return number? winid return the winid if successful, otherwise return nil
function M.peekFoldedLinesUnderCursor(enter, nextLineIncluded)
    return require('ufo.preview'):peekFoldedLinesUnderCursor(enter, nextLineIncluded)
end

---Go to previous start fold. Neovim can't go to previous start fold directly, it's an extra motion.
function M.goPreviousStartFold()
    require('ufo.action').goPreviousStartFold()
end

---Go to previous closed fold. It's an extra motion.
function M.goPreviousClosedFold()
    require('ufo.action').goPreviousClosedFold()
end

---Go to next closed fold. It's an extra motion.
function M.goNextClosedFold()
    return require('ufo.action').goNextClosedFold()
end

---Close all folds but keep foldlevel
function M.closeAllFolds()
    return M.closeFoldsWith(0)
end

---Open all folds but keep foldlevel
function M.openAllFolds()
    return require('ufo.action').openFoldsExceptKinds()
end

---Close the folds with a higher level,
---Like execute `set foldlevel=level` but keep foldlevel
---@param level? number fold level, `v:count` by default
function M.closeFoldsWith(level)
    return require('ufo.action').closeFolds(level or vim.v.count)
end

---Open folds except specified kinds
---@param kinds? UfoFoldingRangeKind[] kind in ranges, get default kinds from `config.close_fold_kinds_for_ft`
function M.openFoldsExceptKinds(kinds)
    if not kinds then
        local c = require('ufo.config')
        if c.close_fold_kinds and not vim.tbl_isempty(c.close_fold_kinds) then
            kinds = c.close_fold_kinds
        else
            kinds = c.close_fold_kinds_for_ft[vim.bo.ft] or c.close_fold_kinds_for_ft.default
        end
    end
    return require('ufo.action').openFoldsExceptKinds(kinds)
end

---Inspect ufo information by bufnr
---@param bufnr? number buffer number, current buffer by default
function M.inspect(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local msg = require('ufo.main').inspectBuf(bufnr)
    if not msg then
        vim.notify(('Buffer %d has not been attached.'):format(bufnr), vim.log.levels.ERROR)
    else
        vim.notify(table.concat(msg, '\n'), vim.log.levels.INFO)
    end
end

---Enable ufo
function M.enable()
    require('ufo.main').enable()
end

---Disable ufo
function M.disable()
    require('ufo.main').disable()
end

---Check whether the buffer has been attached
---@param bufnr? number buffer number, current buffer by default
---@return boolean
function M.hasAttached(bufnr)
    return require('ufo.main').hasAttached(bufnr)
end

---Attach bufnr to enable all features
---@param bufnr? number buffer number, current buffer by default
function M.attach(bufnr)
    require('ufo.main').attach(bufnr)
end

---Detach bufnr to disable all features
---@param bufnr? number buffer number, current buffer by default
function M.detach(bufnr)
    require('ufo.main').detach(bufnr)
end

---Enable to get folds and update them at once
---@param bufnr? number buffer number, current buffer by default
---@return string|'start'|'pending'|'stop' status
function M.enableFold(bufnr)
    return require('ufo.main').enableFold(bufnr)
end

---Disable to get folds
---@param bufnr? number buffer number, current buffer by default
---@return string|'start'|'pending'|'stop' status
function M.disableFold(bufnr)
    return require('ufo.main').disableFold(bufnr)
end

---Get foldingRange from the ufo internal providers by name
---@param bufnr number
---@param providerName string|'lsp'|'treesitter'|'indent'
---@return UfoFoldingRange[]|Promise
function M.getFolds(bufnr, providerName)
    if type(bufnr) == 'string' and type(providerName) == 'number' then
        --TODO signature is changed (swap parameters), notify deprecated in next released
        ---@deprecated
        ---@diagnostic disable-next-line: cast-local-type
        bufnr, providerName = providerName, bufnr
    end
    local func = require('ufo.provider'):getFunction(providerName)
    return func(bufnr)
end

---Apply foldingRange at once.
---ufo always apply folds asynchronously, this function can apply folds synchronously.
---Note: Get ranges from 'lsp' provider is asynchronous.
---@param bufnr number
---@param ranges UfoFoldingRange[]
---@return number winid return the winid if successful, otherwise return -1
function M.applyFolds(bufnr, ranges)
    vim.validate({bufnr = {bufnr, 'number', true}, ranges = {ranges, 'table'}})
    return require('ufo.fold').apply(bufnr, ranges, true)
end

---Merge ufo providers in one
---Pass all ufo providers in a list of strings or functions. If the element is a string, it will be
---treated as a default ufo provider, and this method will query the folds from it. If it is a
---function, it will be executed to get the folds.
---This method will return a new function that gets the folds of all merged providers. The
---returned function can be used to configure the `ufo.setup.provider_selector`. E.g.:
---    require('ufo').setup({
---        provider_selector = function(bufnr, filetype, buftype)
---            return require('ufo').mergeProviders({ 'lsp', 'indent', funcThatReturnsFoldRanges })
---        end,
---    })
---@alias ProviderToMerge string|fun(bufnr: number): UfoFoldingRange[]
---@param providers ProviderToMerge[] Ufo providers names or functions that gets folds
---@return function(bufnr): UfoFoldingRange[] A function that gets the folds of all merged providers
function M.mergeProviders(providers)
    local ufo = require('ufo')

    return function(bufnr)
        local allFolds = {}

        -- Gets the folds from each provider and merge it before returning. Strings are
        -- treated as default UFO providers and functions are executed to get the folds
        for _, provider in ipairs(providers) do
            local providerFolds = {}

            if type(provider) == 'string' then
                providerFolds = ufo.getFolds(bufnr, provider)

            elseif type(provider) == 'function' then
                providerFolds = provider(bufnr)
            end

            -- `providerFolds` can be nil if the `getFolds` method does not return anything,
            -- so need to add a 'or {}' at the end
            vim.list_extend(allFolds, providerFolds or {})
        end

        return allFolds
    end
end

---Setup configuration and enable ufo
---@param opts? UfoConfig
function M.setup(opts)
    opts = opts or {}
    M._config = opts
    M.enable()
end

---------------------------------------setFoldVirtTextHandler---------------------------------------

---@class UfoFoldVirtTextHandlerContext
---@field bufnr number buffer for closed fold
---@field winid number window for closed fold
---@field text string text for the first line of closed fold
---@field get_fold_virt_text fun(lnum: number): UfoExtmarkVirtTextChunk[] a function to get virtual text by lnum

---@class UfoExtmarkVirtTextChunk
---@field [1] string text
---@field [2] string|number highlight

---Set a fold virtual text handler for a buffer, will override global handler if it's existed.
---Ufo actually uses a virtual text with \`nvim_buf_set_extmark\` to overlap the first line of closed fold
---run \`:h nvim_buf_set_extmark | call search('virt_text')\` for detail.
---Return `{}` will not render folded line but only keep a extmark for providers.
---@diagnostic disable: undefined-doc-param
---Detail for handler function:
---@param virtText UfoExtmarkVirtTextChunk[] contained text and highlight captured by Ufo, export to caller
---@param lnum number first line of closed fold, like \`v:foldstart\` in foldtext()
---@param endLnum number last line of closed fold, like \`v:foldend\` in foldtext()
---@param width number text area width, exclude foldcolumn, signcolumn and numberwidth
---@param truncate fun(str: string, width: number): string truncate the str to become specific width,
---return width of string is equal or less than width (2nd argument).
---For example: '1': 1 cell, '你': 2 cells, '2': 1 cell, '好': 2 cells
---truncate('1你2好', 1) return '1'
---truncate('1你2好', 2) return '1'
---truncate('1你2好', 3) return '1你'
---truncate('1你2好', 4) return '1你2'
---truncate('1你2好', 5) return '1你2'
---truncate('1你2好', 6) return '1你2好'
---truncate('1你2好', 7) return '1你2好'
---@param ctx UfoFoldVirtTextHandlerContext the context used by ufo, export to caller

---@alias UfoFoldVirtTextHandler fun(virtText: UfoExtmarkVirtTextChunk[], lnum: number, endLnum: number, width: number, truncate: fun(str: string, width: number), ctx: UfoFoldVirtTextHandlerContext): UfoExtmarkVirtTextChunk[]

---@param bufnr number
---@param handler UfoFoldVirtTextHandler
function M.setFoldVirtTextHandler(bufnr, handler)
    vim.validate({bufnr = {bufnr, 'number', true}, handler = {handler, 'function'}})
    require('ufo.decorator'):setVirtTextHandler(bufnr, handler)
end

---@diagnostic disable: undefined-doc-param
---------------------------------------setFoldVirtTextHandler---------------------------------------

return M
