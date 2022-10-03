local api = vim.api

local M = {}

---
---@param bufnr number
---@param startRange number[]
---@param endRange number[]
---@param namespaces number[]
---@return table
function M.getHighlightsByRange(bufnr, startRange, endRange, namespaces)
    local res = {}
    local endRow, endCol = endRange[1], endRange[2]
    for _, ns in pairs(namespaces) do
        local marks = api.nvim_buf_get_extmarks(bufnr, ns, startRange, endRange, {details = true})
        for _, m in ipairs(marks) do
            local sr, sc, details = m[2], m[3], m[4]
            local er = details.end_row or sr
            local ec = details.end_col or (sc + 1)
            local hlGroup = details.hl_group
            local priority = details.priority
            if hlGroup then
                if er > endRow then
                    er, ec = endRow, endCol
                elseif er == endRow and ec > endCol then
                    er = endCol
                end
                table.insert(res, {sr, sc, er, ec, hlGroup, priority})
            end
        end
    end
    return res
end

function M.setLineHighlight(bufnr, ns, row, hlGroup, priority, id)
    return api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
        id = id,
        end_row = row + 1,
        end_col = 0,
        hl_group = hlGroup,
        hl_eol = true,
        priority = priority
    })
end

function M.setHighlight(bufnr, ns, row, col, endRow, endCol, hlGroup, priority)
    return api.nvim_buf_set_extmark(bufnr, ns, row, col, {
        end_row = endRow,
        end_col = endCol,
        hl_group = hlGroup,
        priority = priority
    })
end

function M.setVirtText(bufnr, ns, row, virtText, opts)
    opts = opts or {}
    return api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
        id = opts.id,
        virt_text = virtText,
        virt_text_win_col = 0,
        priority = opts.priority or 10,
        hl_mode = opts.hl_mode or 'combine'
    })
end

return M
