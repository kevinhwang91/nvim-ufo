---Export methods to the users, `require('ufo').method(...)`
---@class Ufo
local M = {}

---Setup configuration and enable ufo
---@param opts? UfoConfig
function M.setup(opts)
    opts = opts or {}
    M._config = opts
    M.enable()
end

function M.goPreviousStartFold()
    return require('ufo.action').goPreviousStartFold()
end

function M.goPreviousClosedFold()
    return require('ufo.action').goPreviousClosedFold()
end

function M.goNextClosedFold()
    return require('ufo.action').goNextClosedFold()
end

function M.closeAllFolds()
    return require('ufo.action').closeAllFolds()
end

function M.openAllFolds()
    return require('ufo.action').openAllFolds()
end

---Inspect ufo information by bufnr
---@param bufnr? number current buffer default
function M.inspect(bufnr)
    local msg = require('ufo.main').inspectBuf(bufnr)
    if not msg then
        vim.notify(('Buffer %d has not been attached.'):format(bufnr), vim.log.levels.ERROR)
    else
        vim.notify(table.concat(msg, '\n'), vim.log.levels.INFO)
    end
end

---Enable ufo
function M.enable()
    require('ufo.main').enable()
end

---Disable ufo
function M.disable()
    require('ufo.main').disable()
end

---Check whether the buffer has been attached
---@param bufnr? number current buffer default
---@return boolean
function M.hasAttached(bufnr)
    return require('ufo.main').inspectBuf(bufnr) ~= nil
end

---Attach bufnr to enable all features
---@param bufnr? number current buffer default
function M.attach(bufnr)
    require('ufo.main').attach(bufnr)
end

---Detach bufnr to disable all features
---@param bufnr? number current buffer default
function M.detach(bufnr)
    require('ufo.main').detach(bufnr)
end

---Enable to get folds and update them at once
---@param bufnr? number current buffer default
---@return string|'start'|'pending'|'stop' status
function M.enableFold(bufnr)
    return require('ufo.main').enableFold(bufnr)
end

---Disable to get folds
---@param bufnr? number current buffer default
---@return string|'start'|'pending'|'stop' status
function M.disableFold(bufnr)
    return require('ufo.main').disableFold(bufnr)
end

---Get foldingRange from the ufo internal providers by name
---@param providerName string
---@param bufnr number
---@return UfoFoldingRange|Promise
function M.getFolds(providerName, bufnr)
    local ok, res = pcall(require, 'ufo.provider.' .. providerName)
    assert(ok, ([[Can't find %s provider]]):format(providerName))
    return res.getFolds(bufnr)
end

---Set a fold virtual text handler for a buffer, will override global handler if it's existed
---@param bufnr number
---@param handler UfoFoldVirtTextHandler reference to `config.fold_virt_text_handler`
function M.setFoldVirtTextHandler(bufnr, handler)
    require('ufo.decorator'):setVirtTextHandler(bufnr, handler)
end

return M
