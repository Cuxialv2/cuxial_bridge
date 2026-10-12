local V = Bridge.Vehicles

local SELECT = 'SELECT id, citizenid, vehicle, mods, garage, state, depotprice, plate FROM player_vehicles'

---@param r table?
---@return table?
local function normalize(r)
    if not r then return nil end
    local props = r.mods
    if type(props) == 'string' then
        local ok, d = pcall(json.decode, props); props = (ok and type(d) == 'table') and d or {}
    end
    if type(props) ~= 'table' then props = {} end
    if not props.plate and r.plate then props.plate = r.plate end
    return {
        id = r.id,
        citizenid = r.citizenid,
        modelName = r.vehicle,
        props = props,
        garage = r.garage,
        state = r.state,
        depotPrice = r.depotprice,
        plate = r.plate,
    }
end

function V.GetPlayerVehicle(id)
    return normalize((MySQL.query.await(SELECT .. ' WHERE id = ?', { id }) or {})[1])
end

function V.GetPlayerVehicles(filter)
    filter = filter or {}
    local where, params = {}, {}
    if filter.citizenid then where[#where + 1] = 'citizenid = ?'; params[#params + 1] = filter.citizenid end
    if filter.garage then where[#where + 1] = 'garage = ?'; params[#params + 1] = filter.garage end
    if filter.state ~= nil then where[#where + 1] = 'state = ?'; params[#params + 1] = filter.state end

    local sql = SELECT
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end

    local rows = MySQL.query.await(sql, params) or {}
    local out = {}
    for i = 1, #rows do out[i] = normalize(rows[i]) end
    return out
end

---@param ids integer[]
---@return table[]
function V.GetPlayerVehiclesByIds(ids)
    if type(ids) ~= 'table' or #ids == 0 then return {} end
    local placeholders = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(('%s WHERE id IN (%s)'):format(SELECT, placeholders), ids) or {}
    local out = {}
    for i = 1, #rows do out[i] = normalize(rows[i]) end
    return out
end

function V.GetVehicleIdByPlate(plate)
    if not plate then return nil end
    return MySQL.scalar.await('SELECT id FROM player_vehicles WHERE plate = ?', { plate })
end

function V.SaveVehicle(entity, data)
    data = data or {}
    local id = entity and Entity(entity).state.vehicleid
    if not id and entity and DoesEntityExist(entity) then
        id = V.GetVehicleIdByPlate((GetVehicleNumberPlateText(entity) or ''):gsub('%s+$', ''))
    end
    if not id then return false end

    local sets, params = {}, {}
    if data.props ~= nil then
        sets[#sets + 1] = 'mods = ?'; params[#params + 1] = json.encode(data.props)
        if type(data.props) == 'table' and data.props.plate then
            sets[#sets + 1] = 'plate = ?'; params[#params + 1] = data.props.plate
        end
    end
    if data.state ~= nil then sets[#sets + 1] = 'state = ?'; params[#params + 1] = data.state end
    if data.garage ~= nil then sets[#sets + 1] = 'garage = ?'; params[#params + 1] = data.garage end
    if #sets == 0 then return true end

    params[#params + 1] = id
    MySQL.update.await(('UPDATE player_vehicles SET %s WHERE id = ?'):format(table.concat(sets, ', ')), params)
    return true
end

---@param tbl string
---@return string?
local function uniquePlate(tbl)
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
    for _ = 1, 50 do
        local buf = {}
        for i = 1, 8 do
            local n = math.random(1, #chars)
            buf[i] = chars:sub(n, n)
        end
        local plate = table.concat(buf)
        local rows = MySQL.query.await(('SELECT 1 FROM %s WHERE plate = ? LIMIT 1'):format(tbl), { plate })
        if not rows or not rows[1] then return plate end
    end
    return nil
end

function V.CreatePlayerVehicle(data)
    if not data or not data.model or not data.citizenid then return nil end
    local props = data.props or {}
    local plate = props.plate or data.plate or uniquePlate('player_vehicles')
    if not plate then return nil end
    props.plate = plate

    return MySQL.insert.await(
        'INSERT INTO player_vehicles (citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {
            data.citizenid,
            data.model,
            GetHashKey(data.model),
            json.encode(props),
            plate,
            data.garage,
            data.state or 1,
        }
    )
end

function V.SetPlayerVehicleOwner(id, citizenid)
    if not id or not citizenid then return false end
    local n = MySQL.update.await('UPDATE player_vehicles SET citizenid = ? WHERE id = ?', { citizenid, id })
    return (n or 0) > 0
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
    local col = field == 'vehicleId' and 'id' or field == 'plate' and 'plate' or field == 'citizenid' and 'citizenid'
    if not col then return false end
    local n = MySQL.update.await(('DELETE FROM player_vehicles WHERE %s = ?'):format(col), { value })
    return (n or 0) > 0
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
    MySQL.update.await('UPDATE player_vehicles SET state = ?, depotprice = ? WHERE id = ?', { state, depotPrice, id })
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
    local ok, rows = pcall(MySQL.query.await, ('SELECT id, drivingdistance FROM player_vehicles WHERE id IN (%s)'):format(ph), ids)
    if not ok then return out end
    for _, r in ipairs(rows or {}) do out[r.id] = r.drivingdistance or 0 end
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
    local rows = MySQL.query.await(SELECT .. where .. ' ORDER BY id LIMIT ? OFFSET ?', qp) or {}

    local out = {}
    for i = 1, #rows do out[i] = normalize(rows[i]) end
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
