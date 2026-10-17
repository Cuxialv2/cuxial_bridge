local ESX = exports.es_extended:getSharedObject()

local ACCOUNT_MAP = { cash = 'money', bank = 'bank' }

local GANG_META_KEY = 'cuxial_gang'

local function getAccountMoney(xPlayer, account)
    local acc = xPlayer.getAccount(ACCOUNT_MAP[account] or account)
    return acc and acc.money or 0
end

local function getGang(xPlayer)
    local g = xPlayer.getMeta and xPlayer.getMeta(GANG_META_KEY)
    return g or { name = 'none', label = 'No Gang', grade = 0, isboss = false }
end

---@param xPlayer table
---@param meta table
---@return table
local function withStatus(xPlayer, meta)
    local out = {}
    for k, v in pairs(meta) do out[k] = v end
    out.hunger, out.thirst = 0, 0
    local status = xPlayer.get and xPlayer.get('status')
    if type(status) ~= 'table' then return out end
    for _, entry in pairs(status) do
        if type(entry) == 'table' and (entry.name == 'hunger' or entry.name == 'thirst') then
            local pct = tonumber(entry.percent) or (tonumber(entry.val) or 0) / 10000
            out[entry.name] = math.max(0, math.min(100, pct))
        end
    end
    return out
end

local function normalize(xPlayer)
    if not xPlayer then return nil end
    local job = xPlayer.getJob() or {}
    local meta = xPlayer.getMeta and xPlayer.getMeta()
    if type(meta) ~= 'table' then meta = {} end
    meta = withStatus(xPlayer, meta)
    return {
        source    = xPlayer.source,
        citizenid = xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier,
        name      = xPlayer.getName and xPlayer.getName() or nil,
        charinfo  = {
            firstname = xPlayer.get and xPlayer.get('firstName') or nil,
            lastname  = xPlayer.get and xPlayer.get('lastName') or nil,
        },
        money = {
            cash = getAccountMoney(xPlayer, 'cash'),
            bank = getAccountMoney(xPlayer, 'bank'),
            black_money = getAccountMoney(xPlayer, 'black_money'),
        },
        job = {
            name = job.name, label = job.label,
            grade = job.grade, gradeLabel = job.grade_label,
            isboss = job.grade_name == 'boss',
            onduty = job.onDuty,
            type = job.name,
        },
        gang = getGang(xPlayer),

        metadata = meta,
        _raw = xPlayer,
    }
end

Bridge._normalize = normalize

function Bridge.GetPlayer(src) return normalize(ESX.GetPlayerFromId(src)) end
function Bridge.GetRawPlayer(src) return ESX.GetPlayerFromId(src) end

function Bridge.GetPlayerByCitizenId(cid)
    local online = ESX.GetPlayerFromIdentifier(cid)
    if online then return normalize(online) end
    return Bridge.GetOfflinePlayer(cid)
end

function Bridge.GetOfflinePlayer(identifier)
    if not MySQL then
        error('[cuxial_bridge] GetOfflinePlayer (ESX) requiere oxmysql cargado en el recurso')
    end
    local rows = MySQL.query.await(
        'SELECT identifier, accounts, job, job_grade, firstname, lastname, metadata FROM users WHERE identifier = ?',
        { identifier }
    )
    local row = rows and rows[1]
    if not row then return nil end

    local function safeDecode(v)
        if type(v) ~= 'string' then return v or {} end
        local ok, decoded = pcall(json.decode, v)
        return (ok and decoded) or {}
    end

    local accounts = safeDecode(row.accounts)
    local meta = safeDecode(row.metadata)

    return {
        source    = nil,
        offline   = true,
        citizenid = row.identifier,
        name      = (row.firstname and row.lastname) and (row.firstname .. ' ' .. row.lastname) or nil,
        charinfo  = { firstname = row.firstname, lastname = row.lastname },
        money = {
            cash = accounts.money or 0,
            bank = accounts.bank or 0,
            black_money = accounts.black_money or 0,
        },
        job  = { name = row.job, grade = row.job_grade },
        gang = meta[GANG_META_KEY] or { name = 'none', label = 'No Gang', grade = 0, isboss = false },
        metadata = meta,
        _raw = row,
    }
end
function Bridge.GetPlayers()
    local out = {}
    for _, src in ipairs(ESX.GetPlayers()) do
        out[src] = ESX.GetPlayerFromId(src)
    end
    return out
end
function Bridge.GetSource(identifier)
    local p = ESX.GetPlayerFromIdentifier(identifier)
    return p and p.source or nil
end
function Bridge.GetIdentifier(src)
    local p = ESX.GetPlayerFromId(src)
    if not p then return nil end
    return p.getIdentifier and p.getIdentifier() or p.identifier
end

function Bridge.GetMoney(src, account)
    local p = ESX.GetPlayerFromId(src)
    return p and getAccountMoney(p, account) or 0
end
function Bridge.AddMoney(src, account, amount, reason)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    p.addAccountMoney(ACCOUNT_MAP[account] or account, amount, reason)
    return true
end
function Bridge.RemoveMoney(src, account, amount, reason)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    if getAccountMoney(p, account) < amount then return false end
    p.removeAccountMoney(ACCOUNT_MAP[account] or account, amount, reason)
    return true
end

local function esxAccountKey(account) return ACCOUNT_MAP[account] or 'bank' end

function Bridge.GetMoneyOffline(identifier, account)
    local k = esxAccountKey(account)
    local row = (MySQL.query.await(
        ("SELECT JSON_EXTRACT(accounts, '$.%s') AS v FROM users WHERE identifier = ?"):format(k), { identifier }) or {})[1]
    return row and tonumber(row.v) or 0
end

---@param identifier string
---@return table<string, number>
function Bridge.GetAllMoneyOffline(identifier)
    local out = {}
    if type(identifier) ~= 'string' or identifier == '' then return out end
    local rows = MySQL.query.await('SELECT accounts FROM users WHERE identifier = ? LIMIT 1', { identifier })
    local raw = rows and rows[1] and rows[1].accounts
    if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        raw = ok and decoded or nil
    end
    if type(raw) ~= 'table' then return out end
    for account, amount in pairs(raw) do
        out[account == 'money' and 'cash' or account] = tonumber(amount) or 0
    end
    return out
end

function Bridge.AddMoneyOffline(identifier, account, amount, _reason)
    local k = esxAccountKey(account)
    local affected = MySQL.update.await(
        ("UPDATE users SET accounts = JSON_SET(accounts, '$.%s', COALESCE(JSON_EXTRACT(accounts, '$.%s'), 0) + ?) WHERE identifier = ?"):format(k, k),
        { amount, identifier })
    return (affected or 0) > 0
end

function Bridge.RemoveMoneyOffline(identifier, account, amount, _reason)
    local k = esxAccountKey(account)
    local affected = MySQL.update.await(
        ("UPDATE users SET accounts = JSON_SET(accounts, '$.%s', JSON_EXTRACT(accounts, '$.%s') - ?) WHERE identifier = ? AND JSON_EXTRACT(accounts, '$.%s') >= ?"):format(k, k, k),
        { amount, identifier, amount })
    return (affected or 0) > 0
end

function Bridge.GetJob(src)
    local n = normalize(ESX.GetPlayerFromId(src))
    return n and n.job or nil
end

function Bridge.GetJobInfo(name)
    local jobs = ESX.GetJobs and ESX.GetJobs() or {}
    return jobs[name]
end

function Bridge.GetJobs()
    return ESX.GetJobs and ESX.GetJobs() or {}
end

function Bridge.SetJob(src, name, grade)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    p.setJob(name, grade or 0)
    return true
end
function Bridge.SetDuty(src, onDuty)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    local job = p.getJob()
    if not job then return false end
    p.setJob(job.name, job.grade, onDuty)
    return true
end
function Bridge.GetDutyCount(jobType)
    local count, sources = 0, {}
    for _, src in ipairs(ESX.GetPlayers()) do
        local p = ESX.GetPlayerFromId(src)
        local job = p and p.getJob()
        if job and job.name == jobType and job.onDuty then
            count = count + 1
            sources[#sources + 1] = src
        end
    end
    return count, sources
end

function Bridge.GetDutyCountJob(jobName)
    local count, sources = 0, {}
    for _, xP in ipairs(ESX.GetExtendedPlayers('job', jobName)) do
        if xP.job and xP.job.onDuty then
            count = count + 1
            sources[#sources + 1] = xP.source
        end
    end
    return count, sources
end
function Bridge.GetGroupMembers(name)
    return ESX.GetExtendedPlayers('job', name, true)
end
function Bridge.AddPlayerToJob(src, job, grade) return Bridge.SetJob(src, job, grade) end
function Bridge.RemovePlayerFromJob(src) return Bridge.SetJob(src, 'unemployed', 0) end
function Bridge.SetPrimaryJob(src, job, grade) return Bridge.SetJob(src, job, grade) end

function Bridge.GetGang(src)
    local p = ESX.GetPlayerFromId(src)
    if not p then return nil end
    return getGang(p)
end
---@return table<string, table>
local function configGangs()
    local esx = Bridge.Config and Bridge.Config.esx
    return type(esx) == 'table' and type(esx.gangs) == 'table' and esx.gangs or {}
end

---@param gang table
---@param grade integer
---@return table?
local function gangGrade(gang, grade)
    local grades = type(gang.grades) == 'table' and gang.grades or {}
    return grades[grade] or grades[tostring(grade)]
end

function Bridge.SetGang(src, name, grade)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    grade = math.floor(tonumber(grade) or 0)
    local def = configGangs()[name]
    local gradeDef = def and gangGrade(def, grade)
    if name ~= 'none' and not gradeDef then return false end
    local gang = {
        name = name,
        label = def and def.label or 'Sin banda',
        grade = grade,
        gradeLabel = gradeDef and gradeDef.name or nil,
        isboss = gradeDef and gradeDef.isboss == true or false,
    }
    p.setMeta(GANG_META_KEY, gang)
    TriggerEvent('cuxial_bridge:esx:gangUpdated', src, gang)
    return true
end
function Bridge.CreateGangs() end
function Bridge.RemoveGang() end
function Bridge.IsGradeBoss(gangName, grade)
    local def = configGangs()[gangName]
    if not def then return (grade or 0) == 0 end
    local gradeDef = gangGrade(def, math.floor(tonumber(grade) or 0))
    return gradeDef and gradeDef.isboss == true or false
end

function Bridge.SetCharName(src, firstname, lastname)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    local fn = (firstname and firstname ~= '') and firstname or (p.get and p.get('firstName')) or nil
    local ln = (lastname and lastname ~= '') and lastname or (p.get and p.get('lastName')) or nil
    if p.set then
        p.set('firstName', fn)
        p.set('lastName', ln)
    end
    MySQL.update.await('UPDATE users SET firstname = ?, lastname = ? WHERE identifier = ?',
        { fn, ln, p.getIdentifier and p.getIdentifier() or p.identifier })
    return { firstname = fn, lastname = ln }
end

function Bridge.SetFrameworkDeathFlag(src, isDown)
    TriggerClientEvent('cuxial_bridge:internal:setDead', src, isDown == true)
end

function Bridge.GetMetadata(src, key)
    local p = ESX.GetPlayerFromId(src)
    if not p or not p.getMeta then return nil end
    return p.getMeta(key)
end
function Bridge.SetMetadata(src, key, value)
    local p = ESX.GetPlayerFromId(src)
    if not p or not p.setMeta then return false end
    p.setMeta(key, value)
    return true
end

function Bridge.HasPermission(src, perm)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    local group = p.getGroup()
    if perm == 'admin' or perm == 'god' then
        return group == 'admin' or group == 'superadmin'
    end
    return group == perm
end

function Bridge.CreateUseableItem(name, cb)
    ESX.RegisterUsableItem(name, cb)
end

function Bridge.Notify(src, message, _type, duration)
    TriggerClientEvent('esx:showNotification', src, message)
end

function Bridge.OnPlayerLoaded(cb)
    AddEventHandler('esx:playerLoaded', function(playerId)
        cb(playerId)
    end)
end

function Bridge.OnCharacterLoaded(cb)
    AddEventHandler('esx:playerLoaded', function(playerId)
        cb(playerId)
    end)
end

function Bridge.OnPlayerUnload(cb)
    AddEventHandler('esx:playerDropped', function(playerId)
        cb(playerId)
    end)
end

function Bridge.OnJobUpdate(cb)
    AddEventHandler('esx:setJob', function(source, job)
        cb(source, job)
    end)
end

function Bridge.OnGangUpdate(cb)
    AddEventHandler('cuxial_bridge:esx:gangUpdated', function(src, gang)
        cb(src, gang)
    end)
end

---ESX no tiene servicio por trabajo: no hay nada que escuchar.
function Bridge.OnDutyChange(_cb) end

function Bridge.OnMoneyChange(_) end

local tableCache = {}

---@param name string
---@return boolean
local function tableExists(name)
    if tableCache[name] ~= nil then return tableCache[name] end
    if not MySQL then return false end
    local ok, rows = pcall(MySQL.query.await, 'SHOW TABLES LIKE ?', { name })
    tableCache[name] = ok and rows ~= nil and rows[1] ~= nil
    return tableCache[name]
end

local columnCache = {}

---@param tbl string
---@param column string
---@return boolean
local function columnExists(tbl, column)
    local key = tbl .. '.' .. column
    if columnCache[key] ~= nil then return columnCache[key] end
    if not MySQL then return false end
    local ok, rows = pcall(MySQL.query.await, ('SHOW COLUMNS FROM `%s` LIKE ?'):format(tbl), { column })
    columnCache[key] = ok and rows ~= nil and rows[1] ~= nil
    return columnCache[key]
end

Bridge._esxTableExists = tableExists
Bridge._esxColumnExists = columnExists

---@return table<string, { name: string, model: string, price: number, category: string?, hash: integer }>
function Bridge.GetVehicleModels()
    local out = {}
    if not tableExists('vehicles') then return out end
    local ok, rows = pcall(MySQL.query.await, 'SELECT name, model, price, category FROM vehicles')
    if not ok or type(rows) ~= 'table' then return out end
    for i = 1, #rows do
        local row = rows[i]
        if row.model then
            out[row.model] = {
                name = row.name or row.model,
                model = row.model,
                price = tonumber(row.price) or 0,
                category = row.category,
                hash = joaat(row.model),
            }
        end
    end
    return out
end

function Bridge.GetVehiclesByName(name)
    local cat = Bridge.GetVehicleModels()
    if name == nil then return cat end
    return cat[name]
end
function Bridge.GetVehiclesByHash(hash)
    for _, v in pairs(Bridge.GetVehicleModels()) do
        if v.hash == hash then return v end
    end
    return nil
end

---@return table<string, table>
function Bridge.GetGangs()
    local out = {}
    for name, def in pairs(configGangs()) do
        out[name] = { label = def.label or name, grades = def.grades or {} }
    end
    return out
end

---@param citizenid string
---@return number?
function Bridge.GetSourceByCitizenId(citizenid)
    if not citizenid then return nil end

    local p = ESX.GetPlayerFromIdentifier(citizenid)
    local src = p and p.source

    return (type(src) == 'number' and src > 0) and src or nil
end

---@param _ string
---@return boolean
function Bridge.DeleteCharacter(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' or not MySQL then return false end

    local online = ESX.GetPlayerFromIdentifier(citizenid)
    if online and online.source then
        DropPlayer(online.source, 'Personaje eliminado por la administración')
        local deadline = GetGameTimer() + 5000
        while ESX.GetPlayerFromIdentifier(citizenid) and GetGameTimer() < deadline do Wait(100) end
    end

    local extra = {
        { 'owned_vehicles', 'owner' },
        { 'user_licenses', 'owner' },
        { 'billing', 'identifier' },
    }
    for i = 1, #extra do
        local tbl, col = extra[i][1], extra[i][2]
        if tableExists(tbl) then
            pcall(MySQL.update.await, ('DELETE FROM `%s` WHERE `%s` = ?'):format(tbl, col), { citizenid })
        end
    end

    local ok, affected = pcall(MySQL.update.await, 'DELETE FROM users WHERE identifier = ?', { citizenid })
    return ok and (affected or 0) > 0
end

---@return boolean
function Bridge.Login(_, _, _)
    return false
end

function Bridge.Logout(_) end

---@return table[]
function Bridge.GetCharacters(_)
    return {}
end

---@param src number
---@return boolean handled
function Bridge.RevivePlayer(src)
    if GetResourceState('esx_death') == 'started' then
        local ok = pcall(function() return exports.esx_death:Revive(src, 'admin') end)
        if ok then return true end
    end
    if GetResourceState('esx_ambulancejob') ~= 'started' then return false end
    TriggerClientEvent('esx_ambulancejob:revive', src)
    return true
end

---@param src number
---@return boolean handled
function Bridge.HealPlayer(src)
    if GetResourceState('esx_ambulancejob') ~= 'started' then return false end
    TriggerClientEvent('esx_ambulancejob:heal', src, 'big', true)
    return true
end
