extends PanelContainer

# SettingsUI.gd (v1.1 - 7 Slots Unificados)

signal closed

var _is_binding: bool = false
var _binding_action: String = ""
var _binding_label: Button = null

func _ready():
	_setup_ui()
	visible = false

func _setup_ui():
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color.AQUA
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	
	custom_minimum_size = Vector2(400, 600)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# Titulo
	var title = Label.new()
	title.text = "CONFIGURACIÓN DE JUEGO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	# --- MODO DE DISPARO (MOBA) ---
	var cast_label = Label.new()
	cast_label.text = "MODO DE LANZAMIENTO (CAST):"
	vbox.add_child(cast_label)
	
	var cast_option = OptionButton.new()
	cast_option.add_item("Quick Cast (Instantáneo)", 0)
	cast_option.add_item("On Release (Al soltar)", 1)
	cast_option.add_item("Normal Cast (Aim & Click)", 2)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("_skill_controller"):
		cast_option.selected = player._skill_controller.config.cast_mode
	elif get_node_or_null("/root/SettingsManager"):
		cast_option.selected = SettingsManager.get_cast_mode()
	
	cast_option.item_selected.connect(_on_cast_mode_changed)
	vbox.add_child(cast_option)
	
	vbox.add_child(HSeparator.new())
	
	# --- CALIDAD GRÁFICA (3D) ---
	var gfx_label = Label.new()
	gfx_label.text = "CALIDAD GRÁFICA (MODELOS 3D):"
	vbox.add_child(gfx_label)
	
	var gfx_option = OptionButton.new()
	gfx_option.add_item("Baja (Rendimiento / Celulares)", 0)
	gfx_option.add_item("Media (Equilibrado / Recomendado)", 1)
	gfx_option.add_item("Alta (PCs de Gama Alta)", 2)
	
	if get_node_or_null("/root/SettingsManager"):
		gfx_option.selected = SettingsManager.get_graphics_quality()
	
	gfx_option.item_selected.connect(_on_graphics_quality_changed)
	vbox.add_child(gfx_option)
	
	vbox.add_child(HSeparator.new())
	
	# --- CONTROLES (7 SLOTS UNIFICADOS) ---
	var keys_label = Label.new()
	keys_label.text = "ASIGNACIÓN DE SLOTS DE HABILIDAD:"
	vbox.add_child(keys_label)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 250
	vbox.add_child(scroll)
	
	var keys_vbox = VBoxContainer.new()
	scroll.add_child(keys_vbox)
	
	var slots = {
		"slot_1": "SLOT 1 (LÁSER)",
		"slot_2": "SLOT 2 (MISIL)",
		"slot_3": "SLOT 3 (MINA)",
		"slot_4": "SLOT 4 (ESFERA 1)",
		"slot_5": "SLOT 5 (ESFERA 2)",
		"slot_6": "SLOT 6 (ESFERA 3)",
		"slot_7": "SLOT 7 (ESFERA 4)"
	}
	
	for action in slots:
		var row = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = slots[action]
		name_lbl.custom_minimum_size.x = 180
		row.add_child(name_lbl)
		
		var btn = Button.new()
		btn.text = _get_action_key_text(action)
		btn.custom_minimum_size.x = 120
		btn.pressed.connect(_on_bind_pressed.bind(action, btn))
		row.add_child(btn)
		
		keys_vbox.add_child(row)
	
	# Botón Cerrar
	var close_btn = Button.new()
	close_btn.text = "CERRAR Y GUARDAR"
	close_btn.custom_minimum_size.y = 40
	close_btn.pressed.connect(func(): 
		SettingsManager.save_settings()
		visible = false
		closed.emit()
	)
	vbox.add_child(close_btn)
	
	# v264.20: Botón de Reseteo
	var reset_btn = Button.new()
	reset_btn.text = "REESTABLECER VALORES DE FÁBRICA"
	reset_btn.modulate = Color.ORANGE
	reset_btn.pressed.connect(func():
		SettingsManager.reset_to_factory()
		_setup_ui() # Refrescar la UI para mostrar las nuevas teclas
	)
	vbox.add_child(reset_btn)

func _get_action_key_text(action: String) -> String:
	if not InputMap.has_action(action): return "NO DEFINIDA"
	var events = InputMap.action_get_events(action)
	if events.size() > 0:
		return events[0].as_text().replace(" (Physical)", "")
	return "NINGUNA"

func _on_bind_pressed(action: String, label_node: Button):
	if _is_binding: return
	_is_binding = true
	_binding_action = action
	_binding_label = label_node
	label_node.text = "[ PULSA TECLA ]"
	label_node.modulate = Color.YELLOW

func _input(event):
	if _is_binding and event is InputEventKey and event.pressed:
		_rebind_action(_binding_action, event)
		_is_binding = false
		_binding_label.text = event.as_text().replace(" (Physical)", "")
		_binding_label.modulate = Color.WHITE
		get_viewport().set_input_as_handled()

func _rebind_action(action: String, new_event: InputEvent):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, new_event)
	
	# v262.10: Autoguardado Inmediato (Evita pérdida si se cierra con ESC)
	SettingsManager.save_settings()

func _on_cast_mode_changed(idx: int):
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("_skill_controller"):
		player._skill_controller.config.cast_mode = idx
	
	if get_node_or_null("/root/SettingsManager"):
		SettingsManager.cast_mode_cache = idx
		SettingsManager.save_settings()

func _on_graphics_quality_changed(idx: int):
	if get_node_or_null("/root/SettingsManager"):
		SettingsManager.graphics_quality = idx
		SettingsManager.save_settings()
		print("[SETTINGS] Calidad gráfica cambiada a: ", idx)
		
		# Forzar actualización en vivo de las naves y enemigos existentes
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent.has_method("_setup_3d_visuals"):
				# Limpiar metadata para forzar regeneración sin usar la caché
				ent.set_meta("current_glb", "")
				if ent.is_in_group("enemies") and ent.has_method("_setup_enemy_visuals"):
					ent._setup_enemy_visuals()
				elif (ent.is_in_group("player") or ent.is_in_group("remote_players")) and ent.has_method("_setup_ship_visuals"):
					ent._setup_ship_visuals()

func open():
	visible = true
	global_position = (get_viewport_rect().size - size) / 2.0
