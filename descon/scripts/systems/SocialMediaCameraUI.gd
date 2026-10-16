extends Control

signal mode_changed(mode: int)
signal platform_changed(platform: int)
signal recording_toggled(recording: bool)
signal config_changed(config: Dictionary)

@export var camera_system: SocialCameraSystem = null

# Ventana modal reconocida por Player.gd y MainHUD.gd
var window_panel: PanelContainer = null

var _scroll_container: ScrollContainer = null
var _expanded_content: VBoxContainer = null
var _pip_container: SubViewportContainer = null
var _pip_aspect_box: PanelContainer = null
var _pip_status_lbl: Label = null
var _pip_format_badge: Label = null
var _pip_res_badge: Label = null
var _pip_mouse_dragging: bool = false
var _mode_buttons: Array[Button] = []
var _platform_buttons: Array[Button] = []
var _recording_btn: Button = null
var _pip_toggle_btn: Button = null
var _expand_btn: Button = null
var _mode_display: Label = null
var _platform_display: Label = null
var _boss_selector: OptionButton = null
var _cached_bosses: Array[Dictionary] = []
var _slider_labels: Dictionary = {}
var _dynamic_settings_box: VBoxContainer = null
var _dynamic_settings_title: Label = null

var _is_expanded: bool = true
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready():
	add_to_group("camera_ui")
	add_to_group("social_camera_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	_build_ui()
	_update_visibility()
	
	call_deferred("_get_camera_system")

func _get_camera_system() -> SocialCameraSystem:
	if not is_instance_valid(camera_system):
		var smc = get_node_or_null("/root/SocialCamera")
		if is_instance_valid(smc) and smc is SocialCameraSystem:
			set_camera_system(smc)
	return camera_system

func _unhandled_input(event: InputEvent):
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()

func open_panel():
	visible = true
	_is_expanded = true
	_update_visibility()
	move_to_front()
	
	var cam = _get_camera_system()
	if cam:
		if not cam.is_active:
			cam._activate_camera()
		update_mode_display(int(cam.current_mode))
		update_platform_display(int(cam.current_platform))
		set_recording_state(cam.is_recording)
		_setup_pip_preview()
		_refresh_boss_list()
	
	if is_instance_valid(window_panel):
		_ensure_window_in_bounds()
		window_panel.move_to_front()

func close_panel():
	visible = false

func toggle_panel():
	if visible:
		close_panel()
	else:
		open_panel()

func _ensure_window_in_bounds():
	if not is_instance_valid(window_panel): return
	var vp_size = get_viewport_rect().size
	var target_w = min(420.0, vp_size.x * 0.95)
	var target_h = min(620.0, vp_size.y * 0.94)
	window_panel.custom_minimum_size = Vector2(target_w, target_h)
	
	var cur_pos = window_panel.position
	if cur_pos.x < 10 or cur_pos.x > vp_size.x - 100 or cur_pos.y < 20 or cur_pos.y > vp_size.y - 80:
		window_panel.position = Vector2(30, 50)
	else:
		window_panel.position.x = clampf(cur_pos.x, 10.0, max(10.0, vp_size.x - target_w))
		window_panel.position.y = clampf(cur_pos.y, 10.0, max(10.0, vp_size.y - target_h))

func _build_ui():
	window_panel = PanelContainer.new()
	window_panel.name = "CameraWindow"
	window_panel.custom_minimum_size = Vector2(420, 620)
	window_panel.size = Vector2(420, 620)
	window_panel.position = Vector2(30, 50)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	window_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
	)
	
	var root_sb = StyleBoxFlat.new()
	root_sb.bg_color = Color(0.015, 0.025, 0.045, 1.0) # Sólido absoluto
	root_sb.border_width_left = 2; root_sb.border_width_top = 2
	root_sb.border_width_right = 2; root_sb.border_width_bottom = 2
	root_sb.border_color = Color(0.0, 0.85, 1.0, 0.95)
	root_sb.set_corner_radius_all(8)
	root_sb.content_margin_left = 12; root_sb.content_margin_right = 12
	root_sb.content_margin_top = 10; root_sb.content_margin_bottom = 12
	root_sb.shadow_size = 24
	root_sb.shadow_color = Color(0, 0, 0, 0.9)
	window_panel.add_theme_stylebox_override("panel", root_sb)
	add_child(window_panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainContainer"
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	window_panel.add_child(main_vbox)
	
	# --- BARRA DE TÍTULO ---
	var title_bar = PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.custom_minimum_size = Vector2(0, 36)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	
	var title_sb = StyleBoxFlat.new()
	title_sb.bg_color = Color(0.025, 0.05, 0.09, 1.0)
	title_sb.border_width_bottom = 1
	title_sb.border_color = Color(0.0, 0.8, 1.0, 0.45)
	title_sb.set_corner_radius_all(4)
	title_sb.content_margin_left = 8; title_sb.content_margin_right = 8
	title_sb.content_margin_top = 4; title_sb.content_margin_bottom = 4
	title_bar.add_theme_stylebox_override("panel", title_sb)
	main_vbox.add_child(title_bar)
	
	var title_hbox = HBoxContainer.new()
	title_hbox.name = "TitleHBox"
	title_hbox.add_theme_constant_override("separation", 6)
	title_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_hbox)
	
	var drag_icon = Label.new()
	drag_icon.text = "⣿"
	drag_icon.add_theme_font_size_override("font_size", 14)
	drag_icon.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0, 0.85))
	drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_hbox.add_child(drag_icon)
	
	var title_lbl = Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "🎥 CÁMARA & GRABACIÓN (F7)"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_hbox.add_child(title_lbl)
	
	# Botón Toggle PiP / Pantalla Completa
	_pip_toggle_btn = Button.new()
	_pip_toggle_btn.name = "PipToggleBtn"
	_pip_toggle_btn.text = "🖼️ PiP"
	_pip_toggle_btn.tooltip_text = "Alternar entre Recuadro PiP (jugar normal) y Pantalla Completa"
	_pip_toggle_btn.custom_minimum_size = Vector2(65, 26)
	_pip_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(_pip_toggle_btn, Color(0.08, 0.22, 0.35, 1.0))
	_pip_toggle_btn.pressed.connect(_on_pip_toggle_pressed)
	title_hbox.add_child(_pip_toggle_btn)
	
	# Botón REC
	_recording_btn = Button.new()
	_recording_btn.name = "RecordingBtn"
	_recording_btn.text = "⏺ REC"
	_recording_btn.tooltip_text = "Iniciar / Detener Grabación"
	_recording_btn.custom_minimum_size = Vector2(75, 26)
	_recording_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(_recording_btn, Color(0.8, 0.12, 0.12, 1.0))
	_recording_btn.pressed.connect(_on_recording_pressed)
	title_hbox.add_child(_recording_btn)
	
	# Botón Expandir / Minimizar
	_expand_btn = Button.new()
	_expand_btn.name = "ExpandBtn"
	_expand_btn.text = "▲"
	_expand_btn.tooltip_text = "Minimizar / Expandir opciones"
	_expand_btn.custom_minimum_size = Vector2(28, 26)
	_expand_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(_expand_btn, Color(0.08, 0.18, 0.28, 1.0))
	_expand_btn.pressed.connect(_on_expand_toggled)
	title_hbox.add_child(_expand_btn)
	
	# Botón Cerrar
	var close_btn = Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "✕"
	close_btn.tooltip_text = "Cerrar panel (F7 o ESC)"
	close_btn.custom_minimum_size = Vector2(28, 26)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(close_btn, Color(0.28, 0.08, 0.08, 1.0))
	close_btn.pressed.connect(close_panel)
	title_hbox.add_child(close_btn)
	
	# --- MONITOR EN VIVO (PICTURE-IN-PICTURE PREVIEW DINÁMICO) ---
	var monitor_frame = PanelContainer.new()
	monitor_frame.name = "MonitorFrame"
	monitor_frame.custom_minimum_size = Vector2(396, 230)
	monitor_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var mon_sb = StyleBoxFlat.new()
	mon_sb.bg_color = Color(0.015, 0.02, 0.035, 1.0)
	mon_sb.border_width_left = 1; mon_sb.border_width_top = 1
	mon_sb.border_width_right = 1; mon_sb.border_width_bottom = 1
	mon_sb.border_color = Color(0.0, 0.65, 0.85, 0.5)
	mon_sb.set_corner_radius_all(6)
	mon_sb.content_margin_left = 6; mon_sb.content_margin_right = 6
	mon_sb.content_margin_top = 4; mon_sb.content_margin_bottom = 6
	monitor_frame.add_theme_stylebox_override("panel", mon_sb)
	main_vbox.add_child(monitor_frame)
	
	var monitor_vbox = VBoxContainer.new()
	monitor_vbox.name = "MonitorVBox"
	monitor_vbox.add_theme_constant_override("separation", 4)
	monitor_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monitor_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monitor_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	monitor_frame.add_child(monitor_vbox)
	
	# Barra de información superior del monitor
	var monitor_top_bar = HBoxContainer.new()
	monitor_top_bar.name = "MonitorTopBar"
	monitor_top_bar.add_theme_constant_override("separation", 6)
	monitor_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monitor_vbox.add_child(monitor_top_bar)
	
	_pip_status_lbl = Label.new()
	_pip_status_lbl.name = "PiPStatus"
	_pip_status_lbl.text = "🔴 LIVE PiP"
	_pip_status_lbl.add_theme_font_size_override("font_size", 9)
	_pip_status_lbl.add_theme_color_override("font_color", Color(0.0, 1.0, 0.6, 0.95))
	_pip_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monitor_top_bar.add_child(_pip_status_lbl)
	
	var top_bar_spacer = Control.new()
	top_bar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monitor_top_bar.add_child(top_bar_spacer)
	
	_pip_format_badge = Label.new()
	_pip_format_badge.name = "PiPFormatBadge"
	_pip_format_badge.text = "▶ YOUTUBE (16:9)"
	_pip_format_badge.add_theme_font_size_override("font_size", 9)
	_pip_format_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
	_pip_format_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monitor_top_bar.add_child(_pip_format_badge)
	
	_pip_res_badge = Label.new()
	_pip_res_badge.name = "PiPResBadge"
	_pip_res_badge.text = "1920×1080"
	_pip_res_badge.add_theme_font_size_override("font_size", 9)
	_pip_res_badge.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0, 0.85))
	_pip_res_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monitor_top_bar.add_child(_pip_res_badge)
	
	# Etapa central con aspect ratio dinámico
	var monitor_stage = CenterContainer.new()
	monitor_stage.name = "MonitorStage"
	monitor_stage.custom_minimum_size = Vector2(384, 194)
	monitor_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monitor_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monitor_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	monitor_vbox.add_child(monitor_stage)
	
	_pip_aspect_box = PanelContainer.new()
	_pip_aspect_box.name = "PiPAspectBox"
	_pip_aspect_box.custom_minimum_size = Vector2(345, 194)
	_pip_aspect_box.size = Vector2(345, 194)
	_pip_aspect_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_pip_aspect_box.gui_input.connect(_on_pip_preview_gui_input)
	
	var box_sb = StyleBoxFlat.new()
	box_sb.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	box_sb.border_width_left = 2; box_sb.border_width_top = 2
	box_sb.border_width_right = 2; box_sb.border_width_bottom = 2
	box_sb.border_color = Color(0.0, 0.85, 1.0, 0.95)
	box_sb.set_corner_radius_all(6)
	box_sb.shadow_size = 12
	box_sb.shadow_color = Color(0.0, 0.7, 1.0, 0.3)
	_pip_aspect_box.add_theme_stylebox_override("panel", box_sb)
	monitor_stage.add_child(_pip_aspect_box)
	
	_pip_container = SubViewportContainer.new()
	_pip_container.name = "PiPContainer"
	_pip_container.stretch = true
	_pip_container.custom_minimum_size = Vector2(345, 194)
	_pip_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pip_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pip_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_pip_container.gui_input.connect(_on_pip_preview_gui_input)
	_pip_aspect_box.add_child(_pip_container)
	
	# --- BADGES DE ESTADO (Modo y Formato actual) ---
	var status_hbox = HBoxContainer.new()
	status_hbox.name = "StatusHBox"
	status_hbox.add_theme_constant_override("separation", 8)
	status_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_child(status_hbox)
	
	_mode_display = Label.new()
	_mode_display.name = "ModeDisplay"
	_mode_display.text = "MODO: LIBRE"
	_mode_display.add_theme_font_size_override("font_size", 10)
	_mode_display.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	_mode_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_hbox.add_child(_mode_display)
	
	_platform_display = Label.new()
	_platform_display.name = "PlatformDisplay"
	_platform_display.text = "YT 16:9 (1920×1080)"
	_platform_display.add_theme_font_size_override("font_size", 10)
	_platform_display.add_theme_color_override("font_color", Color(0.3, 0.95, 0.55, 1.0))
	_platform_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_platform_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_hbox.add_child(_platform_display)
	
	var sep = HSeparator.new()
	var sep_sb = StyleBoxLine.new()
	sep_sb.color = Color(0.0, 0.75, 1.0, 0.4)
	sep_sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(sep)
	
	# --- ÁREA SCROLLABLE PARA OPCIONES ---
	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "ScrollArea"
	_scroll_container.custom_minimum_size = Vector2(396, 320)
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_child(_scroll_container)
	
	_expanded_content = VBoxContainer.new()
	_expanded_content.name = "ExpandedContent"
	_expanded_content.add_theme_constant_override("separation", 10)
	_expanded_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_expanded_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll_container.add_child(_expanded_content)
	
	# 1. SECCIÓN: OBJETIVO DE CÁMARA (TARGET)
	var boss_section = _create_section("🎯 OBJETIVO DE CÁMARA (TARGET)")
	_expanded_content.add_child(boss_section)
	
	var boss_row = HBoxContainer.new()
	boss_row.add_theme_constant_override("separation", 6)
	boss_row.mouse_filter = Control.MOUSE_FILTER_PASS
	boss_section.add_child(boss_row)
	
	_boss_selector = OptionButton.new()
	_boss_selector.name = "BossSelector"
	_boss_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_selector.custom_minimum_size = Vector2(0, 32)
	_boss_selector.mouse_filter = Control.MOUSE_FILTER_STOP
	_boss_selector.item_selected.connect(_on_boss_item_selected)
	boss_row.add_child(_boss_selector)
	
	var scan_boss_btn = Button.new()
	scan_boss_btn.text = "🔄 Escanear"
	scan_boss_btn.tooltip_text = "Escanear bosses y objetivos del mapa actual"
	scan_boss_btn.custom_minimum_size = Vector2(90, 32)
	scan_boss_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(scan_boss_btn, Color(0.12, 0.28, 0.42, 1.0))
	scan_boss_btn.pressed.connect(_refresh_boss_list)
	boss_row.add_child(scan_boss_btn)
	
	# 2. SECCIÓN: MODOS DE CÁMARA
	var mode_section = _create_section("🕹 MODOS DE CÁMARA")
	_expanded_content.add_child(mode_section)
	
	var mode_grid = GridContainer.new()
	mode_grid.name = "ModeGrid"
	mode_grid.columns = 2
	mode_grid.add_theme_constant_override("h_separation", 6)
	mode_grid.add_theme_constant_override("v_separation", 6)
	mode_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	mode_section.add_child(mode_grid)
	
	var modes = [
		["BOSS_POV", "👁️ 1ª Persona (POV)", "Vista en primera persona desde los ojos mirando al frente"],
		["ENEMY_VIEW", "🎯 Órbita (3ª Persona)", "Cámara orbital centrada alrededor del objetivo"],
		["CINEMATIC", "🎬 Cinemática", "Tomas cinematográficas y fluidas de cine/drone"],
		["PANORAMIC", "🌄 Panorámica 360°", "Rotación suave continua de 360°"],
		["FREE", "🕹️ Libre (WASD)", "Cámara libre manual con teclado y mouse"],
		["LANDSCAPE", "🏞️ Paisaje Aéreo", "Vista cenital aérea del mapa"]
	]
	
	for mode_data in modes:
		var btn = _create_mode_button(mode_data[0], mode_data[1], mode_data[2])
		btn.pressed.connect(_on_mode_button_pressed.bind(mode_data[0]))
		mode_grid.add_child(btn)
		_mode_buttons.append(btn)
	
	# 3. SECCIÓN: FORMATO & REDES SOCIALES
	var platform_section = _create_section("📱 FORMATO & REDES SOCIALES")
	_expanded_content.add_child(platform_section)
	
	var platform_grid = GridContainer.new()
	platform_grid.name = "PlatformGrid"
	platform_grid.columns = 2
	platform_grid.add_theme_constant_override("h_separation", 6)
	platform_grid.add_theme_constant_override("v_separation", 6)
	platform_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	platform_section.add_child(platform_grid)
	
	var platforms = [
		["YOUTUBE", "▶ YouTube", "1920×1080 (16:9)"],
		["INSTAGRAM_FEED", "📷 IG Feed", "1080×1080 (1:1)"],
		["INSTAGRAM_STORY", "📱 IG Reels/Story", "1080×1920 (9:16)"],
		["TIKTOK", "🎵 TikTok", "1080×1920 (9:16)"],
		["CUSTOM", "⚙ Personalizado", "Resolución manual"]
	]
	
	for plat_data in platforms:
		var btn = _create_platform_button(plat_data[0], plat_data[1], plat_data[2])
		btn.pressed.connect(_on_platform_button_pressed.bind(plat_data[0]))
		platform_grid.add_child(btn)
		_platform_buttons.append(btn)
	
	# 4. SECCIÓN: AJUSTES Y SLIDERS
	var settings_panel = _create_settings_panel()
	_expanded_content.add_child(settings_panel)
	
	# 5. SECCIÓN: ACCIONES RÁPIDAS
	var actions_section = _create_section("⚡ ACCIONES RÁPIDAS")
	_expanded_content.add_child(actions_section)
	
	var actions_grid = GridContainer.new()
	actions_grid.columns = 2
	actions_grid.add_theme_constant_override("h_separation", 6)
	actions_grid.add_theme_constant_override("v_separation", 6)
	actions_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	actions_section.add_child(actions_grid)
	
	var reset_btn = _create_action_button("🔄 Centrar Vista", "Restaura y centra inmediatamente la cámara")
	reset_btn.pressed.connect(_on_reset_view)
	actions_grid.add_child(reset_btn)
	
	var save_btn = _create_action_button("💾 Guardar Ajustes", "Guarda la configuración actual a disco")
	save_btn.pressed.connect(_on_save_config)
	actions_grid.add_child(save_btn)
	
	var load_btn = _create_action_button("📁 Cargar Ajustes", "Recarga la configuración guardada")
	load_btn.pressed.connect(_on_load_config)
	actions_grid.add_child(load_btn)
	
	var open_folder_btn = _create_action_button("📂 Abrir Videos", "Abre la carpeta de grabaciones en el Explorador de Windows")
	open_folder_btn.pressed.connect(_on_open_folder)
	actions_grid.add_child(open_folder_btn)
	
	var normal_cam_btn = _create_action_button("🎮 Cámara Normal", "Desactiva la cámara libre y vuelve a la vista del juego")
	normal_cam_btn.pressed.connect(_on_restore_normal_camera)
	actions_grid.add_child(normal_cam_btn)

func _setup_pip_preview():
	var cam = _get_camera_system()
	if not cam: return
	
	if not is_instance_valid(cam.pip_viewport):
		cam._setup_pip_system()
	
	if is_instance_valid(cam.pip_viewport) and is_instance_valid(_pip_container):
		# Enlazar el SubViewport al SubViewportContainer si no está ya
		if cam.pip_viewport.get_parent() != _pip_container:
			if cam.pip_viewport.get_parent():
				cam.pip_viewport.get_parent().remove_child(cam.pip_viewport)
			_pip_container.add_child(cam.pip_viewport)
		
		if _pip_status_lbl:
			_pip_status_lbl.text = "🔴 LIVE PiP (" + cam.get_platform_name() + ")"
		update_pip_preview_aspect(int(cam.current_platform))

func _refresh_boss_list():
	var cam = _get_camera_system()
	if not cam: return
	
	_cached_bosses = cam.get_available_bosses()
	if not _boss_selector: return
	
	_boss_selector.clear()
	# Índice 0 siempre es Mi Jugador
	_boss_selector.add_item("👤 Mi Jugador", 0)
	
	for i in range(_cached_bosses.size()):
		var b = _cached_bosses[i]
		var icon = "👹 " if b["is_boss"] else "👾 "
		var hp_text = " [" + str(int(b["hp"])) + "/" + str(int(b["max_hp"])) + " HP]"
		_boss_selector.add_item(icon + b["name"] + hp_text, i + 1)

func _on_boss_item_selected(index: int):
	var cam = _get_camera_system()
	if not cam: return
	
	if index == 0:
		cam.select_player_target()
		_notify("Objetivo fijado en: 👤 Mi Jugador", "info")
	elif index > 0 and (index - 1) < _cached_bosses.size():
		var b = _cached_bosses[index - 1]
		cam.select_boss_by_node(b["node"], false)
		_notify("Objetivo fijado en: " + b["name"], "info")

func _on_pip_toggle_pressed():
	var cam = _get_camera_system()
	if not cam: return
	
	var new_pip = not cam.is_pip_mode
	cam.set_pip_mode(new_pip)
	if _pip_toggle_btn:
		if new_pip:
			_pip_toggle_btn.text = "🖼️ PiP"
			_style_button(_pip_toggle_btn, Color(0.08, 0.22, 0.35, 1.0))
			_notify("Modo PiP: Tu juego es normal, el recuadro graba", "info")
		else:
			_pip_toggle_btn.text = "📺 Full"
			_style_button(_pip_toggle_btn, Color(0.35, 0.22, 0.08, 1.0))
			_notify("Modo Pantalla Completa: Control directo de cámara", "info")

func _create_section(title: String) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	section.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0, 0.95))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(lbl)
	
	return section

func _create_mode_button(mode_id: String, label: String, tooltip: String) -> Button:
	var btn = Button.new()
	btn.name = "ModeBtn_" + mode_id
	btn.text = label
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(190, 30)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(btn, Color(0.04, 0.09, 0.16, 1.0))
	return btn

func _create_platform_button(platform_id: String, label: String, tooltip: String) -> Button:
	var btn = Button.new()
	btn.name = "PlatformBtn_" + platform_id
	btn.text = label
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(190, 30)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(btn, Color(0.04, 0.09, 0.16, 1.0))
	return btn

func _create_action_button(label: String, tooltip: String) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(190, 30)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(btn, Color(0.06, 0.14, 0.24, 1.0))
	return btn

func _create_settings_panel() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.07, 1.0)
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(0.0, 0.6, 0.9, 0.5)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(vbox)
	
	_dynamic_settings_title = Label.new()
	_dynamic_settings_title.text = "⚙ AJUSTES DEL MODO ACTIVO"
	_dynamic_settings_title.add_theme_font_size_override("font_size", 10)
	_dynamic_settings_title.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0, 0.95))
	_dynamic_settings_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_dynamic_settings_title)
	
	_dynamic_settings_box = VBoxContainer.new()
	_dynamic_settings_box.name = "DynamicSettingsBox"
	_dynamic_settings_box.add_theme_constant_override("separation", 6)
	_dynamic_settings_box.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_dynamic_settings_box)
	
	var cam = _get_camera_system()
	var cur_mode = int(cam.current_mode) if cam else 0
	_rebuild_dynamic_settings(cur_mode)
	
	return panel

func _rebuild_dynamic_settings(mode: int):
	if not is_instance_valid(_dynamic_settings_box): return
	
	for child in _dynamic_settings_box.get_children():
		child.queue_free()
	
	_slider_labels.clear()
	
	var cam = _get_camera_system()
	var cfg = cam.get_config() if cam else {}
	
	match mode:
		0: # FREE
			if _dynamic_settings_title: _dynamic_settings_title.text = "⚙️ PERSONALIZAR: CÁMARA LIBRE (WASD)"
			
			var hint_panel = PanelContainer.new()
			hint_panel.mouse_filter = Control.MOUSE_FILTER_PASS
			var hint_sb = StyleBoxFlat.new()
			hint_sb.bg_color = Color(0.02, 0.08, 0.14, 0.95)
			hint_sb.border_width_left = 2; hint_sb.border_width_top = 1
			hint_sb.border_width_right = 1; hint_sb.border_width_bottom = 1
			hint_sb.border_color = Color(0.0, 0.85, 1.0, 0.8)
			hint_sb.set_corner_radius_all(5)
			hint_sb.content_margin_left = 10; hint_sb.content_margin_right = 10
			hint_sb.content_margin_top = 6; hint_sb.content_margin_bottom = 8
			hint_panel.add_theme_stylebox_override("panel", hint_sb)
			_dynamic_settings_box.add_child(hint_panel)
			
			var hint_vbox = VBoxContainer.new()
			hint_vbox.add_theme_constant_override("separation", 2)
			hint_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
			hint_panel.add_child(hint_vbox)
			
			var h1 = Label.new()
			h1.text = "🎮 CONTROLES DE CÁMARA LIBRE:"
			h1.add_theme_font_size_override("font_size", 9)
			h1.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6, 1.0))
			hint_vbox.add_child(h1)
			
			var h2 = Label.new()
			h2.text = "• Moverse: Teclas W, A, S, D (o Flechas)\n• Subir / Bajar: Teclas Q / E (o Space / C)\n• Vuelo Rápido: Mantener Shift\n• Rotar Ángulo: Clic Derecho + Arrastrar\n• Zoom: Rueda del Mouse"
			h2.add_theme_font_size_override("font_size", 8)
			h2.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0, 0.9))
			hint_vbox.add_child(h2)
			
			_dynamic_settings_box.add_child(_create_slider_setting("Velocidad de Vuelo", 0.5, 10.0, float(cfg.get("free_cam_speed", 2.0)), 0.5, "free_cam_speed"))
			_dynamic_settings_box.add_child(_create_slider_setting("Altura de Cámara (Y)", 0.0, 60.0, float(cfg.get("orbit_height", 4.0)), 0.5, "orbit_height"))
			_dynamic_settings_box.add_child(_create_slider_setting("Distancia / Zoom", 5.0, 200.0, float(cfg.get("orbit_distance", 35.0)), 1.0, "orbit_distance"))
			_dynamic_settings_box.add_child(_create_slider_setting("Ángulo Horizontal", 0.0, 360.0, float(cfg.get("orbit_h", 180.0)), 1.0, "orbit_h"))
			_dynamic_settings_box.add_child(_create_slider_setting("Inclinación Vertical", 5.0, 85.0, float(cfg.get("orbit_v", 35.0)), 1.0, "orbit_v"))
		1, 3, 7: # PLAYER_VIEW, ENEMY_VIEW, CUSTOM (Órbita 3ª Persona)
			if _dynamic_settings_title: _dynamic_settings_title.text = "⚙️ PERSONALIZAR: ÓRBITA (3ª PERSONA)"
			_dynamic_settings_box.add_child(_create_slider_setting("Distancia de Órbita", 5.0, 160.0, float(cfg.get("orbit_distance", 35.0)), 1.0, "orbit_distance"))
			_dynamic_settings_box.add_child(_create_slider_setting("Altura de Cámara (Y)", 0.0, 40.0, float(cfg.get("orbit_height", 4.0)), 0.5, "orbit_height"))
			_dynamic_settings_box.add_child(_create_slider_setting("Ángulo Horizontal", 0.0, 360.0, float(cfg.get("orbit_h", 180.0)), 1.0, "orbit_h"))
			_dynamic_settings_box.add_child(_create_slider_setting("Inclinación Vertical", 5.0, 85.0, float(cfg.get("orbit_v", 25.0)), 1.0, "orbit_v"))
			_dynamic_settings_box.add_child(_create_slider_setting("Suavizado Seguimiento", 0.01, 0.5, float(cfg.get("follow_smoothing", 0.12)), 0.01, "follow_smoothing"))
		2: # BOSS_POV (1ª Persona)
			if _dynamic_settings_title: _dynamic_settings_title.text = "⚙️ PERSONALIZAR: 1ª PERSONA (POV)"
			_dynamic_settings_box.add_child(_create_slider_setting("Altura de Ojos (Y)", -5.0, 25.0, float(cfg.get("eye_height_offset", 0.0)), 0.5, "eye_height_offset"))
			_dynamic_settings_box.add_child(_create_slider_setting("Avance Frontal (Z)", -2.0, 6.0, float(cfg.get("eye_forward_offset", 0.8)), 0.2, "eye_forward_offset"))
			_dynamic_settings_box.add_child(_create_slider_setting("Inclinación (Pitch)", -35.0, 35.0, float(cfg.get("pov_pitch", 0.0)), 1.0, "pov_pitch"))
			_dynamic_settings_box.add_child(_create_slider_setting("Campo de Visión (FOV)", 50.0, 110.0, float(cfg.get("pov_fov", 75.0)), 1.0, "pov_fov"))
			_dynamic_settings_box.add_child(_create_slider_setting("Suavizado de Giro", 0.05, 0.9, float(cfg.get("pov_smoothing", 0.35)), 0.05, "pov_smoothing"))
		4: # PANORAMIC
			if _dynamic_settings_title: _dynamic_settings_title.text = "⚙️ PERSONALIZAR: PANORÁMICA 360°"
			_dynamic_settings_box.add_child(_create_slider_setting("Velocidad de Giro", 1.0, 50.0, float(cfg.get("panoramic_speed", 10.0)), 1.0, "panoramic_speed"))
			_dynamic_settings_box.add_child(_create_slider_setting("Distancia Panorámica", 10.0, 150.0, float(cfg.get("orbit_distance", 35.0)), 1.0, "orbit_distance"))
			_dynamic_settings_box.add_child(_create_slider_setting("Ángulo Vertical", 10.0, 80.0, float(cfg.get("orbit_v", 30.0)), 1.0, "orbit_v"))
		5: # CINEMATIC
			if _dynamic_settings_title: _dynamic_settings_title.text = "⚙️ PERSONALIZAR: CINEMÁTICA"
			_dynamic_settings_box.add_child(_create_slider_setting("Velocidad Cinemática", 0.2, 4.0, float(cfg.get("cinematic_speed", 1.0)), 0.1, "cinematic_speed"))
			_dynamic_settings_box.add_child(_create_slider_setting("Distancia de Toma", 10.0, 100.0, float(cfg.get("cinematic_distance", 35.0)), 1.0, "cinematic_distance"))
			_dynamic_settings_box.add_child(_create_slider_setting("Altura de Toma", 2.0, 40.0, float(cfg.get("cinematic_height", 14.0)), 1.0, "cinematic_height"))
			_dynamic_settings_box.add_child(_create_slider_setting("Suavizado Cinemático", 0.01, 0.2, float(cfg.get("cinematic_smoothing", 0.05)), 0.01, "cinematic_smoothing"))
			_dynamic_settings_box.add_child(_create_slider_setting("Desenfoque DOF (Blur)", 0.0, 5.0, float(cfg.get("cinematic_dof_blur_amount", 1.5)), 0.1, "cinematic_dof_blur_amount"))
		6: # LANDSCAPE
			if _dynamic_settings_title: _dynamic_settings_title.text = "⚙️ PERSONALIZAR: PAISAJE AÉREO"
			_dynamic_settings_box.add_child(_create_slider_setting("Altura de Vuelo", 20.0, 300.0, float(cfg.get("landscape_height", 100.0)), 5.0, "landscape_height"))
			_dynamic_settings_box.add_child(_create_slider_setting("Inclinación Hacia Abajo", 30.0, 85.0, float(cfg.get("landscape_look_down_angle", 60.0)), 1.0, "landscape_look_down_angle"))
			_dynamic_settings_box.add_child(_create_slider_setting("Distancia de Vista", 10.0, 200.0, float(cfg.get("orbit_distance", 35.0)), 2.0, "orbit_distance"))
	
	# Separador sutil para los parámetros de grabación
	var sep = HSeparator.new()
	var sep_sb = StyleBoxLine.new()
	sep_sb.color = Color(0.0, 0.6, 0.9, 0.3)
	sep.add_theme_stylebox_override("separator", sep_sb)
	_dynamic_settings_box.add_child(sep)
	
	var rec_title = Label.new()
	rec_title.text = "🔴 PARÁMETROS DE VIDEO"
	rec_title.add_theme_font_size_override("font_size", 9)
	rec_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45, 0.95))
	_dynamic_settings_box.add_child(rec_title)
	
	_dynamic_settings_box.add_child(_create_slider_setting("FPS de Grabación", 15, 120, float(cfg.get("recording_fps", 60)), 1, "recording_fps"))
	_dynamic_settings_box.add_child(_create_slider_setting("Calidad de Video", 10, 100, float(cfg.get("recording_quality", 90)), 1, "recording_quality"))

func _create_slider_setting(label: String, min_val: float, max_val: float, default: float, step: float, config_key: String) -> HBoxContainer:
	var container = HBoxContainer.new()
	container.name = "SliderContainer_" + config_key
	container.add_theme_constant_override("separation", 6)
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var lbl = Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(lbl)
	
	var slider = HSlider.new()
	slider.name = "Slider_" + config_key
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(110, 0)
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.value_changed.connect(_on_slider_changed.bind(config_key))
	container.add_child(slider)
	
	var value_lbl = Label.new()
	value_lbl.name = "ValueLabel"
	value_lbl.text = str(int(default)) if config_key in ["recording_fps", "recording_quality"] else str(snappedf(default, 0.1))
	value_lbl.add_theme_font_size_override("font_size", 9)
	value_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5, 0.95))
	value_lbl.custom_minimum_size = Vector2(35, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(value_lbl)
	
	_slider_labels[config_key] = value_lbl
	return container

func _style_button(btn: Button, bg: Color):
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(0.0, 0.8, 1.0, 0.7)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	
	var h_sb = sb.duplicate()
	h_sb.bg_color = Color(0.12, 0.32, 0.52, 1.0)
	h_sb.border_color = Color(0.2, 1.0, 1.0, 1.0)
	btn.add_theme_stylebox_override("hover", h_sb)
	
	var p_sb = sb.duplicate()
	p_sb.bg_color = Color(0.18, 0.45, 0.7, 1.0)
	p_sb.border_color = Color.WHITE
	btn.add_theme_stylebox_override("pressed", p_sb)

func _on_title_bar_gui_input(event: InputEvent):
	var handled = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_offset = window_panel.global_position - event.global_position
		else:
			_is_dragging = false
		handled = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_drag_offset = window_panel.global_position - event.position
		else:
			_is_dragging = false
		handled = true
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
		var event_pos = event.global_position if "global_position" in event else event.position
		var new_pos = event_pos + _drag_offset
		var vp_size = get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, max(0.0, vp_size.x - window_panel.size.x))
		new_pos.y = clampf(new_pos.y, 0, max(0.0, vp_size.y - window_panel.size.y))
		window_panel.global_position = new_pos
		handled = true

	if handled:
		get_viewport().set_input_as_handled()

func _on_expand_toggled():
	_is_expanded = not _is_expanded
	_update_visibility()

func _update_visibility():
	if _scroll_container:
		_scroll_container.visible = _is_expanded
	if _expand_btn:
		_expand_btn.text = "▲" if _is_expanded else "▼"
	if is_instance_valid(window_panel):
		if _is_expanded:
			window_panel.custom_minimum_size = Vector2(420, 620)
			window_panel.size = Vector2(420, 620)
		else:
			window_panel.custom_minimum_size = Vector2(420, 80)
			window_panel.size = Vector2(420, 80)

func update_mode_display(mode: int):
	var mode_names = {
		0: "LIBRE (WASD)",
		1: "ÓRBITA (3ª PERSONA)",
		2: "1ª PERSONA (POV)",
		3: "ÓRBITA (3ª PERSONA)",
		4: "PANORÁMICA 360°",
		5: "CINEMÁTICA",
		6: "PAISAJE AÉREO",
		7: "OBJETIVO FIJO"
	}
	var mode_keys = {
		0: "FREE",
		1: "ENEMY_VIEW",
		2: "BOSS_POV",
		3: "ENEMY_VIEW",
		4: "PANORAMIC",
		5: "CINEMATIC",
		6: "LANDSCAPE",
		7: "ENEMY_VIEW"
	}
	
	if _mode_display:
		_mode_display.text = "MODO: " + mode_names.get(mode, "DESCONOCIDO")
	
	var cur_key = mode_keys.get(mode, "")
	for btn in _mode_buttons:
		var mode_id = btn.name.replace("ModeBtn_", "")
		var is_active = (mode_id == cur_key)
		_update_button_highlight(btn, is_active)
	
	_rebuild_dynamic_settings(mode)

func update_platform_display(platform: int):
	var platform_short = {
		0: "YT 16:9 (1920×1080)",
		1: "IG 1:1 (1080×1080)",
		2: "IG 9:16 (1080×1920)",
		3: "TT 9:16 (1080×1920)",
		4: "CUSTOM"
	}
	var platform_keys = {
		0: "YOUTUBE",
		1: "INSTAGRAM_FEED",
		2: "INSTAGRAM_STORY",
		3: "TIKTOK",
		4: "CUSTOM"
	}
	
	if _platform_display:
		_platform_display.text = platform_short.get(platform, "UNKNOWN")
	
	var cur_key = platform_keys.get(platform, "")
	for btn in _platform_buttons:
		var plat_id = btn.name.replace("PlatformBtn_", "")
		var is_active = (plat_id == cur_key)
		_update_button_highlight(btn, is_active)
	
	if _pip_status_lbl and camera_system:
		_pip_status_lbl.text = "🔴 LIVE PiP (" + camera_system.get_platform_name() + ")"
	
	update_pip_preview_aspect(platform)

func update_pip_preview_aspect(platform: int):
	const STAGE_H = 194.0
	const STAGE_W = 384.0
	
	var preview_w = 345.0
	var preview_h = STAGE_H
	var badge_text = "▶ YOUTUBE (16:9)"
	var res_text = "1920×1080"
	
	match platform:
		0: # YOUTUBE (16:9)
			preview_w = round(STAGE_H * (16.0 / 9.0)) # ~345
			preview_h = STAGE_H
			badge_text = "▶ YOUTUBE (16:9)"
			res_text = "1920×1080"
		1: # INSTAGRAM_FEED (1:1)
			preview_w = STAGE_H # 194 (cuadrado centrado)
			preview_h = STAGE_H
			badge_text = "📷 IG FEED (1:1)"
			res_text = "1080×1080"
		2: # INSTAGRAM_STORY (9:16)
			preview_w = round(STAGE_H * (9.0 / 16.0)) # ~109 (smartphone vertical centrado)
			preview_h = STAGE_H
			badge_text = "📱 IG REELS (9:16)"
			res_text = "1080×1920"
		3: # TIKTOK (9:16)
			preview_w = round(STAGE_H * (9.0 / 16.0)) # ~109 (smartphone vertical centrado)
			preview_h = STAGE_H
			badge_text = "🎵 TIKTOK (9:16)"
			res_text = "1080×1920"
		4: # CUSTOM
			var cam = _get_camera_system()
			var res = cam.get_current_resolution() if cam else Vector2i(1920, 1080)
			var asp = float(res.x) / maxf(1.0, float(res.y))
			preview_w = clampf(round(STAGE_H * asp), 80.0, STAGE_W)
			preview_h = STAGE_H
			badge_text = "⚙️ CUSTOM"
			res_text = str(res.x) + "×" + str(res.y)
	
	var target_size = Vector2(preview_w, preview_h)
	if is_instance_valid(_pip_aspect_box):
		_pip_aspect_box.custom_minimum_size = target_size
		_pip_aspect_box.size = target_size
	if is_instance_valid(_pip_container):
		_pip_container.custom_minimum_size = target_size
		_pip_container.size = target_size
	if is_instance_valid(_pip_format_badge):
		_pip_format_badge.text = badge_text
	if is_instance_valid(_pip_res_badge):
		_pip_res_badge.text = res_text

func _on_pip_preview_gui_input(event: InputEvent):
	var cam = _get_camera_system()
	if not cam: return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_LEFT:
			_pip_mouse_dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam.orbit_distance = clampf(cam.orbit_distance - 2.5, cam.orbit_distance_min, cam.orbit_distance_max)
			cam.set_config({"orbit_distance": cam.orbit_distance})
			notify_orbit_changed(cam.orbit_distance, cam.orbit_h, cam.orbit_v)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam.orbit_distance = clampf(cam.orbit_distance + 2.5, cam.orbit_distance_min, cam.orbit_distance_max)
			cam.set_config({"orbit_distance": cam.orbit_distance})
			notify_orbit_changed(cam.orbit_distance, cam.orbit_h, cam.orbit_v)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pip_mouse_dragging:
		cam.orbit_h = fmod(cam.orbit_h + event.relative.x * 0.35, 360.0)
		if cam.orbit_h < 0.0: cam.orbit_h += 360.0
		cam.orbit_v = clampf(cam.orbit_v + event.relative.y * 0.25, 5.0, 85.0)
		cam.set_config({"orbit_h": cam.orbit_h, "orbit_v": cam.orbit_v})
		notify_orbit_changed(cam.orbit_distance, cam.orbit_h, cam.orbit_v)
		get_viewport().set_input_as_handled()

func notify_orbit_changed(distance: float, h: float, v: float):
	if not is_instance_valid(_dynamic_settings_box): return
	
	var d_slider = _dynamic_settings_box.find_child("Slider_orbit_distance", true, false)
	if d_slider and d_slider is HSlider:
		d_slider.set_value_no_signal(distance)
	if _slider_labels.has("orbit_distance") and is_instance_valid(_slider_labels["orbit_distance"]):
		_slider_labels["orbit_distance"].text = str(snappedf(distance, 0.1))
	
	var h_slider = _dynamic_settings_box.find_child("Slider_orbit_h", true, false)
	if h_slider and h_slider is HSlider:
		h_slider.set_value_no_signal(h)
	if _slider_labels.has("orbit_h") and is_instance_valid(_slider_labels["orbit_h"]):
		_slider_labels["orbit_h"].text = str(snappedf(h, 0.1))
	
	var v_slider = _dynamic_settings_box.find_child("Slider_orbit_v", true, false)
	if v_slider and v_slider is HSlider:
		v_slider.set_value_no_signal(v)
	if _slider_labels.has("orbit_v") and is_instance_valid(_slider_labels["orbit_v"]):
		_slider_labels["orbit_v"].text = str(snappedf(v, 0.1))

func set_recording_state(recording: bool):
	if _recording_btn:
		if recording:
			_recording_btn.text = "⏹ STOP"
			_style_button(_recording_btn, Color(0.9, 0.1, 0.1, 1.0))
		else:
			_recording_btn.text = "⏺ REC"
			_style_button(_recording_btn, Color(0.8, 0.12, 0.12, 1.0))

func _update_button_highlight(btn: Button, active: bool):
	if active:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.6, 0.9, 1.0)
		sb.border_width_left = 2; sb.border_width_top = 2
		sb.border_width_right = 2; sb.border_width_bottom = 2
		sb.border_color = Color(0.3, 1.0, 1.0, 1.0)
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
	else:
		_style_button(btn, Color(0.04, 0.09, 0.16, 1.0))

func _on_mode_button_pressed(mode_id: String):
	var mode_map = {
		"BOSS_POV": 2,
		"ENEMY_VIEW": 3,
		"PLAYER_VIEW": 1,
		"CINEMATIC": 5,
		"PANORAMIC": 4,
		"FREE": 0,
		"LANDSCAPE": 6,
		"CUSTOM": 7
	}
	var mode = mode_map.get(mode_id, 0)
	var cam = _get_camera_system()
	if cam:
		cam.set_mode(mode as SocialCameraSystem.CameraMode)
	update_mode_display(mode)
	mode_changed.emit(mode)

func _on_platform_button_pressed(platform_id: String):
	var platform_map = {
		"YOUTUBE": 0,
		"INSTAGRAM_FEED": 1,
		"INSTAGRAM_STORY": 2,
		"TIKTOK": 3,
		"CUSTOM": 4
	}
	var platform = platform_map.get(platform_id, 0)
	var cam = _get_camera_system()
	if cam:
		cam.set_platform(platform as SocialCameraSystem.PlatformPreset)
	update_platform_display(platform)
	platform_changed.emit(platform)

func _on_recording_pressed():
	var cam = _get_camera_system()
	if cam:
		cam.toggle_recording()
	else:
		recording_toggled.emit(true)

func _on_slider_changed(value: float, config_key: String):
	if _slider_labels.has(config_key):
		var lbl = _slider_labels[config_key] as Label
		if lbl:
			if config_key in ["recording_fps", "recording_quality"]:
				lbl.text = str(int(value))
			else:
				lbl.text = str(snappedf(value, 0.1))
	
	var cam = _get_camera_system()
	if cam:
		cam.set_config({config_key: value})
	config_changed.emit({config_key: value})

func _on_reset_view():
	var cam = _get_camera_system()
	if cam:
		cam.set_mode(SocialCameraSystem.CameraMode.FREE)
		if cam.has_method("reset_free_cam_to_target"):
			cam.reset_free_cam_to_target()
		else:
			cam.orbit_h = 180.0
			cam.orbit_v = 35.0
			cam.orbit_distance = 35.0
			cam.orbit_height = 4.0
		cam.set_config({
			"orbit_h": cam.orbit_h,
			"orbit_v": cam.orbit_v,
			"orbit_distance": cam.orbit_distance,
			"orbit_height": cam.orbit_height
		})
		update_mode_display(int(SocialCameraSystem.CameraMode.FREE))
		notify_orbit_changed(cam.orbit_distance, cam.orbit_h, cam.orbit_v)
		_notify("Vista de cámara centrada y reseteada", "info")

func _on_save_config():
	var cam = _get_camera_system()
	if cam:
		cam._save_config()
		_notify("Configuración de cámara guardada", "success")

func _on_load_config():
	var cam = _get_camera_system()
	if cam:
		cam._load_config()
		update_mode_display(int(cam.current_mode))
		update_platform_display(int(cam.current_platform))
		_notify("Configuración de cámara cargada", "success")

func _notify(message: String, type: String = "info"):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("notify"):
		hud.notify(message, type)

func set_camera_system(cam_sys: SocialCameraSystem):
	camera_system = cam_sys
	if camera_system:
		if not mode_changed.is_connected(camera_system._on_ui_mode_changed):
			mode_changed.connect(camera_system._on_ui_mode_changed)
		if not platform_changed.is_connected(camera_system._on_ui_platform_changed):
			platform_changed.connect(camera_system._on_ui_platform_changed)
		if not recording_toggled.is_connected(camera_system._on_ui_recording_toggled):
			recording_toggled.connect(camera_system._on_ui_recording_toggled)
		if not config_changed.is_connected(camera_system._on_ui_config_changed):
			config_changed.connect(camera_system._on_ui_config_changed)
		
		update_mode_display(int(camera_system.current_mode))
		update_platform_display(int(camera_system.current_platform))
		set_recording_state(camera_system.is_recording)
		_setup_pip_preview()

func _on_open_folder():
	var cam = _get_camera_system()
	if cam and cam.has_method("open_recordings_folder"):
		cam.open_recordings_folder()
	else:
		var path = ProjectSettings.globalize_path("user://social_media_recordings/")
		DirAccess.make_dir_recursive_absolute(path)
		OS.shell_open(path)
	_notify("Abriendo carpeta de grabaciones en Windows...", "info")

func _on_restore_normal_camera():
	var cam = _get_camera_system()
	if cam:
		cam._deactivate_camera()
		_notify("Cámara original del juego restaurada", "info")
