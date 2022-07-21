local parsers = require('nvim-treesitter.parsers')
local query = require('nvim-treesitter.query')
local bufmanager = require('ufo.bufmanager')
local foldingrange = require('ufo.model.foldingrange')

local Treesitter = {}
local hasProviders = {}

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
        local pattern, match = iter()
        local matches = {}
        if pattern == nil then
            return pattern
        end
        for id, node in ipairs(match) do
            local name = q.captures[id] -- name of the capture in the query
            if name then
                table.insert(matches, node)
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
        return
    end
    local ft = buf:filetype()
    if hasProviders[ft] == false then
        error('UfoFallbackException')
    end
    local parser = parsers.get_parser(bufnr)
    if not parser then
        hasProviders[ft] = false
        error('UfoFallbackException')
    end

    local ranges = {}
    local ok, matches = getCpatureMatchesRecursively(bufnr, parser)
    if not ok then
        hasProviders[ft] = false
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

return Treesitter
