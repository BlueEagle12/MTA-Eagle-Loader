------------------------------
-- Model Time Streaming Logic
------------------------------

local timeTable     = {}
local streamTimes   = {}
local streamTimeObj = {}

-- Utility: Check if string equals "true"
local function isStringTrue(str)
    return str == "true"
end

-- Set streaming time for a model or by name
function setModelStreamTime(model, name, sIn, sOut)
    if model then streamTimes[model] = {sIn, sOut} end
    streamTimes[name] = {sIn, sOut}
end

-- Remove a stored streaming-time entry (called during map unload)
function clearModelStreamTime(key)
    if key ~= nil then streamTimes[key] = nil end
end

-- Returns true if the current time is between [start, end], wraps midnight
local function isTimeBetween(startHour, startMin, endHour, endMin)
    local curHour, curMin = getTime()
    local startMinTotal = startHour * 60 + startMin
    local endMinTotal   = endHour  * 60 + endMin
    local curMinTotal   = curHour  * 60 + curMin

    if startMinTotal <= endMinTotal then
        return curMinTotal >= startMinTotal and curMinTotal <= endMinTotal
    else
        return curMinTotal >= startMinTotal or curMinTotal <= endMinTotal
    end
end

-- Periodically checks all time-streamed objects and sets their visibility
setTimer(function()
    for obj in pairs(timeTable) do
        if not isElement(obj) then
            timeTable[obj] = nil
            streamTimeObj[obj] = nil
        else
            local model = getElementModel(obj)
            local tData = streamTimes[model]
            if tData then
                local sIn, sOut = tData[1], tData[2]
                if sIn and sOut then
                    local shouldStreamIn = isTimeBetween(sIn, 0, sOut, 0)
                    local state = streamTimeObj[obj]
                    if shouldStreamIn and state ~= 1 then
                        streamTimeObj[obj] = 1
                        setElementInterior(obj, 0)
                        setElementAlpha(obj, 1)
                    elseif not shouldStreamIn and state ~= 2 then
                        streamTimeObj[obj] = 2
                        setElementInterior(obj, 52)
                        setElementAlpha(obj, 0)
                    end
                end
            end
        end
    end
end, 500, 0)

-- Marks an element for time-based streaming if streamTimes exists for its id
function prepTime(element, id)
    timeTable[element] = streamTimes[id] and true or nil
end

------------------------------
-- Object Flags
------------------------------

local flagsTableNew = {}
objectFlags = {
    {bit = 0,  dec = 1,      hex = "0x1",        name = "is_road",                      description = "This model is a road."},
    {bit = 2,  dec = 4,      hex = "0x4",        name = "draw_last",                    description = "Model is transparent. Render after opaque objects."},
    {bit = 3,  dec = 8,      hex = "0x8",        name = "additive",                     description = "Render with additive blending."},
    {bit = 6,  dec = 64,     hex = "0x40",       name = "no_zbuffer_write",             description = "Disable writing to z-buffer."},
    {bit = 7,  dec = 128,    hex = "0x80",       name = "dont_receive_shadows",         description = "Do not draw shadows on this object."},
    {bit = 9,  dec = 512,    hex = "0x200",      name = "is_glass_type_1",              description = "Breakable glass type 1."},
    {bit = 10, dec = 1024,   hex = "0x400",      name = "is_glass_type_2",              description = "Breakable glass type 2."},
    {bit = 11, dec = 2048,   hex = "0x800",      name = "is_garage_door",               description = "Indicates a garage door."},
    {bit = 12, dec = 4096,   hex = "0x1000",     name = "is_damagable",                 description = "Model with ok/dam states."},
    {bit = 13, dec = 8192,   hex = "0x2000",     name = "is_tree",                      description = "Trees and some plants."},
    {bit = 14, dec = 16384,  hex = "0x4000",     name = "is_palm",                      description = "Palms."},
    {bit = 15, dec = 32768,  hex = "0x8000",     name = "does_not_collide_with_flyer",  description = "No collision with flyer."},
    {bit = 20, dec = 1048576,hex = "0x100000",   name = "is_tag",                       description = "This model is a tag."},
    {bit = 21, dec = 2097152,hex = "0x200000",   name = "disable_backface_culling",     description = "Disables backface culling."},
    {bit = 22, dec = 4194304,hex = "0x400000",   name = "is_breakable_statue",          description = "Statue not usable as cover."},
    {bit = 50, dec = 0,      hex = "0x000000",   name = "disable_collisions",           description = "Disable collisions.",    custom = true,  value = false}
}

for _, data in ipairs(objectFlags) do
    flagsTableNew[data.bit] = data.name
    flagsTableNew[data.name] = data.name
end

-- Split comma-separated flags into a table
local function splitFlags(flags)
    if type(flags) ~= "string" then return {} end
    local list = {}
    for value in string.gmatch(flags, "([^,]+)") do
        value = value:gsub("^%s*(.-)%s*$", "%1")
        table.insert(list, value)
    end
    return list
end

-- Add named flag keys to attribute table
function getFlags(attribute)
    for _, flag in ipairs(splitFlags(attribute.flags)) do
        local key = tonumber(flag) or flag
        if flagsTableNew[key] then
            attribute[flagsTableNew[key]] = true
        end
    end
end

------------------------------
-- IMG Asset Utilities
------------------------------

function findImg(assetType, resourceName)
    resourceImages[resourceName] = resourceImages[resourceName] or {}
    if not resourceImages[resourceName][assetType] then
        resourceImages[resourceName][assetType] = engineLoadIMG(string.format(":%s/imgs/%s.img", resourceName, assetType))
        engineAddImage(resourceImages[resourceName][assetType])
    end
    return resourceImages[resourceName][assetType], string.format(":%s/imgs/%s.img", resourceName, assetType)
end

function inIMGAsset(assetName, assetType, resourceName)
    local assetPath = string.format("%s.%s", assetName, assetType)
    if not imageFiles[resourceName] then return false end
    return imageFiles[resourceName][assetPath] and true or false
end

function prepIMGFiles(img, resourceName)
    local filesInArchive = engineImageGetFiles(img)
    for i = 1, #filesInArchive do
        imageFiles[resourceName][filesInArchive[i]] = img
    end
end

function prepIMGContainers(resourceName)
    imageFiles[resourceName] = {}
    for _, v in pairs(IMGNames) do
        for i = 0, maxIMG do
            local img

            if i == 0 then
                if fileExists(string.format(":%s/imgs/%s.img", resourceName, v)) then
                    img = findImg(v, resourceName)
                end
            end
            if not img then
                if fileExists(string.format(":%s/imgs/%s_%s.img", resourceName, v, i)) then
                    img = findImg(v .. "_" .. i, resourceName)
                elseif fileExists(string.format(":%s/imgs/%s%s.img", resourceName, v, i)) then
                    img = findImg(v .. i, resourceName)
                end
            end

            if img then prepIMGFiles(img, resourceName) end
        end
    end
end

function unloadResourceIMGs(resourceName)
    if tostring(resourceName) then
        imageFiles[resourceName] = nil
        resourceImages[resourceName] = nil
        resourceName = resourceName or ""
        for _, v in pairs(IMGNames) do
            for i = 0, maxIMG do
                if (i == 1) then
                    if fileExists(string.format(":%s/imgs/%s_%s.img", resourceName, v, i)) then
                        engineRemoveImage(string.format(":%s/imgs/%s_%s.img", resourceName, v, i))
                    elseif fileExists(string.format(":%s/imgs/%s.img", resourceName, v)) then
                        engineRemoveImage(string.format(":%s/imgs/%s.img", resourceName, v))
                    end
                    if fileExists(string.format(":%s/imgs/%s.img", resourceName, v)) then
                        engineRemoveImage(string.format(":%s/imgs/%s.img", resourceName, v))
                    end
                else
                    if fileExists(string.format(":%s/imgs/%s_%s.img", resourceName, v, i)) then
                        engineRemoveImage(string.format(":%s/imgs/%s_%s.img", resourceName, v, i))
                    elseif fileExists(string.format(":%s/imgs/%s.img", resourceName, v)) then
                        engineRemoveImage(string.format(":%s/imgs/%s.img", resourceName, v))
                    end
                end
            end
        end
    end
end

------------------------------
-- General Utilities
------------------------------

function split(str, sep)
    if type(str) ~= "string" or str == "" or not string.find(str, sep, 1, true) then
        return false
    end
    local result = {}
    for token in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(result, token)
    end
    return #result > 0 and result or false
end

------------------------------
-- Show Nearby Building/Object Utilities
------------------------------

local function showNearby(typeName, commandName, elementType)
    addCommandHandler(commandName, function(_, radius)
        radius = tonumber(radius) or 35
        local px, py, pz = getElementPosition(localPlayer)
        local elements = getElementsByType(elementType)
        local count = 0

        outputChatBox(string.format("#0066CC[Nearby %s]#FFFFFF Scanning within #FFFF00%d m#FFFFFF...", typeName, radius), 255,255,255,true)
        for _, elem in ipairs(elements) do
            local ox, oy, oz = getElementPosition(elem)
            local dist = getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz)
            if dist <= radius then
                local model = getElementModel(elem)
                local id = getElementID(elem) or "N/A"
                local zone = definitionZones[id] or "Unknown"
                outputChatBox(string.format(
                    "#CCCCCC • #00BFFFModel: #FFFFFF%s  #AAAAAA|  #00BFFFID: #FFFFFF%s  #AAAAAA|  #00BFFFZone: #FFFFFF%s  #AAAAAA|  #00BFFFDist: #FFFFFF%dm",
                    model, id, zone, math.floor(dist)
                ), 255,255,255,true)
                count = count + 1
            end
        end

        if count == 0 then
            outputChatBox(string.format("#FF4444No %s found within #FFFF00%d m#FF4444.", typeName:lower(), radius), 255,255,255,true)
        else
            outputChatBox(string.format("#00FF00Total %s found: #FFFFFF%d", typeName:lower(), count), 255,255,255,true)
        end
    end)
end

showNearby("Buildings", "nearbybuildings", "building")
showNearby("Objects", "nearbyobjects", "object")
