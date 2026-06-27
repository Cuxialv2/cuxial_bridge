local I = Bridge.Inventory

function I.useItem(data, cb)

    if cb then cb(data) end
end

function I.Search(searchType, item)

    local has = exports['qb-inventory']:HasItem(item)
    if searchType == 'count' then return has and 1 or 0 end
    return has
end

function I.GetItemCount(item)
    return exports['qb-inventory']:HasItem(item) and 1 or 0
end

function I.displayMetadata() end

function I.weaponWheel() end

function I.openNearbyInventory()
    TriggerServerEvent('inventory:server:OpenInventory')
end

Bridge.Inventory = I

