local Diagnostics = require "EnvironmentalWeapons/EW_Diagnostics"
local Exposure = require "EnvironmentalWeapons/EW_Exposure"
local Adapter = {}
local runtimeTextures = setmetatable({}, { __mode = "k" })
local LEGACY_WORLD_MODEL = "EW_HuntingRifle_SnowLight_World"

local function safeCall(object, method, ...)
    if not object or not object[method] then return false end
    local args = { n = select("#", ...), ... }
    return pcall(function() object[method](object, unpack(args, 1, args.n)) end)
end

local function isInHands(player, item)
    if not player or not item then return false end
    local okPrimary, primary = pcall(function() return player:getPrimaryHandItem() end)
    if okPrimary and primary == item then return true end
    local okSecondary, secondary = pcall(function() return player:getSecondaryHandItem() end)
    return okSecondary and secondary == item
end

-- A weapon in hand and a weapon slung on the back are both drawn on the
-- character, so both need their visual refreshed when the stage changes. Only a
-- weapon stowed inside a container is not rendered, and refreshing for that would
-- restart the held weapon's models for nothing.
local function isRenderedOnCharacter(player, item)
    if isInHands(player, item) then return true end
    return Exposure.attachedToBody(item)
end

-- resetEquippedHandsModels rebuilds the hand attachments only, and it does not
-- reach the rendered model while the character is in a seated or lying animation
-- state: the change appears only once standing restores the normal state. It also
-- does nothing at all for a weapon slung on the back, which is not a hand
-- attachment. resetModelNextFrame is the deferred full rebuild vanilla itself
-- uses for appearance changes, so request both: the cheap one lands immediately
-- when it can, the full one guarantees the change is not stuck until the pose
-- changes.
--
-- Cost is irrelevant here. A stage change happens at most once per controller
-- tick, so this runs a handful of times over an entire snowfall.
local function refreshCharacterVisual(player, item)
    if not isRenderedOnCharacter(player, item) then return false end
    safeCall(player, "resetEquippedHandsModels")
    safeCall(player, "resetModelNextFrame")
    return true
end

-- A weapon lying on the ground is an IsoWorldInventoryObject, not something drawn
-- on the character, so none of the character refresh calls reach it: its snow
-- changed in state but the square kept drawing the old model until the item was
-- picked up. Vanilla marks a changed world object dirty exactly this way.
local function refreshGroundVisual(worldObject, square)
    if not worldObject then return false end
    local refreshed = false
    local okDirty, dirty = pcall(function() return FBORenderChunk.DIRTY_REDRAW end)
    if okDirty and dirty ~= nil then
        if safeCall(worldObject, "invalidateRenderChunkLevel", dirty) then refreshed = true end
    end
    if square then safeCall(square, "setSquareChanged") end
    return refreshed
end

local function restoreWorld(item, state)
    local original = state.original
    if original.hadWorldOverride and original.worldOverride then
        return safeCall(item, "setWorldStaticModel", original.worldOverride)
    end
    local root = item:getModData()
    if root.worldStaticModel == state.visual.worldModel then
        root.worldStaticModel = nil
        return true
    end
    return root.worldStaticModel == nil
end

local function restoreIcon(item, state)
    if runtimeTextures[item] then return safeCall(item, "setTexture", runtimeTextures[item]) end
    local okScript, script = pcall(function() return item:getScriptItem() end)
    if okScript and script then
        local okTexture, texture = pcall(function() return script:getNormalTexture() end)
        if okTexture and texture then return safeCall(item, "setTexture", texture) end
    end
    return false
end

local function clearLegacyWorldOverride(item, state)
    if not state.visual or state.visual.worldModel ~= LEGACY_WORLD_MODEL then
        return false
    end

    local root = item:getModData()
    local current = root.worldStaticModel
    if current == nil then
        state.visual.worldModel = nil
        return false
    end
    if tostring(current) ~= LEGACY_WORLD_MODEL then
        Diagnostics.log("Legacy world override preserved external value for "
            .. tostring(item:getFullType()) .. ": " .. tostring(current))
        state.visual.worldModel = nil
        return false
    end

    root.worldStaticModel = nil
    if root.worldStaticModel == nil then
        state.visual.worldModel = nil
        Diagnostics.log("Cleared legacy Hunting Rifle world override")
        return true
    end
    Diagnostics.log("Failed to clear legacy Hunting Rifle world override")
    return false
end

function Adapter.reconcile(player, item, profile, stage, state, worldObject, square)
    local slot = profile.stages[stage] or profile.stages[0]
    clearLegacyWorldOverride(item, state)
    if state.visual.requestedStage == stage
        and state.visual.equippedModel == slot.equippedModel
        and state.visual.worldModel == slot.worldModel
        and state.visual.icon == slot.icon then
        return
    end

    if not runtimeTextures[item] and item.getTexture then
        local ok, texture = pcall(function() return item:getTexture() end)
        if ok then runtimeTextures[item] = texture end
    end

    local handsChanged = false
    if slot.equippedModel then
        handsChanged = safeCall(item, "setWeaponSprite", slot.equippedModel)
    elseif state.visual.equippedModel then
        if state.original.weaponSprite then
            handsChanged = safeCall(
                item, "setWeaponSprite", state.original.weaponSprite)
        else
            Diagnostics.log("Restore skipped: original WeaponSprite unavailable for "
                .. tostring(item:getFullType()))
        end
    end

    if slot.worldModel then
        safeCall(item, "setWorldStaticModel", slot.worldModel)
    elseif state.visual.worldModel then
        restoreWorld(item, state)
    end

    if slot.icon then
        local texture = getTexture(slot.icon)
        if texture then safeCall(item, "setTexture", texture) end
    elseif state.visual.icon then
        restoreIcon(item, state)
    end

    state.visual.requestedStage = stage
    state.visual.equippedModel = slot.equippedModel
    state.visual.worldModel = slot.worldModel
    state.visual.icon = slot.icon
    local refreshed = false
    if handsChanged then
        refreshed = refreshCharacterVisual(player, item)
        -- A weapon is either carried or on the ground, never both, so exactly one
        -- of these two paths applies.
        if not refreshed then
            refreshed = refreshGroundVisual(worldObject, square)
        end
    end
    Diagnostics.log(item:getFullType() .. " snow=" .. tostring(state.snow)
        .. " stage=" .. tostring(stage)
        .. " refreshed=" .. tostring(refreshed))
end

Adapter.clearLegacyWorldOverride = clearLegacyWorldOverride
return Adapter
