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

func _ready():
	viewport_container = $ViewportCanvas/SubViewportContainer
	viewport_container.stretch = true
	sub_viewport = $ViewportCanvas/SubViewportContainer/SubViewport
	camera_3d = $ViewportCanvas/SubViewportContainer/SubViewport/Camera3D
	asteroids_3d = $ViewportCanvas/SubViewportContainer/SubViewport/Asteroids3D
	
	super._ready()
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
	
	# Ajustar el viewport al tamaño inicial de la pantalla
	_on_window_resized()
	get_tree().get_root().size_changed.connect(_on_window_resized)
	
	# Crear los componentes visuales del botón flotante interactivo de salto
	_create_portal_jump_ui()
	
	# Generar obstáculos procedimentales en el mapa de 10,000 x 10,000 px (Desactivado a petición del usuario)
	# _generate_procedural_obstacles()
	
	# Generar portales 3D de extracción en los puntos configurados en el AdminDash
	_generate_extraction_portals()

	# Inicializar cuenta regresiva de spawn lock y tamaño de mundo desde la config dinámica
	var spawn_lock_ms = 10000.0
	if GameConstants.get("FULL_CONFIG") and GameConstants.FULL_CONFIG.has("gameModes") and GameConstants.FULL_CONFIG.gameModes.has("extraction"):
		var ext = GameConstants.FULL_CONFIG.gameModes.extraction
		if ext.has("spawnLockTime"):
			spawn_lock_ms = float(ext.spawnLockTime)
		if ext.has("width") and float(ext.width) > 0:
			world_size = float(ext.width)
	spawn_lock_remaining = spawn_lock_ms / 1000.0

	# Crear HUD UI de temporizadores
	_create_timers_ui()

	# Conectar señal de actualización de raid desde red
	if NetworkManager:
		if not NetworkManager.raid_time_update.is_connected(_on_raid_time_update):
			NetworkManager.raid_time_update.connect(_on_raid_time_update)

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
				if GameConstants.get("FULL_CONFIG") and GameConstants.FULL_CONFIG.has("gameModes") and GameConstants.FULL_CONFIG.gameModes.has("extraction"):
					var ext = GameConstants.FULL_CONFIG.gameModes.extraction
					if ext.has("spawnPoints"):
						var min_dist = 999999.0
						for sp in ext.spawnPoints:
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
					spawn_bubble_mesh.position.x = initial_player_pos.x * scale_factor
					spawn_bubble_mesh.position.z = initial_player_pos.y * scale_factor
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

	# --- SINCRONIZACIÓN DE CÁMARA PERFECTA DE ALTO NIVEL (Estilo MU Online) ---
	# Para resolver el "desfase raro" definitivamente:
	# El centro de la pantalla no es la posición exacta de la nave (porque la cámara tiene smoothing/suavizado y se retrasa).
	# El centro real de la pantalla en píxeles es cam_2d.get_screen_center_position().
	# Si sincronizamos la cámara 3D con el centro de pantalla real en lugar de la nave,
	# los portales 3D se fijan pixel-perfect con el suelo y con los textos 2D en absoluta cohesión.
	
	var target_pos = Vector2.ZERO
	var current_zoom = 1.0
	
	var cam_2d = get_viewport().get_camera_2d()
	if is_instance_valid(cam_2d):
		target_pos = cam_2d.get_screen_center_position() # Obtener el centro real renderizado de la pantalla
		current_zoom = cam_2d.zoom.x
	else:
		if is_instance_valid(player_node):
			target_pos = player_node.global_position
	
	if is_instance_valid(camera_3d):
		if current_zoom <= 0.01:
			current_zoom = 1.0
			
		var viewport_height = float(get_viewport().size.y)
		if viewport_height <= 0:
			viewport_height = 1080.0
			
		var dynamic_height = camera_height
		if use_orthogonal:
			camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera_3d.size = (viewport_height * scale_factor) / current_zoom
			camera_3d.position.y = camera_height
			dynamic_height = camera_height
		else:
			camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
			var target_visible_height = (viewport_height * scale_factor) / current_zoom
			dynamic_height = target_visible_height / (2.0 * tan(deg_to_rad(camera_3d.fov / 2.0)))
			camera_3d.position.y = dynamic_height
		
		# Sincronizar posición de la cámara 3D con inclinación tridimensional dinámica (45 grados de inclinación original)
		camera_3d.position.x = target_pos.x * scale_factor
		camera_3d.position.z = (target_pos.y * scale_factor) + dynamic_height
		camera_3d.look_at(Vector3(target_pos.x * scale_factor, 0.0, target_pos.y * scale_factor), Vector3.UP)

func _process(delta):
	# Rotación procedimental y lenta de los asteroides 3D de fondo para dar vida a la escena
	if is_instance_valid(asteroids_3d):
		for asteroid in asteroids_3d.get_children():
			if asteroid is Node3D:
				var speed_mult = 0.05 + (abs(asteroid.name.hash() % 10) * 0.01)
				asteroid.rotate_x(delta * speed_mult * 0.5)
				asteroid.rotate_y(delta * speed_mult)
				asteroid.rotate_z(delta * speed_mult * 0.3)
				
	# --- EFECTO GIROSCÓPICO INTERDIMENSIONAL (WOBBLE MULTIEJE) ---
	var parent_portals_3d = get_node_or_null("ViewportCanvas/SubViewportContainer/SubViewport/Portals3D")
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

func _on_window_resized():
	if is_instance_valid(viewport_container) and viewport_container.stretch:
		return
	var size = get_viewport().size
	if is_instance_valid(sub_viewport):
		sub_viewport.set_deferred("size", size)

func _generate_procedural_obstacles():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var parent_walls_3d = get_node_or_null("ViewportCanvas/SubViewportContainer/SubViewport/Walls3D")
	var parent_asteroids_3d = get_node_or_null("ViewportCanvas/SubViewportContainer/SubViewport/Asteroids3D")
	var parent_walls_2d = get_node_or_null("Walls")
	var parent_asteroids_2d = get_node_or_null("Asteroids")
	
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
			box_3d.position = Vector3(pos_2d.x * scale_factor, 0, pos_2d.y * scale_factor)
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
			sphere_3d.position = Vector3(pos_2d.x * scale_factor, rng.randf_range(-2.0, 2.0), pos_2d.y * scale_factor)
			sphere_3d.radius = radius_2d * scale_factor
			sphere_3d.radial_segments = 16
			sphere_3d.rings = 12
			sphere_3d.material = mat_rock
			parent_asteroids_3d.add_child(sphere_3d)
			
	print("[Map_Extraction] ¡Generación procedimental completada! Creados ", num_obstacles, " obstáculos.")

func _generate_extraction_portals():
	# Intentar obtener los puntos configurados dinámicamente desde el servidor (vía GameConstants)
	var extract_points = []
	if GameConstants.get("FULL_CONFIG") and GameConstants.FULL_CONFIG.has("gameModes") and GameConstants.FULL_CONFIG.gameModes.has("extraction"):
		var ext = GameConstants.FULL_CONFIG.gameModes.extraction
		if ext.has("extractPoints"):
			extract_points = ext.extractPoints
			
	# Fallback robusto con las coordenadas exactas de config.json si el servidor aún no envía la config completa
	if extract_points.size() == 0:
		extract_points = [
			{"x": 2974, "y": 5038, "label": "Punto Alfa"},
			{"x": 6920, "y": 5070, "label": "Punto Beta"},
			{"x": 5019, "y": 3025, "label": "Punto Gamma"},
			{"x": 5003, "y": 7019, "label": "Punto Delta"}
		]
		
	active_extract_points = extract_points
		
	var parent_portals_3d = get_node_or_null("ViewportCanvas/SubViewportContainer/SubViewport/Portals3D")
	if not parent_portals_3d:
		parent_portals_3d = Node3D.new()
		parent_portals_3d.name = "Portals3D"
		sub_viewport.add_child(parent_portals_3d)
		
	# Limpiar portales previos
	for child in parent_portals_3d.get_children():
		child.queue_free()
		
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
			
			# INCLINAR EL PORTAL DE CARA A LA CÁMARA OBLÍCUA:
			# Rotamos el modelo 3D -45 grados en el eje X para inclinarlo hacia adelante
			# y -90 grados en Y para alinearlo con el modelado nativo.
			portal_3d.rotation_degrees = Vector3(-45, -90, 0)
			
			# Colocamos las puertas a la misma altura que los obstáculos, ligeramente elevadas
			portal_3d.position = Vector3(pos_2d.x * scale_factor, 0.5, pos_2d.y * scale_factor)
			
			# ¡TAMAÑO AJUSTADO Y PERFECTO!:
			# Escalamos a (10.0, 10.0, 10.0), lo cual es ideal y visible sin ser abrumador.
			portal_3d.scale = Vector3(10.0, 10.0, 10.0)
			parent_portals_3d.add_child(portal_3d)
			
			# Añadir un efecto de luz de punto para destacar la puerta en la penumbra
			var light = OmniLight3D.new()
			light.name = "Light"
			light.position = Vector3(0, 0, 1.5)
			light.light_color = Color(0, 0.9, 1.0)
			light.light_energy = 3.5
			light.omni_range = 15.0
			portal_3d.add_child(light)
		else:
			# Fallback elegante usando formas básicas brillantes de Godot
			var fallback_portal = CSGCylinder3D.new()
			fallback_portal.name = "Portal3D_Fallback_" + str(i)
			fallback_portal.position = Vector3(pos_2d.x * scale_factor, 0.5, pos_2d.y * scale_factor)
			fallback_portal.radius = 4.0
			fallback_portal.height = 3.0
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0, 0.8, 1)
			mat.emission_enabled = true
			mat.emission = Color(0, 0.8, 1)
			fallback_portal.material = mat
			parent_portals_3d.add_child(fallback_portal)
			
		# B. Crear Zona Lógica 2D correspondiente para la lógica de extracción del cliente (SIN COLISIÓN FÍSICA)
		# Eliminamos el StaticBody2D por completo a petición del usuario para evitar colisiones molestas al volar.
		var area_2d = Area2D.new()
		area_2d.name = "ExtractArea2D_" + str(i)
		area_2d.global_position = pos_2d
		area_2d.collision_layer = 1
		area_2d.collision_mask = 1
		
		var trigger_shape = CollisionShape2D.new()
		var trigger_circle = CircleShape2D.new()
		var dynamic_radius = float(pt.get("proximityRadius", 300.0))
		trigger_circle.radius = dynamic_radius # Rango de activación de extracción dinámico
		trigger_shape.shape = trigger_circle
		area_2d.add_child(trigger_shape)
		
		# Agregar etiqueta visual de proximidad en el suelo 2D para ubicarlo con precisión
		var marker = Label.new()
		marker.text = str(pt.get("label", "ZONA DE EXTRACCIÓN"))
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.position = Vector2(-100, -20)
		marker.modulate = Color.CYAN
		area_2d.add_child(marker)
		
		add_child(area_2d)

	print("[Map_Extraction] ¡Cargados con éxito ", extract_points.size(), " portales 3D basados en la configuración!")

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
	
	# 2. ALERTA DE SPAWN LOCK (Top Center - below timer)
	var center_container = CenterContainer.new()
	center_container.name = "SpawnLockContainer"
	center_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
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
