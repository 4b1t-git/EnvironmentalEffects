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

local function refresh(item, snow, stage)
    if not item or item:getFullType() ~= "Base.HuntingRifle" then return end
    local player = getPlayer()
    local profile = Profiles.find(item)
    if not player or not profile then return end
    local state = State.ensure(item, getGameTime():getWorldAgeHours())
    state.snow = snow
    state.stage = stage
    state.lastObservedWorldAgeHours = getGameTime():getWorldAgeHours()
    VisualAdapter.reconcile(player, item, profile, stage, state)
end

-- Forcing each stage matters for verification: waiting for real weather to cross
-- four thresholds is not a practical way to check four textures.
function DebugProbe.forceStage(item, stage)
    local threshold = Config.Stages.thresholds[stage]
    if not threshold then return end
    refresh(item, threshold, stage)
end

function DebugProbe.forceLight(item)
    DebugProbe.forceStage(item, 1)
end

function DebugProbe.restoreVanilla(item)
    refresh(item, 0, 0)
end

local function onContextMenu(playerIndex, context, items)
    local target
    for _, entry in ipairs(items) do
        local item = unpackItem(entry)
        if item and item:getFullType() == "Base.HuntingRifle" then
            target = item
            break
        end
    end
    if not target then return end
    local labels = {
        "EW Debug: force stage 1 (light snow)",
        "EW Debug: force stage 2 (medium snow)",
        "EW Debug: force stage 3 (heavy snow)",
        "EW Debug: force stage 4 (full snow)",
    }
    for stage = 1, #Config.Stages.thresholds do
        local label = labels[stage]
        if label then
            context:addOption(label, target, DebugProbe.forceStage, stage)
        end
    end
    context:addOption("EW Debug: restore vanilla", target, DebugProbe.restoreVanilla)
end

Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
return DebugProbe

