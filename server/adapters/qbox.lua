local core = exports.qbx_core

---@param query string
---@param params? table
---@return table?
local function first(query, params)
    local rows = MySQL.query.await(query, params)
    return rows and rows[1]
end

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

function Bridge.GetPlayer(src)
    return normalize(core:GetPlayer(src))
end

function Bridge.GetRawPlayer(src)
    return core:GetPlayer(src)
end

function Bridge.GetPlayerByCitizenId(cid)
    return normalize(core:GetPlayerByCitizenId(cid))
end

local function decode(v)
    if type(v) ~= 'string' then return v end
    local ok, t = pcall(json.decode, v)
    return ok and t or nil
end

local OFFLINE_COLUMNS = 'citizenid, name, charinfo, money, job, gang, metadata'

local function normalizeOffline(row)
    if not row then return nil end
    local job = decode(row.job) or {}
    local jobGrade = job.grade or {}
    local gang = decode(row.gang) or {}
    local gangGrade = gang.grade or {}
    return {
        source    = nil,
        citizenid = row.citizenid,
        name      = row.name,
        charinfo  = decode(row.charinfo),
        money     = decode(row.money) or {},
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
        metadata = decode(row.metadata),
    }
end

function Bridge.GetOfflinePlayer(cid)
    if not cid then return nil end
    local row = first(
        ('SELECT %s FROM players WHERE citizenid = ?'):format(OFFLINE_COLUMNS), { cid })
    return normalizeOffline(row)
end

function Bridge.GetOfflinePlayersBatch(ids)
    local out = {}
    if not ids or #ids == 0 then return out end
    local ph = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT %s FROM players WHERE citizenid IN (%s)'):format(OFFLINE_COLUMNS, ph), ids) or {}
    for _, row in ipairs(rows) do
        out[row.citizenid] = normalizeOffline(row)
    end
    return out
end

function Bridge.GetPlayers()
    return core:GetQBPlayers()
end

function Bridge.GetSource(identifier)
    return core:GetSource(identifier)
end

function Bridge.GetIdentifier(src)
    local p = core:GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

function Bridge.GetMoney(src, account)
    local value = core:GetMoney(src, account)
    return type(value) == 'number' and value or 0
end

function Bridge.AddMoney(src, account, amount, reason)
    local p = core:GetPlayer(src)
    if not p then return false end
    return p.Functions.AddMoney(account, amount, reason)
end

function Bridge.RemoveMoney(src, account, amount, reason)
    local p = core:GetPlayer(src)
    if not p then return false end
    return p.Functions.RemoveMoney(account, amount, reason)
end

local function qbAccountKey(account)
    return (account == 'cash' or account == 'bank' or account == 'crypto') and account or 'bank'
end

function Bridge.GetMoneyOffline(identifier, account)
    local k = qbAccountKey(account)
    local row = first(
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
    local p = core:GetPlayer(src)
    if not p then return nil end
    local job = p.PlayerData.job
    return {
        name = job.name, label = job.label,
        grade = job.grade.level, gradeLabel = job.grade.name,
        isboss = job.isboss, onduty = job.onduty, type = job.type,
    }
end

function Bridge.GetJobInfo(name)
    return core:GetJob(name)
end

function Bridge.GetJobs()
    return core:GetJobs()
end

function Bridge.SetJob(src, name, grade)
    return core:SetJob(src, name, grade or 0)
end

function Bridge.SetDuty(src, onDuty)
    return core:SetJobDuty(src, onDuty)
end

function Bridge.GetDutyCount(jobType)
    local seen, sources = {}, {}
    local _, byType = core:GetDutyCountType(jobType)
    local _, byName = core:GetDutyCountJob(jobType)
    for _, list in ipairs({ byType or {}, byName or {} }) do
        for _, src in ipairs(list) do
            if not seen[src] then
                seen[src] = true
                sources[#sources + 1] = src
            end
        end
    end
    return #sources, sources
end

function Bridge.GetDutyCountJob(jobName)
    return core:GetDutyCountJob(jobName)
end

function Bridge.GetGroupMembers(name, gtype)
    return core:GetGroupMembers(name, gtype or 'job')
end

function Bridge.AddPlayerToJob(src, job, grade)
    return core:AddPlayerToJob(src, job, grade or 0)
end

function Bridge.RemovePlayerFromJob(src, job)
    return core:RemovePlayerFromJob(src, job)
end

function Bridge.SetPrimaryJob(src, job, grade)
    return core:SetPlayerPrimaryJob(src, job, grade or 0)
end

function Bridge.GetGang(src)
    local p = core:GetPlayer(src)
    if not p then return nil end
    local gang = p.PlayerData.gang
    return {
        name = gang.name, label = gang.label,
        grade = gang.grade.level, gradeLabel = gang.grade.name,
        isboss = gang.isboss,
    }
end

function Bridge.SetGang(src, name, grade)
    return core:SetGang(src, name, grade or 0)
end

function Bridge.CreateGangs(gangs)
    return core:CreateGangs(gangs)
end

function Bridge.RemoveGang(name)
    return core:RemoveGang(name)
end

function Bridge.IsGradeBoss(gangName, grade)
    return core:IsGradeBoss(gangName, grade)
end

function Bridge.SetCharName(src, firstname, lastname)
    local p = core:GetPlayer(src)
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
    return core:GetMetadata(src, key)
end

function Bridge.SetMetadata(src, key, value)
    return core:SetMetadata(src, key, value)
end

function Bridge.HasPermission(src, perm)
    return core:HasPermission(src, perm)
end

function Bridge.CreateUseableItem(name, cb)
    return core:CreateUseableItem(name, cb)
end

function Bridge.Notify(src, message, type, duration)
    return core:Notify(src, message, type, duration)
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

function Bridge.OnDutyChange(cb)
    AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
        cb(src, onDuty)
    end)
end

function Bridge.OnMoneyChange(cb)
    AddEventHandler('QBCore:Server:OnMoneyChange', cb)
end

function Bridge.GetVehiclesByName(name)
    return core:GetVehiclesByName(name)
end

function Bridge.GetVehiclesByHash(hash)
    return core:GetVehiclesByHash(hash)
end

---@return table<string, table>
function Bridge.GetGangs()
    return core:GetGangs() or {}
end

---@return table<string, table>
function Bridge.GetVehicleModels()
    return core:GetVehiclesByName() or {}
end

---@param citizenid string
---@return number?
function Bridge.GetSourceByCitizenId(citizenid)
    if not citizenid then return nil end

    local p = core:GetPlayerByCitizenId(citizenid)
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

    if not core:GetOfflinePlayer(citizenid) then return false end

    core:DeleteCharacter(citizenid)
    return awaitDeleted(citizenid)
end

---@param src number
---@param citizenid? string
---@param newData? table
---@return boolean
function Bridge.Login(src, citizenid, newData)
    if type(src) ~= 'number' or src <= 0 then return false end
    return core:Login(src, citizenid, newData) == true
end

---@param src number
function Bridge.Logout(src)
    if type(src) ~= 'number' or src <= 0 then return end
    core:Logout(src)
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
        row.charinfo = decode(row.charinfo) or {}
        row.money = decode(row.money) or {}
        row.job = decode(row.job)
        row.gang = decode(row.gang)
        row.position = decode(row.position)
        row.metadata = decode(row.metadata) or {}
    end

    return rows
end
