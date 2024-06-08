local foldingrange = require('ufo.model.foldingrange')
local bufmanager = require('ufo.bufmanager')


-- Defines the 'start' and 'end' markers that the provider will search. Each element of the `markers` list is a pair of the 'start'
-- and 'end' marker. Example: `local markers = { { 'start marker', 'end marker' } }`
-- The search is done by marker pair. One marker pair does not affect the other. So the end marker of `markers[0]` will not close the start
-- marker of `markers[1]`, by example
local markers = {
	vim.fn.split(vim.wo.foldmarker, ','),  -- Configured Vim marker
	{ '#region ', '#endregion' }           -- VS Code marker style
}


-- Defines if the provider will only accept markers inside comments
if vim.g.ufo_markers_only_comment == nil then
    vim.g.ufo_markers_only_comment = true
end


-- Provider implementation

local Marker = {}


--- Return the start and end column of the marker
-- If the marker is not found, return nil
-- @param marker string Marker text to be searched
-- @param lines table List of lines of the buffer to search the markers
-- @param lineNum number Line where to search by the marker (starting from 1)
-- @param bufnr number Vim buffer number where to search the marker
-- @return number[]|nil {startColumn, endColumn} or nil if not found
local function getMarkerPosition(marker, lines, lineNum, bufnr)
    local startColumn, endColumn = lines[lineNum]:find(marker, 1, true)

    -- 'startColumn' is nil if the marker is not found
    if startColumn == nil then
        return nil
    end

    -- Does not check if the marker is inside a comment
    if not vim.g.ufo_markers_only_comment then
        return {startColumn, endColumn}
    end

    -- Check if the marker is inside a comment. Does it using native vim highlight or Treesitter.
    -- Treesitter can disable the native highlight search. So it is required to test both. First
    -- try to use the native highlight, then try to use Treesitter

    local cursorSynID = vim.fn.synIDtrans(vim.fn.synID(lineNum, startColumn, 1))  -- `synIDtrans()` is required to follow highlight links

    if cursorSynID ~= 0 then  -- `cursorSynID` is 0 if has been occurred an error (e.g. Can not find a highlight because of Treesitter)
        local cursorSynName = vim.fn.synIDattr(cursorSynID, 'name')

        if cursorSynName == 'Comment' then
            return {startColumn, endColumn}
        end

    -- Tries to use Treesitter
    else
        -- Treesitter line index starts in 0, and lineNum starts in 1. Because of it, the line index must be decreased by 1
        local captures = vim.treesitter.get_captures_at_pos(bufnr, lineNum-1, startColumn)

        for _, value in ipairs(captures) do
            if value.capture == 'comment' then
                return {startColumn, endColumn}
            end
        end
    end

    return nil
end


--- Function that returns folds for the provided buffer based in the markers
-- @param bufnr number Vim buffer number
-- @return UfoFoldingRange[] List of marker folds in the buffer
function Marker.getFolds(bufnr)
    local buf = bufmanager:get(bufnr)

    -- Does not work with buffers that are not managed by UFO
    if not buf then
        return
    end

    local lines = buf:lines(1, -1)

    local folds = {}

    for _, marker in ipairs(markers) do
        local openMarkerLines = {}

        for lineNum, line in ipairs(lines) do
            -- Open marker
            local markerColumns = getMarkerPosition(marker[1], lines, lineNum, bufnr)

            if markerColumns then
                table.insert(openMarkerLines, lineNum)

            -- Close marker
            else
                markerColumns = getMarkerPosition(marker[2], lines, lineNum, bufnr)

                if markerColumns then
                    local relatedOpenMarkerLine = table.remove(openMarkerLines)

                    if relatedOpenMarkerLine then
                        table.insert(
                        folds,
                        foldingrange.new(relatedOpenMarkerLine - 1, lineNum - 1, nil, nil, 'ufo_marker')
                        )
                    end
                end
            end
        end

        -- Closes all remaining open markers (they will be open to the end of the file)
        for _, markerStart in ipairs(openMarkerLines) do
            table.insert(folds, foldingrange.new(markerStart - 1, #lines, nil, nil, 'ufo_marker'))
        end
    end

    return folds
end


return Marker
