local utils = require('ufo.utils')
local api = vim.api

---@class UfoFoldedLine
---@field id number
---@field bufnr number
---@field ns number
---@field rendered boolean
---@field text? string
---@field width? number
---@field virtText? UfoExtmarkVirtTextChunk[]
local FoldedLine = {}

function FoldedLine:new(bufnr, ns, text, width)
    local o = setmetatable({}, self)
    self.__index = self
    o.id = nil
    o.bufnr = bufnr
    o.ns = ns
    o.text = text
    o.width = width
    o.rendered = false
    o.virtText = nil
    return o
end

---
---@param width number
---@return boolean
function FoldedLine:widthChanged(width)
    return self.width ~= width
end

function FoldedLine:textChanged(text)
    return self.text ~= text
end

function FoldedLine:hasRendered()
    return self.rendered == true
end

function FoldedLine:deleteExtmark()
    if self.id then
        api.nvim_buf_del_extmark(self.bufnr, self.ns, self.id)
    end
end

function FoldedLine:updateVirtText(lnum, endLnum, virtText, doRender)
    if doRender then
        local opts = {
            id = self.id,
            end_row = endLnum - 1,
            end_col = 0,
            priority = 10,
            hl_mode = 'combine'
        }
        -- TODO
        -- nvim-hlslens need virt_text to show lens
        -- if not utils.has10() then
            opts.virt_text = virtText
            opts.virt_text_win_col = 0
        -- end
        self.id = api.nvim_buf_set_extmark(self.bufnr, self.ns, lnum - 1, 0, opts)
    end
    self.rendered = doRender
    self.virtText = virtText
end

function FoldedLine:range()
    if not self.id then
        return 0, 0
    end
    local mark = api.nvim_buf_get_extmark_by_id(self.bufnr, self.ns, self.id, {details = true})
    local row, details = mark[1], mark[3]
    local endRow = details.end_row
    return row + 1, endRow + 1
end

return FoldedLine
