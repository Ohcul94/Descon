extends Control

# SettingsUI.gd (v1.1 - 7 Slots Unificados) 

signal closed

var _is_binding: bool = false
var _binding_action: String = ""
var _binding_label: Button = null

func _ready():
	add_to_group("inventory_ui") # v2.6: Unir al grupo de bloqueo global de UI
	add_to_group("settings_ui")  # Para escalado dinámico de fuentes
	_setup_ui()
	visible = false

func _setup_ui():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	
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
	if not get_viewport().size_changed.is_connected(_update_size):
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
	
	# Botón de Cerrar [X] - Agrandado para celulares
	var x_btn = Button.new()
	x_btn.text = " X "
	x_btn.custom_minimum_size = Vector2(50, 50)
	x_btn.add_theme_font_size_override("font_size", 16)
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
	scroll_game.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	
	# --- SELECTOR DE PLATAFORMA ---
	var plat_label = Label.new()
	plat_label.text = "🎮 SELECCIONAR PLATAFORMA DE CONTROL:"
	plat_label.add_theme_font_size_override("font_size", 14)
	plat_label.add_theme_color_override("font_color", Color.YELLOW)
	game_vbox.add_child(plat_label)
	
	var plat_option = OptionButton.new()
	plat_option.add_item("MODO PC (Mouse & Teclado)", 0)
	plat_option.add_item("MODO CELULAR (Joystick & MOBA)", 1)
	plat_option.selected = 1 if SettingsManager.mobile_mode else 0
	game_vbox.add_child(plat_option)
	
	game_vbox.add_child(HSeparator.new())

	# --- CONTENEDORES DE CONFIGURACIÓN ---
	var pc_config = VBoxContainer.new()
	pc_config.visible = not SettingsManager.mobile_mode
	game_vbox.add_child(pc_config)
	
	var mob_config_root = VBoxContainer.new()
	mob_config_root.visible = SettingsManager.mobile_mode
	game_vbox.add_child(mob_config_root)

	# --- DETALLE PC ---
	var pc_header = Label.new()
	pc_header.text = "🖥️ AJUSTES MODO PC"
	pc_header.add_theme_color_override("font_color", Color.CYAN)
	pc_config.add_child(pc_header)
	
	var pc_desc = Label.new()
	pc_desc.text = "Control clásico. El disparo va hacia el cursor del mouse."
	pc_desc.add_theme_font_size_override("font_size", 10)
	pc_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	pc_config.add_child(pc_desc)
	
	var player = get_tree().get_first_node_in_group("player")
	var cast_hbox = HBoxContainer.new()
	cast_hbox.add_theme_constant_override("separation", 20)
	pc_config.add_child(cast_hbox)
	
	var cast_vbox = VBoxContainer.new()
	cast_hbox.add_child(cast_vbox)
	
	var cast_label = Label.new()
	cast_label.text = "MODO DE LANZAMIENTO (PC):"
	cast_vbox.add_child(cast_label)
	
	var cast_option = OptionButton.new()
	cast_option.add_item("Quick Cast (Instantáneo)", 0)
	cast_option.add_item("On Release (Al soltar)", 1)
	cast_option.add_item("Normal Cast (Aim & Click)", 2)
	
	if player and player.get("_skill_controller"):
		cast_option.selected = player._skill_controller.config.cast_mode
	elif get_node_or_null("/root/SettingsManager"):
		cast_option.selected = SettingsManager.cast_mode_cache
	
	cast_option.item_selected.connect(_on_cast_mode_changed)
	cast_vbox.add_child(cast_option)

	# --- DETALLE MÓVIL ---
	var mob_header = Label.new()
	mob_header.text = "📱 AJUSTES MODO CELULAR"
	mob_header.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	mob_config_root.add_child(mob_header)

	var sens_vbox = VBoxContainer.new()
	mob_config_root.add_child(sens_vbox)
	
	var sens_lbl = Label.new()
	sens_lbl.text = "SENSIBILIDAD DE APUNTADO (DRAG):"
	sens_vbox.add_child(sens_lbl)
	
	var sens_slider = HSlider.new()
	sens_slider.min_value = 0.2; sens_slider.max_value = 3.0; sens_slider.step = 0.1
	sens_slider.value = SettingsManager.mobile_aim_sensitivity
	sens_slider.value_changed.connect(func(val):
		SettingsManager.mobile_aim_sensitivity = val
		SettingsManager.save_settings()
	)
	sens_vbox.add_child(sens_slider)
	
	var sens_hint = Label.new()
	sens_hint.text = "Ajusta qué tan lejos llega la mira al arrastrar el dedo."
	sens_hint.add_theme_font_size_override("font_size", 10)
	sens_hint.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6, 1))
	sens_vbox.add_child(sens_hint)
	
	mob_config_root.add_child(HSeparator.new())
	
	var inv_check = CheckButton.new()
	inv_check.text = "INVERTIR EJE Y (APUNTADO)"
	inv_check.button_pressed = SettingsManager.mobile_invert_y
	inv_check.toggled.connect(func(v):
		SettingsManager.mobile_invert_y = v
		SettingsManager.save_settings()
	)
	mob_config_root.add_child(inv_check)

	# CONECTAR SELECTOR
	plat_option.item_selected.connect(func(idx):
		var is_mob = (idx == 1)
		SettingsManager.mobile_mode = is_mob
		SettingsManager.save_settings()
		
		pc_config.visible = not is_mob
		mob_config_root.visible = is_mob
		
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("_update_joystick_visibility"):
			hud._update_joystick_visibility()
	)
	
	game_vbox.add_child(HSeparator.new())

	
	# TECLAS
	var keys_label = Label.new()
	keys_label.text = "ASIGNACIÓN DE TECLAS:"
	game_vbox.add_child(keys_label)
	
	var keys_vbox = VBoxContainer.new()
	game_vbox.add_child(keys_vbox)
	
	var slots = {
		"slot_1": "SLOT 1 (LÁSER)", "slot_2": "SLOT 2 (MISIL)", "slot_3": "SLOT 3 (MINA)",
		"slot_4": "SLOT 4 (HABILIDAD 1)", "slot_5": "SLOT 5 (HABILIDAD 2)", 
		"slot_6": "SLOT 6 (HABILIDAD 3)", "slot_7": "SLOT 7 (HABILIDAD 4)",
		"auto_target_self": "AUTO-LANZAR HABILIDADES",
		"ui_menu": "MENÚ DE SISTEMA (ESC)", "ui_inventory": "INVENTARIO (F1)", "ui_battlepass": "PASE DE BATALLA (F4)",
		"ui_events": "MENÚ DE EVENTOS (F2)",
		"ui_housing": "MENÚ DE HOUSING (F3)",
		"ui_map": "MAPA (M)", "ui_party": "EQUIPO (P)", "ui_pvp_toggle": "MODO COMBATE (C)",
		"portal_jump": "INGRESAR AL PORTAL",
		"toggle_camera_projection": "CAMBIAR PERSPECTIVA (CÁMARA)",
		"toggle_free_camera": "MODO CÁMARA LIBRE 3D",
		"toggle_orbit_mode": "ORBITAR / PANEO (CÁMARA LIBRE)",
		"loot_claim": "ABRIR BOTÍN / COFRE",
		"chat_toggle": "ABRIR / CERRAR CHAT"
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
	

	# --- AJUSTES DE CONTROL PC ---
	var sens_pc_label = Label.new()
	sens_pc_label.text = "AJUSTES DE PRECISIÓN (PC):"
	sens_pc_label.add_theme_color_override("font_color", Color.CYAN)
	pc_config.add_child(sens_pc_label)
	
	var click_lbl = Label.new()
	click_lbl.text = "SENSIBILIDAD DE CLICK (MOVIMIENTO):"
	pc_config.add_child(click_lbl)
	var click_slider = HSlider.new()
	click_slider.min_value = 0.5; click_slider.max_value = 2.0; click_slider.step = 0.1
	if get_node_or_null("/root/SettingsManager"): click_slider.value = SettingsManager.click_sensitivity
	click_slider.value_changed.connect(func(val): SettingsManager.click_sensitivity = val; SettingsManager.save_settings())
	pc_config.add_child(click_slider)

	# ========================== TAB 2: GRÁFICOS Y ACCESIBILIDAD ==========================
	var scroll_gfx = ScrollContainer.new()
	scroll_gfx.name = "GRÁFICOS"
	scroll_gfx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_gfx)
	
	var margin_gfx = MarginContainer.new()
	margin_gfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_gfx.add_theme_constant_override("margin_left", 20)
	margin_gfx.add_theme_constant_override("margin_right", 20)
	margin_gfx.add_theme_constant_override("margin_top", 20)
	scroll_gfx.add_child(margin_gfx)
	
	var gfx_vbox = VBoxContainer.new()
	gfx_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx_vbox.add_theme_constant_override("separation", 12)
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
	
	# LÍMITE DE FPS
	var fps_lbl = Label.new()
	fps_lbl.text = "LÍMITE DE FPS:"
	gfx_vbox.add_child(fps_lbl)
	
	var fps_option = OptionButton.new()
	fps_option.add_item("30 FPS", 0)
	fps_option.add_item("60 FPS (Por Defecto)", 1)
	fps_option.add_item("90 FPS", 2)
	fps_option.add_item("120 FPS", 3)
	
	var fps_idx = 1
	if get_node_or_null("/root/SettingsManager"):
		match SettingsManager.fps_limit:
			30: fps_idx = 0
			60: fps_idx = 1
			90: fps_idx = 2
			120: fps_idx = 3
	fps_option.selected = fps_idx
	fps_option.item_selected.connect(_on_fps_limit_changed)
	gfx_vbox.add_child(fps_option)
	
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
	row_flash.add_theme_constant_override("separation", 10)
	gfx_vbox.add_child(row_flash)
	
	var flash_check = CheckBox.new()
	flash_check.text = ""
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
	row_shake.add_theme_constant_override("separation", 10)
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

	gfx_vbox.add_child(HSeparator.new())

	# CÁMARA 3D
	var row_cam = HBoxContainer.new()
	row_cam.add_theme_constant_override("separation", 10)
	gfx_vbox.add_child(row_cam)

	var cam_check = CheckBox.new()
	cam_check.text = ""
	cam_check.add_theme_stylebox_override("normal", check_style)
	cam_check.add_theme_stylebox_override("pressed", check_style)
	cam_check.add_theme_stylebox_override("hover", check_style)
	if get_node_or_null("/root/SettingsManager"): cam_check.button_pressed = not SettingsManager.cam_use_orthogonal
	cam_check.toggled.connect(func(val):
		var is_3d = val
		SettingsManager.camera_use_orthogonal = not is_3d
		SettingsManager.cam_use_orthogonal = not is_3d
		SettingsManager.save_settings()
		var map_node = get_tree().get_first_node_in_group("map")
		if map_node and map_node.has_method("set_camera_2d_mode"):
			map_node.set_camera_2d_mode(not is_3d)
	)
	row_cam.add_child(cam_check)

	var cam_lbl = Label.new()
	cam_lbl.text = "CÁMARA 3D"
	row_cam.add_child(cam_lbl)

	# ESTRELLAS EN EL CIELO
	var row_stars = HBoxContainer.new()
	row_stars.add_theme_constant_override("separation", 10)
	gfx_vbox.add_child(row_stars)

	var stars_check = CheckBox.new()
	stars_check.text = ""
	stars_check.add_theme_stylebox_override("normal", check_style)
	stars_check.add_theme_stylebox_override("pressed", check_style)
	stars_check.add_theme_stylebox_override("hover", check_style)
	if get_node_or_null("/root/SettingsManager"):
		stars_check.button_pressed = SettingsManager.show_stars
	stars_check.toggled.connect(func(val):
		SettingsManager.show_stars = val
		SettingsManager.save_settings()
		var map_node = get_tree().get_first_node_in_group("map")
		if map_node and map_node.has_method("update_sky_dome_visibility"):
			map_node.update_sky_dome_visibility()
	)
	row_stars.add_child(stars_check)

	var stars_lbl = Label.new()
	stars_lbl.text = "ACTIVAR ESTRELLAS EN EL CIELO"
	row_stars.add_child(stars_lbl)

	# Bottom spacer para forzar scroll en cualquier pantalla
	var bot_spacer = Control.new()
	bot_spacer.custom_minimum_size.y = 200
	gfx_vbox.add_child(bot_spacer)

	# ========================== TAB 3: SONIDO (PRÓXIMAMENTE) ==========================
	var scroll_audio = ScrollContainer.new()
	scroll_audio.name = "SONIDO"
	scroll_audio.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	scroll_hud.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	
	var hud_ref = get_tree().get_first_node_in_group("hud")
	var layouts_data = []
	if hud_ref and hud_ref.get("_hud_layouts"):
		layouts_data = hud_ref._hud_layouts
		
	var active_idx = -1
	if hud_ref and hud_ref.get("active_slot_index") != null:
		active_idx = hud_ref.active_slot_index

	for i in range(4):
		var slot_data = {"name": "Slot %d" % (i+1)}
		if i < layouts_data.size(): slot_data = layouts_data[i]
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		hud_vbox.add_child(row)
		
		# v266.300: Indicador de Slot Activo
		var active_indicator = Label.new()
		active_indicator.text = " ▶ " if i == active_idx else "   "
		active_indicator.add_theme_color_override("font_color", Color.YELLOW)
		row.add_child(active_indicator)
		
		var name_edit = LineEdit.new()
		name_edit.text = slot_data.name
		name_edit.placeholder_text = "Nombre del Layout"
		name_edit.custom_minimum_size.x = 130
		if i == active_idx: name_edit.add_theme_color_override("font_color", Color.YELLOW)
		row.add_child(name_edit)
		
		var apply_btn = Button.new()
		apply_btn.text = "USAR"
		apply_btn.custom_minimum_size.x = 60
		apply_btn.modulate = Color.GREEN
		apply_btn.pressed.connect(func():
			if hud_ref: hud_ref.apply_layout_slot(i)
			refresh_ui() # Refrescar para ver el indicador sin perder el tab
		)
		row.add_child(apply_btn)
		
		var edit_btn = Button.new()
		edit_btn.text = "EDITAR"
		edit_btn.modulate = Color.CYAN
		edit_btn.pressed.connect(func():
			if hud_ref: hud_ref.toggle_hud_editing(i)
		)
		row.add_child(edit_btn)

	# ========================== TAB 5: FUENTES Y TEXTOS ==========================
	var scroll_font = ScrollContainer.new()
	scroll_font.name = "FUENTES"
	scroll_font.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_font)
	
	var margin_font = MarginContainer.new()
	margin_font.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_font.add_theme_constant_override("margin_left", 20)
	margin_font.add_theme_constant_override("margin_right", 20)
	margin_font.add_theme_constant_override("margin_top", 20)
	scroll_font.add_child(margin_font)
	
	var font_vbox = VBoxContainer.new()
	font_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_vbox.add_theme_constant_override("separation", 15)
	margin_font.add_child(font_vbox)
	
	var font_title = Label.new()
	font_title.text = "CONFIGURACIÓN DE TAMAÑOS DE TEXTO:"
	font_title.add_theme_color_override("font_color", Color.CYAN)
	font_vbox.add_child(font_title)
	
	var make_font_slider = func(label_text: String, min_v: int, max_v: int, current_v: int, key_name: String):
		var bold_key = key_name.replace("font_size_", "bold_")
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		font_vbox.add_child(row)
		
		var lbl = Label.new()
		lbl.text = label_text
		lbl.custom_minimum_size.x = 220
		row.add_child(lbl)
		
		var slider = HSlider.new()
		slider.min_value = min_v
		slider.max_value = max_v
		slider.step = 1
		slider.value = current_v
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		
		var val_lbl = Label.new()
		val_lbl.text = str(current_v) + " px"
		val_lbl.custom_minimum_size.x = 50
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		
		var bold_chk = CheckBox.new()
		bold_chk.text = "Negrita"
		bold_chk.button_pressed = SettingsManager.get(bold_key)
		row.add_child(bold_chk)
		
		slider.value_changed.connect(func(val):
			var i_val = int(val)
			val_lbl.text = str(i_val) + " px"
			SettingsManager.set(key_name, i_val)
			SettingsManager.save_settings()
			
			if key_name == "font_size_menus":
				SettingsManager.apply_menu_fonts_live()
			else:
				SettingsManager.update_entity_tags_live()
		)
		
		bold_chk.toggled.connect(func(pressed):
			SettingsManager.set(bold_key, pressed)
			SettingsManager.save_settings()
			
			if bold_key == "bold_menus":
				SettingsManager.apply_menu_fonts_live()
			else:
				SettingsManager.update_entity_tags_live()
		)

	make_font_slider.call("Nombre de Jugadores:", 8, 24, SettingsManager.font_size_player_name, "font_size_player_name")
	make_font_slider.call("Vida/Escudo Jugadores:", 6, 20, SettingsManager.font_size_player_stats, "font_size_player_stats")
	make_font_slider.call("Nombre de Enemigos:", 8, 24, SettingsManager.font_size_enemy_name, "font_size_enemy_name")
	make_font_slider.call("Vida/Escudo Enemigos:", 6, 20, SettingsManager.font_size_enemy_stats, "font_size_enemy_stats")
	make_font_slider.call("Burbujas de Chat:", 6, 24, SettingsManager.font_size_chat_bubble, "font_size_chat_bubble")
	make_font_slider.call("Fuentes de Menús (Base):", 8, 24, SettingsManager.font_size_menus, "font_size_menus")

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

func _on_fps_limit_changed(idx: int):
	var fps = 60
	match idx:
		0: fps = 30
		1: fps = 60
		2: fps = 90
		3: fps = 120
	if get_node_or_null("/root/SettingsManager"):
		SettingsManager.apply_fps_limit(fps)
		SettingsManager.save_settings()

func close():
	SettingsManager.save_settings()
	visible = false
	if get_parent() is CanvasLayer:
		get_parent().visible = false
	closed.emit()

func open():
	_setup_ui()
	visible = true
	if get_parent() is CanvasLayer:
		get_parent().visible = true
	
	# v266.131: Esperar un frame para que Godot calcule el nuevo tamaño mínimo
	await get_tree().process_frame
	_update_size()

# v266.310: Refrescar la UI manteniendo el Tab actual
func refresh_ui():
	var current_tab = 0
	var tabs = find_child("*TabContainer*", true, false)
	if tabs: current_tab = tabs.current_tab
	
	_setup_ui()
	
	tabs = find_child("*TabContainer*", true, false)
	if tabs: tabs.current_tab = current_tab

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
