extends Area2D

# ResourceNode.gd
# Nodo de recurso recolectable (Cartografía → Recursos).
# Muestra el asset 3D definido en AdminDash sobre la cota exacta del piso,
# abre el canal de recolección con rayo 3D y maneja stacks individuales.

const BEAM_VFX_SCRIPT = preload("res://scripts/vfx/ResourceBeamVFX.gd")
const COLLECT_RANGE: float = 460.0 # margen por encima del interactRange del servidor (400)

# Propiedades y señales para compatibilidad total con sistema de Target HUD v350
var is_resource_node: bool = true
var is_dead: bool = false
var is_selected: bool = false
var clan_tag: String = ""
var username: String = ""
var current_hp: float = 1.0
var max_hp: float = 1.0
var current_shield: float = 0.0
var max_shield: float = 0.0

var node_id: String = ""
var resource_id: String = ""
var data: Dictionary = {}
var asset_path: String = ""
var icon_path: String = ""
var amount: int = 1
var node_scale: float = 1.0
var can_float: bool = false
var rot_y: float = 0.0
var y_offset: float = 0.5
var respawn_at: int = 0

var total_stacks: int = 1
var remaining_stacks: int = 1

var is_interactable: bool = false
var is_hovered: bool = false
var is_active: bool = true

var collecting: bool = false
var gather_time: float = 3.0
var collect_elapsed: float = 0.0

var beam = null
var icon_scene: PackedScene = null

var collision: CollisionShape2D = null
var float_time: float = 0.0
var world_root_3d: Node3D = null
var model_node: Node3D = null
var _3d_model: Node3D = null
var is_single_world: bool = false
var map_scale: float = 0.02
var _player_ref: Node2D = null
var _cached_camera_3d: Camera3D = null
var _cached_sub_viewport: SubViewport = null

func get_debuffs_snapshot() -> Array:
	return []

func get_visual_position() -> Vector2:
	if is_instance_valid(world_root_3d):
		return _project_3d_pos_to_2d(world_root_3d.global_position)
	return global_position

func _project_3d_pos_to_2d(pos_3d: Vector3) -> Vector2:
	var current_map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(current_map):
		if not is_instance_valid(_cached_camera_3d) and "camera_3d" in current_map:
			_cached_camera_3d = current_map.camera_3d
		if not is_instance_valid(_cached_sub_viewport) and "sub_viewport" in current_map:
			_cached_sub_viewport = current_map.sub_viewport
	
	if is_instance_valid(_cached_camera_3d) and is_instance_valid(_cached_sub_viewport):
		var cam3d = _cached_camera_3d
		var sub_vp = _cached_sub_viewport
		if sub_vp.size.x > 0 and sub_vp.size.y > 0 and not cam3d.is_position_behind(pos_3d):
			var sv_pixel = cam3d.unproject_position(pos_3d)
			var container = current_map.viewport_container if (is_instance_valid(current_map) and "viewport_container" in current_map) else null
			if is_instance_valid(container):
				sv_pixel *= Vector2(container.size) / Vector2(sub_vp.size)
				sv_pixel = container.global_position + sv_pixel * Vector2(container.scale)
			else:
				var main_size = Vector2(get_viewport().get_visible_rect().size)
				sv_pixel *= main_size / Vector2(sub_vp.size)
			return get_viewport().get_canvas_transform().affine_inverse() * sv_pixel
	return global_position

func get_target_name() -> String:
	var res_id = resource_id
	if res_id == "" or res_id == "null":
		res_id = str(data.get("resourceId", ""))

	var gc = get_node_or_null("/root/GameConstants")
	if is_instance_valid(gc):
		var shop = gc.get("SHOP_ITEMS")
		if typeof(shop) == TYPE_DICTIONARY:
			var res_list = shop.get("resources", [])
			if typeof(res_list) == TYPE_ARRAY:
				for r in res_list:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var n = str(r.get("name", "")).strip_edges()
						if n != "":
							return n

	if NetworkManager and "server_config" in NetworkManager and typeof(NetworkManager.server_config) == TYPE_DICTIONARY:
		var sc = NetworkManager.server_config
		var shop_sc = sc.get("shopItems", {})
		if typeof(shop_sc) == TYPE_DICTIONARY:
			var res_list_sc = shop_sc.get("resources", [])
			if typeof(res_list_sc) == TYPE_ARRAY:
				for r in res_list_sc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var n = str(r.get("name", "")).strip_edges()
						if n != "":
							return n

	if data.has("name") and str(data["name"]).strip_edges() != "":
		return str(data["name"])
	if res_id != "" and res_id != "null":
		return res_id.capitalize()
	return "Recurso"

func _ready():
	add_to_group("resource_nodes")
	collision_mask = 1
	collision_layer = 0
	monitoring = true

	collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 170.0
	collision.shape = circle
	add_child(collision)

	username = get_target_name()

	var current_map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(current_map) and is_instance_valid(current_map.get("sub_viewport")):
		is_single_world = true
		map_scale = current_map.scale_factor if "scale_factor" in current_map else 0.02
		world_root_3d = Node3D.new()
		world_root_3d.name = "ResourceNode3D_" + node_id
		current_map.sub_viewport.add_child(world_root_3d)
		_cached_camera_3d = current_map.camera_3d if "camera_3d" in current_map else null
		_cached_sub_viewport = current_map.sub_viewport
		_build_model()
		_update_3d_position()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	input_event.connect(_on_input_event)
	call_deferred("_check_initial_overlap")

	if NetworkManager:
		if not NetworkManager.admin_config_updated.is_connected(_on_admin_config_updated):
			NetworkManager.admin_config_updated.connect(_on_admin_config_updated)
		if not NetworkManager.config_updated.is_connected(_on_admin_config_updated):
			NetworkManager.config_updated.connect(_on_admin_config_updated)

	input_pickable = true

	scale = Vector2.ZERO
	modulate.a = 0.0
	var tw_in = create_tween().set_parallel(true)
	tw_in.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(self, "modulate:a", 1.0, 0.3)

func _on_admin_config_updated(_cfg = null) -> void:
	node_scale = _material_scale()
	can_float = _material_can_float()
	if is_instance_valid(model_node):
		model_node.scale = Vector3.ONE * node_scale
	var new_path = _material_asset_path().strip_edges()
	if new_path != "" and new_path != "null" and new_path != asset_path:
		asset_path = new_path
		_build_model()

func apply_data(p_data: Dictionary) -> void:
	data = p_data
	if p_data.has("resourceId"):
		resource_id = str(p_data["resourceId"])
	if p_data.has("rotY"):
		rot_y = float(p_data["rotY"])
	if p_data.has("yOffset"):
		y_offset = float(p_data["yOffset"])
	if p_data.has("totalStacks"):
		total_stacks = int(p_data["totalStacks"])
	if p_data.has("remainingStacks"):
		remaining_stacks = int(p_data["remainingStacks"])
	if p_data.has("x") and p_data.has("y"):
		global_position = Vector2(float(p_data["x"]), float(p_data["y"]))

	node_scale = _material_scale()
	can_float = bool(p_data.get("canFloat", _material_can_float()))

	var new_asset = _material_asset_path().strip_edges()
	if new_asset == "" or new_asset == "null":
		new_asset = str(p_data.get("assetPath", "")).strip_edges()

	if new_asset != "" and new_asset != "null" and new_asset != asset_path:
		asset_path = new_asset
		_build_model()
	elif is_instance_valid(model_node):
		model_node.scale = Vector3.ONE * node_scale
		model_node.rotation_degrees = Vector3(0.0, rot_y, 0.0)

	set_active_state(bool(p_data.get("active", true)), int(p_data.get("respawnAt", 0)))
	queue_redraw()

func _build_model() -> void:
	if not is_instance_valid(world_root_3d):
		return

	# Limpiar hijos previos si los hubiera
	for child in world_root_3d.get_children():
		child.queue_free()

	# Determinar escala efectiva configurada en el material
	node_scale = _material_scale()
	can_float = bool(data.get("canFloat", _material_can_float()))

	model_node = null
	var model_path = _material_asset_path().strip_edges()
	if model_path == "" or model_path == "null":
		model_path = asset_path.strip_edges()
	if model_path == "" or model_path == "null":
		model_path = str(data.get("assetPath", "")).strip_edges()

	if model_path != "" and model_path != "null":
		asset_path = model_path
		set_meta("current_glb", model_path)
		if ResourceLoader.exists(model_path):
			var res = load(model_path)
			if res is PackedScene:
				icon_scene = res
				model_node = res.instantiate()
				if model_node is Node3D:
					# Limpiar cualquier luz interna quemada del asset 3D
					for child_light in model_node.find_children("*", "Light3D", true):
						child_light.queue_free()
					model_node.scale = Vector3.ONE * node_scale
					model_node.rotation_degrees = Vector3(0.0, rot_y, 0.0)
					world_root_3d.add_child(model_node)
		else:
			push_warning("[ResourceNode] Asset 3D no encontrado en ruta: " + model_path)

	if not is_instance_valid(model_node):
		# Fallback: cristal naranja estilizado escalado proporcionalmente
		model_node = Node3D.new()
		model_node.scale = Vector3.ONE * node_scale
		var mesh_inst = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = 0.55
		mesh.height = 1.35
		mesh.radial_segments = 6
		mesh.rings = 3
		mesh_inst.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.98, 0.57, 0.24)
		mat.metallic = 0.35
		mat.roughness = 0.3
		mesh_inst.material_override = mat
		mesh_inst.position.y = 0.65
		model_node.add_child(mesh_inst)
		world_root_3d.add_child(model_node)

	_3d_model = model_node
	username = get_target_name()

func _material_scale() -> float:
	var res_id = resource_id
	if res_id == "" or res_id == "null":
		res_id = str(data.get("resourceId", ""))

	# 1. Buscar en Constants.SHOP_ITEMS (autoload principal sincronizado en caliente)
	var consts = get_node_or_null("/root/Constants")
	if is_instance_valid(consts):
		var shop = consts.get("SHOP_ITEMS")
		if typeof(shop) == TYPE_DICTIONARY:
			var res_list = shop.get("resources", [])
			if typeof(res_list) == TYPE_ARRAY:
				for r in res_list:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var s = _extract_scale_from_dict(r)
						if s > 0.0:
							return s

	# 2. Buscar en NetworkManager.server_config (copia del socket)
	if NetworkManager and "server_config" in NetworkManager and typeof(NetworkManager.server_config) == TYPE_DICTIONARY:
		var sc = NetworkManager.server_config
		var shop_sc = sc.get("shopItems", {})
		if typeof(shop_sc) == TYPE_DICTIONARY:
			var res_list_sc = shop_sc.get("resources", [])
			if typeof(res_list_sc) == TYPE_ARRAY:
				for r in res_list_sc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var s = _extract_scale_from_dict(r)
						if s > 0.0:
							return s

	# 3. Buscar en GameConstants
	var gc = get_node_or_null("/root/GameConstants")
	if is_instance_valid(gc):
		var shop_gc = gc.get("SHOP_ITEMS")
		if typeof(shop_gc) == TYPE_DICTIONARY:
			var res_list_gc = shop_gc.get("resources", [])
			if typeof(res_list_gc) == TYPE_ARRAY:
				for r in res_list_gc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var s = _extract_scale_from_dict(r)
						if s > 0.0:
							return s

	# 4. Fallback a lo recibido en data del servidor
	var s_data = _extract_scale_from_dict(data)
	if s_data > 0.0:
		return s_data

	return 1.0

func _extract_scale_from_dict(d: Dictionary) -> float:
	if d.has("scale") and float(d.get("scale", 0.0)) > 0.0:
		return float(d["scale"])
	if d.has("iconScale") and float(d.get("iconScale", 0.0)) > 0.0:
		return float(d["iconScale"])
	return 0.0

func _material_asset_path() -> String:
	var res_id = resource_id
	if res_id == "" or res_id == "null":
		res_id = str(data.get("resourceId", ""))

	# 1. Buscar en Constants.SHOP_ITEMS
	var consts = get_node_or_null("/root/Constants")
	if is_instance_valid(consts):
		var shop = consts.get("SHOP_ITEMS")
		if typeof(shop) == TYPE_DICTIONARY:
			var res_list = shop.get("resources", [])
			if typeof(res_list) == TYPE_ARRAY:
				for r in res_list:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var ap = str(r.get("assetPath", ""))
						if ap != "" and ap != "null":
							return ap

	# 2. Buscar en NetworkManager.server_config
	if NetworkManager and "server_config" in NetworkManager and typeof(NetworkManager.server_config) == TYPE_DICTIONARY:
		var sc = NetworkManager.server_config
		var shop_sc = sc.get("shopItems", {})
		if typeof(shop_sc) == TYPE_DICTIONARY:
			var res_list_sc = shop_sc.get("resources", [])
			if typeof(res_list_sc) == TYPE_ARRAY:
				for r in res_list_sc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var ap = str(r.get("assetPath", ""))
						if ap != "" and ap != "null":
							return ap

	# 3. Buscar en GameConstants
	var gc = get_node_or_null("/root/GameConstants")
	if is_instance_valid(gc):
		var shop_gc = gc.get("SHOP_ITEMS")
		if typeof(shop_gc) == TYPE_DICTIONARY:
			var res_list_gc = shop_gc.get("resources", [])
			if typeof(res_list_gc) == TYPE_ARRAY:
				for r in res_list_gc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						var ap = str(r.get("assetPath", ""))
						if ap != "" and ap != "null":
							return ap

	# 4. Fallback data
	if data.has("assetPath"):
		var ap = str(data["assetPath"])
		if ap != "" and ap != "null":
			return ap

	return ""

func _material_can_float() -> bool:
	var res_id = resource_id
	if res_id == "" or res_id == "null":
		res_id = str(data.get("resourceId", ""))

	# 1. Constants
	var consts = get_node_or_null("/root/Constants")
	if is_instance_valid(consts):
		var shop = consts.get("SHOP_ITEMS")
		if typeof(shop) == TYPE_DICTIONARY:
			var res_list = shop.get("resources", [])
			if typeof(res_list) == TYPE_ARRAY:
				for r in res_list:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						if r.has("canFloat"):
							return bool(r["canFloat"])

	# 2. NetworkManager
	if NetworkManager and "server_config" in NetworkManager and typeof(NetworkManager.server_config) == TYPE_DICTIONARY:
		var sc = NetworkManager.server_config
		var shop_sc = sc.get("shopItems", {})
		if typeof(shop_sc) == TYPE_DICTIONARY:
			var res_list_sc = shop_sc.get("resources", [])
			if typeof(res_list_sc) == TYPE_ARRAY:
				for r in res_list_sc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						if r.has("canFloat"):
							return bool(r["canFloat"])

	# 3. GameConstants
	var gc = get_node_or_null("/root/GameConstants")
	if is_instance_valid(gc):
		var shop_gc = gc.get("SHOP_ITEMS")
		if typeof(shop_gc) == TYPE_DICTIONARY:
			var res_list_gc = shop_gc.get("resources", [])
			if typeof(res_list_gc) == TYPE_ARRAY:
				for r in res_list_gc:
					if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == res_id:
						if r.has("canFloat"):
							return bool(r["canFloat"])

	if data.has("canFloat"):
		return bool(data["canFloat"])

	return false

func _process(delta: float):
	float_time += delta

	# 1. Visibilidad por área de visión del jugador y pantalla (alineado con enemigos / bosses)
	var screen_visible = true
	var local_player = _get_player()
	if is_instance_valid(local_player):
		var vision_r = 1300.0
		if "vision_range" in local_player:
			vision_r = float(local_player.vision_range)
		elif "current_ship_id" in local_player and GameConstants.SHIP_MODELS:
			for ship in GameConstants.SHIP_MODELS:
				if ship.id == local_player.current_ship_id:
					vision_r = float(ship.get("vision", 1300.0))
					break
		var dist = global_position.distance_to(local_player.global_position)
		if dist > vision_r:
			screen_visible = false

	if screen_visible:
		var cam = get_viewport().get_camera_2d()
		if is_instance_valid(cam):
			var screen_size = get_viewport_rect().size
			var cam_pos = cam.global_position
			var margin = 600.0
			var diff = global_position - cam_pos
			if abs(diff.x) > (screen_size.x / 2.0 + margin) or abs(diff.y) > (screen_size.y / 2.0 + margin):
				screen_visible = false

	var should_be_visible = screen_visible and is_active
	if is_instance_valid(world_root_3d):
		if world_root_3d.visible != should_be_visible:
			world_root_3d.visible = should_be_visible

	if not should_be_visible:
		if collecting:
			_send_cancel()
			_cancel_channel("too_far")
		return

	if is_single_world:
		_update_3d_position()

	var v_pos = get_visual_position()
	var mouse_canvas_pos = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var mouse_world_pos = get_global_mouse_position()
	is_hovered = (v_pos.distance_to(mouse_canvas_pos) <= 85.0) or (global_position.distance_to(mouse_world_pos) <= 85.0)
	if is_hovered and is_interactable and remaining_stacks > 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	elif is_hovered:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	if collecting:
		collect_elapsed += delta
		var player = _get_player()
		if not is_instance_valid(player):
			_cancel_channel("interrupted")
			return
		if global_position.distance_to(player.global_position) > COLLECT_RANGE:
			_send_cancel()
			_cancel_channel("too_far")
			return
		if is_instance_valid(beam):
			beam.set_progress(collect_elapsed / maxf(gather_time, 0.01))
		if collect_elapsed >= gather_time:
			collecting = false
			_stop_beam()
			if NetworkManager:
				NetworkManager.send_event("collectResource", { "nodeId": node_id })
		queue_redraw()

func _update_3d_position():
	if not is_instance_valid(world_root_3d):
		return
	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map):
		return

	var s_factor = current_map.scale_factor if "scale_factor" in current_map else map_scale
	var c_z = current_map.correction_z if "correction_z" in current_map else 1.41421356

	world_root_3d.position.x = global_position.x * s_factor
	world_root_3d.position.z = global_position.y * s_factor * c_z

	# Altura del piso: consultar el terreno para que se asiente sobre la superficie
	var ground_h: float = 0.0
	if current_map.has_method("get_terrain_height_at_pos"):
		ground_h = current_map.get_terrain_height_at_pos(global_position)
	elif current_map.has_method("get_height_at"):
		ground_h = current_map.get_height_at(global_position.x, global_position.y)

	var float_offset: float = 0.0
	if can_float:
		float_offset = sin(float_time * 2.618) * 0.07
	world_root_3d.position.y = ground_h + y_offset + float_offset

func _check_initial_overlap():
	if not is_instance_valid(self) or not is_active:
		return
	var found_player = false
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_body_entered(body)
			found_player = true
			break
	if not found_player:
		var p = _get_player()
		if is_instance_valid(p) and global_position.distance_to(p.global_position) <= 170.0:
			_on_body_entered(p)

func _on_body_entered(body):
	if body.is_in_group("player") and is_active and remaining_stacks > 0:
		_player_ref = body
		is_interactable = true
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("_show_resource_button"):
			map._show_resource_button(self)

func _on_body_exited(body):
	if body.is_in_group("player"):
		if is_instance_valid(_player_ref) and body == _player_ref:
			_player_ref = null
		is_interactable = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		# Salir del rango cancela el canal en curso
		if collecting:
			_send_cancel()
			_cancel_channel("too_far")
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("_hide_resource_button"):
			map._hide_resource_button()

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_as_target()
		if is_interactable and not collecting and remaining_stacks > 0:
			_interact()

func _unhandled_input(event):
	if is_hovered and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_as_target()
		if is_interactable and not collecting and remaining_stacks > 0:
			_interact()

func _select_as_target() -> void:
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_node_or_null("/root/MainGame/HUD")
	if is_instance_valid(main_hud) and main_hud.has_method("set_target"):
		main_hud.set_target(self)

func _interact():
	if not is_active or collecting or remaining_stacks <= 0:
		return
	if NetworkManager:
		NetworkManager.send_event("startCollectResource", { "nodeId": node_id })

# --- Canal de recolección (confirmado por el servidor) ---
func begin_channel(p_gather_time_ms: float) -> void:
	if not is_active or collecting:
		return
	# El servidor envía el tiempo en milisegundos
	gather_time = maxf(100.0, p_gather_time_ms) / 1000.0
	collect_elapsed = 0.0
	collecting = true
	queue_redraw()
	_spawn_beam()

func cancel_channel(reason: String = "") -> void:
	_cancel_channel(reason)

func _cancel_channel(reason: String = "") -> void:
	if not collecting:
		_stop_beam()
		return
	collecting = false
	collect_elapsed = 0.0
	_stop_beam()
	queue_redraw()
	if reason != "" and reason != "cancelled" and NetworkManager:
		var msg = "Recolección interrumpida."
		match reason:
			"too_far":
				msg = "Te alejaste demasiado del recurso."
			"busy":
				msg = "Otro piloto está recolectando este recurso."
			"inactive":
				msg = "Ese recurso ya fue recolectado."
			"not_recolectable":
				msg = "Ese material no es recolectable."
			"too_fast":
				msg = "Recolección invalidada."
		NetworkManager.game_notification.emit({ "msg": msg, "type": "warning" })

func _send_cancel() -> void:
	if NetworkManager:
		NetworkManager.send_event("cancelCollectResource", { "nodeId": node_id })

func _spawn_beam() -> void:
	if is_instance_valid(beam):
		return
	var player = _get_player()
	if not is_instance_valid(player):
		return

	var current_map = get_tree().get_first_node_in_group("map")
	if not is_instance_valid(current_map) or not is_instance_valid(current_map.get("sub_viewport")):
		return

	var beam_node = BEAM_VFX_SCRIPT.new()
	beam_node.name = "ResourceBeam_" + node_id
	current_map.sub_viewport.add_child(beam_node)
	beam = beam_node
	beam.setup(self, player)

func _stop_beam() -> void:
	if is_instance_valid(beam):
		if beam.has_method("fade_out_and_free"):
			beam.fade_out_and_free()
		else:
			beam.queue_free()
	beam = null

func _get_player() -> Node2D:
	if is_instance_valid(_player_ref):
		return _player_ref
	var p = get_tree().get_first_node_in_group("player")
	return p if p is Node2D else null

# --- Actualización de Stacks ---
func update_stacks(p_remaining: int, p_total: int) -> void:
	remaining_stacks = p_remaining
	total_stacks = p_total
	collecting = false
	collect_elapsed = 0.0
	_stop_beam()

	if is_instance_valid(world_root_3d):
		var tw = create_tween()
		tw.tween_property(world_root_3d, "scale", Vector3.ONE * 1.2, 0.12).set_trans(Tween.TRANS_BACK)
		tw.tween_property(world_root_3d, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)

	if remaining_stacks <= 0:
		deplete()
		return

	# Si el jugador sigue junto al nodo, reactivar la interacción para el siguiente stack
	call_deferred("_check_initial_overlap")
	queue_redraw()

# --- Estado del nodo ---
func set_active_state(active_state: bool, p_respawn_at: int = 0) -> void:
	is_active = active_state
	respawn_at = p_respawn_at
	if is_active:
		_spawn_in_visual()
	else:
		_deplete_visual()

func deplete(p_respawn_at: int = 0) -> void:
	respawn_at = p_respawn_at
	remaining_stacks = 0
	if collecting:
		_cancel_channel("inactive")
	is_interactable = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map) and map.has_method("_hide_resource_button"):
		map._hide_resource_button()
	_deplete_visual()

func respawn(p_data: Dictionary = {}) -> void:
	if not p_data.is_empty():
		data = p_data
		if p_data.has("resourceId"):
			resource_id = str(p_data["resourceId"])
		total_stacks = int(p_data.get("totalStacks", total_stacks))
		remaining_stacks = int(p_data.get("remainingStacks", total_stacks))
		if p_data.has("x") and p_data.has("y"):
			global_position = Vector2(float(p_data["x"]), float(p_data["y"]))
		if p_data.has("canFloat"):
			can_float = bool(p_data["canFloat"])
		else:
			can_float = _material_can_float()
	else:
		remaining_stacks = total_stacks

	# Siempre consultar la escala exacta configurada en el material
	node_scale = _material_scale()

	if is_instance_valid(model_node):
		model_node.scale = Vector3.ONE * node_scale

	is_active = true
	collecting = false
	collect_elapsed = 0.0
	_stop_beam()

	_spawn_in_visual()
	call_deferred("_check_initial_overlap")

func _deplete_visual() -> void:
	is_active = false
	collision.set_deferred("disabled", true)
	if is_instance_valid(world_root_3d):
		var tw = create_tween()
		tw.tween_property(world_root_3d, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.finished.connect(func():
			if not is_active and is_instance_valid(world_root_3d):
				world_root_3d.visible = false
		)
	queue_redraw()

func _spawn_in_visual() -> void:
	is_active = true
	collision.set_deferred("disabled", false)
	if is_instance_valid(world_root_3d):
		world_root_3d.visible = true
		world_root_3d.scale = Vector3.ZERO
		var tw = create_tween()
		tw.tween_property(world_root_3d, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _draw():
	if not is_active and not collecting:
		return

	# Halo base del nodo (naranja = recursos recolectables)
	draw_arc(Vector2.ZERO, 88.0, 0.0, TAU, 48, Color(0.98, 0.57, 0.24, 0.22), 3.0, true)
	if is_interactable and not collecting:
		draw_arc(Vector2.ZERO, 96.0, 0.0, TAU, 48, Color(0.98, 0.57, 0.24, 0.12), 2.0, true)

	# Pips de stacks restantes si el nodo tiene más de 1 stack
	if total_stacks > 1:
		var start_ang = -PI * 0.75
		var arc_span = PI * 0.5
		var pip_radius = 104.0
		for i in range(total_stacks):
			var t = 0.5 if total_stacks == 1 else float(i) / float(total_stacks - 1)
			var ang = start_ang + arc_span * t
			var pos = Vector2(cos(ang), sin(ang)) * pip_radius
			if i < remaining_stacks:
				# Stack disponible (verde turquesa brillante)
				draw_circle(pos, 5.0, Color(0.2, 0.95, 0.5, 0.95))
				draw_circle(pos, 2.5, Color(1.0, 1.0, 1.0, 0.9))
			else:
				# Stack ya consumido (gris oscuro apagado)
				draw_circle(pos, 4.0, Color(0.3, 0.35, 0.4, 0.4))

	# Progreso del canal con contador en segundos
	if collecting:
		var t = clampf(collect_elapsed / maxf(gather_time, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, 88.0, -PI / 2.0, -PI / 2.0 + TAU * t, 56, Color(0.22, 0.74, 0.97, 0.95), 6.0, true)
		var t_txt = "%s / %s" % [_format_seconds(collect_elapsed), _format_seconds(gather_time)]
		var font = ThemeDB.fallback_font
		if is_instance_valid(font):
			draw_string(font, Vector2(-45, 114), t_txt, HORIZONTAL_ALIGNMENT_CENTER, 90, 13, Color.WHITE)

func _format_seconds(sec: float) -> String:
	var rounded = snappedf(sec, 0.1)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%ds" % [int(roundf(rounded))]
	return "%.1fs" % [rounded]

func _safe_free_world_root_3d() -> void:
	if is_instance_valid(world_root_3d):
		world_root_3d.visible = false
		var p = world_root_3d.get_parent()
		if is_instance_valid(p):
			p.remove_child(world_root_3d)
		world_root_3d.queue_free()
		world_root_3d = null
	model_node = null
	_3d_model = null

func _exit_tree():
	if NetworkManager:
		if NetworkManager.admin_config_updated.is_connected(_on_admin_config_updated):
			NetworkManager.admin_config_updated.disconnect(_on_admin_config_updated)
		if NetworkManager.config_updated.is_connected(_on_admin_config_updated):
			NetworkManager.config_updated.disconnect(_on_admin_config_updated)
	if is_instance_valid(beam):
		beam.queue_free()
	beam = null
	_safe_free_world_root_3d()
