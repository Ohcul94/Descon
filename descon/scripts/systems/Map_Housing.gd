extends BaseMap

# Map_Housing.gd - Sistema de Housing 3D Basado en Grillas
# Cámara rotativa completa 3D, previsualización de colocación y luces dinámicas.

const GRID_CELL_SIZE = 3.0 # Tamaño de cada celda en unidades 3D
var grid_size = 10 # Se actualiza con la configuración del servidor

var housing_unlocked = false
var placed_objects = [] # Lista de objetos colocados en local y sincronizados
var object_nodes = {} # { placement_id: Node3D }

# Estado de la Edición
var is_edit_mode = false
var selected_item_type = "" # ID del catálogo, ej: 'chair', 'light'
var preview_node: Node3D = null
var current_preview_x = 0
var current_preview_z = 0
var current_preview_rot = 0 # 0, 90, 180, 270 grados

# Control de Cámara Orbit
var camera_angle_h = 45.0 # Ángulo horizontal (grados)
var camera_angle_v = 45.0 # Ángulo vertical (grados)
var camera_zoom = 25.0
const MIN_ZOOM = 10.0
const MAX_ZOOM = 50.0

# Nodo raíz para los objetos 3D dentro del sub_viewport
var housing_root_3d: Node3D = null
var grid_lines_3d: Node3D = null

func _ready():
	super._ready()
	use_orthogonal = false # Usar perspectiva hermosa para la cámara de housing
	setup_map()
	_toggle_hud_elements_for_housing(false)

func setup_map():
	zone_name = "MI HANGAR PRIVADO"
	zone_id = 100
	print("[HOUSING] Inicializando Mapa de Housing...")
	
	# Asegurar nodo contenedor 3D
	if is_instance_valid(sub_viewport):
		housing_root_3d = Node3D.new()
		housing_root_3d.name = "HousingRoot3D"
		sub_viewport.add_child(housing_root_3d)
		
		# Crear piso 3D (Grilla)
		_create_grid_visuals()
		
		# Inyectar una luz ambiental hermosa adicional
		var omni = OmniLight3D.new()
		omni.name = "HousingGeneralLight"
		omni.position = Vector3(GRID_CELL_SIZE * 5, 10.0, GRID_CELL_SIZE * 5)
		omni.light_color = Color(0.8, 0.9, 1.0)
		omni.light_energy = 2.0
		omni.omni_range = 40.0
		housing_root_3d.add_child(omni)

	# Conectar señales del NetworkManager si existen
	if not NetworkManager.socket_event_received.is_connected(_on_socket_event_received):
		NetworkManager.socket_event_received.connect(_on_socket_event_received)

	# Solicitar estado de housing
	NetworkManager.send_event("getHousingState", {})

func _create_grid_visuals():
	if not is_instance_valid(housing_root_3d): return
	
	if is_instance_valid(grid_lines_3d):
		grid_lines_3d.queue_free()
		
	grid_lines_3d = Node3D.new()
	grid_lines_3d.name = "GridLines3D"
	housing_root_3d.add_child(grid_lines_3d)
	
	# Obtener tamaño de grilla desde constantes
	var full_config = GameConstants.get("FULL_CONFIG")
	if full_config and full_config.has("housingConfig"):
		grid_size = int(full_config.housingConfig.get("gridSize", 10))
	
	# Crear malla para el suelo de la grilla
	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(grid_size * GRID_CELL_SIZE, grid_size * GRID_CELL_SIZE)
	mesh_instance.mesh = plane_mesh
	
	# Posicionar el centro del plano en el centro de la grilla
	var half_grid = (grid_size * GRID_CELL_SIZE) / 2.0
	mesh_instance.position = Vector3(half_grid, 0.0, half_grid)
	
	# Material del suelo (metálico futurista oscuro)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.08, 0.15)
	mat.metallic = 0.8
	mat.roughness = 0.3
	mesh_instance.material_override = mat
	grid_lines_3d.add_child(mesh_instance)
	
	# Dibujar líneas de grilla (usando pequeños cilindros como cables de neón cian)
	for i in range(grid_size + 1):
		# Líneas a lo largo del eje Z
		var z_line = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = grid_size * GRID_CELL_SIZE
		z_line.mesh = cyl
		z_line.rotation.x = PI / 2.0
		z_line.position = Vector3(i * GRID_CELL_SIZE, 0.01, half_grid)
		
		var grid_mat = StandardMaterial3D.new()
		grid_mat.albedo_color = Color(0.0, 0.6, 1.0)
		grid_mat.emission_enabled = true
		grid_mat.emission = Color(0.0, 0.6, 1.0)
		grid_mat.emission_energy_multiplier = 1.5
		z_line.material_override = grid_mat
		grid_lines_3d.add_child(z_line)
		
		# Líneas a lo largo del eje X
		var x_line = MeshInstance3D.new()
		x_line.mesh = cyl
		x_line.rotation.z = PI / 2.0
		x_line.position = Vector3(half_grid, 0.01, i * GRID_CELL_SIZE)
		x_line.material_override = grid_mat
		grid_lines_3d.add_child(x_line)

func _process(delta):
	# Manejar el control rotativo 3D de la cámara
	_update_orbit_camera()
	
	# Actualizar posición del preview
	if is_edit_mode and is_instance_valid(preview_node):
		var target_pos = Vector3(
			(current_preview_x * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0),
			0.1,
			(current_preview_z * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0)
		)
		preview_node.position = preview_node.position.lerp(target_pos, delta * 20.0)
		preview_node.rotation.y = lerp_angle(preview_node.rotation.y, deg_to_rad(current_preview_rot), delta * 20.0)

func _update_orbit_camera():
	if not is_instance_valid(camera_3d): return
	
	# Rotación horizontal con flechas IZQUIERDA / DERECHA
	if Input.is_key_pressed(KEY_LEFT):
		camera_angle_h += 100.0 * get_process_delta_time()
	if Input.is_key_pressed(KEY_RIGHT):
		camera_angle_h -= 100.0 * get_process_delta_time()
		
	# Inclinación vertical con flechas ARRIBA / ABAJO
	if Input.is_key_pressed(KEY_UP):
		camera_angle_v = clamp(camera_angle_v - 80.0 * get_process_delta_time(), 10.0, 85.0)
	if Input.is_key_pressed(KEY_DOWN):
		camera_angle_v = clamp(camera_angle_v + 80.0 * get_process_delta_time(), 10.0, 85.0)

	# Calcular posición esférica de la cámara alrededor del centro de la grilla
	var half_grid = (grid_size * GRID_CELL_SIZE) / 2.0
	var center = Vector3(half_grid, 0.0, half_grid)
	
	var rad_h = deg_to_rad(camera_angle_h)
	var rad_v = deg_to_rad(camera_angle_v)
	
	var offset = Vector3(
		camera_zoom * cos(rad_v) * sin(rad_h),
		camera_zoom * sin(rad_v),
		camera_zoom * cos(rad_v) * cos(rad_h)
	)
	
	camera_3d.position = center + offset
	camera_3d.look_at(center, Vector3.UP)
	camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE

func _on_socket_event_received(event_name: String, data: Dictionary):
	if event_name == "housingState":
		housing_unlocked = data.get("unlocked", false)
		placed_objects = data.get("placedObjects", [])
		_sync_placed_objects()
		_update_hud_buttons()

func _sync_placed_objects():
	if not is_instance_valid(housing_root_3d): return
	
	# Eliminar nodos viejos que no estén en la lista recibida
	var current_ids = []
	for obj in placed_objects:
		current_ids.append(obj.id)
		
	for id in object_nodes.keys():
		if not id in current_ids:
			if is_instance_valid(object_nodes[id]):
				object_nodes[id].queue_free()
			object_nodes.erase(id)
			
	# Instanciar o mover los objetos colocados
	var full_config = GameConstants.get("FULL_CONFIG")
	var catalog = []
	if full_config and full_config.has("housingConfig"):
		catalog = full_config.housingConfig.get("placeableItems", [])
		
	for obj in placed_objects:
		var id = obj.id
		var item_type = obj.itemType
		var x = int(obj.x)
		var z = int(obj.z)
		var rot = int(obj.rotation)
		
		var item_cfg = null
		for item in catalog:
			if item.id == item_type:
				item_cfg = item
				break
				
		var target_pos = Vector3(
			(x * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0),
			0.0,
			(z * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0)
		)
		
		if not id in object_nodes:
			var node = _instance_3d_object(item_cfg, item_type)
			housing_root_3d.add_child(node)
			object_nodes[id] = node
			
		var instance = object_nodes[id]
		instance.position = target_pos
		instance.rotation.y = deg_to_rad(rot)

# Función mágica robusta para instanciar el GLB o generar un fallback estético
func _instance_3d_object(item_cfg, item_type: String) -> Node3D:
	var node = Node3D.new()
	var loaded_scene = null
	
	if item_cfg and item_cfg.has("model"):
		var path = item_cfg.model
		if ResourceLoader.exists(path):
			loaded_scene = load(path)
			
	if loaded_scene:
		var inst = loaded_scene.instantiate()
		node.add_child(inst)
	else:
		# Fallback estético basado en el tipo
		var mesh_inst = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		var mat = StandardMaterial3D.new()
		
		if item_type == "chair":
			mesh.size = Vector3(0.8, 1.2, 0.8)
			mat.albedo_color = Color(0.6, 0.3, 0.1) # Madera
			mat.roughness = 0.5
		elif item_type == "table":
			mesh.size = Vector3(1.8, 0.9, 1.2)
			mat.albedo_color = Color(0.3, 0.3, 0.35) # Metalizado
			mat.metallic = 0.9
			mat.roughness = 0.2
		elif item_type == "light":
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.2
			cyl.bottom_radius = 0.2
			cyl.height = 2.5
			mesh = cyl
			mat.albedo_color = Color(0.1, 0.1, 0.1)
			
			# Luz integrada
			var light = OmniLight3D.new()
			light.name = "DynamicNeon"
			light.light_color = Color(0.0, 1.0, 1.0)
			light.light_energy = 3.0
			light.omni_range = 8.0
			light.position.y = 1.2
			node.add_child(light)
			
			# Efecto de neón brillante
			var neon_mesh = MeshInstance3D.new()
			var neon_cyl = CylinderMesh.new()
			neon_cyl.top_radius = 0.15
			neon_cyl.bottom_radius = 0.15
			neon_cyl.height = 1.0
			neon_mesh.mesh = neon_cyl
			neon_mesh.position.y = 0.7
			var neon_mat = StandardMaterial3D.new()
			neon_mat.albedo_color = Color(0.0, 1.0, 1.0)
			neon_mat.emission_enabled = true
			neon_mat.emission = Color(0.0, 1.0, 1.0)
			neon_mat.emission_energy_multiplier = 2.0
			neon_mesh.material_override = neon_mat
			node.add_child(neon_mesh)
		elif item_type == "plant":
			var sph = SphereMesh.new()
			sph.radius = 0.6
			sph.height = 1.0
			mesh = sph
			mat.albedo_color = Color(0.0, 0.8, 0.3) # Verde holográfico
			mat.emission_enabled = true
			mat.emission = Color(0.0, 0.8, 0.3)
			mat.emission_energy_multiplier = 0.8
		else:
			mesh.size = Vector3(1.0, 1.0, 1.0)
			mat.albedo_color = Color(0.8, 0.0, 0.8) # Violeta incógnita
			
		mesh_inst.mesh = mesh
		mesh_inst.material_override = mat
		mesh_inst.position.y = mesh.get("height", 0.0) / 2.0 if mesh.has_method("get") else 0.5
		node.add_child(mesh_inst)
		
	return node

# Métodos HUD y Control de Edición
func enter_edit_mode(item_type: String):
	if is_edit_mode: _clear_preview()
	
	is_edit_mode = true
	selected_item_type = item_type
	
	# Buscar config
	var full_config = GameConstants.get("FULL_CONFIG")
	var catalog = []
	if full_config and full_config.has("housingConfig"):
		catalog = full_config.housingConfig.get("placeableItems", [])
		
	var item_cfg = null
	for item in catalog:
		if item.id == item_type:
			item_cfg = item
			break
			
	preview_node = _instance_3d_object(item_cfg, item_type)
	
	# Teñir preview en color verde traslúcido
	_apply_preview_material(preview_node)
	
	if is_instance_valid(housing_root_3d):
		housing_root_3d.add_child(preview_node)
		
	current_preview_x = int(grid_size / 2.0)
	current_preview_z = int(grid_size / 2.0)
	current_preview_rot = 0

func _apply_preview_material(node: Node):
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4) # Verde semitraslúcido
			mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			child.material_override = mat
		_apply_preview_material(child)

func _clear_preview():
	if is_instance_valid(preview_node):
		preview_node.queue_free()
		preview_node = null
	is_edit_mode = false

func _input(event):
	# Procesar Zoom del mouse de forma global en la zona de housing
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom = clamp(camera_zoom - 2.0, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom = clamp(camera_zoom + 2.0, MIN_ZOOM, MAX_ZOOM)

	if not is_edit_mode: return
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_W: # Mover Norte
			current_preview_z = clamp(current_preview_z - 1, 0, grid_size - 1)
		elif event.keycode == KEY_S: # Mover Sur
			current_preview_z = clamp(current_preview_z + 1, 0, grid_size - 1)
		elif event.keycode == KEY_A: # Mover Oeste
			current_preview_x = clamp(current_preview_x - 1, 0, grid_size - 1)
		elif event.keycode == KEY_D: # Mover Este
			current_preview_x = clamp(current_preview_x + 1, 0, grid_size - 1)
		elif event.keycode == KEY_R: # Rotar 90°
			current_preview_rot = (current_preview_rot + 90) % 360
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER: # Colocar
			_place_current_object()
		elif event.keycode == KEY_ESCAPE: # Cancelar
			_clear_preview()

func _place_current_object():
	# Enviar evento de colocación al servidor
	var data = {
		"itemType": selected_item_type,
		"x": current_preview_x,
		"z": current_preview_z,
		"rotation": current_preview_rot
	}
	NetworkManager.send_event("placeHousingObject", data)
	_clear_preview()

# Integración del HUD del Hangar
func _update_hud_buttons():
	var world_node = get_tree().get_first_node_in_group("world_node")
	if not world_node or not is_instance_valid(world_node.ui_hud): return
	
	var hud = world_node.ui_hud
	
	# Asegurarnos de remover cualquier panel de control viejo
	var old_panel = hud.get_node_or_null("HousingControlPanel")
	if is_instance_valid(old_panel):
		old_panel.queue_free()
		
	# Crear botón minimalista arriba en el centro para volver al lobby
	var btn_exit = hud.get_node_or_null("HousingExitButton")
	if not btn_exit:
		btn_exit = Button.new()
		btn_exit.name = "HousingExitButton"
		btn_exit.text = "🚪 Volver al Hangar / Lobby"
		btn_exit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		btn_exit.size = Vector2(250, 40)
		btn_exit.position = Vector2(-125, 20) # Centrado horizontalmente
		btn_exit.pressed.connect(func():
			NetworkManager.send_event("changeZone", 1)
		)
		hud.add_child(btn_exit)

func _exit_tree():
	# Limpieza de UI al salir de la zona
	_toggle_hud_elements_for_housing(true)
	
	# Desconectar señales de red para evitar que se cree la UI de housing tras salir
	if NetworkManager.socket_event_received.is_connected(_on_socket_event_received):
		NetworkManager.socket_event_received.disconnect(_on_socket_event_received)
		
	var world_node = get_tree().get_first_node_in_group("world_node")
	if world_node and is_instance_valid(world_node.ui_hud):
		var exit_btn = world_node.ui_hud.get_node_or_null("HousingExitButton")
		if is_instance_valid(exit_btn):
			exit_btn.queue_free()
		var housing_panel = world_node.ui_hud.get_node_or_null("HousingControlPanel")
		if is_instance_valid(housing_panel):
			housing_panel.queue_free()

func _toggle_hud_elements_for_housing(p_show: bool):
	var world_node = get_tree().get_first_node_in_group("world_node")
	if not world_node or not is_instance_valid(world_node.ui_hud): return
	
	var hud = world_node.ui_hud
	
	var radar = hud.get_node_or_null("RadarWindow")
	if is_instance_valid(radar):
		radar.visible = p_show
		
	var skills = hud.get_node_or_null("Skills")
	if is_instance_valid(skills):
		skills.visible = p_show
		
	var stats = hud.get_node_or_null("CenterStats")
	if is_instance_valid(stats):
		stats.visible = p_show
