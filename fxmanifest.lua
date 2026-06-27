fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cuxial_bridge'
author 'Cuxial'
description 'Capa de compatibilidad multi-framework (qbox / qbcore / esx) para todos los scripts Cuxial'
version '2.5.0'

server_script 'init.lua'

files {
    'init.lua',
    'shared/detect.lua',
    'server/api.lua',
    'server/adapters/qbox.lua',
    'server/adapters/qbcore.lua',
    'server/adapters/esx.lua',
    'server/inventory/ox_inventory.lua',
    'server/inventory/qb-inventory.lua',
    'server/vehicles/qbox.lua',
    'server/vehicles/qbcore.lua',
    'server/vehicles/esx.lua',
    'server/db/qbox.lua',
    'server/db/qbcore.lua',
    'server/db/esx.lua',
    'server/version.lua',
    'client/api.lua',
    'client/adapters/qbox.lua',
    'client/adapters/qbcore.lua',
    'client/adapters/esx.lua',
    'client/inventory/ox_inventory.lua',
    'client/inventory/qb-inventory.lua',
    'client/target/ox_target.lua',
    'client/target/qb-target.lua',
}

