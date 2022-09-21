local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local utils = require('ufo.utils')
local fold = require('ufo.fold')

local M = {}

function M.goPreviousStartFold()
    local function getCurLnum()
        return api.nvim_win_get_cursor(0)[1]
    end

    local cnt = vim.v.count1
    local winView = fn.winsaveview()
    local curLnum = getCurLnum()
    cmd('norm! m`')
    local previousLnum
    local previousLnumList = {}
    while cnt > 0 do
        cmd([[keepj norm! zk]])
        local tLnum = getCurLnum()
        cmd([[keepj norm! [z]])
        if tLnum == getCurLnum() then
            local foldStartLnum = utils.foldClosed(0, tLnum)
            if foldStartLnum > 0 then
                cmd(('keepj norm! %dgg'):format(foldStartLnum))
            end
        end
        local nextLnum = getCurLnum()
        while curLnum > nextLnum do
            tLnum = nextLnum
            table.insert(previousLnumList, nextLnum)
            cmd([[keepj norm! zj]])
            nextLnum = getCurLnum()
            if nextLnum == tLnum then
                break
            end
        end
        if #previousLnumList == 0 then
            break
        end
        if #previousLnumList < cnt then
            cnt = cnt - #previousLnumList
            curLnum = previousLnumList[1]
            previousLnum = curLnum
            cmd(('keepj norm! %dgg'):format(curLnum))
            previousLnumList = {}
        else
            while cnt > 0 do
                previousLnum = table.remove(previousLnumList)
                cnt = cnt - 1
            end
        end
    end
    fn.winrestview(winView)
    if previousLnum then
        cmd(('norm! %dgg_'):format(previousLnum))
    end
end

function M.goPreviousClosedFold()
    local count = vim.v.count1
    local curLnum = api.nvim_win_get_cursor(0)[1]
    local cnt = 0
    local lnum
    for i = curLnum - 1, 1, -1 do
        if utils.foldClosed(0, i) == i then
            cnt = cnt + 1
            lnum = i
            if cnt == count then
                break
            end
        end
    end
    if lnum then
        cmd('norm! m`')
        api.nvim_win_set_cursor(0, {lnum, 0})
    end
end

function M.goNextClosedFold()
    local count = vim.v.count1
    local curLnum = api.nvim_win_get_cursor(0)[1]
    local lineCount = api.nvim_buf_line_count(0)
    local cnt = 0
    local lnum
    for i = curLnum + 1, lineCount do
        if utils.foldClosed(0, i) == i then
            cnt = cnt + 1
            lnum = i
            if cnt == count then
                break
            end
        end
    end
    if lnum then
        cmd('norm! m`')
        api.nvim_win_set_cursor(0, {lnum, 0})
    end
end

function M.closeFolds(level)
    cmd('silent! %foldclose!')
    local curBufnr = api.nvim_get_current_buf()
    local fb = fold.get(curBufnr)
    if not fb then
        return
    end
    for _, range in ipairs(fb.foldRanges) do
        fb:closeFold(range.startLine + 1, range.endLine + 1)
    end
    if level == 0 then
        return
    end

    local lineCount = fb:lineCount()
    local stack = {}
    local lastLevel = 0
    local lastEndLnum = -1
    local lnum = 1
    while lnum <= lineCount do
        local l = fn.foldlevel(lnum)
        if lastLevel < l or l > 0 and lnum == lastEndLnum + 1 then
            local endLnum = utils.foldClosedEnd(0, lnum)
            table.insert(stack, {endLnum, false})
            if l <= level then
                local cmds = {}
                for i = #stack, 1, -1 do
                    local opened = stack[i][2]
                    if opened then
                        break
                    end
                    stack[i][2] = true
                    table.insert(cmds, lnum .. 'foldopen')
                    fb:openFold(lnum)
                end
                if #cmds > 0 then
                    cmd(table.concat(cmds, '|'))
                    -- A line may contain multiple folds, make sure lnum is opened.
                    while lnum == utils.foldClosed(0, lnum) do
                        cmd(lnum .. 'foldopen')
                    end
                end
            else
                lnum = endLnum
            end
        end
        lastLevel = l
        lnum = lnum + 1
        while #stack > 0 do
            local endLnum = stack[#stack][1]
            if lnum <= endLnum then
                break
            end
            table.remove(stack)
            lastEndLnum = math.max(lastEndLnum, endLnum)
        end
    end
end

function M.openFoldsExceptKinds(kinds)
    cmd('silent! %foldopen!')
    local curBufnr = api.nvim_get_current_buf()
    local fb = fold.get(curBufnr)
    if not fb or type(kinds) ~= 'table' or #kinds == 0 then
        return
    end
    local res = {}
    for _, range in ipairs(fb.foldRanges) do
        if range.kind and vim.tbl_contains(kinds, range.kind) then
            local startLnum, endLnum = range.startLine + 1, range.endLine + 1
            fb:closeFold(startLnum, endLnum)
            table.insert(res, {startLnum, endLnum})
        end
    end
    table.sort(res, function(a, b)
        return a[1] == b[1] and a[2] < b[2] or a[1] > b[1]
    end)
    local cmds = {}
    for _, range in ipairs(res) do
        table.insert(cmds, range[1] .. 'foldclose')
    end
    if #cmds > 0 then
        cmd(table.concat(cmds, '|'))
    end
end

return M
