local api = vim.api
local fn = vim.fn
local utils = require('ufo.utils')

local LSize

---
---@class UfoLineSizeBase
---@field winid number
---@field foldenable boolean
---@field foldClosePairs table<number, number[]>
---@field sizes table<number, number>
local LBase = {}

---
---@param sizes table<number, number>
---@return UfoLineSizeBase
function LBase:new(winid, sizes)
    local o = setmetatable({}, self)
    self.__index = self
    o.winid = winid
    o.foldenable = vim.wo.foldenable
    o.foldClosePairs = {}
    o.sizes = sizes
    return o
end

---
---@param lnum number
---@return number
function LBase:size(lnum)
    return self.sizes[lnum]
end

---
---@class UfoLineSizeFFI : UfoLineSizeBase
---@field private _wffi UfoWffi
local LFFI = setmetatable({}, {__index = LBase})

---
---@return UfoLineSizeFFI
function LFFI:new(winid)
    local super = LBase:new(winid, setmetatable({}, {
        __index = function(t, i)
            local v = self._wffi.plinesWin(winid, i)
            rawset(t, i, v)
            return v
        end
    }))
    local o = setmetatable(super, self)
    self.__index = self
    return o
end

---
---@param lnum number
---@param winheight boolean
---@return number
function LFFI:nofillSize(lnum, winheight)
    winheight = winheight or true
    return self._wffi.plinesWinNofill(self.winid, lnum, winheight)
end

---
---@param lnum number
---@return number
function LFFI:fillSize(lnum)
    return self:size(lnum) - self:nofillSize(lnum, true)
end

---
---@class UfoLineSizeNonFFI : UfoLineSizeBase
---@field perLineWidth number
local LNonFFI = setmetatable({}, {__index = LBase})

---
---@return UfoLineSizeNonFFI
function LNonFFI:new(winid)
    local wrap = vim.wo[winid].wrap
    local perLineWidth = api.nvim_win_get_width(winid) - utils.textoff(winid)
    local super = LBase:new(winid, setmetatable({}, {
        __index = function(t, i)
            local v
            if wrap then
                v = math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / perLineWidth)
            else
                v = 1
            end
            rawset(t, i, v)
            return v
        end
    }))
    local o = setmetatable(super, self)
    o.perLineWidth = perLineWidth
    self.__index = self
    return o
end

LNonFFI.nofillSize = LNonFFI.size

---
---@param _ any
---@return number
function LNonFFI.fillSize(_)
    return 0
end

local function init()
    if jit ~= nil then
        LFFI._wffi = require('ufo.wffi')
        LSize = LFFI
    else
        LSize = LNonFFI
    end
end

init()

return LSize
