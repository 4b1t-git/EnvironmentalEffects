local Config = require "EnvironmentalWeapons/EW_Config"
local State = {}

local function safeValue(item, getter)
    if not item or not item[getter] then return nil end
    local ok, result = pcall(function() return item[getter](item) end)
    if not ok or result == nil then return nil end
    return tostring(result)
end

function State.ensure(item, worldAgeHours)
    local root = item:getModData()
    local state = root.EnvironmentalWeapons
    if state and state.schema == Config.SCHEMA_VERSION then return state end

    state = {
        schema = Config.SCHEMA_VERSION,
        snow = 0,
        stage = 0,
        lastObservedWorldAgeHours = tonumber(worldAgeHours) or 0,
        original = {
            fullType = item:getFullType(),
            weaponSprite = safeValue(item, "getWeaponSprite"),
            staticModel = safeValue(item, "getStaticModel"),
            worldStaticModel = safeValue(item, "getWorldStaticModel"),
            modelIndex = tonumber(safeValue(item, "getModelIndex")) or -1,
            textureName = safeValue(item, "getTextureName"),
            hadStaticOverride = root.staticModel ~= nil,
            staticOverride = root.staticModel and tostring(root.staticModel) or nil,
            hadWorldOverride = root.worldStaticModel ~= nil,
            worldOverride = root.worldStaticModel and tostring(root.worldStaticModel) or nil,
        },
        visual = {
            requestedStage = 0,
            equippedModel = nil,
            worldModel = nil,
            icon = nil,
        },
    }
    root.EnvironmentalWeapons = state
    return state
end

return State
