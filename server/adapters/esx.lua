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

local function normalize(xPlayer)
    if not xPlayer then return nil end
    local job = xPlayer.getJob() or {}
    local meta = xPlayer.getMeta and xPlayer.getMeta()
    if type(meta) ~= 'table' then meta = {} end
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
    local row = MySQL.single.await(
        ("SELECT JSON_EXTRACT(accounts, '$.%s') AS v FROM users WHERE identifier = ?"):format(k), { identifier })
    return row and tonumber(row.v) or 0
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
function Bridge.SetGang(src, name, grade)
    local p = ESX.GetPlayerFromId(src)
    if not p then return false end
    p.setMeta(GANG_META_KEY, { name = name, label = name, grade = grade or 0, isboss = (grade or 0) == 0 })
    return true
end
function Bridge.CreateGangs() end
function Bridge.RemoveGang() end
function Bridge.IsGradeBoss(_, grade) return (grade or 0) == 0 end

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

function Bridge.OnMoneyChange(_) end

function Bridge.GetVehiclesByName(_) return {} end
function Bridge.GetVehiclesByHash(_) return {} end

