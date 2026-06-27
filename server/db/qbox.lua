local DB = {}
Bridge.DB = DB

DB.charTable = GetConvar('cuxial_bridge:charTable', 'players')
DB.charId    = GetConvar('cuxial_bridge:charIdColumn', 'citizenid')
DB.vehTable  = GetConvar('cuxial_bridge:vehTable', 'player_vehicles')
DB.vehOwner  = GetConvar('cuxial_bridge:vehOwnerColumn', 'citizenid')

local function decode(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return {} end
    local ok, r = pcall(json.decode, v)
    return (ok and type(r) == 'table') and r or {}
end

local function asBool(v) return v == 1 or v == true or v == '1' end

function DB.SearchTextDefinition()
    return "VARCHAR(255) GENERATED ALWAYS AS (LOWER(CONCAT_WS(' ', "
        .. "JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.firstname')), "
        .. "JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.lastname')), "
        .. "JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.phone')), "
        .. "`citizenid`))) STORED"
end

local function identityFromRow(row)
    local ci = decode(row.charinfo)
    local job = decode(row.job)
    local meta = decode(row.metadata)
    local gender = ci.gender
    if type(gender) == 'string' then gender = (gender:lower() == 'f' or gender == '1') and 1 or 0 end
    return {
        citizenid     = row.citizenid,
        firstname     = ci.firstname or '',
        lastname      = ci.lastname or '',
        dob           = ci.birthdate or ci.dob or '',
        gender        = tonumber(gender) or 0,
        nationality   = ci.nationality or '',
        phone         = ci.phone or '',
        jobLabel      = job.label or '',
        jobGradeLabel = (job.grade and job.grade.name) or '',
        bloodtype     = meta.bloodtype,
        image         = row.police_image,
        wanted        = asBool(row.wanted),
        dangerous     = asBool(row.dangerous),
    }
end

function DB.GetCitizen(id)
    local row = MySQL.single.await(
        'SELECT citizenid, charinfo, job, metadata, police_image, wanted, dangerous FROM players WHERE citizenid = ?',
        { id })
    if not row then return nil end
    return identityFromRow(row)
end

function DB.SearchCitizens(term, limit)
    local rows = MySQL.query.await([[
        SELECT citizenid, charinfo, police_image, wanted, dangerous
        FROM players WHERE search_text LIKE ? LIMIT ?
    ]], { '%' .. tostring(term):lower() .. '%', limit or 20 }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local rec = identityFromRow(row)
        rec.jobLabel, rec.jobGradeLabel, rec.bloodtype = nil, nil, nil
        out[#out + 1] = rec
    end
    return out
end

function DB.GetWanted(limit)
    local rows = MySQL.query.await([[
        SELECT citizenid, charinfo, police_image FROM players
        WHERE wanted = 1 OR dangerous = 1 LIMIT ?
    ]], { limit or 100 }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local ci = decode(row.charinfo)
        out[#out + 1] = {
            citizenid = row.citizenid,
            firstname = ci.firstname or '',
            lastname  = ci.lastname or '',
            image     = row.police_image,
        }
    end
    return out
end

function DB.GetCitizenFlags(id)
    local row = MySQL.single.await(
        'SELECT wanted, dangerous, police_image FROM players WHERE citizenid = ?', { id }) or {}
    return { wanted = asBool(row.wanted), dangerous = asBool(row.dangerous), image = row.police_image }
end

function DB.SetCitizenFlag(id, key, value)
    if key ~= 'wanted' and key ~= 'dangerous' then return false end
    MySQL.update.await(('UPDATE players SET `%s` = ? WHERE citizenid = ?'):format(key),
        { (value and 1) or 0, id })
    return true
end

function DB.SetCitizenImage(id, url)
    MySQL.update.await('UPDATE players SET police_image = ? WHERE citizenid = ?', { url, id })
    return true
end

function DB.GetCitizenImages(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT citizenid, police_image FROM players WHERE citizenid IN (%s)'):format(ph), ids) or {}
    for _, row in ipairs(rows) do out[row.citizenid] = row.police_image end
    return out
end

function DB.GetCitizenInfoBatch(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT citizenid, charinfo, police_image FROM players WHERE citizenid IN (%s)'):format(ph), ids) or {}
    for _, row in ipairs(rows) do
        local ci = decode(row.charinfo)
        out[row.citizenid] = { firstname = ci.firstname or '', lastname = ci.lastname or '', image = row.police_image }
    end
    return out
end

function DB.GetVehiclesByOwner(id)
    local rows = MySQL.query.await('SELECT plate, vehicle, state, garage FROM player_vehicles WHERE citizenid = ?', { id }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { plate = r.plate, model = r.vehicle, state = r.state, garage = r.garage }
    end
    return out
end

function DB.SearchVehicles(term, limit)
    local rows = MySQL.query.await([[
        SELECT v.citizenid, v.plate, v.vehicle AS model, v.state, p.charinfo
        FROM player_vehicles v LEFT JOIN players p ON p.citizenid = v.citizenid
        WHERE v.plate LIKE ? LIMIT ?
    ]], { '%' .. tostring(term) .. '%', limit or 20 }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ci = decode(r.charinfo)
        out[#out + 1] = {
            plate = r.plate, model = r.model, state = r.state, ownerId = r.citizenid,
            ownerFirstname = ci.firstname or '', ownerLastname = ci.lastname or '',
        }
    end
    return out
end

function DB.GetVehicleByPlate(plate)
    local row = MySQL.single.await([[
        SELECT v.citizenid, v.plate, v.vehicle AS model, v.garage, v.state,
               v.depotprice, v.mods, v.wanted, v.description, v.police_image, p.charinfo
        FROM player_vehicles v LEFT JOIN players p ON p.citizenid = v.citizenid
        WHERE v.plate = ?
    ]], { plate })
    if not row then return nil end
    local ci = decode(row.charinfo)
    return {
        ownerId = row.citizenid, plate = row.plate, model = row.model,
        garage = row.garage, state = row.state, depotprice = row.depotprice,
        mods = decode(row.mods),
        wanted = row.wanted, description = row.description, image = row.police_image,
        ownerFirstname = ci.firstname or '', ownerLastname = ci.lastname or '',
    }
end

function DB.GetVehicleScan(plate)
    local row = MySQL.single.await([[
        SELECT v.citizenid, v.mods, v.wanted, p.charinfo
        FROM player_vehicles v LEFT JOIN players p ON p.citizenid = v.citizenid
        WHERE v.plate = ?
    ]], { plate })
    if not row then return nil end
    local ci = decode(row.charinfo)
    return {
        ownerId = row.citizenid, mods = decode(row.mods), wanted = row.wanted,
        ownerFirstname = ci.firstname or '', ownerLastname = ci.lastname or '',
    }
end

function DB.SetVehicleField(plate, key, value)
    local allowed = { police_image = true, wanted = true, description = true, state = true }
    if not allowed[key] then return false end
    MySQL.update.await(('UPDATE player_vehicles SET `%s` = ? WHERE plate = ?'):format(key), { value, plate })
    return true
end

function DB.ListPlayers(limit)
    return MySQL.query.await([[
        SELECT p.citizenid,
               JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
               JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))  AS lastname,
               (SELECT COUNT(*) FROM player_vehicles v WHERE v.citizenid = p.citizenid) AS vehicleCount
        FROM players p
        ORDER BY p.last_updated DESC
        LIMIT ?
    ]], { limit or 500 }) or {}
end

function DB.GetMoneyTotals()
    local row = MySQL.single.await([[SELECT
        COALESCE(SUM(JSON_EXTRACT(money, '$.bank')), 0) AS bank,
        COALESCE(SUM(JSON_EXTRACT(money, '$.cash')), 0) AS cash,
        COUNT(*) AS players FROM players]])
    return {
        bank = tonumber(row and row.bank) or 0,
        cash = tonumber(row and row.cash) or 0,
        players = tonumber(row and row.players) or 0,
    }
end

function DB.GetTopPlayers(limit)
    local rows = MySQL.query.await([[SELECT citizenid AS id,
        JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
        JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) AS lastname,
        JSON_EXTRACT(money, '$.bank') AS bank,
        JSON_EXTRACT(money, '$.cash') AS cash
        FROM players
        ORDER BY (JSON_EXTRACT(money, '$.bank') + JSON_EXTRACT(money, '$.cash')) DESC
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
    local rows = MySQL.query.await(
        "SELECT citizenid FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?", { jobName }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.citizenid end
    return out
end

return DB
