extends Node
class_name FogOfWarManager

# Referencias internas y externas
var parent_map: BaseMap = null
var map_size: Vector2 = Vector2(4000.0, 4000.0)



# Viewports off-screen de renderizado de niebla
var vision_viewport: SubViewport
var history_viewport: SubViewport

# Clases de dibujado personalizadas para los viewports
var vision_drawer: VisionDrawer
var history_drawer: HistoryDrawer

# Recursos e instancias de renderizado 3D
var radial_gradient_tex: GradientTexture2D
var post_process_quad: MeshInstance3D
var shader_mat: ShaderMaterial

# Preload de recursos necesarios
const FOG_SHADER = preload("res://resources/shaders/fog_of_war.gdshader")
const TEXTURE_NOISE_21D = preload("res://VFX/textures/T_VFX_Noise21d_tiled.png")

# Clases internas (Drawers) para encapsular el dibujo de CanvasItem sin dependencias de señales externas
class VisionDrawer extends Node2D:
	var parent_fow: FogOfWarManager = null
	
	func _draw():
		if is_instance_valid(parent_fow):
			parent_fow._draw_vision(self)

class HistoryDrawer extends Node2D:
	var parent_fow: FogOfWarManager = null
	
	func _draw():
		if is_instance_valid(parent_fow):
			parent_fow._draw_history(self)

func setup(map: BaseMap):
	parent_map = map
	map_size = Vector2(map.world_size, map.map_height)
	
	_init_gradient_texture()
	_create_viewports()
	_setup_post_process_quad()

func _init_gradient_texture():
	var grad = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	
	radial_gradient_tex = GradientTexture2D.new()
	radial_gradient_tex.gradient = grad
	radial_gradient_tex.fill = GradientTexture2D.FILL_RADIAL
	radial_gradient_tex.fill_from = Vector2(0.5, 0.5)
	radial_gradient_tex.fill_to = Vector2(1.0, 0.5)
	radial_gradient_tex.width = 256
	radial_gradient_tex.height = 256

func _create_viewports():
	# 1. Viewport de Visión Activa (se limpia automáticamente en cada frame)
	vision_viewport = SubViewport.new()
	vision_viewport.name = "VisionViewport"
	vision_viewport.size = Vector2i(1024, 1024)
	vision_viewport.own_world_3d = false
	vision_viewport.transparent_bg = false
	vision_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vision_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(vision_viewport)
	
	vision_drawer = VisionDrawer.new()
	vision_drawer.name = "VisionDrawer"
	vision_drawer.parent_fow = self
	vision_viewport.add_child(vision_drawer)
	
	# 2. Viewport del Historial (clear_mode NEVER: acumula lo dibujado indefinidamente)
	history_viewport = SubViewport.new()
	history_viewport.name = "HistoryViewport"
	history_viewport.size = Vector2i(1024, 1024)
	history_viewport.own_world_3d = false
	history_viewport.transparent_bg = false
	history_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	history_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(history_viewport)
	
	history_drawer = HistoryDrawer.new()
	history_drawer.name = "HistoryDrawer"
	history_drawer.parent_fow = self
	history_viewport.add_child(history_drawer)

func _setup_post_process_quad():
	if not is_instance_valid(parent_map) or not is_instance_valid(parent_map.camera_3d):
		return
		
	var camera = parent_map.camera_3d
	
	# Limpieza de quad previo si existe
	var old_quad = camera.get_node_or_null("FogOfWarQuad")
	if is_instance_valid(old_quad):
		old_quad.queue_free()
		
	post_process_quad = MeshInstance3D.new()
	post_process_quad.name = "FogOfWarQuad"
	
	# Evitar que el quad proyecte sombras gigantescas sobre el plano de juego en GLES3
	post_process_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post_process_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	post_process_quad.mesh = quad_mesh
	
	# Crear y configurar material con shader
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = FOG_SHADER
	
	var map_size_3d = Vector2(
		parent_map.world_size * parent_map.scale_factor,
		parent_map.map_height * parent_map.scale_factor * parent_map.correction_z
	)
	
	shader_mat.set_shader_parameter("map_size_3d", map_size_3d)
	shader_mat.set_shader_parameter("vision_texture", vision_viewport.get_texture())
	shader_mat.set_shader_parameter("history_texture", history_viewport.get_texture())
	shader_mat.set_shader_parameter("noise_texture", TEXTURE_NOISE_21D)
	
	post_process_quad.material_override = shader_mat
	post_process_quad.extra_cull_margin = 16384.0
	
	camera.add_child(post_process_quad)

func get_vision_providers() -> Array:
	var list = []
	
	# Obtener jugador local
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.get("is_dead") != true:
		list.append(player)
		
	# Obtener aliados o miembros del grupo en la escena
	var entities = get_tree().get_nodes_in_group("entities")
	for entity in entities:
		if is_instance_valid(entity) and entity.get("is_dead") != true:
			if entity.get("_is_ally") == true:
				list.append(entity)
				
	return list

func _draw_vision(drawer: Node2D):
	# Limpiar el fondo del canvas de visión a negro
	drawer.draw_rect(Rect2(0, 0, 1024, 1024), Color.BLACK)
	_draw_all_vision_circles(drawer)

var _history_cleared: bool = false
func _draw_history(drawer: Node2D):
	# Limpiar una sola vez en el primer frame del juego
	if not _history_cleared:
		drawer.draw_rect(Rect2(0, 0, 1024, 1024), Color.BLACK)
		_history_cleared = true
	_draw_all_vision_circles(drawer)

func _draw_all_vision_circles(drawer: Node2D):
	var providers = get_vision_providers()
	
	# Telemetría diagnóstica cada 180 frames para verificar la lógica de dibujado
	var should_log = Engine.get_frames_drawn() % 180 == 0
	if should_log:
		print("[FogOfWar] Dibujando vision. Cantidad de proveedores: ", providers.size(), " MapSize: ", map_size)
		
	for provider in providers:
		var pos_2d = provider.global_position
		var vr = provider.get("vision_range") if "vision_range" in provider else 1300.0
		
		# Evitar división por cero
		var mx = map_size.x if map_size.x > 0.0 else 4000.0
		var my = map_size.y if map_size.y > 0.0 else 4000.0
		
		# Escalar coordenadas lógicas del mapa [0..world_size] al tamaño del viewport [0..1024]
		var x = (pos_2d.x / mx) * 1024.0
		var y = (pos_2d.y / my) * 1024.0
		
		# Ajustar el radio de visión al aspect ratio de la textura para que en 3D sea circular perfecto
		var rx = (vr / mx) * 1024.0
		var ry = (vr / my) * 1024.0
		
		var rect = Rect2(x - rx, y - ry, rx * 2.0, ry * 2.0)
		drawer.draw_texture_rect(radial_gradient_tex, rect, false)
		
		if should_log:
			print(" - [FOW Provider] ", provider.name, " Pos2D: ", pos_2d, " VpPos: ", Vector2(x, y), " Rad: ", Vector2(rx, ry))

func _process(_delta):
	# Sincronizar el tamaño del mapa en 3D dinámicamente
	if is_instance_valid(parent_map):
		map_size = Vector2(parent_map.world_size, parent_map.map_height)
		if is_instance_valid(shader_mat):
			var map_size_3d = Vector2(
				parent_map.world_size * parent_map.scale_factor,
				parent_map.map_height * parent_map.scale_factor * parent_map.correction_z
			)
			shader_mat.set_shader_parameter("map_size_3d", map_size_3d)
			
			# Re-asignar texturas para asegurar sincronización con la GPU en Godot 4
			if is_instance_valid(vision_viewport):
				shader_mat.set_shader_parameter("vision_texture", vision_viewport.get_texture())
			if is_instance_valid(history_viewport):
				shader_mat.set_shader_parameter("history_texture", history_viewport.get_texture())
			
	# Forzar el redibujado de los viewports
	if is_instance_valid(vision_drawer):
		vision_drawer.queue_redraw()
	if is_instance_valid(history_drawer):
		history_drawer.queue_redraw()
