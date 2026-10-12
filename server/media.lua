local NS = GetCurrentResourceName()
local EV = {
    chunk  = NS .. ':bridgeMedia:chunk',
    failed = NS .. ':bridgeMedia:failed',
    resync = NS .. ':bridgeMedia:resync',
    transport = NS .. ':bridgeMedia:transport',
    anchor = NS .. ':bridgeMedia:anchor',
    begin  = NS .. ':bridgeMedia:begin',
    audio  = NS .. ':bridgeMedia:audio',
    finish = NS .. ':bridgeMedia:end',
    feed   = NS .. ':bridgeMedia:feed',
    ended  = NS .. ':bridgeMedia:ended',
}

local Media = {}
Bridge.Media = Media

local ENC_DEFAULT = {
    width = 1280,
    bitrate = 4000000,
    fps = 24,
    codec = 'vp9',
    timesliceMs = 250,
    keyframeMs = 10000,
}

local RELAY_BPS = 384 * 1024
local MAX_CHUNK = 1024 * 1024
local MAX_GOP = 60
local MAX_GOP_BYTES = 10 * 1024 * 1024
local INGEST_WINDOW_MS = 4000
local INGEST_MAX_CHUNKS = 48

---@type table<string, table> sesiones por id
local sessions = {}
---@type table<number, string> id de la sesión que emite cada jugador
local hostOf = {}
---@type table<number, table<string, boolean>> sesiones que mira cada jugador
local viewing = {}

local seq = 0
local function newId()
    seq = seq + 1
    return ('%s-%d-%d'):format(NS, os.time() % 100000, seq)
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function alive(src)
    return src and GetPlayerName(src) ~= nil
end

local function resetCache(s)
    s.header = nil
    s.mime = nil
    s.gop = {}
    s.gopBytes = 0
end

---@param host number source del jugador que emite
---@param opts? { audio?: boolean, maxViewers?: number, bps?: number, enc?: table, tag?: string, onEnd?: fun(session: table, reason: string) }
---@return string? id
function Media.Open(host, opts)
    host = tonumber(host)
    if not alive(host) then return nil end
    opts = type(opts) == 'table' and opts or {}

    local existing = hostOf[host]
    if existing and sessions[existing] then return existing end

    local enc = {}
    for k, v in pairs(ENC_DEFAULT) do enc[k] = v end
    for k, v in pairs(type(opts.enc) == 'table' and opts.enc or {}) do enc[k] = v end

    local id = newId()
    sessions[id] = {
        id = id,
        host = host,
        tag = opts.tag,
        audio = opts.audio == true,
        maxViewers = tonumber(opts.maxViewers) or 0,
        bps = tonumber(opts.bps) or RELAY_BPS,
        enc = enc,
        onEnd = type(opts.onEnd) == 'function' and opts.onEnd or nil,
        viewers = {},
        header = nil, mime = nil, gop = {}, gopBytes = 0,
        ingestAt = 0, ingestN = 0, ingestBytes = 0,
        openedAt = os.time(),
    }
    hostOf[host] = id

    sessions[id].relayKey = Media.RelayStreamKey(id)
    TriggerClientEvent(EV.begin, host, { id = id, enc = enc, audio = sessions[id].audio })
    return id
end

---@param id string
---@return table? sesión (solo lectura)
function Media.Get(id)
    return sessions[id]
end

---@param host number
---@return string? id de la sesión que emite ese jugador
function Media.HostOf(host)
    return hostOf[tonumber(host)]
end

---@param id string
---@param reason? string
function Media.Close(id, reason)
    local s = sessions[id]
    if not s then return end
    sessions[id] = nil
    if hostOf[s.host] == id then hostOf[s.host] = nil end

    if alive(s.host) then TriggerClientEvent(EV.finish, s.host, { id = id }) end
    for src in pairs(s.viewers) do
        if viewing[src] then viewing[src][id] = nil end
        if alive(src) then TriggerClientEvent(EV.ended, src, { id = id, reason = reason or 'closed' }) end
    end
    if s.onEnd then pcall(s.onEnd, s, reason or 'closed') end
end

---@param id string
---@param on boolean
---@return boolean
function Media.SetAudio(id, on)
    local s = sessions[id]
    if not s then return false end
    on = on == true
    if s.audio == on then return true end
    s.audio = on
    if alive(s.host) then TriggerClientEvent(EV.audio, s.host, { id = id, on = on }) end
    return true
end

---@param id string
---@param src number
---@return boolean
function Media.AddViewer(id, src)
    local s = sessions[id]
    src = tonumber(src)
    if not s or not alive(src) then return false end
    if not s.viewers[src] then
        if s.maxViewers > 0 and count(s.viewers) >= s.maxViewers then return false end
        s.viewers[src] = true
        viewing[src] = viewing[src] or {}
        viewing[src][id] = true
    end

    TriggerClientEvent(EV.transport, src, { id = id, relay = s.onRelay == true })
    if s.header and not s.onRelay then
        TriggerLatentClientEvent(EV.feed, src, s.bps, { id = id, chunk = s.header, init = true, mime = s.mime })
        for _, chunk in ipairs(s.gop) do
            TriggerLatentClientEvent(EV.feed, src, s.bps, { id = id, chunk = chunk, init = false })
        end
    end
    return true
end

---@param id string
---@param src number
---@param silent? boolean no avisar al espectador (se fue él)
function Media.RemoveViewer(id, src, silent)
    local s = sessions[id]
    src = tonumber(src)
    if not s or not src or not s.viewers[src] then return end
    s.viewers[src] = nil
    if viewing[src] then viewing[src][id] = nil end
    if not silent and alive(src) then TriggerClientEvent(EV.ended, src, { id = id, reason = 'removed' }) end
end

---@param id string
---@return number
function Media.ViewerCount(id)
    local s = sessions[id]
    return s and count(s.viewers) or 0
end

local function ingestOk(s, bytes)
    local now = GetGameTimer()
    if now - s.ingestAt > INGEST_WINDOW_MS then
        s.ingestAt, s.ingestN, s.ingestBytes = now, 0, 0
    end
    s.ingestN = s.ingestN + 1
    s.ingestBytes = s.ingestBytes + bytes
    return s.ingestN <= INGEST_MAX_CHUNKS and s.ingestBytes <= s.bps * (INGEST_WINDOW_MS / 1000)
end

RegisterNetEvent(EV.chunk, function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local s = sessions[payload.id]
    if not s or s.host ~= src then return end
    local chunk = payload.chunk
    if type(chunk) ~= 'string' or chunk == '' or #chunk > MAX_CHUNK then return end
    if not ingestOk(s, #chunk) then return end

    local init = payload.init == true
    if init then
        resetCache(s)
        s.header = chunk
        if type(payload.mime) == 'string' then s.mime = payload.mime:sub(1, 64) end
    else
        s.gop[#s.gop + 1] = chunk
        s.gopBytes = s.gopBytes + #chunk

        if not s.header or #s.gop > MAX_GOP or s.gopBytes > MAX_GOP_BYTES then resetCache(s) end
    end

    local data = { id = s.id, chunk = chunk, init = init, mime = init and s.mime or nil }
    for viewer in pairs(s.viewers) do
        if alive(viewer) then
            TriggerLatentClientEvent(EV.feed, viewer, s.bps, data)
        else
            s.viewers[viewer] = nil
        end
    end
end)

RegisterNetEvent(EV.transport, function(payload)
    local src = source
    local s = type(payload) == 'table' and sessions[payload.id] or nil
    if not s or s.host ~= src then return end
    local relay = payload.relay == true and Media.RelayConfigured()
    if s.onRelay == relay then return end
    s.onRelay = relay
    resetCache(s)
    for viewer in pairs(s.viewers) do
        if alive(viewer) then TriggerClientEvent(EV.transport, viewer, { id = s.id, relay = relay }) end
    end
end)

RegisterNetEvent(EV.resync, function(payload)
    local src = source
    local s = type(payload) == 'table' and sessions[payload.id] or nil
    if not s or not s.viewers[src] then return end
    local now = GetGameTimer()
    if s.anchorAt and now - s.anchorAt < 1000 then return end
    s.anchorAt = now
    if alive(s.host) then TriggerClientEvent(EV.anchor, s.host, { id = s.id }) end
end)

RegisterNetEvent(EV.failed, function(payload)
    local src = source
    local id = type(payload) == 'table' and payload.id or nil
    local s = id and sessions[id] or nil
    if not s or s.host ~= src then return end
    Media.Close(id, 'failed')
end)

AddEventHandler('playerDropped', function()
    local src = source
    local id = hostOf[src]
    if id then Media.Close(id, 'host_left') end
    local mine = viewing[src]
    if mine then
        for sid in pairs(mine) do Media.RemoveViewer(sid, src, true) end
        viewing[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NS then return end
    for id in pairs(sessions) do Media.Close(id, 'resource_stop') end
end)

local STUN = { 'stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302' }
local TURN_TTL = 86400
local iceCache, icePending = nil, nil

local function fetchCloudflare()
    local tokenId = GetConvar('sd_cf_turn_token_id', '')
    local apiToken = GetConvar('sd_cf_turn_api_token', '')
    if tokenId == '' or apiToken == '' then return nil end
    local p = promise.new()
    PerformHttpRequest(
        ('https://rtc.live.cloudflare.com/v1/turn/keys/%s/credentials/generate-ice-servers'):format(tokenId),
        function(status, body)
            if status ~= 201 or not body then return p:resolve(nil) end
            local ok, decoded = pcall(json.decode, body)
            local list = ok and decoded and decoded.iceServers or nil
            if type(list) == 'table' and list.urls then list = { list } end
            local out = {}
            for _, entry in ipairs(type(list) == 'table' and list or {}) do
                if type(entry) == 'table' and entry.urls ~= nil then out[#out + 1] = entry end
            end
            p:resolve(#out > 0 and out or nil)
        end,
        'POST', json.encode({ ttl = TURN_TTL }),
        { ['Authorization'] = 'Bearer ' .. apiToken, ['Content-Type'] = 'application/json', ['Accept'] = 'application/json' }
    )
    return Citizen.Await(p)
end

---@return table servers
function Media.IceServers()
    if iceCache and iceCache.expires > os.time() then return iceCache.servers end
    if icePending then return Citizen.Await(icePending) end
    local p = promise.new()
    icePending = p
    local servers = {}
    for _, url in ipairs(STUN) do servers[#servers + 1] = { urls = url } end
    local ok, turn = pcall(fetchCloudflare)
    local good = ok and turn ~= nil
    if good then for _, e in ipairs(turn) do servers[#servers + 1] = e end end
    local fixed = GetConvar('sd_phone_turn_url', '')
    if fixed ~= '' then
        servers[#servers + 1] = { urls = fixed, username = GetConvar('sd_phone_turn_username', ''), credential = GetConvar('sd_phone_turn_credential', '') }
    end
    iceCache = { servers = servers, expires = os.time() + (good and (TURN_TTL - 60) or 60) }
    icePending = nil
    p:resolve(servers)
    return servers
end

---@return boolean TURN configurado (las dos convars presentes)
function Media.TurnConfigured()
    return GetConvar('sd_cf_turn_token_id', '') ~= '' and GetConvar('sd_cf_turn_api_token', '') ~= ''
end

local RELAY_APP = 'mdt:cam:'

---@return string url, string key, number ttl
local function relayConfig()
    local url = GetConvar('sd_phone_relay_url', '')
    local key = GetConvar('sd_phone_relay_key', '')
    local ttl = tonumber(GetConvar('sd_phone_relay_ttl', '45')) or 45
    if #key ~= 64 or not key:match('^[0-9a-f]+$') then key = '' end
    if not (url:match('^wss://') or url:match('^ws://')) then url = '' end
    return url, key, math.max(10, math.min(120, math.floor(ttl)))
end

---@return boolean
function Media.RelayConfigured()
    local url, key = relayConfig()
    return url ~= '' and key ~= ''
end

---@param id string
---@return string
function Media.RelayStreamKey(id)
    local clean = tostring(id):gsub('[^A-Za-z0-9_%-]', '-'):sub(1, 64)
    return RELAY_APP .. clean
end

---@param src number
---@param role string
---@param id? string sesión (publish/watch)
---@param gen? number generación del emisor (publish)
---@return table? grant { url, token, key, role, gen, ttlSeconds, expiresAt }
function Media.RelayGrant(src, role, id, gen)
    local url, key, ttl = relayConfig()
    if url == '' or key == '' then return nil end
    src = tonumber(src)
    if not alive(src) then return nil end

    local streamKey, g = '', 0
    if role == 'publish' or role == 'watch' then
        local s = id and sessions[id] or nil
        if not s then return nil end
        if role == 'publish' and s.host ~= src then return nil end
        if role == 'watch' and not s.viewers[src] then return nil end
        streamKey = s.relayKey or Media.RelayStreamKey(s.id)
        g = math.max(0, math.min(2147483647, math.floor(tonumber(gen) or 0)))
    elseif role ~= 'session' then
        return nil
    end

    local jti = exports.cuxial_bridge:MediaRandomHex(16)
    if type(jti) ~= 'string' or #jti ~= 32 then return nil end
    local now = os.time()
    local name = tostring(GetPlayerName(src) or ''):sub(1, 64)
    local claims = json.encode({
        v = 1, iss = 'sd-phone', sub = ('p%d'):format(src), src = src, name = name,
        key = streamKey, role = role, gen = g, iat = now, exp = now + ttl, jti = jti,
    })
    local token = exports.cuxial_bridge:MediaRelayToken(key, claims)
    if type(token) ~= 'string' or token == '' then return nil end
    return { url = url, token = token, key = streamKey, role = role, gen = g, ttlSeconds = ttl, expiresAt = (now + ttl) * 1000 }
end

---@param identity string
---@param name string
---@param role string 'session' | 'watch'
---@param id? string sesión (watch)
---@return table? grant
function Media.RelayGrantExternal(identity, name, role, id)
    local url, key, ttl = relayConfig()
    if url == '' or key == '' then return nil end
    if type(identity) ~= 'string' or identity == '' then return nil end
    if role ~= 'session' and role ~= 'watch' then return nil end

    local streamKey = ''
    if role == 'watch' then
        local s = id and sessions[id] or nil
        if not s then return nil end
        streamKey = s.relayKey or Media.RelayStreamKey(s.id)
    end

    local jti = exports.cuxial_bridge:MediaRandomHex(16)
    if type(jti) ~= 'string' or #jti ~= 32 then return nil end
    local now = os.time()
    local sub = 'x' .. tostring(identity):gsub('[^A-Za-z0-9_%-]', ''):sub(1, 60)
    local claims = json.encode({
        v = 1, iss = 'sd-phone', sub = sub, src = 65535, name = tostring(name or ''):sub(1, 64),
        key = streamKey, role = role, gen = 0, iat = now, exp = now + ttl, jti = jti,
    })
    local token = exports.cuxial_bridge:MediaRelayToken(key, claims)
    if type(token) ~= 'string' or token == '' then return nil end
    return { url = url, token = token, key = streamKey, role = role, gen = 0, ttlSeconds = ttl, expiresAt = (now + ttl) * 1000 }
end

lib.callback.register(NS .. ':bridgeMedia:token', function(source, data)
    if type(data) ~= 'table' then return nil end
    return Media.RelayGrant(source, data.role, data.id, data.gen)
end)
