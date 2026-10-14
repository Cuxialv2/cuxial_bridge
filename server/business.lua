Bridge.Jobs = Bridge.Jobs or {}
Bridge.Society = Bridge.Society or {}

---@param name string
---@return boolean
local function started(name)
    return GetResourceState(name) == 'started'
end

---@param job table  { label, type?, defaultDuty?, offDutyPay?, grades = { { name, payment?, isboss?, bankAuth? } } }
---@return table  grados con clave 0..n como espera qbox/qbcore
local function qbGrades(job)
    local out = {}
    for i, g in ipairs(job.grades or {}) do
        out[i - 1] = {
            name = g.name, payment = g.payment or 0,
            isboss = g.isboss or nil, bankAuth = g.bankAuth or g.isboss or nil,
        }
    end
    return out
end

---@param name string
---@param job table
---@return boolean ok
---@return string? err
local function ensureEsx(name, job)
    if type(MySQL) ~= 'table' then return false, 'oxmysql no cargado en el recurso' end
    MySQL.query.await('INSERT IGNORE INTO jobs (name, label) VALUES (?, ?)', { name, job.label or name })
    for i, g in ipairs(job.grades or {}) do
        MySQL.query.await(
            'INSERT IGNORE INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { name, i - 1, g.name:lower():gsub('%s+', '_'), g.name, g.payment or 0, '{}', '{}' })
    end
    local ok, esx = pcall(function() return exports.es_extended:getSharedObject() end)
    if ok and esx and esx.RefreshJobs then pcall(esx.RefreshJobs) end
    return true
end

---@param name string  nombre del trabajo
---@param job table  { label, type?, defaultDuty?, offDutyPay?, grades = { { name, payment?, isboss? } } }
---@return boolean ok
---@return string? err
function Bridge.Jobs.Ensure(name, job)
    if type(name) ~= 'string' or name == '' or type(job) ~= 'table' then return false, 'parámetros' end
    if Bridge.framework == 'qbox' then
        local data = {
            label = job.label or name, type = job.type, defaultDuty = job.defaultDuty == true,
            offDutyPay = job.offDutyPay == true, grades = qbGrades(job),
        }
        local ok, done, msg = pcall(function() return exports['qbx_core']:CreateJob(name, data) end)
        if not ok then return false, tostring(done) end
        return done ~= false, msg
    end
    if Bridge.framework == 'qbcore' then
        local data = {
            label = job.label or name, type = job.type, defaultDuty = job.defaultDuty == true,
            offDutyPay = job.offDutyPay == true, grades = qbGrades(job),
        }
        for k, g in pairs(data.grades) do data.grades[tostring(k)], data.grades[k] = g, nil end
        local ok, done, msg = pcall(function() return exports['qb-core']:AddJob(name, data) end)
        if not ok then return false, tostring(done) end
        return done ~= false, msg
    end
    if Bridge.framework == 'esx' then return ensureEsx(name, job) end
    return false, 'framework sin soporte'
end

---@param name string
---@return boolean
function Bridge.Jobs.Exists(name)
    local ok, info = pcall(Bridge.GetJobInfo, name)
    return ok and type(info) == 'table'
end

---@return boolean
local function hasSql()
    return type(MySQL) == 'table'
end

---@param raw any
---@return table?
local function decode(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, value = pcall(json.decode, raw)
    return ok and type(value) == 'table' and value or nil
end

---@param cid string
---@return integer?
local function sourceOf(cid)
    local ok, src = pcall(Bridge.GetSourceByCitizenId, cid)
    src = ok and tonumber(src) or nil
    return src and src > 0 and src or nil
end

---@param out table[]
---@param seen table<string, true>
---@param cid string
---@param name string?
---@param grade any
local function push(out, seen, cid, name, grade)
    if type(cid) ~= 'string' or cid == '' or seen[cid] then return end
    seen[cid] = true
    local src = sourceOf(cid)
    out[#out + 1] = {
        cid = cid, name = name and name ~= '' and name or cid,
        grade = math.floor(tonumber(grade) or 0), online = src ~= nil, src = src,
    }
end

---@param name string
---@return table[]
local function membersQbox(name)
    local rows
    local ok, res = pcall(function() return exports['qbx_core']:GetGroupMembers(name, 'job') end)
    if ok and type(res) == 'table' then rows = res end
    if not rows and hasSql() then
        rows = MySQL.query.await("SELECT citizenid, grade FROM player_groups WHERE `group` = ? AND type = 'job'", { name }) or {}
    end
    rows = rows or {}
    local ids = {}
    for i, row in ipairs(rows) do ids[i] = row.citizenid end
    local info = {}
    if #ids > 0 and hasSql() then
        local okB, batch = pcall(Bridge.GetOfflinePlayersBatch, ids)
        info = okB and type(batch) == 'table' and batch or {}
    end
    local out, seen = {}, {}
    for _, row in ipairs(rows) do
        local p = info[row.citizenid] or {}
        local ci = p.charinfo
        local full = type(ci) == 'table' and ci.firstname and ((ci.firstname or '') .. ' ' .. (ci.lastname or '')) or p.name
        push(out, seen, row.citizenid, full, row.grade)
    end
    return out
end

---@param name string
---@return table[]
local function membersQbcore(name)
    local out, seen = {}, {}
    local ok, players = pcall(Bridge.GetPlayers)
    for _, player in pairs(ok and type(players) == 'table' and players or {}) do
        local pd = type(player) == 'table' and player.PlayerData or nil
        if pd and pd.job and pd.job.name == name then
            local ci = pd.charinfo or {}
            push(out, seen, pd.citizenid, ((ci.firstname or '') .. ' ' .. (ci.lastname or '')), (pd.job.grade or {}).level)
        end
    end
    if not hasSql() then return out end
    local rows = MySQL.query.await(
        "SELECT citizenid, charinfo, job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?", { name }) or {}
    for _, row in ipairs(rows) do
        local ci, job = decode(row.charinfo) or {}, decode(row.job) or {}
        push(out, seen, row.citizenid, ((ci.firstname or '') .. ' ' .. (ci.lastname or '')), (job.grade or {}).level)
    end
    return out
end

---@param name string
---@return table[]
local function membersEsx(name)
    local out, seen = {}, {}
    if hasSql() then
        local rows = MySQL.query.await('SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ?', { name }) or {}
        for _, row in ipairs(rows) do
            push(out, seen, row.identifier, ((row.firstname or '') .. ' ' .. (row.lastname or '')), row.job_grade)
        end
        return out
    end
    local ok, esx = pcall(function() return exports.es_extended:getSharedObject() end)
    if not ok or not esx then return out end
    for _, x in pairs(esx.GetExtendedPlayers and esx.GetExtendedPlayers() or {}) do
        local job = x.getJob and x.getJob() or x.job or {}
        if job.name == name then push(out, seen, x.identifier, x.getName and x.getName() or x.name, job.grade) end
    end
    return out
end

---@param name string
---@return { cid: string, name: string, grade: integer, online: boolean, src?: integer }[]
function Bridge.Jobs.Members(name)
    if type(name) ~= 'string' or name == '' then return {} end
    local ok, list = pcall(function()
        if Bridge.framework == 'qbox' then return membersQbox(name) end
        if Bridge.framework == 'qbcore' then return membersQbcore(name) end
        if Bridge.framework == 'esx' then return membersEsx(name) end
        return {}
    end)
    return ok and type(list) == 'table' and list or {}
end

---@param cid string
---@param name string
---@return boolean
local function removeQbcore(cid, name)
    local core = exports['qb-core']:GetCoreObject()
    local src = sourceOf(cid)
    if src then
        local player = core.Functions.GetPlayer(src)
        if not player or player.PlayerData.job.name ~= name then return false end
        player.Functions.SetJob('unemployed', 0)
        return true
    end
    if not hasSql() then return false end
    local def = (core.Shared.Jobs or {}).unemployed or {}
    local g0 = (def.grades or {})['0'] or (def.grades or {})[0] or {}
    local job = {
        name = 'unemployed', label = def.label or 'Civilian', payment = g0.payment or 0, onduty = true,
        isboss = false, type = def.type, grade = { name = g0.name or 'Freelancer', level = 0 },
    }
    local done = MySQL.update.await(
        "UPDATE players SET job = ? WHERE citizenid = ? AND JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?",
        { json.encode(job), cid, name })
    return (tonumber(done) or 0) > 0
end

---@param cid string
---@param name string
---@return boolean
local function removeEsx(cid, name)
    local esx = exports.es_extended:getSharedObject()
    local x = esx.GetPlayerFromIdentifier(cid)
    if x then
        local job = x.getJob and x.getJob() or x.job or {}
        if job.name ~= name then return false end
        x.setJob('unemployed', 0)
        return true
    end
    if not hasSql() then return false end
    local done = MySQL.update.await("UPDATE users SET job = 'unemployed', job_grade = 0 WHERE identifier = ? AND job = ?", { cid, name })
    return (tonumber(done) or 0) > 0
end

---@param cid string
---@param name string  solo quita si ese es su trabajo
---@return boolean ok
function Bridge.Jobs.Remove(cid, name)
    if type(cid) ~= 'string' or cid == '' or type(name) ~= 'string' or name == '' then return false end
    local ok, done = pcall(function()
        if Bridge.framework == 'qbox' then
            if not hasSql() and not sourceOf(cid) then return false end
            local res = exports['qbx_core']:RemovePlayerFromJob(cid, name)
            return res ~= false
        end
        if Bridge.framework == 'qbcore' then return removeQbcore(cid, name) end
        if Bridge.framework == 'esx' then return removeEsx(cid, name) end
        return false
    end)
    return ok and rawequal(done, true)
end

---@return string?  sistema de banca de sociedades disponible
function Bridge.Society.Provider()
    if started('cuxial_banking') then return 'cuxial_banking' end
    if started('Renewed-Banking') then return 'Renewed-Banking' end
    if started('qb-banking') then return 'qb-banking' end
    if started('esx_addonaccount') then return 'esx_addonaccount' end
    return nil
end

---@param society string
---@return table?
local function esxAccount(society)
    local p = promise.new()
    TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. society, function(account) p:resolve(account or false) end)
    SetTimeout(2000, function() if p.state == 0 then p:resolve(false) end end)
    return Citizen.Await(p) or nil
end

---@param society string
---@param amount number
---@param reason? string
---@return boolean
function Bridge.Society.AddMoney(society, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if type(society) ~= 'string' or amount <= 0 then return false end
    local provider = Bridge.Society.Provider()
    local ok, done = pcall(function()
        if provider == 'cuxial_banking' then return exports.cuxial_banking:AddSocietyMoney(society, amount, reason) end
        if provider == 'Renewed-Banking' then return exports['Renewed-Banking']:addAccountMoney(society, amount) end
        if provider == 'qb-banking' then return exports['qb-banking']:AddMoney(society, amount, reason) end
        if provider == 'esx_addonaccount' then
            local account = esxAccount(society)
            if not account then return false end
            account.addMoney(amount)
            return true
        end
        return false
    end)
    return ok and done ~= false and done ~= nil
end

---@param society string
---@param amount number
---@param reason? string
---@return boolean
function Bridge.Society.RemoveMoney(society, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if type(society) ~= 'string' or amount <= 0 then return false end
    local provider = Bridge.Society.Provider()
    local ok, done = pcall(function()
        if provider == 'cuxial_banking' then return exports.cuxial_banking:RemoveSocietyMoney(society, amount, reason) end
        if provider == 'Renewed-Banking' then return exports['Renewed-Banking']:removeAccountMoney(society, amount) end
        if provider == 'qb-banking' then return exports['qb-banking']:RemoveMoney(society, amount, reason) end
        if provider == 'esx_addonaccount' then
            local account = esxAccount(society)
            if not account or (account.money or 0) < amount then return false end
            account.removeMoney(amount)
            return true
        end
        return false
    end)
    return ok and done ~= false and done ~= nil
end

---@param society string
---@return number?  saldo o nil si no hay banca compatible
function Bridge.Society.GetBalance(society)
    if type(society) ~= 'string' then return nil end
    local provider = Bridge.Society.Provider()
    local ok, value = pcall(function()
        if provider == 'cuxial_banking' then
            local acc = exports.cuxial_banking:GetSocietyAccount(society)
            return acc and acc.balance
        end
        if provider == 'Renewed-Banking' then return exports['Renewed-Banking']:getAccountMoney(society) end
        if provider == 'qb-banking' then return exports['qb-banking']:GetAccountBalance(society) end
        if provider == 'esx_addonaccount' then
            local account = esxAccount(society)
            return account and account.money
        end
        return nil
    end)
    return ok and tonumber(value) or nil
end
