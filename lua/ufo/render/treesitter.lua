local highlighter = require('vim.treesitter.highlighter')

local M = {}

function M.parserFinished(bufnr)
    local data = highlighter.active[bufnr]
    if not data then
        return true
    end
    if data.parsing then
        return false
    else
        return true
    end
end

---
---@param bufnr number
---@param startRange number
---@param endRange number
---@param hlGroups? table<number|string, table>
---@return table
function M.getHighlightsByRange(bufnr, startRange, endRange, hlGroups)
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
            local hlId = assert((function()
                if query.get_hl_from_capture then -- nvim 0.10+ #26675
                    return query:get_hl_from_capture(capture)
                else
                    return query.hl_cache[capture]
                end
            end)())
            local priority = tonumber(metadata.priority) or 100
            local conceal = metadata.conceal
            local sr, sc, er, ec = node:range()
            if row <= er and endRow >= sr then
                if sr < row or sr == row and sc < col then
                    sr, sc = row, col
                end
                if er > endRow or er == endRow and ec > endCol then
                    er, ec = endRow, endCol
                end
                if hlGroups then
                    -- Overlap highlighting if range is equal to last's
                    if lsr == sr and lsc == sc and ler == er and lec == ec then
                        if hlGroups[hlId].foreground and lpriority <= priority then
                            last[5], last[6], last[7] = hlId, priority, conceal
                        end
                    else
                        last = {sr, sc, er, ec, hlId, priority, conceal}
                        table.insert(res, last)
                    end
                    lsr, lsc, ler, lec, lpriority = sr, sc, er, ec, priority
                else
                    table.insert(res, {sr, sc, er, ec, hlId, priority, conceal})
                end
            end
        end
    end)
    return res
end

return M
