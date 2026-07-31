local Config = require "EnvironmentalWeapons/EW_Config"
if not Config.DEBUG then return end

require "ISUI/ISInventoryPaneContextMenu"

local Profiles = require "EnvironmentalWeapons/EW_Profiles"
local State = require "EnvironmentalWeapons/EW_State"
local VisualAdapter = require "EnvironmentalWeapons/EW_VisualAdapter"

local DebugProbe = {}

local function unpackItem(entry)
    if instanceof(entry, "InventoryItem") then return entry end
    if entry and entry.items and entry.items[1] then return entry.items[1] end
    return nil
end

-- Any profiled weapon, not one hard-coded FullType. The probe used to name
-- Base.HuntingRifle directly, which quietly stopped covering eighteen of the
-- nineteen supported firearms once the roster grew.
local function profiledItem(entry)
    local item = unpackItem(entry)
    if not item then return nil, nil end
    local profile = Profiles.find(item)
    if not profile then return nil, nil end
    return item, profile
end

local function refresh(item, profile, value, stage)
    local player = getPlayer()
    if not player or not item or not profile then return end
    local state = State.ensure(item, getGameTime():getWorldAgeHours())
    state.snow = value
    state.stage = stage
    state.lastObservedWorldAgeHours = getGameTime():getWorldAgeHours()
    VisualAdapter.reconcile(player, item, profile, stage, state)
end

-- Forcing a stage matters for verification: waiting for real weather to cross
-- seven thresholds is not a practical way to check seven textures.
--
-- `stage` is signed, matching the axis: positive is snow, negative is wet. The
-- value written is that stage's entry threshold, so the state is consistent with
-- what the resolver would have produced on its own rather than an arbitrary
-- number that the next tick would immediately correct.
function DebugProbe.forceStage(item, stage)
    local profile = Profiles.find(item)
    if not profile then return end
    local threshold
    if stage > 0 then
        threshold = Config.Stages.thresholds[stage]
    elseif stage < 0 then
        local wet = Config.Stages.wetThresholds
        threshold = wet and wet[-stage]
        if threshold then threshold = -threshold end
    end
    if not threshold then return end
    refresh(item, profile, threshold, stage)
end

function DebugProbe.restoreVanilla(item)
    local profile = Profiles.find(item)
    if not profile then return end
    refresh(item, profile, 0, 0)
end

local SNOW_LABELS = {
    "EW Debug: force stage 1 (light snow)",
    "EW Debug: force stage 2 (medium snow)",
    "EW Debug: force stage 3 (heavy snow)",
    "EW Debug: force stage 4 (full snow)",
}

local WET_LABELS = {
    "EW Debug: force wet 1 (damp)",
    "EW Debug: force wet 2 (wet)",
    "EW Debug: force wet 3 (soaked)",
}

local function onContextMenu(playerIndex, context, items)
    local target
    for _, entry in ipairs(items) do
        local item = profiledItem(entry)
        if item then
            target = item
            break
        end
    end
    if not target then return end

    for stage = 1, #Config.Stages.thresholds do
        local label = SNOW_LABELS[stage]
        if label then
            context:addOption(label, target, DebugProbe.forceStage, stage)
        end
    end

    local wet = Config.Stages.wetThresholds
    if wet then
        for level = 1, #wet do
            local label = WET_LABELS[level]
            if label then
                context:addOption(label, target, DebugProbe.forceStage, -level)
            end
        end
    end

    context:addOption("EW Debug: restore vanilla", target, DebugProbe.restoreVanilla)
end

Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
return DebugProbe
