local StageResolver = {}

function StageResolver.resolve(snow, currentStage, stageConfig)
    local value = tonumber(snow) or 0
    local stage = math.max(0, math.min(#stageConfig.thresholds, tonumber(currentStage) or 0))

    while stage < #stageConfig.thresholds
        and value >= stageConfig.thresholds[stage + 1] do
        stage = stage + 1
    end
    while stage > 0
        and value < (stageConfig.thresholds[stage] - stageConfig.hysteresis) do
        stage = stage - 1
    end
    return stage
end

return StageResolver

