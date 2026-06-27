local function isUp(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

local forcedFw = GetConvar('cuxial_bridge:framework', 'auto')

local framework
if forcedFw ~= 'auto' then
    framework = forcedFw
elseif isUp('qbx_core') then
    framework = 'qbox'
elseif isUp('qb-core') then
    framework = 'qbcore'
elseif isUp('es_extended') then
    framework = 'esx'
else
    framework = 'qbox'
    print('[cuxial_bridge] ^3aviso:^7 no se detectó framework, usando fallback "qbox"')
end

Bridge.framework = framework

local forcedInv = GetConvar('cuxial_bridge:inventory', 'auto')

local inventory
if forcedInv ~= 'auto' then
    inventory = forcedInv
elseif isUp('ox_inventory') then
    inventory = 'ox_inventory'
elseif isUp('qb-inventory') then
    inventory = 'qb-inventory'
else
    inventory = 'ox_inventory'
end

Bridge.inventory = inventory

local forcedTarget = GetConvar('cuxial_bridge:target', 'auto')

local target
if forcedTarget ~= 'auto' then
    target = forcedTarget
elseif isUp('ox_target') then
    target = 'ox_target'
elseif isUp('qb-target') then
    target = 'qb-target'
else
    target = 'ox_target'
end

Bridge.target = target

function Bridge.is(fw) return Bridge.framework == fw end
function Bridge.usesInventory(inv) return Bridge.inventory == inv end
function Bridge.usesTarget(t) return Bridge.target == t end

