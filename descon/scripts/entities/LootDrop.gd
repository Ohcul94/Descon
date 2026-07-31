extends Area2D

const COFRE_MODEL_SCENE = preload("res://assets/Contenedores/Cofres/3D/Cofre1/Cofre1.glb")

var loot_id: String = ""
var is_interactable: bool = false
var is_hovered: bool = false

var sprite: Sprite2D = null
var collision: CollisionShape2D = null
var float_time: float = 0.0

var world_root_3d: Node3D = null
var is_single_world: bool = false
var map_scale: float = 0.02
var _cached_camera_3d: Camera3D = null
var _cached_sub_viewport: SubViewport = null

func _ready():
	collision_mask = 1
	collision_layer = 0
	monitoring = true

	collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 180.0
	collision.shape = circle
	add_child(collision)

	var current_map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(current_map) and is_instance_valid(current_map.get("sub_viewport")):
		is_single_world = true
		map_scale = current_map.scale_factor if "scale_factor" in current_map else 0.02

		world_root_3d = Node3D.new()
		world_root_3d.name = "LootDrop3D_" + loot_id
		current_map.sub_viewport.add_child(world_root_3d)
		_cached_camera_3d = current_map.camera_3d if "camera_3d" in current_map else null
		_cached_sub_viewport = current_map.sub_viewport

		if COFRE_MODEL_SCENE:
			var model = COFRE_MODEL_SCENE.instantiate()
			model.scale = Vector3(1.3, 1.3, 1.3)
			model.rotation_degrees = Vector3(0, 90, 0)
			world_root_3d.add_child(model)

		sprite = Sprite2D.new()
		sprite.visible = false
		add_child(sprite)

		_update_3d_position()
	else:
		sprite = Sprite2D.new()
		add_child(sprite)

		var viewport = SubViewport.new()
		viewport.size = Vector2i(256, 256)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)

		var node3d = Node3D.new()
		viewport.add_child(node3d)

		var env = WorldEnvironment.new()
		var world_env = Environment.new()
		world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.ambient_light_color = Color.WHITE
		world_env.ambient_light_energy = 0.9
		env.environment = world_env
		node3d.add_child(env)

		var sun = DirectionalLight3D.new()
		sun.position = Vector3(2, 3, 2.5)
		sun.light_energy = 1.6
		sun.rotation_degrees = Vector3(-45, 35, 0)
		node3d.add_child(sun)

		if COFRE_MODEL_SCENE:
			var model = COFRE_MODEL_SCENE.instantiate()
			node3d.add_child(model)
			model.scale = Vector3(1.3, 1.3, 1.3)
			model.rotation_degrees = Vector3(0, 90, 0)

		var cam = Camera3D.new()
		cam.position = Vector3(0, 0.8, 2.0)
		cam.rotation_degrees = Vector3(-18, 0, 0)
		node3d.add_child(cam)

		sprite.texture = viewport.get_texture()
		sprite.scale = Vector2(0.38, 0.38)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Verificar superposición en el próximo frame (get_overlapping_bodies no funciona en el mismo frame)
	call_deferred("_check_initial_overlap")

	input_pickable = false

	_start_floating_animation()

	scale = Vector2.ZERO
	modulate.a = 0.0
	var tw_in = create_tween().set_parallel(true)
	tw_in.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(self, "modulate:a", 1.0, 0.3)

func _process(delta):
	if is_single_world:
		_update_3d_position()

	float_time += delta
	if is_single_world and is_instance_valid(world_root_3d):
		world_root_3d.position.y = 0.85 + sin(float_time * 2.618) * 0.15
	elif is_instance_valid(sprite):
		sprite.position.y = sin(float_time * 2.618) * 8.0

	var mouse_pos = get_global_mouse_position()
	var dist_to_mouse = global_position.distance_to(mouse_pos)
	is_hovered = (dist_to_mouse <= 65.0)

	if is_hovered and is_interactable:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

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

func _start_floating_animation():
	# Flotación manejada por _process vía seno
	pass

func _check_initial_overlap():
	if not is_instance_valid(self):
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_body_entered(body)
			break

func _on_body_entered(body):
	if body.is_in_group("player"):
		is_interactable = true
		# Mostrar botón de interacción directamente en el mapa
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("_show_loot_button"):
			map._show_loot_button(self)

func _on_body_exited(body):
	if body.is_in_group("player"):
		is_interactable = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("_hide_loot_button"):
			map._hide_loot_button()
		var ui = get_tree().get_first_node_in_group("loot_ui")
		if ui and ui.current_loot_id == loot_id:
			ui.close_modal()

func _unhandled_input(event):
	if is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()

func _interact():
	print("[LOOT] Interactuando con botín: ", loot_id)
	if NetworkManager:
		NetworkManager.send_event("inspectLoot", { "lootId": loot_id })

func _exit_tree():
	if is_instance_valid(world_root_3d):
		world_root_3d.queue_free()
		world_root_3d = null

func fade_out_and_free():
	collision.set_deferred("disabled", true)
	is_interactable = false
	var map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(map) and map.has_method("_hide_loot_button"):
		map._hide_loot_button()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func():
		if is_instance_valid(world_root_3d):
			world_root_3d.queue_free()
			world_root_3d = null
		queue_free()
	)
