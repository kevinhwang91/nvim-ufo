local api = vim.api

local buffer = require('ufo.model.foldbuffer')
local event = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local bufmanager = require('ufo.bufmanager')
local utils = require('ufo.utils')
local driver = require('ufo.fold.driver')
local log = require('ufo.lib.log')

---@class UfoFoldBufferManager
---@field initialized boolean
---@field buffers UfoFoldBuffer[]
---@field providerSelector function
---@field closeKindsMap table<string,UfoFoldingRangeKind[]>
---@field disposables UfoDisposable[]
local FoldBufferManager = {}

---
---@param namespace number
---@param selector function
---@param closeKindsMap table<string,UfoFoldingRangeKind[]>
---@return UfoFoldBufferManager
function FoldBufferManager:initialize(namespace, selector, closeKindsMap, closeCurrentLineFoldsMap)
    if self.initialized then
        return self
    end
    self.ns = namespace
    self.providerSelector = selector
    self.closeKindsMap = closeKindsMap
    self.closeCurrentLineFoldsMap = closeCurrentLineFoldsMap
    self.buffers = {}
    self.initialized = true
    self.disposables = {}
    table.insert(self.disposables, disposable:create(function()
        for _, fb in pairs(self.buffers) do
            fb:dispose()
        end
        self.buffers = {}
        self.initialized = false
    end))
    event:on('BufDetach', function(bufnr)
        local fb = self:get(bufnr)
        if fb then
            fb:dispose()
        end
        self.buffers[bufnr] = nil
    end, self.disposables)
    event:on('BufReload', function(bufnr)
        local fb = self:get(bufnr)
        if fb then
            fb:dispose()
        end
    end, self.disposables)

    local function optChanged(bufnr, new, old)
        if old ~= new then
            local fb = self:get(bufnr)
            if fb then
                fb.providers = nil
            end
        end
    end

    event:on('BufTypeChanged', optChanged, self.disposables)
    event:on('FileTypeChanged', optChanged, self.disposables)
    event:on('BufLinesChanged', function(bufnr, _, firstLine, lastLine, lastLineUpdated)
        local fb = self:get(bufnr)
        if fb then
            fb:handleFoldedLinesChanged(firstLine, lastLine, lastLineUpdated)
        end
    end, self.disposables)
    self.providerSelector = selector
    return self
end

---
---@param bufnr number
---@return boolean
function FoldBufferManager:attach(bufnr)
    local fb = self:get(bufnr)
    if not fb then
        self.buffers[bufnr] = buffer:new(bufmanager:get(bufnr), self.ns)
    end
    return not fb
end

---
---@param bufnr number
---@return UfoFoldBuffer
function FoldBufferManager:get(bufnr)
    return self.buffers[bufnr]
end

function FoldBufferManager:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

function FoldBufferManager:parseBufferProviders(fb, selector)
    if not utils.isBufLoaded(fb.bufnr) then
        return
    end
    if not selector then
        fb.providers = {'lsp', 'indent'}
        return
    end
    local res
    local providers = selector(fb.bufnr, fb:filetype(), fb:buftype())
    local t = type(providers)
    if t == 'nil' then
        res = {'lsp', 'indent'}
    elseif t == 'string' or t == 'function' then
        res = {providers}
    elseif t == 'table' then
        res = {}
        for _, m in ipairs(providers) do
            if #res == 2 then
                error('Return value of `provider_selector` only supports {`main`, `fallback`} ' ..
                    [[combo, don't add providers more than two into return table.]])
            end
            table.insert(res, m)
        end
    else
        res = {''}
    end
    fb.providers = res
end

function FoldBufferManager:isFoldMethodsDisabled(fb)
    if not fb.providers then
        self:parseBufferProviders(fb, self.providerSelector)
    end
    return not fb.providers or fb.providers[1] == ''
end

function FoldBufferManager:getRowPairs(winid)
    local rowPairs = {}
    local pairs, closed = driver:getFoldsAndClosedInfo(winid)
    for _, lnum in ipairs(closed) do
        local endLnum = pairs[lnum]
        rowPairs[lnum - 1] = endLnum - 1
    end
    return rowPairs
end

---
---@param bufnr number
---@param ranges? UfoFoldingRange[]
---@param manual? boolean
---@return number
function FoldBufferManager:applyFoldRanges(bufnr, ranges, manual)
    local fb = self:get(bufnr)
    if not fb then
        return -1
    end
    local changedtick = fb:changedtick()
    if ranges then
        fb.foldRanges = ranges
        fb.version = changedtick
    elseif changedtick ~= fb.version then
        return -1
    end
    local winid, windows = utils.getWinByBuf(bufnr)
    if winid == -1 or not utils.isWinValid(winid) then
        return -1
    elseif not vim.wo[winid].foldenable or utils.isDiffOrMarkerFold(winid) then
        return -1
    elseif vim.fn.getcmdwintype() ~= "" then
        return -1
    elseif utils.mode() ~= 'n' then
        return -1
    end
    local rowPairs = {}
    local isFirstApply = not fb.scanned
    if not manual and not fb.scanned or windows then
        rowPairs = self:getRowPairs(winid)
        local kinds = self.closeKindsMap[fb:filetype()] or self.closeKindsMap.default
        local closeCurrentLineFolds = self.closeCurrentLineFoldsMap[fb:filetype()] or self.closeCurrentLineFoldsMap.default
        local curRow = api.nvim_win_get_cursor(winid)[1] - 1
        for _, range in ipairs(fb.foldRanges) do
            if range.kind and vim.tbl_contains(kinds, range.kind) then
                local startLine, endLine = range.startLine, range.endLine
                if closeCurrentLineFolds or curRow <= startLine or curRow > endLine then
                    rowPairs[startLine] = endLine
                end
            end
        end
        for startLine, endLine in pairs(rowPairs) do
            fb:closeFold(startLine + 1, endLine + 1)
        end
        fb.scanned = true
    else
        -- Sync internal state with vim's actual fold state before getting extmarks.
        -- This ensures manually opened folds (via zo) are not re-closed.
        fb:syncFoldedLines(winid)
        local ok, res = pcall(function()
            for _, range in ipairs(fb:getRangesFromExtmarks()) do
                local row, endRow = range[1], range[2]
                rowPairs[row] = endRow
            end
        end)
        if not ok then
            log.info(res)
            fb:resetFoldedLines(true)
            rowPairs = self:getRowPairs(winid)
            for startLine, endLine in pairs(rowPairs) do
                fb:closeFold(startLine + 1, endLine + 1)
            end
        end
    end

    local view, wrow
    -- topline may changed after applying folds, restore topline to save our eyes
    if isFirstApply and not vim.tbl_isempty(rowPairs) then
        view = utils.saveView(winid)
        wrow = utils.wrow(winid)
    end
    log.info('apply fold ranges:', fb.foldRanges)
    log.info('apply fold rowPairs:', rowPairs)
    driver:createFolds(winid, fb.foldRanges, rowPairs)
    if view and utils.wrow(winid) ~= wrow then
        view.topline, view.topfill = utils.evaluateTopline(winid, view.lnum, wrow)
        utils.restView(winid, view)
    end
    return winid
end

return FoldBufferManager
