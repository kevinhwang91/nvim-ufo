---@diagnostic disable: undefined-field
---@class UfoWffi
local M = {}

local utils
local C
local ffi

local CPos_T

local function findWin(winid)
    local err = ffi.new('Error')
    return C.find_window_by_handle(winid, err)
end

---
---@param winid number
---@param lnum number
---@return number
function M.plinesWin(winid, lnum)
    return C.plines_win(findWin(winid), lnum, true)
end

---
---@param winid number
---@param lnum number
---@param winheight boolean
---@return number
function M.plinesWinNofill(winid, lnum, winheight)
    return C.plines_win_nofill(findWin(winid), lnum, winheight)
end

---
---@param winid number
function M.clearFolds(winid)
    local wp = findWin(winid)
    C.clearFolding(wp)
    C.changed_window_setting()
end

---
---@param winid number
---@param ranges number[]
function M.createFolds(winid, ranges)
    local wp = findWin(winid)
    local s, e = CPos_T(), CPos_T()
    for _, p in ipairs(ranges) do
        s.lnum = p[1]
        e.lnum = p[2]
        C.foldCreate(wp, s, e)
    end
end

local function init()
    ffi = require('ffi')
    setmetatable(M, {__index = ffi})
    C = ffi.C
    utils = require('ufo.utils')
    if utils.has08() then
        ffi.cdef([[
            typedef int32_t linenr_T;
        ]])
    else
        ffi.cdef([[
            typedef long linenr_T;
        ]])
    end
    ffi.cdef([[
        typedef struct window_S win_T;
        typedef int colnr_T;

        typedef struct {} Error;
        win_T *find_window_by_handle(int window, Error *err);

        typedef struct {
            linenr_T lnum;
            colnr_T col;
            colnr_T coladd;
        } pos_T;

        void clearFolding(win_T *win);
        void changed_window_setting(void);
        void foldCreate(win_T *wp, pos_T start, pos_T end);

        int plines_win(win_T *wp, linenr_T lnum, bool winheight);
        int plines_win_nofill(win_T *wp, linenr_T lnum, bool winheight);
    ]])
    CPos_T = ffi.typeof('pos_T')
end

init()

return M
