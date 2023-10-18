local parsers = require('nvim-treesitter.parsers')
local query = require('nvim-treesitter.query')
local tsrange = require('nvim-treesitter.tsrange')
local bufmanager = require('ufo.bufmanager')
local foldingrange = require('ufo.model.foldingrange')

---@class UfoTreesitterProvider
---@field hasProviders table<string, boolean>
local Treesitter = {
    hasProviders = {}
}

local MetaNode = {}
MetaNode.__index = MetaNode

function MetaNode:new(range)
    local o = self == MetaNode and setmetatable({}, self) or self
    o.value = range
    return o
end

function MetaNode:range()
    local range = self.value
    return range[1], range[2], range[3], range[4]
end

local function prepareQuery(bufnr, parser, root, rootLang, queryName)
    if not root then
        local firstTree = parser:trees()[1]
        if firstTree then
            root = firstTree:root()
        else
            return
        end
    end

    local range = {root:range()}

    if not rootLang then
        local langTree = parser:language_for_range(range)
        if langTree then
            rootLang = langTree:lang()
        else
            return
        end
    end

    return query.get_query(rootLang, queryName), {
        root = root,
        source = bufnr,
        start = range[1],
        -- The end row is exclusive so we need to add 1 to it.
        stop = range[3] + 1,
    }
end

local function iterFoldMatches(bufnr, parser, root, rootLang)
    local q, p = prepareQuery(bufnr, parser, root, rootLang, 'folds')
    if not q then
        return function() end
    end
    ---@diagnostic disable-next-line: need-check-nil
    local iter = q:iter_matches(p.root, p.source, p.start, p.stop)
    return function()
        local pattern, match, metadata = iter()
        local matches = {}
        if pattern == nil then
            return pattern
        end
        for id, node in pairs(match) do
            local m = metadata[id]
            if m.range then
                node = MetaNode:new(m.range)
            end
            table.insert(matches, node)
        end
        local preds = q.info.patterns[pattern]
        if preds then
            for _, pred in pairs(preds) do
                if pred[1] == 'make-range!' and type(pred[2]) == 'string' and #pred == 4 then
                    local node = tsrange.TSRange.from_nodes(bufnr, match[pred[3]], match[pred[4]])
                    table.insert(matches, node)
                end
            end
        end
        return matches
    end
end

local function getFoldMatches(res, bufnr, parser, root, lang)
    for matches in iterFoldMatches(bufnr, parser, root, lang) do
        for _, node in ipairs(matches) do
            table.insert(res, node)
        end
    end
    return res
end

local function getCpatureMatchesRecursively(bufnr, parser)
    local noQuery = true
    local res = {}
    parser:for_each_tree(function(tree, langTree)
        local lang = langTree:lang()
        if query.has_folds(lang) then
            noQuery = false
            getFoldMatches(res, bufnr, parser, tree:root(), lang)
        end
    end)
    return not noQuery, res
end

function Treesitter.getFolds(bufnr)
    local buf = bufmanager:get(bufnr)
    if not buf then
        return
    end
    local bt = buf:buftype()
    if bt ~= '' and bt ~= 'acwrite' then
        if bt == 'nofile' then
            error('UfoFallbackException')
        end
        return
    end
    local self = Treesitter
    local ft = buf:filetype()
    if self.hasProviders[ft] == false then
        error('UfoFallbackException')
    end
    local parser = parsers.get_parser(bufnr)
    if not parser then
        self.hasProviders[ft] = false
        error('UfoFallbackException')
    end

    local ranges = {}
    local ok, matches = getCpatureMatchesRecursively(bufnr, parser)
    if not ok then
        self.hasProviders[ft] = false
        error('UfoFallbackException')
    end
    for _, node in ipairs(matches) do
        local start, _, stop, stop_col = node:range()
        if stop_col == 0 then
            stop = stop - 1
        end
        if stop > start then
            table.insert(ranges, foldingrange.new(start, stop))
        end
    end
    foldingrange.sortRanges(ranges)
    return ranges
end

function Treesitter:dispose()
    self.hasProviders = {}
end

return Treesitter
