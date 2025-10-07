-- =========================
-- Event Handling
-- =========================

function initializeObjects()
    -- Gather all relevant elements (objects + buildings)
    local allElements = {}
    for _, object in ipairs(getElementsByType("object")) do
        table.insert(allElements, object)
    end
    for _, building in ipairs(getElementsByType("building")) do
        table.insert(allElements, building)
    end

    -- Apply streaming properties to each element
    for _, element in ipairs(allElements) do
        if isElement(element) then
            local id = getElementID(element)
            if id then
                setElementStream(element, id, true, true)
            end
        end
    end
end

-- =========================
-- Streaming
-- =========================

selfLODList = {}

function setElementStream(element, newModel, streamNew, initial, lodParent, uniqueID)
    if not isElement(element) or not newModel then
        outputDebugString2("Error: Invalid element or model specified.")
        return
    end

    local id = getElementID(element) or newModel
    if not id then
        outputDebugString2("Error: Could not determine element ID.")
        return
    end

    local cachedModel = idCache[id]

    if cachedModel then
        if uniqueID then
            uniqueIDs[element] = uniqueID
        end

        setElementModel(element, cachedModel)

        
        setElementID(element, id)

        if definitionZones[id] then
            setElementData(element, "Zone", definitionZones[id] or "")
        end

        prepTime(element, id)

        -- Register element in tracking lists
        if uniqueID then
            itemIDListUnique[id] = itemIDListUnique[id] or {}
            itemIDListUnique[id][uniqueID] = element
        else
            itemIDList[id] = itemIDList[id] or {}
            table.insert(itemIDList[id], element)
        end

        -- Setup custom properties
        for i, v in pairs(definedProperties[id] or {}) do
            setupProperties(element, i, v)
        end

        -- LOD Parenting Logic

        if (not disableLOD) then
            lodParent = lodParents[element] or lodParent
            if highDefLODs and lodParent then
                setupSelfLOD(element, getElementType(element))
            else
                if lodParent then
                    if string.lower(lodParent) == "self" then
                        setupSelfLOD(element, getElementType(element))
                    else
                        lodParents[element] = lodParent
                        local parent = (itemIDListUnique[lodParent] or {})[uniqueID or 0] or (itemIDList[lodParent] or {})[1]
                        if parent then
                            setLowLODElement(element, parent)
                            if lodAttach and lodAttach[lodParent] then
                                attachElements(element, parent)
                            end
                        end
                    end
                end
            end
        end
    else
        local model = defaultIDs[id]
        if model then
            setElementModel(element, model)
            setElementID(element, id)
        else
            if streamDebug then
                outputDebugString2(string.format("Error: Model ID %s not found in cache (Default).", id))
            end
        end
    end
end

addEvent("setElementStream", true)
addEventHandler("setElementStream", resourceRoot, setElementStream)

function setupSelfLOD(element, type)
    if selfLODList[element] then
        destroyElement(selfLODList[element])
    end

    local x, y, z    = getElementPosition(element)
    local xr, yr, zr = getElementRotation(element)

    local createFun = (type == 'building') and createBuilding or createObject
    local build = createFun(1337, x, y, z, xr, yr, zr)
    setElementModel(build, getElementModel(element))
    setLowLODElement(element, build)
    selfLODList[element] = build
    prepTime(build, getElementModel(element))
    setElementCollisionsEnabled(build, false)
end

function setupProperties(element, property, setting)
    if property then
        local propertyFun =
            (property == "collisions_disabled" and setElementCollisionsEnabled) or
            (assetType == "no_stream" and setElementStreamable) or
            setElementCollisionsEnabled

        propertyFun(element, setting)
    end
end

-- =========================
-- Element Creation
-- =========================

function streamElement(id, type, pos, rot, interior, dimension, parentLOD, uniqueID, ignoreStream)
    if modelCrashDebug then
        addToSpawnList(id)
        return
    end

    if not id then
        outputDebugString2("Error: Trying to create invalid element.")
        return
    end

    local x, y, z    = unpack(pos)
    local xr, yr, zr = unpack(rot)

    local validBuilding = ((x > -3000) and (x < 3000) and (y > -3000) and (y < 3000))
    
    local createFun = ((type == 'building') and validBuilding and (not forceObject)) and createBuilding or createObject


    local element = createFun(1337, x, y, z, xr, yr, zr)
    setElementInterior(element, tonumber(interior) or 0)

    if not ignoreStream then
        setElementStream(element, id, true, nil, parentLOD, uniqueID)
    end

    if parentLOD then lodParents[element] = parentLOD end
    if uniqueID then uniqueIDs[element] = uniqueID end

    setElementID(element, id)

    return element
end

function streamObject(id, x, y, z, xr, yr, zr, interior, dimension, parentLOD, uniqueID, ignoreStream)
    return streamElement(id, 'object',
        {tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0},
        {tonumber(xr) or 0, tonumber(yr) or 0, tonumber(zr) or 0},
        interior, dimension, parentLOD, uniqueID, ignoreStream)
end

function streamBuilding(id, x, y, z, xr, yr, zr, interior, parentLOD, uniqueID, ignoreStream)
    return streamElement(id, 'building',
        {tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0},
        {tonumber(xr) or 0, tonumber(yr) or 0, tonumber(zr) or 0},
        interior, parentLOD, uniqueID, ignoreStream)
end

-- =========================
-- Data & Destroy Events
-- =========================

function onElementDataChange(dataName, oldValue)
    if (dataName == "id") and isElement(source) then
        local newId = getElementID(source)
        if newId and idCache[newId] and newId ~= oldValue then
            setElementStream(source, newId)
        end
    end
end
addEventHandler("onElementDataChange", root, onElementDataChange)

function onElementDestroy()
    local elementID   = getElementID(source)
    local elementType = getElementType(source)
    if elementID and idCache[elementID] and (elementType == "object" or elementType == "building") then
        local LOD = getLowLODElement(source)
        if isElement(LOD) then
            destroyElement(LOD)
            outputDebugString2(string.format("LOD for %s with ID %s destroyed successfully.", elementType, elementID))
        end
    end
end
addEventHandler("onElementDestroy", resourceRoot, onElementDestroy)
