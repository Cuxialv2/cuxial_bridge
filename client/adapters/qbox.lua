if not QBX then
    QBX = { PlayerData = {} }

    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if ok and pd then QBX.PlayerData = pd end

    RegisterNetEvent('QBCore:Player:SetPlayerData', function(value)
        QBX.PlayerData = value or {}
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        local ok2, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
        if ok2 and data then QBX.PlayerData = data end
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        QBX.PlayerData = {}
    end)
end

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
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb(Bridge.GetPlayerData()) end)
end
function Bridge.OnPlayerUnload(cb)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() cb() end)
end
function Bridge.OnJobUpdate(cb)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) cb(normalizeJob(job)) end)
end
function Bridge.OnGangUpdate(cb)
    RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang) cb(normalizeGang(gang)) end)
end

function Bridge.OnPlayerLoggedOut(cb)
    RegisterNetEvent('qbx_core:client:playerLoggedOut', function() cb() end)
end

function Bridge.AnnouncePlayerLoaded()
    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
end

---@return boolean
function Bridge.UsesStartingApartment()
    local ok, core = pcall(lib.load, '@qbx_core.config.client')
    return ok and type(core) == 'table' and type(core.characters) == 'table'
        and core.characters.startingApartment == true
end
