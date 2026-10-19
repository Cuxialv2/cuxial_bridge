if Bridge.context ~= 'server' then return end

local REGISTER_EVENT = 'cuxial_bridge:versionRegister'
local resource = GetCurrentResourceName()

---@param repository? string
---@param opts? table
function Bridge.VersionCheck(repository, opts)
    if resource == Bridge._resource then return end
    TriggerEvent(REGISTER_EVENT, resource)
end

if resource ~= Bridge._resource then return end

local DEFAULT_URL = 'https://bot-production-f7ef.up.railway.app'
local FOOTER = '  ^9Descarga en portal.cfx.re · novedades en docs.cuxial.com^7'
local FIRST_DELAY = 15000
local CACHE_TTL = 6 * 3600
local MAX_DETAILS = 3
local SEVERITY = {
    major = { '^1', 'mayor' },
    minor = { '^3', 'menor' },
    patch = { '^2', 'parche' },
}

local registered = {}
local cache, cachedAt = nil, 0
local ready = false

---@return boolean
local function enabled()
    return GetConvar('cuxial_versioncheck', '1') ~= '0'
end

---@return string
local function baseUrl()
    local base = GetConvar('cuxial_versioncheck_url', '')
    if base == '' then base = DEFAULT_URL end
    return (base:gsub('/+$', ''))
end

---@param v string
---@return integer[]
local function toParts(v)
    local p = {}
    for n in v:gmatch('%d+') do p[#p + 1] = tonumber(n) end
    return p
end

---@param a integer[]
---@param b integer[]
---@return integer
local function cmp(a, b)
    for i = 1, 3 do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

---@param cv integer[]
---@param lv integer[]
---@return string
local function severity(cv, lv)
    if (lv[1] or 0) > (cv[1] or 0) then return 'major' end
    if (lv[2] or 0) > (cv[2] or 0) then return 'minor' end
    return 'patch'
end

---@param res string
---@return boolean
local function includesBridge(res)
    for _, key in ipairs({ 'shared_script', 'server_script' }) do
        local n = GetNumResourceMetadata(res, key)
        for i = 0, n - 1 do
            local v = GetResourceMetadata(res, key, i)
            if v and v:find('@cuxial_bridge/init.lua', 1, true) then return true end
        end
    end
    return false
end

---@param res string
---@return boolean
local function tracked(res)
    return res:find('^cuxial_') ~= nil or registered[res] == true or includesBridge(res)
end

---@param res string
---@return string|nil
local function localVersion(res)
    local raw = GetResourceMetadata(res, 'version', 0)
    return raw and raw:match('%d+%.%d+%.%d+')
end

---@param path string
---@param cb fun(data: table|nil)
local function fetch(path, cb)
    PerformHttpRequest(baseUrl() .. path, function(status, response)
        if status ~= 200 or type(response) ~= 'string' then return cb(nil) end
        local ok, data = pcall(json.decode, response)
        cb(ok and type(data) == 'table' and data or nil)
    end, 'GET', '', { ['User-Agent'] = 'cuxial_bridge' })
end

---@param cb fun(list: table|nil)
local function getVersions(cb)
    if cache and os.time() - cachedAt < CACHE_TTL then return cb(cache) end
    fetch('/api/versions', function(data)
        if data then cache, cachedAt = data, os.time() end
        cb(data or cache)
    end)
end

---@param res string
---@param list table
---@return table|nil
local function compare(res, list)
    local current = localVersion(res)
    local entry = list[res] or list[res:lower()]
    local latest = type(entry) == 'table' and type(entry.version) == 'string' and entry.version:match('%d+%.%d+%.%d+')
    if not current or not latest then return nil end
    local diff = cmp(toParts(current), toParts(latest))
    if diff == 0 then return { res = res, current = current, latest = latest } end
    return {
        res = res,
        current = current,
        latest = latest,
        kind = diff > 0 and 'dev' or severity(toParts(current), toParts(latest)),
    }
end

---@param row table
---@param width integer
---@param prefix? string
local function printRow(row, width, prefix)
    local name = row.res .. (' '):rep(width - #row.res)
    local sev = SEVERITY[row.kind] or { '^9', 'dev' }
    print(('%s%s  ^9%s^7 › %s%s^7  ^9%s^7'):format(prefix or '  ', name, row.current, sev[1], row.latest, sev[2]))
    if not row.changes then return end
    for i = 1, math.min(#row.changes, MAX_DETAILS) do
        local t = row.changes[i]
        if type(t) == 'string' then
            t = t:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^[%-%*%+•]%s*', '')
            if #t > 52 then t = t:sub(1, 51) .. '…' end
            print(('    ^9%s^7'):format(t))
        end
    end
end

---@param rows table[]
---@param cb fun()
local function loadDetails(rows, cb)
    if GetConvar('cuxial_versioncheck_details', '0') ~= '1' then return cb() end
    local pending = 0
    for i = 1, #rows do
        if rows[i].kind ~= 'dev' then pending = pending + 1 end
    end
    if pending == 0 then return cb() end
    for i = 1, #rows do
        local row = rows[i]
        if row.kind ~= 'dev' then
            fetch('/api/version/' .. row.res:lower(), function(data)
                if data and type(data.changes) == 'table' then row.changes = data.changes end
                pending = pending - 1
                if pending == 0 then cb() end
            end)
        end
    end
end

---@param rows table[]
local function printBlock(rows)
    local width = 0
    for i = 1, #rows do width = math.max(width, #rows[i].res) end
    local outdated = 0
    for i = 1, #rows do
        if rows[i].kind ~= 'dev' then outdated = outdated + 1 end
    end
    if outdated > 0 then
        print(('^5[cuxial]^7 Actualizaciones disponibles (%d)'):format(outdated))
    else
        print('^5[cuxial]^7 Builds de desarrollo')
    end
    for i = 1, #rows do printRow(rows[i], width) end
    if outdated > 0 then print(FOOTER) end
end

local function startupCheck()
    if not enabled() then
        ready = true
        return
    end
    getVersions(function(list)
        ready = true
        if not list then return end
        local rows, upToDate = {}, 0
        for i = 0, GetNumResources() - 1 do
            local res = GetResourceByFindIndex(i)
            if res and GetResourceState(res) == 'started' and tracked(res) then
                local row = compare(res, list)
                if row and row.kind then
                    rows[#rows + 1] = row
                elseif row then
                    upToDate = upToDate + 1
                end
            end
        end
        if #rows == 0 then
            if upToDate > 0 and GetConvar('cuxial_versioncheck_quiet', '0') ~= '1' then
                print(('^5[cuxial]^9 %d scripts al día^7'):format(upToDate))
            end
            return
        end
        table.sort(rows, function(a, b) return a.res < b.res end)
        loadDetails(rows, function() printBlock(rows) end)
    end)
end

AddEventHandler(REGISTER_EVENT, function(res)
    if type(res) ~= 'string' then return end
    registered[res] = true
end)

AddEventHandler('onResourceStart', function(res)
    if not ready or res == resource or not enabled() then return end
    SetTimeout(3000, function()
        if not tracked(res) then return end
        getVersions(function(list)
            if not list then return end
            local row = compare(res, list)
            if not row or not row.kind then return end
            loadDetails({ row }, function()
                printRow(row, #res, '^5[cuxial]^7 ')
            end)
        end)
    end)
end)

SetTimeout(FIRST_DELAY, startupCheck)
