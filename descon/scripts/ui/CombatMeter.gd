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
	custom_minimum_size = Vector2(340, 180)
	size = Vector2(340, 220)
	
	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 2)
	add_child(_container)
	
	_build_columns()
	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 1)
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.add_child(_rows_container)
	_build_footer()
	
	add_to_group("hud")
	
	if NetworkManager:
		NetworkManager.combat_meter_update.connect(_on_combat_meter_update)
 
func _build_columns():
	_columns_hbox = HBoxContainer.new()
	_columns_hbox.add_theme_constant_override("separation", 2)
	_columns_hbox.custom_minimum_size.y = 22
	_columns_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	_dps_toggle_btn = Button.new()
	_dps_toggle_btn.text = "TOTAL"
	_dps_toggle_btn.flat = true
	_dps_toggle_btn.add_theme_font_size_override("font_size", 9)
	_dps_toggle_btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.5))
	_dps_toggle_btn.custom_minimum_size = Vector2(48, 20)
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
		btn.flat = true
		btn.add_theme_font_size_override("font_size", 9)
		btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
		btn.custom_minimum_size.x = info.min
		if info.expand:
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_column_pressed.bind(i))
		_col_headers.append(btn)
		_columns_hbox.add_child(btn)
	
	_container.add_child(_columns_hbox)

func _build_footer():
	_footer_hbox = HBoxContainer.new()
	_footer_hbox.custom_minimum_size.y = 22
	_footer_hbox.add_theme_constant_override("separation", 10)
	
	_reset_btn = Button.new()
	_reset_btn.text = "⟳ RESET"
	_reset_btn.flat = true
	_reset_btn.add_theme_font_size_override("font_size", 9)
	_reset_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_reset_btn.pressed.connect(_reset_data)
	_footer_hbox.add_child(_reset_btn)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_hbox.add_child(spacer)
	
	_time_lbl = Label.new()
	_time_lbl.text = "--:--"
	_time_lbl.add_theme_font_size_override("font_size", 10)
	_time_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.8, 0.7))
	_footer_hbox.add_child(_time_lbl)
	
	_container.add_child(_footer_hbox)

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
	
	var members = data.get("members", {})
	var has_any = false
	for uid in members:
		var m = members[uid]
		if m.get("dd", 0) > 0 or m.get("dt", 0) > 0 or m.get("hd", 0) > 0:
			has_any = true
			break
	
	if has_any:
		# Solo abrir automáticamente si el usuario NO lo cerró manualmente
		if not visible and not _user_closed:
			visible = true
		if visible:
			_refresh_rows()
	else:
		# Sin datos de combate: ocultar y resetear el flag para permitir reapertura futura
		if visible:
			visible = false
		_user_closed = false

func _refresh_rows():
	for child in _rows_container.get_children():
		child.queue_free()
	
	var members = _current_data.get("members", {})
	if members.is_empty():
		var lbl = Label.new()
		lbl.text = "  SIN DATOS DE COMBATE"
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.7))
		lbl.custom_minimum_size.y = 24
		_rows_container.add_child(lbl)
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
	
	for entry in member_list:
		var m = entry.data
		var row = HBoxContainer.new()
		row.custom_minimum_size.y = 22
		row.add_theme_constant_override("separation", 2)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var is_me = (entry.uid == my_id or entry.uid == my_db_id)
		
		var name_lbl = Label.new()
		name_lbl.text = m.get("n", "---")
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.custom_minimum_size.x = 76
		if is_me:
			name_lbl.add_theme_color_override("font_color", Color(0.0, 1.0, 0.5))
		row.add_child(name_lbl)
		
		if _display_mode == 0:
			_add_val_label(row, m.get("dd", 0))
			_add_val_label(row, m.get("dt", 0))
			_add_val_label(row, m.get("hd", 0))
		else:
			var elapsed = max(_elapsed, 1.0)
			_add_val_label(row, int(m.get("dd", 0) / elapsed))
			_add_val_label(row, int(m.get("dt", 0) / elapsed))
			_add_val_label(row, int(m.get("hd", 0) / elapsed))
		
		_rows_container.add_child(row)
	
	_time_lbl.text = _format_time(_elapsed)

func _get_sort_value(data: Dictionary) -> float:
	match _sort_column:
		0: return 0.0
		1: return float(data.get("dd", 0))
		2: return float(data.get("dt", 0))
		3: return float(data.get("hd", 0))
	return 0.0

func _add_val_label(parent: HBoxContainer, val: int):
	var lbl = Label.new()
	lbl.text = _format_number(val)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.custom_minimum_size.x = 60
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(lbl)

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
