local Profiles = require "EnvironmentalWeapons/EW_Profiles"
local Exposure = {}

-- Bags inside bags inside bags stop somewhere. Four levels covers every vanilla
-- nesting case and bounds the walk if a mod builds a cycle.
local MAX_CONTAINER_DEPTH = 4

-- Verified against the 42.20 bytecode: InventoryItem exposes getAttachedSlot()
-- returning an int and getAttachedSlotType() returning a String. A slung rifle
-- or holstered pistol reports a slot; a loose inventory item does not.
local function attachedToBody(item)
    local ok, slot = pcall(function() return item:getAttachedSlot() end)
    if ok then
        local index = tonumber(slot)
        if index ~= nil then return index >= 0 end
    end
    -- Fallback only if that getter disappears in a later build.
    local okType, slotType = pcall(function() return item:getAttachedSlotType() end)
    if okType and slotType ~= nil then
        local text = tostring(slotType)
        return text ~= "" and text ~= "null"
    end
    return false
end

local function itemContainer(item)
    if not item.getInventory then return nil end
    local ok, inventory = pcall(function() return item:getInventory() end)
    if ok then return inventory end
    return nil
end

function Exposure.resolve(player)
    local result, seen = {}, {}
    if not player then return result end

    local square = player:getSquare()
    local outside = square ~= nil and square:isOutside()

    local function record(item, exposed)
        -- Deduplicated by Lua object identity, which matters for two-handed
        -- rifles that report the same instance in both hands.
        if not item or seen[item] then return end
        if not Profiles.find(item) then return end
        seen[item] = true
        result[#result + 1] = {
            item = item,
            exposed = exposed,
            outside = outside,
        }
    end

    -- Hands first and explicitly. It is the case that must never be missed, and
    -- handling it here does not depend on how the inventory enumerates equipped
    -- items.
    local primary, secondary
    local okPrimary, valuePrimary = pcall(function() return player:getPrimaryHandItem() end)
    if okPrimary then primary = valuePrimary end
    local okSecondary, valueSecondary = pcall(function() return player:getSecondaryHandItem() end)
    if okSecondary then secondary = valueSecondary end
    record(primary, true)
    record(secondary, true)

    -- Then everything carried. A weapon slung on the back or holstered is out in
    -- the weather just as much as one in hand, and a weapon stowed in a bag is
    -- sheltered, so it thaws instead of collecting snow. Tracking both is what
    -- lets snow melt off a stowed weapon at all.
    local function walk(container, depth)
        if not container or depth > MAX_CONTAINER_DEPTH then return end
        local okItems, items = pcall(function() return container:getItems() end)
        if not okItems or not items then return end
        local size = 0
        local okSize, value = pcall(function() return items:size() end)
        if okSize then size = tonumber(value) or 0 end

        for index = 0, size - 1 do
            local okItem, item = pcall(function() return items:get(index) end)
            if okItem and item then
                record(item, attachedToBody(item))
                walk(itemContainer(item), depth + 1)
            end
        end
    end

    local okInventory, inventory = pcall(function() return player:getInventory() end)
    if okInventory then walk(inventory, 1) end

    return result
end

Exposure.attachedToBody = attachedToBody
return Exposure
