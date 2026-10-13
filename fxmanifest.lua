fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cuxial_bridge'
author 'Cuxial'
description 'Capa de compatibilidad multi-framework (qbox / qbcore / esx) para todos los scripts Cuxial'
version '2.14.1'
shared_scripts {
    '@ox_lib/init.lua',
}

server_scripts {
    'init.lua',
    'server/media_sign.js',
}

files {
    'init.lua',
    'shared/detect.lua',
    'shared/config.lua',
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
    'server/zones.lua',
    'server/media.lua',
    'server/phone.lua',
    'client/api.lua',
    'client/adapters/qbox.lua',
    'client/adapters/qbcore.lua',
    'client/adapters/esx.lua',
    'client/inventory/ox_inventory.lua',
    'client/inventory/qb-inventory.lua',
    'client/target/ox_target.lua',
    'client/target/sleepless_interact.lua',
    'client/target/qb-target.lua',
    'client/zones.lua',
    'client/media.lua',
}

