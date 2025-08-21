resourceLoaded = {}
mapUnloaded = false
lodIDList = {}

-- Utility: Read all lines from a file handle, returns a table of lines
local function fileToLines(fh)
    if not fh then return {} end
    local size = fileGetSize(fh)
    if not size or size == 0 then fileClose(fh); return {} end
    local data = fileRead(fh, size)
    fileClose(fh)
    local result = {}
    for line in data:gmatch("[^\r\n]+") do
        table.insert(result, line)
    end
    return result
end

-- Load a zone .definition file (returns table of attribute tables)
function loadZone(resourceName, zone)
    zone = zone:gsub("%s+", "")
    local path = (":%s/zones/%s/%s.definition"):format(resourceName, zone, zone)
    if not fileExists(path) then
        print(string.format("Unable to find zone: %s", path))
        return
    end
    local xml = xmlLoadFile(path)
    if not xml then return end
    local defs = {}
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local attributes = xmlNodeGetAttributes(node)
        getFlags(attributes)
        table.insert(defs, attributes)
    end
    xmlUnloadFile(xml)
    return defs
end

-- Load a zone .map file (returns table of attribute tables with .type field)
function loadMap(resourceName, zone)
    zone = zone:gsub("%s+", "")
    local path = (":%s/zones/%s/%s.map"):format(resourceName, zone, zone)
    if not fileExists(path) then return end
    local xml = xmlLoadFile(path)
    if not xml then return end
    local entries = {}
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local attributes = xmlNodeGetAttributes(node)
        attributes.type = xmlNodeGetName(node)
        table.insert(entries, attributes)
    end
    xmlUnloadFile(xml)
    return entries
end

-- Remove world map and/or interiors as needed
function removeWorldMapConfirm(water)
    if removeDefaultMap then
        if water then
            setWaterLevel(-10000000)
        end
        if removeDefaultInteriors then
            removeGameWorld()
        else
            for i = 0, 50000 do
                removeWorldModel(i, 5000, 0, 0, 0, 0)
                removeWorldModel(i, 5000, 0, 0, 0, 13)
            end
        end
        setOcclusionsEnabled(false)
    end
end

function streamMapElements(resourceName, elementList,offX,offY,offZ)
    local objects = {}
    for _, element in ipairs(elementList or {}) do
        if not (lodIDList[element.id] and highDefLODs) then
            local newElement = streamElement(
                element.id,
                element.type,
                {tonumber(element.posX) or 0 + offX, tonumber(element.posY) or 0 + offY, tonumber(element.posZ) or 0 + offZ},
                {tonumber(element.rotX) or 0, tonumber(element.rotY) or 0, tonumber(element.rotZ) or 0},
                element.interior,
                element.dimension,
                element.lodParent,
                element.uniqueID,
                true
            )
            if newElement then
                table.insert(objects, newElement)
            end
        end
    end
    return objects
end

-- Handles loading zones, maps, and water on resource start
function onResourceStartTimer(resourceThatStarted)
    local resourceName = getResourceName(resourceThatStarted)
    local zoneFilePath = (":%s/eagleZones.txt"):format(resourceName)
    local waterFilePath = (":%s/water.dat"):format(resourceName)
    if not fileExists(zoneFilePath) or resourceLoaded[resourceName] then return end

    local elementList, definitionList = {}, {}

    -- Load maps first
    local fh = fileOpen(zoneFilePath)
    local maps = fileToLines(fh)

    -- check first line for #offset
    local offsetX, offsetY, offsetZ = 0, 0, 0
    if maps[1] and maps[1]:sub(1,7) == "#offset" then
        local x,y,z = maps[1]:match("#offset%s+([^,]+),([^,]+),([^,]+)")
        if x and y and z then
            offsetX, offsetY, offsetZ = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
        end
        table.remove(maps, 1) -- remove the offset line so it’s not treated as a map name
    end

    for _, map in ipairs(maps) do
        for _, v in ipairs(loadMap(resourceName, map) or {}) do
            table.insert(elementList, v)
            if v.lodParent then
                lodIDList[v.lodParent] = true
            end
        end
    end


    -- Then definitions
    local fh2 = fileOpen(zoneFilePath)
    local zones = fileToLines(fh2)
    for _, zone in ipairs(zones) do
        for _, v in ipairs(loadZone(resourceName, zone) or {}) do
            if not (lodIDList[v.id] and highDefLODs) then
                table.insert(definitionList, v)
            end
        end
    end

    removeWorldMapConfirm(true)
    engineRestreamWorld()
    streamMapElements(resourceName, elementList,offsetX, offsetY, offsetZ)

    local lastDef = definitionList[#definitionList]
    if lastDef then
        loadMapDefinitions(resourceName, definitionList, lastDef.id)
    end

    parseWaterDat(waterFilePath, resourceName)
end

addEventHandler("onClientResourceStart", root, onResourceStartTimer)
