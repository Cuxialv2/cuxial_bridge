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

## Médico, vehículos y bandas ESX (2.14)

```lua
Bridge.RevivePlayer(src)                                 -- true si lo hizo qb-ambulancejob / esx_death / esx_ambulancejob
Bridge.HealPlayer(src)                                   -- true si lo hizo qb-ambulancejob / esx_ambulancejob
Bridge.Inventory.OpenVehicleInventory(src, 'trunk', plate) -- 'glovebox' | 'trunk'; ox_inventory y qb-inventory
Bridge.Vehicles.CreatePlayerVehicle({ citizenid = cid, model = 'adder' }) -- matrícula única si no se pasa
```

ESX no trae bandas: se definen en `shared/config.lua` → `esx.gangs` (misma forma que qbox/qbcore) y se guardan en el
metadata del jugador. El catálogo de vehículos en ESX sale de la tabla `vehicles` de esx_vehicleshop si existe.

## Bridge.Media · pantalla en vivo de un jugador

Mismo método que el directo de sd-phone: la NUI del jugador captura el render
del juego como hace el teléfono (textura del juego → framebuffer → readPixels → canvas 2D), lo codifica con MediaRecorder (webm, con el
micrófono en opus si se pide) y manda cada trozo al servidor; el servidor lo
reparte a los espectadores con eventos latentes y guarda la cabecera del
códec y el último grupo de fotogramas para quien se une a mitad. Sin WebRTC,
sin TURN, sin certificados; varios espectadores por emisión.

Servidor (`server/media.lua`, se carga en cada recurso; los eventos llevan el
nombre del recurso como prefijo):

```lua
local id = Bridge.Media.Open(targetSrc, { audio = false, maxViewers = 4, enc = { width = 960, bitrate = 1500000, fps = 20 }, onEnd = function(session, reason) end })
Bridge.Media.AddViewer(id, staffSrc)      -- recibe caché + trozos
Bridge.Media.SetAudio(id, true)           -- abre el micrófono del emisor
Bridge.Media.RemoveViewer(id, staffSrc)
Bridge.Media.Close(id, 'closed')
Bridge.Media.IceServers()                 -- STUN + TURN Cloudflare (sd_cf_turn_*) para lo que sí use WebRTC
```

Permisos: ninguno aquí. Quien llama decide quién mira a quién.

NUI (`webkit/`, se importa por alias de Vite `@bridge/*` apuntando a esta
carpeta; `client/media.lua` ya manda los mensajes `bridgeMedia:*`):

```ts
import { createLiveHost, createLiveViewer } from '@bridge/index'
const host = createLiveHost({ send: fetchNui })          // en la NUI de todos: emite cuando el servidor lo pide
host.handle(action, data)                                 // desde el listener de mensajes NUI
const viewer = createLiveViewer(videoEl, { onHealth })   // en la NUI del que mira
viewer.watch(id); viewer.handle(action, data)
```

Usado por cuxial_admin (ver pantalla y escuchar). Convars en `server-data/media.cfg`.

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

