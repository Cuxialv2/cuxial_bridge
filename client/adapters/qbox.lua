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
    local pd = QBX and QBX.PlayerData
    if not pd then return nil end
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
    return LocalPlayer.state.isLoggedIn == true
end

function Bridge.GetJob()
    return QBX and QBX.PlayerData and normalizeJob(QBX.PlayerData.job) or nil
end

function Bridge.GetJobInfo(name)
    return exports.qbx_core:GetJob(name)
end

function Bridge.GetGang()
    return QBX and QBX.PlayerData and normalizeGang(QBX.PlayerData.gang) or nil
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

