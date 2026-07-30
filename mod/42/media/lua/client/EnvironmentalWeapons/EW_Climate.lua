local Climate = {}

local function clamp01(value)
    value = tonumber(value) or 0
    return math.max(0, math.min(1, value))
end

function Climate.resolveSnowIntensity(isSnow, precipitationIntensity, snowStrengthFallback)
    if not isSnow then return 0 end
    if tonumber(precipitationIntensity) ~= nil then
        return clamp01(precipitationIntensity)
    end
    return clamp01(snowStrengthFallback)
end

-- Precipitation is one channel with a snow flag, so rain is simply active
-- precipitation that is not snow.
function Climate.resolveRainIntensity(isSnow, precipitationIntensity)
    if isSnow then return 0 end
    return clamp01(precipitationIntensity)
end

function Climate.sample(player)
    local manager = getClimateManager()
    local isSnow = manager:getPrecipitationIsSnow()
    local precipitation = manager:getPrecipitationIntensity()
    local snowStrength = manager:getSnowStrength()

    local rainIntensity = Climate.resolveRainIntensity(isSnow, precipitation)
    if rainIntensity <= 0 and not isSnow then
        -- RainManager is the channel vanilla systems themselves use. Fall back to
        -- it when the precipitation intensity channel reports nothing, so rain is
        -- never missed and snow cannot survive a downpour.
        local ok, raining = pcall(function() return RainManager.isRaining() end)
        if ok and raining then rainIntensity = 1 end
    end

    return {
        -- Precipitation intensity is the active weather channel. Snow strength
        -- is only a compatibility fallback if that channel is unavailable.
        snowIntensity = Climate.resolveSnowIntensity(
            isSnow, precipitation, snowStrength),
        rainIntensity = rainIntensity,
        precipitationIsSnow = isSnow,
        temperatureC = tonumber(manager:getAirTemperatureForCharacter(player, false)) or 0,
    }
end

return Climate
