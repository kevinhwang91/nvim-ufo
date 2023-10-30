local api = vim.api

local buffer = require('ufo.model.buffer')
local event = require('ufo.lib.event')
local disposable = require('ufo.lib.disposable')
local promise = require('promise')
local utils = require('ufo.utils')

---@class UfoBufferManager
---@field initialized boolean
---@field buffers UfoBuffer[]
---@field disposables UfoDisposable[]
local BufferManager = {}

local function attach(self, bufnr)
    if not self.buffers[bufnr] and not self.bufDetachSet[bufnr] then
        local buf = buffer:new(bufnr)
        self.buffers[bufnr] = buf
        if not buf:attach() then
            self.buffers[bufnr] = nil
        end
    end
end

function BufferManager:initialize()
    if self.initialized then
        return self
    end
    self.initialized = true
    self.buffers = {}
    self.bufDetachSet = {}
    self.disposables = {}
    table.insert(self.disposables, disposable:create(function()
        for _, b in pairs(self.buffers) do
            b:dispose()
        end
        self.initialized = false
        self.buffers = {}
        self.bufDetachSet = {}
    end))
    ---@diagnostic disable-next-line: unused-local
    event:on('BufWinEnter', function(bufnr, winid)
        attach(self, bufnr or api.nvim_get_current_buf())
    end, self.disposables)
    event:on('BufDetach', function(bufnr)
        local b = self.buffers[bufnr]
        if b then
            b:dispose()
            self.buffers[bufnr] = nil
        end
    end, self.disposables)
    event:on('BufTypeChanged', function(bufnr, new, old)
        local b = self.buffers[bufnr]
        if b and old ~= new then
            if new == 'terminal' or new == 'prompt' then
                event:emit('BufDetach', bufnr)
            else
                b.bt = new
            end
        end
    end, self.disposables)
    event:on('FileTypeChanged', function(bufnr, new, old)
        local b = self.buffers[bufnr]
        if b and old ~= new then
            b.ft = new
        end
    end, self.disposables)
    event:on('SyntaxChanged', function(bufnr, new, old)
        local b = self.buffers[bufnr]
        if b and old ~= new then
            b.syntax = new
        end
    end, self.disposables)

    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        local bufnr = api.nvim_win_get_buf(winid)
        if utils.isBufLoaded(bufnr) then
            attach(self, bufnr)
        else
            -- the first buffer is unloaded while firing `BufWinEnter`
            promise.resolve():thenCall(function()
                if utils.isBufLoaded(bufnr) then
                    attach(self, bufnr)
                end
            end)
        end
    end
    return self
end

---
---@param bufnr number
---@return UfoBuffer
function BufferManager:get(bufnr)
    return self.buffers[bufnr]
end

function BufferManager:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

function BufferManager:attach(bufnr)
    self.bufDetachSet[bufnr] = nil
    attach(self, bufnr)
end

function BufferManager:detach(bufnr)
    self.bufDetachSet[bufnr] = true
    event:emit('BufDetach', bufnr)
end

return BufferManager
