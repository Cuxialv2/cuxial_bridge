local Target = Bridge.Target or {}
local interact = exports.sleepless_interact

local DEFAULT_DISTANCE = 2.5

---@type table<string, { id: string, names: string[] }>
local zones = {}
local serial = 0

---@param options table[]
---@return table[]
local function toInteract(options)
    local out = {}
    for i = 1, #options do
        local o = options[i]
        out[i] = {
            name = o.name,
            label = o.label,
            icon = o.icon,
            distance = o.distance or DEFAULT_DISTANCE,
            items = o.items,
            priority = o.priority,
            image = o.image,
            badge = o.badge,
            preview = o.preview,
            holdTime = o.holdTime,
            cooldown = o.cooldown,
            hideWhenEmpty = o.hideWhenEmpty,
            canInteract = o.canInteract and function(entity)
                return o.canInteract(entity)
            end or nil,
            onSelect = function(data)
                if o.onSelect then o.onSelect(type(data) == 'table' and data.entity or nil) end
            end,
        }
    end
    return out
end

---@param coords vector3
---@param options table[]  ya convertidas
---@return string handle
local function addZone(coords, options)
    serial = serial + 1
    local handle = ('zone%d'):format(serial)
    local names = {}
    for i = 1, #options do
        local name = ('%s@%s'):format(options[i].name or 'option', handle)
        options[i].name = name
        names[i] = name
    end
    zones[handle] = { id = interact:addCoords(coords, options), names = names }
    return handle
end

function Target.addModel(models, options)
    interact:addModel(models, toInteract(options))
end

function Target.removeModel(models, names)
    interact:removeModel(models, names)
end

---@type table<integer, integer>  entidad en red → netId registrado
local networked = {}

function Target.addLocalEntity(entity, options)
    if NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        networked[entity] = netId
        interact:addEntity(netId, toInteract(options))
        return
    end
    interact:addLocalEntity(entity, toInteract(options))
end

function Target.removeLocalEntity(entity, names)
    local netId = networked[entity]
    if netId then
        interact:removeEntity(netId, names)
        networked[entity] = nil
        return
    end
    interact:removeLocalEntity(entity, names)
end

---@param options table[]
function Target.addGlobalPlayer(options)
    interact:addGlobalPlayer(toInteract(options))
end

---@param names string|string[]
function Target.removeGlobalPlayer(names)
    interact:removeGlobalPlayer(names)
end

---@param params table  { coords, size?, rotation?, options }
---@return string zoneId  handle para removeZone
function Target.addBoxZone(params)
    local size = params.size or vec3(1.0, 1.0, 1.0)
    local reach = math.max(size.x or 1.0, size.y or 1.0) / 2 + 1.0
    local options = toInteract(params.options or {})
    for i = 1, #options do
        options[i].distance = math.max(options[i].distance or 0, reach)
    end
    local c = params.coords
    return addZone(vec3(c.x, c.y, c.z), options)
end

---@param coords vector3
---@param options table[]
---@return string zoneId  handle para removeZone
function Target.addPoint(coords, options)
    return addZone(vec3(coords.x, coords.y, coords.z), toInteract(options))
end

---@param id string
function Target.removeZone(id)
    local zone = zones[id]
    if not zone then return end
    zones[id] = nil
    interact:removeCoords(zone.id, zone.names)
end

---@param state boolean  true = sin interacción (menús a pantalla completa, minijuegos…)
function Target.disable(state)
    interact:disableInteract(state == true)
end

Bridge.Target = Target
