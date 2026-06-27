## cuxial_bridge v2.5.0

Capa de compatibilidad multi-framework para los recursos **Cuxial**. Gratis y open-source.

### ✨ Incluye
- Framework: **qbox · qbcore · esx** (detección en runtime)
- Inventario: **ox_inventory · qb-inventory**
- Target: **ox_target · qb-target** — `addLocalEntity`, `addModel`, `addGlobalPlayer`, `addBoxZone`
- `Bridge.VersionCheck(repo)` — aviso de actualización con changelog en consola
- `Bridge.SetFrameworkDeathFlag` — refleja el estado de muerte en ESX (`PlayerData.dead`)

### Instalación
1. Descargá el `Source code (zip)` de esta release.
2. `ensure cuxial_bridge` **antes** de cualquier recurso Cuxial.

### Requisitos
ox_lib + un framework (qbox/qbcore/esx) + inventario + target soportados.
