extends Node2D
class_name BaseMap

# Precarga de recursos estáticos a nivel de clase para optimización y consistencia
const TEXTURE_NOISE_531 = preload("res://VFX/textures/T_VFX_Noise_531.png")
const TEXTURE_NOISE_21D = preload("res://VFX/textures/T_VFX_Noise21d_tiled.png")
const SHADER_GROUND_RELIEF = preload("res://resources/shaders/ground_relief.gdshader")
const TEXTURE_NOISE_019 = preload("res://VFX/textures/T_VFX_Noise_019.png")
const SHADER_BORDER_NEBULA = preload("res://resources/shaders/border_nebula.gdshader")
const SHADER_STARFIELD = preload("res://resources/shaders/starfield.gdshader")
const SHADER_DOME_STARFIELD = preload("res://resources/shaders/dome_starfield.gdshader")
const MODEL_PORTAL_ICON = preload("res://assets/Puertas/3D/Puerta2/Puerta2.glb")
const MODEL_VAULT_ICON = preload("res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb")
const MODEL_LOOT_ICON = preload("res://assets/Contenedores/Cofres/3D/Cofre1/Cofre1.glb")


# Script Base para Mapas Instanciados con Soporte 3D Dinámico.
# Permite definir propiedades específicas por cada nivel y autogenera lienzos 3D.

@export var world_size: float = 4000.0
@export var zone_name: String = "SECTOR DESCONOCIDO"
@export var zone_id: Variant = 1  # Variant: acepta int (zonas normales) y String (arena_x, extract_x)
@export var scale_factor: float = 0.02 # Relación 2D a 3D
@export var camera_height: float = 30.0
@export var use_orthogonal: bool = false

# Referencias dinámicas
var viewport_container: SubViewportContainer = null
var sub_viewport: SubViewport = null
var camera_3d: Camera3D = null
var asteroids_3d: Node3D = null
var player_node: Node2D = null
var border_ring_node: Node3D = null
var rock_data_list: Array = []
var multimeshes: Dictionary = {}
var rock_angle: float = 0.0

# correction_z dinámico: 1.0 / sin(tilt_angle) calculado desde la inclinación real de la cámara
var correction_z: float = 1.41421356

# v420.5: Cursor 3D World-Space (estilo LoL/Dota2)
# Vive en el SubViewport — se mueve via raycast al plano Y=0 cada frame.
# Elimina todas las conversiones Screen→Canvas→SubViewport que causaban desfase.
var cursor_3d: Node3D = null
var mouse_world_pos_3d: Vector3 = Vector3.ZERO   # Posición 3D exacta del cursor en el mundo
var mouse_world_pos_2d: Vector2 = Vector2.ZERO   # Equivalente en espacio lógico 2D del mapa

var fixed_cam_zoom: float = 1.0

# Variables para Cámara Híbrida (1ª / 3ª Persona WoW-Style)
var hybrid_cam_h: float = 180.0
var hybrid_cam_v: float = 12.0
var _lmb_dragging: bool = false
var _lmb_drag_last: Vector2 = Vector2.ZERO
var use_hybrid_camera: bool = false
var _smoothed_target_3d: Vector3 = Vector3.ZERO
var _smoothed_yaw: float = 0.0
var _camera_initialized: bool = false





# Free Camera (orbit/free mode) — toggle con tecla O
var free_cam_active: bool = false
var free_cam_h: float = 180.0  # ángulo horizontal en grados (180 = detrás de la nave)
var free_cam_v: float = 40.0   # ángulo vertical (10-85°, 0 = horizontal, 90 = top-down)
var free_cam_zoom: float = 35.0
var free_cam_center: Vector3 = Vector3.ZERO
var free_orbit_mode: bool = true  # true=orbita jugador, false=libre (WASD)
var _mid_dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO

# Mobile touch camera control state
var _mobile_touch_points: Dictionary = {}
var _mobile_cam_drag_index: int = -1
var _mobile_cam_drag_last: Vector2 = Vector2.ZERO
var _pinch_start_dist: float = 0.0
var _was_mobile_camera_edit: int = 0

# Referencia a la textura de fondo principal
@onready var map_background: TextureRect = get_node_or_null("ParallaxBackground/MapWorldLayer/MapBackground")

func _ready():
	# Ajustar automáticamente el fondo al tamaño del mundo si es necesario
	if is_instance_valid(map_background):
		map_background.visible = false
		adjust_background()
		
	# Configurar acciones de input para cámara libre
	_register_input_actions()
		
	# Configurar el lienzo 3D dinámico si no existe en la escena
	_setup_3d_dynamic()
	
	# Restaurar estado de cámara de la sesión actual (persiste entre warps)
	_restore_camera_state()
	
	# Si mobile edit mode está activo en Settings, forzar cámara libre
	var sm_init = get_node_or_null("/root/SettingsManager")
	var is_mob_cam_edit = 0
	if sm_init and "mobile_camera_edit_enabled" in sm_init:
		is_mob_cam_edit = int(sm_init.mobile_camera_edit_enabled)
	if sm_init and sm_init.mobile_mode:
		free_cam_active = (is_mob_cam_edit != 0)
		_was_mobile_camera_edit = is_mob_cam_edit
	
	# Establecer metadato estático autoritario para sincronizar con proyectiles y entidades
	self.set_meta("correction_z", correction_z)
	
	# v430.1: Conectar señales de sincronización de configuración del servidor
	if NetworkManager:
		if not NetworkManager.config_updated.is_connected(_on_network_config_updated):
			NetworkManager.config_updated.connect(_on_network_config_updated)
		if not NetworkManager.admin_config_updated.is_connected(_on_network_config_updated):
			NetworkManager.admin_config_updated.connect(_on_network_config_updated)

# Registrar acciones de input para cámara libre si no existen
func _register_input_actions():
	if not InputMap.has_action("toggle_free_camera"):
		InputMap.add_action("toggle_free_camera")
		var ev = InputEventKey.new()
		ev.keycode = KEY_O
		InputMap.action_add_event("toggle_free_camera", ev)
	
	if not InputMap.has_action("toggle_orbit_mode"):
		InputMap.add_action("toggle_orbit_mode")
		var ev = InputEventKey.new()
		ev.keycode = KEY_SEMICOLON
		InputMap.action_add_event("toggle_orbit_mode", ev)

func adjust_background():
	_setup_starfield()
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
		headlight.light_energy = 0.3
		headlight.light_specular = 0.1
		headlight.shadow_enabled = false
		camera_3d.add_child(headlight)

	# v370.0: Spawnear altar 3D si está configurado en Defensa del Altar
	_spawn_altar_if_configured()
	
	# v400.4: Diferir el inicio un frame completo para esperar a que la escena vieja se destruya y libere del árbol
	_deferred_ready()

func _deferred_ready():
	print("[BaseMap _deferred_ready] Entrando a deferred ready. Esperando process_frame...")
	await get_tree().process_frame
	print("[BaseMap _deferred_ready] process_frame completado. Llamando a _spawn_map_objects...")
	_spawn_map_objects()
	_create_sky_dome()

func _setup_starfield():
	var bg = get_node_or_null("ParallaxBackground/StaticLayer/SpaceBG")
	if is_instance_valid(bg):
		bg.visible = false

func _create_sky_dome():
	if not is_instance_valid(sub_viewport):
		return
	var existing = sub_viewport.get_node_or_null("SkyDome")
	if is_instance_valid(existing):
		return
	var dome = MeshInstance3D.new()
	dome.name = "SkyDome"
	var mesh = SphereMesh.new()
	mesh.radius = 250.0
	mesh.height = 500.0
	mesh.radial_segments = 64
	mesh.rings = 48
	var mat = ShaderMaterial.new()
	mat.shader = SHADER_DOME_STARFIELD
	mat.render_priority = -128
	dome.material_override = mat
	dome.mesh = mesh
	sub_viewport.add_child(dome)
	
	# Establecer visibilidad inicial según configuración (desactivado por defecto)
	var show_s = false
	if get_node_or_null("/root/SettingsManager"):
		show_s = SettingsManager.show_stars
	dome.visible = show_s
	print("[BaseMap] Cúpula estelar 3D creada. Visibilidad: ", show_s)

func update_sky_dome_visibility():
	if not is_instance_valid(sub_viewport):
		return
	var dome = sub_viewport.get_node_or_null("SkyDome")
	if is_instance_valid(dome):
		var show_s = false
		if get_node_or_null("/root/SettingsManager"):
			show_s = SettingsManager.show_stars
		dome.visible = show_s
		print("[BaseMap] Visibilidad de cúpula estelar actualizada: ", show_s)

func setup_map():
	_setup_dynamic_3d_map_layout()

func _on_network_config_updated(_config):
	print("[BaseMap] Configuración del servidor recibida. Regenerando layout 3D...")
	_setup_dynamic_3d_map_layout()
func _setup_dynamic_3d_map_layout():
	if not is_instance_valid(sub_viewport):
		return

	# Obtener dimensiones dinámicas del mapa desde MAPS_CONFIG (AdminDash Cartografia)
	var map_width = world_size
	var map_height = world_size
	var z_id_str = str(zone_id)
	if "." in z_id_str and z_id_str.is_valid_float():
		var z_float = float(z_id_str)
		if z_float == int(z_float):
			z_id_str = str(int(z_float))
	if GameConstants.MAPS_CONFIG.has(z_id_str):
		var cfg = GameConstants.MAPS_CONFIG[z_id_str]
		if cfg.has("width") and float(cfg.width) > 0:
			map_width = float(cfg.width)
			map_height = float(cfg.width)
			world_size = map_width
		if cfg.has("height") and float(cfg.height) > 0:
			map_height = float(cfg.height)

	var margin_2d = max(world_size * 3.0, 20000.0)
	var ground_size_x = (map_width + margin_2d * 2.0) * scale_factor
	var ground_size_z = (map_height + margin_2d * 2.0) * scale_factor * correction_z
	var center_x = (map_width / 2.0) * scale_factor
	var center_z = (map_height / 2.0) * scale_factor * correction_z
	var y_ground = 0.0

	var fog_start_3d = max(map_width * scale_factor * 0.25, 15.0)
	var fog_end_3d = max(map_width * scale_factor * 0.75, 60.0)

	# v500.0: Si Ground3D ya existe (pre-colocado en la escena), redimensionar sin recrear
	var existing_ground = sub_viewport.get_node_or_null("Ground3D")
	if is_instance_valid(existing_ground):
		_resize_existing_ground(existing_ground, ground_size_x, ground_size_z, center_x, center_z, y_ground, map_width, map_height, fog_start_3d, fog_end_3d)
		return

	# Crear suelo 3D decorativo (superficie estelar / lunar)
	var ground_root = Node3D.new()
	ground_root.name = "Ground3D"
	sub_viewport.add_child(ground_root)

	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(ground_size_x, ground_size_z)
	mesh_instance.mesh = plane_mesh
	mesh_instance.position = Vector3(center_x, y_ground, center_z)

	var ground_mat = _create_ground_material()
	_apply_ground_fog(ground_mat, fog_start_3d, fog_end_3d)
	mesh_instance.material_override = ground_mat
	ground_root.add_child(mesh_instance)

	# --- ANILLO DE NEBULOSA PERIMETRAL (Atmósfera / Horizonte) ---
	var wall_root = Node3D.new()
	wall_root.name = "NebulaWalls"
	ground_root.add_child(wall_root)

	var nebula_width = fog_end_3d * 0.8
	var wall_height = 50.0
	var y_wall = y_ground + wall_height * 0.3

	var min_x = 0.0
	var max_x = map_width * scale_factor
	var min_z = 0.0
	var max_z = map_height * scale_factor * correction_z

	var nebula_offset = 0.0

	var wall_mat = _create_nebula_material()

	_create_nebula_wall(wall_root, "WallTop", Vector2(max_x - min_x + nebula_width * 2.0, wall_height), Vector3((max_x + min_x) / 2.0, y_wall, min_z - nebula_offset), Vector3.ZERO, wall_mat)
	_create_nebula_wall(wall_root, "WallBottom", Vector2(max_x - min_x + nebula_width * 2.0, wall_height), Vector3((max_x + min_x) / 2.0, y_wall, max_z + nebula_offset), Vector3.ZERO, wall_mat)
	_create_nebula_wall(wall_root, "WallLeft", Vector2(max_z - min_z + nebula_width * 2.0, wall_height), Vector3(min_x - nebula_offset, y_wall, (max_z + min_z) / 2.0), Vector3(0, 90, 0), wall_mat)
	_create_nebula_wall(wall_root, "WallRight", Vector2(max_z - min_z + nebula_width * 2.0, wall_height), Vector3(max_x + nebula_offset, y_wall, (max_z + min_z) / 2.0), Vector3(0, 90, 0), wall_mat)

func _resize_existing_ground(ground_root: Node3D, gs_x: float, gs_z: float, cx: float, cz: float, y: float, map_w: float, map_h: float, fog_start: float, fog_end: float):
	var mesh_node = ground_root.get_node_or_null("GroundMesh")
	if is_instance_valid(mesh_node) and mesh_node is MeshInstance3D:
		var pm = mesh_node.mesh
		if pm is PlaneMesh:
			pm.size = Vector2(gs_x, gs_z)
		mesh_node.position = Vector3(cx, y, cz)
		var ground_mat = _create_ground_material()
		_apply_ground_fog(ground_mat, fog_start, fog_end)
		mesh_node.material_override = ground_mat

	var walls = ground_root.get_node_or_null("NebulaWalls")
	if is_instance_valid(walls):
		var wall_height = 50.0
		var y_wall = y + wall_height * 0.3
		var min_x = 0.0
		var max_x = map_w * scale_factor
		var min_z = 0.0
		var max_z = map_h * scale_factor * correction_z
		var nebula_offset = 0.0
		var nebula_width = fog_end * 0.8

		var wall_mat = _create_nebula_material()

		_resize_quad(walls, "WallTop", Vector2(max_x - min_x + nebula_width * 2.0, wall_height), Vector3((max_x + min_x) / 2.0, y_wall, min_z - nebula_offset), Vector3.ZERO, wall_mat)
		_resize_quad(walls, "WallBottom", Vector2(max_x - min_x + nebula_width * 2.0, wall_height), Vector3((max_x + min_x) / 2.0, y_wall, max_z + nebula_offset), Vector3.ZERO, wall_mat)
		_resize_quad(walls, "WallLeft", Vector2(max_z - min_z + nebula_width * 2.0, wall_height), Vector3(min_x - nebula_offset, y_wall, (max_z + min_z) / 2.0), Vector3(0, 90, 0), wall_mat)
		_resize_quad(walls, "WallRight", Vector2(max_z - min_z + nebula_width * 2.0, wall_height), Vector3(max_x + nebula_offset, y_wall, (max_z + min_z) / 2.0), Vector3(0, 90, 0), wall_mat)

func _resize_quad(parent: Node3D, node_name: String, size: Vector2, pos: Vector3, rot: Vector3, mat: Material = null):
	var node = parent.get_node_or_null(node_name)
	if is_instance_valid(node) and node is MeshInstance3D:
		var mesh = node.mesh
		if mesh is QuadMesh:
			mesh.size = size
		node.position = pos
		node.rotation_degrees = rot
		if mat:
			node.material_override = mat

func _create_ground_material() -> Material:
	var mat = ShaderMaterial.new()
	mat.shader = SHADER_GROUND_RELIEF
	mat.set_shader_parameter("u_albedo_tex", TEXTURE_NOISE_531)
	mat.set_shader_parameter("u_detail_tex", TEXTURE_NOISE_21D)
	mat.set_shader_parameter("u_tint_color", Color(0.55, 0.52, 0.48))
	mat.set_shader_parameter("u_tiling", Vector2(5.0, 5.0))
	mat.set_shader_parameter("u_height_scale", 1.8)
	mat.set_shader_parameter("u_detail_strength", 0.4)
	mat.set_shader_parameter("u_metallic", 0.2)
	mat.set_shader_parameter("u_roughness", 0.85)
	mat.set_shader_parameter("u_emission", Vector3(0.04, 0.03, 0.08))
	mat.set_shader_parameter("u_emission_energy", 0.3)
	return mat

func _apply_ground_fog(mat: Material, fog_start: float, fog_end: float):
	if mat is ShaderMaterial:
		mat.set_shader_parameter("u_fog_start", fog_start)
		mat.set_shader_parameter("u_fog_end", fog_end)
		mat.set_shader_parameter("u_fog_color", Color(0.0, 0.0, 0.0, 1.0))
		mat.set_shader_parameter("u_horizon_glow_color", Vector3(0.005, 0.01, 0.02))

func _create_nebula_material() -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = SHADER_BORDER_NEBULA
	mat.set_shader_parameter("u_noise_tex", TEXTURE_NOISE_019)
	mat.set_shader_parameter("u_color_a", Color(0.12, 0.01, 0.22, 0.6))
	mat.set_shader_parameter("u_color_b", Color(0.01, 0.18, 0.38, 0.35))
	mat.set_shader_parameter("u_color_c", Color(0.45, 0.03, 0.28, 0.4))
	mat.set_shader_parameter("u_speed", 0.3)
	mat.set_shader_parameter("u_alpha_scale", 0.9)
	mat.set_shader_parameter("u_horizon_fade", 0.5)
	return mat

func _create_nebula_wall(parent: Node3D, name_str: String, size: Vector2, pos: Vector3, rot: Vector3, mat: Material):
	var wall = MeshInstance3D.new()
	wall.name = name_str
	var mesh = QuadMesh.new()
	mesh.size = size
	wall.mesh = mesh
	wall.material_override = mat
	wall.position = pos
	wall.rotation_degrees = rot
	parent.add_child(wall)

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
				
				# v420.5: Crear cursor 3D world-space
				_create_world_cursor()
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
	
	_apply_ambient_and_zenith_lights(sub_viewport)

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
	
	# v420.5: Crear cursor 3D world-space
	_create_world_cursor()
		
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
	env.ambient_light_color = Color(0.28, 0.30, 0.42) # Espacio azul/gris suave pero iluminado
	env.ambient_light_energy = 1.5 # Alta energía base para que los modelos nunca queden a oscuras

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Obtener calidad gráfica actual
	var quality = 1 # Por defecto Media
	if get_node_or_null("/root/SettingsManager"):
		quality = SettingsManager.get_graphics_quality()

	# Configuración de GLOW (Efecto de brillo) según calidad
	if quality == 0:
		env.glow_enabled = false
	else:
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_strength = 1.2
		env.glow_bloom = 0.15
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.glow_hdr_threshold = 1.2

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.05

	# Habilitar oclusión ambiental (SSAO) e iluminación indirecta (SSIL) según calidad y renderizador activo
	var ssao_active = false
	var ssil_active = false
	
	var current_renderer = ""
	if ProjectSettings.has_setting("rendering/renderer/rendering_method"):
		current_renderer = ProjectSettings.get_setting("rendering/renderer/rendering_method")

	# Configuración de Render Scale y Calidad 3D en el Viewport
	# Para dispositivos de gama baja (calidad = 0), bajamos la resolución de renderizado 3D al 30% (muy liviano, se ve pixelado pero corre fluido)
	# Para calidad media, al 60%. Para calidad alta, al 100%.
	# Nota: Esto no afecta las letras/HUD/UI, que siguen viéndose perfectamente nítidos y legibles.
	var render_scale = 0.60
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "render_scale_3d" in sm:
		render_scale = sm.render_scale_3d
	else:
		if quality == 0:
			render_scale = 0.30
		elif quality == 1:
			render_scale = 0.60
		elif quality == 2:
			render_scale = 1.0

	var scale_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var msaa_mode = Viewport.MSAA_DISABLED
	var screen_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var lod_threshold = 8.0 # Simplifica enormemente los polígonos de los modelos 3D lejanos

	if quality == 1:
		scale_mode = Viewport.SCALING_3D_MODE_FSR if current_renderer == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR
		msaa_mode = Viewport.MSAA_DISABLED
		screen_aa = Viewport.SCREEN_SPACE_AA_FXAA if current_renderer != "gl_compatibility" else Viewport.SCREEN_SPACE_AA_DISABLED
		lod_threshold = 2.0
	elif quality == 2:
		scale_mode = Viewport.SCALING_3D_MODE_FSR if current_renderer == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR
		msaa_mode = Viewport.MSAA_2X
		screen_aa = Viewport.SCREEN_SPACE_AA_FXAA if current_renderer != "gl_compatibility" else Viewport.SCREEN_SPACE_AA_DISABLED
		lod_threshold = 1.0

	sub_vp.scaling_3d_scale = render_scale
	sub_vp.scaling_3d_mode = scale_mode
	sub_vp.msaa_3d = msaa_mode
	sub_vp.screen_space_aa = screen_aa
	sub_vp.mesh_lod_threshold = lod_threshold

	# SSAO y SSIL no están soportados en el renderizador gl_compatibility
	if current_renderer != "gl_compatibility":
		if quality == 1: # Media
			ssao_active = true
		elif quality == 2: # Alta
			ssao_active = true
			ssil_active = true
			
	env.ssao_enabled = ssao_active
	if ssao_active:
		env.ssao_intensity = 1.5
		env.ssao_power = 1.2
		env.ssao_detail = 0.5
		
	# SSIL sólo está disponible en Forward+
	if current_renderer == "forward_plus":
		env.ssil_enabled = ssil_active
		if ssil_active:
			env.ssil_intensity = 1.0

	for child in sub_vp.get_children():
		if child is Light3D:
			child.shadow_enabled = false

	# 2. Luz Direccional Principal (Simula el sol o estrella del sector)
	var main_light = sub_vp.get_node_or_null("DirectionalLight3D")
	if not is_instance_valid(main_light) or not main_light is DirectionalLight3D:
		main_light = DirectionalLight3D.new()
		main_light.name = "DirectionalLight3D"
		sub_vp.add_child(main_light)
		
	# Rotación hacia abajo: -65° en X (iluminación cenital limpia), 35° en Y
	main_light.rotation_degrees = Vector3(-65, 35, 0)
	main_light.light_color = Color(1.0, 0.92, 0.85) # Luz estelar
	main_light.light_energy = 1.1 
	
	# Sombras nativas 3D profesionales según la calidad gráfica del juego
	var native_shadows = true
	if quality == 0: 
		native_shadows = false
			
	main_light.shadow_enabled = native_shadows
	if native_shadows:
		main_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		main_light.directional_shadow_max_distance = 150.0
		main_light.shadow_bias = 0.04
		main_light.shadow_normal_bias = 1.5
		sub_vp.positional_shadow_atlas_size = 2048
		sub_vp.positional_shadow_atlas_16_bits = true

	# 3. Limpieza de luces secundarias (GL Compatibility solo soporta 1-2 luces direccionales de forma estable)
	# El relleno ahora se maneja 100% por la luz ambiental del WorldEnvironment
	var fill_light = sub_vp.get_node_or_null("DirectionalLight3D_Fill")
	if is_instance_valid(fill_light):
		fill_light.queue_free()

	var zenith = sub_vp.get_node_or_null("DirectionalLight3D_Zenith")
	if is_instance_valid(zenith):
		zenith.queue_free()

func update_graphics_quality():
	if is_instance_valid(sub_viewport):
		_apply_ambient_and_zenith_lights(sub_viewport)

func _apply_camera_headlight(cam: Camera3D):
	if not is_instance_valid(cam):
		return
		
	# Limpieza de la luz omni anterior si existía para evitar conflictos
	var old_omni = cam.get_node_or_null("CameraOmniLight")
	if is_instance_valid(old_omni) and old_omni is OmniLight3D:
		old_omni.queue_free()
		
	var headlight = cam.get_node_or_null("CameraHeadlight")
	if is_instance_valid(headlight):
		headlight.queue_free()

# Método para forzar modo 3D perspectiva desde UI (Settings)
func set_camera_2d_mode(_active: bool):
	use_orthogonal = false

func _get_base_height_and_factor() -> Dictionary:
	var viewport_height = float(get_viewport().get_visible_rect().size.y) if is_inside_tree() else 1080.0
	if viewport_height <= 0:
		viewport_height = 1080.0
	var target_visible_height = viewport_height * scale_factor
	var fov_val = camera_3d.fov if is_instance_valid(camera_3d) else 55.0
	var fov_rad = deg_to_rad(fov_val / 2.0)
	var base_height = target_visible_height / (2.0 * tan(fov_rad))
	var factor = sqrt(1.0 + 1.0 / (tan(deg_to_rad(25.0)) * tan(deg_to_rad(25.0))))
	return {"base_height": base_height, "factor": factor}

func _sync_zooms_from_free():
	var res = _get_base_height_and_factor()
	var min_dist = 0.08 * res.base_height * res.factor
	var max_dist = 1.0 * res.base_height * res.factor
	free_cam_zoom = clamp(free_cam_zoom, min_dist, max_dist)
	fixed_cam_zoom = free_cam_zoom / (res.base_height * res.factor)

func _sync_free_from_fixed():
	var res = _get_base_height_and_factor()
	free_cam_zoom = fixed_cam_zoom * res.base_height * res.factor
	var min_dist = 0.08 * res.base_height * res.factor
	var max_dist = 1.0 * res.base_height * res.factor
	free_cam_zoom = clamp(free_cam_zoom, min_dist, max_dist)

# Guardar estado de cámara en SettingsManager (persiste entre mapas, no en disco)
func _save_camera_state():
	if not has_node("/root/SettingsManager"):
		return
	var sm = get_node("/root/SettingsManager")
	sm.cam_fixed_zoom = fixed_cam_zoom
	sm.cam_free_active = free_cam_active
	sm.cam_free_h = free_cam_h
	sm.cam_free_v = free_cam_v
	sm.cam_free_zoom = free_cam_zoom
	sm.cam_free_orbit = free_orbit_mode
	sm.set("cam_use_hybrid", use_hybrid_camera)

func _restore_camera_state():
	if not has_node("/root/SettingsManager"):
		return
	var sm = get_node("/root/SettingsManager")
	fixed_cam_zoom = sm.cam_fixed_zoom
	free_cam_active = sm.cam_free_active
	free_cam_h = sm.cam_free_h
	free_cam_v = sm.cam_free_v
	free_cam_zoom = sm.cam_free_zoom
	free_orbit_mode = sm.cam_free_orbit
	if sm.get("cam_use_hybrid") != null:
		use_hybrid_camera = sm.get("cam_use_hybrid")


# Actualizar cámara libre (orbit/free mode)
func _update_free_camera(shake_offset: Vector3 = Vector3.ZERO):
	if not is_instance_valid(camera_3d):
		return
	
	# En orbit mode, el centro sigue al jugador cada frame
	if free_orbit_mode and is_instance_valid(player_node):
		var pp = player_node.global_position
		free_cam_center = Vector3(pp.x * scale_factor, 0.0, pp.y * scale_factor * correction_z)
	
	# Ángulo FIJO (no relativo a la nave) — la cámara orbita en espacio mundo, no sigue la rotación del barco
	var rad_h = deg_to_rad(free_cam_h)
	var rad_v = deg_to_rad(free_cam_v)
	
	var offset = Vector3(
		free_cam_zoom * cos(rad_v) * sin(rad_h),
		free_cam_zoom * sin(rad_v),
		free_cam_zoom * cos(rad_v) * cos(rad_h)
	)
	
	camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera_3d.fov = 55.0
	camera_3d.position = free_cam_center + offset
	camera_3d.look_at(free_cam_center, Vector3.UP)
	# Aplicar sacudida 3D al final
	camera_3d.position += shake_offset
	
	# NO actualizar correction_z global — los assets 3D (portal, paredes, cofres, etc.)
	# se posicionaron con el tilt de la cámara fija. Si lo cambiamos, se desplazan.
	# En su lugar, calculamos uno local solo para la posición del centro si hiciera falta.

# v420.5: Convierte posición del mouse en pantalla al espacio del SubViewport.
# Esta es la ÚNICA conversión Screen→SubViewport en todo el sistema.
# Todos los demás sistemas deben usar mouse_world_pos_2d en lugar de hacer su propia conversión.
func _get_subvp_mouse_pos() -> Vector2:
	var mouse = get_viewport().get_mouse_position()
	if not is_instance_valid(viewport_container) or not is_instance_valid(sub_viewport):
		return mouse
	var offset = viewport_container.global_position
	var cont_sz = Vector2(viewport_container.size)
	var sub_sz = Vector2(sub_viewport.size)
	var local = mouse - offset
	if sub_sz.x > 0 and cont_sz.x > 0 and sub_sz != cont_sz:
		local *= sub_sz / cont_sz
	return local

# v420.5: Crea el cursor 3D world-space dentro del SubViewport.
# Estilo LoL: anillo exterior + cruz central. Vive en Y=0 (plano del suelo).
func _create_world_cursor():
	if not is_instance_valid(sub_viewport):
		return
	# Limpiar cursor viejo si existía
	var old = sub_viewport.get_node_or_null("WorldCursor3D")
	if is_instance_valid(old):
		old.queue_free()

	cursor_3d = Node3D.new()
	cursor_3d.name = "WorldCursor3D"
	cursor_3d.visible = false
	sub_viewport.add_child(cursor_3d)

	# --- Esfera del cursor (SphereMesh) ---
	var sphere = MeshInstance3D.new()
	sphere.name = "CursorSphere"
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.38
	sphere_mesh.height = 0.76
	sphere_mesh.rings = 24
	sphere_mesh.radial_segments = 24
	sphere.mesh = sphere_mesh
	sphere.position.y = 0.38

	var sphere_mat = StandardMaterial3D.new()
	sphere_mat.albedo_color = Color(0.0, 1.0, 0.85, 0.35)
	sphere_mat.emission_enabled = true
	sphere_mat.emission = Color(0.0, 0.9, 0.75)
	sphere_mat.emission_energy_multiplier = 1.5
	sphere_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.no_depth_test = false
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material_override = sphere_mat
	cursor_3d.add_child(sphere)

	# --- Cruz central (4 líneas pequeñas como en LoL) ---
	var cross_size = 0.12
	var cross_thickness = 0.035
	for i in range(4):
		var bar = MeshInstance3D.new()
		var box = BoxMesh.new()
		if i < 2:
			box.size = Vector3(cross_size, 0.04, cross_thickness)
		else:
			box.size = Vector3(cross_thickness, 0.04, cross_size)
		bar.mesh = box
		var offset_dist = 0.18
		match i:
			0: bar.position = Vector3(-offset_dist, 0.05, 0)
			1: bar.position = Vector3(offset_dist, 0.05, 0)
			2: bar.position = Vector3(0, 0.05, -offset_dist)
			3: bar.position = Vector3(0, 0.05, offset_dist)
		var bar_mat = StandardMaterial3D.new()
		bar_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		bar_mat.emission_enabled = true
		bar_mat.emission = Color(0.5, 1.0, 0.9)
		bar_mat.emission_energy_multiplier = 1.5
		bar_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		bar.material_override = bar_mat
		cursor_3d.add_child(bar)

# v420.5: Actualiza posición del cursor 3D cada frame via raycast al plano Y=0.
# En modo ortogonal (2D), oculta el cursor 3D (el SO se encarga del cursor 2D).
func _update_world_cursor():
	if not is_instance_valid(cursor_3d):
		return

	# Modo 2D: cursor del SO, sin cursor 3D
	if not is_instance_valid(camera_3d):
		cursor_3d.visible = false
		mouse_world_pos_3d = Vector3.ZERO
		mouse_world_pos_2d = Vector2.ZERO
		return

	# Raycast: mouse → SubViewport → cámara 3D → plano Y=0
	var sub_px = _get_subvp_mouse_pos()
	var ray_from = camera_3d.project_ray_origin(sub_px)
	var ray_dir = camera_3d.project_ray_normal(sub_px)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(ray_from, ray_dir * 2000.0)

	if hit != null:
		mouse_world_pos_3d = hit
		mouse_world_pos_2d = Vector2(hit.x / scale_factor, hit.z / (scale_factor * correction_z))
		cursor_3d.global_position = Vector3(hit.x, 0.05, hit.z)
		cursor_3d.visible = true
	else:
		cursor_3d.visible = false


func _process(_delta):

		
	# Sincronizar toggle de edición de cámara móvil desde SettingsManager
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and sm.mobile_mode and "mobile_camera_edit_enabled" in sm:
		if sm.mobile_camera_edit_enabled != _was_mobile_camera_edit:
			_on_mobile_camera_edit_toggled(sm.mobile_camera_edit_enabled)

	# v2.4: Comparar como string para evitar el error 'String' and 'int' cuando zone_id es "extract_X" o "arena_X"
	if str(zone_id) == "100":
		return
		
	# Cúpula estelar sigue a la cámara (sin paralaje, orientación fija en espacio mundo)
	if is_instance_valid(sub_viewport) and is_instance_valid(camera_3d):
		var dome = sub_viewport.get_node_or_null("SkyDome")
		if is_instance_valid(dome):
			dome.global_position = camera_3d.global_position
		
	# --- LOCALIZAR NAVE DEL JUGADOR ---
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]

	# --- CALCULAR OFFSET DE TEMBLOR (SHAKE) 3D ---
	var shake_offset = Vector3.ZERO
	if is_instance_valid(player_node) and "_shake_amount" in player_node:
		var shake = player_node._shake_amount
		if shake > 0.05:
			# Convertir la vibración 2D al espacio 3D multiplicando por scale_factor (0.02)
			var shake_3d = shake * scale_factor
			shake_offset = Vector3(
				randf_range(-shake_3d, shake_3d),
				randf_range(-shake_3d, shake_3d),
				randf_range(-shake_3d, shake_3d)
			)

	# --- CÁMARA LIBRE (ORBIT/FREE MODE) ---
	if free_cam_active and is_instance_valid(camera_3d):
		# WASD para paneo en free mode (no orbit)
		if not free_orbit_mode:
			var dt = get_process_delta_time()
			var rad_h = deg_to_rad(free_cam_h)
			var fwd = Vector3(sin(rad_h), 0, cos(rad_h)).normalized()
			var rgt = Vector3(cos(rad_h), 0, -sin(rad_h)).normalized()
			var pan_speed = 20.0 * (free_cam_zoom / 20.0)
			if Input.is_key_pressed(KEY_W):
				free_cam_center -= fwd * pan_speed * dt
			if Input.is_key_pressed(KEY_S):
				free_cam_center += fwd * pan_speed * dt
			if Input.is_key_pressed(KEY_A):
				free_cam_center -= rgt * pan_speed * dt
			if Input.is_key_pressed(KEY_D):
				free_cam_center += rgt * pan_speed * dt
			# Limitar paneo a los bordes del mapa + margen 10 uds 2D
			var margin_x = 10.0 * scale_factor
			var margin_z = 10.0 * scale_factor * correction_z
			var max_x = world_size * scale_factor
			var max_z = world_size * scale_factor * correction_z
			free_cam_center.x = clamp(free_cam_center.x, -margin_x, max_x + margin_x)
			free_cam_center.z = clamp(free_cam_center.z, -margin_z, max_z + margin_z)
		_update_free_camera(shake_offset)
	else:
		var target_pos = Vector2.ZERO
		if is_instance_valid(player_node):
			target_pos = player_node.global_position
				
		if is_instance_valid(camera_3d):
			camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera_3d.fov = 55.0
			self.set_meta("correction_z", correction_z)
			
			if use_hybrid_camera:
				# --- MODO TERCERA PERSONA WoW-Style (Sin Zoom) ---
				var player_rot_y = 0.0
				if is_instance_valid(player_node):
					player_rot_y = -player_node.rotation - PI/2.0
				
				# Auto-alineación horizontal detrás de la nave cuando se mueve y NO arrastramos
				if is_instance_valid(player_node) and player_node.get("is_moving") and not _lmb_dragging:
					var target_rad_h = deg_to_rad(180.0)
					hybrid_cam_h = lerp_angle(deg_to_rad(hybrid_cam_h), target_rad_h, 0.05 * 60.0 * get_process_delta_time())
					hybrid_cam_h = rad_to_deg(hybrid_cam_h)
				
				# Punto central de la nave flotante
				var base_y = 1.0
				if is_instance_valid(player_node):
					var wr3d = player_node.get("world_root_3d")
					if is_instance_valid(wr3d):
						base_y = wr3d.position.y
						
				var target_3d = Vector3(target_pos.x * scale_factor, base_y + 0.3, target_pos.y * scale_factor * correction_z)
				
				# Inicialización en el primer frame de uso para evitar transiciones kilométricas
				if not _camera_initialized:
					_smoothed_target_3d = target_3d
					_smoothed_yaw = player_rot_y
					_camera_initialized = true
				else:
					# Lerp suave de posición y rotación (yaw) de la cámara
					var dt = get_process_delta_time()
					_smoothed_target_3d = _smoothed_target_3d.lerp(target_3d, 0.08 * 60.0 * dt)
					_smoothed_yaw = lerp_angle(_smoothed_yaw, player_rot_y, 0.08 * 60.0 * dt)
				
				var rad_h = _smoothed_yaw + deg_to_rad(hybrid_cam_h - 180.0)
				var rad_v = deg_to_rad(hybrid_cam_v)
				
				# Distancia de órbita fija (suficientemente alejado en 3ª persona)
				var orbit_dist = 18.0
				
				var offset = Vector3(
					orbit_dist * cos(rad_v) * sin(rad_h),
					orbit_dist * sin(rad_v),
					orbit_dist * cos(rad_v) * cos(rad_h)
				)
				
				camera_3d.position = _smoothed_target_3d + offset
				camera_3d.look_at(_smoothed_target_3d, Vector3.UP)
				camera_3d.position += shake_offset
			else:
				# --- CÁMARA CLÁSICA (Aérea Fija Original 25°) ---
				var viewport_height = float(get_viewport().get_visible_rect().size.y)
				if viewport_height <= 0:
					viewport_height = 1080.0
				var target_visible_height = viewport_height * scale_factor
				var dynamic_height = target_visible_height / (2.0 * tan(deg_to_rad(camera_3d.fov / 2.0)))
				dynamic_height *= fixed_cam_zoom
				camera_3d.position.y = dynamic_height
				
				var z_offset = dynamic_height / tan(deg_to_rad(25.0))
				var corrected_target_z = target_pos.y * scale_factor * correction_z
				camera_3d.position.x = target_pos.x * scale_factor
				camera_3d.position.z = corrected_target_z + z_offset
				camera_3d.look_at(Vector3(target_pos.x * scale_factor, 0.0, corrected_target_z), Vector3.UP)
				camera_3d.position += shake_offset
	
	_update_world_cursor()

	# Chequear cercanía a puertas interactivas del mapa
	_check_doors_proximity()
	_update_interact_visibility()
	
	# Rotación procedimental continua de puertas 3D estilo Extracción
	if active_doors_3d.size() > 0:
		var time = Time.get_ticks_msec() * 0.001
		var index = 0
		for portal in active_doors_3d:
			if is_instance_valid(portal):
				portal.rotate_object_local(Vector3.FORWARD, _delta * 0.8)
				var phase_offset = index * 1.5
				var wobble_x = sin(time * 1.5 + phase_offset) * 0.06
				var wobble_y = cos(time * 1.1 + phase_offset) * 0.06
				portal.rotation.x = deg_to_rad(-45.0) + wobble_x
				portal.rotation.y = deg_to_rad(-90.0) + wobble_y
				index += 1

# _process removido al no haber asteroides decorativos que rotar

func _spawn_altar_if_configured():
	if not is_instance_valid(sub_viewport): return
	
	# Si ya hay un altar configurado e instanciado en objects, no spawnear otro
	var z_str = str(zone_id)
	if GameConstants.MAPS_CONFIG.has(z_str):
		var map_cfg = GameConstants.MAPS_CONFIG[z_str]
		if map_cfg.has("objects") and map_cfg.objects is Array:
			for obj in map_cfg.objects:
				if obj is Dictionary and obj.get("type") == "altar":
					print("[BaseMap] Altar ya configurado en objects. Evitando spawn duplicado.")
					return

	
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

# Variables para el sistema de puertas interactivas estilo extracción
var active_doors: Array = []
var active_doors_3d: Array = []
# v: Sistema de botones de acción múltiple (portal / vault / market / loot) en la parte inferior
var interact_canvas: CanvasLayer = null
var interact_hbox: HBoxContainer = null
var _interact_buttons: Dictionary = {} # key -> { "cell", "desc_label", "click_button" }
var _interact_icons: Dictionary = {} # key -> { "viewport", "holder" }
var _near_door_active: bool = false # Portal cercano (puertas del mapa base)
var _near_extract_portal_active: bool = false # Portal de extracción cercano (Map_Extraction)
# Variables para el sistema de interacción de vaults, market y loot drops
var active_vault_node: Node = null
var active_market_node: Node = null # v500.0: Terminal del Mercado
var active_loot_node: Node = null

# v400.1: Spawnear objetos del mundo desde mapsConfig del servidor con física, rotaciones y comportamiento Premium
# Lee objects[] de mapsConfig e instancia los modelos 3D y colisiones correspondientes
func _spawn_map_objects():
	var z_str = str(zone_id)
	# v400.5: Si zone_id viene como float (ej: 1.0), normalizar a entero para que coincida con las llaves de MAPS_CONFIG
	if "." in z_str and z_str.is_valid_float():
		var z_float = float(z_str)
		if z_float == int(z_float):
			z_str = str(int(z_float))
			
	# ARENA FIX: Si zone_id es un matchId dinámico (ej: "arena_1234567_42"), resolver el
	# mapId base desde los datos del match o desde la config del servidor.
	# El MapEditor3D guarda los objetos bajo el ID numérico del mapa (ej: "9"),
	# no bajo el matchId que es temporal y único por partida.
	if z_str.begins_with("arena_"):
		var resolved = false
		# Prioridad 1: Usar el mapId del match actual (enviado por el server en arenaMatchStarted)
		if NetworkManager and NetworkManager.current_arena_data.has("mapId"):
			z_str = str(NetworkManager.current_arena_data.mapId)
			print("[BaseMap _spawn_map_objects] Arena: zone_id dinámico resuelto a mapId=", z_str)
			resolved = true
		# Prioridad 2: Usar el primer mapa configurado en gameModes.arenas
		if not resolved:
			var full_cfg = GameConstants.get("FULL_CONFIG")
			if full_cfg and full_cfg.has("gameModes") and full_cfg.gameModes.has("arenas"):
				var arena_maps = full_cfg.gameModes.arenas.get("maps", [])
				if arena_maps.size() > 0:
					z_str = str(arena_maps[0])
					print("[BaseMap _spawn_map_objects] Arena: zone_id resuelto desde config a mapId=", z_str)
					resolved = true
		if not resolved:
			print("[BaseMap _spawn_map_objects] Arena: no se pudo resolver mapId para zone_id=", zone_id)
			return
			
	print("[BaseMap _spawn_map_objects] Iniciando spawn. zone_id es: ", z_str)
	if not (z_str in GameConstants.MAPS_CONFIG):
		print("[BaseMap _spawn_map_objects] ERROR: zone_id ", z_str, " no encontrada en MAPS_CONFIG. Configs disponibles: ", GameConstants.MAPS_CONFIG.keys())
		return
	var map_cfg = GameConstants.MAPS_CONFIG[z_str]
	print("[BaseMap _spawn_map_objects] Encontrada config para zona ", z_str, ". Objetos: ", map_cfg.get("objects"))
	if not map_cfg.has("objects") or not (map_cfg.objects is Array):
		print("[BaseMap _spawn_map_objects] ADVERTENCIA: No hay un array de objetos en la config de la zona.")
		return
		
	var vault_script = load("res://scripts/entities/Vault.gd")
	var market_script = load("res://scripts/entities/MarketTerminal.gd") # v500.0
	
	for obj in map_cfg.objects:
		if not (obj is Dictionary and obj.has("x") and obj.has("y")):
			continue
		var obj_pos = Vector2(float(obj.x), float(obj.y))
		var obj_type = str(obj.get("type", "chest"))
		var obj_label = str(obj.get("label", ""))
		
		match obj_type:
			"altar":
				# Altar de Defensa del Altar editable en 3D
				var altar_scene = load("res://assets/Altares/3D/Altar1/Altar1.glb")
				if altar_scene:
					var scale_val = float(obj.get("scale", 15.0))
					var rot_y = float(obj.get("rotY", 180.0))
					var y_offset = float(obj.get("yOffset", 0.0))
					
					var altar_3d = _instantiate_map_object_3d(altar_scene.resource_path, obj_pos, Vector3.ONE * scale_val, Vector3(0, rot_y, 0), Color(0, 1.0, 0.5), y_offset)
					if is_instance_valid(altar_3d):
						# Luz omni para brillo místico
						var light = OmniLight3D.new()
						light.name = "AltarLight"
						light.position = Vector3(0, 2.0, 0)
						light.light_color = Color(0, 1.0, 0.5) 
						light.light_energy = 5.0
						light.omni_range = 15.0
						altar_3d.add_child(light)
						
					# Area2D lógica para capturar impactos y daño
					var altar_area = Area2D.new()
					altar_area.name = "AltarArea2D"
					altar_area.collision_layer = 1 | 2
					altar_area.collision_mask = 1 | 2
					altar_area.global_position = obj_pos
					altar_area.add_to_group("altar")
					
					var col_shape = CollisionShape2D.new()
					var circle = CircleShape2D.new()
					circle.radius = 120.0
					col_shape.shape = circle
					altar_area.add_child(col_shape)
					add_child(altar_area)

					# StaticBody2D físico para obstruir paso de naves
					var static_body = StaticBody2D.new()
					static_body.name = "AltarStaticBody2D"
					static_body.collision_layer = 2
					static_body.collision_mask = 0
					static_body.global_position = obj_pos
					
					var static_col = CollisionShape2D.new()
					var static_circle = CircleShape2D.new()
					static_circle.radius = 100.0
					static_col.shape = static_circle
					static_body.add_child(static_col)
					add_child(static_body)
					print("[BaseMap] Altar instanciado correctamente desde objects config: ", obj_pos)
			"chest":
				# Baúl Premium: instanciar el script Vault.gd (ya tiene su propia lógica 3D, colisión y rango)
				if vault_script:
					var vault = Area2D.new()
					vault.name = "MapVault_" + obj_label.replace(" ", "_")
					vault.set_script(vault_script)
					vault.set_meta("custom_scale", float(obj.get("scale", 1.0)))
					vault.set_meta("custom_rot_y", float(obj.get("rotY", 0.0)))
					vault.set_meta("custom_y_offset", float(obj.get("yOffset", 0.0)))
					# ¡IMPORTANTE!: Añadir al árbol primero, luego asignar global_position
					add_child(vault)
					vault.global_position = obj_pos
					print("[BaseMap] Baúl instanciado correctamente: ", obj_label, " @ ", obj_pos)
			"market":
				# v500.0: Terminal del Mercado / Casa de Subastas (infraestructura del lobby)
				if market_script:
					var market = Area2D.new()
					market.name = "MapMarket_" + obj_label.replace(" ", "_")
					market.set_script(market_script)
					market.set_meta("custom_scale", float(obj.get("scale", 2.0)))
					market.set_meta("custom_rot_y", float(obj.get("rotY", 0.0)))
					market.set_meta("custom_y_offset", float(obj.get("yOffset", 0.0)))
					market.set_meta("asset_path", str(obj.get("assetPath", "")))
					add_child(market)
					market.global_position = obj_pos
					print("[BaseMap] Terminal de Mercado instanciado correctamente: ", obj_label, " @ ", obj_pos)
			"door":
				# Puerta de Warp Interactiva estilo Extracción: Area2D lógica para proximidad
				var target_z = str(obj.get("targetZoneId", "1"))
				# Si el mapa destino está marcado como visible = false en MAPS_CONFIG, no renderizar la puerta ni crear la colisión
				if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(target_z):
					var target_map_cfg = GameConstants.MAPS_CONFIG[target_z]
					if target_map_cfg.has("visible") and target_map_cfg.get("visible") == false:
						print("[BaseMap] Omitiendo puerta al mapa inactivo: ", target_z)
						continue

				var door = Area2D.new()
				door.name = "MapDoor_" + obj_label.replace(" ", "_")
				door.collision_mask = 1  # Detectar jugador
				door.collision_layer = 0
				
				var col = CollisionShape2D.new()
				var circle = CircleShape2D.new()
				circle.radius = 300.0  # Rango de proximidad idéntico al evento de extracción
				col.shape = circle
				door.add_child(col)
				
				# Guardar metadatos del warp
				door.set_meta("targetZoneId", str(obj.get("targetZoneId", "1")))
				door.set_meta("targetX", float(obj.get("targetX", 5000)))
				door.set_meta("targetY", float(obj.get("targetY", 5000)))
				door.set_meta("door_label", obj_label)
				
				# Cargar modelo 3D en el viewport global (usar el assetPath guardado o el de extracción como fallback)
				var model_path = str(obj.get("assetPath", ""))
				if model_path == "":
					model_path = "res://assets/Puertas/3D/Puerta2/Puerta2.glb"
				
				var scale_val = float(obj.get("scale", 1.0))
				var rot_y = float(obj.get("rotY", 0.0))
				var y_offset = float(obj.get("yOffset", 2.5))
				var model_node = _instantiate_map_object_3d(model_path, obj_pos, Vector3.ONE * scale_val, Vector3(0, rot_y, 0), Color(0.0, 0.9, 1.0), y_offset)
				if is_instance_valid(model_node):
					active_doors_3d.append(model_node)
				
				add_child(door)
				door.global_position = obj_pos
				active_doors.append(door)
				
				# Crear la UI de salto si no existe aún
				if not is_instance_valid(interact_hbox):
					_create_portal_jump_ui()
				
				print("[BaseMap] Puerta interactiva instanciada (estilo Extracción): ", obj_label, " -> Zona ", obj.get("targetZoneId", "?"))
			
			"tower":
				# Torre Premium estilo PVP: Marcador visual 3D + Colisión sólida física real
				var tower = StaticBody2D.new()
				tower.name = "MapTower_" + obj_label.replace(" ", "_")
				tower.collision_layer = 2  # Capa física para colisionar y bloquear al jugador
				tower.collision_mask = 0
				
				var col = CollisionShape2D.new()
				var circle = CircleShape2D.new()
				circle.radius = 60.0  # Radio físico real para colisión del pilar
				col.shape = circle
				tower.add_child(col)
				
				# Instanciar el modelo 3D en el viewport global (usar el assetPath guardado o el de PVP como fallback)
				var model_path = str(obj.get("assetPath", ""))
				if model_path == "":
					model_path = "res://assets/Arenas PVP/3D/Torres/Torre1/Torre1.glb"
				
				var scale_val = float(obj.get("scale", 1.0))
				var rot_y = float(obj.get("rotY", 0.0))
				var y_offset = float(obj.get("yOffset", 2.5))
				_instantiate_map_object_3d(model_path, obj_pos, Vector3.ONE * scale_val, Vector3(0, rot_y, 0), Color(1.0, 0.5, 0.0), y_offset)
				
				tower.add_to_group("towers")
				add_child(tower)
				tower.global_position = obj_pos
				print("[BaseMap] Torre (Pilar PVP) instanciado correctamente: ", obj_label, " @ ", obj_pos)
			
			"wall":
				# Pared de Dungeon: Colisión sólida 2D + Visual 3D
				var wall_body = StaticBody2D.new()
				wall_body.name = "MapWall_" + obj_label.replace(" ", "_")
				wall_body.collision_layer = 2  # Colisionar con naves
				wall_body.collision_mask = 0
				
				var scale_val = float(obj.get("scale", 1.0))
				var rot_y = float(obj.get("rotY", 0.0))
				var y_offset = float(obj.get("yOffset", 0.5))
				
				var model_path = str(obj.get("assetPath", ""))
				if model_path == "":
					model_path = "res://assets/Mapas/Mapa1/Paredes/Pared1/Pared1.glb"
				
				var model_node = _instantiate_map_object_3d(model_path, obj_pos, Vector3(scale_val, scale_val, scale_val), Vector3(0, rot_y, 0), Color(0.9, 0.3, 0.1), y_offset)
				
				var custom_size = Vector2(100.0 * scale_val, 20.0 * scale_val)
				var custom_offset = Vector2.ZERO
				
				# --- CONFIGURACIÓN DE COLLIDERS (MANUALES MÚLTIPLES O SIMPLE/AUTODETECTADA) ---
				if obj.has("colliders"):
					for c_obj in obj.colliders:
						var c_type = str(c_obj.type)
						var c_width = float(c_obj.get("width", 0.0))
						var c_height = float(c_obj.get("height", 0.0))
						var c_off_x = float(c_obj.get("offsetX", 0.0))
						var c_off_y = float(c_obj.get("offsetY", 0.0))
						var c_rot = float(c_obj.get("rot", 0.0))
						
						var sub_col = CollisionShape2D.new()
						var sub_size = Vector2.ZERO
						var sub_offset = Vector2(c_off_x, c_off_y) * scale_val
						# Rotar el offset local de acuerdo a la rotación 2D del padre (-rot_y)
						sub_offset = sub_offset.rotated(deg_to_rad(-rot_y))
						
						var sub_is_circle = false
						
						if c_type == "circle":
							sub_is_circle = true
							sub_size = Vector2(c_width, c_width) * scale_val
						else:
							sub_size = Vector2(c_width, c_height) * scale_val
							
						if sub_is_circle:
							var circle = CircleShape2D.new()
							circle.radius = sub_size.x / 2.0
							sub_col.shape = circle
						else:
							var rect = RectangleShape2D.new()
							rect.size = sub_size
							sub_col.shape = rect
							
						sub_col.position = sub_offset
						# Invertir el ángulo de rotación 3D para pasarlo a 2D
						sub_col.rotation = deg_to_rad(-(rot_y + c_rot))
						wall_body.add_child(sub_col)
				else:
					var col = CollisionShape2D.new()
					var col_type = str(obj.get("colType", ""))
					var col_width = float(obj.get("colWidth", 0.0))
					var col_height = float(obj.get("colHeight", 0.0))
					var col_offset_x = float(obj.get("colOffsetX", 0.0))
					var col_offset_y = float(obj.get("colOffsetY", 0.0))
					var col_rot = float(obj.get("colRot", 0.0))
					
					custom_size = Vector2(100.0 * scale_val, 20.0 * scale_val)
					custom_offset = Vector2.ZERO
					var is_circle = false
					
					if col_type != "":
						if col_type == "circle":
							is_circle = true
							custom_size = Vector2(col_width, col_width) * scale_val
						else:
							custom_size = Vector2(col_width, col_height) * scale_val
						custom_offset = Vector2(col_offset_x, col_offset_y) * scale_val
					else:
						if is_instance_valid(model_node):
							var aabb = _calculate_local_aabb(model_node)
							var s_factor = scale_factor
							var corr_z = correction_z
							
							var w_2d = (aabb.size.x / s_factor) * scale_val
							var h_2d = (aabb.size.z / (s_factor * corr_z)) * scale_val
							
							if w_2d > 1.0 and h_2d > 1.0:
								custom_size = Vector2(w_2d, h_2d)
								var aabb_center = aabb.position + aabb.size / 2.0
								custom_offset.x = (aabb_center.x / s_factor) * scale_val
								custom_offset.y = (aabb_center.z / (s_factor * corr_z)) * scale_val
								
								var ratio = w_2d / h_2d
								if ratio >= 0.82 and ratio <= 1.22:
									is_circle = true
					
					# Rotar el offset local de acuerdo a la rotación 2D del padre (-rot_y)
					custom_offset = custom_offset.rotated(deg_to_rad(-rot_y))
					
					if is_circle:
						var circle = CircleShape2D.new()
						circle.radius = custom_size.x / 2.0
						col.shape = circle
					else:
						var rect = RectangleShape2D.new()
						rect.size = custom_size
						col.shape = rect
						
					col.position = custom_offset
					# Invertir el ángulo de rotación 3D para pasarlo a 2D
					col.rotation = deg_to_rad(-(rot_y + col_rot))
					wall_body.add_child(col)
				
				wall_body.add_to_group("walls")
				add_child(wall_body)
				wall_body.global_position = obj_pos
				print("[BaseMap] Pared con autodetect-collider instanciada: ", obj_label, " @ ", obj_pos, " size: ", custom_size, " offset: ", custom_offset)
			
			"decor":
				var scale_val = float(obj.get("scale", 1.0))
				var rot_y = float(obj.get("rotY", 0.0))
				var y_offset = float(obj.get("yOffset", 0.5))
				var model_path = str(obj.get("assetPath", ""))
				if model_path != "":
					_instantiate_map_object_3d(model_path, obj_pos, Vector3.ONE * scale_val, Vector3(0, rot_y, 0), Color(0.8, 0.8, 0.8), y_offset)
					print("[BaseMap] Objeto decorativo (sin colisión) instanciado: ", obj_label, " @ ", obj_pos, " escala: ", scale_val, " rot: ", rot_y)
			
			"spawn":
				# Punto de spawn visual solamente (sin colisión), decorativo
				var model_path = str(obj.get("assetPath", ""))
				if model_path != "" and ResourceLoader.exists(model_path):
					var scale_val = float(obj.get("scale", 1.0))
					var rot_y = float(obj.get("rotY", 0.0))
					var y_offset = float(obj.get("yOffset", 0.0))
					_instantiate_map_object_3d(model_path, obj_pos, Vector3.ONE * scale_val, Vector3(0, rot_y, 0), Color(0.0, 1.0, 0.5), y_offset)
				# print("[BaseMap] Spawn point registrado: ", obj_label, " @ ", obj_pos)
			
			_:
				print("[BaseMap] Tipo de objeto desconocido: ", obj_type, " @ ", obj_pos)



# Instanciar modelo 3D del objeto en el Viewport global del mapa
func _instantiate_map_object_3d(asset_path: String, pos_2d: Vector2, scale_3d: Vector3, rotation_3d: Vector3, light_color: Color, y_offset: float = 0.5) -> Node3D:
	print("[BaseMap _instantiate_map_object_3d] Intentando instanciar: ", asset_path, " @ ", pos_2d)
	if not is_instance_valid(sub_viewport):
		print("[BaseMap _instantiate_map_object_3d] ERROR: sub_viewport es INVÁLIDO o NULO.")
		return null
		
	var scene = load(asset_path)
	if not scene:
		print("[BaseMap _instantiate_map_object_3d] ADVERTENCIA: Falló al cargar ", asset_path, ". Usando cilindro 3D de fallback.")
		# Fallback visual simple
		var fallback = CSGCylinder3D.new()
		fallback.radius = scale_3d.x * 0.3
		fallback.height = scale_3d.y * 1.5
		var mat = StandardMaterial3D.new()
		mat.albedo_color = light_color
		mat.emission_enabled = true
		mat.emission = light_color * 0.5
		fallback.material = mat
		fallback.position = Vector3(pos_2d.x * scale_factor, y_offset, pos_2d.y * scale_factor * correction_z)
		sub_viewport.add_child(fallback)
		return fallback
		
	var obj = scene.instantiate()
	obj.position = Vector3(pos_2d.x * scale_factor, y_offset, pos_2d.y * scale_factor * correction_z)
	obj.scale = scale_3d
	obj.rotation_degrees = rotation_3d
	
	var light = OmniLight3D.new()
	light.light_color = light_color
	light.light_energy = 4.0
	light.omni_range = 10.0
	light.position = Vector3(0, 3.0, 0)
	obj.add_child(light)
	
	sub_viewport.add_child(obj)
	return obj

# Crear UI interactiva flotante de acciones (portal / vault / market / loot)
func _create_portal_jump_ui():
	interact_canvas = CanvasLayer.new()
	interact_canvas.name = "PortalUICanvas"
	interact_canvas.layer = 100
	add_child(interact_canvas)
	
	interact_hbox = HBoxContainer.new()
	interact_hbox.name = "PortalBtnContainer"
	interact_hbox.add_to_group("portal_jump_ui")
	interact_hbox.custom_minimum_size = Vector2(80, 80)
	interact_hbox.size = Vector2(80, 80)
	interact_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	interact_hbox.add_theme_constant_override("separation", 16)
	
	interact_canvas.add_child(interact_hbox)
	interact_hbox.anchor_left = 0.5
	interact_hbox.anchor_right = 0.5
	interact_hbox.anchor_top = 1.0
	interact_hbox.anchor_bottom = 1.0
	interact_hbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	interact_hbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	interact_hbox.offset_top = -130
	interact_hbox.offset_bottom = -50
	
	interact_hbox.visible = false

# Crear (lazy) una celda de botón de acción para una categoría
func _get_or_create_interact_button(key: String) -> Dictionary:
	if _interact_buttons.has(key):
		return _interact_buttons[key]
	if not is_instance_valid(interact_canvas) or not is_instance_valid(interact_hbox):
		return {}
	
	var cell = VBoxContainer.new()
	cell.name = key.capitalize() + "Btn"
	cell.custom_minimum_size = Vector2(80, 80)
	cell.add_theme_constant_override("separation", 2)
	interact_hbox.add_child(cell)
	
	var center_slot = CenterContainer.new()
	cell.add_child(center_slot)
	
	var btn_panel = PanelContainer.new()
	btn_panel.custom_minimum_size = Vector2(64, 64)
	btn_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center_slot.add_child(btn_panel)
	
	var icon_viewport = SubViewport.new()
	icon_viewport.name = key.capitalize() + "IconViewport"
	icon_viewport.size = Vector2(64, 64)
	icon_viewport.transparent_bg = true
	icon_viewport.own_world_3d = true
	icon_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	icon_viewport.handle_input_locally = false
	icon_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	interact_canvas.add_child(icon_viewport)
	
	var icon_cam = Camera3D.new()
	icon_cam.name = "IconCam"
	icon_cam.current = true
	icon_cam.look_at_from_position(Vector3(0, 0.8, 1.5), Vector3.ZERO)
	icon_viewport.add_child(icon_cam)
	
	var icon_light = DirectionalLight3D.new()
	icon_light.look_at_from_position(Vector3(2, 4, 2), Vector3.ZERO)
	icon_light.light_energy = 1.5
	icon_viewport.add_child(icon_light)
	
	var icon_light2 = OmniLight3D.new()
	icon_light2.position = Vector3(-1, 0.5, 0)
	icon_light2.light_energy = 0.8
	icon_light2.omni_range = 5
	icon_viewport.add_child(icon_light2)
	
	var icon_env = WorldEnvironment.new()
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.ambient_light_energy = 2.0
	icon_env.environment = env
	icon_viewport.add_child(icon_env)
	
	var icon_holder = Node3D.new()
	icon_holder.name = "IconModelHolder"
	icon_viewport.add_child(icon_holder)
	
	var icon_texture = TextureRect.new()
	icon_texture.name = "IconTexture"
	icon_texture.texture = icon_viewport.get_texture()
	icon_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_texture.expand = true
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	btn_panel.add_child(icon_texture)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0.4, 0.6, 0.25)
	style_normal.border_width_left = 3
	style_normal.border_width_top = 3
	style_normal.border_width_right = 3
	style_normal.border_width_bottom = 3
	style_normal.border_color = Color(0, 0.9, 1.0, 0.8)
	style_normal.set_corner_radius_all(32)
	style_normal.anti_aliasing = true
	btn_panel.add_theme_stylebox_override("panel", style_normal)
	
	var click_button = Button.new()
	click_button.name = "ClickButton"
	click_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_button.modulate.a = 0
	click_button.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_panel.add_child(click_button)
	click_button.pressed.connect(_on_interact_button_pressed.bind(key))
	
	var desc_label = Label.new()
	desc_label.name = key.capitalize() + "DescLabel"
	desc_label.text = ""
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color.CYAN)
	desc_label.add_theme_color_override("font_outline_color", Color.BLACK)
	desc_label.add_theme_constant_override("outline_size", 5)
	cell.add_child(desc_label)
	
	cell.visible = false
	
	var parts = { "cell": cell, "desc_label": desc_label, "click_button": click_button }
	_interact_buttons[key] = parts
	_interact_icons[key] = { "viewport": icon_viewport, "holder": icon_holder }
	return parts

func _get_interact_button(key: String) -> Button:
	if not _interact_buttons.has(key):
		return null
	var cb = _interact_buttons[key].get("click_button", null)
	return cb if is_instance_valid(cb) else null

func _is_interact_visible(key: String) -> bool:
	return _interact_buttons.has(key) and is_instance_valid(_interact_buttons[key]["cell"]) and _interact_buttons[key]["cell"].visible

func _press_interact(key: String) -> void:
	var btn = _get_interact_button(key)
	if btn:
		btn.pressed.emit()

# Mostrar/ocultar una celda de botón de acción (creación lazy)
func _set_interact_button(key: String, make_visible: bool, desc: String = "") -> void:
	if make_visible:
		var parts = _get_or_create_interact_button(key)
		if parts.is_empty():
			return
		parts["cell"].visible = true
		if desc != "":
			parts["desc_label"].text = desc
	elif _interact_buttons.has(key) and is_instance_valid(_interact_buttons[key]["cell"]):
		_interact_buttons[key]["cell"].visible = false

# ¿Hay algún menú de interfaz abierto (Inventario, Config, Bóveda, Mercado, etc)?
func _is_menu_open() -> bool:
	for node in get_tree().get_nodes_in_group("inventory_ui"):
		if is_instance_valid(node) and node is CanvasItem and node.visible:
			return true
	for group in ["vault_ui", "loot_ui", "market_ui"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node):
				continue
			if node is CanvasItem and node.visible:
				return true
			if node is Control:
				var overlay = node.get_node_or_null("overlay")
				if is_instance_valid(overlay) and overlay.visible:
					return true
				if "is_open" in node and node.get("is_open"):
					return true
	return false

func _set_portal_icon(type: String):
	if not _interact_icons.has(type):
		return
	var holder = _interact_icons[type]["holder"]
	var viewport = _interact_icons[type]["viewport"]
	if not is_instance_valid(holder) or not is_instance_valid(viewport):
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var scene: PackedScene = null
	match type:
		"portal":
			scene = MODEL_PORTAL_ICON
		"vault":
			scene = MODEL_VAULT_ICON
		"loot":
			scene = MODEL_LOOT_ICON
		"market":
			if is_instance_valid(active_market_node) and active_market_node.get("TERMINAL_MODEL_SCENE"):
				scene = active_market_node.TERMINAL_MODEL_SCENE
			else:
				scene = load("res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo3/Decorativo3.glb")
	if scene:
		var model = scene.instantiate()
		model.scale = Vector3(1.5, 1.5, 1.5)
		model.rotation_degrees = Vector3(0, -90, 0)
		holder.add_child(model)

func _on_map_portal_jump_pressed(target_zone: String, _tx: float, _ty: float, _portal_label: String = ""):
	print("[BaseMap] Warp interactivo presionado -> Zona ", target_zone, " coord: ", _tx, ", ", _ty, " portal: ", _portal_label)
	if NetworkManager:
		var target_val: Variant = target_zone
		if target_zone.is_valid_int():
			target_val = int(target_zone)
			
		var payload = {
			"zoneId": target_val,
			"x": _tx,
			"y": _ty
		}
		# v600.2: Enviar la etiqueta del portal usado para el sello por misión (portal específico)
		if _portal_label != "":
			payload["portalLabel"] = _portal_label
		NetworkManager.send_event("changeZone", payload)

# Manejador genérico del botón de interacción (portal / vault / market / loot)
func _on_interact_button_pressed(key: String):
	match key:
		"portal":
			var btn = _get_interact_button("portal")
			if not btn:
				return
			var target = btn.get_meta("target_zone", "1")
			if has_method("_on_portal_jump_pressed") and btn.get_meta("use_extraction_handler", false):
				call("_on_portal_jump_pressed", target)
			else:
				var tx = btn.get_meta("targetX", 5000)
				var ty = btn.get_meta("targetY", 5000)
				var plabel = btn.get_meta("portal_label", "")
				_on_map_portal_jump_pressed(target, tx, ty, plabel)
		"vault":
			if is_instance_valid(active_vault_node) and active_vault_node.has_method("_interact"):
				active_vault_node._interact()
		"market":
			if is_instance_valid(active_market_node) and active_market_node.has_method("_interact"):
				active_market_node._interact()
		"loot":
			if is_instance_valid(active_loot_node) and active_loot_node.has_method("_interact"):
				active_loot_node._interact()

# Actualizar visibilidad de los botones de acción (portal / vault / market / loot)
func _update_interact_visibility():
	if not is_instance_valid(interact_hbox):
		return
	if _is_menu_open():
		interact_hbox.visible = false
		return
	_set_interact_button("portal", _near_door_active or _near_extract_portal_active)
	_set_interact_button("vault", is_instance_valid(active_vault_node))
	_set_interact_button("market", is_instance_valid(active_market_node))
	_set_interact_button("loot", is_instance_valid(active_loot_node))
	interact_hbox.visible = (_near_door_active or _near_extract_portal_active
		or is_instance_valid(active_vault_node) or is_instance_valid(active_market_node) or is_instance_valid(active_loot_node))

# Mostrar botón de loot directamente (llamado desde LootDrop)
func _show_loot_button(loot: Node):
	if not is_instance_valid(interact_hbox):
		_create_portal_jump_ui()
	active_loot_node = loot
	var key_text = _get_bound_interact_key("loot_claim")
	_set_interact_button("loot", true, "ABRIR COFRE [" + key_text + " / Clic]")
	_set_portal_icon("loot")
	_update_interact_visibility()

func _hide_loot_button():
	active_loot_node = null
	_update_interact_visibility()

# Registrar/desregistrar vault para interacción
func register_vault_interaction(vault: Node):
	active_vault_node = vault
	if not is_instance_valid(interact_hbox):
		_create_portal_jump_ui()
	var key_text = _get_bound_interact_key("loot_claim")
	_set_interact_button("vault", true, "ABRIR BAÚL [" + key_text + " / Clic]")
	_set_portal_icon("vault")
	_update_interact_visibility()

func unregister_vault_interaction():
	active_vault_node = null
	_update_interact_visibility()

# v500.0: Registrar/desregistrar terminal de mercado para interacción
func register_market_interaction(market: Node):
	active_market_node = market
	if not is_instance_valid(interact_hbox):
		_create_portal_jump_ui()
	var key_text = _get_bound_interact_key("loot_claim")
	_set_interact_button("market", true, "ABRIR MERCADO [" + key_text + " / Clic]")
	_set_portal_icon("market")
	_update_interact_visibility()

func unregister_market_interaction():
	active_market_node = null
	_update_interact_visibility()

# Obtener texto de tecla interactiva
func _get_bound_interact_key(action: String) -> String:
	if not InputMap.has_action(action): return "Y"
	var events = InputMap.action_get_events(action)
	if events.size() > 0:
		var key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
		if key_text == "SPACE":
			key_text = "ESPACIO"
		return key_text
	return "Y"

# Procesar la cercanía al jugador para activar la interacción de puertas
func _check_doors_proximity():
	if active_doors.size() == 0:
		_near_door_active = false
		return
		
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
			
	var active_near_door = null
	if is_instance_valid(player_node):
		for door in active_doors:
			if is_instance_valid(door):
				var dist = player_node.global_position.distance_to(door.global_position)
				# Detección dentro del radio de 300px
				if dist <= 300.0:
					active_near_door = door
					break
					
	if active_near_door != null:
		_near_door_active = true
		var parts = _get_or_create_interact_button("portal")
		if not parts.is_empty():
			var click_btn = parts["click_button"]
			# v600.2: Etiqueta del portal usado (para sellos por misión de portal específico)
			click_btn.set_meta("portal_label", active_near_door.get_meta("door_label", ""))
			# v600.2: Sello visual si una misión activa selló este portal específico
			var seal_quest: String = ""
			if NetworkManager:
				seal_quest = NetworkManager.get_portal_seal_quest(zone_id, active_near_door.get_meta("door_label", ""))
			if seal_quest != "":
				parts["desc_label"].text = "🔒 PORTAL SELLADO - " + seal_quest
				parts["desc_label"].modulate = Color(1.0, 0.4, 0.4)
				click_btn.disabled = true
				_set_portal_icon("portal")
				return
			else:
				parts["desc_label"].modulate = Color.WHITE
				click_btn.disabled = false
				var target_zone = active_near_door.get_meta("targetZoneId", "1")
				var tx = active_near_door.get_meta("targetX", 5000)
				var ty = active_near_door.get_meta("targetY", 5000)
				
				var target_name = "Lobby / Hangar"
				if GameConstants.get("MAPS_CONFIG") and GameConstants.MAPS_CONFIG.has(target_zone):
					target_name = GameConstants.MAPS_CONFIG[target_zone].get("name", "Sector " + target_zone)
				elif target_zone == "1":
					target_name = "Lobby / Hangar"
				else:
					target_name = "Sector " + target_zone
					
				var bind_key_text = "ESPACIO"
				if InputMap.has_action("portal_jump"):
					var events = InputMap.action_get_events("portal_jump")
					if events.size() > 0:
						bind_key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
						if bind_key_text == "SPACE":
							bind_key_text = "ESPACIO"
							
				parts["desc_label"].text = "ENTRAR A " + target_name.to_upper() + " [" + bind_key_text + " / Clic]"
				click_btn.set_meta("target_zone", target_zone)
				click_btn.set_meta("targetX", tx)
				click_btn.set_meta("targetY", ty)
				click_btn.set_meta("use_extraction_handler", false)
		_set_portal_icon("portal")
	else:
		_near_door_active = false
# Atajo de teclado para entrar al portal si el contenedor está visible
func _input(event):
	# v433: No robar teclas si el jugador está escribiendo (chat, inventario, etc)
	if event is InputEventKey:
		var focus_node = get_viewport().gui_get_focus_owner()
		if focus_node is LineEdit or focus_node is TextEdit:
			return

	if event.is_action_pressed("toggle_free_camera") and not event.is_echo():
		var new_mode_name = ""
		if not free_cam_active and not use_hybrid_camera:
			# De Fija a Libre
			free_cam_active = true
			use_hybrid_camera = false
			_sync_free_from_fixed()
			new_mode_name = "CÁMARA LIBRE"
		elif free_cam_active:
			# De Libre a 3D + Seguimiento
			free_cam_active = false
			use_hybrid_camera = true
			_sync_zooms_from_free()
			_camera_initialized = false
			new_mode_name = "CÁMARA 3D + SEGUIMIENTO"
		else:
			# De 3D + Seguimiento a Fija
			free_cam_active = false
			use_hybrid_camera = false
			new_mode_name = "CÁMARA FIJA"
		
		_save_camera_state()
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").cam_free_active = free_cam_active
		var hud_f = get_tree().get_first_node_in_group("hud")
		if hud_f and hud_f.has_method("notify"):
			hud_f.notify(new_mode_name, "success")
		print("[BaseMap] MODO DE CÁMARA CAMBIADO A: ", new_mode_name)
		get_viewport().set_input_as_handled()

	
	# Toggle orbit/free mode dentro de cámara libre (tecla Tab)
	if free_cam_active and event.is_action_pressed("toggle_orbit_mode") and not event.is_echo():
		free_orbit_mode = !free_orbit_mode
		_save_camera_state()
		# Al entrar en PANEO, cancelar aiming (en ORBIT los skills funcionan)
		if not free_orbit_mode:
			var pn = get_tree().get_first_node_in_group("player")
			if is_instance_valid(pn) and is_instance_valid(pn._skill_controller):
				pn._skill_controller.is_aiming = false
				pn._skill_controller.queue_redraw()
		var hud_f = get_tree().get_first_node_in_group("hud")
		var msg_f = "CÁMARA LIBRE " + ("ORBIT" if free_orbit_mode else "PANEO")
		if hud_f and hud_f.has_method("notify"):
			hud_f.notify(msg_f, "info")
		print("[BaseMap] ", msg_f)
		get_viewport().set_input_as_handled()
	
	# Click/drag para rotación de cámara (configurable: por defecto LMB)
	if event is InputEventMouseButton:
		var cam_btn = MOUSE_BUTTON_LEFT
		if SettingsManager and SettingsManager.get("control_cam_rotate_btn") == "RMB":
			cam_btn = MOUSE_BUTTON_RIGHT
			
		if event.button_index == cam_btn:
			# Si estamos en Cámara Fija, no permitir arrastrar/mover la cámara
			if not free_cam_active and not use_hybrid_camera:
				return
				
			var hovered = get_viewport().gui_get_hovered_control()
			if hovered != null and not (hovered is SubViewportContainer):
				return
			
			_lmb_dragging = event.pressed
			if event.pressed:
				_lmb_drag_last = event.position
				set_meta("lmb_dragged", false)
			else:
				# Si se arrastró, consumimos el evento para evitar selección accidental.
				# Si fue un click limpio, permitimos que pase para seleccionar enemigos o interactuar.
				if get_meta("lmb_dragged", false):
					get_viewport().set_input_as_handled()

	# Scroll para zoom en cámara fija
	if not free_cam_active and not use_hybrid_camera and event is InputEventMouseButton and event.pressed:
		if (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var hovered = get_viewport().gui_get_hovered_control()
			if hovered != null and not (hovered is SubViewportContainer):
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				fixed_cam_zoom = max(0.08, fixed_cam_zoom - 0.04)
			else:
				fixed_cam_zoom = min(1.0, fixed_cam_zoom + 0.04)
			_save_camera_state()
			get_viewport().set_input_as_handled()

	# Middle-click drag para orbitar (solo en cámara libre)
	if free_cam_active and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_dragging = event.pressed
			if event.pressed:
				_drag_last = event.position
			get_viewport().set_input_as_handled()
		
		# Scroll para zoom (solo en cámara libre)
		if (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN) and event.pressed:
			var hovered = get_viewport().gui_get_hovered_control()
			if hovered != null and not (hovered is SubViewportContainer):
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				free_cam_zoom -= 2.0
			else:
				free_cam_zoom += 2.0
			_sync_zooms_from_free()
			_save_camera_state()
			get_viewport().set_input_as_handled()
	
	# Motion drag para orbitar (como MMO: arrastrar con LMB en híbrida o libre, o MMB en libre)
	if event is InputEventMouseMotion:
		if _lmb_dragging:
			var rel = event.relative
			set_meta("lmb_dragged", true)
			if free_cam_active:
				free_cam_h += rel.x * 0.15
				free_cam_v = clamp(free_cam_v + rel.y * 0.15, 1.0, 85.0)
			else:
				hybrid_cam_h += rel.x * 0.15
				hybrid_cam_v = clamp(hybrid_cam_v + rel.y * 0.15, -60.0, 85.0)

			_save_camera_state()
			get_viewport().set_input_as_handled()
		elif free_cam_active and _mid_dragging:
			var delta = event.position - _drag_last
			free_cam_h += delta.x * 0.3
			free_cam_v = clamp(free_cam_v + delta.y * 0.3, 1.0, 85.0)
			_drag_last = event.position
			_save_camera_state()
			get_viewport().set_input_as_handled()

		
	if event.is_action_pressed("portal_jump") and not event.is_echo():
		if _is_interact_visible("portal"):
			var p_btn = _get_interact_button("portal")
			if p_btn and not p_btn.disabled:
				_press_interact("portal")
				get_viewport().set_input_as_handled()

	if event.is_action_pressed("loot_claim") and not event.is_echo():
		for k in ["vault", "market", "loot"]:
			if _is_interact_visible(k):
				_press_interact(k)
				get_viewport().set_input_as_handled()
				break
	
	# --- MOBILE CAMERA TOUCH CONTROLS (drag de órbita de 1 dedo, zoom de 2 dedos) ---
	# Todo el manejo táctil vive aquí, en BaseMap._input(), porque:
	# 1. BaseMap tiene acceso directo a free_cam_h, free_cam_v, free_cam_zoom
	# 2. En Android, InputEventScreenDrag no llega a gui_input de Controls en todos los casos
	# 3. _input() de BaseMap recibe TODOS los eventos incluyendo los ya marcados como handled por la GUI
	#    (los botones del HUD marcan sus toques como handled, pero BaseMap los ignora porque
	#     gui_get_control_under_position() devuelve el control correcto)
	var sm_touch = get_node_or_null("/root/SettingsManager")
	if sm_touch and sm_touch.mobile_mode and "mobile_camera_edit_enabled" in sm_touch:
		var is_touch_edit = int(sm_touch.mobile_camera_edit_enabled)
		# Solo procesar si está en modo LIBRE EDITABLE (state == 1)
		if is_touch_edit == 1:
			_handle_mobile_camera_touch(event, sm_touch)

# Alternar edición de cámara móvil desde Settings
func _on_mobile_camera_edit_toggled(state: int):
	var sm = get_node_or_null("/root/SettingsManager")
	if not sm or not sm.mobile_mode:
		return
	free_cam_active = (state != 0)
	if state != 0:
		_sync_free_from_fixed()
		_restore_camera_state()
	else:
		_sync_zooms_from_free()
		_save_camera_state()
	_was_mobile_camera_edit = state

# Manejo táctil de cámara libre en móvil: 1 dedo orbita, 2 dedos hacen zoom.
# Vive en BaseMap._input() porque aquí están free_cam_h, free_cam_v, etc.
func _handle_mobile_camera_touch(event: InputEvent, sm: Node):
	var sens = sm.get("mobile_camera_sensitivity") if sm.get("mobile_camera_sensitivity") else 1.0
	
	if event is InputEventScreenTouch:
		if event.pressed:
			# Chequear si el toque está sobre un control interactivo del HUD
			# Si es así, NO capturamos: la GUI lo maneja (botón ojito, skills, joystick, etc.)
			var ctrl = get_viewport().gui_get_control_under_position(event.position)
			var on_interactive_ui = false
			if ctrl and is_instance_valid(ctrl):
				if ctrl is Button or ctrl is TextureButton or ctrl is Slider or ctrl is LineEdit or ctrl is OptionButton:
					on_interactive_ui = true
				elif ctrl.name in ["VirtualJoystick", "ControlBar", "ChatUI", "RadarWindow", "CenterStats", "PartyHUD", "Skills", "CamEdit"]:
					on_interactive_ui = true
				elif ctrl.get_parent() and ctrl.get_parent().name in ["VirtualJoystick", "ControlBar", "GridContainer"]:
					on_interactive_ui = true
			
			if not on_interactive_ui:
				get_viewport().set_input_as_handled() # Consumir el toque para que NO dispare apuntado/mira
				if not _mobile_touch_points.has(event.index):
					_mobile_touch_points[event.index] = event.position
				
				if _mobile_touch_points.size() == 1 and _mobile_cam_drag_index == -1:
					# 1 dedo: registrar como drag de órbita
					_mobile_cam_drag_index = event.index
					_mobile_cam_drag_last = event.position
				elif _mobile_touch_points.size() == 2:
					# 2 dedos: cancelar órbita, iniciar pinza
					_mobile_cam_drag_index = -1
					var keys = _mobile_touch_points.keys()
					_pinch_start_dist = _mobile_touch_points[keys[0]].distance_to(_mobile_touch_points[keys[1]])
		else:
			if _mobile_cam_drag_index != -1 and event.index == _mobile_cam_drag_index:
				get_viewport().set_input_as_handled()
			_mobile_touch_points.erase(event.index)
			if event.index == _mobile_cam_drag_index:
				_mobile_cam_drag_index = -1
			if _mobile_touch_points.size() < 2:
				_pinch_start_dist = 0.0
	
	elif event is InputEventScreenDrag:
		_mobile_touch_points[event.index] = event.position
		
		# Órbita de 1 dedo
		if event.index == _mobile_cam_drag_index:
			get_viewport().set_input_as_handled() # Consumir el arrastre para que NO active el apuntado/mira
			var delta = event.position - _mobile_cam_drag_last
			_mobile_cam_drag_last = event.position
			free_cam_h += delta.x * 0.3 * sens
			free_cam_v = clamp(free_cam_v + delta.y * 0.3 * sens, 1.0, 85.0)
			_save_camera_state()
		
		# Zoom con pinza de 2 dedos
		elif _mobile_touch_points.size() >= 2 and _pinch_start_dist > 0.0:
			get_viewport().set_input_as_handled()
			var keys = _mobile_touch_points.keys()
			if keys.size() >= 2:
				var p1 = _mobile_touch_points[keys[0]]
				var p2 = _mobile_touch_points[keys[1]]
				var current_dist = p1.distance_to(p2)
				var zoom_delta = (_pinch_start_dist - current_dist) * 0.1
				free_cam_zoom += zoom_delta
				_pinch_start_dist = current_dist
				_sync_zooms_from_free()
				_save_camera_state()

# Lee la tecla bindeada para mostrar en notificaciones
func _get_bound_key_text(action: String) -> String:
	if not InputMap.has_action(action): return "?"
	var events = InputMap.action_get_events(action)
	if events.size() > 0:
		var e = events[0]
		if e is InputEventKey:
			var kc = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			if kc != 0:
				return OS.get_keycode_string(kc).to_upper()
		elif e is InputEventMouseButton:
			return "M" + str(e.button_index)
	return "?"

func _calculate_local_aabb(node: Node3D) -> AABB:
	var total_aabb = AABB()
	var first = true
	if not is_instance_valid(node):
		return total_aabb
	
	# Pila guarda [nodo, transform_acumulado_relativo_al_root]
	var stack = [[node, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var item = stack.pop_back()
		var curr = item[0]
		var accum_trans = item[1]
		
		if curr is MeshInstance3D and curr.mesh:
			var local_aabb = curr.mesh.get_aabb()
			var trans_aabb = accum_trans * local_aabb
			if first:
				total_aabb = trans_aabb
				first = false
			else:
				total_aabb = total_aabb.merge(trans_aabb)
				
		for child in curr.get_children():
			if child is Node3D:
				var child_trans = accum_trans * child.transform
				stack.append([child, child_trans])
	return total_aabb
