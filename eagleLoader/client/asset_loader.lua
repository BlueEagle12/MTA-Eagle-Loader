-- =========================
-- Resource Management State
-- =========================
resource            = {}
resourceModels      = {}
resourceImages      = {}
imageFiles          = {}
streamingDistances  = {}
validID             = {}
definitionZones     = {}
timeIDs             = {}
itemIDList          = {}
itemIDListUnique    = {}
lodParents          = {}
uniqueIDs           = {}
textureIDs          = {}
definedProperties   = {}
selfLODList         = {}
mapElements         = {}   -- per-resource list of created world elements (for cleanup on unload)

-- Optionally increase streaming memory on nightly builds
if engineStreamingSetMemorySize then
    engineStreamingSetMemorySize(streamingMemoryAllocation * 1024 * 1024)
    engineStreamingSetBufferSize(streamingBufferAllocation * 1024 * 1024)
end

-- =========================
-- Asset Loading / Streaming
-- =========================

local function collectValidIDs()
    -- Rebuild from the elements that currently exist so the table doesn't
    -- accumulate stale IDs from maps that have since been unloaded.
    validID = {}
    for _, obj in ipairs(getElementsByType('object')) do
        validID[getElementID(obj)] = true
    end
    for _, obj in ipairs(getElementsByType('building')) do
        validID[getElementID(obj)] = true
    end
end

local function findFile(assetName, assetType, resourceName, zone)

    local assetPath        = string.format(":%s/zones/%s/%s/%s.%s", resourceName, zone, assetType, assetName, assetType)

    local assetPathTexture = string.format(":%s/textures/%s.txd", resourceName, assetName)
    if fileExists(assetPath) then
        return assetPath
    elseif fileExists(assetPathTexture) then
        return assetPathTexture
    end
end

local function requestTextureID(assetName, img, path)
    if not textureIDs[assetName] then
        textureIDs[assetName] = engineRequestTXD(assetName)
    end
    -- Always re-link to the current IMG: after a resource restart the old IMG
    -- archive is removed and a new one is created, so the TXD-to-IMG association
    -- must be re-established even if the TXD slot was already allocated.
    engineImageLinkTXD(img, path, textureIDs[assetName])
    return textureIDs[assetName]
end

local function loadImgAsset(assetType, assetName, resourceName, modelID)
    if not assetName then return end
    local assetPath = string.format("%s.%s", assetName, assetType)
    local img = imageFiles[resourceName] and imageFiles[resourceName][assetPath]
    if not img then return end

    if assetType == "txd" then
        local tID = requestTextureID(assetName, img, assetPath)
        engineSetModelTXDID(modelID, tID)
    elseif assetType == "col" then
        local asset = engineImageGetFile(img, assetPath)
        local col = engineLoadCOL(asset)
        engineReplaceCOL(col, modelID)
    elseif assetType == "dff" then
        engineImageLinkDFF(img, assetPath, modelID)
    end
end

local function loadAsset(assetType, assetName, resourceName, zone, modelID, alpha)
    if not assetName then return end
    local assetPath = findFile(assetName, assetType, resourceName, zone)
    if not assetPath then
        outputDebugString2(string.format("%s: %s could not be found!", assetType:upper(), assetName.."."..assetType))
        return
    end

    local loaderFunc =
        (assetType == "txd" and requestTextureArchive) or
        (assetType == "col" and requestCollision) or
        (assetType == "dff" and requestModel)

    local asset, cachePath = loaderFunc(assetPath, assetName)
    if not asset then
        outputDebugString2(string.format("%s: %s could not be loaded!", assetType:upper(), assetName))
        return
    end

    if assetType == "txd" then
        engineImportTXD(asset, modelID)
    elseif assetType == "col" then
        engineReplaceCOL(asset, modelID)
    elseif assetType == "dff" then
        local dff = engineReplaceModel(asset, modelID, alpha or false)
        if not dff then
            outputDebugString2(string.format("%s: %s could not be replaced! : %s", assetType:upper(), assetName, modelID))
            return
        end
    end
    -- Optionally: cache loaded asset
    -- table.insert(resource[resourceName], cachePath)
end

local function tryLoadAsset(assetType, fileName, resourceName, zone, modelID, ...)
    if not fileName then return end
    if inIMGAsset(fileName, assetType, resourceName) then
        loadImgAsset(assetType, fileName, resourceName, modelID)
        return true
    else
        if findFile(fileName, assetType, resourceName, zone) then
            loadAsset(assetType, fileName, resourceName, zone, modelID, ...)
            return true
        end
    end
end

-- =========================
-- Map Definitions Loading
-- =========================
function loadMapDefinitions(resourceName, mapDefinitions, last)
    resourceModels[resourceName] = {}
    resource[resourceName] = {}
    startTickCount = getTickCount()
    collectValidIDs()
    prepIMGContainers(resourceName)
    Async:setPriority("normal")

    Async:foreach(mapDefinitions, function(data)
        local modelID, isNew = requestModelID(data.id, true)
        if not tonumber(modelID) then
            outputDebugString2(string.format("Error: Failed to request model ID for object with ID: %s", tostring(data.id)))
            return
        end

        if isNew then
            resourceModels[resourceName][modelID] = true
        end

        if streamEverything or validID[data.id] then
            definedProperties[data.id] = definedProperties[data.id] or {}
            local zone        = data.zone
            local lodDistance = tonumber(data.lodDistance) or 200

            definitionZones[modelID] = zone
            definitionZones[data.id] = zone

            -- LOD distance logic
            local finalDist = (highDefLODs or lodDistance < 10) and 700 or lodDistance
            finalDist = finalDist * drawDistanceMultiplier
            engineSetModelLODDistance(modelID, finalDist, true)
            streamingDistances[modelID] = finalDist

            -- Set model flags and custom funs
            for _, v in pairs(objectFlags) do
                if v.custom then
                    if data[v.name] then
                        definedProperties[data.id][v.name] = v.value
                    end
                else
                    engineSetModelFlag(modelID, v.name, data[v.name] or false)
                end
            end

            -- Load assets
            local dff, col = false, false
            local txdTable = split(data.txd, ',')
            if txdTable then
                for _, txd in ipairs(txdTable) do
                    tryLoadAsset('txd', txd, resourceName, zone, modelID)
                end
            else
                tryLoadAsset('txd', data.txd, resourceName, zone, modelID)
            end

            col = tryLoadAsset('col', data.col or data.id, resourceName, zone, modelID)
            dff = tryLoadAsset('dff', data.dff or data.id, resourceName, zone, modelID, data['draw_last'] or data['additive'])

            -- Time window
            if data.timeIn then
                timeIDs[data.id] = { tonumber(data.timeIn), tonumber(data.timeOut) }
                setModelStreamTime(modelID, data.id, tonumber(data.timeIn), tonumber(data.timeOut))
            end
        end

        if data.id == last then
            loaded(resourceName)
        end
    end)
end

-- =========================
-- Unloading & Cleanup
-- =========================
function unloadMapDefinitions(name)
    if not name or not resource[name] then return end

    -- 1. Destroy the world elements (objects/buildings) created for this map.
    --    This MUST happen before idCache is cleared below, so onElementDestroy
    --    can still resolve each element and tear down its LOD + tracking-table
    --    entries (lodParents, uniqueIDs, selfLODList, itemIDList, ...).
    for _, el in ipairs(mapElements[name] or {}) do
        if isElement(el) then destroyElement(el) end
    end
    mapElements[name] = nil

    -- 2. Destroy water planes registered for this resource.
    for _, el in ipairs(resource[name] or {}) do
        if isElement(el) then destroyElement(el) end
    end

    -- 3. Clear id<->model mappings and the per-id / per-model metadata that
    --    would otherwise grow every time a map is loaded.
    for modelID, strID in pairs(reverseID) do
        if resourceModels[name][modelID] then
            idCache[strID]              = nil
            reverseID[modelID]          = nil
            definitionZones[modelID]    = nil
            definitionZones[strID]      = nil
            streamingDistances[modelID] = nil
            definedProperties[strID]    = nil
            timeIDs[strID]              = nil
            if clearModelStreamTime then
                clearModelStreamTime(modelID)
                clearModelStreamTime(strID)
            end
        end
    end

    -- 4. Free all models assigned to this resource.
    if resourceModels[name] then
        for ID in pairs(resourceModels[name]) do
            engineFreeModel(ID)
        end
    end

    -- 5. Destroy cached asset handles (TXD/COL/DFF).
    for _, v in pairs(globalCache[name] or {}) do
        if isElement(v) then destroyElement(v) end
    end
    globalCache[name] = nil

    resource[name]        = nil
    resourceModels[name]  = nil
    resourceLoaded[name]  = nil

    -- 6. If no maps remain loaded, the SA model-ID pool can be reused.
    if resetSAModelPool and next(resource) == nil then
        resetSAModelPool()
    end

    outputDebugString2(string.format("Successfully unloaded map definitions for resource: %s", name))
end

addEvent("resourceStop", true)
addEventHandler("resourceStop", resourceRoot, unloadMapDefinitions)

addEventHandler("onClientResourceStop", getRootElement(),
    function(stoppedRes)
        if unloadResourceIMGs then
            unloadResourceIMGs(getResourceName(stoppedRes))
        end
    end
)

-- =========================
-- Event Handling & Streaming
-- =========================

function loadedFunction(resourceName)
    if not startTickCount or type(startTickCount) ~= "number" then
        outputDebugString2("Error: startTickCount is invalid or not set.")
        return
    end
    local endTickCount = getTickCount() - startTickCount
    if isElement(resourceRoot) then
        triggerServerEvent("onPlayerLoad", resourceRoot, tostring(endTickCount), resourceName)
    else
        outputDebugString2("Error: resourceRoot is invalid or not available.")
    end
    createTrayNotification(string.format("You have finished loading: %s", resourceName), "info")
end

function loaded(resourceName)
    loadedFunction(resourceName)
    initializeObjects()
    engineRestreamWorld()
    writeDebugFile()
    removeWorldMapConfirm()
    spawnNextObject()
    setTimer(removeWorldMapConfirm, 1000, 5)
end

function getMaps()
    local tempTable = {}
    for name in pairs(resource) do
        table.insert(tempTable, name)
    end
    return tempTable
end
