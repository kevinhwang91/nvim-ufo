local foldingrange = require('ufo.model.foldingrange')
local bufmanager = require('ufo.bufmanager')

local Indent = {}

function Indent.getFolds(bufnr)
    local buf = bufmanager:get(bufnr)
    if not buf then
        return
    end
    local lines = buf:lines(1, -1)
    local ts = vim.bo[bufnr].ts
    local sw = vim.bo[bufnr].sw
    sw = sw == 0 and ts or sw
    local levels = {}
    for _, line in ipairs(lines) do
        local level = -1
        local n = 0
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
                level = math.ceil(n / sw)
                break
            end
        end
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
    for i, level in ipairs(levels) do
        if level >= 0 then
            if level > 0 and level > lastLevel then
                table.insert(stack, {lastLevel, lastLnum})
            elseif level < lastLevel then
                pop(level, lastLnum)
            end
            lastLevel = level
            lastLnum = i
        end
    end
    pop(0, lastLnum)
    return ranges
end

return Indent
