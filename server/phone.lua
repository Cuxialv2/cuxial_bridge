if Bridge.context ~= 'server' then return end

local Phone = {}
Bridge.Phone = Phone

local RESOURCE = 'sd-phone'
local COMPANY_EVENT = 'sd-phone:server:services:message'
local DEFAULT_NUMBER = '555'
local MAX_TEXT = 400

---@type table<string, fun(src: number, text: string, number: string, message: table)[]>
local companyHandlers = {}
local listening = false

---@return boolean
function Phone.IsAvailable()
    return GetResourceState(RESOURCE) == 'started'
end

---@param name string
---@return boolean ok
---@return any result
local function call(name, ...)
    if not Phone.IsAvailable() then return false, nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        local api = exports[RESOURCE]
        return api[name](api, table.unpack(args, 1, args.n))
    end)
    if not ok then
        print(('[cuxial_bridge] ^3aviso:^7 sd-phone:%s falló: %s'):format(name, tostring(result)))
        return false, nil
    end
    return true, result
end

---@param value any
---@return string
local function text(value)
    local s = tostring(value or '')
    if #s > MAX_TEXT then s = s:sub(1, MAX_TEXT) end
    return s
end

---@param value any
---@return string
local function digits(value)
    return (tostring(value or ''):gsub('%D', ''))
end

---@param src number
---@return boolean
function Phone.HasPhone(src)
    if type(src) ~= 'number' or src <= 0 then return false end
    local ok, color = call('hasPhone', src)
    return ok and color ~= nil and color ~= false
end

---@param src number
---@return string?
function Phone.GetNumber(src)
    if type(src) ~= 'number' or src <= 0 then return nil end
    local ok, number = call('getPhoneNumber', src)
    number = ok and digits(number) or ''
    return number ~= '' and number or nil
end

---@param src number
---@param title string
---@param body string
---@param app? string
---@return boolean sent
function Phone.Notify(src, title, body, app)
    if type(src) ~= 'number' or src <= 0 then return false end
    local ok, sent = call('notify', src, {
        title = text(title), body = text(body), app = app or 'messages', appId = app or 'messages', time = 'now',
    })
    return ok and sent == true
end

---@param src number
---@param from string  nombre del remitente
---@param body string
---@param senderNumber? string|number  código corto del hilo (por defecto '555')
---@return boolean sent
function Phone.SendSystemMessage(src, from, body, senderNumber)
    local target = Phone.GetNumber(src)
    if not target then return false end
    local sender = digits(senderNumber)
    local ok, sent = call('sendSystemMessage', sender ~= '' and sender or DEFAULT_NUMBER, text(from), target, text(body))
    return ok and sent == true
end

---@param src number
---@param from string
---@param coords vector3|{ x: number, y: number }
---@param senderNumber? string|number
---@param label? string
---@return boolean sent
function Phone.SendLocation(src, from, coords, senderNumber, label)
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return false end
    local x, y = tonumber(coords.x), tonumber(coords.y)
    if not x or not y then return false end
    local target = Phone.GetNumber(src)
    if not target then return false end
    local sender = digits(senderNumber)
    local ok, sent = call('sendLocation', sender ~= '' and sender or DEFAULT_NUMBER, text(from), target, x, y,
        { label = label and text(label) or text(from) })
    return ok and sent == true
end

---@param message any
local function dispatch(message)
    if type(message) ~= 'table' or type(message.job) ~= 'string' then return end
    local list = companyHandlers[message.job]
    if not list then return end
    local src = tonumber(message.source)
    if not src or src <= 0 or not GetPlayerName(src) then return end
    local number = digits(message.number)
    if number == '' or Phone.GetNumber(src) ~= number then return end
    local body = text(message.body)
    for i = 1, #list do
        local ok, err = pcall(list[i], src, body, number, message)
        if not ok then print(('[cuxial_bridge] ^1Phone.OnCompanyMessage (%s):^7 %s'):format(message.job, tostring(err))) end
    end
end

---@param jobName string  campo `job` de la compañía en configs/services.lua de sd-phone
---@param cb fun(src: number, text: string, number: string, message: table)
function Phone.OnCompanyMessage(jobName, cb)
    if type(jobName) ~= 'string' or jobName == '' or type(cb) ~= 'function' then return end
    companyHandlers[jobName] = companyHandlers[jobName] or {}
    local list = companyHandlers[jobName]
    list[#list + 1] = cb
    if listening then return end
    listening = true
    AddEventHandler(COMPANY_EVENT, function(message)
        CreateThread(function() dispatch(message) end)
    end)
end
