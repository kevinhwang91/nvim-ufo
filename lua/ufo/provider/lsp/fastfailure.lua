local promise = require('promise')

---@class UfoLspFastFailure
---@field initialized boolean
local FastFailure = {
    initialized = false
}

---
---@param bufnr number
---@param kind? string|'comment'|'imports'|'region'
---@return Promise
---@diagnostic disable-next-line: unused-local
function FastFailure.requestFoldingRange(bufnr, kind)
    return promise.reject('No provider')
end

return FastFailure
