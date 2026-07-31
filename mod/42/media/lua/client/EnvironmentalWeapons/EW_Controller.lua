local Config = require "EnvironmentalWeapons/EW_Config"
local Diagnostics = require "EnvironmentalWeapons/EW_Diagnostics"
local Climate = require "EnvironmentalWeapons/EW_Climate"
local Exposure = require "EnvironmentalWeapons/EW_Exposure"
local Profiles = require "EnvironmentalWeapons/EW_Profiles"
local State = require "EnvironmentalWeapons/EW_State"
local Simulation = require "EnvironmentalWeapons/EW_Simulation"
local StageResolver = require "EnvironmentalWeapons/EW_StageResolver"
local VisualAdapter = require "EnvironmentalWeapons/EW_VisualAdapter"

local Controller = {}
Controller.lastRunWorldAgeHours = nil
-- Weak keys: an item that is dropped or destroyed must not be kept alive here.
Controller.previouslyTracked = setmetatable({}, { __mode = "k" })

function Controller.update()
    local player = getPlayer()
    if not player then
        -- Logged, because a silent return here is indistinguishable from the
        -- controller never having been registered at all.
        Diagnostics.log("tick skipped: no player yet")
        return
    end
    local worldAgeHours = getGameTime():getWorldAgeHours()
    local elapsedMinutes = 0
    if Controller.lastRunWorldAgeHours ~= nil then
        elapsedMinutes = math.max(
            0, (worldAgeHours - Controller.lastRunWorldAgeHours) * 60)
    end
    Controller.lastRunWorldAgeHours = worldAgeHours
    local climate = Climate.sample(player)
    local trackedNow = setmetatable({}, { __mode = "k" })

    -- The whole simulation input, every tick, whether or not anything changed.
    --
    -- Without this a build where nothing is happening and a build where the
    -- client Lua never loaded produce byte-identical logs: the only other
    -- diagnostic fires from the visual adapter, which returns early when the
    -- stage it is asked for is the one already applied, so a weapon that stays
    -- dry is silent forever. That ambiguity cost a whole debugging session --
    -- an in-game report of "it was at maximum wet and nothing showed" could not
    -- be told apart from "it never got wet", which are opposite problems.
    --
    -- Guarded rather than left to Diagnostics.log, because unlike the adapter's
    -- one-per-change line this runs every tick and the concatenation would be
    -- paid even with logging off.
    local tracked = Exposure.resolve(player)
    if Config.DEBUG then
        Diagnostics.log("tick: rain=" .. tostring(climate.rainIntensity)
            .. " snowfall=" .. tostring(climate.snowIntensity)
            .. " tempC=" .. tostring(climate.temperatureC)
            .. " elapsedMin=" .. tostring(elapsedMinutes)
            .. " tracked=" .. tostring(#tracked))
    end

    for _, exposure in ipairs(tracked) do
        local item = exposure.item
        trackedNow[item] = true
        local profile = Profiles.find(item)
        local state = State.ensure(item, worldAgeHours)
        -- A newly observed item is charged zero minutes, so time before it was
        -- carried is never applied retroactively.
        local itemElapsedMinutes = Controller.previouslyTracked[item]
            and elapsedMinutes or 0
        state.lastObservedWorldAgeHours = worldAgeHours

        state.snow = Simulation.step(state.snow, itemElapsedMinutes, {
            snowIntensity = climate.snowIntensity,
            rainIntensity = climate.rainIntensity,
            temperatureC = climate.temperatureC,
            outside = exposure.outside,
            exposed = exposure.exposed,
        }, Config.Snow)
        state.stage = StageResolver.resolve(state.snow, state.stage, Config.Stages)
        if Config.DEBUG then
            Diagnostics.log("  " .. tostring(item:getFullType())
                .. " outside=" .. tostring(exposure.outside)
                .. " exposed=" .. tostring(exposure.exposed)
                .. " value=" .. tostring(state.snow)
                .. " stage=" .. tostring(state.stage))
        end
        VisualAdapter.reconcile(player, item, profile, state.stage, state,
            exposure.worldObject, exposure.square)
    end
    Controller.previouslyTracked = trackedNow
end

Events.EveryTenMinutes.Add(Controller.update)
Events.OnGameStart.Add(Controller.update)
-- Proof of life at load. This is the one line that separates "the mod is
-- installed but its client Lua never executed" from every other failure, and it
-- has to be emitted at require time rather than on the first tick, because the
-- first tick is exactly what a load failure prevents.
Diagnostics.log("controller registered; DEBUG=" .. tostring(Config.DEBUG))
return Controller
