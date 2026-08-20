-- Deterministic bluff map-load test for Eagle Loader's client asset lifecycle.
-- Run from the repository root with: lua tests/bluff_map_load.lua

local clock = 0
local timers = {}
local handlers = {}
local nextElementID = 0
local nextModelID = 21000
local nextTXDID = 100
local activeTXDs = {}
local elements = {}
local traces = {}
local streamingMemorySize = 256 * 1024 * 1024
local streamingBufferSize = 64 * 1024 * 1024

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function countEntries(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

local function newElement(elementType)
    nextElementID = nextElementID + 1
    local element = { alive = true, elementType = elementType, testID = nextElementID }
    elements[element] = true
    return element
end

local function advance(milliseconds)
    clock = clock + milliseconds
    local ran
    repeat
        ran = false
        for index = 1, #timers do
            local timer = timers[index]
            if timer.due <= clock then
                table.remove(timers, index)
                timer.callback(unpack(timer.args))
                ran = true
                break
            end
        end
    until not ran
end

root = newElement("root")
resourceRoot = newElement("resource-root")
local loaderResource = newElement("resource")
resourceLoaded = {}
lodIDsByResource = {}
eagleElementOwners = setmetatable({}, { __mode = "k" })
objectFlags = {}
defaultIDs = {}
saObjectIDSet = {}
saPhysicsObjectIDSet = {}
allocateDefaultIDs = false
capAt19999 = false
highDefLODs = false
drawDistanceMultiplier = 1
streamingMemoryAllocation = 512
streamingBufferAllocation = 150

function outputDebugString() end
function outputDebugString2() end
function triggerServerEvent(_, _, resourceName, phase)
    traces[#traces + 1] = tostring(resourceName) .. ":" .. tostring(phase)
end
function addEvent() end
function addEventHandler(eventName, _, callback)
    handlers[eventName] = handlers[eventName] or {}
    handlers[eventName][#handlers[eventName] + 1] = callback
end
function getRootElement() return root end
function getThisResource() return loaderResource end
function getTickCount() return clock end
function setTimer(callback, delay, _, ...)
    timers[#timers + 1] = { due = clock + delay, callback = callback, args = { ... } }
    return timers[#timers]
end
function isElement(element) return type(element) == "table" and element.alive == true end
function destroyElement(element)
    if isElement(element) then element.alive = false end
    return true
end
function getElementType(element) return element and element.elementType end
function getElementsByType(elementType)
    local result = {}
    for element in pairs(elements) do
        if isElement(element) and element.elementType == elementType then
            result[#result + 1] = element
        end
    end
    return result
end
function fileExists() return false end
function splitString() return false end
function getPhysicsOverrides() return {} end
function setModelStreamTime() end
function clearModelStreamTime() end
function writeDebugFile() return true end
function spawnNextObject() end
function initializeObjects() end
function createTrayNotification() end
function resetSAModelPool() end
function restorePhysicsModelGroupsForResource() end

function engineStreamingGetMemorySize() return streamingMemorySize end
function engineStreamingSetMemorySize(value) streamingMemorySize = value end
function engineStreamingGetBufferSize() return streamingBufferSize end
function engineStreamingSetBufferSize(value) streamingBufferSize = value return true end
function engineRestreamWorld() return true end
function engineRequestModel()
    nextModelID = nextModelID + 1
    return nextModelID
end
function engineFreeModel(modelID) traces[#traces + 1] = "free-model:" .. modelID return true end
function engineResetModelFlags() return true end
function engineResetModelLODDistance() return true end
function engineSetModelLODDistance() return true end
function engineSetModelFlag() return true end
function engineRestoreModel() return true end
function engineRestoreCOL() return true end
function engineResetModelTXDID(modelID) traces[#traces + 1] = "reset-txd:" .. modelID return true end
function engineRestoreDFFImage() return true end

function engineRequestTXD()
    nextTXDID = nextTXDID + 1
    activeTXDs[nextTXDID] = true
    return nextTXDID
end
function engineImageLinkTXD() return true end
function engineSetModelTXDID() return true end
function engineRestoreTXDImage() return true end
function engineFreeTXD(txdID)
    assertEqual(activeTXDs[txdID], true, "free live TXD " .. tostring(txdID))
    activeTXDs[txdID] = nil
    traces[#traces + 1] = "free-txd:" .. txdID
    return true
end

function engineImageLinkDFF() return false end
function engineImageGetFile(_, path) return "mock-bytes:" .. tostring(path) end
function engineLoadDFF() return newElement("dff") end
function engineLoadCOL() return newElement("col") end
function engineLoadTXD() return newElement("txd") end
function engineReplaceModel() return true end
function engineReplaceCOL() return true end
function engineImportTXD() return true end

Async = { failNext = false }
function Async:setPriority() end
function Async:foreach(array, iterator, complete, failed, shouldCancel)
    for index, value in ipairs(array) do
        if shouldCancel and shouldCancel() then return end
        iterator(value, index)
        if self.failNext then
            self.failNext = false
            failed("injected bluff-load failure")
            return
        end
    end
    complete()
end

assert(loadfile("eagleLoader/client/cache_helper.lua"))()
assert(loadfile("eagleLoader/client/asset_loader.lua"))()

function prepIMGContainers(resourceName)
    local image = newElement("img")
    resourceImages[resourceName] = { archive = image }
    imageFiles[resourceName] = { ["shared.txd"] = image }
    imageFilePaths[resourceName] = { ["shared.txd"] = "shared.txd" }
end

function getIMGAsset(assetName, assetType, resourceName)
    local images = resourceImages[resourceName]
    if not images then return false end
    return images.archive, tostring(assetName) .. "." .. tostring(assetType)
end

function inIMGAsset(assetName, assetType, resourceName)
    return getIMGAsset(assetName, assetType, resourceName) and true or false
end

function unloadResourceIMGs(resourceName)
    for _, image in pairs(resourceImages[resourceName] or {}) do destroyElement(image) end
    resourceImages[resourceName] = nil
    imageFiles[resourceName] = nil
    imageFilePaths[resourceName] = nil
    traces[#traces + 1] = "remove-img:" .. resourceName
end

local function loadBluffMap(resourceName)
    resourceLoaded[resourceName] = true
    local definition = {
        id = "bluff-model",
        dff = "shared",
        col = "shared",
        txd = "shared",
        zone = "bluff",
        lodDistance = "200"
    }
    loadMapDefinitions(resourceName, { definition }, true, function()
        local placement = newElement("object")
        eagleElementOwners[placement] = resourceName
        mapElements[resourceName] = { placement }
        return true
    end)
end

local function stopBluffMap(resourceName)
    local callbacks = handlers.resourceStop or {}
    assertEqual(#callbacks, 1, "resourceStop handler count")
    callbacks[1](resourceName)
end

local function activeTXDCount() return countEntries(activeTXDs) end

-- Two maps deliberately use the same logical TXD name. Their requested slots
-- must remain resource-scoped and independently releasable.
loadBluffMap("mapA")
loadBluffMap("mapB")
assertEqual(activeTXDCount(), 2, "two resource-scoped TXDs")
assertEqual(countEntries(globalCache.mapA), 2, "mapA fallback DFF/COL handles")
assertEqual(countEntries(globalCache.mapB), 2, "mapB fallback DFF/COL handles")

stopBluffMap("mapA")
assertEqual(unloadingResources.mapA, true, "mapA immediate restart gate")
assertEqual(isElement(mapElements.mapB[1]), true, "mapB survives mapA stop")
advance(100)
assertEqual(resourceModels.mapA, nil, "mapA models removed after first delay")
assertEqual(globalCache.mapA, nil, "mapA fallback handles removed")
assertEqual(resourceImages.mapA, nil, "mapA IMG removed")
assertEqual(activeTXDCount(), 2, "mapA TXD retained for IMG de-stream delay")
assertEqual(unloadingResources.mapA, true, "mapA gate spans TXD delay")
advance(100)
assertEqual(activeTXDCount(), 1, "only mapA TXD released")
assertEqual(unloadingResources.mapA, nil, "mapA restart gate released")
assertEqual(resourceModels.mapB ~= nil, true, "mapB models remain")

-- A failed asynchronous load must use the full IMG/TXD teardown path rather
-- than leaving native handles until the external map resource stops.
Async.failNext = true
resourceLoaded.mapC = true
loadMapDefinitions("mapC", {{
    id = "failed-model", dff = "shared", col = "shared", txd = "shared", zone = "bluff"
}}, true, function() return true end)
assertEqual(unloadingResources.mapC, true, "failed map enters cleanup")
advance(100)
assertEqual(resourceImages.mapC, nil, "failed map IMG removed")
advance(100)
assertEqual(resourceTextureIDs.mapC, nil, "failed map TXDs released")
assertEqual(activeTXDCount(), 1, "failed map returned to mapB baseline")

-- Rapid restart stays blocked across both native cleanup intervals.
stopBluffMap("mapB")
assertEqual(unloadingResources.mapB, true, "mapB immediate restart gate")
advance(100)
assertEqual(unloadingResources.mapB, true, "mapB gate after model cleanup")
advance(99)
assertEqual(unloadingResources.mapB, true, "mapB gate before TXD cleanup")
advance(1)
assertEqual(unloadingResources.mapB, nil, "mapB gate after TXD cleanup")
assertEqual(activeTXDCount(), 0, "all requested TXDs released")

-- Eagle Loader should return process-global streamer settings to the values
-- observed before it started, provided no other resource changed them later.
local stopCallbacks = handlers.onClientResourceStop or {}
assertEqual(#stopCallbacks, 1, "onClientResourceStop handler count")
stopCallbacks[1](loaderResource)
assertEqual(streamingMemorySize, 256 * 1024 * 1024, "streaming memory restored")
assertEqual(streamingBufferSize, 64 * 1024 * 1024, "streaming buffer restored")

print(string.format(
    "PASS bluff map lifecycle: %d trace events, %d active TXDs, %d pending timers",
    #traces,
    activeTXDCount(),
    #timers
))
