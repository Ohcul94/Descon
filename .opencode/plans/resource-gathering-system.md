# Plan: Sistema de Recolección de Recursos (AdminDash + Server + Godot)

## Objetivo
1. **Cartografía** → sección "Recursos" con el mismo control que las Amenazas (modo random/polígono/fijo, cantidad, intervalo, ubicación).
2. **Crafter → Materiales** → checkbox "Recolectable" + input de tiempo (visible solo si está marcado).
3. **Godot** → canal de recolección por proximidad con VFX de rayo continuo celeste/azul; el servidor valida y otorga el ítem.

## Modelo de datos

**Material** (`config.shopItems.resources[]`, existe ya):
```json
{ "recolectable": false, "gatherTime": 3 }   // gatherTime en segundos
```

**Nodo de recurso por zona** (`config.mapsConfig[zona].resources[]`, nuevo — clon de `spawns[]`):
```json
{
  "id": "res_17866...", "resourceId": "mat_hierro",
  "count": 3, "intervalMs": 15000, "amount": 2,
  "spawnMode": "random", "x": 1000, "y": 1000, "radius": 500,
  "polygon": null,
  "assetPath": "res://assets/....glb", "icon": "res://assets/....png",
  "scale": 1.0, "rotY": 0, "yOffset": 0.5
}
```
Al vivir dentro de `mapsConfig` viaja gratis por `saveAdminConfig` → whitelist `CLIENT_CONFIG_KEYS` → Godot. **No hay que tocar la whitelist.**

---

## Fase 1 — AdminDash · Crafter → Materiales (checkbox + tiempo)

Archivo: `AdminDash/js/renderers/renderLoot.js`

1. **Fila existente** `renderLoot.js:445-452` (Escala · Color · Stack · Precio · **No Comerciable**):
   - Añadir `flex-wrap: wrap;` al `<div style="display:flex; gap:15px...">` de la línea 445 (evita romper el layout en pantallas chicas).
   - Insertar después de la línea 451 (No Comerciable):
     - `.field` **"Recolectable"** → `<input type=checkbox ${res.recolectable?'checked':''} onchange="config.shopItems.resources[idx].recolectable = this.checked; renderCrafting();">`
     - `${res.recolectable ? '<input Tiempo (s) gatherTime>' : ''}` → **solo se renderiza si está marcado** (por eso el `renderCrafting()` en el onchange, mismo patrón que ID/Nombre línea 434).
2. `addCraftingResource` (`renderLoot.js:657`) → añadir defaults `recolectable:false, gatherTime:3`.
3. `index.html:1030` → subir `renderLoot.js?v=1.25`.

Estética: mismas clases `.field`/`label` y anchos (`width:110px`) de la fila existente.

---

## Fase 2 — AdminDash · Cartografía → "🌿 RECURSOS RECOLECTABLES"

### 2a. Selector de material (`AdminDash/js/renderers/renderRequirements.js`)
- Nuevo `window.renderSearchableResourceSelect(currentValue, cb, color, extraId)` clonando `renderSearchableEnemySelect` (`renderRequirements.js:200-338`), pero iterando `config.shopItems.resources` **filtrando `r.recolectable === true`**, sin tiers, mostrando `nombre + [gatherTime]s`.
- `index.html:1022` → `renderRequirements.js?v=1.25`.

### 2b. Sección en el detalle de zona (`AdminDash/js/renderers/renderMaps.js`)
- Plantilla exacta: bloque "👾 ECOSISTEMA DE ENEMIGOS" `renderMaps.js:354-441`.
- Insertar **después de la línea 441** (antes de Puertas `:443`) la sección:
  - Header `🌿 RECURSOS RECOLECTABLES` + botón `+ AGREGAR RECURSO` → `openMapAddModal('resource')`.
  - Contenedor `#resources-list`; tarjetas `card-map-resource-${idx}` (borde naranja `rgba(251,146,60,0.25)` para no chocar con verde=amenazas, cian=puertas, oro=mercado, `--accent`=hazards).
  - Campos: Material (selector buscable) · Cant. nodos · Intervalo respawn (ms) · Unidades por recolección · Modo de aparición (4 opciones, misma normalización de `:396-402`) · X/Y · Radio · Polígono (textarea `resource-polygon-${idx}` + ✏️/🗑️) · Asset 3D (.glb + 📁) · Icono/foto (.png + 📁) · Escala · Rot Y · Altura.
  - Preview de la foto del nodo con el `icon` (fallback al icono del material).
  - Badge de aviso si el material referenciado dejó de ser recolectable.

### 2c. Lógica (`AdminDash/js/app.js`)
| Función | Línea | Cambio |
|---|---|---|
| `openMapAddModal` | 1534 | rama `kind === 'resource'` (reutiliza ids `map-add-spawn-mode/pos-fields/radius-field/polygon-field` → `toggleMapAddSpawnMode` (1633) funciona igual). Nuevos ids: `map-add-resource-id`, `map-add-amount`, `map-add-asset`, `map-add-icon`. |
| `startPolygonDrawForNew` | 1373 | generalizar: según `window._mapAddKind` lee `#map-add-enemy-id` o `#map-add-resource-id`. |
| `confirmMapAdd` | 1660 | rama `'resource'` → `m.resources.push({...})`; y en `:1745` mapear `kind==='resource'`. |
| `duplicateMapItem` | 1749 | rama `'resource'` (nuevo id). |
| `requestMapDelete` | 1129 | rama `'resource'` (mensaje + `m.resources.splice` en `:1165`). |
| `selectMapItem` | 1099 | prefijo `resource: 'card-map-resource-'` (`:101`), añadir `[id^="card-map-resource-"]` al reset (`:102`), `focusedRadarItem = {type:'map-resource', index}`. |
| `parsePolygonInput` / `clearPolygon` | 1241 / 1255 | añadir parámetro `kind` (default `'spawn'`) para escribir en `m.resources`. |
| `startPolygonDraw` / `finishPolygonDraw` | 1348 / 1419 | parámetro/global `kind` (textarea id y array destino). |
| Radar `onmousedown` | 3319-3352 | bucle de hit-test para `m.resources` (vértices + punto), antes que spawns. |
| Radar `onmousemove` (drag) | 3384-3427 | tipos `'map-resource'` y `'map-resource-vertex'`. |
| Radar hover | 3442-3463 | bucle de hover de resources. |
| Radar `draw()` | 3605-3717 | bloque "DIBUJAR RECURSOS": polígono/radio/punto+etiqueta en naranja `#fb923c`. |
| `handleGlobalKeydown` | 1798 | verificar que SUPR/Ctrl+D funcionan con `kind='resource'`. |

### 2d. Picker de asset (`AdminDash/js/renderers/renderModes.js`)
- Junto a `triggerMapObjAssetPick` (`renderModes.js:1920`) → nuevo `triggerMapResourceAssetPick(mapId, resIdx)` idéntico pero escribiendo `config.mapsConfig[mapId].resources[resIdx].assetPath` (y variante para `icon`).

---

## Fase 3 — Server (autoridad)

### 3a. `Server/state.js:12`
- Añadir `resourceNodes: {}` (estructura `{ [zone]: [ {id, resourceId, x, y, amount, assetPath, icon, scale, rotY, yOffset, respawnAt|null, collecting|null} ] }`).

### 3b. Nuevo `Server/systems/resourceNodeManager.js`
- `ensureZoneNodes(zone, state)` → crea instancias hasta `count` por cada cfg de `mapsConfig[zone].resources[]`, resolviendo posición según `spawnMode`:
  - `fixed` → `x,y` (+ `spawnValidator.findValidSpawnPosition`, `Server/utils/spawnValidator.js`)
  - `random` con `radius>0` → aleatorio en círculo; `radius=0` → aleatorio en límites del mapa
  - `polygon` → `randomPointInPolygon` (copia local, patrón `AIManager.js:27`)
  - Salta configs cuyo material no tenga `recolectable`.
- `runResourceNodes(io, state)` (tick 1 s) → repone nodos agotados (`respawnAt`) y respeta `intervalMs`.
- `registerResourceNodeHandlers(socket, io, state)`:
  - `startCollectResource {nodeId}` → valida zona, distancia (`lootConfig.interactRange`), que no esté agotado ni en uso → `p.collecting = {nodeId, startedAt, x, y}`.
  - `cancelCollectResource {nodeId}` → limpia.
  - `collectResource {nodeId}` → valida `Date.now()-startedAt >= gatherTime*1000 - 400` (tiempo sale de `shopItems.resources[].gatherTime`), distancia y que el jugador no se haya movido fuera de rango → `addItemToInventory(user, item, state.SERVER_CONFIG, amount)` (`inventoryHandlers.js:66`), `user.save()`, emite `inventoryData` (patrón `lootManager.js:257`), `resourceCollected` al jugador y `resourceNodeDepleted` a la zona; marca `respawnAt = now + intervalMs`.
- `sendZoneResourceNodes(socket, zone)` → emite `resourceNodes {zone, nodes[]}`.
- Export: `{ registerResourceNodeHandlers, runResourceNodes, sendZoneResourceNodes }`.

### 3c. Wiring
- `server.js:~1607` → registrar handlers (junto a `registerLootHandlers`).
- Zona: `server.js:846-870` (login), `Server/handlers/zoneHandler.js:127-148` (warpToZone) y `:501-522` (changeZone) → añadir `sendZoneResourceNodes` después del bloque de `lootDrops`.
- `gameLoop.js:852` → `resourceNodeManager.runResourceNodes(io, state)` (junto a `aiManager.runGuardians()`).

---

## Fase 4 — Godot (cliente)

### 4a. Red — `descon/scripts/autoloads/NetworkManager.gd`
- Señales nuevas: `resource_nodes`, `resource_node_spawned`, `resource_node_depleted`, `resource_collected`.
- Cases en el match de eventos (~`:343`): `"resourceNodes"`, `"resourceNodeSpawned"`, `"resourceNodeDepleted"`, `"resourceCollected"`.

### 4b. `descon/scripts/entities/ResourceNode.gd` (nuevo, plantilla `LootDrop.gd` 234 líneas)
- `Area2D` + `CircleShape2D r=180`, grupo/estados igual que LootDrop.
- Modelo 3D en `map.sub_viewport`: `load(asset_path)` con fallback a cilindro teñido con el color del material (patrón `BaseMap._instantiate_map_object_3d:2177-2193`); tint de materiales como `LootDrop._fix_chest_materials:212`.
- Flotación + `body_entered/exited` → `map._show_resource_button(self)` / `_hide_resource_button()`.
- Estados: `deplete()` (fade out, nodo queda oculto) y `respawn()` (fade in) → se reusa la instancia.
- Barra de canal 2D sobre el nodo (Panel + ColorRect FG, patrón `Player.gd:1234 _ensure_cast_visual_2d`).

### 4c. `descon/scripts/systems/BaseMap.gd`
- Estado: `resource_nodes: Dictionary`, `active_resource_node` (junto a `:1762`).
- Conectar señales en `_ready` (patrón `:156-161`) → crear/actualizar/depletar nodos.
- Botón: `_show_resource_button` / `_hide_resource_button` clon de `_show_loot_button` (`:2478`) con key `"resource"` y desc `"RECOLECTAR [Y / Clic]"`; añadir la key en `_update_interact_visibility` (`:2464`), `_on_interact_button_pressed` (`:2439`) y al bucle de teclas `:2795` (`["vault","market","loot","resource"]`).

### 4d. Canal de recolección (en `ResourceNode.gd`)
1. `_interact()` → `gatherTime` desde `GameConstants.SHOP_ITEMS.resources` (default 3 s) → `send_event("startCollectResource", {nodeId})`.
2. Spawn del VFX rayo; `_process` acumula tiempo, barra al %.
3. Cancela (salir de rango / ESC / botón) → `send_event("cancelCollectResource")` + libera VFX.
4. Al completar → `send_event("collectResource", {nodeId})`; al recibir `resourceCollected`/`resourceNodeDepleted` hace fade del nodo.
5. El servidor puede rechazar → llega `gameNotification` y se corta el canal.

### 4e. VFX rayo alienígena (celeste/azul, continuo, semi-transparente)
- Nuevo `descon/scripts/vfx/ResourceBeamVFX.gd` (Node2D procedural, patrón Vital Link `EntityManager.gd:4676/483-545`):
  - 3 `Line2D` `set_as_top_level(true)`: **Glow** width 16 `Color(0.2,0.75,1.0,0.15)`, **Main** width 5 con gradiente `#38bdf8 → #0ea5e9` alpha 0.75, **Core** width 1.8 `#e0f7ff` alpha 0.95.
  - Puntos regenerados cada ~0.05 s con jitter (clon de `_generate_lightning` `EntityManager.gd:4633`) → rayo de energía continuo.
  - 4-6 "gotas" de material que viajan **nodo → jugador** (extracción).
  - Extremos: origen = modelo 3D del nodo proyectado; destino = `_get_entity_visual_position(player)` (`EntityManager.gd:4799`).
  - Fade-in 0.15 s, fade-out al cancelar/completar.
- (Alternativa documentada, no implementada salvo pedido: cilindro 3D + `resources/shaders/color_beam.gdshader` como en `EntityMechanicsVFX.gd:1534`.)

---

## Fase 5 — Verificación
- `node --check` sobre todos los JS tocados (AdminDash y Server).
- Godot headless: `Godot_v4.7.2-stable_win64.exe --headless --path E:\Descon\descon --quit` para validar parseo de los scripts nuevos/modificados.
- Test manual: marcar material recolectable → ver input de tiempo; crear nodo en zona → ver tarjeta/radar; correr server + cliente → recolectar con el rayo y confirmar ítem en inventario.

## Reglas del repo (respetadas)
- Nada de git (auto_commit false) sin orden explícita.
- No tocar `OracleCloud/`, `Ejecutables*/`, `package.json`, `project.godot`, `.gitignore`.

## Orden de ejecución
1. Fase 1 (Materiales) → 2. Fase 2 (Cartografía) → 3. Fase 3 (Server) → 4. Fase 4 (Godot) → 5. Fase 5 (verificación).
