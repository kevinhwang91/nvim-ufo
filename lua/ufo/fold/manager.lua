local api = vim.api
local cmd = vim.cmd

local buffer     = require('ufo.model.foldbuffer')
local event      = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local bufmanager = require('ufo.bufmanager')
local utils      = require('ufo.utils')
local driver     = require('ufo.fold.driver')
local log        = require('ufo.lib.log')

---@class UfoFoldBufferManager
---@field buffers UfoFoldBuffer[]
---@field providerSelector function
---@field disposables UfoDisposable[]
local FoldBufferManager = {
    buffers = {},
    disposables = {}
}

local initialized

---
---@param namespace number
---@param selector function
---@return UfoFoldBufferManager
function FoldBufferManager:initialize(namespace, selector)
    if initialized then
        return self
    end
    self.ns = namespace
    self.providerSelector = selector
    local disposables = {
        disposable:create(function()
            for _, fb in pairs(self.buffers) do
                fb:dispose()
            end
            self.buffers = {}
        end)
    }
    event:on('BufDetach', function(bufnr)
        local fb = self:get(bufnr)
        if fb then
            fb:dispose()
        end
        self.buffers[bufnr] = nil
    end, disposables)
    event:on('BufReload', function(bufnr)
        local fb = self:get(bufnr)
        if fb then
            fb:reset()
            fb:resetFoldedLines()
        end
    end, disposables)
    self.disposables = disposables
    self.providerSelector = selector
    initialized = true
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
    for _, item in ipairs(self.disposables) do
        item:dispose()
    end
    initialized = false
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
    local providers = selector(fb.bufnr, fb:filetype())
    local t = type(providers)
    if t == 'nil' then
        res = {'lsp', 'indent'}
    elseif t == 'string' or t == 'function' then
        res = {providers}
    elseif t == 'table' then
        res = {}
        for _, m in ipairs(providers) do
            if #res == 2 then
                break
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

local function scanFoldedRanges(winid, lineCount)
    local res = {}
    local stack = {}
    local openFmt, closeFmt = '%dfoldopen', '%dfoldclose'
    for i = 1, lineCount do
        local skip = false
        while #stack > 0 and i >= stack[#stack] do
            local endLnum = table.remove(stack)
            local c = closeFmt:format(endLnum)
            cmd(c)
            log.info(c)
            skip = true
        end
        if not skip then
            local endLnum = utils.foldClosedEnd(winid, i)
            if endLnum ~= -1 then
                table.insert(stack, endLnum)
                table.insert(res, {i - 1, endLnum - 1})
                local c = openFmt:format(i)
                cmd(c)
                log.info(c)
            end
        end
    end
    return res
end

---
---@param fb UfoFoldBuffer
---@param winid number
---@param ranges? UfoFoldingRange[]
---@return boolean
function FoldBufferManager:applyFoldRanges(fb, winid, ranges)
    local changedtick = fb:changedtick()
    if not ranges and changedtick ~= fb.version then
        return false
    elseif utils.mode() ~= 'n' or not utils.isWinValid(winid) or
        utils.isDiffOrMarkerFold(winid) then
        fb.status = 'pending'
        return false
    end
    local rowPairs = {}
    if fb.version == 0 then
        for _, range in ipairs(scanFoldedRanges(winid, fb:lineCount())) do
            local row, endRow = range[1], range[2]
            rowPairs[row] = endRow
        end
    else
        local marks = api.nvim_buf_get_extmarks(fb.bufnr, self.ns, 0, -1, {details = true})
        for _, m in ipairs(marks) do
            local row, endRow = m[2], m[4].end_row
            rowPairs[row] = endRow
        end
    end
    fb.version = changedtick
    if ranges then
        fb.foldRanges = ranges
    end
    log.info('apply fold ranges:', fb.foldRanges)
    log.info('apply fold rowPairs:', rowPairs)
    driver:createFolds(winid, fb.foldRanges, rowPairs)
    return true
end

return FoldBufferManager
