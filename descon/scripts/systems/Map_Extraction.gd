extends BaseMap

# Map_Extraction.gd
# Lógica para la sincronización de cámara 2D a 3D en el Lienzo 3D Único.
# Hereda de BaseMap para compatibilidad del sistema de carga de mapas.

@export var scale_factor: float = 0.02 # Relación entre 2D y 3D (1px 2D = 0.02 unidades 3D)
@export var camera_height: float = 30.0 # Altura base de la cámara 3D sobre el plano horizontal

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
	
	# Generar obstáculos procedimentales en el mapa de 10,000 x 10,000 px
	_generate_procedural_obstacles()

func _process(delta):
	# Intentar buscar el jugador si aún no lo tenemos referenciado
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
	
	# Sincronizar la cámara 3D con la CÁMARA 2D (evita el desfase de suavizado/smoothing de la nave)
	var target_pos = Vector2.ZERO
	var current_zoom = 1.0
	var cam_2d = get_viewport().get_camera_2d()
	
	if is_instance_valid(cam_2d):
		target_pos = cam_2d.global_position
		current_zoom = cam_2d.zoom.x # Copiar el valor de zoom en el eje X (es igual en Y)
	elif is_instance_valid(player_node):
		target_pos = player_node.global_position
		
	if is_instance_valid(camera_3d):
		# 1. En 3D, el plano horizontal es X y Z.
		camera_3d.position.x = target_pos.x * scale_factor
		camera_3d.position.z = target_pos.y * scale_factor
		
		# 2. Sincronizar el Zoom 2D con la Altura de la Cámara 3D (Eje Y)
		# A menor zoom 2D (alejarse), mayor altura 3D (objetos se ven más chicos)
		# A mayor zoom 2D (acercarse), menor altura 3D (objetos se ven más grandes)
		if current_zoom <= 0.01:
			current_zoom = 1.0
		camera_3d.position.y = camera_height / current_zoom
		
	# Rotación procedimental y lenta de los asteroides 3D de fondo para dar vida a la escena
	if is_instance_valid(asteroids_3d):
		for asteroid in asteroids_3d.get_children():
			if asteroid is Node3D:
				# Rotar en diferentes ejes y velocidades según el nombre para variedad
				var speed_mult = 0.05 + (abs(asteroid.name.hash() % 10) * 0.01)
				asteroid.rotate_x(delta * speed_mult * 0.5)
				asteroid.rotate_y(delta * speed_mult)
				asteroid.rotate_z(delta * speed_mult * 0.3)

func _on_window_resized():
	var size = get_viewport().size
	if is_instance_valid(sub_viewport):
		# Sincronizar el tamaño del viewport 3D usando set_deferred para evitar advertencias de inicialización
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
			# --- 1. PARED METÁLICA ---
			var size_2d = rng.randf_range(200.0, 450.0) # Tamaño en píxeles 2D
			
			# A. Elemento Físico 2D
			var static_body = StaticBody2D.new()
			static_body.name = "Wall2D_" + str(i)
			static_body.collision_layer = 2
			static_body.collision_mask = 0 # No necesita máscara, solo es estático
			static_body.add_to_group("obstacles")
			static_body.global_position = pos_2d
			
			var collision_shape = CollisionShape2D.new()
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = Vector2(size_2d, size_2d)
			collision_shape.shape = rect_shape
			static_body.add_child(collision_shape)
			parent_walls_2d.add_child(static_body)
			
			# B. Elemento Visual 3D
			var box_3d = CSGBox3D.new()
			box_3d.name = "Wall3D_" + str(i)
			box_3d.position = Vector3(pos_2d.x * scale_factor, 0, pos_2d.y * scale_factor)
			box_3d.size = Vector3(size_2d * scale_factor, rng.randf_range(5.0, 10.0), size_2d * scale_factor)
			box_3d.material = mat_metal
			parent_walls_3d.add_child(box_3d)
			
		else:
			# --- 2. ASTEROIDE ROCOSO ---
			var radius_2d = rng.randf_range(100.0, 250.0) # Radio en píxeles 2D
			
			# A. Elemento Físico 2D
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
			
			# B. Elemento Visual 3D
			var sphere_3d = CSGSphere3D.new()
			sphere_3d.name = "Asteroid3D_" + str(i)
			sphere_3d.position = Vector3(pos_2d.x * scale_factor, rng.randf_range(-2.0, 2.0), pos_2d.y * scale_factor)
			sphere_3d.radius = radius_2d * scale_factor
			sphere_3d.radial_segments = 16
			sphere_3d.rings = 12
			sphere_3d.material = mat_rock
			parent_asteroids_3d.add_child(sphere_3d)
			
	print("[Map_Extraction] ¡Generación procedimental completada! Creados ", num_obstacles, " obstáculos en mapa 10000x10000.")
