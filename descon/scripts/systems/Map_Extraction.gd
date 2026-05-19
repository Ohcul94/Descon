extends BaseMap

# Map_Extraction.gd
# Lógica para la sincronización de cámara 2D a 3D en el Lienzo 3D Único.
# Hereda de BaseMap para compatibilidad del sistema de carga de mapas.

@export var scale_factor: float = 0.02 # Relación entre 2D y 3D (1px 2D = 0.02 unidades 3D)
@export var camera_height: float = 30.0 # Altura base de la cámara 3D en modo perspectiva
@export var use_orthogonal: bool = true # Activar proyección ortogonal para eliminar distorsión y deslizamiento visual (Sensación Sólida 1:1)

@onready var viewport_container: SubViewportContainer = $ViewportCanvas/SubViewportContainer
@onready var sub_viewport: SubViewport = $ViewportCanvas/SubViewportContainer/SubViewport
@onready var camera_3d: Camera3D = $ViewportCanvas/SubViewportContainer/SubViewport/Camera3D
@onready var asteroids_3d: Node3D = $ViewportCanvas/SubViewportContainer/SubViewport/Asteroids3D

var player_node: Node2D = null

func _ready():
	super._ready()
	
	# Ajustar el viewport al tamaño inicial de la pantalla
	_on_window_resized()
	get_tree().get_root().size_changed.connect(_on_window_resized)
	
	# Generar obstáculos procedimentales en el mapa de 10,000 x 10,000 px (Desactivado a petición del usuario)
	# _generate_procedural_obstacles()
	
	# Generar portales 3D de extracción en los puntos configurados en el AdminDash
	_generate_extraction_portals()

func _physics_process(_delta):
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
		# Fallback a la nave si no hay cámara
		if not is_instance_valid(player_node):
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0:
				player_node = players[0]
		if is_instance_valid(player_node):
			target_pos = player_node.global_position
	
	if is_instance_valid(camera_3d):
		if current_zoom <= 0.01:
			current_zoom = 1.0
			
		var viewport_height = float(get_viewport().size.y)
		if viewport_height <= 0:
			viewport_height = 1080.0
			
		if use_orthogonal:
			camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera_3d.size = (viewport_height * scale_factor) / current_zoom
			camera_3d.position.y = camera_height
		else:
			camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
			var target_visible_height = (viewport_height * scale_factor) / current_zoom
			camera_3d.position.y = target_visible_height / (2.0 * tan(deg_to_rad(camera_3d.fov / 2.0)))
		
		# Sincronizar posición horizontal (X, Z) de la cámara 3D con el centro exacto de la pantalla
		camera_3d.position.x = target_pos.x * scale_factor
		camera_3d.position.z = target_pos.y * scale_factor

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

func _on_window_resized():
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
		trigger_circle.radius = 150.0 # Rango de activación de extracción
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
