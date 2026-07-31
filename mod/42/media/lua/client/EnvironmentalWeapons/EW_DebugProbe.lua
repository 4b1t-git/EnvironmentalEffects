local Config = require "EnvironmentalWeapons/EW_Config"
if not Config.DEBUG then return end

require "ISUI/ISInventoryPaneContextMenu"

local Diagnostics = require "EnvironmentalWeapons/EW_Diagnostics"
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

-- Reports whether the mounted-part model can be reached from Lua at all.
--
-- Vanilla declares which model a mounted part uses on the WEAPON, not on the
-- part: `ModelWeaponPart = x2Scope x2Scope scope scope` means "for part type
-- x2Scope draw model x2Scope at anchor scope". zombie.scripting.objects.
-- ModelWeaponPart has four public String fields and a public no-arg
-- constructor, and HandWeapon exposes public get/setModelWeaponPart, so on
-- paper a scope could be pointed at a snowed model per weapon and per stage --
-- which is the one thing this mod was believed unable to do.
--
-- What is NOT established is whether Kahlua exposes the class for construction,
-- whether the list is per-item or shared with the script object, and whether
-- changing it re-renders anything. Read-only: it constructs nothing and sets
-- nothing, it only reports what is reachable, because a shared list would mean
-- a write here changed every weapon of the type in the save.
-- Logged step by step rather than assembled and printed at the end, and ordered
-- so the decisive questions are answered first.
--
-- The first run of this proved the point: reading a field off a ModelWeaponPart
-- raises, the pcall catches it, but the in-game debugger's "Break On Error"
-- halts on caught errors too, so the run stopped before reaching the questions
-- that actually matter and the report was never printed. Emitting as it goes
-- means whatever has already been established survives an interruption.
function DebugProbe.inspectWeaponParts(item)
    if not item then return end
    local function step(label, fn)
        local ok, value = pcall(fn)
        Diagnostics.log("parts probe | " .. label .. " = "
            .. (ok and tostring(value) or "FAILED"))
        return ok, value
    end

    Diagnostics.log("parts probe | ---- " .. tostring(item:getFullType()) .. " ----")

    -- Decisive question one: can Lua build the objects a write would need? If
    -- either of these is unreachable the whole approach is dead, so ask before
    -- anything that might halt the run.
    local okClass = step("ModelWeaponPart.new()", function() return ModelWeaponPart.new() end)
    local okList = step("ArrayList.new()", function() return ArrayList.new() end)

    -- Decisive question two: are the fields writable? ModelWeaponPart declares
    -- four public Strings and NO accessors, and Kahlua exposes methods rather
    -- than fields, so this is the step most likely to sink it: an object that
    -- cannot be filled in is useless even if it can be constructed.
    if okClass then
        step("write+read modelName on a fresh instance", function()
            local fresh = ModelWeaponPart.new()
            fresh.modelName = "EW_probe"
            return fresh.modelName
        end)
    end

    -- Everything below is detail, and is allowed to be the part that halts.
    local okGet, list = step("getModelWeaponPart()", function()
        return item:getModelWeaponPart()
    end)
    if okGet and list ~= nil then
        local okSize, size = step("list:size()", function() return list:size() end)
        if okSize and size then
            for i = 0, size - 1 do
                step("entry " .. i .. " partType", function() return list:get(i).partType end)
                step("entry " .. i .. " modelName", function() return list:get(i).modelName end)
            end
        end
    end

    Diagnostics.log("parts probe | ---- end ----")
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

    context:addOption("EW Debug: inspect weapon parts (log only)", target,
        DebugProbe.inspectWeaponParts)
    context:addOption("EW Debug: restore vanilla", target, DebugProbe.restoreVanilla)
end

Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
return DebugProbe
