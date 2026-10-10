## 2.13.2

### Nuevo
- **`Bridge.Target.disable(state)`** en los tres adaptadores (sleepless_interact, ox_target, qb-target): apaga o enciende el target mientras hay una interfaz abierta.
- **`hideWhenEmpty`** en las opciones de `Bridge.Target.addPoint` / `addBoxZone` (sleepless_interact): el punto no se dibuja para quien no puede usar ninguna de sus opciones.

### Arreglo
- sleepless_interact: cada zona lleva su propio identificador. Antes, dos puntos en la misma coordenada compartían id y quitar uno se llevaba las opciones del otro.

### Notas
- Cambio **aditivo**: no toca ninguna función existente.

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
