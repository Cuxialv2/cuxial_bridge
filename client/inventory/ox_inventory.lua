local inv = exports.ox_inventory
local I = Bridge.Inventory

function I.useItem(data, cb)
    return inv:useItem(data, cb)
end

function I.Search(searchType, item, metadata)
    return inv:Search(searchType, item, metadata)
end

function I.displayMetadata(data, ...)
    return inv:displayMetadata(data, ...)
end

function I.GetItemCount(item, metadata)
    return inv:Search('count', item) or 0
end

function I.weaponWheel(state)
    return inv:weaponWheel(state)
end

function I.openNearbyInventory(...)
    return inv:openNearbyInventory(...)
end

Bridge.Inventory = I

