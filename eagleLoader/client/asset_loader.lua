-- =========================
-- Resource Management State
-- =========================
resourceElements    = {}
resourceModels      = {}
resourceImages      = {}
imageFiles          = {}
imageFilePaths      = {}
streamingDistances  = {}
definitionZones     = {}
timeIDs             = {}
itemIDList          = {}
itemIDListUnique    = {}
lodParents          = {}
uniqueIDs           = {}
textureIDs          = {}
textureLinkedImages = {}
definedProperties   = {}
mapElements         = {}   -- per-resource list of created world elements (for cleanup on unload)
resourceDefinitions = {}
modelOverrides      = {}
definitionPhysicsOverrides = {}
resourceDefinitionPhysicsOverrides = {}
resourceDefinedProperties = {}
mapLoadGenerations  = {}   -- invalidates queued Async work when a map stops
mapLoadStartTicks   = {}
unloadingResources  = {}
imgLinkedDFFModels  = {}   -- resource -> model IDs linked with engineImageLinkDFF
requestedTXDModels  = {}   -- resource -> model IDs assigned with engineSetModelTXDID
nativeModelOwners   = {}   -- stock model ID -> owning resource/logical definition
modelOverrideOwners = {}   -- stock override ID -> owning resource
local restoreIMGModelLinks

-- Element destruction reaches Lua immediately, but the GTA renderer can keep
-- native streaming references until a later frame. Delay IMG/model teardown so
-- those references are released before their backing assets are restored.
EAGLE_UNLOAD_DELAY_MS = 100

function eagleLoaderStopTrace(resourceName, phase)
    triggerServerEvent("eagleLoader:stopTrace", resourceRoot, resourceName, phase)
end

-- Optionally increase streaming memory on nightly builds
if engineStreamingSetMemorySize then
    engineStreamingSetMemorySize(streamingMemoryAllocation * 1024 * 1024)
    engineStreamingSetBufferSize(streamingBufferAllocation * 1024 * 1024)
end

-- =========================
-- Asset Loading / Streaming
-- =========================

local function findFile(assetName, assetType, resourceName, zone)

    local assetPath = zone and string.format(":%s/zones/%s/%s/%s.%s", resourceName, zone, assetType, assetName, assetType)

    local assetPathTexture = assetType == "txd"
        and string.format(":%s/textures/%s.txd", resourceName, assetName)
    if assetPath and fileExists(assetPath) then
        return assetPath
    elseif assetPathTexture and fileExists(assetPathTexture) then
        return assetPathTexture
    end
end

local function normalizeAssetName(assetName, assetType)
    if type(assetName) ~= "string" then return assetName end

    assetName = assetName:gsub("^%s*(.-)%s*$", "%1")
    return assetName:gsub("%." .. assetType .. "$", "")
end

local function requestTextureID(assetName, img, path, resourceName)
    local cacheKey = tostring(resourceName) .. "\0" .. tostring(assetName)
    if not textureIDs[cacheKey] then
        textureIDs[cacheKey] = engineRequestTXD(assetName)
    end
    if not textureIDs[cacheKey] then
        return false
    end
    if textureLinkedImages[cacheKey] ~= img then
        if not engineImageLinkTXD(img, path, textureIDs[cacheKey]) then
            return false
        end
        textureLinkedImages[cacheKey] = img
    end
    return textureIDs[cacheKey]
end

-- Some 1.6 client builds can allocate custom object IDs above 19999, while a
-- few of the newer IMG/TXD helper functions still validate against the old SA
-- model range.  Use the traditional TXD import path when that happens so one
-- unsupported helper call cannot abort the complete asynchronous map load.
local function importIMGTextureFallback(assetName, img, assetPath, resourceName, modelID)
    globalCache[resourceName] = globalCache[resourceName] or {}
    local cacheKey = "img-txd:" .. tostring(assetName)
    local txd = globalCache[resourceName][cacheKey]

    if not isElement(txd) then
        local asset = engineImageGetFile(img, assetPath)
        txd = asset and engineLoadTXD(asset)
        if isElement(txd) then
            globalCache[resourceName][cacheKey] = txd
        end
    end

    if not isElement(txd) then return false end

    local ok, result = pcall(engineImportTXD, txd, modelID)
    return ok and result == true
end

local function loadImgAsset(assetType, assetName, resourceName, modelID, img, assetPath)
    if not assetName then return end
    assetName = normalizeAssetName(assetName, assetType)
    if not img then
        img, assetPath = getIMGAsset(assetName, assetType, resourceName)
    end
    if not img then return end

    if assetType == "txd" then
        local tID = requestTextureID(assetName, img, assetPath, resourceName)
        local assigned = false
        if tID and engineSetModelTXDID then
            local ok, result = pcall(engineSetModelTXDID, modelID, tID)
            assigned = ok and result == true
        end

        if assigned then
            requestedTXDModels[resourceName] = requestedTXDModels[resourceName] or {}
            requestedTXDModels[resourceName][modelID] = true
        elseif not importIMGTextureFallback(assetName, img, assetPath, resourceName, modelID) then
            outputDebugString2(string.format(
                "TXD: %s could not be assigned to model %s using either TXD-ID or import mode!",
                tostring(assetPath), tostring(modelID)
            ), 2)
            return false
        end
    elseif assetType == "col" then
        local asset = engineImageGetFile(img, assetPath)
        local col = asset and engineLoadCOL(asset)
        if not col or not engineReplaceCOL(col, modelID) then
            outputDebugString2(string.format("COL: %s could not be loaded or replaced from IMG! : %s", assetPath, tostring(modelID)), 2)
            return false
        end
    elseif assetType == "dff" then
        if engineImageLinkDFF(img, assetPath, modelID) then
            imgLinkedDFFModels[resourceName] = imgLinkedDFFModels[resourceName] or {}
            imgLinkedDFFModels[resourceName][modelID] = true
            return true
        end

        local asset = engineImageGetFile(img, assetPath)
        local dff = asset and engineLoadDFF(asset)
        if not dff or not engineReplaceModel(dff, modelID, false) then
            outputDebugString2(string.format("DFF: %s could not be linked or replaced from IMG! : %s", assetPath, tostring(modelID)), 2)
            return false
        end
    end
    return true
end

local function loadAsset(assetType, assetName, resourceName, zone, modelID, alpha, assetPath)
    if not assetName then return end
    assetName = normalizeAssetName(assetName, assetType)
    assetPath = assetPath or findFile(assetName, assetType, resourceName, zone)
    if not assetPath then
        outputDebugString2(string.format("%s: %s could not be found!", assetType:upper(), assetName.."."..assetType))
        return
    end

    local loaderFunc =
        (assetType == "txd" and requestTextureArchive) or
        (assetType == "col" and requestCollision) or
        (assetType == "dff" and requestModel)

    -- Cache by owning map resource. Caching by asset name leaked handles across
    -- map unloads and prevented reliable reuse when several models shared a TXD.
    local asset = loaderFunc(assetPath, resourceName)
    if not asset then
        outputDebugString2(string.format("%s: %s could not be loaded!", assetType:upper(), assetName))
        return
    end

    if assetType == "txd" then
        if not engineImportTXD(asset, modelID) then return false end
    elseif assetType == "col" then
        if not engineReplaceCOL(asset, modelID) then return false end
    elseif assetType == "dff" then
        local dff = engineReplaceModel(asset, modelID, alpha or false)
        if not dff then
            outputDebugString2(string.format("%s: %s could not be replaced! : %s", assetType:upper(), assetName, modelID))
            return
        end
    end
    return true
end

local function tryLoadAsset(assetType, fileName, resourceName, zone, modelID, ...)
    if not fileName then return end
    fileName = normalizeAssetName(fileName, assetType)
    local img, imgPath = getIMGAsset(fileName, assetType, resourceName)
    if img then
        return loadImgAsset(assetType, fileName, resourceName, modelID, img, imgPath)
    end

    local assetPath = findFile(fileName, assetType, resourceName, zone)
    if assetPath then
        local alpha = ...
        return loadAsset(assetType, fileName, resourceName, zone, modelID, alpha, assetPath)
    end
end

local function tryLoadDefinitionDFF(data, resourceName, zone, modelID, alpha)
    local names = {}
    local seen = {}

    local function addName(name)
        name = normalizeAssetName(name, 'dff')
        if name and name ~= "" and not seen[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end

    addName(data.dff)
    addName(data.id)

    for _, name in ipairs(names) do
        if tryLoadAsset('dff', name, resourceName, zone, modelID, alpha) then
            return true
        end
    end
end

local function isEnabledAttribute(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) ~= "string" then return false end
    value = value:gsub("^%s*(.-)%s*$", "%1"):lower()
    return value == "true" or value == "1" or value == "yes" or value == "on"
end

local function hasCollisionDisabled(data)
    return data and (
        isEnabledAttribute(data.disable_collisions)
        or isEnabledAttribute(data.collisions_disabled)
    )
end

local function usesAlphaTransparency(data)
    return isEnabledAttribute(data.draw_last) or isEnabledAttribute(data.additive)
end

local function optionalAssetName(assetName)
    if type(assetName) == "string" then
        assetName = assetName:gsub("^%s*(.-)%s*$", "%1")
        if assetName == "" or assetName == "nil" then
            return nil
        end
    end
    return assetName
end

local function resolveSAModelID(id)
    if id == nil then return nil end
    local key = tostring(id):gsub("^%s*(.-)%s*$", "%1")
    return tonumber(key) or defaultIDs[key]
end

local function definitionNativeModel(data)
    if not data then return nil end
    return data.nativeModel
        or data.nativeModelID
        or data.native_model
        or data.native_model_id
end

-- GTA implements a few object behaviours by comparing the entity's model ID
-- against a hard-coded stock-ID list. A dynamically allocated custom model can
-- copy a stock model's data, but it still does not pass those comparisons.
--
-- `nativeModel` deliberately aliases a logical Eagle ID to one stock SA model
-- slot so its replacement DFF receives that native behaviour. This is useful
-- for traffic lights and similarly hard-coded objects. Only one loaded logical
-- definition may own a native slot at a time.
local function requestDefinitionModelID(resourceName, data)
    local nativeValue = definitionNativeModel(data)
    if nativeValue == nil then
        return requestModelID(data.id, resourceName)
    end

    local modelID = resolveSAModelID(nativeValue)
    if not modelID or not isSAModelID(modelID) then
        outputDebugString2(string.format(
            "Definition %s has invalid nativeModel %s; expected a stock GTA:SA object model.",
            tostring(data.id),
            tostring(nativeValue)
        ), 2)
        return false
    end

    resourceIDCache[resourceName] = resourceIDCache[resourceName] or {}
    local cachedID = tonumber(resourceIDCache[resourceName][data.id])
    if cachedID and cachedID ~= modelID then
        outputDebugString2(string.format(
            "Definition %s is already assigned to model %s and cannot alias native model %s.",
            tostring(data.id),
            tostring(cachedID),
            tostring(modelID)
        ), 2)
        return false
    end

    local existingOwner = nativeModelOwners[modelID]
    if existingOwner
        and (existingOwner.resourceName ~= resourceName or existingOwner.logicalID ~= data.id)
    then
        outputDebugString2(string.format(
            "Native model %s is already owned by %s/%s; cannot also assign %s/%s.",
            tostring(modelID),
            tostring(existingOwner.resourceName),
            tostring(existingOwner.logicalID),
            tostring(resourceName),
            tostring(data.id)
        ), 2)
        return false
    end
    local existingLogicalID = reverseID[modelID]
    if existingLogicalID and existingLogicalID ~= data.id then
        outputDebugString2(string.format(
            "Native model %s is already assigned to logical model %s; cannot also assign %s/%s.",
            tostring(modelID), tostring(existingLogicalID), tostring(resourceName), tostring(data.id)
        ), 2)
        return false
    end
    if modelOverrideOwners[modelID] then
        outputDebugString2(string.format(
            "Native model %s is currently overridden by %s.",
            tostring(modelID), tostring(modelOverrideOwners[modelID])
        ), 2)
        return false
    end

    resourceIDCache[resourceName][data.id] = modelID
    idCache[data.id] = idCache[data.id] or modelID
    reverseID[modelID] = data.id
    nativeModelOwners[modelID] = {
        resourceName = resourceName,
        logicalID = data.id
    }
    outputDebugString2(string.format(
        "Definition %s is using native behavior model %s.",
        tostring(data.id),
        tostring(modelID)
    ))
    return modelID, cachedID == nil, false
end

-- =========================
-- Map Definitions Loading
-- =========================
local function ensureResourceTables(resourceName)
    resourceModels[resourceName] = resourceModels[resourceName] or {}
    resourceElements[resourceName] = resourceElements[resourceName] or {}
end

local function registerDefinition(resourceName, data)
    if not (resourceName and data and data.id) then return end

    resourceDefinitions[resourceName] = resourceDefinitions[resourceName] or {}
    resourceDefinitions[resourceName][data.id] = data
    definitionZones[data.id] = data.zone
end

function registerMapDefinitions(resourceName, mapDefinitions)
    ensureResourceTables(resourceName)
    resourceDefinitions[resourceName] = {}
    prepIMGContainers(resourceName)

    for _, data in ipairs(mapDefinitions or {}) do
        registerDefinition(resourceName, data)
    end
end

local function applyModelSettings(resourceName, data, modelID, mirrorModelIDProperties)
    resourceDefinedProperties[resourceName] = resourceDefinedProperties[resourceName] or {}
    resourceDefinitionPhysicsOverrides[resourceName] = resourceDefinitionPhysicsOverrides[resourceName] or {}
    definedProperties[data.id] = definedProperties[data.id] or {}
    resourceDefinedProperties[resourceName][data.id] = resourceDefinedProperties[resourceName][data.id] or {}
    if mirrorModelIDProperties and data.id ~= modelID then
        definedProperties[modelID] = definedProperties[modelID] or {}
        resourceDefinedProperties[resourceName][modelID] = resourceDefinedProperties[resourceName][modelID] or {}
    end
    local zone        = data.zone
    local lodDistance = tonumber(data.lodDistance) or 200

    definitionZones[modelID] = zone
    definitionZones[data.id] = zone
    local physicsOverrides = getPhysicsOverrides(data)
    definitionPhysicsOverrides[data.id] = physicsOverrides
    resourceDefinitionPhysicsOverrides[resourceName][data.id] = physicsOverrides
    if mirrorModelIDProperties and data.id ~= modelID then
        definitionPhysicsOverrides[modelID] = physicsOverrides
        resourceDefinitionPhysicsOverrides[resourceName][modelID] = physicsOverrides
    end

    local finalDist = (highDefLODs or lodDistance < 10) and 700 or lodDistance
    finalDist = finalDist * drawDistanceMultiplier
    -- engineSetModelLODDistance still rejects extended custom IDs on affected
    -- clients. The model remains usable with its inherited/default distance.
    if modelID >= 0 and modelID <= 19999 then
        local ok = pcall(engineSetModelLODDistance, modelID, finalDist, true)
        if not ok then
            outputDebugString2(string.format(
                "Could not set LOD distance for model %s; using the engine default.",
                tostring(modelID)
            ), 2)
        end
    end
    streamingDistances[modelID] = finalDist

    for _, v in pairs(objectFlags) do
        if v.custom then
            if isEnabledAttribute(data[v.name]) then
                definedProperties[data.id][v.name] = v.value
                resourceDefinedProperties[resourceName][data.id][v.name] = v.value
                if mirrorModelIDProperties and data.id ~= modelID then
                    definedProperties[modelID][v.name] = v.value
                    resourceDefinedProperties[resourceName][modelID][v.name] = v.value
                end
            end
        else
            if isEnabledAttribute(data[v.name]) then
                local ok = pcall(engineSetModelFlag, modelID, v.name, true)
                if not ok then
                    outputDebugString2(string.format(
                        "Could not set model flag %s on model %s.",
                        tostring(v.name), tostring(modelID)
                    ), 2)
                end
            end
        end
    end

    local txdName = optionalAssetName(data.txd)
    if not txdName then
        return
    end

    local txdTable = splitString(txdName, ',')
    if txdTable then
        for _, txd in ipairs(txdTable) do
            tryLoadAsset('txd', txd, resourceName, zone, modelID)
        end
    else
        tryLoadAsset('txd', txdName, resourceName, zone, modelID)
    end
end

local function applySAModelOverride(resourceName, data)
    local modelID = resolveSAModelID(data.id)
    if not modelID then
        outputDebugString2(string.format("Skipping SA model override with invalid ID: %s", tostring(data.id)), 2)
        return false
    end

    local existingOwner = modelOverrideOwners[modelID]
    local existingOverrideID = modelOverrides[resourceName] and modelOverrides[resourceName][modelID]
    if existingOwner
        and (existingOwner ~= resourceName or existingOverrideID ~= data.id)
    then
        outputDebugString2(string.format(
            "Skipping SA model override %s from %s because it is already owned by %s.",
            tostring(modelID), tostring(resourceName), tostring(existingOwner)
        ), 2)
        return false
    end
    if nativeModelOwners[modelID] then
        outputDebugString2(string.format(
            "Skipping SA model override %s from %s because it is a nativeModel slot owned by %s.",
            tostring(modelID), tostring(resourceName), tostring(nativeModelOwners[modelID].resourceName)
        ), 2)
        return false
    end
    if reverseID[modelID] and not nativeModelOwners[modelID] then
        outputDebugString2(string.format(
            "Skipping SA model override %s from %s because that model ID is allocated to %s.",
            tostring(modelID), tostring(resourceName), tostring(reverseID[modelID])
        ), 2)
        return false
    end

    ensureResourceTables(resourceName)
    modelOverrideOwners[modelID] = resourceName
    modelOverrides[resourceName] = modelOverrides[resourceName] or {}
    modelOverrides[resourceName][modelID] = data.id

    applyModelSettings(resourceName, data, modelID, true)

    local colName = optionalAssetName(data.col)
    if colName then
        tryLoadAsset('col', colName, resourceName, data.zone, modelID)
    end

    if optionalAssetName(data.dff) then
        tryLoadDefinitionDFF(data, resourceName, data.zone, modelID, usesAlphaTransparency(data))
    end

    if data.timeIn then
        timeIDs[data.id] = { tonumber(data.timeIn), tonumber(data.timeOut) }
        setModelStreamTime(modelID, data.id, tonumber(data.timeIn), tonumber(data.timeOut))
    end

    return modelID
end

local function applyMapDefinition(resourceName, data)
    if not (resourceName and data and data.id) then return false end
    if data.definitionType == "override" then
        return applySAModelOverride(resourceName, data)
    end

    ensureResourceTables(resourceName)

    local modelID, isNew, isEngineAllocated = requestDefinitionModelID(resourceName, data)
    if not tonumber(modelID) then
        outputDebugString2(string.format("Error: Failed to request model ID for object with ID: %s", tostring(data.id)))
        return false
    end

    if isNew then
        resourceModels[resourceName][modelID] = {
            engineAllocated = isEngineAllocated == true
        }
    end

    applyModelSettings(resourceName, data, modelID)

    local colName = optionalAssetName(data.col)
    local colLoaded = true
    if colName then
        colLoaded = tryLoadAsset('col', colName, resourceName, data.zone, modelID)
    elseif not hasCollisionDisabled(data)
        and (inIMGAsset(data.id, 'col', resourceName) or findFile(data.id, 'col', resourceName, data.zone))
    then
        colLoaded = tryLoadAsset('col', data.id, resourceName, data.zone, modelID)
    end
    local dffLoaded = tryLoadDefinitionDFF(data, resourceName, data.zone, modelID, usesAlphaTransparency(data))

    if not dffLoaded or not colLoaded then
        outputDebugString2(string.format(
            "Skipping model %s because required assets are missing or failed to load. dff=%s col=%s",
            tostring(data.id),
            tostring(dffLoaded),
            tostring(colLoaded)
        ), 2)

        if isNew and tonumber(modelID) then
            if isEngineAllocated and engineFreeModel then
                engineFreeModel(modelID)
            else
                if engineResetModelTXDID
                    and requestedTXDModels[resourceName]
                    and requestedTXDModels[resourceName][modelID]
                then
                    engineResetModelTXDID(modelID)
                    requestedTXDModels[resourceName][modelID] = nil
                end
                if restoreIMGModelLinks then restoreIMGModelLinks(resourceName, modelID) end
                if engineResetModelFlags then engineResetModelFlags(modelID) end
                if engineResetModelLODDistance then engineResetModelLODDistance(modelID) end
                if engineRestoreModel then engineRestoreModel(modelID) end
                if engineRestoreCOL then engineRestoreCOL(modelID) end
            end
            if resourceIDCache[resourceName] then
                resourceIDCache[resourceName][data.id] = nil
            end
            refreshSharedModelID(data.id, modelID)
            reverseID[modelID] = nil
            allocatedModelIDs[modelID] = nil
            resourceModels[resourceName][modelID] = nil
            if resourceDefinedProperties[resourceName] then
                resourceDefinedProperties[resourceName][data.id] = nil
            end
            if resourceDefinitionPhysicsOverrides[resourceName] then
                resourceDefinitionPhysicsOverrides[resourceName][data.id] = nil
            end
            if not idCache[data.id] then
                definedProperties[data.id] = nil
                definitionPhysicsOverrides[data.id] = nil
                definitionZones[data.id] = nil
            end
            definitionPhysicsOverrides[modelID] = nil
            nativeModelOwners[modelID] = nil
        end

        return false
    end

    if data.timeIn then
        timeIDs[data.id] = { tonumber(data.timeIn), tonumber(data.timeOut) }
        setModelStreamTime(modelID, data.id, tonumber(data.timeIn), tonumber(data.timeOut))
    end

    return modelID
end

function loadMapDefinitions(resourceName, mapDefinitions, last, onDefinitionsReady)
    -- Loading definitions is asynchronous.  Keep a generation token so a
    -- coroutine that yielded does not resume after this map has been stopped
    -- and recreate models/elements against already-freed state.
    mapLoadGenerations[resourceName] = (mapLoadGenerations[resourceName] or 0) + 1
    local loadGeneration = mapLoadGenerations[resourceName]

    resourceModels[resourceName] = {}
    resourceElements[resourceName] = {}
    resourceDefinitions[resourceName] = {}
    mapLoadStartTicks[resourceName] = mapLoadStartTicks[resourceName] or getTickCount()
    prepIMGContainers(resourceName)
    Async:setPriority("high")

    for _, data in ipairs(mapDefinitions or {}) do
        registerDefinition(resourceName, data)
    end

    local function initializeReadyObjects()
        if not onDefinitionsReady then return false end
        local ok, initialized = pcall(onDefinitionsReady)
        if not ok then
            outputDebugString2("Map placement initialization failed: " .. tostring(initialized), 1)
            return false
        end
        return initialized == true
    end

    if not last then
        loaded(resourceName, initializeReadyObjects())
        return
    end

    Async:foreach(mapDefinitions, function(data)
        if mapLoadGenerations[resourceName] ~= loadGeneration or not resourceElements[resourceName] then
            return
        end

        applyMapDefinition(resourceName, data)
    end, function()
        if mapLoadGenerations[resourceName] == loadGeneration and resourceElements[resourceName] then
            loaded(resourceName, initializeReadyObjects())
        end
    end, function(err)
        if mapLoadGenerations[resourceName] ~= loadGeneration then
            return
        end
        outputDebugString2(string.format(
            "Map definition load failed for %s: %s",
            tostring(resourceName), tostring(err)
        ), 1)
        if resourceLoaded then resourceLoaded[resourceName] = nil end
        unloadMapDefinitions(resourceName)
    end)
end

-- =========================
-- Unloading & Cleanup
-- =========================
local function safeNativeCleanup(label, cleanupFunction, ...)
    if not cleanupFunction then return false end

    local ok, result = pcall(cleanupFunction, ...)
    if not ok then
        outputDebugString("eagleLoader cleanup failed at " .. tostring(label) .. ": " .. tostring(result), 2)
        return false
    end
    return result
end

local function refreshSharedDefinitionMetadata(logicalID)
    definedProperties[logicalID] = nil
    definitionPhysicsOverrides[logicalID] = nil
    definitionZones[logicalID] = nil
    timeIDs[logicalID] = nil

    for resourceName, scopedCache in pairs(resourceIDCache) do
        if scopedCache[logicalID] then
            local definition = resourceDefinitions[resourceName]
                and resourceDefinitions[resourceName][logicalID]
            definedProperties[logicalID] = resourceDefinedProperties[resourceName]
                and resourceDefinedProperties[resourceName][logicalID]
                or nil
            definitionPhysicsOverrides[logicalID] = resourceDefinitionPhysicsOverrides[resourceName]
                and resourceDefinitionPhysicsOverrides[resourceName][logicalID]
                or nil
            definitionZones[logicalID] = definition and definition.zone or nil
            if definition and definition.timeIn then
                timeIDs[logicalID] = { tonumber(definition.timeIn), tonumber(definition.timeOut) }
                setModelStreamTime(
                    scopedCache[logicalID],
                    logicalID,
                    tonumber(definition.timeIn),
                    tonumber(definition.timeOut)
                )
            end
            return
        end
    end
end

restoreIMGModelLinks = function(resourceName, modelID)
    -- engineImageLinkDFF/TXD installs a streaming link that belongs to the
    -- IMG container, not to the Lua DFF/TXD element.  Remove that link before
    -- freeing the model or removing the IMG; otherwise the IMG streamer can
    -- retain a dead model pointer during a resource stop.
    if engineRestoreDFFImage and imgLinkedDFFModels[resourceName] and imgLinkedDFFModels[resourceName][modelID] then
        eagleLoaderStopTrace(resourceName, "model-" .. tostring(modelID) .. "-restore-dff-img")
        safeNativeCleanup("restore DFF IMG for model " .. tostring(modelID), engineRestoreDFFImage, modelID)
        imgLinkedDFFModels[resourceName][modelID] = nil
    end
end

local function freeRequestedTXDs()
    if not engineFreeTXD then return end

    local freed = {}
    for _, txdID in pairs(textureIDs or {}) do
        if txdID and not freed[txdID] then
            -- This client build expects the requested TXD ID (0-4999), not a
            -- model ID, despite older documentation naming the argument
            -- modelID. Passing Monaco's model 5091 aborted the whole unload.
            if engineRestoreTXDImage then
                safeNativeCleanup("restore TXD IMG " .. tostring(txdID), engineRestoreTXDImage, txdID)
            end
            safeNativeCleanup("free TXD " .. tostring(txdID), engineFreeTXD, txdID)
            freed[txdID] = true
        end
    end
    textureIDs = {}
    textureLinkedImages = {}
end

function unloadMapDefinitions(name, onComplete)
    if not name then return end
    eagleLoaderStopTrace(name, "unload-begin")

    -- Invalidate a possibly-yielded Async:foreach before releasing anything.
    mapLoadGenerations[name] = (mapLoadGenerations[name] or 0) + 1

    if unloadingResources[name] then return false end
    if not (resourceElements[name] or mapElements[name] or resourceLoaded[name]) then
        if onComplete then onComplete() end
        return false
    end
    unloadingResources[name] = true

    -- 1. Destroy the world elements (objects/buildings) created for this map.
    --    This MUST happen before idCache is cleared below, so onElementDestroy
    --    can still resolve each element and tear down its LOD + tracking-table
    --    entries (lodParents, uniqueIDs, selfLODList, itemIDList, ...).
    local elements = mapElements[name] or {}
    for i = #elements, 1, -1 do
        local el = elements[i]
        if isElement(el) then destroyElement(el) end
    end
    eagleLoaderStopTrace(name, "map-elements-destroyed")

    -- self LODs are created after the map rows have been streamed and are not
    -- in mapElements.  Freeing a model while one of those elements still uses
    -- it can crash the client in native streaming code.  Sweep by ownership as
    -- a final guard for self LODs and any other map-owned object missed above.
    for _, elementType in ipairs({ "object", "building" }) do
        for _, el in ipairs(getElementsByType(elementType)) do
            if eagleElementOwners and eagleElementOwners[el] == name then
                destroyElement(el)
            end
        end
    end
    eagleLoaderStopTrace(name, "owned-elements-destroyed")
    mapElements[name] = nil
    if lodIDsByResource then lodIDsByResource[name] = nil end

    -- 2. Destroy water planes registered for this resource.
    for _, el in ipairs(resourceElements[name] or {}) do
        if isElement(el) then destroyElement(el) end
    end
    eagleLoaderStopTrace(name, "water-destroyed")

    -- Ask the streamer to process the now-empty world before native model and
    -- IMG state is touched. The remaining cleanup continues after the delay.
    engineRestreamWorld()
    eagleLoaderStopTrace(name, "native-cleanup-delayed")

    setTimer(function()
        eagleLoaderStopTrace(name, "native-cleanup-begin")

        if restorePhysicsModelGroupsForResource then
            restorePhysicsModelGroupsForResource(name)
        end

        -- 3. Clear id<->model mappings and the per-id / per-model metadata that
        --    would otherwise grow every time a map is loaded.
        for modelID, strID in pairs(reverseID) do
            if resourceModels[name] and resourceModels[name][modelID] then
                if resourceIDCache[name] then
                    resourceIDCache[name][strID] = nil
                end
                refreshSharedModelID(strID, modelID)
                reverseID[modelID]          = nil
                definitionZones[modelID]    = nil
                definitionZones[strID]      = nil
                streamingDistances[modelID] = nil
                definitionPhysicsOverrides[modelID] = nil
                textureLinkedImages[strID]  = nil
                timeIDs[strID]              = nil
                if clearModelStreamTime then
                    clearModelStreamTime(modelID)
                    clearModelStreamTime(strID)
                end
                refreshSharedDefinitionMetadata(strID)
            end
        end

        -- 4. Free all models assigned to this resource.
        if resourceModels[name] then
            for ID, allocation in pairs(resourceModels[name]) do
                if engineResetModelTXDID and requestedTXDModels[name] and requestedTXDModels[name][ID] then
                    eagleLoaderStopTrace(name, "model-" .. tostring(ID) .. "-reset-txd-id")
                    safeNativeCleanup("reset TXD ID for model " .. tostring(ID), engineResetModelTXDID, ID)
                    requestedTXDModels[name][ID] = nil
                end
                if engineResetModelFlags then
                    safeNativeCleanup("reset model flags " .. tostring(ID), engineResetModelFlags, ID)
                end
                if engineResetModelLODDistance then
                    safeNativeCleanup("reset model LOD distance " .. tostring(ID), engineResetModelLODDistance, ID)
                end
                if allocation.engineAllocated then
                    -- engineFreeModel owns teardown of models returned by
                    -- engineRequestModel. Restoring an IMG DFF link first can
                    -- make MTA's streamer dereference that custom allocation
                    -- while it is being released (core.dll access violation).
                    eagleLoaderStopTrace(name, "model-" .. tostring(ID) .. "-free-with-img-link")
                    eagleLoaderStopTrace(name, "model-" .. tostring(ID) .. "-free")
                    safeNativeCleanup("free model " .. tostring(ID), engineFreeModel, ID)
                else
                    eagleLoaderStopTrace(name, "model-" .. tostring(ID) .. "-restore-img-links")
                    restoreIMGModelLinks(name, ID)
                    -- IDs from the real SA object list are restored, never
                    -- freed. Other IDs allocated by engineRequestModel are
                    -- released based on their recorded provenance above.
                    if engineRestoreModel then
                        eagleLoaderStopTrace(name, "model-" .. tostring(ID) .. "-restore-dff")
                        safeNativeCleanup("restore model " .. tostring(ID), engineRestoreModel, ID)
                    end
                    if engineRestoreCOL then
                        eagleLoaderStopTrace(name, "model-" .. tostring(ID) .. "-restore-col")
                        safeNativeCleanup("restore COL " .. tostring(ID), engineRestoreCOL, ID)
                    end
                end
                allocatedModelIDs[ID] = nil
                if nativeModelOwners[ID] and nativeModelOwners[ID].resourceName == name then
                    nativeModelOwners[ID] = nil
                end
            end
        end
        eagleLoaderStopTrace(name, "models-unloaded")

        -- 5. Restore any GTA:SA models touched by <override> entries.
        for ID, strID in pairs(modelOverrides[name] or {}) do
            if engineResetModelTXDID and requestedTXDModels[name] and requestedTXDModels[name][ID] then
                eagleLoaderStopTrace(name, "override-" .. tostring(ID) .. "-reset-txd-id")
                safeNativeCleanup("reset override TXD ID " .. tostring(ID), engineResetModelTXDID, ID)
                requestedTXDModels[name][ID] = nil
            end
            eagleLoaderStopTrace(name, "override-" .. tostring(ID) .. "-restore-img-links")
            restoreIMGModelLinks(name, ID)
            if engineResetModelFlags then safeNativeCleanup("reset override flags " .. tostring(ID), engineResetModelFlags, ID) end
            if engineResetModelLODDistance then safeNativeCleanup("reset override LOD distance " .. tostring(ID), engineResetModelLODDistance, ID) end
            if engineRestoreModel then safeNativeCleanup("restore override model " .. tostring(ID), engineRestoreModel, ID) end
            if engineRestoreCOL then safeNativeCleanup("restore override COL " .. tostring(ID), engineRestoreCOL, ID) end
            definitionZones[ID] = nil
            definitionZones[strID] = nil
            streamingDistances[ID] = nil
            definedProperties[ID] = nil
            definedProperties[strID] = nil
            definitionPhysicsOverrides[ID] = nil
            definitionPhysicsOverrides[strID] = nil
            textureLinkedImages[strID] = nil
            timeIDs[strID] = nil
            if clearModelStreamTime then
                clearModelStreamTime(ID)
                clearModelStreamTime(strID)
            end
            modelOverrideOwners[ID] = nil
        end
        eagleLoaderStopTrace(name, "overrides-restored")
        modelOverrides[name] = nil
        imgLinkedDFFModels[name] = nil
        requestedTXDModels[name] = nil

        -- 6. Destroy cached asset handles (TXD/COL/DFF).
        for _, v in pairs(globalCache[name] or {}) do
            if isElement(v) then destroyElement(v) end
        end
        eagleLoaderStopTrace(name, "asset-elements-destroyed")
        globalCache[name] = nil

        resourceElements[name] = nil
        resourceModels[name]  = nil
        resourceDefinitions[name] = nil
        resourceDefinedProperties[name] = nil
        resourceDefinitionPhysicsOverrides[name] = nil
        resourceIDCache[name] = nil
        resourceLoaded[name]  = nil
        mapLoadStartTicks[name] = nil

        -- 7. If no maps remain loaded, the SA model-ID pool can be reused.
        if resetSAModelPool and next(resourceElements) == nil then
            resetSAModelPool()
            -- Requested TXDs are shared by asset name while maps are active.
            -- Once the last map is gone no model should reference them, so free
            -- them before eagleLoader itself can be stopped or restarted.
            freeRequestedTXDs()
        end

        outputDebugString2(string.format("Successfully unloaded map definitions for resource: %s", name))
        unloadingResources[name] = nil
        if onComplete then onComplete() end
    end, EAGLE_UNLOAD_DELAY_MS, 1)

    return true
end

local function unloadMapResource(name)
    unloadMapDefinitions(name, function()
        if unloadResourceIMGs then
            unloadResourceIMGs(name)
        end
    end)
end

addEvent("resourceStop", true)
addEventHandler("resourceStop", resourceRoot, unloadMapResource)

addEventHandler("onClientResourceStop", getRootElement(),
    function(stoppedRes)
        -- Do not manually tear down eagleLoader-owned native resources while
        -- eagleLoader itself is stopping. MTA is already destroying those
        -- elements/IMG handles as part of this resource stop; doing both paths
        -- causes a double teardown in the native streaming layer.
        if stoppedRes == getThisResource() then
            -- Never perform bulk native/world teardown from the resource-stop
            -- event. It fires both for an intentional loader stop and while a
            -- client disconnects, and a server-side prepare event cannot arrive
            -- before the client resource has already begun stopping. Normal map
            -- unload owns all explicit model/TXD/IMG cleanup while this resource
            -- is still running; MTA owns final resource/session destruction.
            outputDebugString("eagleLoader: lightweight resource shutdown", 3)
            return
        end

        -- Map resources are cleaned by the server-side onResourceStop signal,
        -- while their files are still available. Do not repeat native IMG/model
        -- calls during the local resource teardown.
    end
)

-- =========================
-- Event Handling & Streaming
-- =========================

function loadedFunction(resourceName)
    local startTick = mapLoadStartTicks[resourceName]
    if not startTick or type(startTick) ~= "number" then
        outputDebugString2("Error: map load start tick is invalid or not set.")
        return
    end
    local endTickCount = getTickCount() - startTick
    mapLoadStartTicks[resourceName] = nil
    if isElement(resourceRoot) then
        triggerServerEvent("onPlayerLoad", resourceRoot, tostring(endTickCount), resourceName)
    else
        outputDebugString2("Error: resourceRoot is invalid or not available.")
    end
    createTrayNotification(string.format("You have finished loading: %s", resourceName), "info")
end

function loaded(resourceName, objectsInitialized)
    if not objectsInitialized then
        initializeObjects(resourceName)
    end
    engineRestreamWorld()
    writeDebugFile()
    spawnNextObject()
    loadedFunction(resourceName)
end

function getMaps()
    local tempTable = {}
    for name in pairs(resourceElements) do
        table.insert(tempTable, name)
    end
    return tempTable
end
