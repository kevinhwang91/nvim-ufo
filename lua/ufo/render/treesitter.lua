local highlighter = require('vim.treesitter.highlighter')

local M = {}

function M.getHighlightByRange(bufnr, startRange, endRange)
    local data = highlighter.active[bufnr]
    if not data then
        return {}
    end
    local res = {}
    local row, col = startRange[1], startRange[2]
    local endRow, endCol = endRange[1], endRange[2]
    data.tree:for_each_tree(function(tstree, tree)
        if not tstree then
            return
        end
        local root = tstree:root()
        local rootStartRow, _, rootEndRow, _ = root:range()
        if rootEndRow < row or rootStartRow > endRow then
            return
        end
        local query = data:get_query(tree:lang())
        -- Some injected languages may not have highlight queries.
        if not query:query() then
            return
        end
        local iter = query:query():iter_captures(root, data.bufnr, row, endRow + 1)
        -- Record the last range and priority
        local lsr, lsc, ler, lec, lpriority, last
        for capture, node, metadata in iter do
            if not capture then
                break
            end
            local hlId = query.hl_cache[capture]
            local priority = tonumber(metadata.priority) or 100
            local sr, sc, er, ec = node:range()
            if row <= er and endRow >= sr then
                if sr < row or sr == row and sc < col then
                    sr, sc = row, col
                end
                if er > endRow or er == endRow and ec > endCol then
                    er, ec = endRow, endCol
                end
                -- Overlap highlighting if range is equal to last's
                if lsr == sr and lsc == sc and ler == er and lec == ec then
                    if lpriority <= priority then
                        last[5], last[6] = hlId, priority
                    end
                else
                    last = {sr, sc, er, ec, hlId, priority}
                    table.insert(res, last)
                end
                lsr, lsc, ler, lec, lpriority = sr, sc, er, ec, priority
            end
        end
    end)
    return res
end

return M
