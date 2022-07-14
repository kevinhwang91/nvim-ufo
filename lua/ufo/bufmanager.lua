local api = vim.api

local buffer     = require('ufo.model.buffer')
local event      = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local promise    = require('promise')
local utils      = require('ufo.utils')

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
        if not buf:attach() then
            self.buffers[bufnr] = nil
        end
    end
end

function BufferManager:initialize()
    if initialized then
        return self
    end
    local disposables = {}
    table.insert(disposables, disposable:create(function()
        for _, b in pairs(self.buffers) do
            b:dispose()
        end
        self.buffers = {}
    end))
    event:on('BufEnter', function(bufnr)
        attach(self, bufnr or api.nvim_get_current_buf())
    end, disposables)
    event:on('BufDetach', function(bufnr)
        local b = self.buffers[bufnr]
        if b then
            b:dispose()
            self.buffers[bufnr] = nil
        end
    end, disposables)
    self.disposables = disposables

    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        local bufnr = api.nvim_win_get_buf(winid)
        if utils.isBufLoaded(bufnr) then
            attach(self, bufnr)
        else
            -- the first buffer is unloaded while firing `BufEnter`
            promise.resolve():thenCall(function()
                if utils.isBufLoaded(bufnr) then
                    attach(self, bufnr)
                end
            end)
        end
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
