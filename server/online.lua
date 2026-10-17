---@class BridgeOnlineEntry
---@field src integer
---@field cid string
---@field job string?
---@field grade integer
---@field duty boolean
---@field boss boolean
---@field gang string?
---@field gangGrade integer

---@type table<integer, BridgeOnlineEntry>
local online = {}
---@type table<string, integer>
local byCid = {}
local started = false

---@param v any
---@return integer
local function level(v)
    if type(v) == 'table' then v = v.level end
    return math.floor(tonumber(v) or 0)
end

---@param src integer
local function drop(src)
    local e = online[src]
    if e and byCid[e.cid] == src then byCid[e.cid] = nil end
    online[src] = nil
end

---@param src integer
local function load(src)
    local p = Bridge.GetPlayer(src)
    if not p or not p.citizenid then
        drop(src)
        return
    end
    local job, gang = p.job or {}, p.gang or {}
    local prev = online[src]
    if prev and prev.cid ~= p.citizenid then drop(src) end
    online[src] = {
        src = src,
        cid = p.citizenid,
        job = job.name,
        grade = level(job.grade),
        duty = job.onduty == true,
        boss = job.isboss == true,
        gang = gang.name,
        gangGrade = level(gang.grade),
    }
    byCid[p.citizenid] = src
end

local function rescan()
    local seen = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then
            seen[src] = true
            load(src)
        end
    end
    for src in pairs(online) do
        if not seen[src] then drop(src) end
    end
end

local function start()
    if started then return end
    started = true

    Bridge.OnCharacterLoaded(function(src) load(src) end)
    Bridge.OnPlayerLoaded(function(src) load(src) end)
    Bridge.OnPlayerUnload(function(src) drop(tonumber(src) or -1) end)
    AddEventHandler('playerDropped', function() drop(source) end)

    Bridge.OnJobUpdate(function(src, job)
        local e = online[tonumber(src) or -1]
        if not e or type(job) ~= 'table' then return load(tonumber(src) or -1) end
        e.job = job.name
        e.grade = level(job.grade)
        e.boss = job.isboss == true
        if job.onduty ~= nil then e.duty = job.onduty == true end
    end)
    Bridge.OnGangUpdate(function(src, gang)
        local e = online[tonumber(src) or -1]
        if not e or type(gang) ~= 'table' then return end
        e.gang = gang.name
        e.gangGrade = level(gang.grade)
    end)
    Bridge.OnDutyChange(function(src, onDuty)
        local e = online[tonumber(src) or -1]
        if e then e.duty = onDuty == true end
    end)

    rescan()
    CreateThread(function()
        while true do
            Wait(300000)
            rescan()
        end
    end)
end

---Conectados con personaje cargado, en memoria y al día por eventos (no llama al framework por jugador).
---No modificar la tabla devuelta.
---@return table<integer, BridgeOnlineEntry>
function Bridge.OnlinePlayers()
    start()
    return online
end

---@return integer
function Bridge.OnlineCount()
    start()
    local n = 0
    for _ in pairs(online) do n = n + 1 end
    return n
end

---@param src integer
---@return BridgeOnlineEntry?
function Bridge.OnlineEntry(src)
    start()
    return online[src]
end

---@param cid string
---@return integer?
function Bridge.OnlineSource(cid)
    start()
    return byCid[cid]
end

---@param jobs string|table<string, any>|string[]  un trabajo, un set {name=true} o una lista
---@param onDutyOnly? boolean
---@return integer[] sources
function Bridge.OnlineByJob(jobs, onDutyOnly)
    start()
    local set = jobs
    if type(jobs) == 'string' then
        set = { [jobs] = true }
    elseif type(jobs) == 'table' and jobs[1] ~= nil then
        set = {}
        for _, j in ipairs(jobs) do set[j] = true end
    end
    local out = {}
    for src, e in pairs(online) do
        if e.job and set[e.job] and (not onDutyOnly or e.duty) then out[#out + 1] = src end
    end
    return out
end

---@param gang string
---@return integer[] sources
function Bridge.OnlineByGang(gang)
    start()
    local out = {}
    for src, e in pairs(online) do
        if e.gang == gang then out[#out + 1] = src end
    end
    return out
end
