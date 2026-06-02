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

# Determina si esta instancia es una partida de Defensa del Altar (dinámico desde config)
func _is_altar_defense_zone() -> bool:
	var full_cfg = GameConstants.get("FULL_CONFIG")
	if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("altar_defense"):
		var ad_maps = full_cfg.gameModes.altar_defense.get("maps", [])
		for m in ad_maps:
			if int(m) == zone_id:
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
		camera_3d.transform = Transform3D(
			Basis(
				Vector3(1, 0, 0),
				Vector3(0, 0.707107, 0.707107),
				Vector3(0, -0.707107, 0.707107)
			).orthonormalized(),
			Vector3(0, 30.0, 30.0)
		)
		_apply_camera_headlight(camera_3d)
	
	# Crear los componentes visuales del botón flotante interactivo de salto
	_create_portal_jump_ui()
	
	# Generar obstáculos procedimentales en el mapa de 10,000 x 10,000 px (Desactivado a petición del usuario)
	# _generate_procedural_obstacles()
	
	# Generar portales 3D de extracción/escape en los puntos configurados en el AdminDash
	_generate_extraction_portals()

	# Inicializar cuenta regresiva de spawn lock y tamaño de mundo desde la config dinámica
	var spawn_lock_ms = 10000.0
	var is_ad = _is_altar_defense_zone()
	var full_config = GameConstants.get("FULL_CONFIG")
	if full_config and full_config.has("gameModes"):
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
					
					# Posicionar la burbuja 3D en base a la coordenada 2D del spawn
					var correction_z = 1.41421356
					spawn_bubble_mesh.position.x = initial_player_pos.x * scale_factor
					spawn_bubble_mesh.position.z = initial_player_pos.y * scale_factor * correction_z
					spawn_bubble_mesh.position.y = 0.0
					
					sub_viewport.add_child(spawn_bubble_mesh)
					print("[SpawnLock] Burbuja protectora 3D inicializada con radio: ", r_3d)

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
				
	var container = get_node_or_null("PortalUICanvas/PortalBtnContainer")
	if is_instance_valid(container):
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
				
			var desc_lbl = container.get_node_or_null("PortalDescLabel")
			if desc_lbl:
				desc_lbl.text = "ENTRAR A " + target_name.to_upper() + " [" + bind_key_text + " / Clic]"
				
			var click_btn = container.get_node_or_null("CenterContainer/PortalJumpBtn/ClickButton")
			if click_btn:
				click_btn.set_meta("target_zone", near_portal_target_zone)
				
			container.visible = true
		else:
			container.visible = false

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
			var correction_z = 1.41421356
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
			var correction_z = 1.41421356
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
			
			var correction_z = 1.41421356
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
			var correction_z = 1.41421356
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
	var btn_container = VBoxContainer.new()
	btn_container.name = "PortalBtnContainer"
	btn_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	btn_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	# Desplazar hacia arriba para quedar flotando hermosamente sobre la barra de habilidades
	btn_container.position.y -= 190
	ui_canvas.add_child(btn_container)
	
	# Contenedor para centrar el slot de 64x64
	var center_slot = CenterContainer.new()
	center_slot.name = "CenterContainer"
	btn_container.add_child(center_slot)
	
	# El slot circular estilo habilidad
	var portal_btn = PanelContainer.new()
	portal_btn.name = "PortalJumpBtn"
	portal_btn.custom_minimum_size = Vector2(64, 64)
	portal_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	center_slot.add_child(portal_btn)
	
	# Añadir el dibujo del portal en el centro (emoji galáctico)
	var icon = Label.new()
	icon.text = "🌀"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 28)
	portal_btn.add_child(icon)
	
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
	var click_btn = Button.new()
	click_btn.name = "ClickButton"
	click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_btn.modulate.a = 0 # Completamente invisible
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	portal_btn.add_child(click_btn)
	
	# Etiqueta de texto debajo del portal
	var desc_lbl = Label.new()
	desc_lbl.name = "PortalDescLabel"
	desc_lbl.text = "ENTRAR AL PORTAL [ESPACIO]"
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color.CYAN)
	desc_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	desc_lbl.add_theme_constant_override("outline_size", 5)
	btn_container.add_child(desc_lbl)
	
	# Conectar el click al de salto
	click_btn.pressed.connect(func():
		var target = click_btn.get_meta("target_zone") if click_btn.has_meta("target_zone") else "1"
		_on_portal_jump_pressed(target)
	)
	
	btn_container.visible = false # Oculto por defecto

func _on_portal_jump_pressed(target_zone):
	# Enviar el evento de salto al servidor autoritativo
	print("[Map_Extraction] Iniciando salto interdimensional hacia Zona: ", target_zone)
	NetworkManager.send_event("changeZone", target_zone)

func _input(event):
	# Atajo premium configurable: Presionar la tecla asignada (por defecto Espacio) para saltar instantáneamente
	if event.is_action_pressed("portal_jump") and not event.is_echo():
		var container = get_node_or_null("PortalUICanvas/PortalBtnContainer")
		if is_instance_valid(container) and container.visible:
			var click_btn = get_node_or_null("PortalUICanvas/PortalBtnContainer/CenterContainer/PortalJumpBtn/ClickButton")
			if is_instance_valid(click_btn):
				click_btn.pressed.emit()
				get_viewport().set_input_as_handled()

func _create_timers_ui():
	var ui_canvas = get_node_or_null("PortalUICanvas")
	if not is_instance_valid(ui_canvas): return
	
	# 1. TIMER DE EXTRACCIÓN GLOBAL (Top Center)
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
	sb_timer.border_color = Color(0, 0.9, 1.0, 0.8) # Glowing cyan
	sb_timer.set_corner_radius_all(12)
	sb_timer.set_content_margin_all(8)
	timer_panel.add_theme_stylebox_override("panel", sb_timer)
	top_container.add_child(timer_panel)
	
	match_timer_label = Label.new()
	match_timer_label.name = "MatchTimerLabel"
	match_timer_label.text = "⏱️ CARGANDO RAID... "
	match_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_timer_label.add_theme_font_size_override("font_size", 13)
	match_timer_label.add_theme_color_override("font_color", Color.CYAN)
	match_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	match_timer_label.add_theme_constant_override("outline_size", 4)
	timer_panel.add_child(match_timer_label)

	# 1.5 BARRA DE HP Y SHIELD DEL ALTAR (Para Defensa al Altar)
	var is_ad = _is_altar_defense_zone()
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
