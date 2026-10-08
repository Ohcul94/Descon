extends Control

# ==============================================================================
# PlayerStatsUI.gd - Módulo Standalone de Estadísticas del Piloto (Atajo: 'C')
# ==============================================================================
# - Ventana flotante/arrastrable "ESTADÍSTICAS DEL PILOTO"
# - Visualización dinámica de HP, Escudo, Daño, Regen, Munición y modificadores
# - Compatible con Touch & Mouse drag
# ==============================================================================

const EstadisticasTabScript = preload("res://scripts/ui/inventory/EstadisticasTab.gd")

var is_open: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var window_panel: PanelContainer = null
var header_bar: Control = null
var stats_tab_instance: Control = null


func _ready():
	add_to_group("stats_ui")
	add_to_group("player_stats_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build_ui_structure()


func _build_ui_structure():
	var blocker = Control.new()
	blocker.name = "ClickBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blocker)

	# Ventana flotante principal
	window_panel = PanelContainer.new()
	window_panel.name = "StatsWindow"
	window_panel.custom_minimum_size = Vector2(580, 480)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	window_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
	)

	var sb_win = StyleBoxFlat.new()
	sb_win.bg_color = Color(0.012, 0.022, 0.038, 0.96)
	sb_win.border_width_left = 2; sb_win.border_width_top = 2
	sb_win.border_width_right = 2; sb_win.border_width_bottom = 2
	sb_win.border_color = Color(0.0, 0.8, 1.0, 0.75)
	sb_win.set_corner_radius_all(8)
	sb_win.shadow_color = Color(0, 0, 0, 0.75)
	sb_win.shadow_size = 25
	window_panel.add_theme_stylebox_override("panel", sb_win)
	add_child(window_panel)

	_reposition_window()

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	window_panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Cabecera arrastrable
	header_bar = PanelContainer.new()
	header_bar.custom_minimum_size = Vector2(0, 34)
	var sb_header = StyleBoxFlat.new()
	sb_header.bg_color = Color(0.01, 0.05, 0.09, 0.9)
	sb_header.border_width_bottom = 1
	sb_header.border_color = Color(0.0, 0.8, 1.0, 0.5)
	sb_header.corner_radius_top_left = 6
	sb_header.corner_radius_top_right = 6
	header_bar.add_theme_stylebox_override("panel", sb_header)
	header_bar.gui_input.connect(_on_header_gui_input)
	main_vbox.add_child(header_bar)

	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 8)
	header_bar.add_child(h_box)

	var icon_title = Label.new()
	icon_title.text = " 📊 "
	icon_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(icon_title)

	var title_lbl = Label.new()
	title_lbl.text = "ESTADÍSTICAS DEL PILOTO"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(title_lbl)

	var spacer_h = Control.new()
	spacer_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_box.add_child(spacer_h)

	var btn_close = Button.new()
	btn_close.text = " ✕ "
	btn_close.custom_minimum_size = Vector2(28, 24)
	btn_close.add_theme_font_size_override("font_size", 11)
	btn_close.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	var sb_close = StyleBoxFlat.new()
	sb_close.bg_color = Color(0.18, 0.05, 0.07, 0.7)
	sb_close.set_corner_radius_all(4)
	btn_close.add_theme_stylebox_override("normal", sb_close)
	btn_close.pressed.connect(toggle)
	h_box.add_child(btn_close)

	# Instancia del módulo de Estadísticas
	stats_tab_instance = Control.new()
	stats_tab_instance.name = "EstadisticasTabModule"
	stats_tab_instance.set_script(EstadisticasTabScript)
	stats_tab_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_tab_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if stats_tab_instance.has_method("setup"):
		stats_tab_instance.setup(self)
	main_vbox.add_child(stats_tab_instance)


func update_ui():
	if not is_open: return
	if is_instance_valid(stats_tab_instance) and stats_tab_instance.has_method("update_ui"):
		stats_tab_instance.update_ui()


func toggle():
	is_open = !is_open
	visible = is_open

	if is_open:
		_reposition_window()
		update_ui()
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
			z_index = 105
	else:
		z_index = 0


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(580.0, vp_size.x * 0.95)
	var target_h = min(480.0, vp_size.y * 0.90)
	window_panel.custom_minimum_size = Vector2(target_w, target_h)
	window_panel.size = Vector2(target_w, target_h)
	var pos_x = max(10.0, (vp_size.x - target_w) / 2.0)
	var pos_y = max(10.0, (vp_size.y - target_h) / 2.0)
	window_panel.position = Vector2(pos_x, pos_y)


func _on_header_gui_input(event: InputEvent):
	var handled = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_offset = window_panel.global_position - event.global_position
		else:
			is_dragging = false
		handled = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_offset = window_panel.global_position - event.position
		else:
			is_dragging = false
		handled = true
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and is_dragging:
		var event_pos = event.global_position if "global_position" in event else event.position
		var new_pos = event_pos + drag_offset
		var vp_size = get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - window_panel.size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - window_panel.size.y)
		window_panel.global_position = new_pos
		handled = true

	if handled:
		get_viewport().set_input_as_handled()


func _input(event: InputEvent):
	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	if event.is_action_pressed("ui_stats") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C):
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not is_open: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()
