---@class UfoUtils
local M = {}
local api = vim.api
local fn = vim.fn
local uv = vim.loop

---
---@return fun(): boolean
M.has08 = (function()
    local has08
    return function()
        if has08 == nil then
            has08 = fn.has('nvim-0.8') == 1
        end
        return has08
    end
end)()

---@return fun(): boolean
M.isWindows = (function()
    local isWin
    return function()
        if isWin == nil then
            isWin = uv.os_uname().sysname == 'Windows_NT'
        end
        return isWin
    end
end)()

---
---@return string
function M.mode()
    return api.nvim_get_mode().mode
end

---
---@param bufnr number
---@return number, number[]?
function M.getWinByBuf(bufnr)
    local curBufnr = api.nvim_get_current_buf()
    bufnr = bufnr or curBufnr
    local winids = {}
    for _, winid in ipairs(api.nvim_list_wins()) do
        if bufnr == api.nvim_win_get_buf(winid) then
            table.insert(winids, winid)
        end
    end
    if #winids == 0 then
        return -1
    elseif #winids == 1 then
        return winids[1]
    else
        local winid = curBufnr == bufnr and api.nvim_get_current_win() or winids[1]
        return winid, winids
    end
end

---
---@param winid number
---@param f fun(): any
---@return any
function M.winCall(winid, f)
    if winid == 0 or winid == api.nvim_get_current_win() then
        return f()
    else
        return api.nvim_win_call(winid, f)
    end
end

---
---@param winid number
---@param lnum number
---@return number
function M.foldClosed(winid, lnum)
    return M.winCall(winid, function()
        return fn.foldclosed(lnum)
    end)
end

---
---@param winid number
---@param lnum number
---@return number
function M.foldClosedEnd(winid, lnum)
    return M.winCall(winid, function()
        return fn.foldclosedend(lnum)
    end)
end

---
---@param str string
---@param ts number
---@param start? number
---@return string
function M.expandTab(str, ts, start)
    start = start or 1
    local new = str:sub(1, start - 1)
    local pad = ' '
    local ti = start - 1
    local i = start
    while true do
        i = str:find('\t', i, true)
        if not i then
            if ti == 0 then
                new = str
            else
                new = new .. str:sub(ti + 1)
            end
            break
        end
        if ti + 1 == i then
            new = new .. pad:rep(ts)
        else
            local append = str:sub(ti + 1, i - 1)
            new = new .. append .. pad:rep(ts - api.nvim_strwidth(append) % ts)
        end
        ti = i
        i = i + 1
    end
    return new
end

---@param ms number
---@return Promise
function M.wait(ms)
    return require('promise')(function(resolve)
        local timer = uv.new_timer()
        timer:start(ms, 0, function()
            timer:close()
            resolve()
        end)
    end)
end

---
---@param callback function
---@param ms number
---@return userdata
function M.setTimeout(callback, ms)
    ---@type userdata
    local timer = uv.new_timer()
    timer:start(ms, 0, function()
        timer:close()
        callback()
    end)
    return timer
end

---
---@param bufnr number
---@param name? string
---@param off? number
---@return boolean
function M.isUnNameBuf(bufnr, name, off)
    name = name or api.nvim_buf_get_name(bufnr)
    off = off or api.nvim_buf_get_offset(bufnr, 1)
    return name == '' and off <= 0
end

---
---@param winid number
---@return boolean
function M.isDiffFold(winid)
    return vim.wo[winid].foldmethod == 'diff'
end

---
---@param winid number
---@return boolean
function M.isDiffOrMarkerFold(winid)
    local method = vim.wo[winid].foldmethod
    return method == 'diff' or method == 'marker'
end

---
---@param winid number
---@return table<string, number>
function M.getWinInfo(winid)
    local winfos = fn.getwininfo(winid)
    assert(type(winfos) == 'table' and #winfos == 1,
           '`getwininfo` expected 1 table with single element.')
    return winfos[1]
end

---@param str string
---@param targetWidth number
---@return string
function M.truncateStrByWidth(str, targetWidth)
    if fn.strdisplaywidth(str) <= targetWidth then
        return str
    end
    local width = 0
    local byteOff = 0
    while true do
        local part = fn.strpart(str, byteOff, 1, true)
        width = width + fn.strdisplaywidth(part)
        if width > targetWidth then
            break
        end
        byteOff = byteOff + #part
    end
    return str:sub(1, byteOff)
end

---
---@param winid number
---@return number
function M.textoff(winid)
    return M.getWinInfo(winid).textoff
end

---
---@param bufnr number
---@param lnum number 1-indexed
---@param col number 1-indexed
---@return number 0-indexed
function M.curswant(bufnr, lnum, col)
    if col == 0 then
        return 0
    end
    local text = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
    text = M.expandTab(text:sub(1, col), vim.bo[bufnr].ts)
    return #text - 1
end

---
---@param winid number
---@return boolean
function M.isWinValid(winid)
    if winid then
        return type(winid) == 'number' and winid > 0 and api.nvim_win_is_valid(winid)
    else
        return false
    end
end

---
---@param bufnr number
---@return boolean
function M.isBufLoaded(bufnr)
    return bufnr and type(bufnr) == 'number' and bufnr > 0 and api.nvim_buf_is_loaded(bufnr)
end

M.highlightTimeout = (function()
    local function doUnPack(pos)
        vim.validate({
            pos = {
                pos, function(p)
                    local t = type(p)
                    return t == 'table' or t == 'number'
                end, 'must be table or number type'
            }
        })
        local row, col
        if type(pos) == 'table' then
            row, col = unpack(pos)
        else
            row = pos
        end
        col = col or 0
        return row, col
    end

    local function rangeToRegion(row, col, endRow, endCol)
        local region = {}
        if row > endRow or (row == endCol and col >= endCol) then
            return region
        end
        if row == endRow then
            region[row] = {col, endCol}
            return region
        end
        region[row] = {col, -1}
        for i = row + 1, endRow - 1 do
            region[i] = {0, -1}
        end
        if endCol > 0 then
            region[endRow] = {0, endCol}
        end
        return region
    end

    ---@param bufnr number
    ---@param ns number
    ---@param hlGoup string
    ---@param start number
    ---@param finish number
    ---@param opt? table
    ---@param delay? number
    ---@return Promise
    return function(bufnr, ns, hlGoup, start, finish, opt, delay)
        local row, col = doUnPack(start)
        local endRow, endCol = doUnPack(finish)
        local o = {hl_group = hlGoup}
        o = opt and vim.tbl_deep_extend('keep', o, opt) or o
        local ids = {}
        local region = rangeToRegion(row, col, endRow, endCol)
        for sr, range in pairs(region) do
            local sc, ec = range[1], range[2]
            local er
            if ec == -1 then
                er = sr + 1
                ec = 0
            end
            o.end_row = er
            o.end_col = ec
            table.insert(ids, api.nvim_buf_set_extmark(bufnr, ns, sr, sc, o))
        end
        return M.wait(delay or 300):thenCall(function()
            for _, id in ipairs(ids) do
                pcall(api.nvim_buf_del_extmark, bufnr, ns, id)
            end
        end)
    end
end)()

---
---@param winid number
---@param line number
---@param lsizes number
---@return number, number
function M.evaluateTopline(winid, line, lsizes)
    local log = require('ufo.lib.log')
    local topline
    local iStart, iEnd = line - 1, math.max(1, line - lsizes)
    local lsizeSum = 0
    local i = iStart
    local lsizeObj = require('ufo.model.linesize'):new(winid)
    local len = lsizes - lsizeObj:fillSize(line)
    log.info('winid:', winid, 'line:', line, 'lsizes:', lsizes, 'len:', len)
    local size
    while lsizeSum < len and i >= iEnd do
        local lnum = M.foldClosed(winid, i)
        log.info('lnum:', lnum, 'i:', i)
        if lnum == -1 then
            size = lsizeObj:size(i)
        else
            size = 1
            iEnd = math.max(1, iEnd + lnum - i)
            i = lnum
        end
        lsizeSum = lsizeSum + size
        log.info('size:', size, 'lsizeSum:', lsizeSum)
        topline = i
        i = i - 1
    end
    if not topline then
        topline = line
    end
    -- extraOff lines is need to be showed near the topline
    local topfill = lsizeObj:fillSize(topline)
    local extraOff = lsizeSum - len
    if extraOff > 0 then
        if topfill < extraOff then
            topline = topline + 1
        else
            topfill = topfill - extraOff
        end
    end
    log.info('topline:', topline, 'topfill:', topfill)
    return topline, topfill
end

return M
