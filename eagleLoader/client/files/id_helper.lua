saIDList = {}
defaultIDs = {}
currentSAIndex = 1

-- Utility: read lines from a file handle, returns array of lines
local function getLines(fh)
    if not fh then
        print("Error: Unable to open file handle")
        return {}
    end
    local size = fileGetSize(fh)
    if not size or size == 0 then
        fileClose(fh)
        return {}
    end
    local data = fileRead(fh, size)
    fileClose(fh)
    local result = {}
    for line in string.gmatch(data or "", "[^\r\n]+") do
        table.insert(result, line)
    end
    return result
end

-- Load ID lists
local idListFile = fileOpen("client/files/sa_id_list.id")
local fullIdListFile = fileOpen("client/files/sa_full_id_list.id")

local idList = getLines(idListFile)
local fullIdList = getLines(fullIdListFile)

-- Populate saIDList
for _, line in ipairs(idList) do
    local fields = split(line, ",")
    if tonumber(fields[1]) then
        table.insert(saIDList, tonumber(fields[1]))
    end
end

-- Populate defaultIDs table for name->ID
for _, line in ipairs(fullIdList) do
    local fields = split(line, ",")
    if fields[1] and fields[2] then
        local name = fields[2]:gsub("%s+", "")
        defaultIDs[name] = tonumber(fields[1])
    end
end

-- Request the next available SA model ID
function engineRequestSAModel()
    if currentSAIndex > #saIDList then
        return false
    end

    local model = saIDList[currentSAIndex]
    currentSAIndex = currentSAIndex + 1
    return model
end

-- Reset the SA model-ID pool so it can be reused. Safe to call only when no
-- maps are currently loaded (otherwise IDs could be handed out twice).
function resetSAModelPool()
    currentSAIndex = 1
end
