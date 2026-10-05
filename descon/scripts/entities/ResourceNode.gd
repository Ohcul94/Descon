extends Area2D

# ResourceNode.gd
# Nodo de recurso recolectable (Cartografía → Recursos).
# Muestra el asset 3D definido en AdminDash, abre el canal de recolección
# con un rayo celeste y envía la recolección al servidor al completarse.

const BEAM_VFX_SCRIPT = preload("res://scripts/vfx/ResourceBeamVFX.gd")
const COLLECT_RANGE: float = 460.0 # margen por encima del interactRange del servidor (400)

var node_id: String = ""
var data: Dictionary = {}
var asset_path: String = ""
var icon_path: String = ""
var amount: int = 1
var node_scale: float = 1.0
var rot_y: float = 0.0
var y_offset: float = 0.0
var respawn_at: int = 0

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
var is_single_world: bool = false
var map_scale: float = 0.02
var _player_ref: Node2D = null
var _cached_camera_3d: Camera3D = null
var _cached_sub_viewport: SubViewport = null

func _ready():
	collision_mask = 1
	collision_layer = 0
	monitoring = true

	collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 170.0
	collision.shape = circle
	add_child(collision)

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
	call_deferred("_check_initial_overlap")

	input_pickable = false

	scale = Vector2.ZERO
	modulate.a = 0.0
	var tw_in = create_tween().set_parallel(true)
	tw_in.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(self, "modulate:a", 1.0, 0.3)

func _build_model() -> void:
	if not is_instance_valid(world_root_3d):
		return
	model_node = null
	if asset_path != "":
		var res = load(asset_path)
		if res is PackedScene:
			icon_scene = res
			model_node = res.instantiate()
			if model_node is Node3D:
				model_node.scale = Vector3.ONE * maxf(0.2, node_scale)
				model_node.rotation_degrees = Vector3(0.0, rot_y, 0.0)
				world_root_3d.add_child(model_node)
	if not is_instance_valid(model_node):
		# Fallback: cristal naranja emisivo
		model_node = Node3D.new()
		var mesh_inst = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = 0.55
		mesh.height = 1.35
		mesh.radial_segments = 6
		mesh.rings = 3
		mesh_inst.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.98, 0.57, 0.24)
		mat.emission_enabled = true
		mat.emission = Color(0.98, 0.5, 0.18)
		mat.emission_energy_multiplier = 1.3
		mat.metallic = 0.35
		mat.roughness = 0.3
		mesh_inst.material_override = mat
		mesh_inst.position.y = 0.65
		model_node.add_child(mesh_inst)
		world_root_3d.add_child(model_node)

	var light = OmniLight3D.new()
	light.light_color = Color(0.98, 0.57, 0.24)
	light.light_energy = 3.5
	light.omni_range = 9.0
	light.position.y = 1.2
	world_root_3d.add_child(light)

func _process(delta: float):
	if is_single_world:
		_update_3d_position()

	float_time += delta
	if is_single_world and is_instance_valid(world_root_3d):
		world_root_3d.position.y = y_offset + sin(float_time * 2.618) * 0.07

	if not is_active:
		return

	var mouse_pos = get_global_mouse_position()
	is_hovered = (global_position.distance_to(mouse_pos) <= 65.0)
	if is_hovered and is_interactable:
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

func _check_initial_overlap():
	if not is_instance_valid(self):
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_body_entered(body)
			break

func _on_body_entered(body):
	if body.is_in_group("player") and is_active:
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

func _unhandled_input(event):
	if is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()

func _interact():
	if not is_active or collecting:
		return
	if NetworkManager:
		NetworkManager.send_event("startCollectResource", { "nodeId": node_id })

# --- Canal de recolección (confirmado por el servidor) ---
func begin_channel(p_gather_time: float) -> void:
	if not is_active or collecting:
		return
	gather_time = maxf(0.5, p_gather_time)
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
	var beam_node = Node2D.new()
	beam_node.name = "ResourceBeam_" + node_id
	beam_node.set_script(BEAM_VFX_SCRIPT)
	add_child(beam_node)
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
	if collecting:
		_cancel_channel("inactive")
	is_interactable = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map) and map.has_method("_hide_resource_button"):
		map._hide_resource_button()
	_deplete_visual()

func respawn() -> void:
	if is_active:
		return
	_spawn_in_visual()

func _deplete_visual() -> void:
	is_active = false
	collision.set_deferred("disabled", true)
	if is_instance_valid(world_root_3d):
		var tw = create_tween()
		tw.tween_property(world_root_3d, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	queue_redraw()

func _spawn_in_visual() -> void:
	is_active = true
	collision.set_deferred("disabled", false)
	if is_instance_valid(world_root_3d):
		var target = Vector3.ONE
		world_root_3d.scale = Vector3.ZERO
		var tw = create_tween()
		tw.tween_property(world_root_3d, "scale", target, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _draw():
	if not is_active and not collecting:
		return
	# Halo base del nodo (naranja = recursos recolectables)
	draw_arc(Vector2.ZERO, 88.0, 0.0, TAU, 48, Color(0.98, 0.57, 0.24, 0.22), 3.0, true)
	if is_interactable and not collecting:
		draw_arc(Vector2.ZERO, 96.0, 0.0, TAU, 48, Color(0.98, 0.57, 0.24, 0.12), 2.0, true)
	# Progreso del canal
	if collecting:
		var t = clampf(collect_elapsed / maxf(gather_time, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, 88.0, -PI / 2.0, -PI / 2.0 + TAU * t, 56, Color(0.22, 0.74, 0.97, 0.95), 6.0, true)

func _safe_free_world_root_3d() -> void:
	if is_instance_valid(world_root_3d):
		world_root_3d.visible = false
		var p = world_root_3d.get_parent()
		if is_instance_valid(p):
			p.remove_child(world_root_3d)
		world_root_3d.queue_free()
		world_root_3d = null
	model_node = null

func _exit_tree():
	if is_instance_valid(beam):
		beam.queue_free()
	beam = null
	_safe_free_world_root_3d()
