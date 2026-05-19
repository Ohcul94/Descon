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


## 🎯 CREAR SKILLS PARA ESFERAS:
1. **Analiza Primero** el archivo "E:\Descon\descon\scripts\resources" y los scripts que ya existen.
2. **Analiza primero** el archivo del servidor relacionado y el script del cliente para entender qué variables ya existen.
3. **Identifica** la estructura de datos de las esferas y cómo se aplican en el cliente Godot (main_hud.gd, skills.gd, stats.gd).
4. **Crea** el nuevo skill en el cliente Godot (main_hud.gd, skills.gd, stats.gd) siguiendo la estructura existente.
5. **Modifica** el servidor (Node.js) para que envíe la información del nuevo skill al cliente Godot.
6. **Asegúrate** de que el nuevo skill funcione correctamente en el juego (pruebas).
7. **Idioma:** Explícame y piensa todo en español latinoamericano.
8. **Mantén los nombres de propiedades estándar:** utiliza siempre `hp`, `shield`/`sh`, `zone`, `x`, `y`, `id`, `spheres`.
9. **Panel AdmiNDash** recorda siempre implementar los campos necesarios para yo poder modificar los parámetros del juego desde el panel.
10. **Campos (Inputs)** Los campos tienen que ser siempre en español latinoamericano y expresar sus medidas entre parentesis () por ejemplo: (px) para pixeles, (ms) para milisegundos, etc







##  CREAR MAPAS NUEVOS 2.5D:
Hola. Necesito crear un mapa nuevo para mi juego híbrido 2.5D en Godot 4. El sistema combina jugabilidad, físicas y red en 2D nativo con elementos visuales de fondo y portales en 3D de alta fidelidad, asegurando rendimiento y estética premium. 
Por favor, implementa la siguiente arquitectura de escena y script:
### 1. ESTRUCTURA DE LA ESCENA (.tscn)
El árbol de nodos debe estructurarse exactamente de esta manera:
- Map_New (Node2D)  <-- Nodo raíz del mapa
  - ViewportCanvas (CanvasLayer)  <-- [Propiedad: layer = -15]
    - SubViewportContainer (SubViewportContainer) <-- [Anclado a pantalla completa]
      - SubViewport (SubViewport) <-- [Propiedades esenciales: own_world_3d = true, transparent_bg = true]
        - WorldEnvironment (WorldEnvironment) <-- [Environment: background_mode = 0 (Clear/Transparent)]
        - Camera3D (Camera3D) <-- [Transform3D mirando hacia abajo; projection = Orthogonal]
        - DirectionalLight3D (DirectionalLight3D) <-- Iluminación básica de la escena
        - Portals3D (Node3D) <-- Nodo contenedor para las puertas/assets GLB
        - Asteroids3D (Node3D) <-- Contenedor de decoraciones 3D
  - ParallaxBackground (ParallaxBackground) <-- [Propiedad: layer = -25] (Nebulosa 2D estable del lobby)
    - StaticLayer (CanvasLayer) <-- [Propiedad: layer = -30]
      - SpaceBG (ColorRect) <-- Fondo negro de espacio profundo
    - MapWorldLayer (ParallaxLayer)
      - MapBackground (TextureRect) <-- Nebulosa de fondo 2D con opacidad modulate (1, 1, 1, 1)
  - Walls (Node2D) <-- Para colisiones físicas 2D
  - Asteroids (Node2D)
---
### 2. CÓDIGO DEL SCRIPT DEL MAPA (Map_New.gd)
El script debe heredar de BaseMap. Debe sincronizar de forma pixel-perfect la cámara 3D con la cámara 2D suavizada en el bucle físico, y manejar la rotación giroscópica multieje (wobble) para que los portales floten de forma realista:
```gdscript
extends BaseMap
@export var scale_factor: float = 0.02 # Relación entre 2D y 3D (1px 2D = 0.02 unidades 3D)
@export var camera_height: float = 30.0 # Altura base de la cámara 3D
@export var use_orthogonal: bool = true
@onready var sub_viewport: SubViewport = $ViewportCanvas/SubViewportContainer/SubViewport
@onready var camera_3d: Camera3D = $ViewportCanvas/SubViewportContainer/SubViewport/Camera3D
func _ready():
	super._ready()
	_on_window_resized()
	get_tree().get_root().size_changed.connect(_on_window_resized)
	_generate_extraction_portals()
func _physics_process(_delta):
	# EVITAR MICRO-DESLIZAMIENTOS (Estilo MU Online)
	# Sincronizamos la cámara 3D con el centro de pantalla real (que incluye el smoothing de la cámara 2D)
	var target_pos = Vector2.ZERO
	var current_zoom = 1.0
	
	var cam_2d = get_viewport().get_camera_2d()
	if is_instance_valid(cam_2d):
		target_pos = cam_2d.get_screen_center_position()
		current_zoom = cam_2d.zoom.x
		
	if is_instance_valid(camera_3d):
		if current_zoom <= 0.01: current_zoom = 1.0
		var viewport_height = float(get_viewport().size.y)
		if viewport_height <= 0: viewport_height = 1080.0
		
		# Mantener escala pixel-perfect según resolución y zoom
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_3d.size = (viewport_height * scale_factor) / current_zoom
		camera_3d.position.y = camera_height
		
		# Sincronización solidificada
		camera_3d.position.x = target_pos.x * scale_factor
		camera_3d.position.z = target_pos.y * scale_factor
func _process(delta):
	# EFECTO GIROSCÓPICO INTERDIMENSIONAL (WOBBLE MULTIEJE)
	# Hace que las puertas floten y se bamboleen suavemente en X e Y mientras giran en Z
	var parent_portals = get_node_or_null("ViewportCanvas/SubViewportContainer/SubViewport/Portals3D")
	if is_instance_valid(parent_portals):
		var time = Time.get_ticks_msec() * 0.001
		var index = 0
		for portal in parent_portals.get_children():
			if portal is Node3D:
				portal.rotate_object_local(Vector3.FORWARD, delta * 0.8) # Giro continuo
				var phase = index * 1.5
				var wobble_x = sin(time * 1.5 + phase) * 0.06 # Ajuste de inclinación flotante
				var wobble_y = cos(time * 1.1 + phase) * 0.06
				
				# Aplicar rotación base (-45 grados de inclinación hacia la cámara) más balanceo
				portal.rotation.x = deg_to_rad(-45.0) + wobble_x
				portal.rotation.y = deg_to_rad(-90.0) + wobble_y
				index += 1
func _on_window_resized():
	var size = get_viewport().size
	if is_instance_valid(sub_viewport):
		sub_viewport.set_deferred("size", size)
func _generate_extraction_portals():
	# Cargar modelo 3D GLB
	var portal_mesh_scene = load("res://assets/Puertas/3D/Puerta2/Puerta2.glb")
	var points = [
		{"x": 2000, "y": 2000, "label": "Punto Alfa"},
		{"x": 4000, "y": 4000, "label": "Punto Beta"}
	]
	
	for i in range(points.size()):
		var pt = points[i]
		var pos_2d = Vector2(float(pt.x), float(pt.y))
		
		# Instancia 3D
		if portal_mesh_scene:
			var portal_3d = portal_mesh_scene.instantiate()
			portal_3d.rotation_degrees = Vector3(-45, -90, 0) # Inclinación óptima
			portal_3d.position = Vector3(pos_2d.x * scale_factor, 0.5, pos_2d.y * scale_factor)
			portal_3d.scale = Vector3(10.0, 10.0, 10.0) # Tamaño calibrado
			$ViewportCanvas/SubViewportContainer/SubViewport/Portals3D.add_child(portal_3d)
			
			# Luz de punto
			var light = OmniLight3D.new()
			light.position = Vector3(0, 0, 1.5)
			light.light_color = Color(0, 0.9, 1.0)
			light.light_energy = 3.5
			light.omni_range = 15.0
			portal_3d.add_child(light)
			
		# Area lógica de triggers 2D (sin colisión física molesta)
		var area_2d = Area2D.new()
		area_2d.global_position = pos_2d
		var shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 150.0
		shape.shape = circle
		area_2d.add_child(shape)
		
		var marker = Label.new()
		marker.text = str(pt.label)
		marker.position = Vector2(-100, -20)
		marker.modulate = Color.CYAN
		area_2d.add_child(marker)
		add_child(area_2d)