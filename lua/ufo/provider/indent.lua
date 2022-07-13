local utils        = require('ufo.utils')
local foldingrange = require('ufo.model.foldingrange')
local bufmanager   = require('ufo.bufmanager')

local Indent = {}

local api = vim.api

function Indent.getFolds(bufnr)
    if not utils.isBufLoaded(bufnr) then
        return
    end
    local lines = bufmanager:get(bufnr):lines(0, -1)
    local sw = vim.bo[bufnr].shiftwidth
    local ts = vim.bo[bufnr].ts
    local levels = {}
    for lnum = 1, #lines do
        local line = lines[lnum]
        local n = 0
        local stop = false
        for col = 1, #line do
            -- compare byte is slightly faster than a char in the string
            local b = line:byte(col, col)
            if b == 0x20 then
                -- ' '
                n = n + 1
            elseif b == 0x09 then
                -- '\t'
                n = n + (ts - (n % ts))
            else
                stop = true
                break
            end
        end
        local level = stop and math.ceil(n / sw) or -1
        table.insert(levels, level)
    end

    local ranges = {}
    local stack = {}

    local function pop(curLevel, lastLnum)
        while #stack > 0 do
            local data = stack[#stack]
            local level, lnum = data[1], data[2]
            if level >= curLevel then
                table.insert(ranges, foldingrange.new(lnum - 1, lastLnum - 1))
                table.remove(stack)
            else
                break
            end
        end
    end

    local lastLnum = 1
    local lastLevel = levels[1]
    for i = 1, #lines do
        local curLevel = levels[i]
        if curLevel >= 0 then
            if curLevel > 0 and curLevel > lastLevel then
                table.insert(stack, {lastLevel, lastLnum})
            elseif curLevel < lastLevel then
                pop(curLevel, lastLnum)
            end
            lastLevel = curLevel
            lastLnum = i
        end
    end
    pop(0, lastLnum)
    return ranges
end

return Indent
