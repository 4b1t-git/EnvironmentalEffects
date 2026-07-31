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
-- The value is a SIGNED axis: +maximum is fully snowed, 0 is dry, -wetMaximum is
-- soaked. It is still one number and one simulation; wetness is not a second
-- system running alongside snow.
function Simulation.step(currentSnow, elapsedMinutes, sample, snowConfig)
    local wetMaximum = tonumber(snowConfig.wetMaximum) or 0
    local snow = clamp(tonumber(currentSnow) or 0, -wetMaximum, snowConfig.maximum)
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
        return clamp(snow + (delta * exposure), -wetMaximum, snowConfig.maximum)
    end

    -- Rain strips snow even below freezing. Liquid water is falling, which means
    -- it carries heat and washes the surface, and ambient air can still read
    -- below zero while it rains. Temperature alone must not gate this.
    local rainedOn = exposure > 0
        and sample.outside
        and (tonumber(sample.rainIntensity) or 0) >= snowConfig.minimumIntensity

    if rainedOn then
        -- One continuous push down the axis: the rain washes the snow off and
        -- keeps going into wet. There is no dry state in between, because a
        -- weapon out in a downpour is never dry.
        --
        -- Stripping snow is not scaled by exposure, matching how thawing has
        -- always worked. Wetting IS scaled, because a holster genuinely keeps
        -- water off most of the frame.
        local advance = delta
        if snow <= 0 then advance = delta * exposure end
        return clamp(snow - advance, -wetMaximum, snowConfig.maximum)
    end

    if snow < 0 then
        -- Nothing is falling, so water leaves. Drying needs no warmth: a soaked
        -- weapon in a bag dries out at freezing just as it does indoors, which
        -- is why this is not gated on temperature the way thawing snow is.
        return clamp(snow + delta, -wetMaximum, snowConfig.maximum)
    end

    -- Sheltered means stowed in a container or indoors: no snowfall reaches it
    -- and it thaws. Held out in freezing weather with no precipitation, snow
    -- simply holds; it does not quietly drain away.
    -- Thawing is not scaled: a partly covered weapon still thaws at the normal
    -- rate once it is warm or sheltered. Only catching snow is reduced.
    local melting = (not sample.outside)
        or (exposure <= 0)
        or (temperature > snowConfig.meltStartTemperatureC)
    if not melting then return snow end

    -- Thawing snow stops at dry rather than continuing into wet. Meltwater does
    -- run off a real weapon, but modelling that would leave every thawed weapon
    -- wet with no weather to explain it, and the player never saw the water.
    return clamp(snow - delta, 0, snowConfig.maximum)
end

Simulation.clamp = clamp
return Simulation
