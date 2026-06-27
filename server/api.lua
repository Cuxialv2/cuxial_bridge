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
    'OnPlayerUnload',
    'OnJobUpdate',
    'OnMoneyChange',
    'GetVehiclesByName', 'GetVehiclesByHash',
}

for _, fn in ipairs(CONTRACT) do
    Bridge[fn] = notImplemented(fn)
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

Bridge.Inventory = Bridge.Inventory or {}

Bridge.Vehicles = Bridge.Vehicles or {}