local disposable = require('ufo.lib.disposable')
local log        = require('ufo.lib.log')

---@class UfoEvent
local Event = {
    _collection = {}
}

---@param name string
---@param listener function
function Event:off(name, listener)
    local listeners = self._collection[name]
    if not listeners then
        return
    end
    for i = 1, #listeners do
        if listeners[i] == listener then
            table.remove(listeners, i)
            break
        end
    end
    if #listeners == 0 then
        self._collection[name] = nil
    end
end

---@param name string
---@param listener function
---@param disposables? UfoDisposable[]
---@return UfoDisposable
function Event:on(name, listener, disposables)
    if not self._collection[name] then
        self._collection[name] = {}
    end
    table.insert(self._collection[name], listener)
    local d = disposable:create(function()
        self:off(name, listener)
    end)
    if type(disposables) == 'table' then
        table.insert(disposables, d)
    end
    return d
end

---@param name string
---@vararg any
function Event:emit(name, ...)
    local listeners = self._collection[name]
    if not listeners then
        return
    end
    log.trace('event:', name, 'listeners:', listeners, 'args:', ...)
    for _, listener in ipairs(listeners) do
        listener(...)
    end
end

return Event
