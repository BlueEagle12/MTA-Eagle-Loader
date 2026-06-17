
local CONFIG_PATH = "config.xml"

-- ---------------------------------------------------------------------------
--  Parsing helpers (self-contained; general_helper.lua loads later)
-- ---------------------------------------------------------------------------

local function toBool(v, default)
    if v == nil then return default end
    v = tostring(v):lower()
    if v == "true"  or v == "1" or v == "yes" then return true  end
    if v == "false" or v == "0" or v == "no"  then return false end
    return default
end

local function toNum(v, default)
    return tonumber(v) or default
end

local function splitCSV(str)
    local t = {}
    if type(str) ~= "string" then return t end
    for token in str:gmatch("([^,]+)") do
        token = token:gsub("^%s*(.-)%s*$", "%1")
        if token ~= "" then table.insert(t, token) end
    end
    return t
end

local function attr(node, name)
    return node and xmlNodeGetAttribute(node, name) or nil
end

-- Iterate every child of `parent` with the given tag name.
local function forEachChild(parent, tagName, fn)
    if not parent then return end
    local i = 0
    while true do
        local child = xmlFindChild(parent, tagName, i)
        if not child then break end
        fn(child)
        i = i + 1
    end
end

-- ---------------------------------------------------------------------------
--  Defaults
-- ---------------------------------------------------------------------------

local function applyDefaults()
    -- IMG archive loading
    IMGNames = { "dff", "col", "txd", "custom" }
    maxIMG   = 4

    -- Streaming & distances
    streamEverything          = true
    removeDefaultMap          = true
    removeDefaultInteriors    = true
    allocateDefaultIDs        = true
    highDefLODs               = false
    streamingMemoryAllocation = 512
    streamingBufferAllocation = 150
    drawDistanceMultiplier    = 1

    -- Debug
    streamDebug         = false
    disableLOD          = false
    forceObject         = false
    modelCrashDebug     = false
    modelCrashDebugRate = 25
    despawnDebug        = false
    crashIndex          = 0      -- internal state, not exposed in config.xml

    -- LOD attachments
    lodAttach = {}

    -- Alpha fix shader
    alphaFixApply   = {}
    enableAlphaFix  = true
    enableAlphaFix2 = false
end

-- ---------------------------------------------------------------------------
--  Load
-- ---------------------------------------------------------------------------

local function loadConfig()
    applyDefaults()

    local root = xmlLoadFile(CONFIG_PATH)
    if not root then
        outputDebugString("eagleLoader: config.xml missing or invalid; using built-in defaults.", 2)
        return
    end

    -- IMG archive loading
    local img = xmlFindChild(root, "img", 0)
    if img then
        local names = attr(img, "names")
        if names then IMGNames = splitCSV(names) end
        maxIMG = toNum(attr(img, "max"), maxIMG)
    end

    -- Streaming & distances
    local s = xmlFindChild(root, "streaming", 0)
    if s then
        streamEverything          = toBool(attr(s, "streamEverything"),       streamEverything)
        removeDefaultMap          = toBool(attr(s, "removeDefaultMap"),        removeDefaultMap)
        removeDefaultInteriors    = toBool(attr(s, "removeDefaultInteriors"),  removeDefaultInteriors)
        allocateDefaultIDs        = toBool(attr(s, "allocateDefaultIDs"),      allocateDefaultIDs)
        highDefLODs               = toBool(attr(s, "highDefLODs"),             highDefLODs)
        streamingMemoryAllocation = toNum(attr(s, "memoryAllocation"),         streamingMemoryAllocation)
        streamingBufferAllocation = toNum(attr(s, "bufferAllocation"),         streamingBufferAllocation)
        drawDistanceMultiplier    = toNum(attr(s, "drawDistanceMultiplier"),   drawDistanceMultiplier)
    end

    -- Debug
    local d = xmlFindChild(root, "debug", 0)
    if d then
        streamDebug         = toBool(attr(d, "streamDebug"),         streamDebug)
        disableLOD          = toBool(attr(d, "disableLOD"),          disableLOD)
        forceObject         = toBool(attr(d, "forceObject"),         forceObject)
        modelCrashDebug     = toBool(attr(d, "modelCrashDebug"),     modelCrashDebug)
        modelCrashDebugRate = toNum(attr(d, "modelCrashDebugRate"),  modelCrashDebugRate)
        despawnDebug        = toBool(attr(d, "despawnDebug"),        despawnDebug)
    end

    -- LOD attachments
    local lod = xmlFindChild(root, "lodAttach", 0)
    forEachChild(lod, "model", function(m)
        local name = attr(m, "name")
        if name then lodAttach[name] = true end
    end)

    -- Alpha fix shader
    local af = xmlFindChild(root, "alphaFix", 0)
    if af then
        enableAlphaFix  = toBool(attr(af, "enable"),       enableAlphaFix)
        enableAlphaFix2 = toBool(attr(af, "experimental"), enableAlphaFix2)
        forEachChild(af, "pattern", function(p)
            local val = attr(p, "value")
            if val then table.insert(alphaFixApply, val) end
        end)
    end

    xmlUnloadFile(root)
end

loadConfig()
