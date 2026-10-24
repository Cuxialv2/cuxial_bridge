## 2.24.0

### Novedades
- `Bridge.Anim` en el cliente: un recurso bloquea las animaciones del jugador (emotes, menú, cancelar, manos arriba, brazos cruzados, señalar, tumbarse, agacharse) mientras dura una escena suya, con un motivo por cada escena.
- Mientras haya bloqueo, el móvil (sd-phone) queda desactivado y se reactiva al soltarlo; si otro script ya lo había desactivado, no se toca.
- sleepless_interact oculta las opciones con animación mientras haya bloqueo.
- Varios recursos y motivos a la vez: el jugador vuelve a poder animarse cuando se sueltan todos. Si el recurso se para, sus bloqueos se sueltan solos; si `cuxial_emotes` reinicia, se vuelven a aplicar.

## 2.23.0

### Novedades
- Gestión de miembros de un trabajo con el jugador conectado o desconectado: `Bridge.Jobs.Hire`, `SetGrade`, `Grade` y `Grades`, junto a `Members` y `Remove`.
- Pensado para paneles de jefe (contratar, despedir y cambiar de grado) que sirvan para cualquier trabajo.

## 2.22.1

### Correcciones
- Las apps y pantallas de `Bridge.Screens` vuelven a registrarse de verdad cuando `cuxial_screens` arranca después o se reinicia (antes se perdían en silencio).

## 2.22.0

### Novedades
- `Bridge.Screens.registerScreen` y `removeScreen`: un recurso da de alta sus pantallas de `cuxial_screens` (por ejemplo, el monitor de una oficina) y se vuelven a registrar solas si `cuxial_screens` reinicia.

## 2.21.0

### Novedades
- `Bridge.Screens` para las apps de Cuxial OS (`cuxial_screens`): registrar una app desde cualquier recurso, recibir sus llamadas ya validadas por la sesión de pantalla, enviarle datos y avisos al jugador que la tiene abierta.
- En el cliente, abrir o cerrar una pantalla desde otro recurso (por ejemplo, al sentarse en una silla).

### Mejoras
- Si `cuxial_screens` arranca después o se reinicia, las apps se vuelven a registrar solas.

## 2.20.0

### Novedades
- Aviso de versión único al arrancar para todos los scripts Cuxial instalados, sin configurar nada.
- Una línea por script desactualizado con la versión nueva y su gravedad (mayor, menor o parche).
- Si todo está al día, una sola línea discreta.

### Configuración
- `cuxial_versioncheck 0` en `server.cfg` desactiva el aviso.
- `cuxial_versioncheck_quiet 1` oculta la línea de scripts al día.
- `cuxial_versioncheck_details 1` muestra hasta 3 novedades por script.
- `cuxial_versioncheck_url` cambia la dirección de consulta.

### Mejoras
- Una sola consulta por arranque, sin depender de GitHub ni de sus límites de peticiones.
- El aviso es más compacto y se lee bien en la consola de txAdmin.

## 2.19.1

### Cambiado
- En QBox, las consultas de una sola fila de la base de datos usan el mismo método que el resto. El resultado no cambia.

## 2.19.0

### Añadido
- `Bridge.DB.GetVehicleOwners(plates)` devuelve el dueño de varias matrículas en una sola consulta: `{ [plate] = citizenid }`. Funciona en QBox, QBCore y ESX; las matrículas sin dueño no aparecen.

## 2.18.0

### Nuevo
- **Registro de conectados en memoria** (`server/online.lua`): `Bridge.OnlinePlayers()` → `{ [src] = { src, cid, job, grade, duty, boss, gang, gangGrade } }`, `Bridge.OnlineByJob(job|set|lista, onDutyOnly?)`, `Bridge.OnlineByGang(gang)`, `Bridge.OnlineSource(cid)`, `Bridge.OnlineEntry(src)`, `Bridge.OnlineCount()`. Vive en cada recurso que incluye el bridge y se mantiene con los eventos del framework (carga, descarga, trabajo, banda, servicio) más un repaso cada 5 min; consultarlo no llama al framework por jugador. Usarlo en vez de recorrer `GetPlayers()` con `GetPlayer`/`GetJob`/`GetIdentifier`.
- **`Bridge.OnDutyChange(cb(src, onDuty))`**: qbox/qbcore `QBCore:Server:SetDuty`; esx no aplica.

## 2.17.0

### Nuevo
- **`Bridge.Media.List(tag?)`** → `{ { id, src, tag, viewers, startedAt, audio, relay } }` de las sesiones activas del recurso, por orden de apertura. **`Bridge.Media.ByTarget(src)`** (id de la sesión que emite ese jugador) e **`IsViewer(id, src)`**.
- Evento local `cuxial_bridge:mediaEnded` (`id, reason, tag, resource`) al cerrarse cualquier sesión, además de `onEnd`.
- webkit: `createLiveHost({ onTransport })` + `host.relay`; `viewer.relay`. Sin cambios de comportamiento por defecto.

## 2.16.0

### Nuevo
- **`Bridge.Jobs.Members(name)`** → `{ { cid, name, grade, online, src? } }` con conectados y desconectados. qbox: `GetGroupMembers(name, 'job')` (respaldo SQL en `player_groups`) + nombres con `GetOfflinePlayersBatch`; qbcore: conectados + `players` por `job.name`; esx: `users.job`. Sin oxmysql: solo conectados.
- **`Bridge.Jobs.Remove(cid, name)`** → `true` si le quita ese trabajo (conectado o no). qbox: `RemovePlayerFromJob`; qbcore: `SetJob('unemployed', 0)` o `UPDATE players`; esx: `setJob('unemployed', 0)` o `UPDATE users`. Solo quita si su trabajo es `name`.

## 2.15.0

### Nuevo
- **`Bridge.Jobs.Ensure(name, job)`** crea o actualiza un trabajo al arrancar (`job = { label, type?, defaultDuty?, offDutyPay?, grades = { { name, payment?, isboss? } } }`, grados 0..n por orden). qbox: `CreateJob` en memoria (no escribe `shared/jobs.lua`); qbcore: `AddJob`; esx: filas en `jobs`/`job_grades` (INSERT IGNORE) + `RefreshJobs`. `Bridge.Jobs.Exists(name)`.
- **`Bridge.Society.AddMoney|RemoveMoney(society, amount, reason)`** y **`GetBalance(society)`**: cuxial_banking → Renewed-Banking → qb-banking → esx_addonaccount (`society_<name>`). `Bridge.Society.Provider()` dice cuál hay (`nil` = ninguno).

## 2.14.2

### Rendimiento
- qbox `Bridge.GetDutyCount(jobType)`: usa `GetDutyCountType` y `GetDutyCountJob` de qbx_core en vez de recorrer todos los jugadores con `GetPlayer` (cada llamada cruzaba el objeto entero del jugador entre recursos). Con 200+ jugadores bajaba picos de 30-60 ms en recursos que cuentan servicio a menudo. Mismo resultado: total y lista de sources sin duplicados.
- qbox `Bridge.GetMoney(src, account)`: usa `GetMoney` de qbx_core en lugar de `GetPlayer`.

## 2.14.1

### Arreglo
- Los módulos del bridge se cargaban con nombre `@@cuxial_bridge/...`. `lib.require` de ox_lib toma el recurso del primer archivo `@@` que encuentra en la pila, así que un recurso que llamaba a `lib.require('data.x')` dentro de un callback del bridge (por ejemplo `OnPlayerLoaded`) buscaba el archivo en `cuxial_bridge` y fallaba con «module not found» y «circular-dependency». Ahora se cargan como `@cuxial_bridge/...` y `lib.require` resuelve al recurso que llama.

## 2.14.0

### Nuevo
- **`Bridge.RevivePlayer(src)`** / **`Bridge.HealPlayer(src)`** → `true` si el sistema médico del framework se encargó. qbcore: `qb-ambulancejob` (`hospital:client:Revive`, `hospital:client:HealInjuries 'full'`). esx: `esx_death:Revive` o, en versiones antiguas, `esx_ambulancejob:revive`; curar con `esx_ambulancejob:heal`. qbox y sin recurso: `false` (el que llama usa su camino).
- **`Bridge.Inventory.OpenVehicleInventory(src, kind, plate)`** (`kind` = `glovebox`/`trunk`): ox_inventory (`glove`/`trunk` + matrícula) y qb-inventory (`glovebox-`/`trunk-` + matrícula).
- **`shared/config.lua`** (`Bridge.Config`): `esx.gangs`, lista de bandas para ESX con la misma forma que qbox/qbcore.
- qb-inventory: `forceOpenInventory` implementado (`player` → `OpenInventoryById`; resto → `OpenInventory(src, id)`).
- ESX: `GetGangs` (desde config), `GetVehicleModels` / `GetVehiclesByName` / `GetVehiclesByHash` (tabla `vehicles` de esx_vehicleshop si existe), `DeleteCharacter` (expulsa y borra `users` + `owned_vehicles`, `user_licenses`, `billing` si existen).
- ESX normalize: `money.black_money`; `metadata.hunger`/`thirst` 0-100 desde esx_status (0 sin él).
- ESX `DB.SearchPlayersPaged`: `lastSeen` desde `users.last_seen` si la columna existe.
- qbcore: `Bridge.DB` (reutiliza el módulo de qbox; mismo esquema `players`/`player_vehicles`).

### Arreglo
- qbcore `SetJob` buscaba al jugador por citizenid con un source: nunca cambiaba el trabajo.
- qbcore/esx `Vehicles.CreatePlayerVehicle`: acepta `data.props.plate` o `data.plate`; sin ninguna genera una única (8 caracteres). Antes devolvía `nil` si faltaba `props.plate`.
- ESX `SetGang` valida contra `esx.gangs` (nombre y grado); `IsGradeBoss` usa `isboss` del grado.

### Notas
- qbox sin cambios de comportamiento.

## 2.13.2

### Nuevo
- **`Bridge.Target.disable(state)`** en los tres adaptadores (sleepless_interact, ox_target, qb-target): apaga o enciende el target mientras hay una interfaz abierta.
- **`hideWhenEmpty`** en las opciones de `Bridge.Target.addPoint` / `addBoxZone` (sleepless_interact): el punto no se dibuja para quien no puede usar ninguna de sus opciones.

### Arreglo
- sleepless_interact: cada zona lleva su propio identificador. Antes, dos puntos en la misma coordenada compartían id y quitar uno se llevaba las opciones del otro.

### Notas
- Cambio **aditivo**: no toca ninguna función existente.
- Los módulos de `media` pasan a ser opcionales: si no están en la carpeta, el bridge arranca igual.

## 2.13.0

### Nuevo
- **Riqueza de un personaje, conectado o no** (lo usa el panel del banco, `cuxial_banking`):
  - `Bridge.GetAllMoneyOffline(identifier)` → todas las cuentas guardadas (`{ cash, bank, crypto, ... }`), sin reducirlas a cash/bank/crypto como hace `GetMoneyOffline`.
  - `Bridge.Inventory.GetOfflineInventory(identifier)` → items guardados del personaje (`{ {name, count, slot, metadata} }`).
  - `Bridge.Inventory.GetOwnedStashes(identifier)` → `{ {name, items} }` de los almacenes cuyo dueño es el personaje.
  - `Bridge.Inventory.GetStashData(name, owner?)` → items de un almacén guardado, o `nil` si no existe.
  - `Bridge.Inventory.CountItems(items, names)` → `total, porNombre`; suma en memoria, vale para inventario vivo o guardado.
  - `Bridge.Vehicles.GetStorageByOwner(identifier)` → `{ {id, plate, vehicle, trunk, glovebox} }` con los items ya decodificados.
- Implementado para **qbox / qbcore + ox_inventory** (dinero también en esx). En el resto de combinaciones devuelven `{}` o `nil`, así que se pueden llamar sin comprobar el adaptador.

### Notas
- Son lecturas de lo **guardado**: con el jugador conectado, el inventario vivo se lee con `Bridge.Inventory.GetInventoryItems(src)`.
- Cambio **aditivo**: no toca ninguna función existente.

## 2.12.1

### Arreglo
- `Bridge.Target.addLocalEntity`/`removeLocalEntity` con sleepless_interact: si la entidad está **en red** (vehículos
  y objetos de servidor) se registra por netId (`addEntity`/`removeEntity`). sleepless ignoraba las opciones locales
  con offset (`autoCenter`) en entidades con netId, así que no aparecían (p. ej. "Coger escalera" en el camión de
  cuxial_electrician). Las entidades locales siguen igual.

## 2.12.0

### Nuevo
- **`Bridge.Phone`** (servidor, `server/phone.lua`): adaptador de sd-phone — `IsAvailable`, `HasPhone`, `GetNumber`, `Notify`, `SendSystemMessage`, `SendLocation` y `OnCompanyMessage(job, cb)` (mensajes de clientes a una compañía de la app Servicios).
- Sin sd-phone todo devuelve `false`/`nil`: el recurso que lo usa cae a su notificación normal.

### Notas
- Cambio **aditivo**: no toca ninguna función existente.

## 2.11.x

### Nuevo
- **`Bridge.Vehicles.GetPlayerVehiclesByIds(ids)`** — resuelve una lista de vehículos por sus ids en **una sola consulta**, devolviendo el mismo shape que `GetPlayerVehicle`. Implementado en los tres adaptadores (qbox, qbcore, esx).
  - En **qbox** se consulta la tabla directamente: `qbx_vehicles` no expone un filtro por ids, y encadenar `GetPlayerVehicle` por fila convertía cualquier listado en un N+1.
  - Devuelve `{}` con una lista vacía, así que es seguro llamarlo sin comprobar antes.

### Notas
- Pensado para pantallas que resuelven muchos vehículos de golpe. El primer consumidor es el listado de depósito de `cuxial_garages`, que pasaba de una consulta por vehículo retenido a una única consulta por apertura.
- Cambio **aditivo**: no toca ninguna función existente ni su firma, así que actualizar no requiere cambios en los recursos que ya usan el bridge.
