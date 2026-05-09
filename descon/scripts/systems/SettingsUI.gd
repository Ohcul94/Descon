extends Control

# SettingsUI.gd (v1.1 - 7 Slots Unificados)

signal closed

var _is_binding: bool = false
var _binding_action: String = ""
var _binding_label: Button = null

func _ready():
	add_to_group("inventory_ui") # v2.6: Unir al grupo de bloqueo global de UI
	_setup_ui()
	visible = false

func _setup_ui():
	for child in get_children(): child.queue_free()
	
	# v2.3: Capa de bloqueo total (Click-through prevention)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Fondo Oscurecedor (Bloquea clicks al minimapa/chat)
	var bg = ColorRect.new()
	bg.name = "Dimmer"
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Panel Central (El menú real)
	var main_panel = PanelContainer.new()
	main_panel.name = "MainPanel"
	add_child(main_panel)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color.CYAN
	style.set_corner_radius_all(8)
	main_panel.add_theme_stylebox_override("panel", style)
	
	_update_size()
	get_viewport().size_changed.connect(_update_size)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# Contenedor de Cabecera (Titulo + [X])
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	# Titulo
	var title = Label.new()
	title.text = "CONFIGURACIÓN DE JUEGO"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	
	# Botón de Cerrar [X]
	var x_btn = Button.new()
	x_btn.text = " X "
	x_btn.custom_minimum_size = Vector2(30, 30)
	x_btn.pressed.connect(func(): close())
	header.add_child(x_btn)
	
	vbox.add_child(HSeparator.new())
	
	# --- CONTENEDOR DE TABS (v2.0) ---
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)
	
	# ========================== TAB 1: JUEGO Y CONTROLES ==========================
	var scroll_game = ScrollContainer.new()
	scroll_game.name = "JUEGO Y TECLAS"
	tabs.add_child(scroll_game)
	
	var margin_game = MarginContainer.new()
	margin_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_game.add_theme_constant_override("margin_left", 20)
	margin_game.add_theme_constant_override("margin_right", 20)
	margin_game.add_theme_constant_override("margin_top", 20)
	scroll_game.add_child(margin_game)
	
	var game_vbox = VBoxContainer.new()
	game_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_vbox.add_theme_constant_override("separation", 10)
	margin_game.add_child(game_vbox)
	
	# MODO DE DISPARO
	var cast_label = Label.new()
	cast_label.text = "MODO DE LANZAMIENTO (CAST):"
	game_vbox.add_child(cast_label)
	
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
	game_vbox.add_child(cast_option)
	
	game_vbox.add_child(HSeparator.new())
	
	# TECLAS
	var keys_label = Label.new()
	keys_label.text = "ASIGNACIÓN DE TECLAS:"
	game_vbox.add_child(keys_label)
	
	var keys_vbox = VBoxContainer.new()
	game_vbox.add_child(keys_vbox)
	
	var slots = {
		"slot_1": "SLOT 1 (LÁSER)", "slot_2": "SLOT 2 (MISIL)", "slot_3": "SLOT 3 (MINA)",
		"slot_4": "SLOT 4", "slot_5": "SLOT 5", "slot_6": "SLOT 6", "slot_7": "SLOT 7",
		"ui_menu": "MENÚ DE SISTEMA (ESC)", "ui_inventory": "INVENTARIO (F1)",
		"ui_map": "MAPA (M)", "ui_party": "EQUIPO (P)", "ui_pvp_toggle": "MODO COMBATE (C)"
	}


	
	for action in slots:
		var row = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = slots[action]
		name_lbl.custom_minimum_size.x = 160
		row.add_child(name_lbl)
		
		var btn = Button.new()
		btn.text = _get_action_key_text(action)
		btn.custom_minimum_size.x = 120
		btn.pressed.connect(_on_bind_pressed.bind(action, btn))
		row.add_child(btn)
		keys_vbox.add_child(row)
		
	game_vbox.add_child(HSeparator.new())
	

	# --- AJUSTES DE CONTROL (v2.1) ---
	var sens_label = Label.new()
	sens_label.text = "AJUSTES DE PRECISIÓN Y CONTROL:"
	sens_label.add_theme_color_override("font_color", Color.CYAN)
	game_vbox.add_child(sens_label)
	
	# SENSIBILIDAD DE CLICK (MOVIMIENTO)
	var click_lbl = Label.new()
	click_lbl.text = "SENSIBILIDAD DE CLICK (RESPUESTA AL MOVERTE):"
	game_vbox.add_child(click_lbl)
	var click_slider = HSlider.new()
	click_slider.min_value = 0.5; click_slider.max_value = 2.0; click_slider.step = 0.1
	if get_node_or_null("/root/SettingsManager"): click_slider.value = SettingsManager.click_sensitivity
	click_slider.value_changed.connect(func(val): SettingsManager.click_sensitivity = val; SettingsManager.save_settings())
	game_vbox.add_child(click_slider)

	# MAGNETISMO DE HABILIDADES
	var mag_lbl = Label.new()
	mag_lbl.text = "MAGNETISMO DE HABILIDADES (AUTO-APUNTADO):"
	game_vbox.add_child(mag_lbl)
	var mag_slider = HSlider.new()
	mag_slider.min_value = 0.5; mag_slider.max_value = 3.0; mag_slider.step = 0.1
	if get_node_or_null("/root/SettingsManager"): mag_slider.value = SettingsManager.skill_magnetism
	mag_slider.value_changed.connect(func(val): SettingsManager.skill_magnetism = val; SettingsManager.save_settings())
	game_vbox.add_child(mag_slider)

	# ========================== TAB 2: GRÁFICOS Y ACCESIBILIDAD ==========================
	var scroll_gfx = ScrollContainer.new()
	scroll_gfx.name = "GRÁFICOS"
	tabs.add_child(scroll_gfx)
	
	var margin_gfx = MarginContainer.new()
	margin_gfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_gfx.add_theme_constant_override("margin_left", 20)
	margin_gfx.add_theme_constant_override("margin_right", 20)
	margin_gfx.add_theme_constant_override("margin_top", 20)
	scroll_gfx.add_child(margin_gfx)
	
	var gfx_vbox = VBoxContainer.new()
	gfx_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx_vbox.add_theme_constant_override("separation", 15)
	margin_gfx.add_child(gfx_vbox)
	
	# CALIDAD GRÁFICA
	var gfx_label = Label.new()
	gfx_label.text = "CALIDAD DE MODELOS 3D:"
	gfx_vbox.add_child(gfx_label)
	
	var gfx_option = OptionButton.new()
	gfx_option.add_item("Baja (Rendimiento)", 0)
	gfx_option.add_item("Media (Recomendado)", 1)
	gfx_option.add_item("Alta (PCs Potentes)", 2)
	
	if get_node_or_null("/root/SettingsManager"):
		gfx_option.selected = SettingsManager.get_graphics_quality()
	
	gfx_option.item_selected.connect(_on_graphics_quality_changed)
	gfx_vbox.add_child(gfx_option)
	
	gfx_vbox.add_child(HSeparator.new())
	
	# v2.9: Estilo para Checkboxes (Reborde visible SOLO en la caja)
	var check_style = StyleBoxFlat.new()
	check_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	check_style.border_width_left = 2; check_style.border_width_top = 2
	check_style.border_width_right = 2; check_style.border_width_bottom = 2
	check_style.border_color = Color.CYAN
	check_style.set_corner_radius_all(4)
	
	# EFECTO DE PARPADEO
	var row_flash = HBoxContainer.new()
	row_flash.add_theme_constant_override("separation", 15)
	gfx_vbox.add_child(row_flash)
	
	var flash_check = CheckBox.new()
	flash_check.text = "" # Sin texto para que el estilo sea solo el recuadro
	flash_check.add_theme_stylebox_override("normal", check_style)
	flash_check.add_theme_stylebox_override("pressed", check_style)
	flash_check.add_theme_stylebox_override("hover", check_style)
	if get_node_or_null("/root/SettingsManager"): flash_check.button_pressed = SettingsManager.hit_flash_enabled
	flash_check.toggled.connect(func(val): SettingsManager.hit_flash_enabled = val; SettingsManager.save_settings())
	row_flash.add_child(flash_check)
	
	var flash_lbl = Label.new()
	flash_lbl.text = "EFECTO DE PARPADEO (RECIBIR DAÑO)"
	row_flash.add_child(flash_lbl)
	
	# TEMBLOR DE CÁMARA
	var row_shake = HBoxContainer.new()
	row_shake.add_theme_constant_override("separation", 15)
	gfx_vbox.add_child(row_shake)
	
	var shake_check = CheckBox.new()
	shake_check.text = ""
	shake_check.add_theme_stylebox_override("normal", check_style)
	shake_check.add_theme_stylebox_override("pressed", check_style)
	shake_check.add_theme_stylebox_override("hover", check_style)
	if get_node_or_null("/root/SettingsManager"): shake_check.button_pressed = SettingsManager.camera_shake_enabled
	shake_check.toggled.connect(func(val): SettingsManager.camera_shake_enabled = val; SettingsManager.save_settings())
	row_shake.add_child(shake_check)
	
	var shake_lbl = Label.new()
	shake_lbl.text = "TEMBLOR DE CÁMARA"
	row_shake.add_child(shake_lbl)

	
	var shake_slider = HSlider.new()
	shake_slider.min_value = 0.0; shake_slider.max_value = 2.0; shake_slider.step = 0.1
	if get_node_or_null("/root/SettingsManager"): shake_slider.value = SettingsManager.camera_shake_intensity
	shake_slider.value_changed.connect(func(val): SettingsManager.camera_shake_intensity = val; SettingsManager.save_settings())
	gfx_vbox.add_child(shake_slider)

	# ========================== TAB 3: SONIDO (PRÓXIMAMENTE) ==========================
	var scroll_audio = ScrollContainer.new()
	scroll_audio.name = "SONIDO"
	tabs.add_child(scroll_audio)
	
	var margin_audio = MarginContainer.new()
	margin_audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_audio.add_theme_constant_override("margin_left", 20)
	margin_audio.add_theme_constant_override("margin_right", 20)
	margin_audio.add_theme_constant_override("margin_top", 20)
	scroll_audio.add_child(margin_audio)
	
	var audio_vbox = VBoxContainer.new()
	audio_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_audio.add_child(audio_vbox)
	
	var audio_msg = Label.new()
	audio_msg.text = "\n\nSISTEMA DE AUDIO EN DESARROLLO...\n\nPRÓXIMAMENTE PODRÁS CONFIGURAR EL VOLUMEN\nDE SFX, MÚSICA Y ENTORNO."
	audio_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_msg.modulate.a = 0.5
	audio_vbox.add_child(audio_msg)

	# ========================== TAB 4: INTERFAZ Y LAYOUT ==========================
	var scroll_hud = ScrollContainer.new()
	scroll_hud.name = "INTERFAZ Y LAYOUT"
	tabs.add_child(scroll_hud)
	
	var margin_hud = MarginContainer.new()
	margin_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_hud.add_theme_constant_override("margin_left", 20)
	margin_hud.add_theme_constant_override("margin_right", 20)
	margin_hud.add_theme_constant_override("margin_top", 20)
	scroll_hud.add_child(margin_hud)
	
	var hud_vbox = VBoxContainer.new()
	hud_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_vbox.add_theme_constant_override("separation", 15)
	margin_hud.add_child(hud_vbox)
	
	var layout_lbl = Label.new()
	layout_lbl.text = "PERSONALIZACIÓN DE INTERFAZ:"
	layout_lbl.add_theme_color_override("font_color", Color.CYAN)
	hud_vbox.add_child(layout_lbl)
	
	var edit_hud_btn = Button.new()
	edit_hud_btn.text = "EDITAR LAYOUT HUD (MOVER BOTONES)"
	edit_hud_btn.custom_minimum_size.y = 40
	edit_hud_btn.modulate = Color(0.5, 1.0, 1.0)
	edit_hud_btn.pressed.connect(func():
		close()
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toggle_hud_editing"):
			hud.toggle_hud_editing()
	)
	hud_vbox.add_child(edit_hud_btn)
	
	var hud_desc = Label.new()
	hud_desc.text = "Al activar esta opción, podrás arrastrar libremente los slots de habilidades en tu pantalla.\nUna vez en Modo Edición, verás el botón 'Restaurar de Fábrica' por si quieres volver a la formación original."
	hud_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	hud_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hud_vbox.add_child(hud_desc)

	# ========================== PIE DE PÁGINA (BOTONES COMUNES) ==========================

	vbox.add_child(HSeparator.new())
	
	var reset_btn = Button.new()
	reset_btn.text = "REESTABLECER VALORES DE FÁBRICA"
	reset_btn.modulate = Color.ORANGE
	reset_btn.pressed.connect(func():
		SettingsManager.reset_to_factory()
		_setup_ui()
	)
	vbox.add_child(reset_btn)
	
	var close_btn = Button.new()
	close_btn.text = "CERRAR Y GUARDAR"
	close_btn.custom_minimum_size.y = 40
	close_btn.pressed.connect(func(): 
		close()
	)
	vbox.add_child(close_btn)

func _get_action_key_text(action: String) -> String:
	if not InputMap.has_action(action): return "NO DEFINIDA"
	var events = InputMap.action_get_events(action)
	if events.size() > 0:
		var txt = events[0].as_text().replace(" (Physical)", "")
		if txt.contains("Physical"): txt = txt.replace("Physical", "").strip_edges()
		if txt.begins_with("Mouse Button"): txt = "M" + txt.replace("Mouse Button ", "")
		return txt.to_upper()
	return "NINGUNA"


func _on_bind_pressed(action: String, label_node: Button):
	if _is_binding: return
	_is_binding = true
	_binding_action = action
	_binding_label = label_node
	label_node.text = "[ PULSA TECLA ]"
	label_node.modulate = Color.YELLOW

func _input(event):
	# v2.8: Cerrar con ESC
	if visible and event.is_action_pressed("ui_menu"):
		close()
		get_viewport().set_input_as_handled()
		return

	if _is_binding and event is InputEventKey and event.pressed:
		_rebind_action(_binding_action, event)
		_is_binding = false
		_binding_label.text = event.as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()

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

func close():
	SettingsManager.save_settings()
	visible = false
	if get_parent() is CanvasLayer:
		get_parent().visible = false
	closed.emit()

func open():
	visible = true
	if get_parent() is CanvasLayer:
		get_parent().visible = true
	_update_size()

func _update_size():
	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = (screen_size - r_size) / 2.0
	
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var panel = get_node_or_null("MainPanel")
	if panel:
		panel.size = r_size
		panel.position = r_pos
		panel.custom_minimum_size = r_size
