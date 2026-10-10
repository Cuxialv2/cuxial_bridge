local veh = exports.qbx_vehicles
local V = Bridge.Vehicles

function V.GetPlayerVehicle(id)
    return veh:GetPlayerVehicle(id)
end

function V.GetPlayerVehicles(filter)
    return veh:GetPlayerVehicles(filter)
end

---@param ids integer[]
---@return table[]
function V.GetPlayerVehiclesByIds(ids)
    if type(ids) ~= 'table' or #ids == 0 then return {} end
    local placeholders = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT id, citizenid, vehicle, mods, garage, state, depotprice, plate FROM player_vehicles WHERE id IN (%s)'):format(placeholders),
        ids) or {}
    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        local ok, props = pcall(json.decode, r.mods or '')
        props = (ok and type(props) == 'table') and props or {}
        if not props.plate and r.plate then props.plate = r.plate end
        out[i] = {
            id = r.id,
            citizenid = r.citizenid,
            modelName = r.vehicle,
            props = props,
            garage = r.garage,
            state = r.state,
            depotPrice = r.depotprice,
        }
    end
    return out
end

function V.GetVehicleIdByPlate(plate)
    return veh:GetVehicleIdByPlate(plate)
end

function V.SaveVehicle(entity, data)
    return veh:SaveVehicle(entity, data)
end

function V.CreatePlayerVehicle(data)
    return veh:CreatePlayerVehicle(data)
end

function V.SetPlayerVehicleOwner(id, citizenid)
    return veh:SetPlayerVehicleOwner(id, citizenid)
end

---@param id integer
---@param citizenid string
---@param requireState integer  solo cambia el dueño si el estado sigue siendo este (claim atómico)
---@return boolean
function V.ClaimOwner(id, citizenid, requireState)
    if not id or not citizenid then return false end
    local n = MySQL.update.await(
        'UPDATE player_vehicles SET citizenid = ? WHERE id = ? AND state = ?', { citizenid, id, requireState })
    return (n or 0) > 0
end

function V.DeletePlayerVehicles(field, value)
    return veh:DeletePlayerVehicles(field, value)
end

function V.SetState(id, state)
    MySQL.update.await('UPDATE player_vehicles SET state = ? WHERE id = ?', { state, id })
end

function V.ClaimState(id, fromState, toState)
    local n = MySQL.update.await('UPDATE player_vehicles SET state = ? WHERE id = ? AND state = ?', { toState, id, fromState })
    return (n or 0) > 0
end

function V.SetStateGarage(id, state, garage)
    MySQL.update.await('UPDATE player_vehicles SET state = ?, garage = ? WHERE id = ?', { state, garage, id })
end

function V.ClaimStateGarage(id, fromState, toState, garage)
    local n = MySQL.update.await('UPDATE player_vehicles SET state = ?, garage = ? WHERE id = ? AND state = ?', { toState, garage, id, fromState })
    return (n or 0) > 0
end

function V.SetGarage(id, garage)
    MySQL.update.await('UPDATE player_vehicles SET garage = ? WHERE id = ?', { garage, id })
end

function V.ClaimGarage(id, fromGarage, toGarage, requireState)
    local n
    if fromGarage == nil then
        n = MySQL.update.await('UPDATE player_vehicles SET garage = ? WHERE id = ? AND garage IS NULL AND state = ?', { toGarage, id, requireState })
    else
        n = MySQL.update.await('UPDATE player_vehicles SET garage = ? WHERE id = ? AND garage = ? AND state = ?', { toGarage, id, fromGarage, requireState })
    end
    return (n or 0) > 0
end

function V.SetStateDepotPrice(id, state, depotPrice)
    MySQL.update.await('UPDATE player_vehicles SET state = ?, depotPrice = ? WHERE id = ?', { state, depotPrice, id })
end

function V.CountByGarage()
    local rows = MySQL.query.await('SELECT garage, COUNT(*) AS n FROM player_vehicles WHERE garage IS NOT NULL GROUP BY garage') or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.garage] = r.n end
    return out
end

function V.MileageFor(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local ok, rows = pcall(MySQL.query.await, ('SELECT id, mileage FROM player_vehicles WHERE id IN (%s)'):format(ph), ids)
    if not ok then return out end
    for _, r in ipairs(rows or {}) do out[r.id] = r.mileage or 0 end
    return out
end

function V.AdminList(opts)
    opts = opts or {}
    local perPage = tonumber(opts.perPage) or 50
    local page = math.max(1, tonumber(opts.page) or 1)

    local where, params = '', {}
    if type(opts.search) == 'string' and opts.search ~= '' then
        local like = '%' .. opts.search .. '%'
        where = ' WHERE plate LIKE ? OR vehicle LIKE ? OR citizenid LIKE ?'
        params = { like, like, like }
    end

    local total = MySQL.scalar.await('SELECT COUNT(*) FROM player_vehicles' .. where, params) or 0
    local pages = math.max(1, math.ceil(total / perPage))
    page = math.min(page, pages)
    local offset = (page - 1) * perPage

    local qp = {}
    for i = 1, #params do qp[i] = params[i] end
    qp[#qp + 1] = perPage
    qp[#qp + 1] = offset
    local rows = MySQL.query.await(
        'SELECT id, citizenid, vehicle, mods, garage, state, depotprice, plate FROM player_vehicles' ..
        where .. ' ORDER BY id LIMIT ? OFFSET ?', qp) or {}

    local out = {}
    for _, r in ipairs(rows) do
        local props = r.mods
        if type(props) == 'string' then
            local ok, d = pcall(json.decode, props); props = (ok and type(d) == 'table') and d or {}
        end
        if type(props) ~= 'table' then props = {} end
        if not props.plate then props.plate = r.plate end
        out[#out + 1] = {
            id = r.id, citizenid = r.citizenid, modelName = r.vehicle, props = props,
            garage = r.garage, state = r.state, depotPrice = r.depotprice, plate = r.plate,
        }
    end
    return { rows = out, total = total, page = page, pages = pages, perPage = perPage }
end

---@param raw any  columna JSON trunk/glovebox
---@return table[]
local function decodeStorage(raw)
    if type(raw) == 'string' and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        raw = ok and decoded or nil
    end
    if type(raw) ~= 'table' then return {} end
    local out = {}
    for _, item in pairs(raw) do
        if type(item) == 'table' and item.name then
            out[#out + 1] = {
                name = item.name,
                count = tonumber(item.count or item.amount) or 0,
                slot = item.slot,
                metadata = type(item.metadata) == 'table' and item.metadata or (type(item.info) == 'table' and item.info or {}),
            }
        end
    end
    return out
end

---@param identifier string
---@return { id: integer, plate: string, vehicle: string, trunk: table[], glovebox: table[] }[]
function V.GetStorageByOwner(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    local ok, rows = pcall(MySQL.query.await,
        'SELECT id, plate, vehicle, trunk, glovebox FROM player_vehicles WHERE citizenid = ?', { identifier })
    if not ok or not rows then return {} end
    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        out[i] = {
            id = r.id, plate = r.plate, vehicle = r.vehicle,
            trunk = decodeStorage(r.trunk), glovebox = decodeStorage(r.glovebox),
        }
    end
    return out
end

Bridge.Vehicles = V
