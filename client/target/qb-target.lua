local Target = Bridge.Target or {}
local qb = exports['qb-target']

---@param options table[]
---@return table[]
local function toQb(options)
    local out = {}
    for i = 1, #options do
        local o = options[i]
        out[i] = {
            label = o.label,
            icon = o.icon,
            item = o.items,
            canInteract = o.canInteract and function(entity)
                return o.canInteract(entity)
            end or nil,
            action = function(entity)
                if o.onSelect then o.onSelect(entity) end
            end,
        }
    end
    return out
end

---@param options table[]
---@return number
local function distOf(options)
    return (options[1] and options[1].distance) or 2.5
end

function Target.addModel(models, options)
    qb:AddTargetModel(models, { options = toQb(options), distance = distOf(options) })
end

function Target.removeModel(models, names)
    qb:RemoveTargetModel(models, names)
end

function Target.addLocalEntity(entity, options)
    qb:AddTargetEntity(entity, { options = toQb(options), distance = distOf(options) })
end

function Target.removeLocalEntity(entity, names)
    qb:RemoveTargetEntity(entity, names)
end

---@param options table[]
function Target.addGlobalPlayer(options)
    qb:AddGlobalPlayer({ options = toQb(options), distance = distOf(options) })
end

---@param names string|string[]
function Target.removeGlobalPlayer(names)
    qb:RemoveGlobalPlayer(names)
end

local boxSeq = 0

---@param params table
---@return string zoneId  nombre/handle para removeZone
function Target.addBoxZone(params)
    boxSeq = boxSeq + 1
    local name = params.name or ('cuxial_box_%d'):format(boxSeq)
    local c = params.coords
    local size = params.size or vec3(1.0, 1.0, 1.0)
    qb:AddBoxZone(name, vector3(c.x, c.y, c.z), size.x, size.y, {
        name      = name,
        heading   = params.rotation or 0.0,
        debugPoly = params.debug or false,
        minZ      = c.z - (size.z / 2.0),
        maxZ      = c.z + (size.z / 2.0),
    }, {
        options  = toQb(params.options or {}),
        distance = distOf(params.options or {}),
    })
    return name
end

---@param id string
function Target.removeZone(id)
    qb:RemoveZone(id)
end

Bridge.Target = Target
