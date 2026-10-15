local NS = GetCurrentResourceName()
local EV = {
    chunk  = NS .. ':bridgeMedia:chunk',
    failed = NS .. ':bridgeMedia:failed',
    resync = NS .. ':bridgeMedia:resync',
    anchor = NS .. ':bridgeMedia:anchor',
    transport = NS .. ':bridgeMedia:transport',
    begin  = NS .. ':bridgeMedia:begin',
    audio  = NS .. ':bridgeMedia:audio',
    finish = NS .. ':bridgeMedia:end',
    feed   = NS .. ':bridgeMedia:feed',
    ended  = NS .. ':bridgeMedia:ended',
}

local UPLOAD_BPS = 384 * 1024
local Media = { hosting = nil, audio = false }
Bridge.Media = Media

local function push(action, data)
    SendNUIMessage({ action = action, data = data })
end

RegisterNetEvent(EV.begin, function(data)
    if type(data) ~= 'table' or not data.id then return end
    Media.hosting = data.id
    Media.audio = data.audio == true
    push('bridgeMedia:begin', data)
end)

RegisterNetEvent(EV.audio, function(data)
    if type(data) ~= 'table' or data.id ~= Media.hosting then return end
    Media.audio = data.on == true
    push('bridgeMedia:audio', data)
end)

RegisterNetEvent(EV.finish, function(data)
    if type(data) ~= 'table' then return end
    if data.id == Media.hosting then Media.hosting = nil; Media.audio = false end
    push('bridgeMedia:end', data)
end)

RegisterNetEvent(EV.feed, function(data)
    if type(data) ~= 'table' then return end
    push('bridgeMedia:feed', data)
end)

RegisterNetEvent(EV.ended, function(data)
    if type(data) ~= 'table' then return end
    push('bridgeMedia:ended', data)
end)

RegisterNUICallback('bridgeMediaChunk', function(data, cb)
    cb(true)
    if type(data) ~= 'table' or data.id ~= Media.hosting then return end
    if type(data.chunk) ~= 'string' or data.chunk == '' then return end
    TriggerLatentServerEvent(EV.chunk, UPLOAD_BPS, { id = data.id, chunk = data.chunk, init = data.init == true, mime = data.mime })
end)

RegisterNetEvent(EV.anchor, function(data)
    if type(data) ~= 'table' or data.id ~= Media.hosting then return end
    push('bridgeMedia:anchor', data)
end)

RegisterNUICallback('bridgeMediaResync', function(data, cb)
    cb(true)
    if type(data) ~= 'table' or type(data.id) ~= 'string' then return end
    TriggerServerEvent(EV.resync, { id = data.id })
end)

RegisterNUICallback('bridgeMediaRelayToken', function(data, cb)
    if type(data) ~= 'table' then return cb(false) end
    local grant = lib.callback.await(NS .. ':bridgeMedia:token', false, { role = data.role, id = data.id, gen = data.gen })
    cb(grant or false)
end)

RegisterNUICallback('bridgeMediaTransport', function(data, cb)
    cb(true)
    if type(data) ~= 'table' or data.id ~= Media.hosting then return end
    TriggerServerEvent(EV.transport, { id = data.id, relay = data.relay == true })
end)

RegisterNetEvent(EV.transport, function(data)
    if type(data) ~= 'table' then return end
    push('bridgeMedia:transport', data)
end)

RegisterNUICallback('bridgeMediaFailed', function(data, cb)
    cb(true)
    if type(data) ~= 'table' or data.id ~= Media.hosting then return end
    TriggerServerEvent(EV.failed, { id = data.id })
end)

---@return boolean
function Media.IsHosting()
    return Media.hosting ~= nil
end

---@return boolean
function Media.IsMicOpen()
    return Media.hosting ~= nil and Media.audio
end
