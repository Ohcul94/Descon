extends Area2D

# MarketTerminal.gd (v1.0 - Terminal de la Casa de Subastas)
# Infraestructura interactiva del Mercado en el Lobby (Zona Segura).

const DEFAULT_TERMINAL_MODEL = preload("res://assets/Mapas/Mapa1/Estructuras/3D/Decorativo3/Decorativo3.glb")

var TERMINAL_MODEL_SCENE: PackedScene = null

var is_interactable: bool = false
var is_hovered: bool = false

var sprite: Sprite2D = null
var collision: CollisionShape2D = null
var float_time: float = 0.0

var is_single_world: bool = false
var world_root_3d: Node3D = null
var map_scale: float = 0.02

func _ready():
	add_to_group("market_terminals")
	
	# Modelo del objeto colocado en MapEditor3D (assetPath) con fallback al diseño por defecto
	var asset_path = str(get_meta("asset_path", ""))
	if asset_path != "" and ResourceLoader.exists(asset_path):
		var loaded = load(asset_path)
		if loaded is PackedScene:
			TERMINAL_MODEL_SCENE = loaded
			print("[MARKET] Usando asset del mapa: ", asset_path)
	if TERMINAL_MODEL_SCENE == null:
		TERMINAL_MODEL_SCENE = DEFAULT_TERMINAL_MODEL
	
	collision_mask = 1
	collision_layer = 0
	
	collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 160.0
	collision.shape = circle
	add_child(collision)
	
	var solid_body = StaticBody2D.new()
	solid_body.collision_layer = 2
	solid_body.collision_mask = 0
	add_child(solid_body)
	
	var solid_collision = CollisionShape2D.new()
	var solid_circle = CircleShape2D.new()
	solid_circle.radius = 45.0
	solid_collision.shape = solid_circle
	solid_body.add_child(solid_collision)
	
	sprite = Sprite2D.new()
	add_child(sprite)
	
	var current_map = get_tree().get_first_node_in_group("map")
	var target_viewport = null
	
	if is_instance_valid(current_map):
		if "sub_viewport" in current_map and is_instance_valid(current_map.sub_viewport):
			is_single_world = true
			target_viewport = current_map.sub_viewport
			if "scale_factor" in current_map:
				map_scale = current_map.scale_factor
				
	sprite.visible = not is_single_world
	
	if is_single_world:
		var skip_3d = get_meta("skip_3d_model", false)
		if not skip_3d:
			world_root_3d = Node3D.new()
			world_root_3d.name = "Market3D_" + name
			target_viewport.add_child(world_root_3d)
			
			if TERMINAL_MODEL_SCENE:
				var model = TERMINAL_MODEL_SCENE.instantiate()
				world_root_3d.add_child(model)
				
				var custom_scale = get_meta("custom_scale", 2.0)
				var custom_rot_y = get_meta("custom_rot_y", 0.0)
				model.scale = Vector3.ONE * custom_scale
				model.rotation_degrees = Vector3(0, custom_rot_y, 0)
				
				# Luz dorada distintiva del Mercado
				var light = OmniLight3D.new()
				light.name = "MarketLight"
				light.position = Vector3(0, 2.2, 0)
				light.light_color = Color(1.0, 0.84, 0.0)
				light.light_energy = 4.0
				light.omni_range = 12.0
				world_root_3d.add_child(light)
			_update_3d_position()
	else:
		var viewport = SubViewport.new()
		viewport.size = Vector2i(512, 512)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		
		world_root_3d = Node3D.new()
		viewport.add_child(world_root_3d)
		
		var env = WorldEnvironment.new()
		var world_env = Environment.new()
		world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.ambient_light_color = Color(0.8, 0.85, 0.9)
		world_env.ambient_light_energy = 1.2
		env.environment = world_env
		world_root_3d.add_child(env)
		
		var sun = DirectionalLight3D.new()
		sun.position = Vector3(2, 3, 2.5)
		sun.light_energy = 1.8
		sun.rotation_degrees = Vector3(-45, 35, 0)
		world_root_3d.add_child(sun)
		
		if TERMINAL_MODEL_SCENE:
			var model = TERMINAL_MODEL_SCENE.instantiate()
			world_root_3d.add_child(model)
			
			var custom_scale = get_meta("custom_scale", 2.0)
			var custom_rot_y = get_meta("custom_rot_y", 0.0)
			model.scale = Vector3.ONE * custom_scale
			model.rotation_degrees = Vector3(0, custom_rot_y, 0)
		
		var cam = Camera3D.new()
		cam.position = Vector3(0, 1.6, 3.8)
		cam.rotation_degrees = Vector3(-20, 0, 0)
		world_root_3d.add_child(cam)
		
		sprite.texture = viewport.get_texture()
		sprite.scale = Vector2(0.84, 0.84)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	
	# Etiqueta flotante "MERCADO"
	var label = Label.new()
	label.text = "MERCADO"
	label.position = Vector2(-42, -95)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	call_deferred("_check_initial_overlap")
	_start_floating_animation()

func _process(delta):
	float_time += delta
	if is_single_world and is_instance_valid(world_root_3d):
		var base_y = get_meta("custom_y_offset", 0.0)
		world_root_3d.position.y = base_y
	elif is_instance_valid(sprite):
		sprite.position.y = 0.0
	_update_3d_position()
	
	var mouse_pos = get_global_mouse_position()
	var dist_to_mouse = global_position.distance_to(mouse_pos)
	is_hovered = (dist_to_mouse <= 55.0)
	
	if is_hovered and is_interactable:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _start_floating_animation():
	pass

func _update_3d_position():
	if is_instance_valid(world_root_3d):
		var current_map = get_tree().get_first_node_in_group("map")
		var correction_z = current_map.correction_z if is_instance_valid(current_map) and "correction_z" in current_map else 1.41421356
		world_root_3d.position.x = global_position.x * map_scale
		world_root_3d.position.z = global_position.y * map_scale * correction_z

func _exit_tree():
	if is_single_world and is_instance_valid(world_root_3d):
		world_root_3d.queue_free()

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
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("register_market_interaction"):
			map.register_market_interaction(self)

func _on_body_exited(body):
	if body.is_in_group("player"):
		is_interactable = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("unregister_market_interaction") and map.get("active_market_node") == self:
			map.unregister_market_interaction()
		var ui = get_tree().get_first_node_in_group("market_ui")
		if ui and ui.is_open:
			ui.close_market()

func _unhandled_input(event):
	if is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()

func _interact():
	print("[MARKET] Interactuando con terminal de la Casa de Subastas")
	if NetworkManager:
		NetworkManager.send_event("getMarketData", {})