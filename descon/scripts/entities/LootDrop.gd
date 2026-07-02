extends Area2D

const COFRE_MODEL_SCENE = preload("res://assets/Contenedores/Cofres/3D/Cofre1/Cofre1.glb")
const HAND_INTERACT_TEX = preload("res://assets/UI/hand_interact.jpg")

var loot_id: String = ""
var is_interactable: bool = false
var is_hovered: bool = false

var sprite: Sprite2D = null
var interaction_prompt: PanelContainer = null
var prompt_label: Label = null
var collision: CollisionShape2D = null
var tween_float: Tween = null

var world_root_3d: Node3D = null
var is_single_world: bool = false
var map_scale: float = 0.02
var _cached_camera_3d: Camera3D = null
var _cached_sub_viewport: SubViewport = null

func _ready():
	collision_mask = 1
	collision_layer = 0

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
		_project_prompt_position()
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

	var key_text = "Y"
	if InputMap.has_action("loot_claim"):
		var events = InputMap.action_get_events("loot_claim")
		if events.size() > 0:
			key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
			if key_text == "SPACE":
				key_text = "ESPACIO"

	interaction_prompt = PanelContainer.new()
	interaction_prompt.visible = false
	interaction_prompt.custom_minimum_size = Vector2(140, 32)
	interaction_prompt.position = Vector2(-70, -60)

	var prompt_style = StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.02, 0.02, 0.05, 0.85)
	prompt_style.border_width_left = 1
	prompt_style.border_width_top = 1
	prompt_style.border_width_right = 1
	prompt_style.border_width_bottom = 1
	prompt_style.border_color = Color(1.0, 0.75, 0.0, 0.8)
	prompt_style.set_corner_radius_all(6)
	prompt_style.anti_aliasing = true
	interaction_prompt.add_theme_stylebox_override("panel", prompt_style)

	var prompt_hbox = HBoxContainer.new()
	prompt_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_hbox.add_theme_constant_override("separation", 6)
	interaction_prompt.add_child(prompt_hbox)

	var prompt_icon = TextureRect.new()
	if HAND_INTERACT_TEX:
		prompt_icon.texture = HAND_INTERACT_TEX
	prompt_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prompt_icon.custom_minimum_size = Vector2(18, 18)
	prompt_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prompt_hbox.add_child(prompt_icon)

	prompt_label = Label.new()
	prompt_label.text = "[" + key_text + "] ABRIR COFRE"
	prompt_label.add_theme_font_size_override("font_size", 11)
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 3)
	prompt_hbox.add_child(prompt_label)

	add_child(interaction_prompt)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	input_pickable = false

	_start_floating_animation()

	scale = Vector2.ZERO
	modulate.a = 0.0
	var tw_in = create_tween().set_parallel(true)
	tw_in.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(self, "modulate:a", 1.0, 0.3)

func _process(_delta):
	if is_single_world:
		_update_3d_position()
		_project_prompt_position()

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

func _project_prompt_position():
	if not is_instance_valid(interaction_prompt) or not is_instance_valid(world_root_3d):
		return
	var map = get_tree().get_first_node_in_group("map")
	if is_instance_valid(_cached_camera_3d) and is_instance_valid(_cached_sub_viewport):
		var px = _cached_camera_3d.unproject_position(world_root_3d.global_position)
		if _cached_sub_viewport.size.x > 0 and _cached_sub_viewport.size.y > 0:
			var ms = Vector2(get_viewport().get_visible_rect().size)
			px *= ms / Vector2(_cached_sub_viewport.size)
		interaction_prompt.global_position = get_viewport().get_canvas_transform().affine_inverse() * px

func _start_floating_animation():
	if tween_float:
		tween_float.kill()
	tween_float = create_tween().set_loops()
	if is_single_world and is_instance_valid(world_root_3d):
		tween_float.tween_property(world_root_3d, "position:y", -0.15, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween_float.tween_property(world_root_3d, "position:y", 0.15, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	elif is_instance_valid(sprite):
		tween_float.tween_property(sprite, "position:y", -8.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween_float.tween_property(sprite, "position:y", 8.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _update_button_label_text():
	var key_text = "Y"
	if InputMap.has_action("loot_claim"):
		var events = InputMap.action_get_events("loot_claim")
		if events.size() > 0:
			key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
			if key_text == "SPACE":
				key_text = "ESPACIO"

	if prompt_label:
		prompt_label.text = "[" + key_text + "] ABRIR COFRE"

func _on_body_entered(body):
	if body.is_in_group("player"):
		is_interactable = true
		_update_button_label_text()
		if interaction_prompt:
			interaction_prompt.visible = true

			interaction_prompt.scale = Vector2.ZERO
			interaction_prompt.pivot_offset = Vector2(70, 16)
			var tw_lbl = create_tween()
			tw_lbl.tween_property(interaction_prompt, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_body_exited(body):
	if body.is_in_group("player"):
		is_interactable = false
		if interaction_prompt:
			interaction_prompt.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

		var ui = get_tree().get_first_node_in_group("loot_ui")
		if ui and ui.current_loot_id == loot_id:
			ui.close_modal()

func _unhandled_input(event):
	if is_interactable and event.is_action_pressed("loot_claim") and not event.is_echo():
		_interact()
		get_viewport().set_input_as_handled()
	elif is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	if interaction_prompt:
		interaction_prompt.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	if tween_float:
		tween_float.kill()

	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func():
		if is_instance_valid(world_root_3d):
			world_root_3d.queue_free()
			world_root_3d = null
		queue_free()
	)
