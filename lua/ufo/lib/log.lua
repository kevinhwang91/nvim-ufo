--- Singleton
---@class UfoLog
---@field trace fun(...)
---@field debug fun(...)
---@field info fun(...)
---@field warn fun(...)
---@field error fun(...)
---@field path string
local Log = {}
local fn = vim.fn
local uv = vim.loop

---@type table<string, number>
local levelMap
local levelNr
local defaultLevel

local function getLevelNr(level)
    local nr
    if type(level) == 'number' then
        nr = level
    elseif type(level) == 'string' then
        nr = levelMap[level:upper()]
    else
        nr = defaultLevel
    end
    return nr
end

---
---@param l number|string
function Log.setLevel(l)
    levelNr = getLevelNr(l)
end

---
---@param l number|string
---@return boolean
function Log.isEnabled(l)
    return getLevelNr(l) >= levelNr
end

---
---@return string|'trace'|'debug'|'info'|'warn'|'error'
function Log.level()
    for l, nr in pairs(levelMap) do
        if nr == levelNr then
            return l
        end
    end
    return 'UNDEFINED'
end

local function inspect(v)
    local s
    local t = type(v)
    if t == 'nil' then
        s = 'nil'
    elseif t ~= 'string' then
        s = vim.inspect(v)
    else
        s = tostring(v)
    end
    return s
end

local function pathSep()
    return uv.os_uname().sysname == 'Windows_NT' and [[\]] or '/'
end

local function init()
    local logDir = fn.stdpath('cache')
    Log.path = table.concat({logDir, 'ufo.log'}, pathSep())
    local logDateFmt = '%y-%m-%d %T'

    fn.mkdir(logDir, 'p')
    levelMap = {TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4}
    defaultLevel = 3
    Log.setLevel(vim.env.UFO_LOG)

    for l in pairs(levelMap) do
        Log[l:lower()] = function(...)
            local argc = select('#', ...)
            if argc == 0 or levelMap[l] < levelNr then
                return
            end
            local msgTbl = {}
            for i = 1, argc do
                local arg = select(i, ...)
                table.insert(msgTbl, inspect(arg))
            end
            local msg = table.concat(msgTbl, ' ')
            local info = debug.getinfo(2, 'Sl')
            local linfo = info.short_src:match('[^/]*$') .. ':' .. info.currentline

            local fp = assert(io.open(Log.path, 'a+'))
            local str = string.format('[%s] [%s] %s : %s\n', os.date(logDateFmt), l, linfo, msg)
            fp:write(str)
            fp:close()
        end
    end
end

init()

return Log
