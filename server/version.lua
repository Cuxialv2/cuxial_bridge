if Bridge.context ~= 'server' then return end

local checked = {}

---@param v string
---@return integer[]
local function toParts(v)
    local p = {}
    for n in v:gmatch('%d+') do p[#p + 1] = tonumber(n) end
    return p
end

---@param a integer[]
---@param b integer[]
---@return integer  -1 si a<b, 0 igual, 1 si a>b
local function cmp(a, b)
    for i = 1, 3 do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

---@param cv integer[]
---@param lv integer[]
---@return string label, string color
local function severity(cv, lv)
    if (lv[1] or 0) > (cv[1] or 0) then return 'MAJOR', '^1' end
    if (lv[2] or 0) > (cv[2] or 0) then return 'MINOR', '^3' end
    return 'PATCH', '^2'
end

---@param body string|nil
---@param maxLines integer
---@return string[]|nil
local function formatChangelog(body, maxLines)
    if type(body) ~= 'string' or body == '' then return nil end
    body = body:gsub('\r\n', '\n')
    local out = {}
    for line in body:gmatch('[^\n]+') do
        local t = line:gsub('^%s+', ''):gsub('%s+$', '')
        if t ~= '' and not t:find('^%*%*Full Changelog') and not t:find('^%-%-%-+$') then
            t = t:gsub('^#+%s*', '')
            t = t:gsub('^[%-%*%+]%s+', '• ')
            t = t:gsub('%*%*', ''):gsub('`', '')
            out[#out + 1] = t
            if #out >= maxLines then
                out[#out + 1] = '…'
                break
            end
        end
    end
    return out[1] and out or nil
end

local RULE = ('─'):rep(62)

---@param resource string
---@param current string
---@param latest string
---@param data table
---@param maxLines integer
local function printBanner(resource, current, latest, data, maxLines)
    local sev, col = severity(toParts(current), toParts(latest))
    print(('%s%s^0'):format(col, RULE))
    print((' ^7%s   v%s ^7→ %sv%s^7   %s[%s]^0'):format(resource, current, col, latest, col, sev))

    local lines = formatChangelog(data.body, maxLines)
    if lines then
        print(('%s%s^0'):format(col, RULE))
        local title = data.name and data.name ~= '' and data.name or ('v' .. latest)
        print((' ^7Novedades (%s):'):format(title))
        for i = 1, #lines do
            print(('   ^7%s'):format(lines[i]))
        end
    end

    print(('%s%s^0'):format(col, RULE))
    print((' ^7Descarga: ^5%s^0'):format(data.html_url or ('https://github.com/' .. resource)))
    print(('%s%s^0'):format(col, RULE))
end

---@param repository string  'owner/repo'
---@param opts? { changelog?: boolean, maxLines?: integer }
function Bridge.VersionCheck(repository, opts)
    if type(repository) ~= 'string' then return end
    opts = opts or {}
    local maxLines = tonumber(opts.maxLines) or 10
    local resource = GetInvokingResource() or GetCurrentResourceName()

    if checked[resource] then return end
    checked[resource] = true

    local raw = GetResourceMetadata(resource, 'version', 0)
    local current = raw and raw:match('%d+%.%d+%.%d+')
    if not current then
        return print(("^3[cuxial_bridge]^7 no se pudo leer la versión de ^5%s^7^0"):format(resource))
    end

    SetTimeout(1000, function()
        PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(repository), function(status, response)
            if status == 403 then
                return print(('^3[cuxial_bridge]^7 GitHub rate-limit al chequear ^5%s^7^0'):format(resource))
            end
            if status ~= 200 or not response then return end

            local ok, data = pcall(json.decode, response)
            if not ok or type(data) ~= 'table' or data.prerelease or not data.tag_name then return end

            local latest = data.tag_name:match('%d+%.%d+%.%d+')
            if not latest then return end

            local diff = cmp(toParts(current), toParts(latest))
            if diff == 0 then return end
            if diff > 0 then
                return print(("^2[cuxial_bridge]^7 %s está en ^2v%s^7 (release publicada: v%s, build de desarrollo)^0")
                    :format(resource, current, latest))
            end

            if opts.changelog == false then data.body = nil end
            printBanner(resource, current, latest, data, maxLines)
        end, 'GET', '', {
            ['User-Agent'] = resource,
            ['Accept'] = 'application/vnd.github+json',
        })
    end)
end
