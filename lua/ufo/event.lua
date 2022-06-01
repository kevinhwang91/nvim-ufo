---@class UfoEvent
local Event = {
    _collection = {}
}

---@param name string
---@param listener function
function Event.off(name, listener)
    local listeners = Event._collection[name]
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
        Event._collection[name] = nil
    end
end

---@param name string
---@param listener function
---@param disposables table
---@return table
function Event.on(name, listener, disposables)
    if not Event._collection[name] then
        Event._collection[name] = {}
    end
    table.insert(Event._collection[name], listener)
    local disposable = {
            dispose = function()
                Event.off(name, listener)
            end
    }
    if type(disposables) == 'table' then
        table.insert(disposables, disposable)
    end
    return disposable
end

---@param name string
---@vararg any
function Event.emit(name, ...)
    local listeners = Event._collection[name]
    if not listeners then
        return
    end
    for _, listener in ipairs(listeners) do
        listener(...)
    end
end

return Event
