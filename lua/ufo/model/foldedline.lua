local utils = require('ufo.utils')
local api = vim.api

---@class UfoFoldedLine
---@field id number
---@field bufnr number
---@field ns number
---@field rendered boolean
---@field virtText? UfoExtmarkVirtTextChunk[]
---@field extIds? number[]
---@field extHash? number
local FoldedLine = {}

function FoldedLine:new(bufnr, ns)
    local o = setmetatable({}, self)
    self.__index = self
    o.id = nil
    o.bufnr = bufnr
    o.ns = ns
    o.rendered = false
    o.virtText = nil
    o.extIds = nil
    return o
end

function FoldedLine:hasRendered()
    return self.rendered == true
end

local function hashList(list)
    local hash = 0
    local prime = 31
    local mod = 2 ^ 31
    for _, num in ipairs(list) do
        hash = (hash + num * prime) % mod
    end
    return hash
end

function FoldedLine:validExtIds(o)
    -- if type(o) ~= 'table' then
    --     return false
    -- end
    if not self.extIds or #self.extIds ~= #o then
        return false
    end
    return self.extHash == hashList(o)
end

function FoldedLine:deleteExtmark()
    if self.id then
        api.nvim_buf_del_extmark(self.bufnr, self.ns, self.id)
    end
end

function FoldedLine:updateVirtText(lnum, endLnum, virtText, extIds)
    if extIds then
        local opts = {
            id = self.id,
            end_row = endLnum - 1,
            end_col = 0,
            priority = 10,
            hl_mode = 'combine'
        }
        if not utils.has10() then
            opts.virt_text = virtText
            opts.virt_text_win_col = 0
        end
        self.id = api.nvim_buf_set_extmark(self.bufnr, self.ns, lnum - 1, 0, opts)
        self.extHash = hashList(extIds)
        self.rendered = true
    else
        self.rendered = false
    end
    self.virtText = virtText
    self.extIds = extIds
end

function FoldedLine:range()
    if not self.id then
        return 0, 0
    end
    local mark = api.nvim_buf_get_extmark_by_id(self.bufnr, self.ns, self.id, {details = true})
    local row, details = mark[1], mark[3]
    ---@diagnostic disable-next-line: need-check-nil
    local endRow = details.end_row
    return row + 1, endRow + 1
end

return FoldedLine
