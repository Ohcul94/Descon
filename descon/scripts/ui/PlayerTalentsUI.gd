extends Control

# ==============================================================================
# PlayerTalentsUI.gd - Módulo Standalone del Árbol de Talentos (Atajo: 'T')
# ==============================================================================
# - Ventana flotante/arrastrable "ÁRBOL DE TALENTOS DE COMBATE"
# - Canvas interactivo con zoom, arrastre (pan), puntos asignables y reset
# - Sincronía autoritativa en tiempo real con TalentSystem y el servidor
# ==============================================================================

const TalentsTabScript = preload("res://scripts/ui/inventory/TalentsTab.gd")

var is_open: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var window_panel: PanelContainer = null
var header_bar: Control = null
var talents_tab_instance: Control = null
var active_modales: Array = []


func _ready():
	add_to_group("talents_ui")
	add_to_group("player_talents_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build_ui_structure()
	_connect_signals()


func _connect_signals():
	if NetworkManager:
		if NetworkManager.has_signal("config_updated"):
			if not NetworkManager.config_updated.is_connected(_on_server_config_updated):
				NetworkManager.config_updated.connect(_on_server_config_updated)
		if NetworkManager.has_signal("game_notification"):
			if not NetworkManager.game_notification.is_connected(_on_game_notification):
				NetworkManager.game_notification.connect(_on_game_notification)

	var ts = get_tree().get_first_node_in_group("talent_system")
	if is_instance_valid(ts) and ts.has_signal("talents_updated"):
		if not ts.talents_updated.is_connected(_on_talents_updated):
			ts.talents_updated.connect(_on_talents_updated)


func _on_server_config_updated(_cfg: Dictionary = {}):
	if is_open:
		update_ui()


func _on_talents_updated():
	if is_open:
		update_ui()


func _on_game_notification(data: Dictionary):
	var msg = str(data.get("msg", ""))
	var type = str(data.get("type", "info"))
	if is_open and type == "error":
		_show_result_modal("AVISO DE TALENTOS", msg)


# ==============================================================================
# CONSTRUCCIÓN DE LA ESTRUCTURA UI
# ==============================================================================
func _build_ui_structure():
	var blocker = Control.new()
	blocker.name = "ClickBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blocker)

	# Ventana flotante principal
	window_panel = PanelContainer.new()
	window_panel.name = "TalentsWindow"
	window_panel.custom_minimum_size = Vector2(880, 600)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	window_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
	)

	var sb_win = StyleBoxFlat.new()
	sb_win.bg_color = Color(0.012, 0.022, 0.035, 0.96)
	sb_win.border_width_left = 2; sb_win.border_width_top = 2
	sb_win.border_width_right = 2; sb_win.border_width_bottom = 2
	sb_win.border_color = Color(0.0, 0.82, 0.96, 0.75)
	sb_win.set_corner_radius_all(8)
	sb_win.shadow_color = Color(0, 0, 0, 0.7)
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
	sb_header.bg_color = Color(0.02, 0.05, 0.08, 0.9)
	sb_header.border_width_bottom = 1
	sb_header.border_color = Color(0.0, 0.82, 0.96, 0.4)
	sb_header.corner_radius_top_left = 6
	sb_header.corner_radius_top_right = 6
	header_bar.add_theme_stylebox_override("panel", sb_header)
	header_bar.gui_input.connect(_on_header_gui_input)
	main_vbox.add_child(header_bar)

	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 8)
	header_bar.add_child(h_box)

	var icon_title = Label.new()
	icon_title.text = " 🧬 "
	icon_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(icon_title)

	var title_lbl = Label.new()
	title_lbl.text = "ÁRBOL DE TALENTOS Y ESPECIALIZACIÓN"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
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

	# Instancia del lienzo de Talentos
	talents_tab_instance = Control.new()
	talents_tab_instance.name = "TalentsTabModule"
	talents_tab_instance.set_script(TalentsTabScript)
	talents_tab_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	talents_tab_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if talents_tab_instance.has_method("setup"):
		talents_tab_instance.setup(self)
	main_vbox.add_child(talents_tab_instance)


# Compatibilidad con métodos llamados desde TalentsTab.gd / ItemInfoHelper
func hide_item_info():
	pass

func _show_modal(title: String, message: String, on_confirm: Callable, extra_control: Control = null):
	var m = PanelContainer.new()
	m.z_index = 200
	m.custom_minimum_size = Vector2(320, 150)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.025, 0.04, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color.CYAN
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.8)
	sb.shadow_size = 20
	m.add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	m.add_child(margin)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var t = Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 11); t.add_theme_color_override("font_color", Color.CYAN); v.add_child(t)
	var rtl = RichTextLabel.new(); rtl.bbcode_enabled = true; rtl.text = message; rtl.custom_minimum_size.y = 50; rtl.fit_content = true; v.add_child(rtl)

	if is_instance_valid(extra_control):
		v.add_child(extra_control)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	v.add_child(hb)

	var btn_cancel = Button.new(); btn_cancel.text = " CANCELAR "; btn_cancel.add_theme_font_size_override("font_size", 9)
	btn_cancel.pressed.connect(func():
		active_modales.erase(m)
		m.queue_free()
	)
	hb.add_child(btn_cancel)

	var btn_ok = Button.new(); btn_ok.text = " CONFIRMAR "; btn_ok.add_theme_font_size_override("font_size", 9); btn_ok.modulate = Color.CYAN
	btn_ok.pressed.connect(func():
		active_modales.erase(m)
		m.queue_free()
		on_confirm.call()
	)
	hb.add_child(btn_ok)

	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	active_modales.append(m)


func _show_result_modal(title: String, message: String):
	var m = PanelContainer.new()
	m.z_index = 200
	m.custom_minimum_size = Vector2(300, 130)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.025, 0.04, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color(1.0, 0.4, 0.4)
	sb.set_corner_radius_all(6)
	m.add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	m.add_child(margin)

	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 10); margin.add_child(v)
	var t = Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 11); t.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4)); v.add_child(t)
	var rtl = RichTextLabel.new(); rtl.bbcode_enabled = true; rtl.text = message; rtl.custom_minimum_size.y = 40; rtl.fit_content = true; v.add_child(rtl)

	var btn_ok = Button.new(); btn_ok.text = " ENTENDIDO "; btn_ok.add_theme_font_size_override("font_size", 9)
	btn_ok.pressed.connect(func():
		active_modales.erase(m)
		m.queue_free()
	)
	v.add_child(btn_ok)

	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	active_modales.append(m)


func update_ui():
	if not is_open: return
	if is_instance_valid(talents_tab_instance) and talents_tab_instance.has_method("update_ui"):
		talents_tab_instance.update_ui()


func toggle():
	is_open = !is_open
	visible = is_open

	if is_open:
		_reposition_window()
		_connect_signals()
		update_ui()
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
			z_index = 105
		_deferred_initial_refresh()
	else:
		_close_all_modales()
		z_index = 0


func _deferred_initial_refresh():
	await get_tree().process_frame
	if is_open:
		_reposition_window()
		if is_instance_valid(talents_tab_instance) and talents_tab_instance.has_method("update_ui"):
			talents_tab_instance.update_ui()


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(880.0, vp_size.x * 0.95)
	var target_h = min(600.0, vp_size.y * 0.92)
	window_panel.custom_minimum_size = Vector2(target_w, target_h)
	window_panel.size = Vector2(target_w, target_h)
	var pos_x = max(10.0, (vp_size.x - target_w) / 2.0)
	var pos_y = max(10.0, (vp_size.y - target_h) / 2.0)
	window_panel.position = Vector2(pos_x, pos_y)


func _close_all_modales():
	for m in active_modales:
		if is_instance_valid(m): m.queue_free()
	active_modales.clear()


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

	if event.is_action_pressed("ui_talents") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T):
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not is_open: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if active_modales.size() > 0:
			var m = active_modales.pop_back()
			if is_instance_valid(m): m.queue_free()
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
