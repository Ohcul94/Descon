@tool
extends Node3D
class_name MapEditor3D

## CONFIGURACIÓN
@export var scale_factor: float = 0.02
@export var correction_z: float = 1.41421356
@export var grid_cell_size: float = 50.0

@export_group("Sincronización con Servidor")
@export var zone_id: String = "1"


@export_group("Importar Mapa Manual")
@export_multiline var json_to_import: String = ""
@export var trigger_import: bool = false:
	set(val):
		if val:
			import_from_json()
			trigger_import = false
			notify_property_list_changed()




## NODOS INTERNOS
var objects_root: Node3D = null

## ESTADO DEL EDITOR
var _selected_object: Node3D = null
var _is_dragging: bool = false
var _drag_offset: Vector3 = Vector3.ZERO
var _snap_to_grid: bool = true
var _gizmo_mode: int = 0  # 0=move, 1=rotate, 2=scale
# var _current_gizmo: Node3D = null
var _auto_loading: bool = false

const OBJ_TYPES: Array[String] = ["wall", "door", "chest", "tower", "decor", "vault", "loot", "altar", "portal", "spawn", "nexus", "pillar", "market", "custom"]

func _ready():
	if not Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return
	_setup_editor_camera()
	_connect_editor_signals()
	
	# v700.4: Carga y sincronización diferida automática al abrir la escena en el editor
	_auto_loading = true
	call_deferred("load_from_server")
	print("MapEditor3D: Editor listo. Carga automática del servidor completada de forma transparente.")


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
	var target = objects_root if is_instance_valid(objects_root) else self
	if is_instance_valid(target):
		if not target.child_entered_tree.is_connected(_on_child_added):
			target.child_entered_tree.connect(_on_child_added)
		if not target.child_exiting_tree.is_connected(_on_child_removed):
			target.child_exiting_tree.connect(_on_child_removed)

func _on_child_added(child: Node):
	if not is_instance_valid(child) or not (child is Node3D or child is MeshInstance3D):
		return
		
	# v700.6: Ignorar de forma segura nodos de infraestructura del sistema
	if child.name in ["Camera3D", "GroundPlane", "DirectionalLight3D", "WorldEnvironment", "ObjectsRoot", "MapBoundaryVisual", "EventMarkers", "Terrain3D", "SkyDome"]:
		return
		
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
		obj.name = _unique_node_name(obj.get_parent(), base_name.replace(" ", "_").replace("@", ""))
		
	if not obj.has_meta("label"):
		obj.set_meta("label", obj.name)
	if not obj.has_meta("scale_2d"):
		obj.set_meta("scale_2d", 1.0)
	if not obj.has_meta("rot_y_deg"):
		obj.set_meta("rot_y_deg", 0.0)

func _unique_node_name(parent: Node, desired: String) -> String:
	if not parent:
		return desired
	var taken := {}
	for c in parent.get_children():
		if c is Node:
			taken[c.name] = true
	if not taken.has(desired):
		return desired
	var i := 2
	while taken.has("%s_%d" % [desired, i]):
		i += 1
	return "%s_%d" % [desired, i]

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
		var clean_name = _unique_node_name(objects_root, _selected_object.name.replace("@", ""))
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

func _show_context_menu(p_position: Vector2):
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
	menu.add_item("Cambiar tipo: altar", 16)
	menu.add_item("Cambiar tipo: spawn", 17)
	menu.add_item("Cambiar tipo: market", 18)
	menu.add_separator()
	menu.add_item("Exportar JSON al portapapeles", 99)
	menu.id_pressed.connect(_on_context_menu_select)
	menu.popup(Rect2i(int(p_position.x), int(p_position.y), 0, 0))

func _on_context_menu_select(id: int):
	match id:
		10, 11, 12, 13, 14, 15, 16, 17, 18:
			if _selected_object:
				var types = ["wall", "door", "chest", "tower", "decor", "custom", "altar", "spawn", "market"]
				var type_index = id - 10
				var new_type = types[type_index]
				_selected_object.set_meta("obj_type", new_type)
				_apply_default_properties_by_type(_selected_object, new_type)
				print("MapEditor3D: Tipo cambiado a: " + new_type)
		99:
			_export_to_json()

func _apply_default_properties_by_type(obj: Node3D, _type: String):
	obj.set_meta("scale_2d", obj.scale.x)
	obj.set_meta("rot_y_deg", obj.rotation_degrees.y)

## EXPORTACIÓN JSON

func _export_to_json():
	var objects_array = []
	
	var stack = []
	for child in objects_root.get_children():
		stack.append(child)
		
	while stack.size() > 0:
		var curr = stack.pop_back()
		if curr is Node3D and curr.get_meta("editor_only", false):
			var obj_data = _node3d_to_config_dict(curr)
			objects_array.append(obj_data)
		else:
			for sub in curr.get_children():
				stack.append(sub)
	
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
	
	var config = {
		"type": obj_type,
		"x": _round_decimals(x_2d, 2),
		"y": _round_decimals(y_2d, 2),
		"yOffset": _round_decimals(pos_3d.y, 3),
		"label": label,
		"assetPath": asset_path,
		"scale": _round_decimals(scale_2d, 2),
		"rotY": _round_decimals(rot_y_deg, 1)
	}
	
	if node.has_meta("colType"): config["colType"] = node.get_meta("colType")
	if node.has_meta("colWidth"): config["colWidth"] = node.get_meta("colWidth")
	if node.has_meta("colHeight"): config["colHeight"] = node.get_meta("colHeight")
	if node.has_meta("colOffsetX"): config["colOffsetX"] = node.get_meta("colOffsetX")
	if node.has_meta("colOffsetY"): config["colOffsetY"] = node.get_meta("colOffsetY")
	if node.has_meta("colRot"): config["colRot"] = node.get_meta("colRot")
	if node.has_meta("radius"): config["radius"] = node.get_meta("radius")
	if node.has_meta("targetZoneId"): config["targetZoneId"] = node.get_meta("targetZoneId")
	if node.has_meta("targetX"): config["targetX"] = node.get_meta("targetX")
	if node.has_meta("targetY"): config["targetY"] = node.get_meta("targetY")
	if node.has_meta("team"): config["team"] = node.get_meta("team")
	if node.has_meta("ammoType"): config["ammoType"] = node.get_meta("ammoType")
	if node.has_meta("attackType"): config["attackType"] = node.get_meta("attackType")
	if node.has_meta("damage"): config["damage"] = node.get_meta("damage")
	if node.has_meta("hp"): config["hp"] = node.get_meta("hp")
	if node.has_meta("shield"): config["shield"] = node.get_meta("shield")
	if node.has_meta("range"): config["range"] = node.get_meta("range")


	
	# Buscar todos los colisionadores visuales como nodos hijos
	var colliders_array = []
	for child in node.get_children():
		if child.name.to_lower().contains("collider") or child is CSGBox3D or child is CollisionShape3D or child.get_class() == "CollisionPolygon3D" or child is CollisionPolygon3D:
			var c_type = "rect"
			var w_3d = child.scale.x
			var h_3d = child.scale.z
			
			if child.name.to_lower().contains("circle") or child is CSGCylinder3D:
				c_type = "circle"
				if child is CSGCylinder3D:
					w_3d = child.radius * 2.0 * child.scale.x
					h_3d = w_3d
			elif child is CollisionShape3D:
				if child.shape is CylinderShape3D or child.shape is SphereShape3D:
					c_type = "circle"
					w_3d = child.shape.radius * 2.0 * child.scale.x
					h_3d = w_3d
				elif child.shape is BoxShape3D:
					w_3d = child.shape.size.x * child.scale.x
					h_3d = child.shape.size.z * child.scale.z
			elif child is CSGBox3D:
				w_3d = child.size.x * child.scale.x
				h_3d = child.size.z * child.scale.z
				
			var c_data = {
				"type": c_type,
				"width": _round_decimals(w_3d / scale_factor, 2),
				"height": _round_decimals(h_3d / (scale_factor * correction_z), 2),
				"offsetX": _round_decimals(child.position.x / scale_factor, 2),
				"offsetY": _round_decimals(child.position.z / (scale_factor * correction_z), 2)
			}
			if child.rotation_degrees.y != 0.0:
				c_data["rot"] = _round_decimals(child.rotation_degrees.y, 1)
			colliders_array.append(c_data)
			
	if colliders_array.size() > 0:
		config["colliders"] = colliders_array
		# Para compatibilidad, llenar campos raíz con el primero
		config["colType"] = colliders_array[0]["type"]
		config["colWidth"] = colliders_array[0]["width"]
		config["colHeight"] = colliders_array[0]["height"]
		config["colOffsetX"] = colliders_array[0]["offsetX"]
		config["colOffsetY"] = colliders_array[0]["offsetY"]
		if colliders_array[0].has("rot"):
			config["colRot"] = colliders_array[0]["rot"]
	elif node is CSGBox3D and not config.has("colWidth"):
		# Si el nodo en sí es un colisionador (CSGBox3D) standalone (ej. paredes invisibles en carpeta Colliders)
		var w_3d = node.size.x * node.scale.x
		var h_3d = node.size.z * node.scale.z
		config["colType"] = "rect"
		config["colWidth"] = _round_decimals(w_3d / scale_factor, 2)
		config["colHeight"] = _round_decimals(h_3d / (scale_factor * correction_z), 2)
		config["colOffsetX"] = 0.0
		config["colOffsetY"] = 0.0
	elif node is CSGCylinder3D and not config.has("colWidth"):
		# v700.7: Soporte standalone para CSGCylinder3D (círculo perfecto) - misma lógica que CSGBox pero circular
		var diam_3d = node.radius * 2.0 * node.scale.x
		# Usar escala promedio X/Z si es no uniforme, pero mantener compatible con export previo (scale.x)
		var diam_w = diam_3d / scale_factor
		config["colType"] = "circle"
		config["colWidth"] = _round_decimals(diam_w, 2)
		config["colHeight"] = _round_decimals(diam_w, 2)
		config["colOffsetX"] = 0.0
		config["colOffsetY"] = 0.0
			
	return config

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
		
	# v700.5: Limpiar únicamente los objetos editables anteriores (con metadata editor_only)
	# para no borrar la cámara, luces, terreno u otra infraestructura de escena.
	if not objects_root:
		objects_root = find_child("ObjectsRoot", true, false)
		
	if objects_root:
		for child in objects_root.get_children():
			objects_root.remove_child(child)
			child.queue_free()
	else:
		# Si no hay ObjectsRoot, limpiar los objetos con editor_only directamente hijos de self
		for child in get_children():
			if child is Node3D and child.get_meta("editor_only", false):
				remove_child(child)
				child.queue_free()
		
	print("MapEditor3D: Importando ", data.size(), " objetos...")
	
	var scene_root = get_tree().edited_scene_root if Engine.is_editor_hint() else self
	var target_parent = objects_root if is_instance_valid(objects_root) else self
	
	for obj in data:
		if not (obj is Dictionary):
			continue
		var asset_path = obj.get("assetPath", "")
		if asset_path == "":
			if obj.get("type") == "door":
				asset_path = "res://assets/Puertas/3D/Puerta2/Puerta2.glb"
			elif obj.get("type") == "chest":
				asset_path = "res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb"
			elif obj.get("type") == "altar":
				asset_path = "res://assets/Altares/3D/Altar1/Altar1.glb"
			elif obj.get("type") == "spawn":
				asset_path = "res://assets/Puertas/3D/Puerta2/Puerta2.glb" # marcador visual de spawn
			elif obj.get("type") == "nexus":
				asset_path = "res://assets/Altares/3D/Altar1/Altar1.glb"
			elif obj.get("type") == "pillar":
				asset_path = "res://assets/Pilares/3D/Pilar1/Pilar1.glb"
			else:
				asset_path = "res://assets/Mapas/Mapa1/Paredes/Pared1/Pared1.glb"

				
		var scene = load(asset_path)
		if not scene:
			print("MapEditor3D: No se pudo cargar el archivo: ", asset_path)
			continue
			
		var instance = scene.instantiate()
		var base_name = str(obj.get("label", instance.name)).replace(" ", "_").replace("@", "")
		instance.name = _unique_node_name(target_parent, base_name)
		target_parent.add_child(instance)
		if scene_root:
			instance.owner = scene_root
		
		# Posición
		var x_2d = float(obj.get("x", 0.0))
		var y_2d = float(obj.get("y", 0.0))
		var type_str = obj.get("type", "wall")
		var default_y = 0.5
		if type_str in ["door", "tower"]:
			default_y = 2.5
		elif type_str == "chest":
			default_y = 0.0
		
		var y_offset = float(obj.get("yOffset", default_y))
		instance.global_position = Vector3(
			x_2d * scale_factor,
			y_offset,
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
		
		if obj.has("colType"): instance.set_meta("colType", obj.colType)
		if obj.has("colWidth"): instance.set_meta("colWidth", float(obj.colWidth))
		if obj.has("colHeight"): instance.set_meta("colHeight", float(obj.colHeight))
		if obj.has("colOffsetX"): instance.set_meta("colOffsetX", float(obj.colOffsetX))
		if obj.has("colOffsetY"): instance.set_meta("colOffsetY", float(obj.colOffsetY))
		if obj.has("colRot"): instance.set_meta("colRot", float(obj.colRot))
		
		# Crear nodos hijos visuales temporales en el editor para que el usuario pueda editarlos con gizmos
		if obj.has("colliders"):
			var idx = 1
			for c_obj in obj.colliders:
				var c_type = str(c_obj.type)
				var c_width = float(c_obj.get("width", 100.0))
				var c_height = float(c_obj.get("height", 20.0))
				var c_off_x = float(c_obj.get("offsetX", 0.0))
				var c_off_y = float(c_obj.get("offsetY", 0.0))
				var c_rot = float(c_obj.get("rot", 0.0))
				
				var h_visual = 0.2 / scale_val # Altura fija visual en el editor de 0.2 unidades
				
				var col_helper = null
				if c_type == "circle":
					col_helper = CSGCylinder3D.new()
					col_helper.name = "ColliderCircle" + str(idx)
					col_helper.radius = (c_width * scale_factor) / 2.0
					col_helper.height = h_visual
				else:
					col_helper = CSGBox3D.new()
					col_helper.name = "Collider" + str(idx)
					col_helper.size = Vector3(c_width * scale_factor, h_visual, c_height * scale_factor * correction_z)
					
				var mat = StandardMaterial3D.new()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color = Color(0.0, 0.8, 0.0, 0.3) # Verde translúcido
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				col_helper.material = mat
				
				col_helper.position = Vector3(c_off_x * scale_factor, h_visual / 2.0, c_off_y * scale_factor * correction_z)
				col_helper.rotation_degrees = Vector3(0, c_rot, 0)
				instance.add_child(col_helper)
				if scene_root:
					col_helper.owner = scene_root
				idx += 1
		elif obj.has("colType"):
			var c_type = str(obj.colType)
			var c_width = float(obj.get("colWidth", 100.0))
			var c_height = float(obj.get("colHeight", 20.0))
			var c_off_x = float(obj.get("colOffsetX", 0.0))
			var c_off_y = float(obj.get("colOffsetY", 0.0))
			var c_rot = float(obj.get("colRot", 0.0))
			
			var h_visual = 0.2 / scale_val # Altura fija visual en el editor de 0.2 unidades
			
			var col_helper = null
			if c_type == "circle":
				col_helper = CSGCylinder3D.new()
				col_helper.name = "ColliderCircle"
				col_helper.radius = (c_width * scale_factor) / 2.0
				col_helper.height = h_visual
			else:
				col_helper = CSGBox3D.new()
				col_helper.name = "Collider"
				col_helper.size = Vector3(c_width * scale_factor, h_visual, c_height * scale_factor * correction_z)
				
			var mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.0, 0.8, 0.0, 0.3) # Verde translúcido
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			col_helper.material = mat
			
			col_helper.position = Vector3(c_off_x * scale_factor, h_visual / 2.0, c_off_y * scale_factor * correction_z)
			col_helper.rotation_degrees = Vector3(0, c_rot, 0)
			instance.add_child(col_helper)
			if scene_root:
				col_helper.owner = scene_root
		
		if obj.has("radius"):
			instance.set_meta("radius", float(obj.get("radius")))
		if obj.has("targetZoneId"):
			instance.set_meta("targetZoneId", str(obj.get("targetZoneId")))
		if obj.has("targetX"):
			instance.set_meta("targetX", float(obj.get("targetX")))
		if obj.has("targetY"):
			instance.set_meta("targetY", float(obj.get("targetY")))
		if obj.has("team"):
			instance.set_meta("team", str(obj.get("team")))
		if obj.has("ammoType"):
			instance.set_meta("ammoType", str(obj.get("ammoType")))
		if obj.has("attackType"):
			instance.set_meta("attackType", str(obj.get("attackType")))
		if obj.has("damage"):
			instance.set_meta("damage", float(obj.get("damage")))
		if obj.has("hp"):
			instance.set_meta("hp", float(obj.get("hp")))
		if obj.has("shield"):
			instance.set_meta("shield", float(obj.get("shield")))
		if obj.has("range"):
			instance.set_meta("range", float(obj.get("range")))


			
	print("MapEditor3D: ✅ Importación completada con éxito.")

func load_from_server():
	_clear_event_markers()
	
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

	# Dimensiones: leer primero del gameMode si es zona de evento
	var zone_id_int = int(zone_id)
	var width_val = 0.0
	var height_val = 0.0

	# Leer configuraciones de gameModes
	var ext_cfg = config_dict.get("gameModes", {}).get("extraction", {})
	var ext_maps = ext_cfg.get("maps", [])
	var ad_cfg = config_dict.get("gameModes", {}).get("altar_defense", {})
	var ad_maps = ad_cfg.get("maps", [])

	# Comparación tipo-segura: JSON puede parsear los IDs como float (10.0) en vez de int (10)
	var is_extraction_zone = false
	for _m in ext_maps:
		if int(_m) == zone_id_int:
			is_extraction_zone = true
			break

	var is_altar_zone = false
	for _m in ad_maps:
		if int(_m) == zone_id_int:
			is_altar_zone = true
			break

	var arena_cfg = config_dict.get("gameModes", {}).get("arenas", {})
	var arena_maps = arena_cfg.get("maps", [])
	var is_arena_zone = false
	for _m in arena_maps:
		if int(_m) == zone_id_int:
			is_arena_zone = true
			break

	print("MapEditor3D: [DEBUG] zona=", zone_id, " is_extraction=", is_extraction_zone, " is_altar=", is_altar_zone, " is_arena=", is_arena_zone)



	# ─── ZONA NORMAL: importar mapsConfig.objects directamente ────────────
	if not is_extraction_zone and not is_altar_zone:
		json_to_import = JSON.stringify(objects)
		import_from_json()

	# ─── ZONA DE EXTRACCIÓN ───────────────────────────────────────────────
	if is_extraction_zone:
		width_val  = float(ext_cfg.get("width",  0))
		height_val = float(ext_cfg.get("height", 0))
		set_meta("extraction_config", {
			"extractPoints": ext_cfg.get("extractPoints", []),
			"spawnPoints":   ext_cfg.get("spawnPoints",   []),
			"spawners":      ext_cfg.get("spawners",      []),
			"countdownTime": ext_cfg.get("countdownTime", 600000),
			"extractRadius": ext_cfg.get("extractRadius", 150),
			"spawnLockTime": ext_cfg.get("spawnLockTime", 10000)
		})
		_spawn_extraction_markers(ext_cfg)

		if objects.size() > 0:
			# Ya tiene objects guardados desde el editor, usarlos directamente
			json_to_import = JSON.stringify(objects)
			import_from_json()
			print("MapEditor3D: ✅ Objects de extracción cargados desde mapsConfig (", objects.size(), " obj).")
		else:
			# Primera vez: generar puertas desde extractPoints como objetos 3D editables
			var generated_objects = []
			var extract_pts    = ext_cfg.get("extractPoints", [])
			var default_radius = float(ext_cfg.get("extractRadius", 150))
			for ep in extract_pts:
				generated_objects.append({
					"type":         "door",
					"x":            float(ep.get("x", 0)),
					"y":            float(ep.get("y", 0)),
					"yOffset":      0.0,
					"label":        str(ep.get("label", "Punto")),
					"scale":        10.0,
					"rotY":         -90.0,
					"radius":       float(ep.get("proximityRadius", default_radius)),
					"targetZoneId": str(ep.get("targetZone", "1"))
				})
			if generated_objects.size() > 0:
				print("MapEditor3D: ℹ️ objects vacío. Importando ", generated_objects.size(), " extractPoints como puertas 3D editables...")
				json_to_import = JSON.stringify(generated_objects)
				import_from_json()
				print("MapEditor3D: ✅ Puertas importadas. Movelasen 3D y guardá con 'Save to Server'.")
			else:
				print("MapEditor3D: ⚠️ La zona de extracción no tiene extractPoints en el config.")

	# ─── ZONA DE DEFENSA DE ALTAR ─────────────────────────────────────────
	if is_altar_zone:
		if width_val  <= 0: width_val  = float(ad_cfg.get("width",  0))
		if height_val <= 0: height_val = float(ad_cfg.get("height", 0))
		set_meta("altar_defense_config", {
			"altarPos":     ad_cfg.get("altarPos",     {}),
			"spawnPoints":  ad_cfg.get("spawnPoints",  []),
			"spawners":     ad_cfg.get("spawners",     []),
			"exitPortals":  ad_cfg.get("exitPortals",  []),
			"waves":        ad_cfg.get("waves",        []),
			"altarHp":      ad_cfg.get("altarHp",      10000),
			"altarShield":  ad_cfg.get("altarShield",  5000),
			"waveInterval": ad_cfg.get("waveInterval", 30000),
			"spawnLockTime":ad_cfg.get("spawnLockTime",10000)
		})
		_spawn_altar_defense_markers(ad_cfg)

		if objects.size() > 0:
			json_to_import = JSON.stringify(objects)
			import_from_json()
			print("MapEditor3D: ✅ Objects de altar cargados desde mapsConfig (", objects.size(), " obj).")
		else:
			var generated_objects = []
			var altar_pos    = ad_cfg.get("altarPos", {})
			var exit_portals = ad_cfg.get("exitPortals", [])
			if altar_pos.has("x") and altar_pos.has("y"):
				generated_objects.append({
					"type": "altar", "x": float(altar_pos.x), "y": float(altar_pos.y),
					"yOffset": 0.0, "label": "Altar", "scale": 15.0, "rotY": 180.0
				})
			for ep in exit_portals:
				generated_objects.append({
					"type": "door",
					"x": float(ep.get("x", 0)), "y": float(ep.get("y", 0)),
					"yOffset": 0.0, "label": str(ep.get("label", "Escape")),
					"scale": 10.0, "rotY": -90.0,
					"radius": float(ep.get("radius", 150))
				})
			if generated_objects.size() > 0:
				print("MapEditor3D: ℹ️ objects vacío. Importando altar + ", exit_portals.size(), " portales como objetos 3D editables...")
				json_to_import = JSON.stringify(generated_objects)
				import_from_json()
				print("MapEditor3D: ✅ Altar y portales importados. Editalos y guardá con 'Save to Server'.")
			else:
				print("MapEditor3D: ⚠️ Altar defense sin altarPos ni exitPortals en config.")

	# ─── ZONA DE ARENA PVP ────────────────────────────────────────────────
	if is_arena_zone:
		var arena_map_cfg = arena_cfg.get("mapConfigs", {}).get(zone_id, {})
		width_val  = float(arena_map_cfg.get("width", 10000))
		height_val = float(arena_map_cfg.get("height", 10000))
		
		set_meta("arena_config", arena_map_cfg)

		if objects.size() > 0:
			json_to_import = JSON.stringify(objects)
			import_from_json()
			print("MapEditor3D: ✅ Objects de arena PVP cargados desde mapsConfig (", objects.size(), " obj).")
		else:
			var generated_objects = []
			
			# Nexo Rojo
			var nexus_red = arena_map_cfg.get("nexusRed", {})
			if nexus_red.has("x") and nexus_red.has("y"):
				generated_objects.append({
					"type": "nexus", "x": float(nexus_red.x), "y": float(nexus_red.y),
					"yOffset": 0.0, "label": "Nexus Red", "scale": 20.0, "rotY": 0.0, "team": "red",
					"hp": float(nexus_red.get("hp", 10000)), "shield": float(nexus_red.get("shield", 5000))
				})
			
			# Nexo Azul
			var nexus_blue = arena_map_cfg.get("nexusBlue", {})
			if nexus_blue.has("x") and nexus_blue.has("y"):
				generated_objects.append({
					"type": "nexus", "x": float(nexus_blue.x), "y": float(nexus_blue.y),
					"yOffset": 0.0, "label": "Nexus Blue", "scale": 20.0, "rotY": 180.0, "team": "blue",
					"hp": float(nexus_blue.get("hp", 10000)), "shield": float(nexus_blue.get("shield", 5000))
				})
			
			# Pilares
			var pillars = arena_map_cfg.get("pillars", [])
			for i in range(pillars.size()):
				var p = pillars[i]
				generated_objects.append({
					"type": "pillar", "x": float(p.get("x", 0)), "y": float(p.get("y", 0)),
					"yOffset": 0.0, "label": str(p.get("name", "Pilar_" + str(i+1))),
					"scale": 12.0, "rotY": 0.0, "team": str(p.get("team", "neutral")),
					"hp": float(p.get("hp", 3000)), "shield": float(p.get("shield", 1500)),
					"range": float(p.get("range", 600)), "ammoType": str(p.get("ammoType", "laser")),
					"attackType": str(p.get("attackType", "fast")), "damage": float(p.get("damage", 150))
				})

			# Spawns
			var spawns = arena_map_cfg.get("spawns", [])
			for i in range(spawns.size()):
				var sp = spawns[i]
				generated_objects.append({
					"type": "spawn", "x": float(sp.get("x", 0)), "y": float(sp.get("y", 0)),
					"yOffset": 0.0, "label": str(sp.get("name", "Spawn_" + str(i+1))),
					"scale": 10.0, "rotY": 0.0, "team": str(sp.get("team", "red")),
					"radius": float(sp.get("radius", 200))
				})

			if generated_objects.size() > 0:
				print("MapEditor3D: ℹ️ objects vacío. Importando nexos, spawns y pilares como objetos editables...")
				json_to_import = JSON.stringify(generated_objects)
				import_from_json()
				print("MapEditor3D: ✅ Nexos, pilares y spawns importados en 3D. Editalos y guardá con 'Save to Server'.")
			else:
				print("MapEditor3D: ⚠️ La arena PVP no tiene configuración en gameModes.")




	# Fallback de dimensiones si no se llenaron desde gameMode
	if width_val  <= 0: width_val  = float(map_data.get("width",  0))
	if height_val <= 0: height_val = float(map_data.get("height", 0))
	if width_val  <= 0: width_val  = 10000
	if height_val <= 0: height_val = 10000

	# Actualizar el borde delimitador del mapa
	update_map_boundary(width_val, height_val)

	# Actualizar material del GridVisual
	var grid_visual = get_node_or_null("GroundPlane/GridVisual")
	if is_instance_valid(grid_visual) and grid_visual is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.08, 0.15, 1)
		mat.metallic     = 0.3
		mat.roughness    = 0.8
		grid_visual.material_override = mat

	print("MapEditor3D: ✅ Cargado mapa Zona ", zone_id, " (", map_data.get("name", "Sin Nombre"), ") Tamaño: ", width_val, "x", height_val)


func _clear_event_markers():
	var old = get_node_or_null("EventMarkers")
	if is_instance_valid(old):
		old.free()

func _create_marker_disc(pos_2d: Vector2, radius_2d: float, color: Color, label: String, parent: Node3D):
	var r_3d = radius_2d * scale_factor
	var pos_3d = Vector3(pos_2d.x * scale_factor, 0.05, pos_2d.y * scale_factor * correction_z)
	
	var marker = CSGCylinder3D.new()
	marker.radius = r_3d
	marker.height = 0.1
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	marker.material = mat
	marker.position = pos_3d
	parent.add_child(marker)
	
	if label != "":
		var lbl = _create_label_3d(label, color)
		lbl.position = pos_3d + Vector3(0, 3.0, 0)
		parent.add_child(lbl)

func _create_label_3d(text: String, color: Color) -> Node3D:
	var lbl = Node3D.new()
	var label3d = Label3D.new()
	label3d.text = text
	label3d.font_size = 24
	label3d.outline_size = 4
	label3d.outline_modulate = Color(0, 0, 0, 0.8)
	label3d.modulate = color
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label3d.no_aa = false
	label3d.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.add_child(label3d)
	return lbl

func _spawn_extraction_markers(ext_cfg: Dictionary):
	var root = Node3D.new()
	root.name = "EventMarkers"
	add_child(root)
	
	var portal_mesh = load("res://assets/Puertas/3D/Puerta2/Puerta2.glb")
	
	var extract_points = ext_cfg.get("extractPoints", [])
	for i in range(extract_points.size()):
		var ep = extract_points[i]
		var x = float(ep.get("x", 0))
		var y = float(ep.get("y", 0))
		var label = str(ep.get("label", "Extracción"))
		_create_marker_disc(Vector2(x, y), 150, Color(0.2, 1, 0.2), "🛸 " + label, root)
		if portal_mesh:
			var portal = portal_mesh.instantiate()
			portal.name = "PortalExtract_" + str(i)
			portal.rotation_degrees = Vector3(-45, -90, 0)
			portal.position = Vector3(x * scale_factor, 0.5, y * scale_factor * correction_z)
			portal.scale = Vector3(10.0, 10.0, 10.0)
			root.add_child(portal)
	
	var spawn_points = ext_cfg.get("spawnPoints", [])
	for sp in spawn_points:
		var x = float(sp.get("x", 0))
		var y = float(sp.get("y", 0))
		var label = str(sp.get("label", "Spawn"))
		_create_marker_disc(Vector2(x, y), 200, Color(0.2, 0.6, 1), "📍 " + label, root)
	
	var spawners = ext_cfg.get("spawners", [])
	for sw in spawners:
		var x = float(sw.get("x", 0))
		var y = float(sw.get("y", 0))
		var radius = float(sw.get("radius", 300))
		var label = str(sw.get("label", "Amenaza"))
		_create_marker_disc(Vector2(x, y), radius, Color(1, 0.2, 0.2), "👾 " + label, root)

func _spawn_altar_defense_markers(ad_cfg: Dictionary):
	var root = Node3D.new()
	root.name = "EventMarkers"
	add_child(root)
	
	var altar_pos = ad_cfg.get("altarPos", {})
	if altar_pos.has("x") and altar_pos.has("y"):
		var x = float(altar_pos.x)
		var y = float(altar_pos.y)
		_create_marker_disc(Vector2(x, y), 250, Color(1, 0.8, 0.2), "🏛️ ALTAR", root)
	
	var spawn_points = ad_cfg.get("spawnPoints", [])
	for sp in spawn_points:
		var x = float(sp.get("x", 0))
		var y = float(sp.get("y", 0))
		var label = str(sp.get("label", "Spawn"))
		_create_marker_disc(Vector2(x, y), 200, Color(0.2, 0.6, 1), "📍 " + label, root)
	
	var spawners = ad_cfg.get("spawners", [])
	for sw in spawners:
		var x = float(sw.get("x", 0))
		var y = float(sw.get("y", 0))
		var radius = float(sw.get("radius", 300))
		var label = str(sw.get("label", "Amenaza"))
		_create_marker_disc(Vector2(x, y), radius, Color(1, 0.2, 0.2), "👾 " + label, root)
	
	var portal_mesh = load("res://assets/Puertas/3D/Puerta2/Puerta2.glb")
	var exit_portals = ad_cfg.get("exitPortals", [])
	for i in range(exit_portals.size()):
		var ep = exit_portals[i]
		var x = float(ep.get("x", 0))
		var y = float(ep.get("y", 0))
		var label = str(ep.get("label", "Portal"))
		_create_marker_disc(Vector2(x, y), 150, Color(0.2, 1, 1), "🚪 " + label, root)
		if portal_mesh:
			var portal = portal_mesh.instantiate()
			portal.name = "PortalEscape_" + str(i)
			portal.rotation_degrees = Vector3(-45, -90, 0)
			portal.position = Vector3(x * scale_factor, 0.5, y * scale_factor * correction_z)
			portal.scale = Vector3(10.0, 10.0, 10.0)
			root.add_child(portal)

func update_map_boundary(width_2d: float, height_2d: float):
	var old_b = get_node_or_null("MapBoundaryVisual")
	if is_instance_valid(old_b):
		old_b.queue_free()
		
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
		
	# v700.3: Buscar y serializar todos los objetos editables de la escena (dentro o fuera de ObjectsRoot)
	var objects_array = []
	if not objects_root:
		objects_root = find_child("ObjectsRoot", true, false)
		
	var stack = []
	for child in get_children():
		stack.append(child)
	if objects_root:
		for child in objects_root.get_children():
			if not child in stack:
				stack.append(child)
				
	while stack.size() > 0:
		var curr = stack.pop_back()
		if not is_instance_valid(curr):
			continue
			
		# Ignorar nodos del sistema de infraestructura por defecto
		if curr.name in ["Camera3D", "GroundPlane", "DirectionalLight3D", "WorldEnvironment", "ObjectsRoot", "MapBoundaryVisual", "EventMarkers", "Terrain3D", "SkyDome"]:
			continue
			
		if curr is Node3D and curr.get_meta("editor_only", false):
			var obj_data = _node3d_to_config_dict(curr)
			objects_array.append(obj_data)
		else:
			for sub in curr.get_children():
				stack.append(sub)
				
	# Reemplazar en la configuración
	maps_config[zone_id]["objects"] = objects_array
	
	# v700.5: Sincronizar propiedad local para guardarla físicamente en el archivo .tscn
	json_to_import = JSON.stringify(objects_array)
	
	# --- SINCRONIZACIÓN REVERSA: Actualizar gameModes si es zona de evento ---
	var zone_id_int_sv = int(zone_id)

	# Separar objetos por tipo (sin lambdas para compatibilidad)
	var door_objects = []
	var altar_objects = []
	for _obj in objects_array:
		var _t = _obj.get("type", "")
		if _t == "door": door_objects.append(_obj)
		elif _t == "altar": altar_objects.append(_obj)

	# Tipo-safe check para extraction maps
	var _sv_is_extraction = false
	if config_dict.has("gameModes") and config_dict.gameModes.has("extraction"):
		var ext_cfg_sv = config_dict.gameModes.extraction
		for _m in ext_cfg_sv.get("maps", []):
			if int(_m) == zone_id_int_sv:
				_sv_is_extraction = true
				break
		if _sv_is_extraction and door_objects.size() > 0:
			var new_extract_pts = []
			for d in door_objects:
				new_extract_pts.append({
					"label": str(d.get("label", "Punto")),
					"x": float(d.get("x", 0)),
					"y": float(d.get("y", 0)),
					"proximityRadius": float(d.get("radius", ext_cfg_sv.get("extractRadius", 150))),
					"targetZone": str(d.get("targetZoneId", "1"))
				})
			ext_cfg_sv["extractPoints"] = new_extract_pts
			print("MapEditor3D: 🔄 gameModes.extraction.extractPoints actualizado con ", new_extract_pts.size(), " puertas.")

	# Tipo-safe check para altar_defense maps
	var _sv_is_altar = false
	if config_dict.has("gameModes") and config_dict.gameModes.has("altar_defense"):
		var ad_cfg_sv = config_dict.gameModes.altar_defense
		for _m in ad_cfg_sv.get("maps", []):
			if int(_m) == zone_id_int_sv:
				_sv_is_altar = true
				break
		if _sv_is_altar:
			if altar_objects.size() > 0:
				var a = altar_objects[0]
				ad_cfg_sv["altarPos"] = { "x": float(a.get("x", 5000)), "y": float(a.get("y", 5000)) }
				print("MapEditor3D: 🔄 gameModes.altar_defense.altarPos actualizado: ", ad_cfg_sv.altarPos)
			if door_objects.size() > 0:
				var new_portals = []
				for d in door_objects:
					new_portals.append({
						"label": str(d.get("label", "Escape")),
						"radius": float(d.get("radius", 150)),
						"x": float(d.get("x", 0)),
						"y": float(d.get("y", 0))
					})
				ad_cfg_sv["exitPortals"] = new_portals
				print("MapEditor3D: 🔄 gameModes.altar_defense.exitPortals actualizado con ", new_portals.size(), " portales del mapa 3D.")

	# Tipo-safe check para arena PVP maps
	var _sv_is_arena = false
	if config_dict.has("gameModes") and config_dict.gameModes.has("arenas"):
		var arenas_cfg_sv = config_dict.gameModes.arenas
		for _m in arenas_cfg_sv.get("maps", []):
			if int(_m) == zone_id_int_sv:
				_sv_is_arena = true
				break
		if _sv_is_arena:
			var arena_map_cfg = arenas_cfg_sv.get("mapConfigs", {}).get(zone_id, {})
			
			var nexus_red_objs = []
			var nexus_blue_objs = []
			var pillar_objs = []
			var spawn_objs = []
			
			for o in objects_array:
				var type_str = o.get("type", "")
				if type_str == "nexus":
					if o.get("team", "") == "red" or o.get("label", "").to_lower().contains("red"):
						nexus_red_objs.append(o)
					else:
						nexus_blue_objs.append(o)
				elif type_str == "pillar":
					pillar_objs.append(o)
				elif type_str == "spawn":
					spawn_objs.append(o)

			# Actualizar Nexo Rojo
			if nexus_red_objs.size() > 0:
				var nr = nexus_red_objs[0]
				arena_map_cfg["nexusRed"] = {
					"x": float(nr.get("x", 2000)),
					"y": float(nr.get("y", 5000)),
					"hp": float(nr.get("hp", 10000)),
					"shield": float(nr.get("shield", 5000))
				}
				print("MapEditor3D: 🔄 gameModes.arenas nexusRed actualizado.")
				
			# Actualizar Nexo Azul
			if nexus_blue_objs.size() > 0:
				var nb = nexus_blue_objs[0]
				arena_map_cfg["nexusBlue"] = {
					"x": float(nb.get("x", 8000)),
					"y": float(nb.get("y", 5000)),
					"hp": float(nb.get("hp", 10000)),
					"shield": float(nb.get("shield", 5000))
				}
				print("MapEditor3D: 🔄 gameModes.arenas nexusBlue actualizado.")

			# Actualizar Pilares
			if pillar_objs.size() > 0:
				var new_pillars = []
				for p in pillar_objs:
					new_pillars.append({
						"name": str(p.get("label", "Pilar")),
						"team": str(p.get("team", "neutral")),
						"x": float(p.get("x", 0)),
						"y": float(p.get("y", 0)),
						"hp": float(p.get("hp", 3000)),
						"shield": float(p.get("shield", 1500)),
						"range": float(p.get("range", 600)),
						"ammoType": str(p.get("ammoType", "laser")),
						"attackType": str(p.get("attackType", "fast")),
						"damage": float(p.get("damage", 150))
					})
				arena_map_cfg["pillars"] = new_pillars
				print("MapEditor3D: 🔄 gameModes.arenas pillars actualizados: ", new_pillars.size())

			# Actualizar Spawns
			if spawn_objs.size() > 0:
				var new_spawns = []
				for sp in spawn_objs:
					new_spawns.append({
						"name": str(sp.get("label", "Spawn")),
						"team": str(sp.get("team", "red")),
						"x": float(sp.get("x", 0)),
						"y": float(sp.get("y", 0)),
						"radius": float(sp.get("radius", 200))
					})
				arena_map_cfg["spawns"] = new_spawns
				print("MapEditor3D: 🔄 gameModes.arenas spawns actualizados: ", new_spawns.size())

	
	# Escribir de vuelta a config.json de forma bonita (4 espacios de indentación)
	var new_content = JSON.stringify(config_dict, "    ")
	var write_file = FileAccess.open(file_path, FileAccess.WRITE)
	if write_file:
		write_file.store_string(new_content)
		write_file.close()
		print("MapEditor3D: ✅ Guardado mapa de la Zona ", zone_id, " (", maps_config[zone_id].get("name", "Sin Nombre"), ") en Server/config.json.")
		
		# Sincronización local: Guardar automáticamente la escena .tscn del editor para evitar desincronización
		if Engine.is_editor_hint():
			var ei = Engine.get_singleton("EditorInterface")
			if ei:
				ei.save_scene()
				print("MapEditor3D: ✅ Escena .tscn guardada automáticamente en disco.")
	else:
		print("MapEditor3D: Error al abrir config.json para escribir.")
