local Profiles = require "EnvironmentalWeapons/EW_Profiles"
local Exposure = {}

-- Bags inside bags inside bags stop somewhere. Four levels covers every vanilla
-- nesting case and bounds the walk if a mod builds a cycle.
local MAX_CONTAINER_DEPTH = 4

-- Weapons lying on the ground are simulated too, but only near the player.
-- Without this a rifle dropped indoors kept its snow forever and one left out in
-- a blizzard never collected any: the controller simply never saw it.
--
-- The sweep is deliberately bounded. Ground items are world objects on squares,
-- so cost scales with area rather than with what the player carries. A radius of
-- 10 is 441 squares per tick, which is cheap at one tick per ten game minutes,
-- and it matches how the rest of the game treats distance: what is near you
-- behaves, what is far away is not simulated.
local GROUND_RADIUS = 10

-- A holster is a pouch: it covers the barrel and most of the frame, leaving the
-- grip and hammer out. So a holstered weapon is genuinely out in the weather, but
-- it catches far less than one held in the open. Slung on the back is different --
-- nothing covers it -- so that keeps the full rate.
--
-- Treating a holstered weapon as sheltered instead would be worse: it would thaw
-- during a blizzard at -10 C, which is a bigger lie than collecting snow slightly
-- too fast.
local HOLSTER_EXPOSURE = 0.5
local HOLSTER_SLOT_PATTERN = "[Hh]olster"

-- Verified against the 42.20 bytecode: InventoryItem exposes getAttachedSlot()
-- returning an int and getAttachedSlotType() returning a String. A slung rifle
-- or holstered pistol reports a slot; a loose inventory item does not.
-- Returns 0 when the item is not on the body, 1 when it is fully out in the
-- weather, and a fraction when something partly covers it.
local function bodyExposure(item)
    local slotType
    local okType, value = pcall(function() return item:getAttachedSlotType() end)
    if okType and value ~= nil then slotType = tostring(value) end
    local sheltered = slotType ~= nil and slotType:match(HOLSTER_SLOT_PATTERN) ~= nil

    local ok, slot = pcall(function() return item:getAttachedSlot() end)
    if ok then
        local index = tonumber(slot)
        if index ~= nil then
            if index < 0 then return 0 end
            return sheltered and HOLSTER_EXPOSURE or 1
        end
    end
    -- Fallback only if that getter disappears in a later build.
    if slotType ~= nil and slotType ~= "" and slotType ~= "null" then
        return sheltered and HOLSTER_EXPOSURE or 1
    end
    return 0
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

    -- `exposed` is a thunk, not a value. Passing attachedToBody(item) directly
    -- meant Lua evaluated it for every item in the inventory before the profile
    -- check could reject it, paying two pcalls per carried item every tick for
    -- items that can never match a profile.
    -- `itemOutside` defaults to the player's square, which is right for anything
    -- carried, and is passed explicitly for ground items so each one is judged by
    -- where it actually lies.
    local function record(item, isExposed, itemOutside, worldObject, itemSquare)
        -- Deduplicated by Lua object identity, which matters for two-handed
        -- rifles that report the same instance in both hands.
        if not item or seen[item] then return end
        if not Profiles.find(item) then return end
        seen[item] = true
        result[#result + 1] = {
            item = item,
            exposed = isExposed(item),
            outside = itemOutside == nil and outside or itemOutside,
            -- Carried through so the adapter can force a redraw of a weapon
            -- lying on the ground; a world object is not rendered on the
            -- character and never sees the hands refresh.
            worldObject = worldObject,
            square = itemSquare,
        }
    end

    local function alwaysExposed() return 1 end

    -- Hands first and explicitly. It is the case that must never be missed, and
    -- handling it here does not depend on how the inventory enumerates equipped
    -- items.
    local primary, secondary
    local okPrimary, valuePrimary = pcall(function() return player:getPrimaryHandItem() end)
    if okPrimary then primary = valuePrimary end
    local okSecondary, valueSecondary = pcall(function() return player:getSecondaryHandItem() end)
    if okSecondary then secondary = valueSecondary end
    record(primary, alwaysExposed)
    record(secondary, alwaysExposed)

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
                record(item, bodyExposure)
                walk(itemContainer(item), depth + 1)
            end
        end
    end

    local okInventory, inventory = pcall(function() return player:getInventory() end)
    if okInventory then walk(inventory, 1) end

    -- Finally the ground nearby. `outside` is read from the item's own square,
    -- not the player's: a rifle dropped in a doorway thaws or collects snow
    -- according to where IT lies, which is the whole point of tracking it.
    local okSquare, square = pcall(function() return player:getSquare() end)
    if not okSquare or not square then return result end
    local okCell, cell = pcall(function() return getCell() end)
    if not okCell or not cell then return result end

    local px, py, pz
    local okCoords = pcall(function()
        px, py, pz = square:getX(), square:getY(), square:getZ()
    end)
    if not okCoords then return result end

    for dy = -GROUND_RADIUS, GROUND_RADIUS do
        for dx = -GROUND_RADIUS, GROUND_RADIUS do
            local okGround, ground = pcall(function()
                return cell:getGridSquare(px + dx, py + dy, pz)
            end)
            if okGround and ground then
                local groundOutside = false
                local okOutside, value = pcall(function() return ground:isOutside() end)
                if okOutside then groundOutside = value == true end

                local okObjects, objects = pcall(function() return ground:getWorldObjects() end)
                if okObjects and objects then
                    local count = 0
                    local okCount, size = pcall(function() return objects:size() end)
                    if okCount then count = tonumber(size) or 0 end
                    for index = 0, count - 1 do
                        local object, item
                        local okItem = pcall(function()
                            object = objects:get(index)
                            item = object and object:getItem() or nil
                        end)
                        -- Lying in the open is exposed by definition; the square
                        -- decides whether that means snowfall or shelter.
                        if okItem and item then
                            record(item, alwaysExposed, groundOutside, object, ground)
                        end
                    end
                end
            end
        end
    end

    return result
end

-- Kept as a boolean for the visual adapter, which only needs to know whether the
-- item is drawn on the character at all.
function Exposure.attachedToBody(item)
    return bodyExposure(item) > 0
end

-- The other players this client can see, excluding the local one.
--
-- Empty in single player. Guarded rather than branched on isClient(), because a
-- coop host is both and the question that matters is simply whether there is
-- anyone else on screen to draw. That also makes split screen work for free:
-- there the "remote" players are the other local ones.
function Exposure.remotePlayers(localPlayer)
    local result = {}
    local ok, players = pcall(function() return getOnlinePlayers() end)
    if not ok or players == nil then return result end

    local size = 0
    local okSize, value = pcall(function() return players:size() end)
    if okSize then size = tonumber(value) or 0 end

    for index = 0, size - 1 do
        local okPlayer, other = pcall(function() return players:get(index) end)
        if okPlayer and other and other ~= localPlayer then
            -- A player whose square the cell has not loaded is not being drawn,
            -- so simulating their weapon would be work nobody can see.
            local okSquare, square = pcall(function() return other:getSquare() end)
            if okSquare and square then result[#result + 1] = other end
        end
    end
    return result
end

-- What another player has ON them, which is all of what this client draws for
-- them: the two hands, and anything slung or holstered.
--
-- Deliberately NOT the full walk `resolve` does. Their backpack contents are
-- never rendered, so snowing them would be invisible work, and the ground near
-- them is already covered by the local player's own sweep whenever the two are
-- close enough to see each other -- recording a ground item twice would charge
-- it the elapsed time twice and age it at double rate.
function Exposure.resolveRendered(player)
    local result, seen = {}, {}
    if not player then return result end

    local outside = false
    local okSquare, square = pcall(function() return player:getSquare() end)
    if okSquare and square then
        local okOutside, value = pcall(function() return square:isOutside() end)
        if okOutside then outside = value == true end
    end

    local function record(item, exposed)
        if not item or seen[item] then return end
        if not Profiles.find(item) then return end
        seen[item] = true
        result[#result + 1] = {
            item = item,
            exposed = exposed,
            outside = outside,
            worldObject = nil,
            square = nil,
        }
    end

    local okPrimary, primary = pcall(function() return player:getPrimaryHandItem() end)
    if okPrimary then record(primary, 1) end
    local okSecondary, secondary = pcall(function() return player:getSecondaryHandItem() end)
    if okSecondary then record(secondary, 1) end

    local okInventory, inventory = pcall(function() return player:getInventory() end)
    if okInventory and inventory then
        local okItems, items = pcall(function() return inventory:getItems() end)
        if okItems and items then
            local size = 0
            local okSize, value = pcall(function() return items:size() end)
            if okSize then size = tonumber(value) or 0 end
            for index = 0, size - 1 do
                local okItem, item = pcall(function() return items:get(index) end)
                -- Top level only, and only if it is actually worn: a slung rifle
                -- reports an attachment slot, a spare one loose in the inventory
                -- does not and is not drawn on the character.
                if okItem and item then
                    local worn = bodyExposure(item)
                    if worn > 0 then record(item, worn) end
                end
            end
        end
    end

    return result
end
return Exposure
