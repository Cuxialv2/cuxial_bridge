local ESX = exports.es_extended:getSharedObject()

local DB = {}
Bridge.DB = DB

DB.charTable = GetConvar('cuxial_bridge:charTable', 'users')
DB.charId    = GetConvar('cuxial_bridge:charIdColumn', 'identifier')
DB.vehTable  = GetConvar('cuxial_bridge:vehTable', 'owned_vehicles')
DB.vehOwner  = GetConvar('cuxial_bridge:vehOwnerColumn', 'owner')

local function decode(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return {} end
    local ok, r = pcall(json.decode, v)
    return (ok and type(r) == 'table') and r or {}
end

local function asBool(v) return v == 1 or v == true or v == '1' end
function DB.SearchTextDefinition()
    return "VARCHAR(255) GENERATED ALWAYS AS (LOWER(CONCAT_WS(' ', "
        .. "`firstname`, `lastname`, `identifier`))) STORED"
end

local function jobLabels(jobName, jobGrade)
    if not jobName then return '', '' end
    local jobs = ESX.GetJobs and ESX.GetJobs() or {}
    local j = jobs[jobName]
    if not j then return jobName, tostring(jobGrade or 0) end
    local g = j.grades and j.grades[tostring(jobGrade or 0)]
    return j.label or jobName, (g and (g.label or g.name)) or tostring(jobGrade or 0)
end

local function identityFromRow(row)
    local meta = decode(row.metadata)
    return {
        citizenid     = row.identifier,
        firstname     = row.firstname or '',
        lastname      = row.lastname or '',
        dob           = row.dateofbirth or '',
        gender        = (tostring(row.sex):lower() == 'f') and 1 or 0,
        nationality   = '',
        phone         = meta.phone or '',
        jobLabel      = (select(1, jobLabels(row.job, row.job_grade))),
        jobGradeLabel = (select(2, jobLabels(row.job, row.job_grade))),
        bloodtype     = meta.bloodtype,
        image         = row.police_image,
        wanted        = asBool(row.wanted),
        dangerous     = asBool(row.dangerous),
    }
end

function DB.GetCitizen(id)
    local row = MySQL.single.await(
        'SELECT identifier, firstname, lastname, dateofbirth, sex, job, job_grade, metadata, police_image, wanted, dangerous FROM users WHERE identifier = ?',
        { id })
    if not row then return nil end
    return identityFromRow(row)
end

function DB.SearchCitizens(term, limit)
    local rows = MySQL.query.await([[
        SELECT identifier, firstname, lastname, dateofbirth, sex, police_image, wanted, dangerous
        FROM users WHERE search_text LIKE ? LIMIT ?
    ]], { '%' .. tostring(term):lower() .. '%', limit or 20 }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            citizenid = row.identifier,
            firstname = row.firstname or '',
            lastname  = row.lastname or '',
            dob       = row.dateofbirth or '',
            gender    = (tostring(row.sex):lower() == 'f') and 1 or 0,
            nationality = '',
            phone     = '',
            image     = row.police_image,
            wanted    = asBool(row.wanted),
            dangerous = asBool(row.dangerous),
        }
    end
    return out
end

function DB.GetWanted(limit)
    local rows = MySQL.query.await([[
        SELECT identifier, firstname, lastname, police_image FROM users
        WHERE wanted = 1 OR dangerous = 1 LIMIT ?
    ]], { limit or 100 }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            citizenid = row.identifier,
            firstname = row.firstname or '',
            lastname  = row.lastname or '',
            image     = row.police_image,
        }
    end
    return out
end

function DB.GetCitizenFlags(id)
    local row = MySQL.single.await(
        'SELECT wanted, dangerous, police_image FROM users WHERE identifier = ?', { id }) or {}
    return { wanted = asBool(row.wanted), dangerous = asBool(row.dangerous), image = row.police_image }
end

function DB.SetCitizenFlag(id, key, value)
    if key ~= 'wanted' and key ~= 'dangerous' then return false end
    MySQL.update.await(('UPDATE users SET `%s` = ? WHERE identifier = ?'):format(key),
        { (value and 1) or 0, id })
    return true
end

function DB.SetCitizenImage(id, url)
    MySQL.update.await('UPDATE users SET police_image = ? WHERE identifier = ?', { url, id })
    return true
end

function DB.GetCitizenImages(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT identifier, police_image FROM users WHERE identifier IN (%s)'):format(ph), ids) or {}
    for _, row in ipairs(rows) do out[row.identifier] = row.police_image end
    return out
end

function DB.GetCitizenInfoBatch(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT identifier, firstname, lastname, police_image FROM users WHERE identifier IN (%s)'):format(ph), ids) or {}
    for _, row in ipairs(rows) do
        out[row.identifier] = { firstname = row.firstname or '', lastname = row.lastname or '', image = row.police_image }
    end
    return out
end

local function vehModel(raw)
    local v = decode(raw)
    return v.model or v.modelName or ''
end

function DB.GetVehiclesByOwner(id)
    local rows = MySQL.query.await(('SELECT plate, vehicle FROM %s WHERE %s = ?'):format(DB.vehTable, DB.vehOwner), { id }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { plate = r.plate, model = vehModel(r.vehicle) } end
    return out
end

function DB.SearchVehicles(term, limit)
    local rows = MySQL.query.await(([[
        SELECT v.%s AS ownerId, v.plate, v.vehicle, u.firstname, u.lastname
        FROM %s v LEFT JOIN users u ON u.identifier = v.%s
        WHERE v.plate LIKE ? LIMIT ?
    ]]):format(DB.vehOwner, DB.vehTable, DB.vehOwner), { '%' .. tostring(term) .. '%', limit or 20 }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            plate = r.plate, model = vehModel(r.vehicle), state = nil, ownerId = r.ownerId,
            ownerFirstname = r.firstname or '', ownerLastname = r.lastname or '',
        }
    end
    return out
end

function DB.GetVehicleByPlate(plate)
    local row = MySQL.single.await(([[
        SELECT v.%s AS ownerId, v.plate, v.vehicle, v.wanted, v.description, v.police_image,
               u.firstname, u.lastname
        FROM %s v LEFT JOIN users u ON u.identifier = v.%s
        WHERE v.plate = ?
    ]]):format(DB.vehOwner, DB.vehTable, DB.vehOwner), { plate })
    if not row then return nil end
    return {
        ownerId = row.ownerId, plate = row.plate, model = vehModel(row.vehicle),
        garage = nil, state = nil, depotprice = nil, mods = decode(row.vehicle),
        wanted = row.wanted, description = row.description, image = row.police_image,
        ownerFirstname = row.firstname or '', ownerLastname = row.lastname or '',
    }
end

function DB.GetVehicleScan(plate)
    local row = MySQL.single.await(([[
        SELECT v.%s AS ownerId, v.vehicle, v.wanted, u.firstname, u.lastname
        FROM %s v LEFT JOIN users u ON u.identifier = v.%s
        WHERE v.plate = ?
    ]]):format(DB.vehOwner, DB.vehTable, DB.vehOwner), { plate })
    if not row then return nil end
    return {
        ownerId = row.ownerId, mods = decode(row.vehicle), wanted = row.wanted,
        ownerFirstname = row.firstname or '', ownerLastname = row.lastname or '',
    }
end

function DB.SetVehicleField(plate, key, value)
    local allowed = { police_image = true, wanted = true, description = true, state = true }
    if not allowed[key] then return false end
    MySQL.update.await(('UPDATE %s SET `%s` = ? WHERE plate = ?'):format(DB.vehTable, key), { value, plate })
    return true
end

function DB.ListPlayers(limit)
    return MySQL.query.await([[
        SELECT u.identifier AS citizenid, u.firstname, u.lastname,
               (SELECT COUNT(*) FROM owned_vehicles v WHERE v.owner = u.identifier) AS vehicleCount
        FROM users u ORDER BY u.identifier LIMIT ?
    ]], { limit or 500 }) or {}
end

function DB.GetMoneyTotals()
    local row = MySQL.single.await([[SELECT
        COALESCE(SUM(JSON_EXTRACT(accounts, '$.bank')), 0) AS bank,
        COALESCE(SUM(JSON_EXTRACT(accounts, '$.money')), 0) AS cash,
        COUNT(*) AS players FROM users]])
    return {
        bank = tonumber(row and row.bank) or 0,
        cash = tonumber(row and row.cash) or 0,
        players = tonumber(row and row.players) or 0,
    }
end

function DB.GetTopPlayers(limit)
    local rows = MySQL.query.await([[SELECT identifier AS id, firstname, lastname,
        JSON_EXTRACT(accounts, '$.bank') AS bank,
        JSON_EXTRACT(accounts, '$.money') AS cash
        FROM users
        ORDER BY (JSON_EXTRACT(accounts, '$.bank') + JSON_EXTRACT(accounts, '$.money')) DESC
        LIMIT ?]], { limit or 100 }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id,
            firstname = r.firstname or 'Unknown',
            lastname = r.lastname or '',
            bank = tonumber(r.bank) or 0,
            cash = tonumber(r.cash) or 0,
        }
    end
    return out
end

function DB.GetJobMembers(jobName)
    local rows = MySQL.query.await('SELECT identifier FROM users WHERE job = ?', { jobName }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.identifier end
    return out
end

return DB
