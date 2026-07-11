extends Area2D

# Precargas estáticas para optimización de rendimiento (v313.2)
const BAUL_MODEL_SCENE = preload("res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb")

# Vault.gd (v1.0 - Baúl Personal Interactivo AAA)
# Entidad física del banco espacial en el lobby.

var is_interactable: bool = false
var is_hovered: bool = false

# Componentes visuales dinámicos
var sprite: Sprite2D = null
var collision: CollisionShape2D = null
var float_time: float = 0.0

# Soporte para perspectiva 2.5D global (is_single_world)
var is_single_world: bool = false
var world_root_3d: Node3D = null
var map_scale: float = 0.02

func _ready():
	add_to_group("vaults")
	
	# 1. Configurar capas de física para colisionar con el Player
	collision_mask = 1 # Detectar al jugador (collision_layer = 1)
	collision_layer = 0 # Estático, no colisiona
	
	# 2. Configurar la forma de colisión
	collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 160.0 # Rango de interacción
	collision.shape = circle
	add_child(collision)
	
	# 2b. Configurar obstáculo sólido (StaticBody2D) para colisión física real
	var solid_body = StaticBody2D.new()
	solid_body.collision_layer = 2 # Capa física que bloquea al jugador (collision_mask = 2)
	solid_body.collision_mask = 0  # No necesita detectar nada él mismo
	add_child(solid_body)
	
	var solid_collision = CollisionShape2D.new()
	var solid_circle = CircleShape2D.new()
	solid_circle.radius = 45.0 # Radio de colisión física (bloquea el paso)
	solid_collision.shape = solid_circle
	solid_body.add_child(solid_collision)
	
	# 3. Crear sprite visual y renderizador 3D local
	sprite = Sprite2D.new()
	add_child(sprite)
	
	# Detectar si hay un lienzo 3D global en el mapa actual
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
		# Instanciar en el Viewport global del mapa
		world_root_3d = Node3D.new()
		world_root_3d.name = "Vault3D_" + name
		target_viewport.add_child(world_root_3d)
		
		if BAUL_MODEL_SCENE:
			var model = BAUL_MODEL_SCENE.instantiate()
			world_root_3d.add_child(model)
			model.scale = Vector3(1.4, 1.4, 1.4)
			model.rotation_degrees = Vector3(0, 90, 0)
		_update_3d_position()
	else:
		# Render local con SubViewport propio (fallback)
		var viewport = SubViewport.new()
		viewport.size = Vector2i(512, 512)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		
		world_root_3d = Node3D.new()
		viewport.add_child(world_root_3d)
		
		# Entorno con luz ambiente blanca
		var env = WorldEnvironment.new()
		var world_env = Environment.new()
		world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.ambient_light_color = Color(0.8, 0.85, 0.9)
		world_env.ambient_light_energy = 1.2
		env.environment = world_env
		world_root_3d.add_child(env)
		
		# Luz direccional frontal para relieve 3D
		var sun = DirectionalLight3D.new()
		sun.position = Vector3(2, 3, 2.5)
		sun.light_energy = 1.8
		sun.rotation_degrees = Vector3(-45, 35, 0)
		world_root_3d.add_child(sun)
		
		if BAUL_MODEL_SCENE:
			var model = BAUL_MODEL_SCENE.instantiate()
			world_root_3d.add_child(model)
			model.scale = Vector3(1.4, 1.4, 1.4) # Escala normal perfecta para el baúl
			model.rotation_degrees = Vector3(0, 90, 0) # Mirando de frente y nivelado
		
		# Cámara 3D (Ángulo ligeramente inclinado desde arriba)
		var cam = Camera3D.new()
		cam.position = Vector3(0, 1.6, 3.8)
		cam.rotation_degrees = Vector3(-20, 0, 0)
		world_root_3d.add_child(cam)
		
		# Asignar la textura renderizada al Sprite 2D de la entidad
		sprite.texture = viewport.get_texture()
		sprite.scale = Vector2(0.84, 0.84)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	
	# 4. Conectar señales
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Verificar superposición en el próximo frame
	call_deferred("_check_initial_overlap")

	# Animaciones de suspensión
	_start_floating_animation()

func _process(delta):
	float_time += delta
	if is_single_world and is_instance_valid(world_root_3d):
		world_root_3d.position.y = sin(float_time * 2.243) * 0.12 - 0.5
	elif is_instance_valid(sprite):
		sprite.position.y = sin(float_time * 2.243) * 6.0
	_update_3d_position()
	
	var mouse_pos = get_global_mouse_position()
	var dist_to_mouse = global_position.distance_to(mouse_pos)
	# v1.1: Reducir radio de hover de 120px a 55px para que se ajuste a su nueva escala y evitar clics accidentales al costado
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
		# Registrar en el mapa para mostrar botón de interacción
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("register_vault_interaction"):
			map.register_vault_interaction(self)

func _on_body_exited(body):
	if body.is_in_group("player"):
		is_interactable = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		# Solo desregistrar si este vault es el activo actualmente
		var map = get_tree().get_first_node_in_group("map")
		if is_instance_valid(map) and map.has_method("unregister_vault_interaction") and map.get("active_vault_node") == self:
			map.unregister_vault_interaction()
		# Cerrar el modal del baúl si se aleja
		var ui = get_tree().get_first_node_in_group("vault_ui")
		if ui and ui.is_open:
			ui.close_vault()

func _unhandled_input(event):
	if is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()

func _interact():
	print("[VAULT] Interactuando con baúl personal")
	if NetworkManager:
		NetworkManager.send_event("getVaultData", {})
