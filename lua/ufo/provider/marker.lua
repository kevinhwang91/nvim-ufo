local foldingrange = require('ufo.model.foldingrange')
local bufmanager = require('ufo.bufmanager')


-- Defines the 'start' and 'end' markers that the provider will search. Each element of the `markers` list is a pair of the 'start'
-- and 'end' marker. Example: `local markers = { { 'start marker', 'end marker' } }`
-- The search is done by marker pair. One marker pair does not affect the other. So the end marker of `markers[0]` will not close the start
-- marker of `markers[1]`, by example
local markers = {
	vim.fn.split(vim.wo.foldmarker, ','),  -- Configured Vim marker
	{
        '#region ',   -- Start of VS code marker
        '#endregion'  -- End of VS Code marker
    }
}


-- Provider implementation

local Marker = {}


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
            local markerColumns = line:find(marker[1], 1, true)

            if markerColumns then
                table.insert(openMarkerLines, lineNum)

            -- Close marker
            else
                markerColumns = line:find(marker[2], 1, true)

                if markerColumns then
                    local relatedOpenMarkerLine = table.remove(openMarkerLines)

                    if relatedOpenMarkerLine then
                        table.insert(
                        folds,
                        foldingrange.new(relatedOpenMarkerLine - 1, lineNum - 1, nil, nil, 'marker')
                        )
                    end
                end
            end
        end

        -- Closes all remaining open markers (they will be open to the end of the file)
        for _, markerStart in ipairs(openMarkerLines) do
            table.insert(folds, foldingrange.new(markerStart - 1, #lines, nil, nil, 'marker'))
        end
    end

    return folds
end


return Marker
