local Config = {
    SCHEMA_VERSION = 1,
    DEBUG = true,
    UPDATE_EVENT = "EveryTenMinutes",

    Snow = {
        maximum = 100,

        -- One signed axis carries both states: +100 is fully snowed, 0 is dry,
        -- -100 is soaked. Rain pushes the value down continuously, crosses zero
        -- and keeps going, so the snow-to-wet transition needs no special case
        -- and there is never a fake "dry" moment in the middle of a downpour.
        -- Set to 0 to disable wetness entirely; the snow half is unaffected.
        wetMaximum = 100,

        -- One visual stage per controller tick, in both directions. The stage
        -- entry thresholds below are 20/45/70/90 with 4 points of hysteresis, so
        -- 25 points per 10 game minutes crosses exactly one threshold going up
        -- and exactly one coming back down. Keep minutesPerStage equal to the
        -- controller interval; tools/validate.js enforces that.
        minutesPerStage = 10,
        percentPerStage = 25,

        -- Snowfall intensity GATES accumulation instead of scaling it. Build
        -- 42.20 reports precipitation intensity well below 1.0 during snow, and
        -- multiplying by it stretched stage 2 past 20 game hours, which reads in
        -- game as the mod being broken. Set this true to restore proportional
        -- rates, at the cost of a predictable pace.
        scaleWithIntensity = false,
        minimumIntensity = 0.01,
        accumulationMaxTemperatureC = 0.5,

        -- Snow does not evaporate from a frozen weapon left out in the open. It
        -- only retreats when sheltered from snowfall or when it is warm enough
        -- to thaw.
        meltStartTemperatureC = 0,
    },

    Stages = {
        thresholds = { 20, 45, 70, 90 },

        -- The wet side is read on the magnitude of a negative value and mirrors
        -- the snow spacing, so 25 points per tick still crosses exactly one
        -- threshold per controller tick. Three levels, not four: a weapon goes
        -- from dry to soaked over a much narrower visual range than dusted to
        -- buried, and a fourth level would not be distinguishable in game.
        wetThresholds = { 20, 45, 70 },
        hysteresis = 4,
    },
}

return Config
