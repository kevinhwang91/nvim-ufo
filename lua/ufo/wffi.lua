---@diagnostic disable: undefined-field
local M = {}

local utils
local C
local ffi

local CPos_T

local function findWin(winid)
    local err = ffi.new('Error')
    return C.find_window_by_handle(winid, err)
end

function M.clearFolds(winid)
    local wp = findWin(winid)
    C.clearFolding(wp)
    C.changed_window_setting()
end

function M.createFolds(winid, posList)
    local wp = findWin(winid)
    local s, e = CPos_T(), CPos_T()
    for _, p in ipairs(posList) do
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
    ]])
    CPos_T = ffi.typeof('pos_T')
end

init()

return M
