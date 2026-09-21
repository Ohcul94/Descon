extends PanelContainer

var window_id = "CombatMeter"
var _display_mode = 0
var _current_data = {}
var _elapsed = 0.0
var _sort_column = 0
var _sort_ascending = false
var _user_closed = false  # true = el usuario lo cerró manualmente, no reabrir automático

var _container: VBoxContainer
var _columns_hbox: HBoxContainer
var _rows_container: VBoxContainer
var _footer_hbox: HBoxContainer
var _reset_btn: Button
var _time_lbl: Label
var _dps_toggle_btn: Button

var _col_headers = []

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(350, 220)
	size = Vector2(350, 220)
	modulate = Color(1, 1, 1, 1) # 100% sólido por defecto
	
	# Contenedor con márgenes para que la tabla comience debajo del título y dentro de los chaflanes
	var margin_box = MarginContainer.new()
	margin_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_box.add_theme_constant_override("margin_left", 12)
	margin_box.add_theme_constant_override("margin_right", 12)
	margin_box.add_theme_constant_override("margin_top", 28) # Comienza debajo del título "Metricas"
	margin_box.add_theme_constant_override("margin_bottom", 10)
	add_child(margin_box)
	
	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 2)
	margin_box.add_child(_container)
	
	_build_columns()
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_container.add_child(scroll)
	
	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 0) # 0 para conectar las líneas tipo Excel
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)
	
	_build_footer()
	_refresh_rows()
	
	add_to_group("hud")
	
	if NetworkManager:
		NetworkManager.combat_meter_update.connect(_on_combat_meter_update)

func _build_columns():
	_columns_hbox = HBoxContainer.new()
	_columns_hbox.add_theme_constant_override("separation", 0) # 0 para conectar las celdas
	_columns_hbox.custom_minimum_size.y = 24
	_columns_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var header_sb = StyleBoxFlat.new()
	header_sb.bg_color = Color(0.02, 0.08, 0.15, 1.0) # Sólido 100%
	header_sb.border_width_right = 1
	header_sb.border_width_bottom = 1
	header_sb.border_color = Color(0.0, 0.85, 1.0, 0.6) # Línea divisoria nítida tipo Excel
	header_sb.content_margin_left = 4
	header_sb.content_margin_right = 4
	
	var header_sb_hover = header_sb.duplicate()
	header_sb_hover.bg_color = Color(0.04, 0.12, 0.22, 1.0)
	
	_dps_toggle_btn = Button.new()
	_dps_toggle_btn.text = "TOTAL"
	_dps_toggle_btn.add_theme_font_size_override("font_size", 10)
	_dps_toggle_btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.65, 1.0))
	_dps_toggle_btn.add_theme_color_override("font_hover_color", Color(0.3, 1.0, 0.8, 1.0))
	_dps_toggle_btn.add_theme_color_override("font_pressed_color", Color(0.0, 0.8, 0.5, 1.0))
	_dps_toggle_btn.add_theme_color_override("font_focus_color", Color(0.0, 1.0, 0.65, 1.0))
	_dps_toggle_btn.add_theme_stylebox_override("normal", header_sb)
	_dps_toggle_btn.add_theme_stylebox_override("hover", header_sb_hover)
	_dps_toggle_btn.add_theme_stylebox_override("pressed", header_sb_hover)
	_dps_toggle_btn.custom_minimum_size = Vector2(48, 24)
	_dps_toggle_btn.pressed.connect(_toggle_display_mode)
	_columns_hbox.add_child(_dps_toggle_btn)
	
	var col_info = [
		{ "name": "PILOTO", "min": 76, "expand": true },
		{ "name": "DAÑO", "min": 60, "expand": false },
		{ "name": "RECIBIDO", "min": 60, "expand": false },
		{ "name": "CURACIÓN", "min": 60, "expand": false },
	]
	
	for i in range(col_info.size()):
		var info = col_info[i]
		var btn = Button.new()
		btn.text = info.name
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_color", Color(0.0, 0.92, 1.0, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.5, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.0, 0.75, 0.9, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(0.0, 0.92, 1.0, 1.0))
		btn.add_theme_stylebox_override("normal", header_sb)
		btn.add_theme_stylebox_override("hover", header_sb_hover)
		btn.add_theme_stylebox_override("pressed", header_sb_hover)
		btn.custom_minimum_size.x = info.min
		btn.custom_minimum_size.y = 24
		if info.expand:
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_column_pressed.bind(i))
		_col_headers.append(btn)
		_columns_hbox.add_child(btn)
	
	_container.add_child(_columns_hbox)

func _build_footer():
	var footer_sb = StyleBoxFlat.new()
	footer_sb.bg_color = Color(0.015, 0.04, 0.08, 1.0) # Sólido 100%
	footer_sb.border_width_top = 1
	footer_sb.border_color = Color(0.0, 0.85, 1.0, 0.5)
	footer_sb.content_margin_top = 4
	
	var footer_panel = PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", footer_sb)
	footer_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	_footer_hbox = HBoxContainer.new()
	_footer_hbox.custom_minimum_size.y = 20
	_footer_hbox.add_theme_constant_override("separation", 10)
	
	_reset_btn = Button.new()
	_reset_btn.text = "⟳ RESET"
	_reset_btn.flat = true
	_reset_btn.add_theme_font_size_override("font_size", 10)
	_reset_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 1.0))
	_reset_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.4, 1.0))
	_reset_btn.pressed.connect(_reset_data)
	_footer_hbox.add_child(_reset_btn)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hbox.add_child(spacer)
	
	_time_lbl = Label.new()
	_time_lbl.text = "--:--"
	_time_lbl.add_theme_font_size_override("font_size", 10)
	_time_lbl.add_theme_color_override("font_color", Color(0.7, 0.88, 1.0, 1.0))
	_footer_hbox.add_child(_time_lbl)
	
	footer_panel.add_child(_footer_hbox)
	_container.add_child(footer_panel)

func toggle():
	visible = !visible
	_user_closed = not visible  # Si lo cierra el usuario, marcar para no reabrir
	if visible:
		_user_closed = false
		NetworkManager.send_event("requestCombatMeter", {})

func _toggle_display_mode():
	_display_mode = (_display_mode + 1) % 2
	_dps_toggle_btn.text = "DPS" if _display_mode == 1 else "TOTAL"
	_refresh_rows()

func _on_column_pressed(col_idx: int):
	if _sort_column == col_idx:
		_sort_ascending = !_sort_ascending
	else:
		_sort_column = col_idx
		_sort_ascending = true
	_refresh_rows()

func _on_combat_meter_update(data: Dictionary):
	_current_data = data
	_elapsed = data.get("elapsed", 0.0)
	
	# Solo refrescar las filas si el panel ya está abierto
	if visible:
		_refresh_rows()

func _refresh_rows():
	for child in _rows_container.get_children():
		child.queue_free()
	
	var members = _current_data.get("members", {})
	if members.is_empty():
		var row = HBoxContainer.new()
		row.custom_minimum_size.y = 24
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty_cell = _create_table_cell("  SIN DATOS DE COMBATE REGISTRADOS", 304, true, HORIZONTAL_ALIGNMENT_LEFT, Color(0.45, 0.65, 0.8, 1.0), true, false)
		row.add_child(empty_cell)
		_rows_container.add_child(row)
		_time_lbl.text = "--:--"
		return
	
	var member_list = []
	for uid in members:
		member_list.append({ "uid": uid, "data": members[uid] })
	
	var my_id = NetworkManager.my_socket_id if NetworkManager else ""
	var my_db_id = ""
	var lp = get_tree().get_first_node_in_group("player")
	if is_instance_valid(lp):
		my_db_id = lp.db_id
	
	member_list.sort_custom(func(a, b):
		var key_a = _get_sort_value(a.data)
		var key_b = _get_sort_value(b.data)
		if _sort_ascending:
			return key_a < key_b
		return key_a > key_b
	)
	
	for idx in range(member_list.size()):
		var entry = member_list[idx]
		var m = entry.data
		var is_me = (entry.uid == my_id or entry.uid == my_db_id)
		var is_even = (idx % 2 == 0)
		
		var row = HBoxContainer.new()
		row.custom_minimum_size.y = 22
		row.add_theme_constant_override("separation", 0) # 0 para conectar las líneas tipo Excel
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Celda 1: Rango (#1, #2, etc.) alineado con TOTAL/DPS
		var rank_str = "#%d" % (idx + 1)
		var rank_cell = _create_table_cell(rank_str, 48, false, HORIZONTAL_ALIGNMENT_CENTER, Color(0.7, 0.85, 1.0, 1.0), is_even, is_me)
		row.add_child(rank_cell)
		
		# Celda 2: Nombre del Piloto
		var name_str = m.get("n", "---")
		var name_col = Color(0.0, 1.0, 0.6, 1.0) if is_me else Color(1.0, 1.0, 1.0, 1.0)
		var name_cell = _create_table_cell(name_str, 76, true, HORIZONTAL_ALIGNMENT_LEFT, name_col, is_even, is_me)
		row.add_child(name_cell)
		
		# Valores de Daño, Recibido y Curación
		var dd_val = m.get("dd", 0)
		var dt_val = m.get("dt", 0)
		var hd_val = m.get("hd", 0)
		if _display_mode == 1:
			var elapsed = max(_elapsed, 1.0)
			dd_val = int(dd_val / elapsed)
			dt_val = int(dt_val / elapsed)
			hd_val = int(hd_val / elapsed)
			
		# Celda 3: Daño
		var dd_cell = _create_table_cell(_format_number(dd_val), 60, false, HORIZONTAL_ALIGNMENT_RIGHT, Color(1.0, 0.45, 0.45, 1.0), is_even, is_me)
		row.add_child(dd_cell)
		
		# Celda 4: Recibido
		var dt_cell = _create_table_cell(_format_number(dt_val), 60, false, HORIZONTAL_ALIGNMENT_RIGHT, Color(1.0, 0.8, 0.3, 1.0), is_even, is_me)
		row.add_child(dt_cell)
		
		# Celda 5: Curación
		var hd_cell = _create_table_cell(_format_number(hd_val), 60, false, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.3, 1.0, 0.7, 1.0), is_even, is_me)
		row.add_child(hd_cell)
		
		_rows_container.add_child(row)
	
	_time_lbl.text = _format_time(_elapsed)

func _create_table_cell(text: String, min_w: float, expand: bool, align: HorizontalAlignment, text_color: Color, is_even: bool, is_me: bool) -> PanelContainer:
	var cell = PanelContainer.new()
	cell.custom_minimum_size = Vector2(min_w, 22)
	if expand:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
	var sb = StyleBoxFlat.new()
	if is_me:
		sb.bg_color = Color(0.0, 0.22, 0.14, 1.0) # Sólido 100%
	elif is_even:
		sb.bg_color = Color(0.015, 0.035, 0.065, 1.0) # Sólido 100%
	else:
		sb.bg_color = Color(0.022, 0.05, 0.085, 1.0) # Sólido 100%
		
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.0, 0.85, 1.0, 0.4) # Borde nítido tipo Excel
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	cell.add_theme_stylebox_override("panel", sb)
	
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", text_color)
	lbl.horizontal_alignment = align
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	cell.add_child(lbl)
	
	return cell

func _get_sort_value(data: Dictionary) -> float:
	match _sort_column:
		0: return 0.0
		1: return float(data.get("dd", 0))
		2: return float(data.get("dt", 0))
		3: return float(data.get("hd", 0))
	return 0.0

func _format_number(val: int) -> String:
	var abs_val = abs(val)
	if abs_val < 1000:
		return str(val)
	elif abs_val < 1000000:
		var thousands = float(val) / 1000.0
		return str(snapped(thousands, 0.1)) + "K"
	else:
		var millions = float(val) / 1000000.0
		return str(snapped(millions, 0.1)) + "M"

func _format_time(seconds: float) -> String:
	var total_sec = int(seconds)
	var mins = int(total_sec / 60.0)
	var secs = total_sec % 60
	return "%02d:%02d" % [mins, secs]

func _reset_data():
	if NetworkManager:
		NetworkManager.send_event("resetCombatMeter", {})
	_current_data = {}
	_elapsed = 0.0
	_refresh_rows()
