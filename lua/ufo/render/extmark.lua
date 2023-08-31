local api = vim.api

local M = {}

---
---@param bufnr number
---@param startRange number[]
---@param endRange number[]
---@param namespaces number[]
---@return table, table
function M.getHighlightsAndInlayByRange(bufnr, startRange, endRange, namespaces)
    local hlRes, inlayRes = {}, {}
    local endRow, endCol = endRange[1], endRange[2]
    for _, ns in pairs(namespaces) do
        local marks = api.nvim_buf_get_extmarks(bufnr, ns, startRange, endRange, {details = true})
        for _, m in ipairs(marks) do
            local sr, sc, details = m[2], m[3], m[4]
            local er = details.end_row or sr
            local ec = details.end_col or (sc + 1)
            local hlGroup = details.hl_group
            local priority = details.priority
            local virtTextPos = details.virt_text_pos
            if hlGroup then
                if er > endRow then
                    er, ec = endRow, endCol
                elseif er == endRow and ec > endCol then
                    er = endCol
                end
                table.insert(hlRes, {sr, sc, er, ec, hlGroup, priority})
            end
            if virtTextPos == 'inline' then
                table.insert(inlayRes, {sr, sc, details.virt_text, priority})
            end
        end
    end
    return hlRes, inlayRes
end

function M.setHighlight(bufnr, ns, row, col, endRow, endCol, hlGroup, priority)
    return api.nvim_buf_set_extmark(bufnr, ns, row, col, {
        end_row = endRow,
        end_col = endCol,
        hl_group = hlGroup,
        priority = priority
    })
end

function M.setVirtText(bufnr, ns, row, col, virtText, opts)
    opts = opts or {}
    local textPos = opts.virt_text_pos
    local winCol = not textPos and col == 0 and 0 or nil
    return api.nvim_buf_set_extmark(bufnr, ns, row, col, {
        id = opts.id,
        virt_text = virtText,
        virt_text_win_col = winCol,
        virt_text_pos = textPos or 'eol',
        priority = opts.priority or 10,
        hl_mode = opts.hl_mode or 'combine'
    })
end

return M
