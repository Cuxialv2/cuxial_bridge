local PHONE = 'sd-phone'

local locked = false
local disabledByUs = false

---@return boolean
local function phoneReady()
    return GetResourceState(PHONE) == 'started'
end

local function applyPhone()
    if not phoneReady() then return end

    if locked and not disabledByUs then
        local ok, already = pcall(function() return exports[PHONE]:isDisabled() end)
        if not ok or already then return end
        disabledByUs = pcall(function() exports[PHONE]:setDisabled(true) end)
        return
    end

    if not locked and disabledByUs then
        disabledByUs = false
        pcall(function() exports[PHONE]:setDisabled(false) end)
    end
end

AddStateBagChangeHandler('animLock', ('player:%s'):format(cache.serverId), function(_, _, value)
    locked = value ~= nil
    applyPhone()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= PHONE then return end
    disabledByUs = false
    applyPhone()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not disabledByUs or not phoneReady() then return end
    pcall(function() exports[PHONE]:setDisabled(false) end)
end)

locked = LocalPlayer.state.animLock ~= nil
applyPhone()
