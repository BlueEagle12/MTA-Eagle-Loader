-- ========================================
-- Global Asset/Model Cache Tables
-- ========================================
globalCache = {}
idCache     = {}
useLODs     = {}
reverseID   = {}

-- ========================================
-- Model ID Request (unique per logical key)
-- ========================================
function requestModelID(modelID)
    if not modelID then return false end

    local cachedID = tonumber(idCache[modelID])
    if cachedID then
        return cachedID
    end

    local newID = engineRequestModel('object')
    if tonumber(newID) and newID <= 19999 then
        idCache[modelID] = newID
        reverseID[newID] = modelID
        return newID, true
    elseif tonumber(newID) then
        -- Allocated an ID outside the usable range; free it so the slot
        -- isn't leaked before we fall back to the SA pool.
        engineFreeModel(newID)
    end

    -- Fallback: allocate from SA pool if configured
    if allocateDefaultIDs then
        newID = engineRequestSAModel('object')
        if newID then
            idCache[modelID] = newID
            reverseID[newID] = modelID
            return newID, true
        end
    end

    return false
end

-- ========================================
-- Generic Asset Loader (with per-resource cache)
-- ========================================
local function requestAsset(path, resourceName, loadFunc)
    if not (path and resourceName and loadFunc) then return false end

    globalCache[resourceName] = globalCache[resourceName] or {}

    if not isElement(globalCache[resourceName][path]) and fileExists(path) then
        globalCache[resourceName][path] = loadFunc(path)
    end

    return globalCache[resourceName][path] or false
end

-- ========================================
-- Specialized Asset Requests
-- ========================================
function requestTextureArchive(path, resourceName)
    return requestAsset(path, resourceName, engineLoadTXD)
end

function requestCollision(path, resourceName)
    return requestAsset(path, resourceName, engineLoadCOL)
end

function requestModel(path, resourceName)
    return requestAsset(path, resourceName, engineLoadDFF)
end

-- ========================================
-- Release all cached assets for a given resource
-- ========================================
function releaseCache(resourceName)
    if not resourceName or not globalCache[resourceName] then return false end
    globalCache[resourceName] = nil
    return true
end
