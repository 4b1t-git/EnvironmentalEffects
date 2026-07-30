local Config = require "EnvironmentalWeapons/EW_Config"
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
    if not player then return end
    local worldAgeHours = getGameTime():getWorldAgeHours()
    local elapsedMinutes = 0
    if Controller.lastRunWorldAgeHours ~= nil then
        elapsedMinutes = math.max(
            0, (worldAgeHours - Controller.lastRunWorldAgeHours) * 60)
    end
    Controller.lastRunWorldAgeHours = worldAgeHours
    local climate = Climate.sample(player)
    local trackedNow = setmetatable({}, { __mode = "k" })

    for _, exposure in ipairs(Exposure.resolve(player)) do
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
        VisualAdapter.reconcile(player, item, profile, state.stage, state,
            exposure.worldObject, exposure.square)
    end
    Controller.previouslyTracked = trackedNow
end

Events.EveryTenMinutes.Add(Controller.update)
Events.OnGameStart.Add(Controller.update)
return Controller
