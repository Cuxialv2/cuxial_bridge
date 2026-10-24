if Bridge.context ~= 'client' then return end

local Screens = {}
Bridge.Screens = Screens

local RESOURCE = 'cuxial_screens'

---@return boolean
function Screens.IsAvailable()
    return GetResourceState(RESOURCE) == 'started'
end

---@param name string
---@return any
local function call(name, ...)
    if not Screens.IsAvailable() then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        local api = exports[RESOURCE]
        return api[name](api, table.unpack(args, 1, args.n))
    end)
    if not ok then
        print(('[cuxial_bridge] ^3aviso:^7 cuxial_screens:%s falló: %s'):format(name, tostring(result)))
        return nil
    end
    return result
end

---@param screenId string
---@return boolean
function Screens.open(screenId)
    return call('Use', screenId) == true
end

function Screens.close()
    call('Close')
end

---@return boolean
function Screens.isUsing()
    return call('IsUsing') == true
end

---@return string?
function Screens.current()
    return call('Current')
end
