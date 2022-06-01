local highlighter = require('vim.treesitter.highlighter')

local M = {}

function M.getHighlightInRow(bufnr, row)
    local data = highlighter.active[bufnr]
    if not data then
        return {}
    end
    local res = {}
    data.tree:for_each_tree(function(tstree, tree)
        if not tstree then
            return
        end
        local root = tstree:root()
        local rootStartRow, _, rootEndRow, _ = root:range()
        -- Only worry about trees within the line range
        if rootStartRow > row or rootEndRow < row then
            return
        end
        local query = data:get_query(tree:lang())
        -- Some injected languages may not have highlight queries.
        if not query:query() then
            return
        end
        local iter = query:query():iter_captures(root, data.bufnr, row, row + 1)
        for capture, node, metadata in iter do
            if not capture then
                break
            end
            local startRow, startCol, endRow, endCol = node:range()
            if startRow <= row and row <= endRow then
                if startRow < row then
                    startCol = 0
                end
                if endRow > row then
                    endCol = -1
                end
                local hl = query.hl_cache[capture]
                table.insert(res, {hl, tonumber(metadata.priority) or 100, startCol, endCol})
            end
        end
    end)
    return res
end

return M
