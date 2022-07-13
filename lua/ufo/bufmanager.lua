local api = vim.api

local buffer = require('ufo.model.buffer')
local event  = require('ufo.lib.event')

---@class UfoBufferManager
---@field buffers UfoBuffer[]
---@field disposables UfoDisposable[]
local BufferManager = {
    buffers = {},
    disposables = {}
}

local initialized

local function attach(self, bufnr)
    if not self.buffers[bufnr] then
        local buf = buffer:new(bufnr)
        self.buffers[bufnr] = buf
        buf:attach()
    end
end

function BufferManager:initialize()
    if initialized then
        return self
    end
    event:on('BufEnter', function()
        attach(self, api.nvim_get_current_buf())
    end, self.disposables)
    event:on('BufDetach', function(bufnr)
        self.buffers[bufnr] = nil
    end, self.disposables)

    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        attach(self, api.nvim_win_get_buf(winid))
    end
    initialized = true
    return self
end

---
---@param bufnr number
---@return UfoBuffer
function BufferManager:get(bufnr)
    return self.buffers[bufnr]
end

function BufferManager:dispose()
    for _, item in ipairs(self.disposables) do
        item:dispose()
    end
    initialized = false
end

return BufferManager
