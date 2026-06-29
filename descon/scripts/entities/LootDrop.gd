extends Area2D

# Preprecargas estáticas para evitar I/O y congelamiento de FPS en el hilo principal (v313.2)
const COFRE_MODEL_SCENE = preload("res://assets/Contenedores/Cofres/3D/Cofre1/Cofre1.glb")
const HAND_INTERACT_TEX = preload("res://assets/UI/hand_interact.jpg")

# LootDrop.gd (v1.0 - Botín Físico Interactivo AAA)
# Representa el contenedor visual de botín en el mapa espacial.

var loot_id: String = ""
var is_interactable: bool = false
var is_hovered: bool = false

# Componentes visuales dinámicos
var sprite: Sprite2D = null
var interaction_prompt: PanelContainer = null
var prompt_label: Label = null
var collision: CollisionShape2D = null
var tween_float: Tween = null




func _ready():
	# 1. Configurar capas de física para colisionar con el Player (Player está en capa 1)
	collision_mask = 1 # Detectar al jugador (collision_layer = 1)
	collision_layer = 0 # No colisiona con proyectiles ni otros
	
	# 2. Configurar la forma de colisión dinámicamente
	collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 180.0 # Rango de interacción cómodo
	collision.shape = circle
	add_child(collision)
	
	# 3. Crear sprite visual y renderizador 3D local (SubViewport)
	sprite = Sprite2D.new()
	add_child(sprite)
	
	var viewport = SubViewport.new()
	viewport.size = Vector2i(256, 256)
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
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.9
	env.environment = world_env
	node3d.add_child(env)
	
	# Luz direccional frontal para relieve 3D (Rotación precalculada para evitar look_at antes de entrar al árbol)
	var sun = DirectionalLight3D.new()
	sun.position = Vector3(2, 3, 2.5)
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-45, 35, 0)
	node3d.add_child(sun)
	
	# Instanciar el cofre 3D GLB precargado
	if COFRE_MODEL_SCENE:
		var model = COFRE_MODEL_SCENE.instantiate()
		node3d.add_child(model)
		# Escala y rotación del cofre (nivelado horizontalmente)
		model.scale = Vector3(1.3, 1.3, 1.3)
		model.rotation_degrees = Vector3(0, 90, 0)
	
	# Cámara 3D (Posición y ángulo fijos para evitar look_at antes de entrar al árbol)
	var cam = Camera3D.new()
	cam.position = Vector3(0, 0.8, 2.0)
	cam.rotation_degrees = Vector3(-18, 0, 0)
	node3d.add_child(cam)
	
	# Asignar la textura renderizada al Sprite 2D de la entidad
	sprite.texture = viewport.get_texture()
	sprite.scale = Vector2(0.38, 0.38) # Tamaño aumentado (más visible pero más chico que la nave)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	
	# 4. Crear panel flotante de interacción premium (Cargar atajo dinámico desde el SettingsManager)
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
	prompt_style.bg_color = Color(0.02, 0.02, 0.05, 0.85) # Fondo espacial oscuro neón
	prompt_style.border_width_left = 1
	prompt_style.border_width_top = 1
	prompt_style.border_width_right = 1
	prompt_style.border_width_bottom = 1
	prompt_style.border_color = Color(1.0, 0.75, 0.0, 0.8) # Dorado brillante neón
	prompt_style.set_corner_radius_all(6)
	prompt_style.anti_aliasing = true
	interaction_prompt.add_theme_stylebox_override("panel", prompt_style)
	
	var prompt_hbox = HBoxContainer.new()
	prompt_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_hbox.add_theme_constant_override("separation", 6)
	interaction_prompt.add_child(prompt_hbox)
	
	# Icono miniatura de la manito interactiva precargada
	var prompt_icon = TextureRect.new()
	if HAND_INTERACT_TEX:
		prompt_icon.texture = HAND_INTERACT_TEX
	prompt_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prompt_icon.custom_minimum_size = Vector2(18, 18)
	prompt_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prompt_hbox.add_child(prompt_icon)
	
	# Texto indicador de tecla
	prompt_label = Label.new()
	prompt_label.text = "[" + key_text + "] ABRIR COFRE"
	prompt_label.add_theme_font_size_override("font_size", 11)
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Amarillo dorado suave
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 3)
	prompt_hbox.add_child(prompt_label)
	
	add_child(interaction_prompt)
	
	# 5. Conectar señales de proximidad
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# 6. Configuración de interacción de mouse (Matemática por distancia para precisión)
	input_pickable = false
	
	# 7. Animaciones AAA
	_start_floating_animation()
	
	# C) Animación de entrada (escala progresiva)
	scale = Vector2.ZERO
	modulate.a = 0.0
	var tw_in = create_tween().set_parallel(true)
	tw_in.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(self, "modulate:a", 1.0, 0.3)
 
func _process(_delta):
	# Detección matemática de hover del mouse
	var mouse_pos = get_global_mouse_position()
	var dist_to_mouse = global_position.distance_to(mouse_pos)
	is_hovered = (dist_to_mouse <= 65.0)
	
	# Cambiar el cursor a manito si está encima y el jugador está lo suficientemente cerca
	if is_hovered and is_interactable:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
 
func _start_floating_animation():
	if tween_float:
		tween_float.kill()
	tween_float = create_tween().set_loops()
	tween_float.tween_property(sprite, "position:y", -8.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween_float.tween_property(sprite, "position:y", 8.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# _create_loot_button_ui fue removida para limpiar el botón del HUD

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
	# Si entra el jugador local
	if body.is_in_group("player"):
		is_interactable = true
		_update_button_label_text()
		if interaction_prompt:
			interaction_prompt.visible = true
			
			# Animación de latido y escala del panel flotante
			interaction_prompt.scale = Vector2.ZERO
			interaction_prompt.pivot_offset = Vector2(70, 16) # Mitad de su tamaño mínimo 140x32
			var tw_lbl = create_tween()
			tw_lbl.tween_property(interaction_prompt, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
 
func _on_body_exited(body):
	if body.is_in_group("player"):
		is_interactable = false
		if interaction_prompt:
			interaction_prompt.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		
		# Si el modal del loot está abierto para este botín, notificarle que cierre
		var ui = get_tree().get_first_node_in_group("loot_ui")
		if ui and ui.current_loot_id == loot_id:
			ui.close_modal()
 
func _unhandled_input(event):
	# Atajo de teclado: Acción rebindeable loot_claim si está en rango
	if is_interactable and event.is_action_pressed("loot_claim") and not event.is_echo():
		_interact()
		get_viewport().set_input_as_handled()
	# Click izquierdo sobre la zona del cofre si está en rango
	elif is_interactable and is_hovered and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_interact()
		get_viewport().set_input_as_handled()
 
func _interact():
	print("[LOOT] Interactuando con botín: ", loot_id)
	if NetworkManager:
		NetworkManager.send_event("inspectLoot", { "lootId": loot_id })
 
func fade_out_and_free():
	# Desactivar interacción física inmediatamente
	collision.set_deferred("disabled", true)
	is_interactable = false
	if interaction_prompt:
		interaction_prompt.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	if tween_float:
		tween_float.kill()
		
	# Animación de encogimiento suave
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func():
		queue_free()
	)
