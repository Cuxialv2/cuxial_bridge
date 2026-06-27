local inv = exports.ox_inventory
local I = Bridge.Inventory

function I.AddItem(src, item, count, metadata, slot)
    return inv:AddItem(src, item, count or 1, metadata, slot)
end

function I.RemoveItem(src, item, count, metadata, slot)
    return inv:RemoveItem(src, item, count or 1, metadata, slot)
end

function I.GetItemCount(src, item, metadata)
    return inv:GetItemCount(src, item, metadata) or 0
end

function I.Search(src, searchType, item, metadata)
    return inv:Search(src, searchType, item, metadata)
end

function I.CanCarryItem(src, item, count, metadata)
    return inv:CanCarryItem(src, item, count or 1, metadata)
end

function I.GetItem(src, item, metadata, returnsCount)
    return inv:GetItem(src, item, metadata, returnsCount)
end

function I.GetSlot(src, slot)
    return inv:GetSlot(src, slot)
end

function I.SetMetadata(src, slot, metadata)
    return inv:SetMetadata(src, slot, metadata)
end

function I.GetInventoryItems(src)
    return inv:GetInventoryItems(src)
end

function I.GetInventory(src)
    return inv:GetInventory(src)
end

function I.ClearInventory(src, keep)
    return inv:ClearInventory(src, keep)
end

function I.RegisterStash(id, label, slots, weight, owner, groups, coords)
    return inv:RegisterStash(id, label, slots, weight, owner, groups, coords)
end

function I.openInventory(...) return inv:openInventory(...) end
function I.openNearbyInventory(...) return inv:openNearbyInventory(...) end
function I.forceOpenInventory(...) return inv:forceOpenInventory(...) end
function I.registerHook(...) return inv:registerHook(...) end
function I.displayMetadata(...) return inv:displayMetadata(...) end

Bridge.Inventory = I

