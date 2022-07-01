local parsers = require('nvim-treesitter.parsers')
local query = require('nvim-treesitter.query')
local utils = require('ufo.utils')

local Treesitter = {}

local function prepare_query(bufnr, parser, queryName, root, rootLang)
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
    local q, p = prepare_query(bufnr, parser, 'folds', root, rootLang)
    if not q then
        return function() end
    end
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
    if noQuery then
        error('UfoFallbackException')
    end
    return res
end

function Treesitter.getFolds(bufnr)
    local rt = ktime()
    if not utils.isBufLoaded(bufnr) then
        return
    end
    local bt = vim.bo[bufnr].bt
    if bt ~= '' and bt ~= 'acwrite' then
        return
    end
    local parser = parsers.get_parser(bufnr)
    if not parser then
        error('UfoFallbackException')
    end

    local ranges = {}
    local matches = getCpatureMatchesRecursively(bufnr, parser)
    for _, node in ipairs(matches) do
        local start, _, stop, stop_col = node:range()
        if stop_col == 0 then
            stop = stop - 1
        end
        if stop > start then
            table.insert(ranges, {startLine = start, endLine = stop})
        end
    end
    info(ktime() - rt)
    return ranges
end

return Treesitter
