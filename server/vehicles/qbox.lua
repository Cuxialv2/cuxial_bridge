local veh = exports.qbx_vehicles
local V = Bridge.Vehicles

function V.GetPlayerVehicle(id)
    return veh:GetPlayerVehicle(id)
end

function V.GetPlayerVehicles(filter)
    return veh:GetPlayerVehicles(filter)
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

--- @return table<string, integer>  conteo de vehículos por garaje
function V.CountByGarage()
    local rows = MySQL.query.await('SELECT garage, COUNT(*) AS n FROM player_vehicles WHERE garage IS NOT NULL GROUP BY garage') or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.garage] = r.n end
    return out
end

--- @param ids integer[]
--- @return table<integer, number>
function V.MileageFor(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local ok, rows = pcall(MySQL.query.await, ('SELECT id, mileage FROM player_vehicles WHERE id IN (%s)'):format(ph), ids)
    if not ok then return out end
    for _, r in ipairs(rows or {}) do out[r.id] = r.mileage or 0 end
    return out
end

--- @param opts { search?: string, page?: integer, perPage?: integer }
--- @return { rows: table[], total: integer, page: integer, pages: integer, perPage: integer }
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

Bridge.Vehicles = V

