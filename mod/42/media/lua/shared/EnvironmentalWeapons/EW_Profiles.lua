local Profiles = {}

local huntingRifle = {
    fullType = "Base.HuntingRifle",
    weaponSprite = "HuntingRifle",
    enabled = true,
    -- Every stage leaves worldModel nil on purpose. Firearms must fall through to
    -- the engine's HandWeapon handling, which keeps the dropped rifle flat and
    -- still textured; a WorldStaticModel forces the generic atlas branch and
    -- stands the rifle upright.
    stages = {
        [0] = { equippedModel = nil, worldModel = nil, icon = nil },
        [1] = {
            equippedModel = "EW_HuntingRifle_SnowLight",
            worldModel = nil,
            icon = nil,
        },
        [2] = {
            equippedModel = "EW_HuntingRifle_SnowMedium",
            worldModel = nil,
            icon = nil,
        },
        [3] = {
            equippedModel = "EW_HuntingRifle_SnowHeavy",
            worldModel = nil,
            icon = nil,
        },
        [4] = {
            equippedModel = "EW_HuntingRifle_SnowFull",
            worldModel = nil,
            icon = nil,
        },
    },
}

Profiles.byFullType = {
    [huntingRifle.fullType] = huntingRifle,
}
-- Future aliases must be explicitly keyed by FullType. A shared WeaponSprite
-- never enables an unrelated item.
Profiles.aliasesByFullType = {}

function Profiles.find(item)
    if not item then return nil end
    local fullType = item:getFullType()
    local profile = Profiles.byFullType[fullType]
    if not profile then
        local canonicalType = Profiles.aliasesByFullType[fullType]
        profile = canonicalType and Profiles.byFullType[canonicalType] or nil
    end
    return profile and profile.enabled and profile or nil
end

return Profiles
