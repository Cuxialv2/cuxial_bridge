local QBCore = exports['qb-core']:GetCoreObject()

local function normalize(p)
    if not p or not p.PlayerData then return nil end
    local pd = p.PlayerData
    local job = pd.job or {}
    local jobGrade = job.grade or {}
    local gang = pd.gang or {}
    local gangGrade = gang.grade or {}
    return {
        source    = pd.source,
        citizenid = pd.citizenid,
        name      = pd.name,
        charinfo  = pd.charinfo,
        money     = pd.money,
        job = {
            name = job.name, label = job.label,
            grade = jobGrade.level, gradeLabel = jobGrade.name,
            isboss = job.isboss, onduty = job.onduty, type = job.type,
        },
        gang = {
            name = gang.name, label = gang.label,
            grade = gangGrade.level, gradeLabel = gangGrade.name,
            isboss = gang.isboss,
        },
        metadata = pd.metadata,
        _raw = p,
    }
end

Bridge._normalize = normalize

function Bridge.GetPlayer(src) return normalize(QBCore.Functions.GetPlayer(src)) end
function Bridge.GetRawPlayer(src) return QBCore.Functions.GetPlayer(src) end
function Bridge.GetPlayerByCitizenId(cid) return normalize(QBCore.Functions.GetPlayerByCitizenId(cid)) end

local function decodeJson(v)
    if type(v) ~= 'string' then return v end
    local ok, t = pcall(json.decode, v)
    return ok and t or nil
end

function Bridge.GetOfflinePlayer(cid)
    if not cid then return nil end
    local row = MySQL.single.await(
        'SELECT citizenid, name, charinfo, money, job, gang, metadata FROM players WHERE citizenid = ?',
        { cid })
    if not row then return nil end
    local job = decodeJson(row.job) or {}
    local jobGrade = job.grade or {}
    local gang = decodeJson(row.gang) or {}
    local gangGrade = gang.grade or {}
    return {
        source    = nil,
        citizenid = row.citizenid,
        name      = row.name,
        charinfo  = decodeJson(row.charinfo),
        money     = decodeJson(row.money) or {},
        job = {
            name = job.name, label = job.label,
            grade = jobGrade.level, gradeLabel = jobGrade.name,
            isboss = job.isboss, onduty = job.onduty, type = job.type,
        },
        gang = {
            name = gang.name, label = gang.label,
            grade = gangGrade.level, gradeLabel = gangGrade.name,
            isboss = gang.isboss,
        },
        metadata = decodeJson(row.metadata),
    }
end
function Bridge.GetPlayers() return QBCore.Functions.GetQBPlayers() end
function Bridge.GetSource(identifier)
    return QBCore.Functions.GetSource(identifier)
end
function Bridge.GetIdentifier(src)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

function Bridge.GetMoney(src, account)
    local p = QBCore.Functions.GetPlayer(src)
    return p and (p.PlayerData.money[account] or 0) or 0
end
function Bridge.AddMoney(src, account, amount, reason)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.Functions.AddMoney(account, amount, reason) or false
end
function Bridge.RemoveMoney(src, account, amount, reason)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.Functions.RemoveMoney(account, amount, reason) or false
end

local function qbAccountKey(account)
    return (account == 'cash' or account == 'bank' or account == 'crypto') and account or 'bank'
end

function Bridge.GetMoneyOffline(identifier, account)
    local k = qbAccountKey(account)
    local row = MySQL.single.await(
        ("SELECT JSON_EXTRACT(money, '$.%s') AS v FROM players WHERE citizenid = ?"):format(k), { identifier })
    return row and tonumber(row.v) or 0
end

---@param identifier string
---@return table<string, number>
function Bridge.GetAllMoneyOffline(identifier)
    local out = {}
    if type(identifier) ~= 'string' or identifier == '' then return out end
    local rows = MySQL.query.await('SELECT money FROM players WHERE citizenid = ? LIMIT 1', { identifier })
    local raw = rows and rows[1] and rows[1].money
    if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        raw = ok and decoded or nil
    end
    if type(raw) ~= 'table' then return out end
    for account, amount in pairs(raw) do
        out[account] = tonumber(amount) or 0
    end
    return out
end

function Bridge.AddMoneyOffline(identifier, account, amount, _reason)
    local k = qbAccountKey(account)
    local affected = MySQL.update.await(
        ("UPDATE players SET money = JSON_SET(money, '$.%s', COALESCE(JSON_EXTRACT(money, '$.%s'), 0) + ?) WHERE citizenid = ?"):format(k, k),
        { amount, identifier })
    return (affected or 0) > 0
end

function Bridge.RemoveMoneyOffline(identifier, account, amount, _reason)
    local k = qbAccountKey(account)
    local affected = MySQL.update.await(
        ("UPDATE players SET money = JSON_SET(money, '$.%s', JSON_EXTRACT(money, '$.%s') - ?) WHERE citizenid = ? AND JSON_EXTRACT(money, '$.%s') >= ?"):format(k, k, k),
        { amount, identifier, amount })
    return (affected or 0) > 0
end

function Bridge.GetJob(src)
    local p = QBCore.Functions.GetPlayer(src)
    if not p then return nil end
    local job = p.PlayerData.job
    return {
        name = job.name, label = job.label,
        grade = job.grade.level, gradeLabel = job.grade.name,
        isboss = job.isboss, onduty = job.onduty, type = job.type,
    }
end

function Bridge.GetJobInfo(name)
    return QBCore.Shared.Jobs and QBCore.Shared.Jobs[name] or nil
end

function Bridge.GetJobs()
    return QBCore.Shared.Jobs or {}
end

function Bridge.SetJob(src, name, grade)
    local p = QBCore.Functions.GetPlayerByCitizenId(src)
    return p and p.Functions.SetJob(name, grade or 0) or false
end

function Bridge.SetDuty(src, onDuty)
    local p = QBCore.Functions.GetPlayer(src)
    if not p then return false end
    return p.Functions.SetJobDuty(onDuty)
end

function Bridge.GetDutyCount(jobType)
    local count, sources = 0, {}
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local p = QBCore.Functions.GetPlayer(src)
        if p then
            local job = p.PlayerData.job
            if job and job.onduty and (job.type == jobType or job.name == jobType) then
                count = count + 1
                sources[#sources + 1] = src
            end
        end
    end
    return count, sources
end

function Bridge.GetDutyCountJob(jobName)
    local players, count = QBCore.Functions.GetPlayersOnDuty(jobName)
    return count, players
end

function Bridge.GetGroupMembers(name)
    local players = QBCore.Functions.GetPlayersByJob(name, false)
    return players
end

function Bridge.AddPlayerToJob()
    print('[cuxial_bridge] ^3AddPlayerToJob^7: multi-job no soportado en qb-core base (requiere qb-multijob)')
    return false
end
function Bridge.RemovePlayerFromJob()
    print('[cuxial_bridge] ^3RemovePlayerFromJob^7: multi-job no soportado en qb-core base (requiere qb-multijob)')
    return false
end
function Bridge.SetPrimaryJob(src, job, grade) return Bridge.SetJob(src, job, grade) end

function Bridge.GetGang(src)
    local p = QBCore.Functions.GetPlayer(src)
    if not p then return nil end
    local gang = p.PlayerData.gang
    return {
        name = gang.name, label = gang.label,
        grade = gang.grade.level, gradeLabel = gang.grade.name,
        isboss = gang.isboss,
    }
end
function Bridge.SetGang(src, name, grade)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.Functions.SetGang(name, grade or 0) or false
end

function Bridge.CreateGangs(gangs)
    for name, data in pairs(gangs) do
        pcall(function() QBCore.Functions.AddGang(name, data) end)
    end
end
function Bridge.RemoveGang(name)
    local ok = pcall(function() QBCore.Functions.RemoveGang(name) end)
    return ok
end
function Bridge.IsGradeBoss(gangName, grade)
    local g = QBCore.Shared.Gangs[gangName]
    return g and g.grades[grade] and g.grades[grade].isboss or false
end

function Bridge.SetCharName(src, firstname, lastname)
    local p = QBCore.Functions.GetPlayer(src)
    if not p then return false end
    local charinfo = p.PlayerData.charinfo or {}
    if firstname and firstname ~= '' then charinfo.firstname = firstname end
    if lastname and lastname ~= '' then charinfo.lastname = lastname end
    p.Functions.SetPlayerData('charinfo', charinfo)
    p.Functions.SetMetaData('firstname', charinfo.firstname)
    p.Functions.SetMetaData('lastname', charinfo.lastname)
    if p.Functions.Save then p.Functions.Save() end
    if p.Functions.UpdatePlayerData then p.Functions.UpdatePlayerData(false) end
    TriggerClientEvent('QBCore:Player:UpdatePlayerData', src)
    return charinfo
end

function Bridge.GetMetadata(src, key)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.PlayerData.metadata[key] or nil
end
function Bridge.SetMetadata(src, key, value)
    local p = QBCore.Functions.GetPlayer(src)
    return p and p.Functions.SetMetaData(key, value) or false
end

function Bridge.HasPermission(src, perm) return QBCore.Functions.HasPermission(src, perm) end

function Bridge.CreateUseableItem(name, cb) return QBCore.Functions.CreateUseableItem(name, cb) end

function Bridge.Notify(src, message, type, duration)
    TriggerClientEvent('QBCore:Notify', src, message, type, duration)
end

function Bridge.OnPlayerLoaded(cb)
    RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
        cb(source)
    end)
end

function Bridge.OnCharacterLoaded(cb)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source
        if type(src) == 'number' then cb(src) end
    end)
end

function Bridge.OnPlayerUnload(cb)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        cb(src)
    end)
end

function Bridge.OnJobUpdate(cb)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
        cb(src, job)
    end)
end

function Bridge.OnGangUpdate(cb)
    AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang)
        cb(src, gang)
    end)
end

function Bridge.OnMoneyChange(cb)
    AddEventHandler('QBCore:Server:OnMoneyChange', cb)
end

function Bridge.GetVehiclesByName(name)
    local cat = QBCore.Shared.Vehicles or {}
    if name == nil then return cat end
    return cat[name]
end
function Bridge.GetVehiclesByHash(hash)
    for _, v in pairs(QBCore.Shared.Vehicles or {}) do
        if v.hash == hash then return v end
    end
    return nil
end

---@return table<string, table>
function Bridge.GetGangs()
    return QBCore.Shared.Gangs or {}
end

---@return table<string, table>
function Bridge.GetVehicleModels()
    return QBCore.Shared.Vehicles or {}
end

---@param citizenid string
---@return number?
function Bridge.GetSourceByCitizenId(citizenid)
    if not citizenid then return nil end

    local p = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    local src = p and p.PlayerData and p.PlayerData.source

    return (type(src) == 'number' and src > 0) and src or nil
end

---@param citizenid string
---@return boolean gone
local function awaitDeleted(citizenid)
    local deadline = GetGameTimer() + 5000
    while GetGameTimer() < deadline do
        if not Bridge.GetOfflinePlayer(citizenid) then return true end
        Wait(100)
    end
    return false
end

---@param citizenid string
---@return boolean
function Bridge.DeleteCharacter(citizenid)
    if not citizenid or citizenid == '' then return false end

    local remove = QBCore.Player.ForceDeleteCharacter
    if type(remove) ~= 'function' then return false end

    remove(citizenid)
    return awaitDeleted(citizenid)
end

---@param src number
---@param citizenid? string
---@param newData? table
---@return boolean
function Bridge.Login(src, citizenid, newData)
    if type(src) ~= 'number' or src <= 0 then return false end
    return QBCore.Player.Login(src, citizenid, newData) == true
end

---@param src number
function Bridge.Logout(src)
    if type(src) ~= 'number' or src <= 0 then return end
    QBCore.Player.Logout(src)
end

---@param src number
---@return table[]
function Bridge.GetCharacters(src)
    local license2 = GetPlayerIdentifierByType(src, 'license2')
    local license = GetPlayerIdentifierByType(src, 'license')
    if not license2 and not license then return {} end

    local rows = MySQL.query.await([[
        SELECT citizenid, cid, charinfo, money, job, gang, position, metadata
        FROM players WHERE license = ? OR license = ? ORDER BY cid
    ]], { license2 or '', license or '' }) or {}

    for i = 1, #rows do
        local row = rows[i]
        row.charinfo = decodeJson(row.charinfo) or {}
        row.money = decodeJson(row.money) or {}
        row.job = decodeJson(row.job)
        row.gang = decodeJson(row.gang)
        row.position = decodeJson(row.position)
        row.metadata = decodeJson(row.metadata) or {}
    end

    return rows
end
