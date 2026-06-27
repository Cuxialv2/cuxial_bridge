local Target = Bridge.Target or {}
local ox = exports.ox_target

---@param options table[]
---@return table[]
local function toOx(options)
    local out = {}
    for i = 1, #options do
        local o = options[i]
        out[i] = {
            name = o.name,
            label = o.label,
            icon = o.icon,
            distance = o.distance or 2.5,
            items = o.items,
            canInteract = o.canInteract and function(entity)
                return o.canInteract(entity)
            end or nil,
            onSelect = function(data)
                if o.onSelect then o.onSelect(data.entity) end
            end,
        }
    end
    return out
end

function Target.addModel(models, options)
    ox:addModel(models, toOx(options))
end

function Target.removeModel(models, names)
    ox:removeModel(models, names)
end

function Target.addLocalEntity(entity, options)
    ox:addLocalEntity(entity, toOx(options))
end

function Target.removeLocalEntity(entity, names)
    ox:removeLocalEntity(entity, names)
end

---@param options table[]
function Target.addGlobalPlayer(options)
    ox:addGlobalPlayer(toOx(options))
end

---@param names string|string[]
function Target.removeGlobalPlayer(names)
    ox:removeGlobalPlayer(names)
end

---@param params table
---@return number|string zoneId  handle para removeZone
function Target.addBoxZone(params)
    return ox:addBoxZone({
        coords   = params.coords,
        size     = params.size or vec3(1.0, 1.0, 1.0),
        rotation = params.rotation or 0.0,
        debug    = params.debug,
        options  = toOx(params.options or {}),
    })
end

---@param id number|string
function Target.removeZone(id)
    ox:removeZone(id)
end

Bridge.Target = Target
