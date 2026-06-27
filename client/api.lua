local function notImplemented(name)
    return function()
        error(('[cuxial_bridge] (client) %s() no implementado en adaptador "%s"')
            :format(name, Bridge.framework), 2)
    end
end

local CONTRACT = {
    'GetPlayerData', 'IsLoggedIn', 'GetJob', 'GetJobInfo', 'GetGang',
    'OnPlayerLoaded', 'OnPlayerUnload', 'OnJobUpdate', 'OnGangUpdate',
}
for _, fn in ipairs(CONTRACT) do
    Bridge[fn] = notImplemented(fn)
end

function Bridge.Notify(data)
    if type(data) == 'string' then data = { description = data } end
    if lib and lib.notify then
        lib.notify(data)
    else
        TriggerEvent('ox_lib:notify', data)
    end
end

local labelCache = {}

---@param model string|number
---@return string
function Bridge.GetVehicleLabel(model)
    if model == nil then return '' end
    local hash = type(model) == 'number' and model or joaat(model)

    local cached = labelCache[hash]
    if cached ~= nil then return cached end

    local displayKey = GetDisplayNameFromVehicleModel(hash)
    local label
    if displayKey == '' or displayKey == 'CARNOTFOUND' then
        label = tostring(model)
    else
        local makeKey = GetMakeNameFromVehicleModel(hash)
        local make = (makeKey and makeKey ~= '') and GetLabelText(makeKey) or 'NULL'
        local name = GetLabelText(displayKey)
        if name == 'NULL' then name = displayKey end
        if make == 'NULL' or make == '' then
            label = name
        else
            label = make .. ' ' .. name
        end
    end

    label = (label:gsub('^%s*(.-)%s*$', '%1'))
    if label == '' then label = tostring(model) end

    labelCache[hash] = label
    return label
end

---@param model string|number
---@return integer class  clase GTA (0-22) o -1 si el modelo es desconocido
function Bridge.GetVehicleClass(model)
    if model == nil then return -1 end
    local hash = type(model) == 'number' and model or joaat(model)
    return GetVehicleClassFromName(hash)
end

---@param key string
---@return any
function Bridge.GetMetadata(key)
    local data = Bridge.GetPlayerData()
    local meta = data and data.metadata
    if not meta then return nil end
    return meta[key]
end

Bridge.Inventory = Bridge.Inventory or {}
Bridge.Target = Bridge.Target or {}

