extends Control

# MainHUD.gd (Omni-HUD Coordinator v200.0)

# Referencias a Componentes Principales
@onready var center_stats = $CenterStats
@onready var radar_window = $RadarWindow
@onready var skills_hud = $Skills
@onready var control_bar = get_node_or_null("ControlBar")

# Referencias a Textos y Diagnósticos
@onready var fps_label = $TopLeft/FPS
@onready var ms_label = $TopLeft/MS
@onready var online_label = $TopLeft/ONLINE

var radar_title: Label = null # v243.60: Titulo del Minimapa (Nombre del Sector)
var virtual_joystick = null # Controlado por TouchControls.gd

var _esc_menu: Control = null
var _settings_menu: Control = null
var _pvp_status: bool = false
var _blind_overlay: ColorRect = null # v260.90: Efecto de Ceguera (Humo)
var _selected_node_for_editing: Control = null # v266.530: Persistencia de selección para sliders
var is_editing_layout: bool = false
var _editing_slot_index: int = -1 # v266.300: Slot que se está editando
var _layout_backup: Dictionary = {} # Para cancelar cambios
var active_slot_index: int = 0 # v266.300: Para mostrar cuál está en uso
var _hud_layouts: Array = [] # v266.130: Almacén de slots (Máx 4)
var is_selecting_trade_target: bool = false # v300.080: Modo selección de trade

func _ready():
	add_to_group("hud")
	print("[MainHUD] Inicializando coordinador central modular v200.0")
	
	# v302.99: Atajo de Desarrollador para simular móvil en PC
	set_process_input(true)
	
	# COMPONENTIZACIÓN: Inyección Dinámica de Scripts de Componentes
	_inject_components()
	
	if skills_hud and skills_hud.has_method("_ready"):
		skills_hud._ready()
	if control_bar and control_bar.has_method("_ready"):
		control_bar._ready()
	if center_stats and center_stats.has_method("_ready"):
		center_stats._ready()
	
	# v210.190: Inyectar HUD Notifier (Paridad con Web)
	_setup_notifier()
	
	# v266.155: Soporte para cambio de resolución en tiempo real
	get_viewport().size_changed.connect(_on_viewport_resize)

	_aggressive_hide(self)
	_update_icon_tooltips()
	
	for child in get_children():
		if child.has_method("toggle_minimize"):
			if not child.minimized.is_connected(_on_minimize_pressed):
				child.minimized.connect(_on_minimize_pressed)
	
	if NetworkManager:
		if not NetworkManager.login_success.is_connected(_on_server_data_received):
			NetworkManager.auth_success.connect(func(d): _on_server_data_received(d))
		NetworkManager.player_updated.connect(_on_server_player_updated)
		NetworkManager.enemy_kill_session.connect(_on_enemy_kill_reward)
		
		# v240.50: Sincronizar Errores de Autorización (Bloqueo de Cambio de Nave, etc)
		if not NetworkManager.auth_error.is_connected(notify):
			NetworkManager.auth_error.connect(func(msg): notify(str(msg), "warn"))
		
		# v240.90: Sincronía de Mensajes del Servidor (Combat Logs, Info de Juego)
		if not NetworkManager.game_notification.is_connected(_on_game_notification):
			NetworkManager.game_notification.connect(_on_game_notification)
		
		# v260.91: Conexión de Ceguera
		if not NetworkManager.blind_state.is_connected(_on_blind_state):
			NetworkManager.blind_state.connect(_on_blind_state)
		
		_setup_blind_overlay()

		# v300.050: Conexiones de TRADE
		NetworkManager.trade_invitation_received.connect(_on_trade_invitation_received)
		NetworkManager.trade_started.connect(_on_trade_started)

	# v305.95: Aplicar Marcos Sci-Fi (Diseño Referencia Roja)
	_apply_sci_fi_frame(center_stats)
	_apply_sci_fi_frame(radar_window)
	
	# v306.10: Aplicar a Panel de Equipo y Barra de Control (Solo limpieza, sin marco visible)
	var party_hud = get_node_or_null("PartyHUD")
	if party_hud: _apply_sci_fi_frame(party_hud, true)
	if control_bar: _apply_sci_fi_frame(control_bar, true)
	
	# v306.50: Unificar Slots de Habilidades
	if skills_hud:
		for slot in skills_hud.get_children():
			if slot is Control and "Slot" in slot.name:
				_apply_sci_fi_frame(slot, false, false, true) # Sin brillo, con remaches
	
	# v305.95: El chat puede tardar un frame en instanciarse
	get_tree().process_frame.connect(func():
		var chats = get_tree().get_nodes_in_group("chat_ui")
		for chat in chats: _apply_sci_fi_frame(chat)
	, CONNECT_ONE_SHOT)

func _inject_components():
	# 1. Componente de Habilidades
	if skills_hud and skills_hud.get_script() != load("res://scripts/systems/SkillsHUD.gd"):
		skills_hud.set_script(load("res://scripts/systems/SkillsHUD.gd"))
		print("[MainHUD] Script SkillsHUD.gd inyectado en $Skills")
	
	# 2. Componente de Controles Táctiles y Joystick
	if control_bar and control_bar.get_script() != load("res://scripts/systems/TouchControls.gd"):
		control_bar.set_script(load("res://scripts/systems/TouchControls.gd"))
		print("[MainHUD] Script TouchControls.gd inyectado en $ControlBar")
		
	# 3. Componente de Estadísticas
	if center_stats and center_stats.get_script() != load("res://scripts/systems/StatsHUD.gd"):
		center_stats.set_script(load("res://scripts/systems/StatsHUD.gd"))
		print("[MainHUD] Script StatsHUD.gd inyectado en $CenterStats")

func _on_game_notification(data: Dictionary):
	var msg = data.get("msg", "")
	var type = data.get("type", "info")
	notify(msg, type)

func _on_server_data_received(p_data: Dictionary):
	if p_data.has("gameData"):
		var gd = p_data.gameData
		var layout = gd.get("hudPositions", gd.get("hud_layout", {}))
		var config = gd.get("hudConfig", gd.get("hud_config", {}))
		_hud_layouts = gd.get("hudLayouts", []) # v266.130
		
		# v266.640: Si el layout está vacío (jugador nuevo), aplicar el default de fábrica
		if layout.is_empty():
			_restore_default_layout()
		else:
			_apply_hud_data(layout, config)
		
		# v266.300: Determinar slot activo
		_update_active_slot_index(layout)

func _update_active_slot_index(current_layout: Dictionary):
	if _hud_layouts.is_empty(): 
		active_slot_index = -1
		return
		
	for i in range(_hud_layouts.size()):
		var slot = _hud_layouts[i]
		if slot and slot.has("positions"):
			if str(slot.positions) == str(current_layout):
				active_slot_index = i
				return
	active_slot_index = -1

func _input(event: InputEvent):
	# v302.99: SIMULADOR DE MÓVIL PARA PC (Atajo F10)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		if SettingsManager:
			SettingsManager.mobile_mode = !SettingsManager.mobile_mode
			SettingsManager.save_settings()
			if SettingsManager.has_method("_apply_mobile_window_size"):
				SettingsManager._apply_mobile_window_size()
			
			if NetworkManager:
				NetworkManager.logout()
				
			get_tree().reload_current_scene()
			return

	if not NetworkManager or not NetworkManager.is_logged_in: return

	# v266.120: Atajo de teclado para cerrar edición
	if is_editing_layout and event.is_action_pressed("ui_menu"):
		_restore_layout_backup()
		toggle_hud_editing()
		get_viewport().set_input_as_handled()
		return
		
	# v266.99: Sistema Absoluto de Arrastre por Geometría
	if is_editing_layout:
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch:
			if _is_pos_over_priority_ui(event.position, true): return
			
			if event.pressed:
				var clicked_node = null
				var handle = get_node_or_null("SkillsMasterHandle")
				
				# 1. Chequear manija maestra
				if handle and handle.visible and handle.get_global_rect().has_point(event.position):
					clicked_node = skills_hud
				
				# 2. Chequear slots individuales (en orden inverso)
				if not clicked_node and skills_hud:
					for i in range(skills_hud.get_child_count() - 1, -1, -1):
						var child = skills_hud.get_child(i)
						if child is Control and child.name != "DragOverlay" and child.visible:
							if child.get_global_rect().has_point(event.position):
								clicked_node = child
								break
				
				# 3. v266.220: Chequear Ventanas Mayores (Stats, Mapa, Chat, Equipo, Iconos)
				if not clicked_node:
					for win_id in ["CenterStats", "RadarWindow", "ChatUI", "VirtualJoystick", "PartyHUD", "ControlBar"]:
						var win = _get_hud_node(win_id)
						if win and win.visible and win.get_global_rect().has_point(event.position):
							clicked_node = win
							break
				
				if clicked_node:
					_dragging_node = clicked_node
					_drag_offset = event.position
					_node_start_positions.clear()
					_node_start_positions[clicked_node] = clicked_node.global_position
					
					# v266.500: Mostrar y actualizar Panel de Propiedades
					var edit_ui = get_node_or_null("EditLayoutUI")
					if edit_ui:
						_selected_node_for_editing = clicked_node
						var pp = edit_ui.find_child("PropertyPanel", true, false)
						if pp:
							pp.visible = true
							var t_name = pp.find_child("TargetName", true, false)
							if t_name: t_name.text = clicked_node.name.to_upper()
							
							var s_slider = pp.find_child("ScaleSlider", true, false)
							if s_slider: s_slider.value = clicked_node.scale.x / 2.0
							
							var a_slider = pp.find_child("AlphaSlider", true, false)
							if a_slider: a_slider.value = clicked_node.modulate.a
							
							var s_val = pp.find_child("ScaleVal", true, false)
							if s_val: s_val.text = str(int(clicked_node.scale.x * 100))
							var a_val = pp.find_child("AlphaVal", true, false)
							if a_val: a_val.text = str(int(clicked_node.modulate.a * 100))
					
					if clicked_node.name == "Skills":
						clicked_node.top_level = true
						for child in clicked_node.get_children():
							if child is Control and child.name != "DragOverlay":
								child.top_level = true
								_node_start_positions[child] = child.global_position
					else:
						clicked_node.top_level = true
								
					get_viewport().set_input_as_handled()
					return
			else:
				_dragging_node = null
				
		elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _dragging_node:
			var delta = event.position - _drag_offset
			
			for node in _node_start_positions.keys():
				if is_instance_valid(node):
					node.global_position = _node_start_positions[node] + delta
			
			if _dragging_node.name == "Skills":
				var handle = get_node_or_null("SkillsMasterHandle")
				if handle: handle.global_position = _node_start_positions[_dragging_node] + delta + Vector2(-35, 0)
			
			get_viewport().set_input_as_handled()
			return

	# v300.090: CLIC PARA TRADE (Feedback Pro)
	if is_selecting_trade_target:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var target = _get_entity_under_mouse()
				if target:
					var tid = target.get("entity_id") if target.has("entity_id") else target.name
					NetworkManager.send_event("tradeInvite", tid)
					notify("INVITACIÓN ENVIADA A " + target.name.to_upper(), "info")
				else:
					notify("SELECCIÓN CANCELADA", "warn")
				_cancel_trade_selection()
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_trade_selection()
				get_viewport().set_input_as_handled()
				return
		elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			_cancel_trade_selection()
			get_viewport().set_input_as_handled()
			return

	var ui_nodes = get_tree().get_nodes_in_group("inventory_ui")
	for ui in ui_nodes:
		if ui.visible:
			if event.is_action_pressed("ui_events") or event.is_action_pressed("ui_inventory") or event.is_action_pressed("ui_party"):
				break
			return

	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	if event.is_action_pressed("ui_menu"):
		toggle_esc_menu()
		get_viewport().set_input_as_handled()
	
	if event.is_action_pressed("ui_party"):
		_on_icon_pressed("Party")
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_events"):
		_on_icon_pressed("Events")
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_pvp_toggle"):
		var requested_status = !_pvp_status
		if NetworkManager:
			NetworkManager.send_event("togglePvP", requested_status)
		get_viewport().set_input_as_handled()

func _apply_hud_data(layout: Dictionary, config: Dictionary):
	var screen_size = get_viewport_rect().size
	for win_id in layout:
		var pos_data = layout[win_id]
		var node = _get_hud_node(win_id)
		if node and typeof(pos_data) == TYPE_DICTIONARY:
			node.top_level = true
			var rx = float(pos_data.get("x", 0.0))
			var ry = float(pos_data.get("y", 0.0))
			
			var final_pos = Vector2.ZERO
			var original_w = 1280.0
			var original_h = 800.0
			
			if rx <= 2.0 and ry <= 2.0:
				final_pos = Vector2(rx * screen_size.x, ry * screen_size.y)
			else:
				var sc_val_temp = float(pos_data.get("scale", 0.5))
				var final_sc_temp = sc_val_temp * 2.0
				var rs_temp = node.size
				if node.name == "CenterStats": rs_temp = Vector2(320, 200)
				elif node.name == "RadarWindow": rs_temp = Vector2(280, 280)
				elif "Chat" in node.name: rs_temp = Vector2(320, 200)
				elif "Party" in node.name: rs_temp = Vector2(200, 80)
				elif "ControlBar" in node.name: rs_temp = Vector2(280, 45)
				elif rs_temp.x <= 0: rs_temp = node.get_combined_minimum_size()
				if rs_temp.x <= 0: rs_temp = Vector2(100, 100)
				
				var ns_temp = rs_temp * Vector2(final_sc_temp, final_sc_temp)
				
				# X: Anclar al borde más cercano
				if rx + (ns_temp.x / 2.0) > (original_w / 2.0):
					var margin_right = original_w - (rx + ns_temp.x)
					final_pos.x = screen_size.x - ns_temp.x - margin_right
				else:
					final_pos.x = rx
					
				# Y: Anclar al borde más cercano
				if ry + (ns_temp.y / 2.0) > (original_h / 2.0):
					var margin_bottom = original_h - (ry + ns_temp.y)
					final_pos.y = screen_size.y - ns_temp.y - margin_bottom
				else:
					final_pos.y = ry
			
			var sc_val = float(pos_data.get("scale", 0.5))
			var final_sc = sc_val * 2.0
			node.scale = Vector2(final_sc, final_sc)
			node.modulate.a = float(pos_data.get("alpha", 1.0))

			var raw_size = node.size
			if node.name == "CenterStats": raw_size = Vector2(320, 200)
			elif node.name == "RadarWindow": raw_size = Vector2(280, 280)
			elif "Chat" in node.name: raw_size = Vector2(320, 200)
			elif "Party" in node.name: raw_size = Vector2(200, 80)
			elif "ControlBar" in node.name: raw_size = Vector2(280, 45)
			elif raw_size.x <= 0: raw_size = node.get_combined_minimum_size()
			if raw_size.x <= 0: raw_size = Vector2(100, 100)
				
			var node_size = raw_size * node.scale
			final_pos.x = clamp(final_pos.x, 0, screen_size.x - node_size.x)
			final_pos.y = clamp(final_pos.y, 0, screen_size.y - node_size.y)
			node.global_position = final_pos
	
	for win_id in config:
		var node = _get_hud_node(win_id)
		if node: node.visible = bool(config[win_id])

func _on_viewport_resize():
	if not is_instance_valid(NetworkManager): return
	var data = NetworkManager.current_user_data
	if typeof(data) == TYPE_DICTIONARY and data.has("hud_layout"):
		_apply_hud_data(data["hud_layout"], data.get("hud_config", {}))

func _process(_delta):
	# Trade Highlight visual feedback
	if is_selecting_trade_target:
		var target = _get_entity_under_mouse()
		for p in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(p) and not p.is_in_group("player") and p.has_method("set_target"):
				if p == target:
					p.modulate = Color(0.5, 2.5, 4.0) 
					p.scale = p.scale.lerp(Vector2(1.15, 1.15), 0.1)
				else:
					p.modulate = Color.WHITE
					p.scale = p.scale.lerp(Vector2.ONE, 0.1)

	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		visible = false
		return
	else:
		visible = true
	
	if fps_label: fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	if ms_label: ms_label.text = "MS: " + str(NetworkManager.current_ms)
	if is_instance_valid(online_label):
		online_label.text = "ONLINE: " + str(NetworkManager.online_count)

func _on_minimize_pressed(id: String):
	var node = _get_hud_node(id)
	if node:
		node.visible = false
		_update_icon_state(id, false)

func _on_icon_pressed(id: String):
	if id == "Events":
		toggle_events_panel()
		if is_instance_valid(_events_panel):
			_update_icon_state("Events", _events_panel.visible)
		return
		
	if id == "EscMenu":
		toggle_esc_menu()
		if is_instance_valid(_esc_menu):
			_update_icon_state("EscMenu", _esc_menu.visible)
		return
		
	var node = _get_hud_node(id)
	if node:
		if node.has_method("toggle"):
			node.toggle()
		else:
			node.visible = !node.visible
		_update_icon_state(id, node.visible)

func _get_hud_node(id: String):
	var real_id = id
	if id == "Chat": real_id = "ChatUI"
	if id == "Stats": real_id = "CenterStats"
	if id == "Squad" or id == "Party": real_id = "PartyHUD"
	if id == "SkillsContainer": real_id = "Skills"
	
	var node = get_node_or_null(real_id)
	
	if not node and skills_hud:
		node = skills_hud.get_node_or_null(id)
	
	if not node and get_parent():
		node = get_parent().get_node_or_null(real_id)
		
	if not node:
		var all_hud = get_tree().get_nodes_in_group("hud")
		if all_hud.size() > 0:
			node = all_hud[0].find_child(real_id, true, false)
			
	return node

func _update_icon_state(id: String, is_active: bool):
	if control_bar:
		var icon = control_bar.get_node_or_null("Icon" + id)
		if icon: icon.modulate = Color.WHITE if is_active else Color(0.4, 0.4, 0.4, 0.6)

func _aggressive_hide(node):
	for child in node.get_children():
		if child is Button:
			if child.text == "-" or child.name == "MinBtn":
				child.visible = false; child.queue_free()
		if child is Label:
			var t = child.text.to_upper()
			if "SISTEMA" in t or "RECON" in t:
				radar_title = child
				child.text = "LOCALIZANDO..."

func set_map_name(p_name: String):
	if is_instance_valid(radar_title):
		radar_title.text = p_name.to_upper()
	elif is_instance_valid(radar_window):
		for child in radar_window.get_children():
			if child is Label:
				var t = child.text.to_upper()
				if "SISTEMA" in t or "RECON" in t or "LOCALIZANDO" in t:
					radar_title = child
					child.text = p_name.to_upper()
					break

# --- SISTEMA HUD NOTIFIER v210.190 ---
var _notifier_container: VBoxContainer = null

func _setup_notifier():
	_notifier_container = VBoxContainer.new()
	_notifier_container.name = "HUD_Notifier"
	_notifier_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notifier_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	_notifier_container.offset_top = 60 
	_notifier_container.grow_horizontal = Control.GROW_DIRECTION_BOTH 
	_notifier_container.grow_vertical = Control.GROW_DIRECTION_END  
	_notifier_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_notifier_container)

func notify(msg: String, type: String = "info"):
	if not _notifier_container: return
	
	var existing = null
	for child in _notifier_container.get_children():
		if child.get_meta("raw_msg", "") == msg:
			existing = child; break
		
		if "RECOMPENSA" in msg and "RECOMPENSA" in child.get_meta("raw_msg", ""):
			var units = ["EXP", "HUBS", "OHCU"]
			for u in units:
				if u in msg and u in child.get_meta("raw_msg", ""):
					existing = child; break
			if existing: break

	if existing:
		var old_msg = existing.get_meta("raw_msg", "")
		if "RECOMPENSA" in msg and "RECOMPENSA" in old_msg:
			var regex = RegEx.new()
			regex.compile("\\+([\\d\\.]+)")
			var m1 = regex.search(old_msg)
			var m2 = regex.search(msg)
			if m1 and m2:
				var val1 = float(m1.get_string(1).replace(".", ""))
				var val2 = float(m2.get_string(1).replace(".", ""))
				var unit = "EXP"
				if "HUBS" in msg: unit = "HUBS"
				elif "OHCU" in msg: unit = "OHCU"
				
				var new_total = val1 + val2
				var new_msg = "RECOMPENSA: +" + _format_val(new_total) + " " + unit
				existing.text = new_msg
				existing.set_meta("raw_msg", new_msg)
				_animate_notification(existing, true)
				return
		
		var count = existing.get_meta("count", 1) + 1
		existing.set_meta("count", count)
		existing.text = msg + " x" + str(count)
		_animate_notification(existing, true)
		return

	if _notifier_container.get_child_count() >= 5:
		var first = _notifier_container.get_child(0)
		if is_instance_valid(first): first.queue_free()

	var label = Label.new()
	label.text = msg
	label.set_meta("raw_msg", msg)
	label.set_meta("count", 1)
	label.add_theme_font_size_override("font_size", 10)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.7)
	sb.border_width_right = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	
	match type:
		"warn", "error": sb.border_color = Color.YELLOW
		"success": sb.border_color = Color.GREEN
		"info": sb.border_color = Color.CYAN
		_: sb.border_color = Color.CYAN
	
	label.add_theme_stylebox_override("normal", sb)
	label.modulate = sb.border_color
	
	_notifier_container.add_child(label)
	_animate_notification(label)

func _animate_notification(node: Label, is_update: bool = false):
	var tw = create_tween().set_parallel(true)
	if not is_update:
		node.modulate.a = 0
		node.scale = Vector2(0.8, 0.8) 
		tw.tween_property(node, "modulate:a", 1.0, 0.2)
		tw.tween_property(node, "scale", Vector2(1.0, 1.0), 0.2)
	else:
		tw.tween_property(node, "scale", Vector2(1.1, 1.1), 0.1)
		tw.chain().tween_property(node, "scale", Vector2(1.0, 1.0), 0.1)
	
	var wait_tw = create_tween()
	wait_tw.tween_interval(4.0)
	wait_tw.tween_property(node, "modulate:a", 0.0, 0.5)
	wait_tw.finished.connect(node.queue_free)

func _format_val(v):
	var s = str(int(v))
	var r = ""
	var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r
		c += 1
		if c == 3 and i != 0:
			r = "." + r
			c = 0
	return r

# --- MENÚ ESC v220.85 ---
func toggle_esc_menu():
	if _esc_menu and _esc_menu.visible:
		_esc_menu.visible = false
		if is_editing_layout: toggle_hud_editing()
		return
	
	if not _esc_menu:
		_create_esc_menu()
	
	_esc_menu.visible = true
	_esc_menu.reset_size()
	_esc_menu.global_position = (get_viewport_rect().size - _esc_menu.size) / 2.0

func _restore_default_layout():
	if not is_editing_layout:
		active_slot_index = -1
		if NetworkManager:
			NetworkManager.send_event("saveHudLayout", { "positions": {} })
	
	var default_layout = {
		"CenterStats":     { "x": 1063,  "y": 21,    "scale": 0.5, "alpha": 1.0 },
		"ChatUI":          { "x": 12,    "y": 545,   "scale": 0.5, "alpha": 1.0 },
		"RadarWindow":     { "x": 1066,  "y": 564,   "scale": 0.5, "alpha": 1.0 },
		"SkillsContainer": { "x": 101,   "y": 684,   "scale": 0.5, "alpha": 1.0 },
		"LaserSlot":       { "x": 364.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"MissileSlot":     { "x": 449.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"MineSlot":        { "x": 534.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"Sphere1Slot":     { "x": 619.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"Sphere2Slot":     { "x": 704.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"Sphere3Slot":     { "x": 789.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"Sphere4Slot":     { "x": 874.5, "y": 714,   "scale": 0.5, "alpha": 1.0 },
		"PartyHUD":        { "x": 10,    "y": 120,   "scale": 0.5, "alpha": 1.0 },
		"ControlBar":      { "x": 10,    "y": 745,   "scale": 0.5, "alpha": 1.0 },
	}
	
	# v1.10: Sincronización dinámica de valores de fábrica definidos en el AdminDash
	if NetworkManager and NetworkManager.current_user_data.has("adminConfig"):
		var admin_cfg = NetworkManager.current_user_data.adminConfig
		if admin_cfg.has("pilotConfig") and admin_cfg.pilotConfig.has("defaultLayout"):
			var server_layout = admin_cfg.pilotConfig.defaultLayout
			for key in server_layout:
				if server_layout[key] != null and typeof(server_layout[key]) == TYPE_DICTIONARY:
					default_layout[key] = server_layout[key]
					
	_apply_hud_data(default_layout, {})
	
	var joy = _get_hud_node("VirtualJoystick")
	if joy:
		var joy_enabled = SettingsManager.mobile_mode if SettingsManager else false
		joy.visible = joy_enabled
		joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if joy_enabled:
			joy.global_position = Vector2(20, 680)
		else:
			joy.global_position = Vector2(-2000, -2000)
	
	var editor_ui = get_node_or_null("EditLayoutUI")
	if editor_ui:
		var pp = editor_ui.find_child("PropertyPanel", true, false)
		if pp:
			var s_slider = pp.find_child("ScaleSlider", true, false)
			if s_slider: s_slider.value = 0.5
			var a_slider = pp.find_child("AlphaSlider", true, false)
			if a_slider: a_slider.value = 1.0

	print("[MainHUD] Layout de fábrica restaurado.")
	
	if is_editing_layout:
		await get_tree().process_frame
		for win_id in ["Skills", "CenterStats", "RadarWindow", "ChatUI"]:
			var win = _get_hud_node(win_id)
			if win:
				var gp = win.global_position
				win.top_level = true
				win.global_position = gp
				if win.name == "Skills":
					for child in win.get_children():
						if child is Control and child.name != "DragOverlay":
							var cgp = child.global_position
							child.top_level = true
							child.global_position = cgp
		
		var handle = get_node_or_null("SkillsMasterHandle")
		if handle and skills_hud:
			handle.global_position = skills_hud.global_position + Vector2(-35, 0)

func _create_esc_menu():
	var canvas = CanvasLayer.new()
	canvas.name = "EscCanvas"
	canvas.layer = 100
	add_child(canvas)
	
	_esc_menu = PanelContainer.new()
	_esc_menu.name = "EscMenu"
	canvas.add_child(_esc_menu)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color.CYAN
	style.set_corner_radius_all(10)
	_esc_menu.add_theme_stylebox_override("panel", style)
	_esc_menu.custom_minimum_size = Vector2(250, 150)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	_esc_menu.add_child(vbox)
	
	var title = Label.new()
	title.text = "MENÚ DE SISTEMA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var pvp_btn = Button.new()
	pvp_btn.name = "PvPButton"
	pvp_btn.text = "MODO COMBATE: " + ("ACTIVO" if _pvp_status else "SEGURO")
	pvp_btn.modulate = Color.RED if _pvp_status else Color.GREEN
	pvp_btn.pressed.connect(func():
		var requested_status = !_pvp_status
		NetworkManager.send_event("togglePvP", requested_status)
	)
	var config_btn = Button.new()
	config_btn.text = "CONFIGURACIONES"
	config_btn.pressed.connect(func():
		_esc_menu.visible = false
		_open_settings()
	)
	vbox.add_child(config_btn)
	
	var trade_btn = Button.new()
	trade_btn.text = "INVITAR A COMERCIAR (CLIC)"
	trade_btn.modulate = Color.CYAN
	trade_btn.pressed.connect(_on_esc_trade_pressed)
	vbox.add_child(trade_btn)
	
	var logout_btn = Button.new()
	logout_btn.text = "CERRAR SESIÓN"
	logout_btn.pressed.connect(func():
		if NetworkManager:
			NetworkManager.logout()
			get_tree().reload_current_scene()
	)
	vbox.add_child(logout_btn)
	
	var close_btn = Button.new()
	close_btn.text = "VOLVER AL JUEGO"
	close_btn.pressed.connect(func(): _esc_menu.visible = false)
	vbox.add_child(close_btn)
	
	_esc_menu.size = _esc_menu.get_combined_minimum_size()
	
func set_pvp_status(enabled: bool):
	_on_server_player_updated({"id": NetworkManager.my_socket_id, "pvpEnabled": enabled})

func _on_server_player_updated(data: Dictionary):
	if not data.has("id"): return
	
	var my_id = NetworkManager.my_socket_id if NetworkManager else ""
	var is_local = (str(data.id) == str(my_id))
	
	if is_local:
		if data.has("pvpEnabled"):
			var old_status = _pvp_status
			_pvp_status = data.pvpEnabled
			
			if is_instance_valid(_esc_menu):
				var pvp_btn = _esc_menu.find_child("PvPButton", true, false)
				if is_instance_valid(pvp_btn):
					pvp_btn.text = "MODO COMBATE: " + ("ACTIVO" if _pvp_status else "SEGURO")
					pvp_btn.modulate = Color.RED if _pvp_status else Color.GREEN
			
			if old_status != _pvp_status:
				notify("Modo Combate: " + ("Activado" if _pvp_status else "Desactivado"), "success")
	
	for entity in get_tree().get_nodes_in_group("entities"):
		if str(entity.entity_id) == str(data.id):
			if data.has("pvpEnabled"):
				entity.pvp_status = data.pvpEnabled
				if entity.name_tag:
					entity.name_tag.modulate = Color(1, 0.2, 0.2) if data.pvpEnabled else Color.WHITE
			break

func _on_enemy_kill_reward(data: Dictionary):
	var h = int(data.get("hubs", 0))
	var o = int(data.get("ohcu", 0))
	var e = int(data.get("exp", 0))
	
	if e > 0: notify("RECOMPENSA: +" + _format_val(e) + " EXP", "success")
	if h > 0: notify("RECOMPENSA: +" + _format_val(h) + " HUBS", "info")
	if o > 0: notify("RECOMPENSA: +" + _format_val(o) + " OHCU", "warn")

func _update_icon_tooltips():
	if control_bar and control_bar.has_method("_update_icon_tooltips"):
		control_bar._update_icon_tooltips()

func _open_settings():
	if not _settings_menu:
		var s_script = load("res://scripts/systems/SettingsUI.gd")
		if s_script:
			var canvas = CanvasLayer.new()
			canvas.name = "SettingsLayer"
			canvas.layer = 150
			add_child(canvas)
			
			_settings_menu = s_script.new()
			canvas.add_child(_settings_menu)
			_settings_menu.closed.connect(func(): toggle_esc_menu())

	if _settings_menu:
		_settings_menu.open()
		var canvas = _settings_menu.get_parent()
		if canvas is CanvasLayer:
			canvas.visible = true

func _is_pos_over_priority_ui(p: Vector2, ignore_editable: bool = false) -> bool:
	if not ignore_editable:
		if radar_window and radar_window.visible:
			if radar_window.get_global_rect().has_point(p): return true
		
		var chat_nodes = get_tree().get_nodes_in_group("chat_ui")
		for chat in chat_nodes:
			if chat is Control and chat.visible:
				if chat.get_global_rect().has_point(p): return true
		
		if control_bar and control_bar.visible:
			if control_bar.get_global_rect().has_point(p): return true
			
		var p_hud = get_node_or_null("PartyHUD")
		if p_hud and p_hud.visible:
			if p_hud.get_global_rect().has_point(p): return true

	var ui_nodes = get_tree().get_nodes_in_group("inventory_ui")
	for ui in ui_nodes:
		if ui is Control and ui.visible:
			if ui.get_global_rect().has_point(p): return true

	if _esc_menu and _esc_menu.visible:
		if _esc_menu.get_global_rect().has_point(p): return true
		
	if _settings_menu and _settings_menu.visible:
		if _settings_menu.get_global_rect().has_point(p): return true

	var edit_ui = get_node_or_null("EditLayoutUI")
	if edit_ui and edit_ui.visible:
		var top_bar = edit_ui.find_child("TopBar", true, false)
		if top_bar and top_bar.visible and top_bar.get_global_rect().has_point(p): return true
		var prop_panel = edit_ui.find_child("PropertyPanel", true, false)
		if prop_panel and prop_panel.visible and prop_panel.get_global_rect().has_point(p): return true
		
	return false

func _setup_blind_overlay():
	if _blind_overlay: return
	_blind_overlay = ColorRect.new()
	_blind_overlay.name = "BlindOverlay"
	_blind_overlay.color = Color(0, 0, 0, 0)
	_blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind_overlay.z_index = 200
	add_child(_blind_overlay)

func _on_blind_state(data: Dictionary):
	var active = data.get("active", false)
	var tw = create_tween()
	if active:
		tw.tween_property(_blind_overlay, "color:a", 1.0, 0.05)
	else:
		tw.tween_property(_blind_overlay, "color:a", 0.0, 0.1)

# --- SISTEMA DE EDICIÓN DE HUD v266.300 ---
func toggle_hud_editing(slot_index: int = -1):
	if is_editing_layout and slot_index != -1: return
	
	is_editing_layout = !is_editing_layout
	
	var edit_container = get_node_or_null("EditLayoutUI")
	if is_editing_layout:
		_editing_slot_index = slot_index
		_backup_layout()
		
		if _editing_slot_index >= 0 and _editing_slot_index < _hud_layouts.size():
			var slot = _hud_layouts[_editing_slot_index]
			if slot.has("positions") and not slot.positions.is_empty():
				_apply_hud_data(slot.positions, {})
		
		if not edit_container:
			edit_container = CanvasLayer.new()
			edit_container.name = "EditLayoutUI"
			edit_container.layer = 110
			
			var grid = ColorRect.new()
			grid.name = "AlignmentGrid"
			grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			edit_container.add_child(grid)
			
			var mat = ShaderMaterial.new()
			var sh = Shader.new()
			sh.code = "shader_type canvas_item;
				void fragment() {
					vec2 grid = fract(SCREEN_UV * vec2(20.0, 15.0));
					float line = step(0.98, grid.x) + step(0.98, grid.y);
					COLOR = vec4(0.0, 1.0, 1.0, line * 0.1);
				}"
			mat.shader = sh
			grid.material = mat
			
			var panel = HBoxContainer.new()
			panel.name = "TopBar"
			edit_container.add_child(panel)
			
			panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			panel.custom_minimum_size.y = 80
			panel.alignment = BoxContainer.ALIGNMENT_CENTER
			panel.add_theme_constant_override("separation", 30)
			
			var vbox = VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			panel.add_child(vbox)
			
			var prop_panel = PanelContainer.new()
			prop_panel.name = "PropertyPanel"
			prop_panel.visible = false
			prop_panel.custom_minimum_size = Vector2(250, 120)
			
			edit_container.add_child(prop_panel)
			prop_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			prop_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			prop_panel.offset_right = -20
			prop_panel.offset_top = -60
			
			var prop_style = StyleBoxFlat.new()
			prop_style.bg_color = Color(0, 0, 0, 0.85)
			prop_style.border_width_left = 2; prop_style.border_color = Color.CYAN
			prop_panel.add_theme_stylebox_override("panel", prop_style)
			
			var prop_vbox = VBoxContainer.new()
			prop_vbox.add_theme_constant_override("separation", 10)
			prop_panel.add_child(prop_vbox)
			
			var prop_title = Label.new()
			prop_title.name = "TargetName"
			prop_title.text = "PROPIEDADES"
			prop_title.add_theme_color_override("font_color", Color.YELLOW)
			prop_vbox.add_child(prop_title)
			
			var scale_row = HBoxContainer.new()
			prop_vbox.add_child(scale_row)
			var scale_lbl = Label.new()
			scale_lbl.text = "ESC:"
			scale_lbl.custom_minimum_size.x = 40
			scale_row.add_child(scale_lbl)
			
			var scale_slider = HSlider.new()
			scale_slider.name = "ScaleSlider"
			scale_slider.min_value = 0.05; scale_slider.max_value = 1.0; scale_slider.step = 0.01
			scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var scale_val_edit = LineEdit.new()
			scale_val_edit.name = "ScaleVal"
			scale_val_edit.text = "100"
			scale_val_edit.custom_minimum_size.x = 45
			scale_val_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			scale_slider.value_changed.connect(func(v):
				if _selected_node_for_editing: 
					var final_v = v * 2.0
					_selected_node_for_editing.scale = Vector2(final_v, final_v)
					scale_val_edit.text = str(int(final_v * 100))
					if _selected_node_for_editing.name == "Skills":
						var handle = get_node_or_null("SkillsMasterHandle")
						if handle: handle.global_position = _selected_node_for_editing.global_position + Vector2(-35, 0)
			)
			
			scale_val_edit.text_submitted.connect(func(new_text):
				var val = float(new_text) / 100.0
				scale_slider.value = val / 2.0
				scale_val_edit.release_focus()
			)
			
			scale_row.add_child(scale_slider)
			scale_row.add_child(scale_val_edit)
			
			var alpha_row = HBoxContainer.new()
			prop_vbox.add_child(alpha_row)
			var alpha_lbl = Label.new()
			alpha_lbl.text = "OPA:"
			alpha_lbl.custom_minimum_size.x = 40
			alpha_row.add_child(alpha_lbl)
			
			var alpha_slider = HSlider.new()
			alpha_slider.name = "AlphaSlider"
			alpha_slider.min_value = 0.01; alpha_slider.max_value = 1.0; alpha_slider.step = 0.01
			alpha_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var alpha_val_edit = LineEdit.new()
			alpha_val_edit.name = "AlphaVal"
			alpha_val_edit.text = "100"
			alpha_val_edit.custom_minimum_size.x = 45
			alpha_val_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			alpha_slider.value_changed.connect(func(v):
				if _selected_node_for_editing: 
					_selected_node_for_editing.modulate.a = v
					alpha_val_edit.text = str(int(v * 100))
			)
			
			alpha_val_edit.text_submitted.connect(func(new_text):
				var val = float(new_text) / 100.0
				alpha_slider.value = val
				alpha_val_edit.release_focus()
			)
			
			alpha_row.add_child(alpha_slider)
			alpha_row.add_child(alpha_val_edit)
			
			var title_lbl = Label.new()
			title_lbl.name = "TitleLabel"
			var s_name = "Manual"
			if _editing_slot_index >= 0 and _editing_slot_index < _hud_layouts.size():
				s_name = _hud_layouts[_editing_slot_index].name
			title_lbl.text = "EDITANDO LAYOUT: " + s_name.to_upper()
			title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title_lbl.add_theme_color_override("font_color", Color.CYAN)
			vbox.add_child(title_lbl)
			
			var btns_hbox = HBoxContainer.new()
			btns_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			btns_hbox.add_theme_constant_override("separation", 20)
			vbox.add_child(btns_hbox)
			
			var save_btn = Button.new()
			save_btn.text = " ✔ GUARDAR CAMBIOS "
			save_btn.modulate = Color.GREEN
			save_btn.pressed.connect(func():
				_save_hud_positions(_editing_slot_index)
				toggle_hud_editing()
			)
			btns_hbox.add_child(save_btn)
			
			var cancel_btn = Button.new()
			cancel_btn.text = " ✕ SALIR SIN GUARDAR "
			cancel_btn.modulate = Color.ORANGE
			cancel_btn.pressed.connect(func():
				_restore_layout_backup()
				if is_editing_layout:
					toggle_hud_editing(-1) 
			)
			btns_hbox.add_child(cancel_btn)
			
			var restore_btn = Button.new()
			restore_btn.text = " ↺ VALORES DE FÁBRICA "
			restore_btn.modulate = Color.RED
			restore_btn.pressed.connect(_restore_default_layout)
			btns_hbox.add_child(restore_btn)
			
			add_child(edit_container)
		
		var current_slot_name = "Manual"
		if _editing_slot_index >= 0 and _editing_slot_index < _hud_layouts.size():
			current_slot_name = _hud_layouts[_editing_slot_index].name
		
		var t_lbl = edit_container.find_child("TitleLabel", true, false)
		if t_lbl: t_lbl.text = "EDITANDO LAYOUT: " + current_slot_name.to_upper()
		edit_container.visible = true
	else:
		if edit_container: 
			var pp = edit_container.find_child("PropertyPanel", true, false)
			if pp: pp.visible = false
			edit_container.visible = false
		_editing_slot_index = -1
	
	if is_instance_valid(_settings_menu): _settings_menu.close()
	if is_instance_valid(_esc_menu): _esc_menu.visible = false
	
	# Hacer que todo sea movible
	if is_instance_valid(skills_hud):
		var handle = get_node_or_null("SkillsMasterHandle")
		if is_editing_layout:
			if not handle:
				handle = Button.new()
				handle.name = "SkillsMasterHandle"
				handle.text = "::"
				handle.custom_minimum_size = Vector2(30, 60)
				add_child(handle)
			
			handle.visible = true
			handle.global_position = skills_hud.global_position + Vector2(-35, 0)
		elif handle:
			handle.visible = false
			
		for child in skills_hud.get_children():
			if child is Control and child.name != "DragOverlay":
				if is_editing_layout:
					var gp = child.global_position
					child.top_level = true
					child.global_position = gp
				_make_node_draggable(child, child.name)
		
	# Ventanas Mayores
	var wins = ["CenterStats", "RadarWindow", "ChatUI", "PartyHUD", "ControlBar"]
	if SettingsManager and SettingsManager.mobile_mode:
		wins.append("VirtualJoystick")
		
	for win_id in wins:
		var win = _get_hud_node(win_id)
		if win:
			if is_editing_layout:
				win.visible = true
				var gp = win.global_position
				win.top_level = true
				win.global_position = gp
				win.mouse_filter = Control.MOUSE_FILTER_STOP
			
			_make_node_draggable(win, win_id)

func _make_node_draggable(node: Control, _hud_id: String):
	if not node: return
	
	var overlay = node.get_node_or_null("DragOverlay")
	if is_editing_layout:
		if not overlay:
			overlay = ColorRect.new()
			overlay.name = "DragOverlay"
			overlay.color = Color(0, 1, 1, 0.4)
			overlay.mouse_filter = Control.MOUSE_FILTER_STOP
			
			var border = ReferenceRect.new()
			border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			border.border_color = Color.CYAN
			border.border_width = 3
			border.editor_only = false
			overlay.add_child(border)
			node.add_child(overlay)
			
			if node is Container:
				overlay.top_level = true
				overlay.anchor_right = 0
				overlay.anchor_bottom = 0
				var sync = func(): 
					overlay.global_position = node.global_position
					overlay.size = node.size
				node.resized.connect(sync)
				node.item_rect_changed.connect(sync)
				sync.call()
			else:
				overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		overlay.visible = true
		node.move_child(overlay, node.get_child_count() - 1)
		
		var t_btn = node.get_node_or_null("TouchButton")
		if t_btn: t_btn.disabled = true
	elif overlay:
		overlay.visible = false
		var t_btn = node.get_node_or_null("TouchButton")
		if t_btn: t_btn.disabled = false

var _dragging_node: Control = null
var _drag_offset: Vector2 = Vector2.ZERO
var _node_start_positions: Dictionary = {}

func apply_layout_slot(index: int):
	if index < 0: return
	
	var slot = null
	if index < _hud_layouts.size():
		slot = _hud_layouts[index]
	
	if slot and slot.has("positions") and not slot.positions.is_empty():
		_apply_hud_data(slot.positions, {})
		print("[MainHUD] Slot aplicado: ", slot.name)
		
		active_slot_index = index
		if NetworkManager:
			NetworkManager.current_user_data["hudPositions"] = slot.positions
			NetworkManager.current_user_data["hud_layout"] = slot.positions
			
			var payload = { "positions": slot.positions }
			NetworkManager.send_event("saveHudLayout", payload)
	else:
		print("[MainHUD] Slot vacío, restaurando default.")
		active_slot_index = -1
		_restore_default_layout()

func _save_hud_positions(slot_index: int = -1, slot_name: String = ""):
	var screen_size = get_viewport_rect().size
	var get_normalized_pos = func(win: Control, original_w: float, original_h: float):
		var ns = win.size
		if win.name == "CenterStats": ns = Vector2(320, 200)
		elif win.name == "RadarWindow": ns = Vector2(280, 280)
		elif "Chat" in win.name: ns = Vector2(320, 200)
		elif "Party" in win.name: ns = Vector2(200, 80)
		elif "ControlBar" in win.name: ns = Vector2(280, 45)
		elif ns.x <= 0: ns = win.get_combined_minimum_size()
		if ns.x <= 0: ns = Vector2(100, 100)
		
		ns *= win.scale
		var nx = 0.0
		var ny = 0.0
		
		# Inverso X
		if win.global_position.x + (ns.x / 2.0) > (screen_size.x / 2.0):
			var margin_right = screen_size.x - (win.global_position.x + ns.x)
			nx = original_w - ns.x - margin_right
		else:
			nx = win.global_position.x
			
		# Inverso Y
		if win.global_position.y + (ns.y / 2.0) > (screen_size.y / 2.0):
			var margin_bottom = screen_size.y - (win.global_position.y + ns.y)
			ny = original_h - ns.y - margin_bottom
		else:
			ny = win.global_position.y
			
		return Vector2(nx, ny)

	var layout = {}
	if skills_hud:
		var npos = get_normalized_pos.call(skills_hud, 1280.0, 800.0)
		layout["SkillsContainer"] = { 
			"x": npos.x, "y": npos.y,
			"scale": skills_hud.scale.x / 2.0, "alpha": skills_hud.modulate.a
		}
		for child in skills_hud.get_children():
			if child.name == "DragOverlay": continue
			var cpos = get_normalized_pos.call(child, 1280.0, 800.0)
			layout[child.name] = { 
				"x": cpos.x, "y": cpos.y,
				"scale": child.scale.x / 2.0, "alpha": child.modulate.a
			}
	
	for win_id in ["CenterStats", "RadarWindow", "ChatUI", "VirtualJoystick", "PartyHUD", "ControlBar"]:
		var win = _get_hud_node(win_id)
		if win:
			var wpos = get_normalized_pos.call(win, 1280.0, 800.0)
			layout[win_id] = { 
				"x": wpos.x, "y": wpos.y,
				"scale": win.scale.x / 2.0, "alpha": win.modulate.a
			}
	
	if NetworkManager:
		NetworkManager.current_user_data["hudPositions"] = layout
		NetworkManager.current_user_data["hud_layout"] = layout
		
		_update_active_slot_index(layout)
		
		var payload = { "positions": layout }
		if slot_index >= 0:
			payload["slotIndex"] = slot_index
			payload["name"] = slot_name
			if slot_index < _hud_layouts.size():
				_hud_layouts[slot_index].positions = layout
				if slot_name != "": _hud_layouts[slot_index].name = slot_name
		
		active_slot_index = slot_index
		NetworkManager.send_event("saveHudLayout", payload)

func _backup_layout():
	_layout_backup.clear()
	var screen_size = get_viewport_rect().size
	var scale_x = 1280.0 / screen_size.x
	var scale_y = 800.0 / screen_size.y

	if skills_hud:
		_layout_backup["SkillsContainer"] = { 
			"x": skills_hud.global_position.x * scale_x, "y": skills_hud.global_position.y * scale_y,
			"scale": skills_hud.scale.x / 2.0, "alpha": skills_hud.modulate.a
		}
		for child in skills_hud.get_children():
			if child is Control and child.name != "DragOverlay":
				_layout_backup[child.name] = { 
					"x": child.global_position.x * scale_x, "y": child.global_position.y * scale_y,
					"scale": child.scale.x / 2.0, "alpha": child.modulate.a
				}
	
	for win_id in ["CenterStats", "RadarWindow", "ChatUI", "VirtualJoystick", "PartyHUD", "ControlBar"]:
		var win = _get_hud_node(win_id)
		if win:
			_layout_backup[win_id] = { 
				"x": win.global_position.x * scale_x, "y": win.global_position.y * scale_y,
				"scale": win.scale.x / 2.0, "alpha": win.modulate.a
			}

func _restore_layout_backup():
	if _layout_backup.is_empty(): return
	_apply_hud_data(_layout_backup, {})

# --- v305.95: SISTEMA DE MARCOS DINÁMICOS ---
func _apply_sci_fi_frame(node: Control, invisible: bool = false, show_glow: bool = true, show_rivets: bool = true):
	if not node: return
	
	node.clip_contents = true
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var clean_node = func(target, recursive_func):
		for child in target.get_children():
			var c_name = child.name.to_lower()
			if c_name == "header" or c_name == "title" or c_name == "titlebar" or c_name == "min":
				child.visible = false
			
			if child is VBoxContainer or child.name == "Minimap" or child.name == "VBox" or child.name == "Scroll":
				var margin = 25
				if target.name.contains("Slot"): margin = 5
				
				child.anchor_left = 0; child.anchor_top = 0
				child.anchor_right = 1; child.anchor_bottom = 1
				child.offset_left = margin; child.offset_top = margin
				child.offset_right = -margin; child.offset_bottom = -margin
				
			if child is PanelContainer or child is Panel:
				child.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
				child.clip_contents = true
			
			if child is Label and (child.text.contains("SISTEMA") or child.text.contains("LOBY") or child.text.contains("CHAT")):
				child.visible = false
			recursive_func.call(child, recursive_func)

	if node is PanelContainer or node is Panel or node is Control:
		node.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		if node.name == "CenterStats": node.custom_minimum_size = Vector2(250, 140)
		elif node.name == "RadarWindow": node.custom_minimum_size = Vector2(220, 220)
		elif "Chat" in node.name: node.custom_minimum_size = Vector2(320, 200)
		elif "Party" in node.name: node.custom_minimum_size = Vector2(200, 80)
		elif "ControlBar" in node.name: node.custom_minimum_size = Vector2(280, 45)
		elif "Slot" in node.name: 
			node.custom_minimum_size = Vector2(65, 65)
			node.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			if node is Button: 
				node.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
				node.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
				node.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	
	clean_node.call(node, clean_node)
	if invisible: return
	
	var frame_script = load("res://scripts/ui/HUDFrame.gd")
	if not frame_script: return
	var frame = Control.new(); frame.set_script(frame_script); frame.name = "SciFiFrame"
	if "show_glow" in frame: frame.set("show_glow", show_glow)
	if "show_rivets" in frame: frame.set("show_rivets", show_rivets)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if node is Container:
		frame.top_level = true
		frame.anchor_right = 0
		frame.anchor_bottom = 0
		var sync_f = func():
			frame.global_position = node.global_position
			frame.size = node.size
		node.resized.connect(sync_f)
		node.item_rect_changed.connect(sync_f)
		sync_f.call()
	else:
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	node.add_child(frame)
	node.move_child(frame, 0)

# --- v300.060: GESTIÓN DE TRADE ---
func _on_trade_invitation_received(data):
	is_selecting_trade_target = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(300, 120)
	panel.name = "TradeInvitePopup"
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.05, 0.1, 0.9)
	sb.border_width_left = 3; sb.border_color = Color.CYAN
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "SOLICITUD DE COMERCIO"
	title.add_theme_color_override("font_color", Color.CYAN)
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)
	
	var info = Label.new()
	info.text = data.fromName.to_upper() + " quiere comerciar."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(hbox)
	
	var btn_acc = Button.new()
	btn_acc.text = "ACEPTAR"
	btn_acc.modulate = Color.GREEN
	btn_acc.pressed.connect(func():
		NetworkManager.send_event("tradeAcceptInvite", data.fromId)
		panel.queue_free()
	)
	hbox.add_child(btn_acc)
	
	var btn_rej = Button.new()
	btn_rej.text = "RECHAZAR"
	btn_rej.modulate = Color.RED
	btn_rej.pressed.connect(func(): panel.queue_free())
	hbox.add_child(btn_rej)
	
	add_child(panel)
	
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.pivot_offset = panel.custom_minimum_size / 2.0
	panel.scale = Vector2.ZERO
	
	var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.4)
	
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(panel):
		var tw2 = create_tween()
		tw2.tween_property(panel, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw2.finished.connect(panel.queue_free)

func _on_trade_started(data):
	var old = get_node_or_null("TradeHUD")
	if old: 
		old.queue_free()

	var trade_scene = load("res://scripts/ui/TradeHUD.gd")
	if trade_scene:
		var trade_hud = CanvasLayer.new()
		trade_hud.name = "TradeHUD_" + str(Time.get_ticks_msec())
		trade_hud.layer = 100
		
		trade_hud.set_script(trade_scene)
		_build_trade_ui_runtime(trade_hud)
		add_child(trade_hud)
		
		trade_hud.setup(data)

func _build_trade_ui_runtime(node):
	var main_frame = Panel.new()
	main_frame.name = "MainFrame"
	node.add_child(main_frame)
	
	main_frame.anchor_left = 0.1
	main_frame.anchor_right = 0.9
	main_frame.anchor_top = 0.1
	main_frame.anchor_bottom = 0.9
	main_frame.offset_left = 0; main_frame.offset_right = 0
	main_frame.offset_top = 0; main_frame.offset_bottom = 0
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0.05, 0.1, 0.95)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color.CYAN; sb.set_corner_radius_all(10)
	main_frame.add_theme_stylebox_override("panel", sb)
	
	var layout = VBoxContainer.new()
	layout.name = "ContentLayout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 15)
	main_frame.add_child(layout)
	
	var header = HBoxContainer.new()
	header.name = "Header"
	var partner_lbl = Label.new()
	partner_lbl.name = "PartnerName"
	partner_lbl.text = "SISTEMA DE COMERCIO INTERGALÁCTICO"
	partner_lbl.add_theme_color_override("font_color", Color.CYAN)
	partner_lbl.add_theme_font_size_override("font_size", 18)
	header.add_child(partner_lbl)
	
	var spacer = Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(spacer)
	
	var close_btn = Button.new(); close_btn.name = "CloseButton"; close_btn.text = " X "; header.add_child(close_btn)
	close_btn.pressed.connect(func():
		if NetworkManager: NetworkManager.send_event("tradeCancel", {})
		node.queue_free()
	)
	
	layout.add_child(header)
	layout.add_child(HSeparator.new())
	
	var columns_container = HBoxContainer.new()
	columns_container.name = "Columns"
	columns_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_container.add_theme_constant_override("separation", 15)
	layout.add_child(columns_container)
	
	var col_names = ["TU OFERTA", "SU OFERTA", "BODEGA", "EQUIPADO"]
	var col_ids = ["MySide", "PartnerSide", "InventorySide", "EquippedSide"]
	
	for i in range(4):
		var col = VBoxContainer.new()
		col.name = col_ids[i]
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var title = Label.new()
		title.text = col_names[i]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", Color.AQUA)
		col.add_child(title)
		
		var scroll = ScrollContainer.new()
		scroll.name = "ScrollContainer" 
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(scroll)
		
		var grid = GridContainer.new()
		grid.name = "OfferGrid" if i < 2 else ("InventoryGrid" if i == 2 else "EquippedGrid")
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		
		columns_container.add_child(col)
		if i < 3: columns_container.add_child(VSeparator.new())
	
	var footer = HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(HSeparator.new())
	
	var status = Label.new(); status.name = "StatusLabel"; status.text = "NEGOCIANDO..."; footer.add_child(status)
	var f_spacer = Control.new(); f_spacer.custom_minimum_size.x = 50; footer.add_child(f_spacer)
	
	var confirm = Button.new()
	confirm.name = "ConfirmButton"
	confirm.text = "CONFIRMAR OFERTA"
	confirm.custom_minimum_size = Vector2(200, 45)
	confirm.modulate = Color.CYAN
	footer.add_child(confirm)
	layout.add_child(footer)

# --- v300.280: FUNCIONES DE SOPORTE TRADE ---
func _on_esc_trade_pressed():
	_close_esc_menu()
	is_selecting_trade_target = true
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	notify("MODO COMERCIO: SELECCIONA UN PILOTO", "info")

func _cancel_trade_selection():
	is_selecting_trade_target = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	for p in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(p) and not p.is_in_group("player"):
			p.modulate = Color.WHITE
			p.scale = Vector2.ONE

func _close_esc_menu():
	if is_instance_valid(_esc_menu): _esc_menu.visible = false

func _get_entity_under_mouse():
	var m_pos = get_global_mouse_position()
	var best_dist = 100.0
	var best_target = null
	
	for p in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(p) and not p.is_in_group("player"):
			var d = m_pos.distance_to(p.global_position)
			if d < best_dist:
				best_dist = d
				best_target = p
	return best_target

var _events_panel: Control = null
func toggle_events_panel():
	if not is_instance_valid(_events_panel):
		var res = load("res://scenes/ui/EventsPanel.tscn")
		if res:
			_events_panel = res.instantiate()
		else:
			_events_panel = Control.new()
			_events_panel.set_script(load("res://scripts/ui/EventsPanel.gd"))
		add_child(_events_panel)
		
	if _events_panel.has_method("toggle"):
		_events_panel.toggle()
	else:
		_events_panel.visible = !_events_panel.visible
