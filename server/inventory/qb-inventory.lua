local inv = exports['qb-inventory']
local I = Bridge.Inventory

local function warnUnsupported(name)
    return function()
        print(('[cuxial_bridge] %s no está soportado en qb-inventory (no-op)'):format(name))
    end
end

function I.AddItem(src, item, count, metadata, slot)
    return inv:AddItem(src, item, count or 1, slot, metadata)
end

function I.RemoveItem(src, item, count, metadata, slot)
    return inv:RemoveItem(src, item, count or 1, slot)
end

function I.GetItemCount(src, item, metadata)
    local itemData = inv:GetItemByName(src, item)
    return itemData and itemData.amount or 0
end

function I.Search(src, searchType, item, metadata)
    if searchType == 'count' then
        return I.GetItemCount(src, item, metadata)
    end
    local items = inv:GetItemsByName(src, item) or {}
    return items
end

function I.CanCarryItem(src, item, count, metadata)
    return inv:CanAddItem(src, item, count or 1)
end

function I.GetItemDefinition(item)
    local ok, def = pcall(function()
        local core = exports['qb-core']:GetCoreObject()
        return core and core.Shared and core.Shared.Items and core.Shared.Items[item] or nil
    end)
    return ok and def or nil
end

function I.GetItem(src, item, metadata, returnsCount)
    local itemData = inv:GetItemByName(src, item)
    if returnsCount then return itemData and itemData.amount or 0 end
    return itemData
end

function I.GetSlot(src, slot)
    return inv:GetItemBySlot(src, slot)
end

function I.SetMetadata(src, slot, metadata)
    local item = inv:GetItemBySlot(src, slot)
    if not item then return false end
    return inv:SetItemData(src, item.name, 'info', metadata)
end

function I.GetInventoryItems(src)
    return inv:GetInventory(src)
end

function I.GetInventory(src)
    return inv:GetInventory(src)
end

function I.ClearInventory(src, keep)
    return inv:ClearInventory(src, keep)
end

function I.RegisterStash(id, label, slots, weight, owner)
    local ok, res = pcall(function()
        return inv:CreateInventory(id, { label = label, slots = slots, maxweight = weight })
    end)
    return ok and res or nil
end

I.openInventory       = warnUnsupported('openInventory')
I.openNearbyInventory = warnUnsupported('openNearbyInventory')
local VEHICLE_PREFIX = { glovebox = 'glovebox-', trunk = 'trunk-' }

---@param src number
---@param invType 'player'|'stash'|'glovebox'|'trunk'|string
---@param data any  source del jugador en 'player'; id del inventario en el resto
---@return boolean
function I.forceOpenInventory(src, invType, data)
    if invType == 'player' then
        local target = tonumber(type(data) == 'table' and data.id or data)
        if not target then return false end
        inv:OpenInventoryById(src, target)
        return true
    end
    local id = type(data) == 'table' and data.id or data
    if type(id) ~= 'string' or id == '' then return false end
    inv:OpenInventory(src, id)
    return true
end

---@param src number
---@param kind 'glovebox'|'trunk'
---@param plate string
---@return boolean
function I.OpenVehicleInventory(src, kind, plate)
    local prefix = VEHICLE_PREFIX[kind]
    if not prefix or type(plate) ~= 'string' or plate == '' then return false end
    inv:OpenInventory(src, prefix .. plate)
    return true
end

I.registerHook      = warnUnsupported('registerHook')
I.displayMetadata     = warnUnsupported('displayMetadata')

function I.GetItems()
    local ok, items = pcall(function()
        local core = exports['qb-core']:GetCoreObject()
        return core and core.Shared and core.Shared.Items or nil
    end)
    return (ok and type(items) == 'table') and items or {}
end

Bridge.Inventory = I
