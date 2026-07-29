extends BaseMap

# Map_Extraction.gd
# Lógica para la sincronización de cámara 2D a 3D en el Lienzo 3D Único.
# Hereda de BaseMap para compatibilidad del sistema de carga de mapas.
var active_extract_points: Array = []

var match_timer_label: Label = null
var spawn_lock_container: PanelContainer = null
var spawn_lock_label: Label = null
var spawn_lock_remaining: float = 0.0
var initial_player_pos: Vector2 = Vector2.ZERO
var has_saved_initial_pos: bool = false
var spawn_lock_finished_notify_timer: float = 0.0
var spawn_lock_radius: float = 500.0
var spawn_bubble_mesh: MeshInstance3D = null
var last_warn_time: float = 0.0

# Registro de elementos de arena
var arena_nexuses_nodes: Dictionary = {}
var arena_pillars_nodes: Dictionary = {}

# Determina si esta instancia es una partida de Defensa del Altar (dinámico desde config)
func _is_altar_defense_zone() -> bool:
	var full_cfg = GameConstants.get("FULL_CONFIG")
	if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
		var ad_maps = full_cfg.gameModes.altar_defense.get("maps", [])
		for m in ad_maps:
			if str(m) == str(zone_id):
				return true
	return false

func _ready():
	super._ready()
	
	# Obtener referencias dinámicas creadas por la clase base
	if is_instance_valid(sub_viewport):
		asteroids_3d = sub_viewport.get_node_or_null("Asteroids3D")
		if not is_instance_valid(asteroids_3d):
			asteroids_3d = Node3D.new()
			asteroids_3d.name = "Asteroids3D"
			sub_viewport.add_child(asteroids_3d)
			
	if is_instance_valid(camera_3d):
		camera_3d.fov = 35.0
	
	# Crear los componentes visuales del botón flotante interactivo de salto
	_create_portal_jump_ui()
	
	# Generar obstáculos procedimentales en el mapa de 10,000 x 10,000 px (Desactivado a petición del usuario)
	# _generate_procedural_obstacles()
	
	# Generar portales 3D de extracción/escape en los puntos configurados en el AdminDash
	if not _is_arena_zone():
		_generate_extraction_portals()

	# Inicializar cuenta regresiva de spawn lock y tamaño de mundo desde la config dinámica
	var spawn_lock_ms = 10000.0
	var is_ad = _is_altar_defense_zone()
	var is_ar = _is_arena_zone()
	var full_config = GameConstants.get("FULL_CONFIG")
	if full_config and full_config.has("gameModes"):
		if is_ar:
			if full_config.gameModes.has("arenas"):
				var arena_cfg = full_config.gameModes.arenas
				if arena_cfg.has("spawnLockTime"):
					spawn_lock_ms = float(arena_cfg.spawnLockTime)
				if arena_cfg.has("mapConfigs") and arena_cfg.mapConfigs.has(str(zone_id)):
					var map_cfg = arena_cfg.mapConfigs[str(zone_id)]
					if map_cfg.has("width") and float(map_cfg.width) > 0:
						world_size = float(map_cfg.width)
						adjust_background()
		else:
			var mode_key = "altar_defense" if is_ad else "extraction"
			if full_config.gameModes.has(mode_key):
				var mode_cfg = full_config.gameModes[mode_key]
				if mode_cfg.has("spawnLockTime"):
					spawn_lock_ms = float(mode_cfg.spawnLockTime)
				if mode_cfg.has("width") and float(mode_cfg.width) > 0:
					world_size = float(mode_cfg.width)
					adjust_background()
	spawn_lock_remaining = spawn_lock_ms / 1000.0

	# Crear HUD UI de temporizadores
	_create_timers_ui()

	# Conectar señal de actualización de raid desde red
	if NetworkManager:
		if not NetworkManager.raid_time_update.is_connected(_on_raid_time_update):
			NetworkManager.raid_time_update.connect(_on_raid_time_update)
		if not NetworkManager.altar_state_update.is_connected(_on_altar_state_update):
			NetworkManager.altar_state_update.connect(_on_altar_state_update)
		if not NetworkManager.update_exit_portals.is_connected(_on_update_exit_portals):
			NetworkManager.update_exit_portals.connect(_on_update_exit_portals)
		if not NetworkManager.arena_state_update.is_connected(_on_arena_state_update):
			NetworkManager.arena_state_update.connect(_on_arena_state_update)
		# ARENA FIX: Conectar arenaMatchStarted para auto-configurar el zone_id del matchId
		# cuando World.gd (safety net) instancia este mapa después del changeZoneDone.
		# Esto es necesario porque el matchId es "arena_XXX" (dinámico) y no un número fijo.
		if not NetworkManager.arena_match_started.is_connected(_on_arena_match_started_self):
			NetworkManager.arena_match_started.connect(_on_arena_match_started_self)
			
	# Instanciar elementos de la Arena PvP si corresponde
	_spawn_arena_elements()
	
	# Retry arena elements cuando llegue la config del server
	if _is_arena_zone() and arena_nexuses_nodes.is_empty() and arena_pillars_nodes.is_empty():
		if NetworkManager:
			if not NetworkManager.admin_config_updated.is_connected(_on_config_retry_arena):
				NetworkManager.admin_config_updated.connect(_on_config_retry_arena)
			if not NetworkManager.config_updated.is_connected(_on_config_retry_arena):
				NetworkManager.config_updated.connect(_on_config_retry_arena)

# Handler local para arenaMatchStarted en el nodo del mapa.
# Actualiza zone_id al matchId real y regenera los elementos de arena si faltan.
func _on_arena_match_started_self(data: Dictionary) -> void:
	var match_id = str(data.get("matchId", ""))
	if match_id.is_empty():
		return
	# Si el zone_id ya es correcto, solo asegurar que los elementos estén spawneados
	if str(zone_id) == match_id:
		if arena_nexuses_nodes.is_empty():
			NetworkManager.current_arena_data = data
			_spawn_arena_elements()
		return
	# Actualizar zone_id al matchId dinámico del servidor
	zone_id = match_id
	print("[Map_Extraction] arena_match_started recibido. zone_id actualizado a: ", zone_id)
	# Guardar datos de arena en el NetworkManager para que _spawn_arena_elements los use
	NetworkManager.current_arena_data = data
	_clear_arena_elements()
	_spawn_arena_elements()

func _physics_process(_delta):
	# --- LOCALIZAR NAVE DEL JUGADOR ---
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]

	# --- GESTIÓN DINÁMICA DE SPAWN LOCK (BARRERA DE INICIO CON MOVIMIENTO PERMITIDO) ---
	if spawn_lock_remaining > 0.0:
		spawn_lock_remaining = max(0.0, spawn_lock_remaining - _delta)
		
		if is_instance_valid(player_node):
			if not has_saved_initial_pos:
				initial_player_pos = player_node.global_position
				has_saved_initial_pos = true
				

				
				# Encontrar el spawn point configurado más cercano para extraer su radio dinámicamente
				var closest_radius = 500.0
				if _is_arena_zone():
					if NetworkManager.current_arena_data.has("spawns"):
						var min_dist = 999999.0
						var arena_spawns = NetworkManager.current_arena_data.spawns
						for sp in arena_spawns:
							var sp_pos = Vector2(float(sp.get("x", 0)), float(sp.get("y", 0)))
							var dist = initial_player_pos.distance_to(sp_pos)
							if dist < min_dist:
								min_dist = dist
								closest_radius = float(sp.get("radius", 200.0))
								initial_player_pos = sp_pos
				else:
					var is_ad_spawn = _is_altar_defense_zone()
					var full_cfg = GameConstants.get("FULL_CONFIG")
					if full_cfg and full_cfg.has("gameModes"):
						var mode_key = "altar_defense" if is_ad_spawn else "extraction"
						if full_cfg.gameModes.has(mode_key):
							var mode_cfg = full_cfg.gameModes[mode_key]
							if mode_cfg.has("spawnPoints"):
								var min_dist = 999999.0
								for sp in mode_cfg.spawnPoints:
									var sp_pos = Vector2(float(sp.get("x", 0)), float(sp.get("y", 0)))
									var dist = initial_player_pos.distance_to(sp_pos)
									if dist < min_dist:
										min_dist = dist
										closest_radius = float(sp.get("radius", 500.0))
				spawn_lock_radius = closest_radius
				
				# Inyectar burbuja tridimensional de barrera protectora de spawn (estilo Shield Skill)
				if is_instance_valid(sub_viewport) and not spawn_bubble_mesh:
					spawn_bubble_mesh = MeshInstance3D.new()
					spawn_bubble_mesh.name = "SpawnBarrierBubble"
					var sphere = SphereMesh.new()
					var r_3d = spawn_lock_radius * scale_factor
					sphere.radius = r_3d
					sphere.height = r_3d * 2.0
					spawn_bubble_mesh.mesh = sphere
					
					var mat = ShaderMaterial.new()
					mat.shader = load("res://resources/shaders/energy_shield.gdshader")
					if mat.shader:
						# Color naranja/dorado brillante palpitante de barrera espacial
						mat.set_shader_parameter("color_escudo", Color(1.0, 0.65, 0.1, 0.8))
						mat.set_shader_parameter("modo_curacion", false)
					spawn_bubble_mesh.material_override = mat
					print("[SpawnLock] Burbuja protectora 3D inicializada con radio: ", r_3d)
					
				# Posicionar la burbuja 3D en base a la coordenada 2D del spawn
				spawn_bubble_mesh.position.x = initial_player_pos.x * scale_factor
				spawn_bubble_mesh.position.z = initial_player_pos.y * scale_factor * correction_z
				spawn_bubble_mesh.position.y = 0.0

				sub_viewport.add_child(spawn_bubble_mesh)

			# Permitir movimiento libre DENTRO de la burbuja, restringir salida
			var distance = player_node.global_position.distance_to(initial_player_pos)
			if distance > spawn_lock_radius:
				var direction = (player_node.global_position - initial_player_pos).normalized()
				player_node.global_position = initial_player_pos + direction * spawn_lock_radius
				if "velocity" in player_node:
					player_node.velocity = Vector2.ZERO
				
				# Alerta en logs superiores (MainHUD) para no molestar sobre la nave
				var now = Time.get_ticks_msec() / 1000.0
				if now - last_warn_time > 2.0:
					last_warn_time = now
					var hud = get_tree().get_first_node_in_group("hud")
					if hud and hud.has_method("notify"):
						hud.notify("🚨 BARRERA SENSORIAL: Regresa al sector seguro del spawn", "warn")
			
			player_node.set_meta("skills_blocked", true)
			player_node.set_meta("spawn_locked", true)
			
		if spawn_lock_label and spawn_lock_container:
			spawn_lock_label.text = "🚨 BARRERA DE SEGURIDAD ACTIVA 🚨\nSISTEMAS ONLINE EN: " + str(snapped(spawn_lock_remaining, 0.1)) + "s"
			spawn_lock_container.visible = true
			var border_pulse = 0.6 + sin(Time.get_ticks_msec() * 0.015) * 0.4
			spawn_lock_container.modulate.a = border_pulse
	else:
		if has_saved_initial_pos:
			if is_instance_valid(player_node):
				player_node.set_meta("skills_blocked", false)
				player_node.set_meta("spawn_locked", false)
				spawn_lock_finished_notify_timer = 1.5
				has_saved_initial_pos = false
				
				# Desvanecer y limpiar la burbuja protectora tridimensional
				if is_instance_valid(spawn_bubble_mesh):
					var tween = create_tween()
					tween.tween_property(spawn_bubble_mesh, "scale", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_SINE)
					tween.finished.connect(func():
						if is_instance_valid(spawn_bubble_mesh):
							spawn_bubble_mesh.queue_free()
							spawn_bubble_mesh = null
					)
				
		if spawn_lock_finished_notify_timer > 0.0:
			spawn_lock_finished_notify_timer = max(0.0, spawn_lock_finished_notify_timer - _delta)
			if spawn_lock_label and spawn_lock_container:
				spawn_lock_label.text = "🟢 ¡CONEXIÓN SENSORIAL ESTABLECIDA! 🟢\nSISTEMAS DE VUELO Y COMBATE ONLINE"
				spawn_lock_label.add_theme_color_override("font_color", Color.GREEN)
				spawn_lock_container.visible = true
				spawn_lock_container.modulate.a = clamp(spawn_lock_finished_notify_timer / 1.5, 0.0, 1.0)
		else:
			if spawn_lock_container:
				spawn_lock_container.visible = false

func _process(delta):
	super(delta)
	
	# Rotación procedimental y lenta de los asteroides 3D de fondo para dar vida a la escena
	if is_instance_valid(asteroids_3d):
		for asteroid in asteroids_3d.get_children():
			if asteroid is Node3D:
				var speed_mult = 0.05 + (abs(asteroid.name.hash() % 10) * 0.01)
				asteroid.rotate_x(delta * speed_mult * 0.5)
				asteroid.rotate_y(delta * speed_mult)
				asteroid.rotate_z(delta * speed_mult * 0.3)
				
	# --- EFECTO GIROSCÓPICO INTERDIMENSIONAL (WOBBLE MULTIEJE) ---
	var parent_portals_3d = sub_viewport.get_node_or_null("Portals3D") if is_instance_valid(sub_viewport) else null
	if is_instance_valid(parent_portals_3d):
		var time = Time.get_ticks_msec() * 0.001
		var index = 0
		for portal in parent_portals_3d.get_children():
			if portal is Node3D:
				# 1. Rotación continua sobre su propio eje de entrada (Vector3.FORWARD)
				portal.rotate_object_local(Vector3.FORWARD, delta * 0.8)
				
				# 2. Oscilación giroscópica sinusoidal en X e Y para el balanceo estelar
				var phase_offset = index * 1.5
				var wobble_x = sin(time * 1.5 + phase_offset) * 0.06 # Balanceo suave en X
				var wobble_y = cos(time * 1.1 + phase_offset) * 0.06 # Balanceo suave en Y
				
				portal.rotation.x = deg_to_rad(-45.0) + wobble_x
				portal.rotation.y = deg_to_rad(-90.0) + wobble_y
				
				index += 1

	# --- VERIFICACIÓN DE PROXIMIDAD A PORTALES E INTERACCIÓN DE SALTO ---
	var active_near_portal = null
	var near_portal_target_zone = "1"
	
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
			
	if is_instance_valid(player_node):
		for pt in active_extract_points:
			var pos_2d = Vector2(float(pt.x), float(pt.y))
			var radius = float(pt.get("proximityRadius", 300.0))
			var dist = player_node.global_position.distance_to(pos_2d)
			
			if dist <= radius:
				active_near_portal = pt
				near_portal_target_zone = str(pt.get("targetZone", "1"))
				break
				
	if is_instance_valid(portal_btn_container):
		if active_near_portal != null:
			var target_name = "Lobby / Hangar"
			if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(near_portal_target_zone):
				target_name = GameConstants.MAPS_CONFIG[near_portal_target_zone].get("name", "Sector " + near_portal_target_zone)
			elif near_portal_target_zone == "1":
				target_name = "Lobby / Hangar"
			else:
				target_name = "Sector " + near_portal_target_zone
				
			var bind_key_text = "ESPACIO"
			if InputMap.has_action("portal_jump"):
				var events = InputMap.action_get_events("portal_jump")
				if events.size() > 0:
					bind_key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
					if bind_key_text == "SPACE":
						bind_key_text = "ESPACIO"
				
			if is_instance_valid(portal_desc_label):
				portal_desc_label.text = "ENTRAR A " + target_name.to_upper() + " [" + bind_key_text + " / Clic]"
				
			if is_instance_valid(portal_click_button):
				portal_click_button.set_meta("target_zone", near_portal_target_zone)
				
			_current_interact_mode = "portal"
			_set_portal_icon("portal")
			portal_btn_container.visible = true
		else:
			if _current_interact_mode == "portal":
				_current_interact_mode = ""
			# No ocultar si hay vault/loot activo
			if not is_instance_valid(active_vault_node) and not is_instance_valid(active_loot_node):
				portal_btn_container.visible = false
	_update_interact_visibility()

func _generate_procedural_obstacles():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var parent_walls_3d = sub_viewport.get_node_or_null("Walls3D") if is_instance_valid(sub_viewport) else null
	var parent_asteroids_3d = sub_viewport.get_node_or_null("Asteroids3D") if is_instance_valid(sub_viewport) else null
	var parent_walls_2d = get_node_or_null("Walls")
	var parent_asteroids_2d = get_node_or_null("Asteroids")
	
	if is_instance_valid(sub_viewport):
		if not parent_walls_3d:
			parent_walls_3d = Node3D.new()
			parent_walls_3d.name = "Walls3D"
			sub_viewport.add_child(parent_walls_3d)
		if not parent_asteroids_3d:
			parent_asteroids_3d = Node3D.new()
			parent_asteroids_3d.name = "Asteroids3D"
			sub_viewport.add_child(parent_asteroids_3d)
			
	if not parent_walls_3d or not parent_asteroids_3d or not parent_walls_2d or not parent_asteroids_2d:
		print("[Map_Extraction] Error: ¡Nodos padres no encontrados para la generación!")
		return
		
	# Limpiar cualquier nodo pre-existente para evitar duplicación
	for child in parent_walls_3d.get_children(): child.queue_free()
	for child in parent_asteroids_3d.get_children(): child.queue_free()
	for child in parent_walls_2d.get_children(): child.queue_free()
	for child in parent_asteroids_2d.get_children(): child.queue_free()
	
	# Definición de materiales
	var mat_metal = StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.45, 0.50, 0.55)
	mat_metal.metallic = 0.95
	mat_metal.roughness = 0.3
	
	var mat_rock = StandardMaterial3D.new()
	mat_rock.albedo_color = Color(0.35, 0.31, 0.27)
	mat_rock.roughness = 0.9
	
	# Generar 60 obstáculos esparcidos
	var num_obstacles = 60
	for i in range(num_obstacles):
		var pos_2d = Vector2(rng.randf_range(500, 9500), rng.randf_range(500, 9500))
		var is_wall = rng.randf() > 0.4 # 60% paredes metálicas, 40% asteroides rocosos
		
		if is_wall:
			var size_2d = rng.randf_range(200.0, 450.0)
			
			var static_body = StaticBody2D.new()
			static_body.name = "Wall2D_" + str(i)
			static_body.collision_layer = 2
			static_body.collision_mask = 0
			static_body.add_to_group("obstacles")
			static_body.global_position = pos_2d
			
			var collision_shape = CollisionShape2D.new()
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = Vector2(size_2d, size_2d)
			collision_shape.shape = rect_shape
			static_body.add_child(collision_shape)
			parent_walls_2d.add_child(static_body)
			
			var box_3d = CSGBox3D.new()
			box_3d.name = "Wall3D_" + str(i)
			box_3d.position = Vector3(pos_2d.x * scale_factor, 0, pos_2d.y * scale_factor * correction_z)
			box_3d.size = Vector3(size_2d * scale_factor, rng.randf_range(5.0, 10.0), size_2d * scale_factor)
			box_3d.material = mat_metal
			parent_walls_3d.add_child(box_3d)
			
		else:
			var radius_2d = rng.randf_range(100.0, 250.0)
			
			var static_body = StaticBody2D.new()
			static_body.name = "Asteroid2D_" + str(i)
			static_body.collision_layer = 2
			static_body.collision_mask = 0
			static_body.add_to_group("obstacles")
			static_body.global_position = pos_2d
			
			var collision_shape = CollisionShape2D.new()
			var circle_shape = CircleShape2D.new()
			circle_shape.radius = radius_2d
			collision_shape.shape = circle_shape
			static_body.add_child(collision_shape)
			parent_asteroids_2d.add_child(static_body)
			
			var sphere_3d = CSGSphere3D.new()
			sphere_3d.name = "Asteroid3D_" + str(i)
			sphere_3d.position = Vector3(pos_2d.x * scale_factor, rng.randf_range(-2.0, 2.0), pos_2d.y * scale_factor * correction_z)
			sphere_3d.radius = radius_2d * scale_factor
			sphere_3d.radial_segments = 16
			sphere_3d.rings = 12
			sphere_3d.material = mat_rock
			parent_asteroids_3d.add_child(sphere_3d)
			
	print("[Map_Extraction] ¡Generación procedimental completada! Creados ", num_obstacles, " obstáculos.")

func _generate_extraction_portals():
	# Intentar obtener los puntos configurados dinámicamente desde el servidor (vía GameConstants)
	var extract_points = []
	var is_ad_portal = _is_altar_defense_zone()
	var full_cfg = GameConstants.get("FULL_CONFIG")
	if full_cfg and full_cfg.has("gameModes"):
		var mode_key = "altar_defense" if is_ad_portal else "extraction"
		var key = "exitPortals" if is_ad_portal else "extractPoints"
		if full_cfg.gameModes.has(mode_key) and full_cfg.gameModes[mode_key].has(key):
			extract_points = full_cfg.gameModes[mode_key].get(key)
			
	# Fallback robusto con las coordenadas exactas de config.json si el servidor aún no envía la config completa
	if extract_points.size() == 0 and not is_ad_portal:
		extract_points = [
			{"x": 2974, "y": 5038, "label": "Punto Alfa"},
			{"x": 6920, "y": 5070, "label": "Punto Beta"},
			{"x": 5019, "y": 3025, "label": "Punto Gamma"},
			{"x": 5003, "y": 7019, "label": "Punto Delta"}
		]
		
	# Si es Altar Defense, no generamos portales al cargar. Esperamos la señal del servidor.
	if is_ad_portal:
		active_extract_points = []
		# Limpiar portales 2D viejos
		for old_area in get_tree().get_nodes_in_group("extraction_portal_areas"):
			old_area.queue_free()
		var parent_portals_3d = sub_viewport.get_node_or_null("Portals3D") if is_instance_valid(sub_viewport) else null
		if is_instance_valid(parent_portals_3d):
			for child in parent_portals_3d.get_children():
				child.queue_free()
		print("[Map_Extraction] Zona Altar Defense cargada. Esperando apertura de portales desde el servidor.")
		return
		
	_generate_extraction_portals_list(extract_points)

func _generate_extraction_portals_list(extract_points: Array):
	active_extract_points = extract_points
	
	# Verificar si ya hay puertas instanciadas por la clase base (en mapsConfig.objects)
	var has_placed_doors = false
	var z_str = str(zone_id)
	if "." in z_str and z_str.is_valid_float():
		var z_float = float(z_str)
		if z_float == int(z_float):
			z_str = str(int(z_float))
			
	if GameConstants.MAPS_CONFIG.has(z_str):
		var map_cfg = GameConstants.MAPS_CONFIG[z_str]
		if map_cfg.has("objects") and map_cfg.objects is Array:
			for obj in map_cfg.objects:
				if obj is Dictionary and obj.get("type") in ["door", "portal"]:
					has_placed_doors = true
					break
					
	if has_placed_doors:
		print("[Map_Extraction] Omitiendo instanciación de portales duplicados (detectadas puertas pre-colocadas en mapsConfig.objects).")
		return
	
	var parent_portals_3d = sub_viewport.get_node_or_null("Portals3D") if is_instance_valid(sub_viewport) else null
	if is_instance_valid(sub_viewport) and not parent_portals_3d:
		parent_portals_3d = Node3D.new()
		parent_portals_3d.name = "Portals3D"
		sub_viewport.add_child(parent_portals_3d)
		
	# Limpiar portales previos
	if is_instance_valid(parent_portals_3d):
		for child in parent_portals_3d.get_children():
			child.queue_free()
			
	# Limpiar portales 2D viejos
	for old_area in get_tree().get_nodes_in_group("extraction_portal_areas"):
		old_area.queue_free()
		
	# Cargar el Asset 3D GLB suministrado
	var portal_mesh_scene = load("res://assets/Puertas/3D/Puerta2/Puerta2.glb")
	if not portal_mesh_scene:
		print("[Map_Extraction] ADVERTENCIA: No se pudo cargar res://assets/Puertas/3D/Puerta2/Puerta2.glb. Usando cilindros 3D de fallback.")
		
	for i in range(extract_points.size()):
		var pt = extract_points[i]
		var pos_2d = Vector2(float(pt.x), float(pt.y))
		
		# A. Instanciar en el espacio 3D
		if portal_mesh_scene:
			var portal_3d = portal_mesh_scene.instantiate()
			portal_3d.name = "Portal3D_" + str(i)
			portal_3d.rotation_degrees = Vector3(-45, -90, 0)
			
			portal_3d.position = Vector3(pos_2d.x * scale_factor, 0.5, pos_2d.y * scale_factor * correction_z)
			portal_3d.scale = Vector3(10.0, 10.0, 10.0)
			parent_portals_3d.add_child(portal_3d)
			
			var light = OmniLight3D.new()
			light.name = "Light"
			light.position = Vector3(0, 0, 1.5)
			light.light_color = Color(0, 0.9, 1.0)
			light.light_energy = 3.5
			light.omni_range = 15.0
			portal_3d.add_child(light)
		else:
			var fallback_portal = CSGCylinder3D.new()
			fallback_portal.name = "Portal3D_Fallback_" + str(i)
			fallback_portal.position = Vector3(pos_2d.x * scale_factor, 0.5, pos_2d.y * scale_factor * correction_z)
			fallback_portal.radius = 4.0
			fallback_portal.height = 3.0
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0, 0.8, 1)
			mat.emission_enabled = true
			mat.emission = Color(0, 0.8, 1)
			fallback_portal.material = mat
			parent_portals_3d.add_child(fallback_portal)
			
		# B. Crear Zona Lógica 2D correspondiente
		var area_2d = Area2D.new()
		area_2d.name = "ExtractArea2D_" + str(i)
		area_2d.global_position = pos_2d
		area_2d.collision_layer = 1
		area_2d.collision_mask = 1
		area_2d.add_to_group("extraction_portal_areas")
		
		var trigger_shape = CollisionShape2D.new()
		var trigger_circle = CircleShape2D.new()
		var dynamic_radius = float(pt.get("proximityRadius", 300.0))
		trigger_circle.radius = dynamic_radius
		trigger_shape.shape = trigger_circle
		area_2d.add_child(trigger_shape)
		
		var marker = Label.new()
		marker.text = str(pt.get("label", "ZONA DE EXTRACCIÓN"))
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.position = Vector2(-100, -20)
		marker.modulate = Color.CYAN
		area_2d.add_child(marker)
		
		add_child(area_2d)

	print("[Map_Extraction] ¡Cargados con éxito ", extract_points.size(), " portales dinámicos!")

func _on_update_exit_portals(portals: Array):
	print("[Map_Extraction] Actualización de portales recibida: ", portals.size(), " portales activos.")
	if portals.size() == 0:
		active_extract_points = []
		# Limpiar portales 2D viejos
		for old_area in get_tree().get_nodes_in_group("extraction_portal_areas"):
			old_area.queue_free()
		var parent_portals_3d = sub_viewport.get_node_or_null("Portals3D") if is_instance_valid(sub_viewport) else null
		if is_instance_valid(parent_portals_3d):
			for child in parent_portals_3d.get_children():
				child.queue_free()
				
		var container = get_node_or_null("PortalUICanvas/PortalBtnContainer")
		if is_instance_valid(container):
			container.visible = false
	else:
		_generate_extraction_portals_list(portals)

func _create_portal_jump_ui():
	# Crear un CanvasLayer exclusivo para la interfaz premium de salto
	var ui_canvas = CanvasLayer.new()
	ui_canvas.name = "PortalUICanvas"
	ui_canvas.layer = 100 # Dibujar por encima del HUD general
	add_child(ui_canvas)
	
	# Contenedor principal de posición centrado abajo
	portal_btn_container = VBoxContainer.new()
	portal_btn_container.name = "PortalBtnContainer"
	portal_btn_container.add_to_group("portal_jump_ui")
	portal_btn_container.custom_minimum_size = Vector2(80, 80)
	portal_btn_container.size = Vector2(80, 80)
	portal_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	ui_canvas.add_child(portal_btn_container)
	portal_btn_container.anchor_left = 0.5
	portal_btn_container.anchor_right = 0.5
	portal_btn_container.anchor_top = 1.0
	portal_btn_container.anchor_bottom = 1.0
	portal_btn_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	portal_btn_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	portal_btn_container.offset_left = -40
	portal_btn_container.offset_right = 40
	portal_btn_container.offset_top = -130
	portal_btn_container.offset_bottom = -50
	
	# Contenedor para centrar el slot de 64x64
	var center_slot = CenterContainer.new()
	center_slot.name = "CenterContainer"
	portal_btn_container.add_child(center_slot)
	
	# El slot circular estilo habilidad
	var portal_btn = PanelContainer.new()
	portal_btn.name = "PortalJumpBtn"
	portal_btn.custom_minimum_size = Vector2(64, 64)
	portal_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	center_slot.add_child(portal_btn)
	
	# Añadir el modelo 3D del objeto en el centro
	portal_icon_viewport = SubViewport.new()
	portal_icon_viewport.name = "PortalIconViewport"
	portal_icon_viewport.size = Vector2(64, 64)
	portal_icon_viewport.transparent_bg = true
	portal_icon_viewport.own_world_3d = true
	portal_icon_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	portal_icon_viewport.handle_input_locally = false
	portal_icon_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	ui_canvas.add_child(portal_icon_viewport)

	var icon_cam = Camera3D.new()
	icon_cam.name = "IconCam"
	icon_cam.current = true
	icon_cam.look_at_from_position(Vector3(0, 0.8, 1.5), Vector3.ZERO)
	portal_icon_viewport.add_child(icon_cam)

	var icon_light = DirectionalLight3D.new()
	icon_light.look_at_from_position(Vector3(2, 4, 2), Vector3.ZERO)
	icon_light.light_energy = 1.5
	portal_icon_viewport.add_child(icon_light)

	var icon_light2 = OmniLight3D.new()
	icon_light2.position = Vector3(-1, 0.5, 0)
	icon_light2.light_energy = 0.8
	icon_light2.omni_range = 5
	portal_icon_viewport.add_child(icon_light2)

	var icon_env = WorldEnvironment.new()
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.ambient_light_energy = 2.0
	icon_env.environment = env
	portal_icon_viewport.add_child(icon_env)

	portal_icon_holder = Node3D.new()
	portal_icon_holder.name = "IconModelHolder"
	portal_icon_viewport.add_child(portal_icon_holder)

	var icon_texture = TextureRect.new()
	icon_texture.name = "IconTexture"
	icon_texture.texture = portal_icon_viewport.get_texture()
	icon_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_texture.expand = true
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portal_btn.add_child(icon_texture)
	
	# Estilo normal circular neón cian
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0.4, 0.6, 0.25)
	style_normal.border_width_left = 3
	style_normal.border_width_top = 3
	style_normal.border_width_right = 3
	style_normal.border_width_bottom = 3
	style_normal.border_color = Color(0, 0.9, 1.0, 0.8)
	style_normal.set_corner_radius_all(32)
	style_normal.anti_aliasing = true
	
	portal_btn.add_theme_stylebox_override("panel", style_normal)
	
	# Botón invisible para capturar el click de mouse
	portal_click_button = Button.new()
	portal_click_button.name = "ClickButton"
	portal_click_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portal_click_button.modulate.a = 0 # Completamente invisible
	portal_click_button.mouse_filter = Control.MOUSE_FILTER_STOP
	portal_btn.add_child(portal_click_button)
	
	# Etiqueta de texto debajo del portal
	portal_desc_label = Label.new()
	portal_desc_label.name = "PortalDescLabel"
	portal_desc_label.text = "ENTRAR AL PORTAL [ESPACIO]"
	portal_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portal_desc_label.add_theme_font_size_override("font_size", 12)
	portal_desc_label.add_theme_color_override("font_color", Color.CYAN)
	portal_desc_label.add_theme_color_override("font_outline_color", Color.BLACK)
	portal_desc_label.add_theme_constant_override("outline_size", 5)
	portal_btn_container.add_child(portal_desc_label)
	
	# Conectar el click al manejador genérico (portal / vault / loot)
	portal_click_button.pressed.connect(_on_interact_button_pressed)
	
	portal_btn_container.visible = false # Oculto por defecto
	_set_portal_icon("portal")

func _on_portal_jump_pressed(target_zone):
	# Enviar el evento de salto al servidor autoritativo
	print("[Map_Extraction] Iniciando salto interdimensional hacia Zona: ", target_zone)
	NetworkManager.send_event("changeZone", target_zone)

# Override del manejador genérico para usar _on_portal_jump_pressed en lugar de _on_map_portal_jump_pressed
func _on_interact_button_pressed():
	match _current_interact_mode:
		"portal":
			var target = portal_click_button.get_meta("target_zone") if portal_click_button.has_meta("target_zone") else "1"
			_on_portal_jump_pressed(target)
		"vault":
			if is_instance_valid(active_vault_node) and active_vault_node.has_method("_interact"):
				active_vault_node._interact()
		"loot":
			if is_instance_valid(active_loot_node) and active_loot_node.has_method("_interact"):
				active_loot_node._interact()

func _input(event):
	super._input(event)
	# Atajo premium configurable: Presionar la tecla asignada (por defecto Espacio) para saltar instantáneamente
	if event.is_action_pressed("portal_jump") and not event.is_echo():
		if is_instance_valid(portal_btn_container) and portal_btn_container.visible and _current_interact_mode == "portal":
			if is_instance_valid(portal_click_button):
				portal_click_button.pressed.emit()
				get_viewport().set_input_as_handled()

	if event.is_action_pressed("loot_claim") and not event.is_echo():
		if is_instance_valid(portal_btn_container) and portal_btn_container.visible and _current_interact_mode in ["vault", "loot"]:
			if is_instance_valid(portal_click_button):
				portal_click_button.pressed.emit()
				get_viewport().set_input_as_handled()

func _create_timers_ui():
	var ui_canvas = get_node_or_null("PortalUICanvas")
	if not is_instance_valid(ui_canvas): return
	
	var is_ad = _is_altar_defense_zone()
	var is_ar = _is_arena_zone()
	var is_ext = not is_ad and not is_ar
	
	# 1. TIMER DE COMBATE / EXTRACCIÓN (Top Center)
	var top_container = CenterContainer.new()
	top_container.name = "RaidTimerContainer"
	top_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_container.offset_top = 20
	ui_canvas.add_child(top_container)
	
	var timer_panel = PanelContainer.new()
	timer_panel.name = "TimerPanel"
	var sb_timer = StyleBoxFlat.new()
	sb_timer.bg_color = Color(0, 0, 0, 0.75)
	sb_timer.set_border_width_all(2)
	sb_timer.border_color = Color(0, 0.9, 1.0, 0.8)
	sb_timer.set_corner_radius_all(12)
	sb_timer.set_content_margin_all(8)
	timer_panel.add_theme_stylebox_override("panel", sb_timer)
	top_container.add_child(timer_panel)
	
	match_timer_label = Label.new()
	match_timer_label.name = "MatchTimerLabel"
	if is_ext:
		match_timer_label.text = "EXTRACCIÓN EN: --:--"
	elif is_ar:
		match_timer_label.text = "ARENA PVP"
		timer_panel.visible = false
	else:
		timer_panel.visible = false
	match_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_timer_label.add_theme_font_size_override("font_size", 13)
	match_timer_label.add_theme_color_override("font_color", Color.CYAN)
	match_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	match_timer_label.add_theme_constant_override("outline_size", 4)
	timer_panel.add_child(match_timer_label)

	# 1.5 BARRA DE HP Y SHIELD DEL ALTAR (Solo para Defensa al Altar)
	if is_ad:
		var altar_hud_container = CenterContainer.new()
		altar_hud_container.name = "AltarHUDContainer"
		altar_hud_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		altar_hud_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
		altar_hud_container.offset_top = 75
		ui_canvas.add_child(altar_hud_container)
		
		var altar_panel = PanelContainer.new()
		altar_panel.name = "AltarPanel"
		var sb_altar = StyleBoxFlat.new()
		sb_altar.bg_color = Color(0.05, 0.05, 0.05, 0.85)
		sb_altar.set_border_width_all(2)
		sb_altar.border_color = Color(0, 1.0, 0.5, 0.8) # Borde verde neón místico
		sb_altar.set_corner_radius_all(10)
		sb_altar.set_content_margin_all(8)
		altar_panel.add_theme_stylebox_override("panel", sb_altar)
		altar_hud_container.add_child(altar_panel)
		
		var vbox = VBoxContainer.new()
		altar_panel.add_child(vbox)
		
		var title = Label.new()
		title.text = "🏛️ ALTAR SENSORIAL 🏛️"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 11)
		title.add_theme_color_override("font_color", Color(0, 1.0, 0.5))
		vbox.add_child(title)
		
		# Escudo (Azul)
		var sh_progress = ProgressBar.new()
		sh_progress.name = "AltarShieldBar"
		sh_progress.custom_minimum_size = Vector2(250, 10)
		sh_progress.show_percentage = false
		var sb_sh_bg = StyleBoxFlat.new()
		sb_sh_bg.bg_color = Color(0.1, 0.1, 0.2, 0.6)
		sb_sh_bg.set_corner_radius_all(5)
		sh_progress.add_theme_stylebox_override("background", sb_sh_bg)
		var sb_sh_fill = StyleBoxFlat.new()
		sb_sh_fill.bg_color = Color(0, 0.5, 1.0, 0.95)
		sb_sh_fill.set_corner_radius_all(5)
		sh_progress.add_theme_stylebox_override("fill", sb_sh_fill)
		vbox.add_child(sh_progress)
		
		# Vida (Verde)
		var hp_progress = ProgressBar.new()
		hp_progress.name = "AltarHpBar"
		hp_progress.custom_minimum_size = Vector2(250, 10)
		hp_progress.show_percentage = false
		var sb_hp_bg = StyleBoxFlat.new()
		sb_hp_bg.bg_color = Color(0.2, 0.1, 0.1, 0.6)
		sb_hp_bg.set_corner_radius_all(5)
		hp_progress.add_theme_stylebox_override("background", sb_hp_bg)
		var sb_hp_fill = StyleBoxFlat.new()
		sb_hp_fill.bg_color = Color(0, 0.9, 0.1, 0.95)
		sb_hp_fill.set_corner_radius_all(5)
		hp_progress.add_theme_stylebox_override("fill", sb_hp_fill)
		vbox.add_child(hp_progress)
		
		var status_lbl = Label.new()
		status_lbl.name = "AltarStatusLabel"
		status_lbl.text = "Escudo: --/-- | Vida: --/--"
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.add_theme_font_size_override("font_size", 10)
		status_lbl.add_theme_color_override("font_color", Color.WHITE)
		vbox.add_child(status_lbl)
		
		# Inicialización con datos configurados en el cliente local si están cargados
		var full_cfg = GameConstants.get("FULL_CONFIG")
		if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
			var ad_cfg = full_cfg.gameModes.altar_defense
			var max_hp = float(ad_cfg.get("altarHp", 10000))
			var max_sh = float(ad_cfg.get("altarShield", 5000))
			sh_progress.max_value = max_sh
			sh_progress.value = max_sh
			hp_progress.max_value = max_hp
			hp_progress.value = max_hp
			status_lbl.text = "Escudo: " + str(int(max_sh)) + "/" + str(int(max_sh)) + " | Vida: " + str(int(max_hp)) + "/" + str(int(max_hp))
	
	# 2. ALERTA DE SPAWN LOCK (Top Center - below timer/altar)
	var center_container = CenterContainer.new()
	center_container.name = "SpawnLockContainer"
	center_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	
	# Desplazar hacia abajo si la barra del altar está presente para que no colisionen
	if is_ad:
		center_container.offset_top = 180
	else:
		center_container.offset_top = 85
		
	center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_container.grow_vertical = Control.GROW_DIRECTION_END
	ui_canvas.add_child(center_container)
	
	spawn_lock_container = PanelContainer.new()
	var sb_lock = StyleBoxFlat.new()
	sb_lock.bg_color = Color(0.1, 0, 0, 0.8) # Reddish dark
	sb_lock.set_border_width_all(3)
	sb_lock.border_color = Color(1.0, 0.3, 0.0, 0.9) # Glowing orange/red border
	sb_lock.set_corner_radius_all(16)
	sb_lock.set_content_margin_all(20)
	spawn_lock_container.add_theme_stylebox_override("panel", sb_lock)
	center_container.add_child(spawn_lock_container)
	
	spawn_lock_label = Label.new()
	spawn_lock_label.name = "SpawnLockLabel"
	spawn_lock_label.text = "🚨 BARRERA DE SPAWN ACTIVA 🚨\nSISTEMAS CONGELADOS: 10.0s"
	spawn_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawn_lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	spawn_lock_label.add_theme_font_size_override("font_size", 16)
	spawn_lock_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.0)) # Orange
	spawn_lock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	spawn_lock_label.add_theme_constant_override("outline_size", 5)
	spawn_lock_container.add_child(spawn_lock_label)
	
	spawn_lock_container.visible = false

func _on_altar_state_update(data: Dictionary):
	var hp = float(data.get("hp", 0))
	var max_hp = float(data.get("maxHp", 10000))
	var sh = float(data.get("shield", 0))
	var max_sh = float(data.get("maxShield", 5000))
	
	var ui_canvas = get_node_or_null("PortalUICanvas")
	if not is_instance_valid(ui_canvas): return
	
	var sh_bar = ui_canvas.get_node_or_null("AltarHUDContainer/AltarPanel/VBoxContainer/AltarShieldBar") as ProgressBar
	var hp_bar = ui_canvas.get_node_or_null("AltarHUDContainer/AltarPanel/VBoxContainer/AltarHpBar") as ProgressBar
	var status_lbl = ui_canvas.get_node_or_null("AltarHUDContainer/AltarPanel/VBoxContainer/AltarStatusLabel") as Label
	
	if is_instance_valid(sh_bar):
		sh_bar.max_value = max_sh
		sh_bar.value = sh
	if is_instance_valid(hp_bar):
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if is_instance_valid(status_lbl):
		status_lbl.text = "Escudo: " + str(int(sh)) + "/" + str(int(max_sh)) + " | Vida: " + str(int(hp)) + "/" + str(int(max_hp))

func _on_raid_time_update(data: Dictionary):
	var remaining = int(data.get("remaining", 0))
	if match_timer_label:
		var mins = int(float(remaining) / 60.0)
		var secs = remaining % 60
		var time_str = "%02d:%02d" % [mins, secs]
		match_timer_label.text = "⏱️ EXTRACCIÓN EN: " + time_str
		
		# Feedback de alerta cuando queda poco tiempo
		if remaining <= 120:
			match_timer_label.add_theme_color_override("font_color", Color.RED)
			var panel = match_timer_label.get_parent()
			if panel:
				panel.modulate = Color(1.3, 0.5, 0.5, 1.0)
		else:
			match_timer_label.add_theme_color_override("font_color", Color.CYAN)
			var panel = match_timer_label.get_parent()
			if panel:
				panel.modulate = Color.WHITE

# --- SISTEMA DE ARENAS (PVP) ---
func _is_arena_zone() -> bool:
	if str(zone_id).begins_with("arena_"):
		return true
	var full_cfg = GameConstants.get("FULL_CONFIG")
	if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("arenas"):
		var arena_maps = full_cfg.gameModes.arenas.get("maps", [])
		for m in arena_maps:
			if str(m) == str(zone_id):
				return true
	return false

func _spawn_arena_elements():
	if not _is_arena_zone(): return
	print("[ARENA] Generando elementos de combate para la Arena PvP...")
	
	var data = NetworkManager.current_arena_data
	if data.is_empty():
		print("[ARENA] Datos de arena vacíos. Cargando desde config.json como fallback...")
		var full_cfg = GameConstants.get("FULL_CONFIG")
		if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("arenas"):
			var arena_cfg = full_cfg.gameModes.arenas
			if arena_cfg.has("mapConfigs") and arena_cfg.mapConfigs.has(str(zone_id)):
				data = arena_cfg.mapConfigs[str(zone_id)]
		if data.is_empty():
			if not NetworkManager.arena_match_started.is_connected(_on_arena_match_started_spawn):
				NetworkManager.arena_match_started.connect(_on_arena_match_started_spawn)
			return
		
	# Limpiar elementos anteriores por seguridad
	_clear_arena_elements()
	
	# Obtener rutas de assets 3D
	# NOTA: Los assets de nexo son los Altares y los pilares son los Pilares,
	# igual que los usa el MapEditor3D_Evento_3_PVP.tscn
	var nexus_asset_path = "res://assets/Altares/3D/Altar1/Altar1.glb"
	var pillar_asset_path = "res://assets/Pilares/3D/Pilar1/Pilar1.glb"
	
	# Fallback: si no existen los Altares usar las Torres de defense, si existen
	if not ResourceLoader.exists(nexus_asset_path):
		nexus_asset_path = "res://assets/Arenas PVP/3D/Nexos/Nexo1/Nexo1.glb"
	if not ResourceLoader.exists(pillar_asset_path):
		pillar_asset_path = "res://assets/Arenas PVP/3D/Torres/Torre1/Torre1.glb"
	print("[ARENA] Usando assets → Nexo: ", nexus_asset_path, " | Pilar: ", pillar_asset_path)
	
	# Instanciar Nexos (soporta formato plano y anidado)
	var has_nexuses = false
	var nexuses_data = {}
	
	if data.has("nexuses"):
		nexuses_data = data.nexuses
		has_nexuses = true
	else:
		# Formato plano del AdminDash: nexusRed, nexusBlue
		if data.has("nexusRed") or data.has("nexusBlue"):
			nexuses_data = {}
			if data.has("nexusRed"):
				nexuses_data["red"] = data.nexusRed
			if data.has("nexusBlue"):
				nexuses_data["blue"] = data.nexusBlue
			has_nexuses = true
	
	if has_nexuses:
		if nexuses_data.has("red"):
			_spawn_nexus("nexus_red", nexuses_data.red, "red", nexus_asset_path)
		if nexuses_data.has("blue"):
			_spawn_nexus("nexus_blue", nexuses_data.blue, "blue", nexus_asset_path)
			
	# Instanciar Pilares
	if data.has("pillars"):
		for pillar in data.pillars:
			_spawn_pillar(pillar, pillar_asset_path)

func _on_arena_match_started_spawn(_data):
	_spawn_arena_elements()

func _on_config_retry_arena(_config):
	if _is_arena_zone() and arena_nexuses_nodes.is_empty() and arena_pillars_nodes.is_empty():
		_spawn_arena_elements()
		if not arena_nexuses_nodes.is_empty() or not arena_pillars_nodes.is_empty():
			if NetworkManager.admin_config_updated.is_connected(_on_config_retry_arena):
				NetworkManager.admin_config_updated.disconnect(_on_config_retry_arena)
			if NetworkManager.config_updated.is_connected(_on_config_retry_arena):
				NetworkManager.config_updated.disconnect(_on_config_retry_arena)

func _clear_arena_elements():
	for key in arena_nexuses_nodes:
		var n = arena_nexuses_nodes[key]
		if is_instance_valid(n.node_2d): n.node_2d.queue_free()
		if is_instance_valid(n.node_3d): n.node_3d.queue_free()
	arena_nexuses_nodes.clear()
	
	for key in arena_pillars_nodes:
		var n = arena_pillars_nodes[key]
		if is_instance_valid(n.node_2d): n.node_2d.queue_free()
		if is_instance_valid(n.node_3d): n.node_3d.queue_free()
	arena_pillars_nodes.clear()

func _spawn_nexus(id: String, cfg: Dictionary, team: String, asset_path: String):
	var pos_2d = Vector2(float(cfg.get("x", 0)), float(cfg.get("y", 0)))
	var max_hp = float(cfg.get("maxHp", cfg.get("hp", 10000)))
	var max_sh = float(cfg.get("maxShield", cfg.get("shield", 5000)))
	
	# 1. Objeto 2D Lógico
	var area = Area2D.new()
	area.name = id
	area.global_position = pos_2d
	area.collision_layer = 1 | 2
	area.collision_mask = 1 | 2
	area.add_to_group("arena_nexuses")
	area.set_meta("entity_id", id)
	area.set_meta("team", team)
	
	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 150.0
	col.shape = circle
	area.add_child(col)
	
	# Obstrucción Física 2D
	var static_body = StaticBody2D.new()
	static_body.name = id + "_Physics"
	static_body.collision_layer = 2
	static_body.collision_mask = 0
	
	var static_col = CollisionShape2D.new()
	var static_circle = CircleShape2D.new()
	static_circle.radius = 120.0
	static_col.shape = static_circle
	static_body.add_child(static_col)
	add_child(static_body)
	# Asignar la posición global después de añadirlo al árbol de la escena para evitar fallos de offset
	static_body.global_position = pos_2d
	
	# HUD Premium (Nombre y Barras Segmentadas)
	var hud = ArenaStructureHUD.new()
	hud.name_text = ("🔴 NEXO ROJO" if team == "red" else "🔵 NEXO AZUL")
	hud.team = team
	hud.current_hp = max_hp
	hud.max_hp = max_hp
	hud.current_shield = max_sh
	hud.max_shield = max_sh
	hud.bar_width = 120.0
	hud.num_segments = 10
	hud.position = Vector2(0, -90)
	area.add_child(hud)
	
	add_child(area)
	
	# 2. Instanciación 3D
	var node_3d = _instantiate_model_3d(asset_path, pos_2d, Vector3(18.0, 18.0, 18.0), team)
	
	arena_nexuses_nodes[id] = {
		"node_2d": area,
		"node_3d": node_3d,
		"hud": hud,
		"max_hp": max_hp,
		"max_sh": max_sh
	}

func _spawn_pillar(cfg: Dictionary, asset_path: String):
	var id = cfg.get("id", cfg.get("name", "pillar_" + str(cfg.get("x", 0))))
	var team = cfg.get("team", "red")
	var pos_2d = Vector2(float(cfg.x), float(cfg.y))
	var max_hp = float(cfg.get("maxHp", cfg.get("hp", 3000)))
	var max_sh = float(cfg.get("maxShield", cfg.get("shield", 1500)))
	
	# 1. Objeto 2D Lógico
	var area = Area2D.new()
	area.name = id
	area.global_position = pos_2d
	area.collision_layer = 1 | 2
	area.collision_mask = 1 | 2
	area.add_to_group("arena_pillars")
	area.set_meta("entity_id", id)
	area.set_meta("team", team)
	
	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 80.0
	col.shape = circle
	area.add_child(col)
	
	# Obstrucción Física 2D
	var static_body = StaticBody2D.new()
	static_body.name = id + "_Physics"
	static_body.collision_layer = 2
	static_body.collision_mask = 0
	
	var static_col = CollisionShape2D.new()
	var static_circle = CircleShape2D.new()
	static_circle.radius = 60.0
	static_col.shape = static_circle
	static_body.add_child(static_col)
	add_child(static_body)
	# Asignar la posición global después de añadirlo al árbol de la escena para evitar fallos de offset
	static_body.global_position = pos_2d
	
	# HUD Premium (Nombre y Barras Segmentadas)
	var hud = ArenaStructureHUD.new()
	hud.name_text = cfg.get("name", "PILAR")
	hud.team = team
	hud.current_hp = max_hp
	hud.max_hp = max_hp
	hud.current_shield = max_sh
	hud.max_shield = max_sh
	hud.bar_width = 80.0
	hud.num_segments = 8
	hud.position = Vector2(0, -70)
	area.add_child(hud)
	
	add_child(area)
	
	# 2. Instanciación 3D
	var node_3d = _instantiate_model_3d(asset_path, pos_2d, Vector3(10.0, 10.0, 10.0), team)
	
	arena_pillars_nodes[id] = {
		"node_2d": area,
		"node_3d": node_3d,
		"hud": hud,
		"max_hp": max_hp,
		"max_sh": max_sh
	}

func _instantiate_model_3d(asset_path: String, pos_2d: Vector2, scale_3d: Vector3, team: String) -> Node3D:
	if not is_instance_valid(sub_viewport): return null
	
	var path = asset_path.replace("\\", "/")
	if path.begins_with("res://"):
		pass
	elif ":" in path:
		var parts = path.split("/descon/")
		if parts.size() > 1:
			path = "res://" + parts[1]
		else:
			path = "res://assets/Arenas PVP/3D/Nexos/Nexo1/Nexo1.glb"
			
	var scene = load(path)
	if not scene:
		var fallback = CSGCylinder3D.new()
		fallback.radius = scale_3d.x * 0.3
		fallback.height = scale_3d.y * 1.5
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.2) if team == "red" else Color(0.2, 0.6, 1)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.5
		fallback.material = mat
		
		fallback.position = Vector3(pos_2d.x * scale_factor, 0.0, pos_2d.y * scale_factor * correction_z)
		sub_viewport.add_child(fallback)
		return fallback
		
	var obj = scene.instantiate()
	obj.position = Vector3(pos_2d.x * scale_factor, 0.0, pos_2d.y * scale_factor * correction_z)
	obj.scale = scale_3d
	
	# Corregir inclinación si es el nexo (rotarlo 45 grados en Y para que quede derecho)
	if asset_path.contains("Nexo"):
		obj.rotation_degrees = Vector3(0, 45, 0)
	else:
		obj.rotation_degrees = Vector3(0, 0, 0)
	
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.2) if team == "red" else Color(0.2, 0.6, 1.0)
	light.light_energy = 4.0
	light.omni_range = 10.0
	light.position = Vector3(0, 3.0, 0)
	obj.add_child(light)
	
	sub_viewport.add_child(obj)
	return obj

func _on_arena_state_update(data: Dictionary):
	if data.has("nexuses"):
		var nexuses = data.nexuses
		for team in ["red", "blue"]:
			var id = "nexus_" + team
			if nexuses.has(team) and arena_nexuses_nodes.has(id):
				var n_data = nexuses[team]
				var node_info = arena_nexuses_nodes[id]
				if is_instance_valid(node_info.get("hud")):
					var hp = float(n_data.get("hp", 0))
					var sh = float(n_data.get("shield", 0))
					node_info.hud.update_stats(hp, node_info.max_hp, sh, node_info.max_sh)
					
	if data.has("pillars"):
		for p_data in data.pillars:
			var id = p_data.get("id", "")
			if arena_pillars_nodes.has(id):
				var node_info = arena_pillars_nodes[id]
				if is_instance_valid(node_info.get("hud")):
					var hp = float(p_data.get("hp", 0))
					var sh = float(p_data.get("shield", 0))
					node_info.hud.update_stats(hp, node_info.max_hp, sh, node_info.max_sh)
					
	var remaining = int(data.get("remainingTime", 0))
	if match_timer_label and remaining > 0:
		var mins = int(float(remaining) / 60.0)
		var secs = remaining % 60
		var time_str = "%02d:%02d" % [mins, secs]
		match_timer_label.text = "⏱️ PVP RESTANTE: " + time_str
		match_timer_label.add_theme_color_override("font_color", Color.YELLOW)


# ==============================================================================
# --- CLASE HELPER PARA HUD DE ESTRUCTURAS DE ARENA (Nexos y Torres) ---
# ==============================================================================
class ArenaStructureHUD extends Node2D:
	var name_text: String = ""
	var team: String = ""
	var current_hp: float = 0.0
	var max_hp: float = 1.0
	var current_shield: float = 0.0
	var max_shield: float = 1.0
	var bar_width: float = 100.0
	var num_segments: int = 8
	var label_node: Label = null

	func _ready():
		label_node = Label.new()
		label_node.text = name_text
		label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Aplicar outline negro premium
		label_node.add_theme_font_size_override("font_size", 11)
		label_node.add_theme_color_override("font_outline_color", Color.BLACK)
		label_node.add_theme_constant_override("outline_size", 4)
		
		# Color del texto según team
		if team == "red":
			label_node.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		elif team == "blue":
			label_node.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0))
		else:
			label_node.add_theme_color_override("font_color", Color.WHITE)
			
		label_node.custom_minimum_size = Vector2(200, 20)
		label_node.position = Vector2(-100, -32)
		add_child(label_node)

	func update_stats(hp: float, max_h: float, sh: float, max_s: float):
		current_hp = hp
		max_hp = max_h
		current_shield = sh
		max_shield = max_s
		queue_redraw()

	func _draw():
		var gap = 2.0
		var seg_w = (bar_width - (gap * (num_segments - 1.0))) / float(num_segments)
		
		var sh_pct = clamp(current_shield / max_shield if max_shield > 0.0 else 0.0, 0.0, 1.0)
		var hp_pct = clamp(current_hp / max_hp if max_hp > 0.0 else 0.0, 0.0, 1.0)
		
		# Dibujar barras segmentadas abajo del nombre
		var base_y = -10.0
		
		for i in range(num_segments):
			var x = -(bar_width / 2.0) + (i * (seg_w + gap))
			
			# Fondo (Escudo) - Cian oscuro semi-transparente
			draw_rect(Rect2(x, base_y - 8, seg_w, 4), Color(0.0, 1.0, 1.0, 0.25))
			var f_sh = clamp((sh_pct * num_segments) - i, 0.0, 1.0)
			if f_sh > 0.0:
				draw_rect(Rect2(x, base_y - 8, seg_w * f_sh, 4), Color(0.0, 0.85, 1.0))
			
			# Fondo (HP) - Verde oscuro semi-transparente
			draw_rect(Rect2(x, base_y - 2, seg_w, 4), Color(0.0, 0.8, 0.0, 0.25))
			var f_hp = clamp((hp_pct * num_segments) - i, 0.0, 1.0)
			if f_hp > 0.0:
				var c = Color(0.0, 0.8, 0.1) if hp_pct > 0.3 else Color(1.0, 0.1, 0.1)
				draw_rect(Rect2(x, base_y - 2, seg_w * f_hp, 4), c)
