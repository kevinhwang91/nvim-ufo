local fn = vim.fn

local M = {}

---
---@param winid number
---@param lnum number
---@param endLnum number
---@return table
function M.mapHighlightsByLnum(winid, lnum, endLnum)
    local res = {}
    for _, m in pairs(fn.getmatches(winid)) do
        if m.pattern then
            table.insert(res, m)
        else
            local added = false
            local function add(match)
                if not added then
                    table.insert(res, match)
                    added = true
                end
            end

            for i = 1, 8 do
                local k = 'pos' .. i
                local p = m[k]
                local pType = type(p)
                if pType == 'nil' then
                    break
                end
                if pType == 'number' then
                    if p >= lnum and p <= endLnum then
                        m[k] = p - lnum + 1
                        add(m)
                    end
                else
                    local l = p[1]
                    if l >= lnum and l <= endLnum then
                        m[k][1] = l - lnum + 1
                        add(m)
                    end
                end
            end
        end
    end
    return res
end

return M
