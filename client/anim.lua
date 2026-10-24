if Bridge.context ~= 'client' then return end

local Anim = {}
Bridge.Anim = Anim

local RESOURCE = 'cuxial_emotes'

---@type table<string, true>
local held = {}

---@param locked boolean
---@param reason string
local function send(locked, reason)
    if GetResourceState(RESOURCE) ~= 'started' then return end
    local ok, err = pcall(function()
        exports[RESOURCE]:SetEmoteLock(locked, reason)
    end)
    if not ok then
        print(('[cuxial_bridge] ^3aviso:^7 cuxial_emotes:SetEmoteLock falló: %s'):format(tostring(err)))
    end
end

---@param reason string  motivo propio del recurso ('seat', 'office'…); cada motivo se suelta por separado
function Anim.lock(reason)
    if type(reason) ~= 'string' or held[reason] then return end
    held[reason] = true
    send(true, reason)
end

---@param reason string
function Anim.unlock(reason)
    if type(reason) ~= 'string' or not held[reason] then return end
    held[reason] = nil
    send(false, reason)
end

---@param reason string
---@param locked boolean
function Anim.set(reason, locked)
    if locked then
        Anim.lock(reason)
    else
        Anim.unlock(reason)
    end
end

function Anim.unlockAll()
    for reason in pairs(held) do
        held[reason] = nil
        send(false, reason)
    end
end

---@param reason? string  sin motivo: si este recurso tiene alguno
---@return boolean
function Anim.isHeld(reason)
    if reason then return held[reason] == true end
    return next(held) ~= nil
end

---@return boolean  bloqueado por cualquier recurso
function Anim.isLocked()
    return LocalPlayer.state.animLock ~= nil
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= RESOURCE then return end
    for reason in pairs(held) do send(true, reason) end
end)
