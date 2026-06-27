local QBCore = exports['qb-core']:GetCoreObject()

local function normalizeJob(job)
    if not job then return nil end
    return {
        name = job.name, label = job.label,
        grade = job.grade and job.grade.level, gradeLabel = job.grade and job.grade.name,
        isboss = job.isboss, onduty = job.onduty, type = job.type,
    }
end
local function normalizeGang(gang)
    if not gang then return nil end
    return {
        name = gang.name, label = gang.label,
        grade = gang.grade and gang.grade.level, gradeLabel = gang.grade and gang.grade.name,
        isboss = gang.isboss,
    }
end

function Bridge.GetPlayerData()
    local pd = QBCore.Functions.GetPlayerData()
    if not pd or not pd.citizenid then return nil end
    return {
        citizenid = pd.citizenid,
        charinfo  = pd.charinfo,
        job       = normalizeJob(pd.job),
        gang      = normalizeGang(pd.gang),
        metadata  = pd.metadata,
        _raw      = pd,
    }
end

function Bridge.IsLoggedIn()
    if LocalPlayer.state.isLoggedIn ~= nil then return LocalPlayer.state.isLoggedIn == true end
    local pd = QBCore.Functions.GetPlayerData()
    return pd ~= nil and pd.citizenid ~= nil
end

function Bridge.GetJob()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and normalizeJob(pd.job) or nil
end

function Bridge.GetJobInfo(name)
    return QBCore.Shared and QBCore.Shared.Jobs and QBCore.Shared.Jobs[name] or nil
end
function Bridge.GetGang()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and normalizeGang(pd.gang) or nil
end

function Bridge.OnPlayerLoaded(cb)
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function() cb(Bridge.GetPlayerData()) end)
end
function Bridge.OnPlayerUnload(cb)
    AddEventHandler('QBCore:Client:OnPlayerUnload', function() cb() end)
end
function Bridge.OnJobUpdate(cb)
    AddEventHandler('QBCore:Client:OnJobUpdate', function(job) cb(normalizeJob(job)) end)
end
function Bridge.OnGangUpdate(cb)
    AddEventHandler('QBCore:Client:OnGangUpdate', function(gang) cb(normalizeGang(gang)) end)
end

