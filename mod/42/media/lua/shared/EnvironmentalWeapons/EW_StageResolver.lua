local StageResolver = {}

-- Climb and fall through a threshold ladder with hysteresis, so a value sitting
-- on a boundary cannot flicker between two stages tick after tick.
local function resolveLadder(magnitude, level, thresholds, hysteresis)
    local top = #thresholds
    local current = math.max(0, math.min(top, level))
    while current < top and magnitude >= thresholds[current + 1] do
        current = current + 1
    end
    while current > 0 and magnitude < (thresholds[current] - hysteresis) do
        current = current - 1
    end
    return current
end

-- Stages mirror the signed value: positive stages are snow, negative stages are
-- wet, and 0 is the vanilla appearance. Both sides run the same ladder; only the
-- thresholds and the sign differ.
function StageResolver.resolve(snow, currentStage, stageConfig)
    local value = tonumber(snow) or 0
    local stage = tonumber(currentStage) or 0
    local wetThresholds = stageConfig.wetThresholds

    -- Crossing zero always passes through the dry stage. A weapon cannot go from
    -- wearing snow to looking wet without being neither for an instant, and
    -- carrying a stale stage across the sign would show the wrong texture.
    if value >= 0 and stage < 0 then stage = 0 end
    if value <= 0 and stage > 0 then stage = 0 end

    if value >= 0 or not wetThresholds or #wetThresholds == 0 then
        return resolveLadder(value, stage, stageConfig.thresholds, stageConfig.hysteresis)
    end

    local level = resolveLadder(-value, -stage, wetThresholds, stageConfig.hysteresis)
    -- Return a plain 0 rather than a negated one. Dry has a single
    -- representation, so profile lookups and equality checks cannot miss it.
    if level == 0 then return 0 end
    return -level
end

return StageResolver

