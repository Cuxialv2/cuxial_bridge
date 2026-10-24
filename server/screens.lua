if Bridge.context ~= 'server' then return end

local Screens = {}
Bridge.Screens = Screens

local RESOURCE = 'cuxial_screens'
local NAME = '^[%w_%-%.:]+$'

---@type table<string, table>
local apps = {}
---@type table<string, table>
local screens = {}
---@type table<string, table<string, fun(src: integer, payload: any, session: table): any, string?, string?>>
local handlers = {}
local listening = false

---@return boolean
function Screens.IsAvailable()
    return GetResourceState(RESOURCE) == 'started'
end

---@return boolean  exports listos: 'started', o 'starting' dentro de su onResourceStart (re-registro)
local function reachable()
    local state = GetResourceState(RESOURCE)
    return state == 'started' or state == 'starting'
end

---@param name string
---@return boolean ok
---@return any result
---@return any extra
local function call(name, ...)
    if not reachable() then return false, nil end
    local args = table.pack(...)
    local ok, result, extra = pcall(function()
        local api = exports[RESOURCE]
        return api[name](api, table.unpack(args, 1, args.n))
    end)
    if not ok then
        print(('[cuxial_bridge] ^3aviso:^7 cuxial_screens:%s falló: %s'):format(name, tostring(result)))
        return false, nil
    end
    return true, result, extra
end

---@param appId string
---@param method string
---@param src integer
---@param payload any
---@param session table
---@return table
local function dispatch(appId, method, src, payload, session)
    local fn = handlers[appId] and handlers[appId][method]
    if not fn then return { ok = false, error = 'error_method' } end
    local ok, data, err, message = pcall(fn, src, payload, session)
    if not ok then
        print(('[cuxial_bridge] ^1error:^7 app %s:%s: %s'):format(appId, method, tostring(data)))
        return { ok = false, error = 'error_app_failed' }
    end
    if err ~= nil then return { ok = false, error = tostring(err), message = message } end
    return { ok = true, data = data }
end

---@param id string
---@return boolean
---@return string?
local function send(id)
    local ok, done, err = call('RegisterApp', apps[id], dispatch)
    if not ok then return false, 'unavailable' end
    return done == true, err
end

local function listen()
    if listening then return end
    listening = true
    AddEventHandler('onResourceStart', function(resource)
        if resource ~= RESOURCE then return end
        for id in pairs(apps) do send(id) end
        for id, def in pairs(screens) do
            local ok, done, err = call('RegisterScreen', def)
            if not ok or done ~= true then
                print(('[cuxial_bridge] ^3aviso:^7 pantalla %s sin registrar en cuxial_screens: %s'):format(id, tostring(err)))
            end
        end
    end)
end

---@class BridgeScreensApp
---@field id string
---@field label string
---@field icon? string
---@field page string
---@field size? { w: integer, h: integer }
---@field minSize? { w: integer, h: integer }
---@field access? { jobs?: table<string, integer>, gangs?: table<string, integer>, boss?: boolean }
---@field screens? string[]
---@field tags? string[]
---@field pinned? boolean
---@field desktop? boolean
---@field mirror? boolean    false = en el espejo de cuxial_screens los demás ven una tarjeta, no la app

---@param def BridgeScreensApp
---@return boolean ok
---@return string? error
function Screens.registerApp(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or not def.id:match('^[%w_%-]+$') then return false, 'id' end
    apps[def.id] = def
    handlers[def.id] = handlers[def.id] or {}
    listen()
    if not Screens.IsAvailable() then return true, 'pending' end
    return send(def.id)
end

---@param id string
---@return boolean
function Screens.unregisterApp(id)
    if not apps[id] then return false end
    apps[id] = nil
    handlers[id] = nil
    local ok, done = call('UnregisterApp', id)
    return ok and done == true
end

---@param appId string
---@param method string
---@param fn fun(src: integer, payload: any, session: { screen: string, cid: string, app: string }): any, string?, string?
function Screens.onCall(appId, method, fn)
    if type(appId) ~= 'string' or type(method) ~= 'string' or not method:match(NAME) then
        error('[cuxial_bridge] Screens.onCall: appId y method deben ser texto (method: letras, números, _ - . :)', 2)
    end
    handlers[appId] = handlers[appId] or {}
    handlers[appId][method] = fn
end

---@param src integer
---@param appId string
---@param event string
---@param data? any
---@return boolean
function Screens.push(src, appId, event, data)
    local ok, done = call('Push', src, appId, event, data)
    return ok and done == true
end

---@param src integer
---@param appId string
---@param title string
---@param body? string
---@return boolean
function Screens.notify(src, appId, title, body)
    local ok, done = call('Notify', src, appId, { title = title, body = body })
    return ok and done == true
end

---@param def table  definición de pantalla de cuxial_screens (docs/contracts/screens.md); se vuelve a registrar si cuxial_screens reinicia
---@return boolean ok
---@return string? error
function Screens.registerScreen(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or #def.id < 1 then return false, 'id' end
    screens[def.id] = def
    listen()
    if not Screens.IsAvailable() then return true, 'pending' end
    local ok, done, err = call('RegisterScreen', def)
    if not ok then return false, 'unavailable' end
    return done == true, err
end

---@param id string
---@return boolean
function Screens.removeScreen(id)
    if not screens[id] then return false end
    screens[id] = nil
    local ok, done = call('RemoveScreen', id)
    return ok and done == true
end

---@param src integer
---@return { screen: string, cid: string, unlocked: boolean, apps: string[] }?
function Screens.getSession(src)
    local ok, info = call('GetSessionInfo', src)
    return ok and info or nil
end

---@param src integer
function Screens.closeFor(src)
    call('CloseFor', src)
end
