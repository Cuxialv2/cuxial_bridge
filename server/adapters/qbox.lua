local core = exports.qbx_core

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

function Bridge.GetOfflinePlayer(cid)
    if not cid then return nil end
    local row = MySQL.single.await(
        'SELECT citizenid, name, charinfo, money, job, gang, metadata FROM players WHERE citizenid = ?',
        { cid })
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
    local p = core:GetPlayer(src)
    if not p then return 0 end
    return p.PlayerData.money[account] or 0
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
    local row = MySQL.single.await(
        ("SELECT JSON_EXTRACT(money, '$.%s') AS v FROM players WHERE citizenid = ?"):format(k), { identifier })
    return row and tonumber(row.v) or 0
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
    local count, sources = 0, {}
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local p = src and core:GetPlayer(src)
        local job = p and p.PlayerData.job
        if job and job.onduty and (job.type == jobType or job.name == jobType) then
            count = count + 1
            sources[#sources + 1] = src
        end
    end
    return count, sources
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

function Bridge.OnMoneyChange(cb)
    AddEventHandler('QBCore:Server:OnMoneyChange', cb)
end

function Bridge.GetVehiclesByName(name)
    return core:GetVehiclesByName(name)
end

function Bridge.GetVehiclesByHash(hash)
    return core:GetVehiclesByHash(hash)
end

