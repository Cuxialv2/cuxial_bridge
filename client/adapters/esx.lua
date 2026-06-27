local ESX = exports.es_extended:getSharedObject()

local function normalizeJob(job)
    if not job then return nil end
    return {
        name = job.name, label = job.label,
        grade = job.grade, gradeLabel = job.grade_label,
        isboss = job.grade_name == 'boss',
        onduty = job.onDuty, type = job.name,
    }
end

function Bridge.GetPlayerData()
    local pd = ESX.GetPlayerData and ESX.GetPlayerData() or ESX.PlayerData
    if not pd then return nil end
    return {
        citizenid = pd.identifier,
        charinfo  = { firstname = pd.firstName, lastname = pd.lastName },
        job       = normalizeJob(pd.job),
        gang      = { name = 'none', label = 'No Gang', grade = 0, isboss = false },
        metadata  = pd.metadata or {},
        _raw      = pd,
    }
end

function Bridge.IsLoggedIn()
    return ESX.IsPlayerLoaded and ESX.IsPlayerLoaded() or false
end

function Bridge.GetJob()
    local pd = ESX.GetPlayerData and ESX.GetPlayerData() or ESX.PlayerData
    return pd and normalizeJob(pd.job) or nil
end

function Bridge.GetJobInfo(name)
    local job = Bridge.GetJob()
    return (job and job.name == name) and job or nil
end
function Bridge.GetGang()
    return { name = 'none', label = 'No Gang', grade = 0, isboss = false }
end

function Bridge.OnPlayerLoaded(cb)
    RegisterNetEvent('esx:playerLoaded', function() cb(Bridge.GetPlayerData()) end)
end
function Bridge.OnPlayerUnload(cb)
    RegisterNetEvent('esx:onPlayerLogout', function() cb() end)
end
function Bridge.OnJobUpdate(cb)
    RegisterNetEvent('esx:setJob', function(job) cb(normalizeJob(job)) end)
end
function Bridge.OnGangUpdate(_)

end

RegisterNetEvent('cuxial_bridge:internal:setDead', function(isDown)
    if ESX.SetPlayerData then ESX.SetPlayerData('dead', isDown == true) end
end)

