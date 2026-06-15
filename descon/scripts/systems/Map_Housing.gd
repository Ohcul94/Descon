extends BaseMap

# Map_Housing.gd - Sistema de Housing 3D Basado en Grillas
# Cámara rotativa 3D, previsualización por mouse, colisiones, flotación en Y y modo edición interactivo.

const GRID_CELL_SIZE = 3.0 # Tamaño de cada celda en unidades 3D
var grid_size = 10 # Se actualiza con la configuración del servidor

var housing_unlocked = false
var placed_objects = [] # Lista de objetos colocados en local y sincronizados
var object_nodes = {} # { placement_id: Node3D }

# Estado de la Edición / Construcción
var is_edit_mode = false
var selected_item_type = "" # ID del catálogo, ej: 'chair', 'light'
var preview_node: Node3D = null
var current_preview_x = 0
var current_preview_z = 0
var current_preview_rot = 0 # 0, 90, 180, 270 grados
var moving_object_id = "" # ID del objeto que se está moviendo/editando en el mapa

# Modo Edición del Hangar (Diseño interactivo de lo ya puesto)
var is_editing_layout = false
var btn_edit_layout: Button = null

# Control de Cámara Orbit
var camera_angle_h = 45.0 # Ángulo horizontal (grados)
var camera_angle_v = 45.0 # Ángulo vertical (grados)
var camera_zoom = 25.0
const MIN_ZOOM = 10.0
const MAX_ZOOM = 50.0

var camera_center = Vector3.ZERO

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
	
	var half_grid = (grid_size * GRID_CELL_SIZE) / 2.0
	camera_center = Vector3(half_grid, 0.0, half_grid)
	
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
	
	# Asegurar que se muestren los botones del HUD inmediatamente
	_update_hud_buttons()

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
		
	_update_grid_visibility()

func _update_grid_visibility():
	if is_instance_valid(grid_lines_3d):
		grid_lines_3d.visible = (is_edit_mode or is_editing_layout)

func _process(delta):
	_update_grid_visibility()
	
	# Ocultar name_tag (vida, escudo, nombre) del player en la grilla del hangar
	var pl = get_tree().get_first_node_in_group("player")
	if pl and "name_tag" in pl and is_instance_valid(pl.name_tag):
		pl.name_tag.visible = false

	# Manejar el control rotativo 3D de la cámara
	_update_orbit_camera()
	
	# Tiempo de simulación para la flotación
	var time = Time.get_ticks_msec() / 1000.0
	
	# Efecto de balanceo flotante para objetos colocados en el mapa (simulando que vuelan)
	for id in object_nodes.keys():
		var node = object_nodes[id]
		if is_instance_valid(node):
			# Ocultar el original si lo estamos moviendo actualmente
			if moving_object_id == id:
				node.visible = false
			else:
				node.visible = true
				# Sube y baja flotante (1.5 unidades arriba de la grilla)
				node.position.y = 1.5 + sin(time * 2.2 + id.hash()) * 0.25
	
	# Actualizar posición, color y validez del preview en modo edición
	if is_edit_mode and is_instance_valid(preview_node):
		# Paneo/posicionamiento con el mouse proyectado en la grilla
		var mouse_pos = get_viewport().get_mouse_position()
		var grid_pos_3d = _project_mouse_to_grid(mouse_pos)
		
		# Calcular coordenadas de celda
		var cell_x = clamp(floor(grid_pos_3d.x / GRID_CELL_SIZE), 0, grid_size - 1)
		var cell_z = clamp(floor(grid_pos_3d.z / GRID_CELL_SIZE), 0, grid_size - 1)
		
		current_preview_x = int(cell_x)
		current_preview_z = int(cell_z)
		
		# Sube y baja flotante para el preview también
		var target_pos = Vector3(
			(current_preview_x * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0),
			1.5 + sin(time * 2.2) * 0.25,
			(current_preview_z * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0)
		)
		preview_node.position = preview_node.position.lerp(target_pos, delta * 25.0)
		preview_node.rotation.y = lerp_angle(preview_node.rotation.y, deg_to_rad(current_preview_rot), delta * 25.0)
		
		# Colisiones: si está ocupado (y no es el mismo objeto que estamos editando/moviendo), pintar de rojo
		var occupied = _is_cell_occupied(current_preview_x, current_preview_z)
		_apply_preview_color(preview_node, Color(1.0, 0.0, 0.0, 0.45) if occupied else Color(0.0, 1.0, 0.0, 0.45))

func _update_orbit_camera():
	if not is_instance_valid(camera_3d): return
	
	var rad_h = deg_to_rad(camera_angle_h)
	
	# Si no estamos en modo edición, permitir desplazarnos por la grilla usando WASD (Paneo)
	if not is_edit_mode:
		var move_speed = 25.0 * get_process_delta_time()
		# Vectores en el plano XZ alineados con la visual de la cámara
		var forward = Vector3(sin(rad_h), 0, cos(rad_h)).normalized()
		var right = Vector3(cos(rad_h), 0, -sin(rad_h)).normalized()
		
		if Input.is_key_pressed(KEY_W):
			camera_center -= forward * move_speed
		if Input.is_key_pressed(KEY_S):
			camera_center += forward * move_speed
		if Input.is_key_pressed(KEY_A):
			camera_center -= right * move_speed
		if Input.is_key_pressed(KEY_D):
			camera_center += right * move_speed
			
		# Limitar el paneo de la cámara al área de la grilla más un margen de 2 celdas de amortiguación
		var margin = GRID_CELL_SIZE * 2.0
		var max_limit = grid_size * GRID_CELL_SIZE
		camera_center.x = clamp(camera_center.x, -margin, max_limit + margin)
		camera_center.z = clamp(camera_center.z, -margin, max_limit + margin)
	
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

	rad_h = deg_to_rad(camera_angle_h)
	var rad_v = deg_to_rad(camera_angle_v)
	
	var offset = Vector3(
		camera_zoom * cos(rad_v) * sin(rad_h),
		camera_zoom * sin(rad_v),
		camera_zoom * cos(rad_v) * cos(rad_h)
	)
	
	camera_3d.position = camera_center + offset
	camera_3d.look_at(camera_center, Vector3.UP)
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
			1.5,
			(z * GRID_CELL_SIZE) + (GRID_CELL_SIZE / 2.0)
		)
		
		if not id in object_nodes:
			var node = _instance_3d_object(item_cfg, item_type)
			housing_root_3d.add_child(node)
			object_nodes[id] = node
			
		var instance = object_nodes[id]
		instance.position = target_pos
		instance.rotation.y = deg_to_rad(rot)

# Instanciar el GLB o generar un fallback estético
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
		# Escalado del modelo 3D según el tipo para un tamaño coherente en el mapa
		if "casa" in str(item_type):
			inst.scale = Vector3(6.0, 6.0, 6.0)
		else:
			inst.scale = Vector3(2.5, 2.5, 2.5)
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
		
		# Escalar el fallback en el mapa para tamaño coherente
		node.scale = Vector3(2.5, 2.5, 2.5)
		
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
	
	# Teñir preview en color verde traslúcido inicialmente
	_apply_preview_color(preview_node, Color(0.0, 1.0, 0.0, 0.45))
	
	if is_instance_valid(housing_root_3d):
		housing_root_3d.add_child(preview_node)
		
	current_preview_x = int(grid_size / 2.0)
	current_preview_z = int(grid_size / 2.0)
	current_preview_rot = 0
	
	_update_hud_buttons()

func _project_mouse_to_grid(mouse_pos: Vector2) -> Vector3:
	if not is_instance_valid(camera_3d): return Vector3.ZERO
	
	var from = camera_3d.project_ray_origin(mouse_pos)
	var dir = camera_3d.project_ray_normal(mouse_pos)
	
	if abs(dir.y) < 0.0001: return Vector3.ZERO
	var t = -from.y / dir.y
	if t < 0.0: return Vector3.ZERO
	
	return from + dir * t

func _is_cell_occupied(x: int, z: int) -> bool:
	for obj in placed_objects:
		# Si estamos moviendo este mismo objeto, no consideramos su propia celda como ocupada
		if moving_object_id != "" and obj.id == moving_object_id:
			continue
		if int(obj.x) == x and int(obj.z) == z:
			return true
	return false

func _apply_preview_color(node: Node, color: Color):
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override
			if not mat or not mat is StandardMaterial3D:
				mat = StandardMaterial3D.new()
				mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
				child.material_override = mat
			mat.albedo_color = color
		_apply_preview_color(child, color)

func _clear_preview():
	if moving_object_id != "" and object_nodes.has(moving_object_id):
		if is_instance_valid(object_nodes[moving_object_id]):
			object_nodes[moving_object_id].visible = true
	
	if is_instance_valid(preview_node):
		preview_node.queue_free()
		preview_node = null
	is_edit_mode = false
	moving_object_id = ""
	
	_update_hud_buttons()

func _input(event):
	# Evitar zoom si hay interfaces de usuario visibles que capturen la entrada
	var ui_nodes = get_tree().get_nodes_in_group("inventory_ui")
	for ui in ui_nodes:
		if ui.visible:
			return

	# Procesar Zoom del mouse de forma global en la zona de housing
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom = clamp(camera_zoom - 2.0, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom = clamp(camera_zoom + 2.0, MIN_ZOOM, MAX_ZOOM)

	# Selección interactiva de objetos instalados para mover (si el Modo Edición está activo en el HUD)
	if not is_edit_mode and is_editing_layout and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_viewport().get_mouse_position()
		var grid_pos_3d = _project_mouse_to_grid(mouse_pos)
		
		var cell_x = int(clamp(floor(grid_pos_3d.x / GRID_CELL_SIZE), 0, grid_size - 1))
		var cell_z = int(clamp(floor(grid_pos_3d.z / GRID_CELL_SIZE), 0, grid_size - 1))
		
		# Buscar si hay un objeto en esa celda para seleccionarlo y desplazarlo
		for obj in placed_objects:
			if int(obj.x) == cell_x and int(obj.z) == cell_z:
				moving_object_id = obj.id
				current_preview_rot = int(obj.get("rotation", 0))
				enter_edit_mode(obj.itemType)
				get_viewport().set_input_as_handled()
				break
		return

	if not is_edit_mode: return
	
	# Click izquierdo para posicionar/comprar objeto (solo si la celda no está ocupada)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _is_cell_occupied(current_preview_x, current_preview_z):
			_place_current_object()
			get_viewport().set_input_as_handled()

	# Click derecho para ELIMINAR el objeto o cancelar
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if moving_object_id != "":
			NetworkManager.send_event("removeHousingObject", {"id": moving_object_id})
			_clear_preview()
			get_viewport().set_input_as_handled()
		else:
			# Cancelar compra de item
			_clear_preview()
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R: # Rotar 90°
			current_preview_rot = (current_preview_rot + 90) % 360
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE: # Cancelar
			_clear_preview()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE: # Eliminar objeto seleccionado
			if moving_object_id != "":
				NetworkManager.send_event("removeHousingObject", {"id": moving_object_id})
				_clear_preview()
				get_viewport().set_input_as_handled()

func _place_current_object():
	if moving_object_id != "":
		# Enviar evento de actualización de posición al servidor
		var data = {
			"id": moving_object_id,
			"x": current_preview_x,
			"z": current_preview_z,
			"rotation": current_preview_rot
		}
		NetworkManager.send_event("moveHousingObject", data)
		moving_object_id = ""
		is_edit_mode = false
		if is_instance_valid(preview_node):
			preview_node.queue_free()
			preview_node = null
	else:
		# Enviar evento de colocación/compra al servidor
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
	
	# Remover botones viejos liberándolos de la escena inmediatamente
	var old_panel = hud.get_node_or_null("HousingControlPanel")
	if is_instance_valid(old_panel):
		hud.remove_child(old_panel)
		old_panel.queue_free()
		
	# Crear contenedor vertical para los botones y las instrucciones
	var menu_container = VBoxContainer.new()
	menu_container.name = "HousingControlPanel"
	menu_container.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_container.add_theme_constant_override("separation", 10)
	hud.add_child(menu_container)
	
	# Posicionar con anchors y offsets responsivos con mayor altura para albergar las instrucciones
	menu_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	menu_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu_container.size = Vector2(700, 95)
	menu_container.offset_left = -350
	menu_container.offset_right = 350
	menu_container.offset_top = 20
	menu_container.offset_bottom = 115
	
	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	menu_container.add_child(button_row)
		
	# Botón 1: Salir del Hangar
	var btn_exit = Button.new()
	btn_exit.name = "HousingExitButton"
	btn_exit.text = "🚪 Volver al Hangar / Lobby"
	btn_exit.custom_minimum_size = Vector2(250, 40)
	_apply_sci_fi_button_style(btn_exit, Color.RED)
	btn_exit.pressed.connect(func():
		NetworkManager.send_event("changeZone", 1)
	)
	button_row.add_child(btn_exit)
		
	# Botón 2: Modo Edición de Distribución
	btn_edit_layout = Button.new()
	btn_edit_layout.name = "HousingEditLayoutButton"
	btn_edit_layout.custom_minimum_size = Vector2(250, 40)
	_apply_sci_fi_button_style(btn_edit_layout, Color.CYAN)
	_update_edit_layout_button_style()
	btn_edit_layout.pressed.connect(func():
		is_editing_layout = !is_editing_layout
		if not is_editing_layout and is_edit_mode:
			_clear_preview()
		_update_edit_layout_button_style()
		_update_hud_buttons() # Actualizar HUD al alternar modo
	)
	button_row.add_child(btn_edit_layout)

	# Banner de instrucciones y atajos en modo de colocación/edición
	if is_edit_mode:
		var help_lbl = Label.new()
		if moving_object_id != "":
			help_lbl.text = "🔧 Moviendo Objeto:  [R] Rotar  |  [Clic Izq] Confirmar Posición  |  [Clic Der / Supr] ELIMINAR  |  [Esc] Cancelar"
		else:
			help_lbl.text = "🏗️ Colocando Objeto:  [R] Rotar  |  [Clic Izq] Construir  |  [Clic Der / Esc] Cancelar Adquisición"
		
		help_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		help_lbl.add_theme_color_override("font_color", Color.CYAN)
		help_lbl.add_theme_font_size_override("font_size", 11)
		
		# Estilo Sci-Fi semi-transparente para la barra de ayuda
		var sb_help = StyleBoxFlat.new()
		sb_help.bg_color = Color(0.0, 0.05, 0.1, 0.85)
		sb_help.border_width_left = 1; sb_help.border_width_top = 1
		sb_help.border_width_right = 1; sb_help.border_width_bottom = 1
		sb_help.border_color = Color.CYAN
		sb_help.set_corner_radius_all(5)
		sb_help.content_margin_top = 5
		sb_help.content_margin_bottom = 5
		help_lbl.add_theme_stylebox_override("normal", sb_help)
		
		menu_container.add_child(help_lbl)
	elif is_editing_layout:
		var help_lbl = Label.new()
		help_lbl.text = "🔧 Modo Edición Activado:  [Clic Izq] Seleccionar cualquier objeto del hangar para Moverlo o Eliminarlo"
		help_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		help_lbl.add_theme_color_override("font_color", Color.YELLOW)
		help_lbl.add_theme_font_size_override("font_size", 11)
		
		var sb_help = StyleBoxFlat.new()
		sb_help.bg_color = Color(0.05, 0.05, 0.0, 0.85)
		sb_help.border_width_left = 1; sb_help.border_width_top = 1
		sb_help.border_width_right = 1; sb_help.border_width_bottom = 1
		sb_help.border_color = Color.YELLOW
		sb_help.set_corner_radius_all(5)
		sb_help.content_margin_top = 5
		sb_help.content_margin_bottom = 5
		help_lbl.add_theme_stylebox_override("normal", sb_help)
		
		menu_container.add_child(help_lbl)

func _apply_sci_fi_button_style(btn: Button, border_color: Color):
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.01, 0.05, 0.1, 0.8)
	sb_normal.border_width_left = 2
	sb_normal.border_width_top = 2
	sb_normal.border_width_right = 2
	sb_normal.border_width_bottom = 2
	sb_normal.border_color = border_color
	sb_normal.set_corner_radius_all(6)
	
	var sb_hover = StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.02, 0.1, 0.2, 0.9)
	sb_hover.border_width_left = 2
	sb_hover.border_width_top = 2
	sb_hover.border_width_right = 2
	sb_hover.border_width_bottom = 2
	sb_hover.border_color = border_color.lightened(0.2)
	sb_hover.set_corner_radius_all(6)
	
	var sb_pressed = StyleBoxFlat.new()
	sb_pressed.bg_color = Color(0.0, 0.02, 0.05, 0.95)
	sb_pressed.border_width_left = 2
	sb_pressed.border_width_top = 2
	sb_pressed.border_width_right = 2
	sb_pressed.border_width_bottom = 2
	sb_pressed.border_color = border_color.darkened(0.2)
	sb_pressed.set_corner_radius_all(6)
	
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.CYAN)

func _update_edit_layout_button_style():
	if not is_instance_valid(btn_edit_layout): return
	if is_editing_layout:
		btn_edit_layout.text = "🔧 Modo Edición: ACTIVADO"
		btn_edit_layout.modulate = Color.CYAN
	else:
		btn_edit_layout.text = "🔧 Modo Edición: DESACTIVADO"
		btn_edit_layout.modulate = Color.WHITE

func _exit_tree():
	# Limpieza de UI al salir de la zona
	_toggle_hud_elements_for_housing(true)
	
	# Desconectar señales de red para evitar que se cree la UI de housing tras salir
	if NetworkManager.socket_event_received.is_connected(_on_socket_event_received):
		NetworkManager.socket_event_received.disconnect(_on_socket_event_received)
		
	# Volver a hacer visible el name_tag al salir del Hangar
	var pl = get_tree().get_first_node_in_group("player")
	if pl and "name_tag" in pl and is_instance_valid(pl.name_tag):
		pl.name_tag.visible = true

	var world_node = get_tree().get_first_node_in_group("world_node")
	if world_node and is_instance_valid(world_node.ui_hud):
		var control_panel = world_node.ui_hud.get_node_or_null("HousingControlPanel")
		if is_instance_valid(control_panel):
			control_panel.queue_free()

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
