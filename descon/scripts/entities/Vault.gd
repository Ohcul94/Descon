extends Area2D

# Vault.gd (v1.0 - Baúl Personal Interactivo AAA)
# Entidad física del banco espacial en el lobby.

var is_interactable: bool = false
var is_hovered: bool = false

# Componentes visuales dinámicos
var sprite: Sprite2D = null
var interaction_prompt: PanelContainer = null
var prompt_label: Label = null
var collision: CollisionShape2D = null
var tween_float: Tween = null

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
	
	# 3. Crear sprite visual y renderizador 3D local (SubViewport)
	sprite = Sprite2D.new()
	add_child(sprite)
	
	var viewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	
	# Escena 3D interna
	var node3d = Node3D.new()
	viewport.add_child(node3d)
	
	# Entorno con luz ambiente blanca
	var env = WorldEnvironment.new()
	var world_env = Environment.new()
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color(0.8, 0.85, 0.9)
	world_env.ambient_light_energy = 1.2
	env.environment = world_env
	node3d.add_child(env)
	
	# Luz direccional frontal para relieve 3D
	var sun = DirectionalLight3D.new()
	sun.position = Vector3(2, 3, 2.5)
	sun.light_energy = 1.8
	sun.rotation_degrees = Vector3(-45, 35, 0)
	node3d.add_child(sun)
	
	# Cargar e instanciar el modelo 3D del Baúl Personal
	var glb_path = "res://assets/Contenedores/Baules/3D/Baul1/Baul1.glb"
	if ResourceLoader.exists(glb_path):
		var model_scene = load(glb_path)
		if model_scene:
			var model = model_scene.instantiate()
			node3d.add_child(model)
			model.scale = Vector3(2.8, 2.8, 2.8) # Tamaño doble (escala gigante solicitada)
			model.rotation_degrees = Vector3(0, 90, 0) # Mirando de frente y nivelado
	
	# Cámara 3D (Ángulo ligeramente inclinado desde arriba)
	var cam = Camera3D.new()
	cam.position = Vector3(0, 1.6, 3.8)
	cam.rotation_degrees = Vector3(-20, 0, 0)
	node3d.add_child(cam)
	
	# Asignar la textura renderizada al Sprite 2D de la entidad
	sprite.texture = viewport.get_texture()
	sprite.scale = Vector2(0.84, 0.84)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	
	# 4. Crear panel flotante de interacción premium
	var key_text = "Y"
	if InputMap.has_action("loot_claim"):
		var events = InputMap.action_get_events("loot_claim")
		if events.size() > 0:
			key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
			if key_text == "SPACE":
				key_text = "ESPACIO"
			
	interaction_prompt = PanelContainer.new()
	interaction_prompt.visible = false
	interaction_prompt.custom_minimum_size = Vector2(170, 32)
	interaction_prompt.position = Vector2(-85, -145)
	interaction_prompt.mouse_filter = Control.MOUSE_FILTER_PASS
	interaction_prompt.gui_input.connect(_on_prompt_gui_input)
	
	var prompt_style = StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.02, 0.02, 0.05, 0.9)
	prompt_style.border_width_left = 1
	prompt_style.border_width_top = 1
	prompt_style.border_width_right = 1
	prompt_style.border_width_bottom = 1
	prompt_style.border_color = Color(1.0, 0.75, 0.0, 0.8) # Borde dorado brillante
	prompt_style.set_corner_radius_all(6)
	prompt_style.anti_aliasing = true
	interaction_prompt.add_theme_stylebox_override("panel", prompt_style)
	
	var prompt_hbox = HBoxContainer.new()
	prompt_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_hbox.add_theme_constant_override("separation", 6)
	prompt_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_prompt.add_child(prompt_hbox)
	
	# Icono miniatura de la mano (cargado desde el archivo JPG)
	var prompt_icon = TextureRect.new()
	var img_path = "res://assets/UI/hand_interact.jpg"
	if ResourceLoader.exists(img_path):
		prompt_icon.texture = load(img_path)
	prompt_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prompt_icon.custom_minimum_size = Vector2(18, 18)
	prompt_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prompt_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_hbox.add_child(prompt_icon)
	
	# Texto
	prompt_label = Label.new()
	prompt_label.text = "[" + key_text + "] BAÚL PERSONAL"
	prompt_label.add_theme_font_size_override("font_size", 11)
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 3)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_hbox.add_child(prompt_label)
	
	add_child(interaction_prompt)
	
	# Conectar señales
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Animaciones de suspensión
	_start_floating_animation()

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var dist_to_mouse = global_position.distance_to(mouse_pos)
	is_hovered = (dist_to_mouse <= 120.0)
	
	if is_hovered and is_interactable:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _start_floating_animation():
	if tween_float:
		tween_float.kill()
	tween_float = create_tween().set_loops()
	tween_float.tween_property(sprite, "position:y", -6.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween_float.tween_property(sprite, "position:y", 6.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _update_prompt_text():
	var key_text = "Y"
	if InputMap.has_action("loot_claim"):
		var events = InputMap.action_get_events("loot_claim")
		if events.size() > 0:
			key_text = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
			if key_text == "SPACE":
				key_text = "ESPACIO"
				
	if prompt_label:
		prompt_label.text = "[" + key_text + "] BAÚL PERSONAL"

func _on_body_entered(body):
	if body.is_in_group("player"):
		is_interactable = true
		_update_prompt_text()
		if interaction_prompt:
			interaction_prompt.visible = true
			interaction_prompt.scale = Vector2.ZERO
			interaction_prompt.pivot_offset = Vector2(85, 16)
			var tw = create_tween()
			tw.tween_property(interaction_prompt, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_body_exited(body):
	if body.is_in_group("player"):
		is_interactable = false
		if interaction_prompt:
			interaction_prompt.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		
		# Cerrar el modal del baúl si se aleja
		var ui = get_tree().get_first_node_in_group("vault_ui")
		if ui and ui.is_open:
			ui.close_vault()

func _unhandled_input(event):
	if is_interactable and event.is_action_pressed("loot_claim") and not event.is_echo():
		_interact()
		get_viewport().set_input_as_handled()
	elif is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()

func _interact():
	print("[VAULT] Interactuando con baúl personal")
	if NetworkManager:
		NetworkManager.send_event("getVaultData", {})

func _on_prompt_gui_input(event):
	if is_interactable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()
