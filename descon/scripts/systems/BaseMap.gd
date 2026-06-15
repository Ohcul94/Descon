extends Node2D
class_name BaseMap

# Script Base para Mapas Instanciados con Soporte 3D Dinámico.
# Permite definir propiedades específicas por cada nivel y autogenera lienzos 3D.

@export var world_size: float = 4000.0
@export var zone_name: String = "SECTOR DESCONOCIDO"
@export var zone_id = 1
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
		map_background.visible = false
		adjust_background()
		
	# Configurar el lienzo 3D dinámico si no existe en la escena
	_setup_3d_dynamic()

func adjust_background():
	if is_instance_valid(map_background):
		# v311.1: Adaptar fondo dinámicamente al tamaño del mundo con un margen del 50%
		var bg_margin = world_size * 0.5
		map_background.offset_left = -bg_margin
		map_background.offset_top = -bg_margin
		map_background.offset_right = world_size + bg_margin
		map_background.offset_bottom = world_size + bg_margin
	
	# v306.3: Consolidar el sistema de Lienzo Único registrando el mapa en el grupo global
	add_to_group("map")

	# v307.0: Inyectar luz de cámara frontal (Headlight) si no existe ya en la cámara para evitar naves negras
	if is_instance_valid(camera_3d) and not camera_3d.has_node("CameraHeadlight"):
		var headlight = DirectionalLight3D.new()
		headlight.name = "CameraHeadlight"
		headlight.light_color = Color(0.9, 0.95, 1.0)
		headlight.light_energy = 1.0
		headlight.light_specular = 0.3
		headlight.shadow_enabled = false
		camera_3d.add_child(headlight)

	# v370.0: Spawnear altar 3D si está configurado en Defensa del Altar
	_spawn_altar_if_configured()

func setup_map():
	# Método para ejecutar lógica específica al cargar el mapa
	pass

func _setup_3d_dynamic():
	# Si ya existe ViewportCanvas en la escena (como en Map_Extraction), vincular referencias y retornar
	var existing_canvas = get_node_or_null("ViewportCanvas")
	if is_instance_valid(existing_canvas):
		viewport_container = existing_canvas.get_node_or_null("SubViewportContainer")
		if is_instance_valid(viewport_container):
			viewport_container.stretch = true
			viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			sub_viewport = viewport_container.get_node_or_null("SubViewport")
			if is_instance_valid(sub_viewport):
				sub_viewport.transparent_bg = true
				sub_viewport.own_world_3d = true
				sub_viewport.handle_input_locally = false
				sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				camera_3d = sub_viewport.get_node_or_null("Camera3D")
				if is_instance_valid(camera_3d):
					_apply_camera_headlight(camera_3d)
				asteroids_3d = sub_viewport.get_node_or_null("Asteroids3D")
				
				# Aplicar iluminación mejorada cenital de arriba y ambiental de soporte
				_apply_ambient_and_zenith_lights(sub_viewport)
		return

	# Si es un mapa 2D puro (Lobby, Default, etc.), crear lienzo 3D de alta gama programáticamente
	print("[BaseMap] Generando lienzo 3D autoritario para el Mapa: ", zone_name)
	var canvas = CanvasLayer.new()
	canvas.name = "ViewportCanvas"
	canvas.layer = -5
	add_child(canvas)
	
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "SubViewportContainer"
	viewport_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	viewport_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.stretch = true
	canvas.add_child(viewport_container)
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	sub_viewport = SubViewport.new()
	sub_viewport.name = "SubViewport"
	sub_viewport.transparent_bg = true
	sub_viewport.own_world_3d = true
	sub_viewport.handle_input_locally = false
	sub_viewport.size = get_viewport().size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)
	
	# Aplicar iluminación mejorada cenital de arriba y ambiental de soporte
	_apply_ambient_and_zenith_lights(sub_viewport)

	# Iluminación de espacio profundo (Luz principal con sombras para relieve)
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
	
	# Cámara 3D ortogonal de perspectiva bloqueada (Mirando hacia abajo en el eje Y)
	camera_3d = Camera3D.new()
	camera_3d.name = "Camera3D"
	camera_3d.fov = 35.0
	camera_3d.transform = Transform3D(
		Basis(
			Vector3(1, 0, 0),
			Vector3(0, 0, -1),
			Vector3(0, 1, 0)
		),
		Vector3.ZERO
	)
	camera_3d.current = true
	sub_viewport.add_child(camera_3d)
	_apply_camera_headlight(camera_3d)
	
	# No instanciamos asteroides procedimentales por defecto para mantener el fondo limpio y libre de esferas fantasma
		
	# Manejar redimensionamiento de pantalla de forma reactiva
	get_tree().get_root().size_changed.connect(func():
		if is_instance_valid(viewport_container) and viewport_container.stretch:
			return
		if is_instance_valid(sub_viewport):
			sub_viewport.size = get_viewport().size
	)

func _apply_ambient_and_zenith_lights(sub_vp: SubViewport):
	if not is_instance_valid(sub_vp):
		return
		
	# 1. WorldEnvironment (Asegurar luz ambiental clara de soporte duplicada)
	var env_node = sub_vp.get_node_or_null("WorldEnvironment")
	if not is_instance_valid(env_node):
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		sub_vp.add_child(env_node)
		
	var env = env_node.environment
	if is_instance_valid(env):
		env = env.duplicate()
		env_node.environment = env
	else:
		env = Environment.new()
		env_node.environment = env
		
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.9) # Luz ambiente neutra muy clara (sin tintes oscuros)
	env.ambient_light_energy = 2.2 # Potente energía ambiental para eliminar partes negras o en penumbra
	
	# Desactivar sombras en todas las luces del Viewport para evitar áreas negras
	for child in sub_vp.get_children():
		if child is Light3D:
			child.shadow_enabled = false
			# Evitar que las luces direccionales quemen la escena
			if child is DirectionalLight3D:
				child.light_energy = min(child.light_energy, 1.0)
				child.light_color = Color(1.0, 1.0, 1.0) # Luz blanca para mantener fidelidad de color
	
	# 2. Limpieza de DirectionalLight3D_Zenith para liberar slots de luces direccionales en Compatibility mode
	var zenith = sub_vp.get_node_or_null("DirectionalLight3D_Zenith")
	if is_instance_valid(zenith):
		zenith.queue_free()

func _apply_camera_headlight(cam: Camera3D):
	if not is_instance_valid(cam):
		return
		
	# Limpieza de la luz omni anterior si existía para evitar conflictos
	var old_omni = cam.get_node_or_null("CameraOmniLight")
	if is_instance_valid(old_omni) and old_omni is OmniLight3D:
		old_omni.queue_free()
		
	var headlight = cam.get_node_or_null("CameraHeadlight")
	if not is_instance_valid(headlight):
		headlight = DirectionalLight3D.new()
		headlight.name = "CameraHeadlight"
		cam.add_child(headlight)
		
	headlight.rotation = Vector3.ZERO # Apunta en la misma dirección de la cámara
	headlight.light_color = Color(1.0, 1.0, 1.0) # Luz blanca pura frontal
	headlight.light_energy = 1.8 # Energía para un brillo constante uniforme sin decaer
	headlight.light_specular = 0.2 # Brillo especular suave
	headlight.shadow_enabled = false # Sin sombras para evitar oclusión y mantener visibilidad

func _process(_delta):
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
		cam_2d.force_update_scroll() # Forzar actualización inmediata para evitar desfase de 1 frame (efecto acordeón)
		target_pos = cam_2d.get_screen_center_position()
		current_zoom = cam_2d.zoom.x
	else:
		if is_instance_valid(player_node):
			target_pos = player_node.global_position
			
	if is_instance_valid(camera_3d):
		if current_zoom <= 0.01:
			current_zoom = 1.0
			
		var viewport_height = float(get_viewport().get_visible_rect().size.y)
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
		var correction_z = 1.41421356 # 1.0 / sin(45 grados) para compensar perspectiva ortogonal
		var corrected_target_z = target_pos.y * scale_factor * correction_z
		camera_3d.position.x = target_pos.x * scale_factor
		camera_3d.position.z = corrected_target_z + dynamic_height
		camera_3d.look_at(Vector3(target_pos.x * scale_factor, 0.0, corrected_target_z), Vector3.UP)

# _process removido al no haber asteroides decorativos que rotar

func _spawn_altar_if_configured():
	if not is_instance_valid(sub_viewport): return
	
	var full_config = GameConstants.get("FULL_CONFIG")
	if not full_config or not full_config.has("gameModes") or not full_config.gameModes.has("altar_defense"):
		return
		
	var ad_config = full_config.gameModes.altar_defense
	if not ad_config.has("maps") or not (ad_config.maps is Array):
		return
		
	var map_included = false
	for m in ad_config.maps:
		if str(m) == str(zone_id):
			map_included = true
			break
			
	if not map_included:
		return
		
	var altar_pos_data = ad_config.get("altarPos")
	if not altar_pos_data or not altar_pos_data.has("x") or not altar_pos_data.has("y"):
		return
		
	var altar_pos = Vector2(float(altar_pos_data.x), float(altar_pos_data.y))
	print("[BaseMap] Spawneando Altar 3D en la posición: ", altar_pos)
	
	var altar_scene = load("res://assets/Altares/3D/Altar1/Altar1.glb")
	if altar_scene:
		var altar_3d = altar_scene.instantiate()
		altar_3d.name = "Altar3D"
		# Rotación vertical recta (mirando hacia el sur/cámara en el eje Y)
		altar_3d.rotation_degrees = Vector3(0, 180, 0)
		var correction_z = 1.41421356
		altar_3d.position = Vector3(altar_pos.x * scale_factor, 0.0, altar_pos.y * scale_factor * correction_z)
		# Escalamos para hacerlo bastante visible y destacado (15.0 de escala o 12.0)
		altar_3d.scale = Vector3(15.0, 15.0, 15.0)
		
		# Agregamos luz omni para iluminar el altar con un brillo verde neón místico
		var light = OmniLight3D.new()
		light.name = "AltarLight"
		light.position = Vector3(0, 2.0, 0)
		light.light_color = Color(0, 1.0, 0.5) 
		light.light_energy = 5.0
		light.omni_range = 15.0
		altar_3d.add_child(light)
		
		sub_viewport.add_child(altar_3d)

		# --- AÑADIR COLLIDERS 2D PARA EL ALTAR ---
		# 1. Area2D lógica para capturar impactos y daño
		var altar_area = Area2D.new()
		altar_area.name = "AltarArea2D"
		altar_area.collision_layer = 1 | 2
		altar_area.collision_mask = 1 | 2
		altar_area.global_position = altar_pos
		altar_area.add_to_group("altar")
		
		var col_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 120.0
		col_shape.shape = circle
		altar_area.add_child(col_shape)
		add_child(altar_area)

		# 2. StaticBody2D físico para obstruir paso de naves
		var static_body = StaticBody2D.new()
		static_body.name = "AltarStaticBody2D"
		static_body.collision_layer = 2
		static_body.collision_mask = 0
		static_body.global_position = altar_pos
		
		var static_col = CollisionShape2D.new()
		var static_circle = CircleShape2D.new()
		static_circle.radius = 100.0
		static_col.shape = static_circle
		static_body.add_child(static_col)
		add_child(static_body)
		
		print("[BaseMap] Colliders 2D del Altar instanciados (Radio lógico: 120, Físico: 100)")
	else:
		print("[BaseMap] ADVERTENCIA: No se pudo cargar res://assets/Altares/3D/Altar1/Altar1.glb")
