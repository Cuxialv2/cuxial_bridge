if Bridge then return end

Bridge = {
    _version = '0.1.0',
    _resource = 'cuxial_bridge',
}

local function loadModule(path)
    local content = LoadResourceFile(Bridge._resource, path)
    if not content then
        error(('[cuxial_bridge] no se pudo leer el módulo "%s"'):format(path), 2)
    end
    local chunk, err = load(content, ('@@%s/%s'):format(Bridge._resource, path))
    if not chunk then
        error(('[cuxial_bridge] error compilando "%s": %s'):format(path, err), 2)
    end
    return chunk()
end

Bridge._loadModule = loadModule

loadModule('shared/detect.lua')

local context = IsDuplicityVersion() and 'server' or 'client'
Bridge.context = context

loadModule(context .. '/api.lua')
loadModule(context .. '/adapters/' .. Bridge.framework .. '.lua')

loadModule(context .. '/inventory/' .. Bridge.inventory .. '.lua')

if context == 'server' then
    loadModule('server/vehicles/' .. Bridge.framework .. '.lua')
    loadModule('server/db/' .. Bridge.framework .. '.lua')
    loadModule('server/version.lua')
else
    loadModule('client/target/' .. Bridge.target .. '.lua')
end

if GetCurrentResourceName() == Bridge._resource then
    print(('[cuxial_bridge] listo framework=%s inventario=%s contexto=%s')
        :format(Bridge.framework, Bridge.inventory, context))
    if context == 'server' and Bridge.VersionCheck then
        Bridge.VersionCheck('Cuxialv2/cuxial_bridge')
    end
end

return Bridge
