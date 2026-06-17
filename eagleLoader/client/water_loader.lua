-- =========================
-- Water Config
-- =========================
local WORLD_MIN = -3000
local WORLD_MAX = 3000
local Z_MIN = -1000
local Z_MAX = 1000
local waterDebug = false

local shiftX, shiftY, shiftZ = 0, 0, 0


-- ==============================
-- Water Loader Core
-- ==============================

function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function parseWaterDat(filePath,resourceName)
    local waterData = {}
    if fileExists(filePath) then
        local file = fileOpen(filePath)
        if not file then
            outputDebugString("Failed to open: " .. tostring(filePath), 1)
            return {}
        end

        local content = fileRead(file, fileGetSize(file))
        fileClose(file)

        cLine = 0

        for line in string.gmatch(content, "[^\r\n]+") do
            cLine = cLine + 1
            local coords = {}
            for num in string.gmatch(line, "[-%d%.]+") do
                table.insert(coords, tonumber(num))
            end

            -- A 4-vertex water quad needs at least 29 numeric values
            -- (4 corners * 7 values + 1 type flag). Some exports include
            -- trailing values, so accept >= 29 rather than requiring exactly 29.
            if #coords >= 29 then
                local function getClamped(i)
                    local x = clamp(coords[i] + shiftX, WORLD_MIN, WORLD_MAX)
                    local y = clamp(coords[i+1] + shiftY, WORLD_MIN, WORLD_MAX)
                    local z = clamp(coords[i+2] + shiftZ, Z_MIN, Z_MAX)
                    return x, y, z
                end

                local x1, y1, z1 = getClamped(1)
                local x2, y2, z2 = getClamped(8)
                local x3, y3, z3 = getClamped(15)
                local x4, y4, z4 = getClamped(22)

                table.insert(waterData, {
                    x1 = x1, y1 = y1, z1 = z1,
                    x2 = x2, y2 = y2, z2 = z2,
                    x3 = x3, y3 = y3, z3 = z3,
                    x4 = x4, y4 = y4, z4 = z4,
                    type = coords[29], name = cLine
                })
            else
                print("MALFORMED WATER - "..line)
            end
        end

        outputDebugString("Parsed " .. tostring(#waterData) .. " water quads from " .. filePath)
        createWaterPlanes(waterData,resourceName)
    else
        outputDebugString2("Error: No water.dat file present.")
    end
end


function createWater2(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,name)
    -- Return the created water element so createWaterPlanes can track it for
    -- cleanup on unload; otherwise water planes leak across map switches.
    local water = createWater(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4)

    if waterDebug then
        createRadarFromWaterZone(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,name)
    end

    return water
end


function createWaterPlanes(waterData,resourceName)
    for _, w in ipairs(waterData) do
        local water = createWater2(w.x1, w.y1, w.z1,
                    w.x2, w.y2, w.z2,
                    w.x3, w.y3, w.z3,
                    w.x4, w.y4, w.z4,w.name)
        if water then
            if resource[resourceName] then
                table.insert(resource[resourceName], water)
            end
        end 
    end
end

-- ==============================
-- Debug system
-- ==============================

radarAreas = {}

function createRadarFromWaterZone(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,rName)
    -- Find min/max XY from all corners
    local minX = math.min(x1, x2, x3, x4)
    local maxX = math.max(x1, x2, x3, x4)
    local minY = math.min(y1, y2, y3, y4)
    local maxY = math.max(y1, y2, y3, y4)
    
    local width = maxX - minX
    local height = maxY - minY
    
    
    local rArea = createRadarArea(minX, minY, width, height, math.random(0,255), math.random(0,255), math.random(0,255), 200) -- blue

    table.insert(radarAreas,{area = rArea,name = rName})

    return rArea
end


function isPlayerInRadarArea(area)
    local x, y = getElementPosition(localPlayer)

    local ax, ay = getElementPosition(area)
    local aw, ah = getRadarAreaSize (area)        

    return x >= ax and x <= ax + aw and y >= ay and y <= ay + ah
end

addCommandHandler("currentZone", function()
    local zoneName = "Unknown"
    for _, info in ipairs(radarAreas) do
        if isPlayerInRadarArea(info.area) then
            zoneName = info.name
            break
        end
    end
    outputChatBox("You are in zone: " .. zoneName, 255, 255, 0)
end)