@tool
extends Node3D
class_name MapEditor3D

## CONFIGURACIÓN
@export var scale_factor: float = 0.02
@export var correction_z: float = 1.41421356
@export var grid_cell_size: float = 50.0

@export_group("Sincronización con Servidor")
@export var zone_id: String = "1"
@export var confirm_overwrite_on_load: bool = false
@export var load_from_server_config: bool = false:
	set(val):
		if val:
			load_from_server()
			load_from_server_config = false
			notify_property_list_changed()
@export var save_to_server_config: bool = false:
	set(val):
		if val:
			save_to_server()
			save_to_server_config = false
			notify_property_list_changed()

@export_group("Importar Mapa Manual")
@export_multiline var json_to_import: String = ""
@export var trigger_import: bool = false:
	set(val):
		if val:
			import_from_json()
			trigger_import = false
			notify_property_list_changed()




## NODOS INTERNOS
@onready var objects_root: Node3D = %ObjectsRoot

## ESTADO DEL EDITOR
var _selected_object: Node3D = null
var _is_dragging: bool = false
var _drag_offset: Vector3 = Vector3.ZERO
var _snap_to_grid: bool = true
var _gizmo_mode: int = 0  # 0=move, 1=rotate, 2=scale
var _current_gizmo: Node3D = null

const OBJ_TYPES: Array[String] = ["wall", "door", "chest", "tower", "decor", "vault", "loot", "altar", "portal", "spawn", "custom"]

func _ready():
	if not Engine.is_editor_hint():
		queue_free()
		return
	
	_setup_editor_camera()
	_connect_editor_signals()
	print("MapEditor3D: Editor listo. Arrastra .glb a ObjectsRoot")

func _setup_editor_camera():
	var cam = get_node_or_null("Camera3D")
	if cam:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 35.0
		cam.position = Vector3(0, 40, 40)
		cam.rotation_degrees = Vector3(-45, 0, 0)
		cam.near = 0.1
		cam.far = 10000.0

func _connect_editor_signals():
	objects_root.child_entered_tree.connect(_on_child_added)
	objects_root.child_exiting_tree.connect(_on_child_removed)

func _on_child_added(child: Node):
	if child is MeshInstance3D or child is Node3D:
		_setup_object_metadata(child)
		child.set_meta("editor_only", true)

func _on_child_removed(child: Node):
	if child == _selected_object:
		_clear_selection()

func _setup_object_metadata(obj: Node3D):
	if not obj.has_meta("obj_type"):
		obj.set_meta("obj_type", "wall")
	if not obj.has_meta("asset_path"):
		if obj.scene_file_path != "":
			obj.set_meta("asset_path", obj.scene_file_path)
		elif obj is MeshInstance3D and obj.mesh:
			obj.set_meta("asset_path", obj.mesh.resource_path)
	if obj.name.contains("@"):
		var base_name = ""
		if obj.scene_file_path != "":
			base_name = obj.scene_file_path.get_file().get_basename()
		elif obj.has_meta("label"):
			base_name = obj.get_meta("label")
		else:
			base_name = obj.get_class()
		obj.name = base_name.replace(" ", "_").replace("@", "")
		
	if not obj.has_meta("label"):
		obj.set_meta("label", obj.name)
	if not obj.has_meta("scale_2d"):
		obj.set_meta("scale_2d", 1.0)
	if not obj.has_meta("rot_y_deg"):
		obj.set_meta("rot_y_deg", 0.0)

## INPUT DEL EDITOR

func _input(event: InputEvent):
	if not Engine.is_editor_hint():
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_left_click(event)
		else:
			_is_dragging = false
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_context_menu(event.position)
	
	if event is InputEventMouseMotion and _is_dragging and _selected_object:
		_drag_selected_object(event.position)
	
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G: _snap_to_grid = not _snap_to_grid
			KEY_W: _gizmo_mode = 0
			KEY_E: _gizmo_mode = 1
			KEY_R: _gizmo_mode = 2
			KEY_DELETE: _delete_selected()
			KEY_D:
				if event.ctrl_pressed:
					_duplicate_selected()
			KEY_C:
				if event.ctrl_pressed:
					_copy_to_json()

func _handle_left_click(event: InputEventMouseButton):
	var ray_result = _raycast_from_mouse(event.position)
	if ray_result:
		var hit_obj = ray_result.collider
		while hit_obj and hit_obj != objects_root:
			if hit_obj.get_parent() == objects_root:
				_select_object(hit_obj)
				_is_dragging = true
				_drag_offset = hit_obj.global_position - ray_result.position
				return
			hit_obj = hit_obj.get_parent()
	_clear_selection()

func _raycast_from_mouse(screen_pos: Vector2) -> Dictionary:
	var viewport = get_viewport()
	var camera = viewport.get_camera_3d()
	if not camera:
		return {}
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 10000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	
	if result:
		return { "position": result.position, "collider": result.collider }
	return {}

func _drag_selected_object(screen_pos: Vector2):
	var ray_result = _raycast_from_mouse(screen_pos)
	if not ray_result:
		return
	
	var target_pos = ray_result.position + _drag_offset
	
	if _snap_to_grid:
		target_pos = _snap_position_to_grid(target_pos)
	
	match _gizmo_mode:
		0:
			_selected_object.global_position = target_pos
		1:
			var dir = (target_pos - _selected_object.global_position).normalized()
			var angle = atan2(dir.x, dir.z)
			_selected_object.rotation.y = angle
			_selected_object.set_meta("rot_y_deg", rad_to_deg(angle))
		2:
			var dist = _selected_object.global_position.distance_to(target_pos)
			var new_scale = max(0.1, dist / 2.0)
			_selected_object.scale = Vector3.ONE * new_scale
			_selected_object.set_meta("scale_2d", new_scale)

func _snap_position_to_grid(pos: Vector3) -> Vector3:
	var cell_3d = grid_cell_size * scale_factor
	return Vector3(
		round(pos.x / cell_3d) * cell_3d,
		0.0,
		round(pos.z / cell_3d) * cell_3d
	)

func _clear_selection():
	_selected_object = null
	_is_dragging = false

func _select_object(obj: Node3D):
	_clear_selection()
	_selected_object = obj
	print("MapEditor3D: Seleccionado: " + obj.name + " | Tipo: " + obj.get_meta("obj_type", "wall"))

## ACCIONES

func _delete_selected():
	if _selected_object:
		print("MapEditor3D: Eliminado: " + _selected_object.name)
		_selected_object.queue_free()
		_clear_selection()

func _duplicate_selected():
	if _selected_object:
		var dup = _selected_object.duplicate()
		var clean_name = _selected_object.name.replace("@", "")
		dup.name = clean_name
		objects_root.add_child(dup)
		
		var scene_root = get_tree().edited_scene_root if Engine.is_editor_hint() else self
		if scene_root:
			dup.owner = scene_root
			for child in dup.get_children():
				child.owner = scene_root
				
		dup.global_position += Vector3(5, 0, 5)
		_setup_object_metadata(dup)
		_select_object(dup)

func _copy_to_json():
	_export_to_json()

func _show_context_menu(position: Vector2):
	var menu = PopupMenu.new()
	add_child(menu)
	menu.add_item("Añadir objeto (arrastrar .glb)", 1)
	menu.add_separator()
	menu.add_item("Cambiar tipo: wall", 10)
	menu.add_item("Cambiar tipo: door", 11)
	menu.add_item("Cambiar tipo: chest", 12)
	menu.add_item("Cambiar tipo: tower", 13)
	menu.add_item("Cambiar tipo: decor", 14)
	menu.add_item("Cambiar tipo: custom", 15)
	menu.add_separator()
	menu.add_item("Exportar JSON al portapapeles", 99)
	menu.id_pressed.connect(_on_context_menu_select)
	menu.popup(Rect2i(position.x, position.y, 0, 0))

func _on_context_menu_select(id: int):
	match id:
		10, 11, 12, 13, 14, 15:
			if _selected_object:
				var types = ["wall", "door", "chest", "tower", "decor", "custom"]
				var type_index = id - 10
				var new_type = types[type_index]
				_selected_object.set_meta("obj_type", new_type)
				_apply_default_properties_by_type(_selected_object, new_type)
				print("MapEditor3D: Tipo cambiado a: " + new_type)
		99:
			_export_to_json()

func _apply_default_properties_by_type(obj: Node3D, type: String):
	obj.set_meta("scale_2d", obj.scale.x)
	obj.set_meta("rot_y_deg", obj.rotation_degrees.y)

## EXPORTACIÓN JSON

func _export_to_json():
	var objects_array = []
	
	for child in objects_root.get_children():
		if child is Node3D and child.get_meta("editor_only", false):
			var obj_data = _node3d_to_config_dict(child)
			objects_array.append(obj_data)
	
	var json_text = JSON.stringify(objects_array, "\t")
	DisplayServer.clipboard_set(json_text)
	
	print("MapEditor3D: ✅ JSON exportado al portapapeles (" + str(objects_array.size()) + " objetos)")
	print("MapEditor3D: Pégalo en tu AdminDash → MAPS_CONFIG[\"1\"].objects = <pegar aquí>")
	
	print("\n--- COPIA DESDE AQUÍ ---")
	print(json_text)
	print("--- FIN ---\n")

func _node3d_to_config_dict(node: Node3D) -> Dictionary:
	var pos_3d = node.global_position
	var x_2d = pos_3d.x / scale_factor
	var y_2d = pos_3d.z / (scale_factor * correction_z)
	
	# Siempre usar el transform REAL del nodo (lo que el usuario ajustó con el gizmo)
	var rot_y_deg = rad_to_deg(node.rotation.y)
	var obj_type = node.get_meta("obj_type", "wall")
	
	var scale_2d = node.scale.x
	var asset_path = node.get_meta("asset_path", "")
	var label = node.get_meta("label", node.name)
	
	if asset_path == "":
		if node.scene_file_path != "":
			asset_path = node.scene_file_path
		elif node is MeshInstance3D and node.mesh:
			asset_path = node.mesh.resource_path
	
	return {
		"type": obj_type,
		"x": _round_decimals(x_2d, 2),
		"y": _round_decimals(y_2d, 2),
		"label": label,
		"assetPath": asset_path,
		"scale": _round_decimals(scale_2d, 2),
		"rotY": _round_decimals(rot_y_deg, 1)
	}

func _round_decimals(val: float, decimals: int = 2) -> float:
	var mult = pow(10, decimals)
	return round(val * mult) / mult

func export_json_manual():
	_export_to_json()

func import_from_json():
	if json_to_import.strip_edges() == "":
		print("MapEditor3D: JSON de importación vacío.")
		return
	
	var json = JSON.new()
	var error = json.parse(json_to_import)
	if error != OK:
		print("MapEditor3D: Error al parsear JSON: ", json.get_error_message())
		return
		
	var data = json.get_data()
	if not (data is Array):
		print("MapEditor3D: El JSON debe ser un Array de objetos.")
		return
		
	# Limpiar objetos anteriores
	if not objects_root:
		objects_root = %ObjectsRoot
	if not objects_root:
		objects_root = get_node_or_null("ObjectsRoot")
		
	if objects_root:
		for child in objects_root.get_children():
			child.queue_free()
	else:
		print("MapEditor3D: No se encontró el nodo ObjectsRoot.")
		return
		
	print("MapEditor3D: Importando ", data.size(), " objetos...")
	
	var scene_root = get_tree().edited_scene_root if Engine.is_editor_hint() else self
	
	for obj in data:
		if not (obj is Dictionary):
			continue
		var asset_path = obj.get("assetPath", "")
		if asset_path == "":
			if obj.get("type") == "door":
				asset_path = "res://assets/Puertas/3D/Puerta2/Puerta2.glb"
			elif obj.get("type") == "chest":
				asset_path = "res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb"
			else:
				asset_path = "res://assets/Paredes/Pared1/Pared1.glb"
				
		var scene = load(asset_path)
		if not scene:
			print("MapEditor3D: No se pudo cargar el archivo: ", asset_path)
			continue
			
		var instance = scene.instantiate()
		var label_val = str(obj.get("label", instance.name))
		instance.name = label_val.replace(" ", "_").replace("@", "")
		objects_root.add_child(instance)
		if scene_root:
			instance.owner = scene_root
		
		# Posición
		var x_2d = float(obj.get("x", 0.0))
		var y_2d = float(obj.get("y", 0.0))
		instance.global_position = Vector3(
			x_2d * scale_factor,
			0.0,
			y_2d * scale_factor * correction_z
		)
		
		# Rotación y Escala desde el JSON
		var rot_y = float(obj.get("rotY", 0.0))
		var scale_val = float(obj.get("scale", 1.0))
		
		instance.rotation_degrees = Vector3(0.0, rot_y, 0.0)
		instance.scale = Vector3.ONE * scale_val
		
		# Metadata
		instance.set_meta("editor_only", true)
		instance.set_meta("obj_type", obj.get("type", "wall"))
		instance.set_meta("label", obj.get("label", instance.name))
		instance.set_meta("asset_path", asset_path)
		instance.set_meta("scale_2d", scale_val)
		instance.set_meta("rot_y_deg", rot_y)
		
		if obj.has("targetZoneId"):
			instance.set_meta("targetZoneId", str(obj.get("targetZoneId")))
		if obj.has("targetX"):
			instance.set_meta("targetX", float(obj.get("targetX")))
		if obj.has("targetY"):
			instance.set_meta("targetY", float(obj.get("targetY")))
			
	print("MapEditor3D: ✅ Importación completada con éxito.")

func load_from_server():
	if not confirm_overwrite_on_load:
		print("\n⚠️ [MapEditor3D PREVENCIÓN DE PÉRDIDA DE DATOS] ⚠️")
		print("Para cargar los datos del servidor y reemplazar lo que tienes en el editor,")
		print("DEBES activar primero la casilla 'confirm_overwrite_on_load' en el Inspector.\n")
		return
		
	confirm_overwrite_on_load = false
	
	var file_path = "res://../Server/config.json"
	if not FileAccess.file_exists(file_path):
		print("MapEditor3D: No se encuentra Server/config.json en: ", file_path)
		return
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("MapEditor3D: Error al parsear config.json: ", json.get_error_message())
		return
		
	var config_dict = json.get_data()
	if not (config_dict is Dictionary) or not config_dict.has("mapsConfig"):
		print("MapEditor3D: Formato inválido en config.json (falta mapsConfig).")
		return
		
	var maps_config = config_dict["mapsConfig"]
	if not maps_config.has(zone_id):
		print("MapEditor3D: La zona ", zone_id, " no existe en mapsConfig.")
		return
		
	var map_data = maps_config[zone_id]
	var objects = map_data.get("objects", [])
	
	# Importar los objetos
	json_to_import = JSON.stringify(objects)
	import_from_json()
	
	# Actualizar el borde delimitador del mapa (Nebulosa morada translúcida)
	var width_val = float(map_data.get("width", 2000))
	var height_val = float(map_data.get("height", 2000))
	update_map_boundary(width_val, height_val)
	
	# Actualizar la textura y material de GroundPlane/GridVisual para que coincida con el Hangar/Lobby
	var grid_visual = get_node_or_null("GroundPlane/GridVisual")
	if is_instance_valid(grid_visual) and grid_visual is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.08, 0.15, 1)
		mat.metallic = 0.3
		mat.roughness = 0.8
		grid_visual.material_override = mat
	
	print("MapEditor3D: ✅ Cargado mapa de la Zona ", zone_id, " (", map_data.get("name", "Sin Nombre"), ") desde el servidor. Tamaño: ", width_val, "x", height_val)

func update_map_boundary(width_2d: float, height_2d: float):
	var old_b = get_node_or_null("MapBoundaryVisual")
	if is_instance_valid(old_b):
		old_b.free()
		
	var boundary_visual = Node3D.new()
	boundary_visual.name = "MapBoundaryVisual"
	add_child(boundary_visual)
		
	var w_3d = width_2d * scale_factor
	var h_3d = height_2d * scale_factor * correction_z
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.1, 0.8, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.1, 0.7)
	mat.emission_energy_multiplier = 1.2
	
	# 4 Paredes translúcidas para encerrar los límites exactos del mapa
	_create_boundary_wall(boundary_visual, Vector3(w_3d, 10.0, 0.2), Vector3(w_3d / 2.0, 5.0, 0.0), mat)
	_create_boundary_wall(boundary_visual, Vector3(w_3d, 10.0, 0.2), Vector3(w_3d / 2.0, 5.0, h_3d), mat)
	_create_boundary_wall(boundary_visual, Vector3(0.2, 10.0, h_3d), Vector3(0.0, 5.0, h_3d / 2.0), mat)
	_create_boundary_wall(boundary_visual, Vector3(0.2, 10.0, h_3d), Vector3(w_3d, 5.0, h_3d / 2.0), mat)

func _create_boundary_wall(parent: Node3D, box_size: Vector3, pos: Vector3, mat: Material):
	var box = BoxMesh.new()
	box.size = box_size
	var mi = MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func save_to_server():
	var file_path = "res://../Server/config.json"
	if not FileAccess.file_exists(file_path):
		print("MapEditor3D: No se encuentra Server/config.json en: ", file_path)
		return
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("MapEditor3D: Error al parsear config.json: ", json.get_error_message())
		return
		
	var config_dict = json.get_data()
	if not (config_dict is Dictionary) or not config_dict.has("mapsConfig"):
		print("MapEditor3D: Formato inválido en config.json.")
		return
		
	var maps_config = config_dict["mapsConfig"]
	if not maps_config.has(zone_id):
		print("MapEditor3D: La zona ", zone_id, " no existe en mapsConfig.")
		return
		
	# Advertencia sobre nodos colocados fuera de ObjectsRoot
	var default_nodes = ["Camera3D", "GroundPlane", "DirectionalLight3D", "WorldEnvironment", "ObjectsRoot", "MapBoundaryVisual"]
	for child in get_children():
		if child is Node3D and not child.name in default_nodes:
			print("\n⚠️ [MapEditor3D ADVERTENCIA] ⚠️")
			print("El objeto '" + child.name + "' está fuera de ObjectsRoot.")
			print("Para que se guarde en config.json y aparezca en el juego, DEBES arrastrarlo dentro de 'ObjectsRoot' en el árbol de escenas.\n")

	# Generar el array de objetos actual
	var objects_array = []
	if not objects_root:
		objects_root = %ObjectsRoot
	if not objects_root:
		objects_root = get_node_or_null("ObjectsRoot")
		
	if objects_root:
		for child in objects_root.get_children():
			if child is Node3D and child.get_meta("editor_only", false):
				var obj_data = _node3d_to_config_dict(child)
				objects_array.append(obj_data)
				
	# Reemplazar en la configuración
	maps_config[zone_id]["objects"] = objects_array
	
	# Escribir de vuelta a config.json de forma bonita (4 espacios de indentación)
	var new_content = JSON.stringify(config_dict, "    ")
	var write_file = FileAccess.open(file_path, FileAccess.WRITE)
	if write_file:
		write_file.store_string(new_content)
		write_file.close()
		print("MapEditor3D: ✅ Guardado mapa de la Zona ", zone_id, " (", maps_config[zone_id].get("name", "Sin Nombre"), ") en Server/config.json.")
	else:
		print("MapEditor3D: Error al abrir config.json para escribir.")
