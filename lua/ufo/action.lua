local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local utils = require('ufo.utils')

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
        api.nvim_win_set_cursor(0, {lnum, 0})
    end
end

function M.closeFolds(level)
    if level == 0 then
        M.closeAllFolds()
        return
    end
    local curBufnr = api.nvim_get_current_buf()
    local fb = require('ufo.fold').get(curBufnr)
    if fb and #fb.foldRanges == 0 then
        return
    end
    local ranges = {}
    for _, fr in ipairs(fb.foldRanges) do
        table.insert(ranges, {fr.startLine + 1, fr.endLine + 1})
    end
    table.sort(ranges, function(a, b)
        return a[1] == b[1] and a[2] < b[2] or a[1] < b[1]
    end)
    local stack = {}
    local res = {}
    local function pop(range)
        while #stack > 0 do
            local outRange = stack[#stack]
            local osl, oel = outRange[1], outRange[2]
            local sl, el = range[1], range[2]
            if osl <= sl and el <= oel then
                break
            end
            if #stack > level then
                table.insert(res, stack[#stack])
            end
            table.remove(stack)
        end
    end

    for _, range in ipairs(ranges) do
        pop(range)
        table.insert(stack, range)
    end
    pop({0, 0})

    if #res == 0 then
        return
    end
    local cmds = {'silent! %foldopen!'}
    local fmt = 'silent! %d,%dfoldclose'
    for _, range in ipairs(res) do
        table.insert(cmds, fmt:format(range[1], range[2]))
    end
    cmd(table.concat(cmds, '|'))
end

function M.closeAllFolds()
    cmd('silent! %foldclose!')
    local curBufnr = api.nvim_get_current_buf()
    local fb = require('ufo.fold').get(curBufnr)
    for _, fr in ipairs(fb.foldRanges) do
        fb:closeFold(fr.startLine + 1, fr.endLine + 1)
    end
end

function M.openAllFolds()
    cmd('silent! %foldopen!')
end

return M
