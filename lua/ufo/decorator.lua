local api = vim.api
local fn  = vim.fn

local utils  = require('ufo.utils')
local log    = require('ufo.log')
local config = require('ufo.config')

local foldbuffer = require('ufo.fold.buffer')
local highlight = require('ufo.highlight')
local treesitter = require('ufo.treesitter')

local initialized
local hlGroups


---@class UfoDecorator
---@field namespace number
---@field virtTextHandler? function[]
---@field disposables table
local Decorator = {}

local collection
local redrawType

local function fillSlots(col, endCol, hlGroup, priority, hlGroupSlots, prioritySlots)
    if not hlGroup or not hlGroups[hlGroup].foreground then
        return
    end
    for i = col + 1, endCol do
        local oldPriority = prioritySlots[i]
        if not oldPriority or oldPriority <= priority then
            prioritySlots[i] = priority
            hlGroupSlots[i] = hlGroup
        end
    end
end

local function getVirtText(bufnr, text, lnum, syntax, namespaces)
    local len = #text
    if len == 0 then
        return {{'', 'UfoFoldedFg'}}
    end
    local prioritySlots = {}
    local hlGroupSlots = {}
    for _, n in pairs(namespaces) do
        local marks = api.nvim_buf_get_extmarks(bufnr, n,
                                                {lnum - 1, 0}, {lnum - 1, -1},
                                                {details = true})
        for _, m in ipairs(marks) do
            local col, details = m[3], m[4]
            if col < len then
                local endCol = math.min(details.end_col or (col + 1), len)
                local hlGroup = details.hl_group
                local priority = details.priority
                fillSlots(col, endCol, hlGroup, priority, hlGroupSlots, prioritySlots)
            end
        end
    end
    for _, m in ipairs(treesitter.getHighlightInRow(bufnr, lnum - 1)) do
        local hlGroup, priority, col, endCol = m[1], m[2], m[3], m[4]
        if endCol == -1 then
            endCol = len
        end
        fillSlots(col, endCol, hlGroup, priority, hlGroupSlots, prioritySlots)
    end
    if syntax then
        api.nvim_buf_call(bufnr, function()
            for i = 1, len do
                if not prioritySlots[i] then
                    local hlId = fn.synID(lnum, i, true)
                    prioritySlots[i] = 1
                    hlGroupSlots[i] = hlId
                end
            end
        end)
    end
    local virtText = {}
    local lastHlGroup = hlGroupSlots[1] or 'UfoFoldedFg'
    local lastIndex = 1
    for i = 2, len do
        local hlGroup = hlGroupSlots[i] or 'UfoFoldedFg'
        if lastHlGroup ~= hlGroup then
            table.insert(virtText, {text:sub(lastIndex, i - 1), lastHlGroup})
            lastIndex = i
            lastHlGroup = hlGroup
        end
    end
    table.insert(virtText, {text:sub(lastIndex), lastHlGroup})
    return virtText
end

local function unHandledFoldedLnums(fb, rows)
    local lastRow = rows[1]
    local folded = {}
    for i = 2, #rows do
        local lnum = lastRow + 1
        local closed = fb:hasClosed(lnum)
        if rows[i] > lnum then
            if not closed and utils.foldClosed(0, lnum) == lnum then
                table.insert(folded, lnum)
            end
        elseif closed then
            fb:openFold(lnum)
        end
        lastRow = rows[i]

    end

    local lnum = lastRow + 1
    local closed = fb:hasClosed(lnum)
    if utils.foldClosed(0, lnum) == lnum then
        if not closed then
            table.insert(folded, lnum)
        end
    elseif closed then
        fb:openFold(lnum)
    end
    return folded
end

---@diagnostic disable-next-line: unused-local
local function onStart(name, tick, redrawT)
    redrawType = redrawT
    collection = {}
end

---@diagnostic disable-next-line: unused-local
local function onWin(name, winid, bufnr, topRow, botRow)
    local fb = foldbuffer:get(bufnr)
    if not fb or not vim.wo[winid].foldenable then
        collection[winid] = nil
        return false
    end
    collection[winid] = {
        winid = winid,
        bufnr = bufnr,
        rows = {}
    }
end

---@diagnostic disable-next-line: unused-local
local function onLine(name, winid, bufnr, row)
    table.insert(collection[winid].rows, row)
end

---@diagnostic disable-next-line: unused-local
local function onEnd(name, tick)
    local nss, mode
    for winid, data in pairs(collection or {}) do
        local bufnr = data.bufnr
        local fb = foldbuffer:get(bufnr)
        if #data.rows > 0 then
            utils.winCall(winid, function()
                local folded = unHandledFoldedLnums(fb, data.rows)
                local len = #folded
                if len == 0 then
                    return
                end
                local textoff = utils.textoff(winid)
                local width = api.nvim_win_get_width(winid) - textoff
                local syntax = vim.bo[bufnr].syntax ~= ''
                if not nss then
                    nss = {}
                    for _, namespace in pairs(api.nvim_get_namespaces()) do
                        if Decorator.namespace ~= namespace then
                            table.insert(nss, namespace)
                        end
                    end
                end
                for i = 1, len do
                    local lnum = folded[i]
                    local endLnum = utils.foldClosedEnd(0, lnum)
                    local text = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
                    local virtText
                    local handler = Decorator.getVirtTextHandler(bufnr)
                    if not handler then
                        width = width - 3
                    end
                    text = utils.textLimitedByWidth(text, width)
                    virtText = getVirtText(bufnr, text, lnum, syntax, nss)
                    if handler then
                        virtText = handler(virtText, lnum, endLnum, width, {
                            tick = tick,
                            bufnr = bufnr,
                            winid = winid,
                            text = text
                        })
                    else
                        table.insert(virtText, {' ⋯ ', 'UfoFoldedEllipsis'})
                    end
                    fb:closeFold(lnum, endLnum, virtText)
                end
            end)
        end
        local lnum = api.nvim_win_get_cursor(winid)[1]
        if redrawType == 40 then
            if winid == fb.winid and lnum == fb.lnum then
                mode = mode and mode or utils.mode()
                if mode == 'n' then
                    fb:synchronize(winid)
                end
            end
        end
        fb.lnum = lnum
        fb.winid = winid
    end
    collection = nil
end

function Decorator.setVirtTextHandler(bufnr, handler)
    if not Decorator.virtTextHandlers then
        Decorator.virtTextHandlers = setmetatable({}, {__mode = 'v'})
    end
    Decorator.virtTextHandlers[bufnr] = handler
end

function Decorator.getVirtTextHandler(bufnr)
    local handler
    if Decorator.virtTextHandlers then
        handler = Decorator.virtTextHandlers[bufnr]
    end
    return handler
end

function Decorator.initialize(namespace)
    if initialized then
        return
    end
    local disposables = {}
    api.nvim_set_decoration_provider(namespace, {
        on_start = onStart,
        on_win = onWin,
        on_line = onLine,
        on_end = onEnd
    })
    Decorator.namespace = namespace
    table.insert(disposables, function()
        api.nvim_set_decoration_provider(namespace, {})
    end)
    local virtTextHandler = config.fold_virt_text_handler
    if type(virtTextHandler) == 'function' then
        -- TODO
        -- how to clean up the wipeouted buffer, need refactor
        Decorator.virtTextHandlers = setmetatable({}, {
            __index = function(tbl, bufnr)
                rawset(tbl, bufnr, virtTextHandler)
                return virtTextHandler
            end
        })
    end
    hlGroups = highlight.hlGroups()
    Decorator.disposables = disposables
    initialized = true
end

function Decorator.dispose()
    for _, item in ipairs(Decorator.disposables) do
        item.dispose()
    end
    initialized = false
end

return Decorator
