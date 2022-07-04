local event = require('ufo.lib.event')

local api = vim.api

---@class UfoPreviewKeymap
---@field ns number
---@field bufnr number
---@field keyMessages table
---@field keyMapsBackup table
local Keymap = {
    keyBackup = {}
}

local function setKeymaps(bufnr, keyMessages)
    local opts = {noremap = true, nowait = true}
    local rhsFmt = [[<Cmd>lua require('ufo.lib.event'):emit('onBufRemap', %d, %q)<CR>]]
    for msg, key in pairs(keyMessages) do
        local lhs = key
        local rhs = rhsFmt:format(bufnr, msg)
        api.nvim_buf_set_keymap(bufnr, 'n', lhs, rhs, opts)
    end
end

function Keymap:setKeymaps()
    setKeymaps(self.bufnr, self.keyMessages)
end

function Keymap:restoreKeymaps()
    for _, key in pairs(self.keyMessages) do
        pcall(api.nvim_buf_del_keymap, self.bufnr, 'n', key)
    end
    for _, k in ipairs(self.keyBackup) do
        api.nvim_buf_set_keymap(self.bufnr, 'n', k.lhs, k.rhs, k.opts)
    end
    self.keyBackup = {}
end

function Keymap:saveKeymaps()
    local keys = {}
    for _, v in pairs(self.keyMessages) do
        if v:match('^<.*>$') then
            v = v:upper()
        end
        keys[v] = true
    end
    for _, k in ipairs(api.nvim_buf_get_keymap(self.bufnr, 'n')) do
        if keys[k.lhs] then
            local opts = {
                expr = k.expr == 1,
                noremap = k.noremap == 1,
                nowait = k.nowait == 1,
                silent = k.silent == 1
            }
            table.insert(self.keyBackup, {lhs = k.lhs, rhs = k.rhs, opts = opts})
        end
    end
end

---
---@param bufnr number
---@param namespace number
---@param keyMessages table
---@param floatKeyMessages table
---@return UfoPreviewKeymap
function Keymap:attach(bufnr, floatBufnr, namespace, keyMessages, floatKeyMessages)
    self.bufnr = bufnr
    self.ns = namespace
    self.keyMessages = keyMessages
    self:saveKeymaps()
    self:setKeymaps()
    setKeymaps(floatBufnr, floatKeyMessages)
    vim.on_key(function(char)
        local b1, b2, b3 = char:byte(1, -1)
        -- 0x80, 0xfd, 0x4b <ScrollWheelUp>
        -- 0x80, 0xfd, 0x4c <ScrollWheelDown>
        if b1 == 0x80 and b2 == 0xfd then
            if b3 == 0x4b then
                event:emit('onBufRemap', bufnr, 'wheelUp')
            elseif b3 == 0x4c then
                event:emit('onBufRemap', bufnr, 'wheelDown')
            end
        end
        event:emit('onBufRemap', bufnr, 'onKey')
    end, namespace)
    return self
end

function Keymap:dispose()
    vim.on_key(nil, self.ns)
    self:restoreKeymaps()
end

return Keymap
