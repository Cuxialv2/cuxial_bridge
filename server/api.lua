local function notImplemented(name)
    return function()
        error(('[cuxial_bridge] %s() no implementado en el adaptador "%s"')
            :format(name, Bridge.framework), 2)
    end
end

local CONTRACT = {
    'GetPlayer', 'GetPlayerByCitizenId', 'GetOfflinePlayer', 'GetPlayers',
    'GetSource', 'GetIdentifier',
    'GetMoney', 'AddMoney', 'RemoveMoney',
    'GetMoneyOffline', 'AddMoneyOffline', 'RemoveMoneyOffline',
    'GetJob', 'GetJobInfo', 'GetJobs', 'SetJob', 'SetDuty', 'GetDutyCount', 'GetDutyCountJob',
    'GetGroupMembers',
    'AddPlayerToJob', 'RemovePlayerFromJob', 'SetPrimaryJob',
    'GetGang', 'SetGang', 'CreateGangs', 'RemoveGang', 'IsGradeBoss',
    'GetMetadata', 'SetMetadata',
    'SetCharName',
    'HasPermission',
    'CreateUseableItem',
    'Notify',
    'OnPlayerLoaded',
    'OnCharacterLoaded',
    'OnPlayerUnload',
    'OnJobUpdate',
    'OnGangUpdate',
    'OnMoneyChange',
    'GetVehiclesByName', 'GetVehiclesByHash',
}

for _, fn in ipairs(CONTRACT) do
    Bridge[fn] = notImplemented(fn)
end

---@param ids string[]
---@return table<string, table>
function Bridge.GetOfflinePlayersBatch(ids)
    local out = {}
    if type(ids) ~= 'table' then return out end
    for i = 1, #ids do
        local id = ids[i]
        if id and out[id] == nil then
            out[id] = Bridge.GetOfflinePlayer(id)
        end
    end
    return out
end

function Bridge.DeleteVehicle(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

function Bridge.OnPlayerDropped(cb)
    AddEventHandler('playerDropped', function(reason)
        cb(source, reason)
    end)
end

---@param src number
---@param ace string
---@return boolean
function Bridge.IsAceAllowed(src, ace)
    return IsPlayerAceAllowed(src, ace)
end

---@param identifier string
---@return table<string, number>
function Bridge.GetAllMoneyOffline(identifier)
    return {}
end

Bridge.Inventory = Bridge.Inventory or {}

Bridge.Vehicles = Bridge.Vehicles or {}

---@param identifier string
---@return table[]
function Bridge.Inventory.GetOfflineInventory(identifier)
    return {}
end

---@param identifier string
---@return { name: string, items: table[] }[]
function Bridge.Inventory.GetOwnedStashes(identifier)
    return {}
end

---@param name string
---@param owner? string
---@return table[]?
function Bridge.Inventory.GetStashData(name, owner)
    return nil
end

---@param items table[]?
---@param names string|string[]
---@return integer total
---@return table<string, integer> byName
function Bridge.Inventory.CountItems(items, names)
    local wanted, byName, total = {}, {}, 0
    if type(names) == 'string' then names = { names } end
    if type(items) ~= 'table' or type(names) ~= 'table' then return 0, byName end
    for i = 1, #names do wanted[names[i]] = true end
    for _, item in pairs(items) do
        if type(item) == 'table' and wanted[item.name] then
            local count = math.floor(tonumber(item.count or item.amount) or 0)
            if count > 0 then
                total = total + count
                byName[item.name] = (byName[item.name] or 0) + count
            end
        end
    end
    return total, byName
end

---@param identifier string
---@return { id: integer, plate: string, vehicle: string, trunk: table[], glovebox: table[] }[]
function Bridge.Vehicles.GetStorageByOwner(identifier)
    return {}
end

---@param src number
---@return boolean handled
function Bridge.RevivePlayer(src)
    return false
end

---@param src number
---@return boolean handled
function Bridge.HealPlayer(src)
    return false
end

---@param src number
---@param kind 'glovebox'|'trunk'
---@param plate string
---@return boolean
function Bridge.Inventory.OpenVehicleInventory(src, kind, plate)
    return false
end
