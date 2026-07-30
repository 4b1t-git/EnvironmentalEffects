local Config = require "EnvironmentalWeapons/EW_Config"
local State = {}

local function safeValue(item, getter)
    if not item or not item[getter] then return nil end
    local ok, result = pcall(function() return item[getter](item) end)
    if not ok or result == nil then return nil end
    return tostring(result)
end

-- Only the channels the adapter actually restores are captured. Snapshotting
-- getStaticModel, getModelIndex or getTextureName as well looked prudent but
-- nothing ever read them back, so they were dead weight persisted into every
-- save. fullType stays because it is what identifies a corrupted record.
local function captureOriginal(item, root)
    return {
        fullType = item:getFullType(),
        weaponSprite = safeValue(item, "getWeaponSprite"),
        hadWorldOverride = root.worldStaticModel ~= nil,
        worldOverride = root.worldStaticModel and tostring(root.worldStaticModel) or nil,
    }
end

function State.ensure(item, worldAgeHours)
    local root = item:getModData()
    local state = root.EnvironmentalWeapons
    if state and state.schema == Config.SCHEMA_VERSION then return state end

    -- A schema bump must never re-snapshot the item, because by then the adapter
    -- may already have replaced its WeaponSprite with a snow model. Capturing
    -- then would record "EW_..._Snow*" as the vanilla original and make restoring
    -- to vanilla impossible: the weapon would be permanently snowy. Carry the
    -- existing snapshot and accumulated snow forward instead.
    local carried = state and state.original or nil
    local carriedSnow = state and tonumber(state.snow) or nil
    local carriedStage = state and tonumber(state.stage) or nil
    local carriedVisual = state and state.visual or nil

    state = {
        schema = Config.SCHEMA_VERSION,
        snow = carriedSnow or 0,
        stage = carriedStage or 0,
        lastObservedWorldAgeHours = tonumber(worldAgeHours) or 0,
        original = carried or captureOriginal(item, root),
        visual = carriedVisual or {
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
