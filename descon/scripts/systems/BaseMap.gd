extends Node2D
class_name BaseMap

# Script Base para Mapas Instanciados con Soporte 3D Dinámico.
# Permite definir propiedades específicas por cada nivel y autogenera lienzos 3D.

@export var world_size: float = 4000.0
@export var zone_name: String = "SECTOR DESCONOCIDO"

@export var scale_factor: float = 0.02 # Relación 2D a 3D
@export var camera_height: float = 30.0
@export var use_orthogonal: bool = true

# Referencias dinámicas
var viewport_container: SubViewportContainer = null
var sub_viewport: SubViewport = null
var camera_3d: Camera3D = null
var asteroids_3d: Node3D = null
var player_node: Node2D = null

# Referencia a la textura de fondo principal
@onready var map_background: TextureRect = get_node_or_null("ParallaxBackground/MapWorldLayer/MapBackground")

func _ready():
	# Ajustar automáticamente el fondo al tamaño del mundo si es necesario
	if is_instance_valid(map_background):
		# Efecto de fade-in para transición suave
		map_background.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(map_background, "modulate:a", 0.7, 1.5).set_trans(Tween.TRANS_SINE)
		
	# Configurar el lienzo 3D dinámico si no existe en la escena
	_setup_3d_dynamic()

func setup_map():
	# Método para ejecutar lógica específica al cargar el mapa
	pass

func _setup_3d_dynamic():
	# Si ya existe ViewportCanvas en la escena (como en Map_Extraction), vincular referencias y retornar
	var existing_canvas = get_node_or_null("ViewportCanvas")
	if is_instance_valid(existing_canvas):
		viewport_container = existing_canvas.get_node_or_null("SubViewportContainer")
		if is_instance_valid(viewport_container):
			sub_viewport = viewport_container.get_node_or_null("SubViewport")
			if is_instance_valid(sub_viewport):
				camera_3d = sub_viewport.get_node_or_null("Camera3D")
				asteroids_3d = sub_viewport.get_node_or_null("Asteroids3D")
		return

	# Si es un mapa 2D puro (Lobby, Default, etc.), crear lienzo 3D de alta gama programáticamente
	print("[BaseMap] Generando lienzo 3D autoritario para el Mapa: ", zone_name)
	var canvas = CanvasLayer.new()
	canvas.name = "ViewportCanvas"
	canvas.layer = -15
	add_child(canvas)
	
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "SubViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	viewport_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(viewport_container)
	
	sub_viewport = SubViewport.new()
	sub_viewport.name = "SubViewport"
	sub_viewport.transparent_bg = true
	sub_viewport.own_world_3d = true
	sub_viewport.handle_input_locally = false
	sub_viewport.size = get_viewport().size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)
	
	# Iluminación de espacio profundo
	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.transform = Transform3D(
		Basis(
			Vector3(0.866, -0.433, 0.25),
			Vector3(0, 0.5, 0.866),
			Vector3(-0.5, -0.75, 0.433)
		).orthonormalized(),
		Vector3.ZERO
	)
	light.light_color = Color(0.70, 0.85, 1.0)
	light.light_energy = 1.2
	sub_viewport.add_child(light)
	
	# Cámara 3D ortogonal de perspectiva bloqueada
	camera_3d = Camera3D.new()
	camera_3d.name = "Camera3D"
	camera_3d.fov = 50.0
	camera_3d.transform = Transform3D(
		Basis(
			Vector3(1, 0, 0),
			Vector3(0, 0, 1),
			Vector3(0, -1, 0)
		),
		Vector3.ZERO
	)
	sub_viewport.add_child(camera_3d)
	
	# Nodo contenedor de asteroides de decoración espacial
	asteroids_3d = Node3D.new()
	asteroids_3d.name = "Asteroids3D"
	sub_viewport.add_child(asteroids_3d)
	
	var rock_material = StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.35, 0.31, 0.27)
	rock_material.roughness = 0.9
	
	# Distribuir asteroides en un área espacial de decoración
	var asteroid_positions = [
		Vector3(15, -6, 20), Vector3(25, -4, 10), Vector3(8, -8, 30),
		Vector3(-10, -5, 15), Vector3(45, -7, 40), Vector3(5, -6, 5),
		Vector3(30, -5, 35), Vector3(0, -7, 25), Vector3(50, -4, -10),
		Vector3(12, -8, -5), Vector3(22, -6, 45), Vector3(-5, -5, 35)
	]
	
	for i in range(asteroid_positions.size()):
		var ast = CSGSphere3D.new()
		ast.name = "ProceduralAsteroid_" + str(i)
		ast.transform.origin = asteroid_positions[i]
		ast.radius = 1.2 + (i % 4) * 0.7
		ast.radial_segments = 16
		ast.rings = 12
		ast.material = rock_material
		asteroids_3d.add_child(ast)
		
	# Manejar redimensionamiento de pantalla de forma reactiva
	get_tree().get_root().size_changed.connect(func():
		if is_instance_valid(sub_viewport):
			sub_viewport.size = get_viewport().size
	)

func _physics_process(_delta):
	# --- LOCALIZAR NAVE DEL JUGADOR ---
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]

	# --- SINCRONIZACIÓN DE CÁMARA PERFECTA DE ALTO NIVEL ---
	var target_pos = Vector2.ZERO
	var current_zoom = 1.0
	
	var cam_2d = get_viewport().get_camera_2d()
	if is_instance_valid(cam_2d):
		target_pos = cam_2d.get_screen_center_position()
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
			
		if use_orthogonal:
			camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera_3d.size = (viewport_height * scale_factor) / current_zoom
			camera_3d.position.y = camera_height
		else:
			camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
			var target_visible_height = (viewport_height * scale_factor) / current_zoom
			camera_3d.position.y = target_visible_height / (2.0 * tan(deg_to_rad(camera_3d.fov / 2.0)))
		
		# Sincronizar posición de la cámara 3D con el centro de la pantalla
		camera_3d.position.x = target_pos.x * scale_factor
		camera_3d.position.z = target_pos.y * scale_factor

func _process(delta):
	# Rotación procedimental y lenta de los asteroides 3D de fondo
	if is_instance_valid(asteroids_3d):
		for asteroid in asteroids_3d.get_children():
			if asteroid is Node3D:
				var speed_mult = 0.05 + (abs(asteroid.name.hash() % 10) * 0.01)
				asteroid.rotate_x(delta * speed_mult * 0.5)
				asteroid.rotate_y(delta * speed_mult)
				asteroid.rotate_z(delta * speed_mult * 0.3)
