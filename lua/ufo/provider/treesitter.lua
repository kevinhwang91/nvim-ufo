local bufmanager = require('ufo.bufmanager')
local foldingrange = require('ufo.model.foldingrange')

---@class UfoTreesitterProvider
---@field hasProviders table<string, boolean>
local Treesitter = {
    hasProviders = {}
}

---@diagnostic disable: deprecated
---@return vim.treesitter.LanguageTree|nil parser for the buffer, or nil if parser is not available
local function getParser(bufnr, lang)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok then
        return nil
    end
    return parser
end
local get_query = assert(vim.treesitter.query.get or vim.treesitter.query.get_query)
local get_query_files = assert(vim.treesitter.query.get_files or vim.treesitter.query.get_query_files)
---@diagnostic enable: deprecated


-- Backward compatibility for the dummy directive (#make-range!),
-- which no longer exists in nvim-treesitter v1.0+
if not vim.tbl_contains(vim.treesitter.query.list_directives(), "make-range!") then
    vim.treesitter.query.add_directive("make-range!", function() end, {})
end

local MetaNode = {}
MetaNode.__index = MetaNode

function MetaNode:new(range, type)
    local o = self == MetaNode and setmetatable({}, self) or self
    o._range = range
    o._type = type
    return o
end

function MetaNode:range()
    local range = self._range
    return range[1], range[2], range[3], range[4]
end

function MetaNode:type()
    return self._type
end

--- Return a meta node that represents a range between two nodes, i.e., (#make-range!),
--- that is similar to the legacy TSRange.from_node() from nvim-treesitter.
function MetaNode.from_nodes(start_node, end_node)
    local start_pos = { start_node:start() }
    local end_pos = { end_node:end_() }
    return MetaNode:new({
        [1] = start_pos[1],
        [2] = start_pos[2],
        [3] = end_pos[1],
        [4] = end_pos[2],
    })
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

    return get_query(rootLang, queryName), {
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

        -- Extract capture names from each match
        for id, nodes in pairs(match) do
            local m = metadata[id]
            if m and m.range then
                local type = nodes.type and nodes:type() or nil
                node = MetaNode:new(m.range, type)
            elseif type(nodes) ~= "table" then
                -- old behaviou before 0.11
                node = nodes
            elseif #nodes == 1 then
                node = nodes[1]
            else
                node = MetaNode.from_nodes(nodes[1], nodes[#nodes])
            end

            table.insert(matches, node)
        end

        -- Add some predicates for testing
        local preds = q.info.patterns[pattern]
        if preds then
            for _, pred in pairs(preds) do
                if pred[1] == 'make-range!' and type(pred[2]) == 'string' and #pred == 4 then
                    local node = MetaNode.from_nodes(match[pred[3]], match[pred[4]])
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
        local has_folds = #get_query_files(lang, 'folds', nil) > 0
        if has_folds then
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
    local parser = getParser(bufnr)
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
        if node.range then
            local start, _, stop, stop_col = node:range()
            if stop_col == 0 then
                stop = stop - 1
            end
            if stop > start then
                local type = node.type and node:type() or nil
                table.insert(ranges, foldingrange.new(start, stop, nil, nil, type))
            end
        end
    end
    foldingrange.sortRanges(ranges)
    return ranges
end

function Treesitter:dispose()
    self.hasProviders = {}
end

return Treesitter
