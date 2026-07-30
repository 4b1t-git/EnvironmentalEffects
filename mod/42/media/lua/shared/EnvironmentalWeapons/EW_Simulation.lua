local Simulation = {}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

-- Pure: no engine calls, so tests/pure_logic_test.js mirrors it exactly.
--
-- Rate is expressed as "one visual stage per tick" and converted to a per-minute
-- figure, so a skipped or coalesced tick still advances the correct amount rather
-- than losing time.
function Simulation.step(currentSnow, elapsedMinutes, sample, snowConfig)
    local snow = clamp(tonumber(currentSnow) or 0, 0, snowConfig.maximum)
    local minutes = math.max(0, tonumber(elapsedMinutes) or 0)
    if minutes == 0 then return snow end

    local intensity = clamp(tonumber(sample.snowIntensity) or 0, 0, 1)
    local temperature = tonumber(sample.temperatureC) or 0
    local delta = (snowConfig.percentPerStage / snowConfig.minutesPerStage) * minutes

    -- `exposed` is a fraction, not a flag: 1 in the open, 0.5 holstered, 0 stowed.
    -- A holster covers the barrel and most of the frame, so a holstered weapon
    -- collects real snow but slower than one carried in the open.
    local exposure = tonumber(sample.exposed)
    if exposure == nil then exposure = sample.exposed and 1 or 0 end
    if exposure < 0 then exposure = 0 elseif exposure > 1 then exposure = 1 end

    local accumulating = exposure > 0
        and sample.outside
        and intensity >= snowConfig.minimumIntensity
        and temperature <= snowConfig.accumulationMaxTemperatureC

    if accumulating then
        if snowConfig.scaleWithIntensity then delta = delta * intensity end
        return clamp(snow + (delta * exposure), 0, snowConfig.maximum)
    end

    -- Rain strips snow even below freezing. Liquid water is falling, which means
    -- it carries heat and washes the surface, and ambient air can still read
    -- below zero while it rains. Temperature alone must not gate this.
    local rainedOn = exposure > 0
        and sample.outside
        and (tonumber(sample.rainIntensity) or 0) >= snowConfig.minimumIntensity

    -- Sheltered means stowed in a container or indoors: no snowfall reaches it
    -- and it thaws. Held out in freezing weather with no precipitation, snow
    -- simply holds; it does not quietly drain away.
    -- Thawing is not scaled: a partly covered weapon still thaws at the normal
    -- rate once it is warm or sheltered. Only catching snow is reduced.
    local melting = (not sample.outside)
        or (exposure <= 0)
        or rainedOn
        or (temperature > snowConfig.meltStartTemperatureC)
    if not melting then return snow end

    return clamp(snow - delta, 0, snowConfig.maximum)
end

Simulation.clamp = clamp
return Simulation
