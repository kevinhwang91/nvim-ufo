---@alias UfoFoldingRangeKind
---| 'comment'
---| 'imports'
---| 'region'

---@class UfoFoldingRange
---@field startLine number
---@field startCharacter? number
---@field endLine number
---@field endCharacter? number
---@field kind? UfoFoldingRangeKind
local FoldingRange = {}

function FoldingRange.new(startLine, endLine, startCharacter, endCharacter, kind)
    local o = {}
    o.startLine = startLine
    o.endLine = endLine
    o.startCharacter = startCharacter
    o.endCharacter = endCharacter
    o.kind = kind
    return o
end

---
---@param ranges UfoFoldingRange
function FoldingRange.sortRanges(ranges)
    if jit then
        return
    end
    table.sort(ranges, function(a, b)
        return a.startLine == b.startLine and a.endLine < b.endLine or a.startLine > b.startLine
    end)
end

return FoldingRange
