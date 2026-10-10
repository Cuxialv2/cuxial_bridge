# cuxial_bridge

Capa de compatibilidad multi-framework para los recursos **Cuxial**. Abstrae el framework (qbox / qbcore / esx), el inventario (ox_inventory / qb-inventory) y el sistema de target (sleepless_interact / ox_target / qb-target) detrás de una sola API `Bridge.*`, detectando todo en runtime.

Es **gratis** y open-source. Los demás recursos Cuxial dependen de él.

## Instalación

1. Descargá la última [release](https://github.com/Cuxialv2/cuxial_bridge/releases).
2. Poné `cuxial_bridge` en tu carpeta de recursos.
3. `ensure cuxial_bridge` **antes** de cualquier recurso Cuxial.

```cfg
ensure cuxial_bridge
```

## Dependencias

- [ox_lib](https://github.com/overextended/ox_lib)
- Un framework: **qbox**, **qbcore** o **esx**
- Inventario: **ox_inventory** o **qb-inventory**
- Target: **sleepless_interact**, **ox_target** o **qb-target**

## Uso

```lua
shared_scripts {
    '@ox_lib/init.lua',
    '@cuxial_bridge/init.lua',
}
```

```lua
local player = Bridge.GetPlayer(src)
Bridge.AddMoney(src, 'bank', 500, 'reason')
Bridge.Target.addLocalEntity(entity, options)
Bridge.VersionCheck('owner/repo')
```

## Soportados

| Capa | Opciones |
|------|----------|
| Framework | qbox · qbcore · esx |
| Inventario | ox_inventory · qb-inventory |
| Target | ox_target · qb-target |

## Riqueza de un personaje (lecturas offline)

```lua
local money = Bridge.GetAllMoneyOffline(citizenid)                 -- { cash, bank, crypto, ... }
local items = Bridge.Inventory.GetOfflineInventory(citizenid)      -- { {name, count, slot, metadata} }
local stashes = Bridge.Inventory.GetOwnedStashes(citizenid)        -- { {name, items} }
local stash = Bridge.Inventory.GetStashData('policelocker', citizenid)
local total, byName = Bridge.Inventory.CountItems(items, { 'money', 'black_money' })
local storage = Bridge.Vehicles.GetStorageByOwner(citizenid)       -- { {id, plate, vehicle, trunk, glovebox} }
```

Leen lo guardado en base de datos (qbox / qbcore con ox_inventory); con otros adaptadores devuelven `{}` o `nil`.

## Bridge.Phone · teléfono (sd-phone)

Servidor (`server/phone.lua`). Los recursos nunca llaman a los exports del teléfono: pasan por aquí. Sin `sd-phone`
arrancado todo devuelve `false`/`nil` y el recurso usa su notificación normal.

```lua
Bridge.Phone.IsAvailable()                                  -- sd-phone arrancado
Bridge.Phone.HasPhone(src)                                  -- lleva un teléfono
Bridge.Phone.GetNumber(src)                                 -- número (lo asigna si no tiene) o nil
Bridge.Phone.Notify(src, title, text, app?)                 -- banner del teléfono → true/false
Bridge.Phone.SendSystemMessage(src, from, text, number?)    -- SMS de sistema (número corto por defecto '555')
Bridge.Phone.SendLocation(src, from, coords, number?, label?) -- tarjeta de ubicación en Mensajes
Bridge.Phone.OnCompanyMessage(job, function(src, text, number, message) end)
```

`OnCompanyMessage` escucha `sd-phone:server:services:message` (mensaje de un cliente a una compañía de la app
Servicios) y filtra por el `job` de la compañía; comprueba que el número del mensaje es el del jugador. La compañía se
da de alta en `sd-phone/configs/services.lua` (`Companies`); el `job` no tiene que existir en el framework.
Usado por cuxial_gasstations (detailing a domicilio).
