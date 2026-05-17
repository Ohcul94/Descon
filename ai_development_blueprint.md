# 🌌 INSTRUCTIVO MAESTRO DE DESARROLLO PARA LA IA (DESCON MMO)

Este documento es un **Blueprint de Desarrollo** personalizado para el proyecto **DESCON MMO**. Está diseñado para ser copiado y pegado al inicio del chat con cualquier Inteligencia Artificial (IA) cuando quieras crear una nueva habilidad (skill), un nuevo modo de juego, o modificar mecánicas del cliente (Godot 4 GDScript) o del servidor (Node.js).

---

## 📋 CÓMO USAR ESTE BLUEPRINT
> [!TIP]
> Cuando inicies una nueva sesión con un asistente de IA, cópiale este bloque de texto junto con tu requerimiento específico. Esto evitará que la IA invente soluciones genéricas o destruya los patrones de código que ya funcionan.

---

```markdown
# CONTEXTO DEL PROYECTO: DESCON MMO

Estás trabajando en "DESCON MMO", un juego multijugador masivo en 2D. 
- **Tecnología del Servidor:** Node.js (JavaScript puro con Socket.io y MongoDB Atlas).
- **Tecnología del Cliente:** Godot Engine 4 (GDScript v4+).
- **Estilo de Arquitectura:** Monolito Modular Optimizado (el servidor corre en un solo VPS económico, por lo que el rendimiento de CPU y memoria RAM es prioritario).

---

## 🏛️ REGLAS DE ARQUITECTURA CRÍTICAS (NO ROMPER JAMÁS)

### 1. La Regla de Oro de la RAM vs Base de Datos (Low-Cost Performance)
* **Procesamiento Rápido en RAM:** Toda la lógica de tiempo real (movimiento a 30 FPS, combate, daño, posición de IAs y proyectiles) se maneja puramente en variables volátiles en memoria RAM dentro del servidor (`state.players` y `state.enemies`). 
* **Persistencia Lenta en MongoDB:** NUNCA leas ni escribas en MongoDB en ticks o loops rápidos. Solo se accede a la base de datos de forma asíncrona en eventos aislados y deterministas:
  1. Al iniciar sesión (Carga de inventario).
  2. Al cambiar de mapa / Warp Portal (Warp persistente).
  3. Al comprar/vender en tiendas o comerciar.
  4. Al morir o extraer con éxito de una Raid.
  5. En un auto-guardado en segundo plano (cada 5 minutos).

### 2. Modularización en el Servidor
* `server.js` es puramente el **Host de Red / Telefonista**. Recibe las conexiones y delega todo a los manejadores.
* Toda nueva mecánica compleja debe nacer en un archivo aislado en la carpeta `systems/` (ej. `systems/extractionManager.js`, `systems/AIManager.js`) o `events/` (ej. `events/clanHandlers.js`), y registrarse limpiamente en `server.js`.

### 3. Saneamiento y Sincronía de Zonas
* **Función Clave:** Se debe usar siempre el ayudante `normalizeZone(z)` definido en el servidor.
* **El Problema:** JavaScript distingue estrictamente entre `"2"` (String) y `2` (Number). Para evitar desincronizaciones visuales donde los jugadores e IAs no se ven en el mapa, **todas las comparaciones de zonas deben estar normalizadas**:
  `if (normalizeZone(p.zone) === normalizeZone(targetZone))`

---

## 🛰️ PATRÓN DE COMUNICACIÓN RED (SOCKET.IO <=> GDSCRIPT)

### Flujo de Envío desde el Servidor:
Cuando ocurre un cambio, el servidor emite un evento al socket o a la sala:
* `socket.to("zone_X").emit("playerMoved", data)`
* `socket.emit("currentPlayers", list)`

### Flujo de Recepción en el Cliente (Godot 4):
* El autoload `NetworkManager.gd` es el controlador central de red.
* Escucha los paquetes en `_on_packet_received`, mapea los eventos a señales personalizadas y las emite globalmente:
  * Señal `player_updated(data)` -> Despachada para actualizar stats/esferas/PvP.
  * Señal `clear_zone_entities(zoneId)` -> Despachada en `changeZoneDone` para limpiar el mapa visualmente.
* El script `World.gd` conecta estas señales y se encarga de instanciar las naves enemigas/aliadas (`Ship.tscn` y `Enemy.tscn`) dinámicamente.

---

## 🧠 SISTEMA DE INTELIGENCIA ARTIFICIAL (IA)
* **Base Común:** Todos los enemigos heredan de `behaviors/BaseAI.js`.
* **Rangos de Visión:** El rango por defecto es de `800px` (a menos que se active una horda o boost de agresividad extremo). Spawnear enemigos fuera de estos límites de mapa (ej. a más de `2000px` en Mapa 2) causará que ignoren a los jugadores.
* **Ciclo de IA:** Corre dentro de `gameLoop.js`. Actualiza las posiciones y targetea al jugador más cercano en su zona que cumpla la validación `isSameZone(player, enemy)`.

---

## 🎯 INSTRUCCIONES PARA EL DISEÑO DEL NUEVO REQUERIMIENTO:
Cuando implementes el nuevo módulo solicitado por el usuario:
1. **Analiza primero** el archivo del servidor relacionado y el script del cliente para entender qué variables ya existen.
2. **Mantén los nombres de propiedades estándar:** utiliza siempre `hp`, `shield`/`sh`, `zone`, `x`, `y`, `id`, `spheres`.
3. **No uses placeholders ni mockups:** escribe código completo y funcional listo para producción.
4. **Respeta los tipos de datos:** si vas a inyectar un nuevo payload de inventario, asegúrate de no pisar ni sobrescribir la propiedad local `current_zone` del cliente Godot, dejando que sea gobernada de forma autoritativa por `changeZoneDone`.
5. **Idioma:** Explícame y piensa todo en español latinoamericano.

[INSERTAR AQUÍ EL REQUERIMIENTO DEL NUEVO MÓDULO O MECÁNICA]
```
