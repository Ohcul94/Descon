extends Control

# MainHUD.gd (Omni-HUD v190.41 - Fixed Skill Cooldowns)

@onready var hubs_label = $CenterStats/VBox/Currency/HUBS
@onready var ohcu_label = $CenterStats/VBox/Currency/OHCU
@onready var lvl_label = $CenterStats/VBox/LevelInfo/LVL
@onready var speed_label = null 

@onready var fps_label = $TopLeft/FPS
@onready var ms_label = $TopLeft/MS
@onready var online_label = $TopLeft/ONLINE

@onready var center_stats = $CenterStats
@onready var radar_window = $RadarWindow
@onready var skills_hud = $Skills
@onready var virtual_joystick = null # v266.400

var radar_title: Label = null # v243.60: Titulo del Minimapa (Nombre del Sector)

var _ammo_nodes = {} # Etiquetas de texto de munición
var _ammo_menus = {} # v226.70: Menús anclados a cada botón
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


func _ready():
	add_to_group("hud")
	print("[HUD] Sistema v190.41 inicializado.")
	
	# v266.400: Inyectar Joystick Virtual (Soporte Móvil)
	_setup_joystick()
	_update_joystick_visibility() # v266.570: Ocultar si está desactivado de entrada
	
	# v210.190: Inyectar HUD Notifier (Paridad con Web)
	_setup_notifier()
	
	# v167.30: Inyectar Icono de Escuadrón (REPLICA TOTAL v190.60)
	# v238.10: Inyectar Iconos Táctiles (Inventario y Admin para Tablets)
	var c_bar = get_node_or_null("ControlBar")
	if c_bar:
		# v238.20: Sincronía Táctil Autorizativa (Esperar al Login)
		if NetworkManager:
			if not NetworkManager.login_success.is_connected(_setup_touch_buttons):
				NetworkManager.login_success.connect(func(_d): _setup_touch_buttons())
		
		# Icono Squad (Siempre Visible)
		if not c_bar.has_node("IconSquad"):
			var btn = Button.new()
			btn.name = "IconSquad"
			btn.text = "👥"
			btn.custom_minimum_size = Vector2(32,32)
			var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.1,0.1,0.1,0.6); sb.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", sb)
			btn.pressed.connect(_on_icon_pressed.bind("Squad"))
			c_bar.add_child(btn)
			c_bar.move_child(btn, 0)
			
	# v266.155: Soporte para cambio de resolución en tiempo real
	get_viewport().size_changed.connect(_on_viewport_resize)


	
	_aggressive_hide(self)
	_update_icon_tooltips()
	
	for child in get_children():
		if child.has_method("toggle_minimize"):
			if not child.minimized.is_connected(_on_minimize_pressed):
				child.minimized.connect(_on_minimize_pressed)
	
	_ammo_nodes["laser"] = get_node_or_null("Skills/LaserSlot/ammo-q")
	_ammo_nodes["missile"] = get_node_or_null("Skills/MissileSlot/ammo-w")
	_ammo_nodes["mine"] = get_node_or_null("Skills/MineSlot/ammo-e")
	if center_stats:
		center_stats.visible = true
		var vbox = center_stats.get_node_or_null("VBox")
		if vbox:
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
			vbox.add_theme_constant_override("separation", 10)
			
			if not is_instance_valid(speed_label):
				speed_label = Label.new()
				speed_label.name = "SpeedLabel"
				speed_label.add_theme_font_size_override("font_size", 10)
				speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				speed_label.modulate = Color.YELLOW
				vbox.add_child(speed_label)
		
	# v214.195: Conexión de slots de esferas para desequipar
	var s1 = get_node_or_null("Skills/Sphere1Slot")
	var s2 = get_node_or_null("Skills/Sphere2Slot")
	var s3 = get_node_or_null("Skills/Sphere3Slot")
	var s4 = get_node_or_null("Skills/Sphere4Slot")
	
	# v230.10: Inyección dinámica del 4to slot si no existe en la escena
	if not s4 and s3:
		s4 = s3.duplicate()
		s4.name = "Sphere4Slot"
		s3.get_parent().add_child(s4)
		# Ajustar posición si no es un contenedor automático
		if not s3.get_parent() is BoxContainer:
			s4.position = s3.position + Vector2(s3.size.x + 10, 0)
		
		# Forzar etiquetas de ATQ / F
		for child in s4.find_children("*", "Label", true, false):
			if child.text == "CUR" or child.text == "MOV" or child.text == "DEF":
				child.text = "ATQ"
			if child.text == "D" or child.text == "A" or child.text == "S":
				child.text = "F"
		print("[HUD] Sphere4Slot inyectado dinámicamente.")

	if s1: _make_clickable(s1, _on_sphere_slot_gui_input.bind(null, 0))
	if s2: _make_clickable(s2, _on_sphere_slot_gui_input.bind(null, 1))
	if s3: _make_clickable(s3, _on_sphere_slot_gui_input.bind(null, 2))
	if s4: _make_clickable(s4, _on_sphere_slot_gui_input.bind(null, 3))
	
	var sl = get_node_or_null("Skills/LaserSlot")
	var smi = get_node_or_null("Skills/MissileSlot")
	var sei = get_node_or_null("Skills/MineSlot")
	if sl: _make_clickable(sl, _on_base_slot_gui_input.bind(null, "laser"))
	if smi: _make_clickable(smi, _on_base_slot_gui_input.bind(null, "missile"))
	if sei: _make_clickable(sei, _on_base_slot_gui_input.bind(null, "mine"))
	
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

func _setup_joystick():
	if virtual_joystick: return
	var joy_script = load("res://scripts/ui/VirtualJoystick.gd")
	if joy_script:
		virtual_joystick = joy_script.new()
		virtual_joystick.name = "VirtualJoystick"
		add_child(virtual_joystick)
		virtual_joystick.joystick_updated.connect(_on_joystick_updated)
		print("[HUD] Joystick Virtual inyectado.")

func _on_joystick_updated(dir: Vector2):
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_method("set_joystick_direction"):
		p.set_joystick_direction(dir)

func _update_joystick_visibility():
	if virtual_joystick:
		var enabled = SettingsManager.mobile_mode if SettingsManager else false
		virtual_joystick.visible = enabled
		# v266.690: Siempre IGNORE. El joystick usa _input() manual.
		virtual_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if enabled:
			# Restaurar posición si está habilitado
			if NetworkManager and NetworkManager.current_user_data.has("hudPositions"):
				var data = NetworkManager.current_user_data["hudPositions"]
				if data.has("VirtualJoystick"):
					_apply_hud_data({"VirtualJoystick": data["VirtualJoystick"]}, {})
				else:
					# Si no hay guardado, poner default
					virtual_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
		else:
			# v266.760: No lo mandamos al limbo, solo lo ocultamos. 
			# Si lo mandamos al limbo, hay que restaurarlo bien al habilitar.
			virtual_joystick.visible = false
			virtual_joystick.global_position = Vector2(-2000, -2000) 


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
		
		# v266.300: Determinar slot activo (comparación de posiciones)
		_update_active_slot_index(layout)

func _update_active_slot_index(current_layout: Dictionary):
	if _hud_layouts.is_empty(): 
		active_slot_index = -1
		return
		
	# Comparar el layout actual con los slots para ver cuál coincide mejor
	for i in range(_hud_layouts.size()):
		var slot = _hud_layouts[i]
		if slot and slot.has("positions"):
			if str(slot.positions) == str(current_layout):
				active_slot_index = i
				return
	active_slot_index = -1 # No coincide con ninguno (modificado manual)

func _input(event: InputEvent):
	# v266.120: Atajo de teclado para cerrar edición
	if is_editing_layout and event.is_action_pressed("ui_menu"):
		toggle_hud_editing()
		get_viewport().set_input_as_handled()
		return
		
	# v266.99: Sistema Absoluto de Arrastre por Geometría
	if is_editing_layout:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var clicked_node = null
				var handle = get_node_or_null("SkillsMasterHandle")
				
				# 1. Chequear manija maestra
				if handle and handle.visible and handle.get_global_rect().has_point(event.position):
					clicked_node = get_node_or_null("Skills")
				
				# 2. Chequear slots individuales (en orden inverso)
				if not clicked_node:
					var sc = get_node_or_null("Skills")
					if sc:
						for i in range(sc.get_child_count() - 1, -1, -1):
							var child = sc.get_child(i)
							if child is Control and child.name != "DragOverlay" and child.visible:
								if child.get_global_rect().has_point(event.position):
									clicked_node = child
									break
				
				# 3. v266.220: Chequear Ventanas Mayores (Stats, Mapa, Chat)
				if not clicked_node:
					for win_id in ["CenterStats", "RadarWindow", "ChatUI", "VirtualJoystick"]:
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
						_selected_node_for_editing = clicked_node # Marcar para los sliders
						var pp = edit_ui.find_child("PropertyPanel", true, false)
						if pp:
							pp.visible = true
							var t_name = pp.find_child("TargetName", true, false)
							if t_name: t_name.text = clicked_node.name.to_upper()
							
							var s_slider = pp.find_child("ScaleSlider", true, false)
							if s_slider: s_slider.value = clicked_node.scale.x / 2.0
							
							var a_slider = pp.find_child("AlphaSlider", true, false)
							if a_slider: a_slider.value = clicked_node.modulate.a
							
							# Actualizar los labels de % iniciales
							var s_val = pp.find_child("ScaleVal", true, false)
							if s_val: s_val.text = str(int(clicked_node.scale.x * 100)) + "%"
							var a_val = pp.find_child("AlphaVal", true, false)
							if a_val: a_val.text = str(int(clicked_node.modulate.a * 100)) + "%"
					
					# Si movemos el contenedor, también movemos los hijos porque son top_level
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

	# v244.60: Bloquear menú de sistema en el login
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
	# v2.7: Bloqueo de seguridad para ESC (Si hay algún menú de UI abierto)
	var ui_nodes = get_tree().get_nodes_in_group("inventory_ui")
	for ui in ui_nodes:
		if ui.visible: return

	# v266.160: Bloquear shortcuts si el usuario está escribiendo (Chat, etc)
	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	if event.is_action_pressed("ui_menu"):
		toggle_esc_menu()
		get_viewport().set_input_as_handled()
	
	if event.is_action_pressed("ui_party"):
		_on_icon_pressed("Party")
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
			if rx <= 2.0 and ry <= 2.0:
				# Posicionamiento porcentual (0.0 - 1.0)
				final_pos = Vector2(rx * screen_size.x, ry * screen_size.y)
			else:
				# Posicionamiento absoluto (Pixeles)
				# v266.150: Adaptar posición absoluta a nueva resolución si es necesario
				# Asumimos que el layout original era para 1280x800 (base del proyecto)
				var scale_x = screen_size.x / 1280.0
				var scale_y = screen_size.y / 800.0
				final_pos = Vector2(rx * scale_x, ry * scale_y)
			
			# v266.510: Ajuste de Escala (0.5 = 100% original)
			var sc_val = float(pos_data.get("scale", 0.5))
			var final_sc = sc_val * 2.0
			node.scale = Vector2(final_sc, final_sc)
			node.modulate.a = float(pos_data.get("alpha", 1.0))

			# Clampear para que no se salga de la pantalla
			var node_size = node.size * node.scale if node.size.x > 0 else Vector2(100, 100) * final_sc
			final_pos.x = clamp(final_pos.x, 0, screen_size.x - node_size.x)
			final_pos.y = clamp(final_pos.y, 0, screen_size.y - node_size.y)
			node.global_position = final_pos
	
	# v266.157: Restaurar el bucle de visibilidad que se movió por error
	for win_id in config:
		var node = _get_hud_node(win_id)
		if node: node.visible = bool(config[win_id])

func _on_viewport_resize():
	# v266.156: Re-aplicar layout al cambiar el tamaño de la ventana
	if not is_instance_valid(NetworkManager): return
	var data = NetworkManager.current_user_data
	if typeof(data) == TYPE_DICTIONARY and data.has("hud_layout"):
		_apply_hud_data(data["hud_layout"], data.get("hud_config", {}))

func _process(_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		visible = false
		return
	else:
		visible = true
	
	_handle_ammo_selector()
	
	if is_instance_valid(lvl_label):
		var p_exp = p_node.get("current_exp")
		if p_exp == null: p_exp = 0.0
		var lvl = p_node.get("level")
		if lvl == null: lvl = 1
		
		# v193.15: Meta Exponencial Sincronizada (Lvl^1.5 * 1000)
		var next_exp = floor(1000.0 * pow(lvl, 1.5))
		var pct = clamp((p_exp / next_exp) * 100, 0, 100)
		lvl_label.text = "LEVEL " + str(lvl) + " | EXP " + str(int(pct)) + "%"
		
	if is_instance_valid(hubs_label): 
		var val = p_node.get("hubs")
		hubs_label.text = "HUBS: " + _format_val(val if val != null else 0)
		
	if is_instance_valid(ohcu_label): 
		var val = p_node.get("ohculianos")
		ohcu_label.text = "OHCU: " + _format_val(val if val != null else 0)

	if is_instance_valid(speed_label):
		var val = p_node.get("speed")
		var s_pts = p_node.get("slow_points")
		if s_pts == null: s_pts = 0.0
		var final_speed = max(0.0, (val if val != null else 0.0) - s_pts)
		speed_label.text = "SPEED: " + str(int(final_speed)) + " KM/H"
		
		# v9.0: Feedback de color si hay slow
		if s_pts > 1.0: speed_label.modulate = Color.CYAN
		else: speed_label.modulate = Color.YELLOW

	if fps_label: fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	if ms_label: ms_label.text = "MS: " + str(NetworkManager.current_ms)
	if is_instance_valid(online_label):
		online_label.text = "ONLINE: " + str(NetworkManager.online_count)
	
	_update_skill_ui("laser", p_node, get_node_or_null("Skills/LaserSlot"))
	_update_skill_ui("missile", p_node, get_node_or_null("Skills/MissileSlot"))
	_update_skill_ui("mine", p_node, get_node_or_null("Skills/MineSlot"))
	
	_update_sphere_ui(0, p_node, get_node_or_null("Skills/Sphere1Slot"))
	_update_sphere_ui(1, p_node, get_node_or_null("Skills/Sphere2Slot"))
	_update_sphere_ui(2, p_node, get_node_or_null("Skills/Sphere3Slot"))
	_update_sphere_ui(3, p_node, get_node_or_null("Skills/Sphere4Slot"))
	
	# v260.95: Sincronizar Etiquetas de Teclas (Slots 1-7)
	_sync_hud_keys()

func _sync_hud_keys():
	var skills_container = get_node_or_null("Skills")
	if not is_instance_valid(skills_container): return

	var all_slots = skills_container.find_children("*Slot", "Control", true, false)
	
	var slot_to_action = {
		"LaserSlot": "slot_1", "MissileSlot": "slot_2", "MineSlot": "slot_3",
		"Sphere1Slot": "slot_4", "Sphere2Slot": "slot_5", 
		"Sphere3Slot": "slot_6", "Sphere4Slot": "slot_7"
	}

	for slot in all_slots:
		var action = slot_to_action.get(slot.name, "")
		if action == "": continue
		
		var lbl = slot.get_node_or_null("BindingLabel")
		if not is_instance_valid(lbl):
			lbl = Label.new()
			lbl.name = "BindingLabel"
			lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.offset_top = 8 
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color.CYAN)
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_constant_override("outline_size", 4)
			slot.add_child(lbl)
			
		if is_instance_valid(lbl):
			var evs = InputMap.action_get_events(action)
			if evs.size() > 0:
				var txt = evs[0].as_text().replace(" (Physical)", "").replace(" - Physical", "")
				if txt.begins_with("Mouse Button"): txt = "M" + txt.replace("Mouse Button ", "")
				lbl.text = txt.to_upper()
			else:
				lbl.text = "-"
			
			slot.move_child(lbl, slot.get_child_count() - 1)
			lbl.visible = true
		
		for child in slot.get_children():
			if child is Label and child.name != "BindingLabel" and child.name != "CD":
				# v266.20: Ocultar si se llama "Key" (el bindeo viejo estático)
				if child.name == "Key":
					child.visible = false
					continue
					
				child.visible = true
				if child.name != "ammo-q" and child.name != "ammo-w" and child.name != "ammo-e":
					child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					child.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
					child.grow_horizontal = Control.GROW_DIRECTION_BOTH

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

func set_map_name(p_name: String):
	if is_instance_valid(radar_title):
		radar_title.text = p_name.to_upper()
	elif is_instance_valid(radar_window):
		# Fallback: Buscarlo si no se capturó en el primer scan
		for child in radar_window.get_children():
			if child is Label:
				var t = child.text.to_upper()
				if "SISTEMA" in t or "RECON" in t or "LOCALIZANDO" in t:
					radar_title = child
					child.text = p_name.to_upper()
					break

var _max_cds = {} # v190.42: Aprendizaje dinmico de CDs reales

func _update_skill_ui(type: String, ref, slot):
	if not slot: return
	var l_fill = slot.get_node_or_null("Fill")
	var l_cd = slot.get_node_or_null("CD")
	var l_am = _ammo_nodes.get(type)
	
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(type, 0.0)
	
	if l_fill:
		# --- SISTEMA DE PORCENTAJE AUTO-ADAPTATIVO (v190.42) ---
		# El HUD aprende cul es el CD mximo real que manda el servidor
		if not _max_cds.has(type) or rv > _max_cds[type]:
			_max_cds[type] = max(rv, 0.5) # El mnimo es 0.5 para el lser
		
		# Si el CD est en 0 por mucho tiempo, reseteamos el mximo (por si cambi ship)
		if rv < 0.01:
			_max_cds[type] = lerp(_max_cds[type], 0.5, 0.01)

		var max_cd = _max_cds[type]
		var pct = clamp(rv / max_cd, 0.0, 1.0)
		
		var parent_h = slot.size.y if slot.size.y > 0 else 65.0
		var parent_w = slot.size.x if slot.size.x > 0 else 65.0
		
		l_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_fill.size = Vector2(parent_w, parent_h * pct)
		# La posición Y hace que la barra baje desde arriba (1.0 - pct)
		l_fill.position = Vector2(0, parent_h * (1.0 - pct))
		l_fill.visible = rv > 0.02
	
	if l_cd:
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1)) + "s"
			
	if l_am and ref.get("ammo") != null:
		var a_list = ref.get("ammo").get(type, [0,0,0,0,0,0])
		var sel_data = ref.get("selected_ammo")
		var sel = sel_data.get(type, 0) if sel_data != null else 0
		var a_count = a_list[sel] if a_list.size() > sel else 0
		l_am.text = "T" + str(int(sel + 1)) + ": " + _format_val(a_count)
		l_am.modulate = Color(1.0, 1.0, 0.0) 
		l_am.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		l_am.offset_bottom = -5 
		l_am.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_am.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l_am.add_theme_font_size_override("font_size", 10)
		l_am.visible = true

func _update_sphere_ui(id: int, ref, slot):
	if not slot: return
	var p_size = slot.size if slot.size.y > 0 else Vector2(65, 65)
	var l_fill = slot.get_node_or_null("Fill")
	
	var key = "sphere_" + str(id)
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(key, 0.0)
	
	if l_fill:
		# --- SISTEMA DE PORCENTAJE AUTO-ADAPTATIVO (v190.42) ---
		if not _max_cds.has(key) or rv > _max_cds[key]:
			_max_cds[key] = max(rv, 1.0)
		
		var max_cd = _max_cds[key]
		var pct = clamp(rv / max_cd, 0.0, 1.0)
		
		l_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_fill.size = Vector2(p_size.x, p_size.y * pct)
		l_fill.position = Vector2(0, p_size.y * (1.0 - pct))
		l_fill.visible = rv > 0.05
	
	var l_cd = slot.get_node_or_null("CD")
	if not l_cd:
		l_cd = Label.new()
		l_cd.name = "CD"
		l_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l_cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_cd.add_theme_color_override("font_color", Color.RED)
		l_cd.add_theme_font_size_override("font_size", 12)
		slot.add_child(l_cd)
	
	if is_instance_valid(l_cd):
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1)) + "s"
		l_cd.modulate = Color.RED
	
	var type_color = Color.WHITE
	var sm = ref.get_node_or_null("SpheresManager")
	var equipped = false
	
	if is_instance_valid(sm) and sm.spheres_data.size() > id:
		var skill = sm.spheres_data[id]["equipped"]
		equipped = skill != null
		if skill:
			var raw_type = "ataque"
			if typeof(skill) == TYPE_DICTIONARY: raw_type = str(skill.get("type", "ataque")).to_lower()
			else: raw_type = str(skill.get("type")).to_lower() if skill.get("type") else "ataque"
			
			if "ataque" in raw_type: type_color = Color.RED
			elif "defensa" in raw_type: type_color = Color.AQUA
			elif "curación" in raw_type or "curacion" in raw_type: type_color = Color.GREEN
			elif "utilidad" in raw_type or "movimiento" in raw_type: type_color = Color.YELLOW
			else: type_color = Color.WHITE
	
	var final_text_color = Color.RED if rv > 0.05 else type_color
	slot.modulate = Color.WHITE 
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6) if equipped else Color(0, 0, 0, 0.2)
	sb.draw_center = true
	sb.border_width_left = 2; sb.border_width_right = 2; sb.border_width_top = 2; sb.border_width_bottom = 2
	sb.border_color = Color.AQUA if equipped else Color(0.2, 0.2, 0.2, 0.5)
	sb.set_corner_radius_all(p_size.x) 
	sb.set_content_margin_all(2)
	sb.anti_aliasing = true
	
	if slot.has_method("add_theme_stylebox_override"):
		slot.add_theme_stylebox_override("normal", sb)
		slot.add_theme_stylebox_override("hover", sb)
		slot.add_theme_stylebox_override("pressed", sb)
		slot.add_theme_stylebox_override("disabled", sb)
		if slot is PanelContainer:
			slot.add_theme_stylebox_override("panel", sb)
	
	# v235.91: Sincronía de Etiquetas Internas
	var short_txt = "VACÍO"
	if equipped:
		if type_color == Color.RED: short_txt = "ATQ"
		elif type_color == Color.AQUA: short_txt = "DEF"
		elif type_color == Color.GREEN: short_txt = "CUR"
		elif type_color == Color.YELLOW: short_txt = "UTIL"

	for child in slot.get_children():
		if child is Label:
			if child.name == "CD":
				child.modulate = Color.RED
				child.add_theme_color_override("font_color", Color.RED)
			elif child.name == "Key":
				pass
			else:
				child.text = short_txt
				child.add_theme_color_override("font_color", final_text_color) 
				child.modulate.a = 1.0 if equipped else 0.3



func _on_minimize_pressed(id: String):
	var node = _get_hud_node(id)
	if node:
		node.visible = false
		_update_icon_state(id, false)

func _on_icon_pressed(id: String):
	if id == "EscMenu":
		toggle_esc_menu()
		return
		
	# Normalizar ID para el sistema de Squad
	var node = _get_hud_node(id)
	if node:
		node.visible = !node.visible
		_update_icon_state(id, node.visible)

func _get_hud_node(id: String):
	var real_id = id
	if id == "Chat": real_id = "ChatUI"
	if id == "Stats": real_id = "CenterStats"
	if id == "Squad" or id == "Party": real_id = "PartyHUD"
	if id == "SkillsContainer": real_id = "Skills"
	if id == "RadarWindow": real_id = "RadarWindow"
	if id == "VirtualJoystick": real_id = "VirtualJoystick"
	
	# 1. Buscar como hijo directo
	var node = get_node_or_null(real_id)
	
	# 2. Buscar dentro de Skills si es un slot
	if not node:
		var sc = get_node_or_null("Skills")
		if sc: node = sc.get_node_or_null(id)
	
	# 3. Buscar en el padre (v266.235: Mayor alcance para ChatUI)
	if not node and get_parent():
		node = get_parent().get_node_or_null(real_id)
		
	# 4. Búsqueda recursiva por nombre en todo el árbol de UI si falla lo anterior
	if not node:
		var all_hud = get_tree().get_nodes_in_group("hud")
		if all_hud.size() > 0:
			node = all_hud[0].find_child(real_id, true, false)
			
	return node

func _update_icon_state(id: String, is_active: bool):
	var icon = get_node_or_null("ControlBar/Icon" + id)
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
				# child.visible = false; child.queue_free() # v243.61: Ya no borramos, ahora lo usamos para el Mapa

func _handle_ammo_selector():
	# v266.161: Bloquear selector si hay foco en un campo de texto
	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	var is_ctrl = Input.is_key_pressed(KEY_CTRL)
	
	if is_ctrl:
		if _ammo_menus.is_empty():
			_create_ammo_menu()
		_toggle_ammo_menu(true)
	else:
		if not _ammo_menus.is_empty():
			_toggle_ammo_menu(false)

func _toggle_ammo_menu(p_show: bool):
	for type in _ammo_menus:
		var m = _ammo_menus[type]
		if is_instance_valid(m):
			m.visible = p_show
	
	if p_show:
		_update_ammo_menu_selection()

func _create_ammo_menu():
	var types = {
		"laser": {"path": "Skills/LaserSlot", "count": 6},
		"missile": {"path": "Skills/MissileSlot", "count": 3},
		"mine": {"path": "Skills/MineSlot", "count": 3}
	}
	
	for t in types:
		var slot_node = get_node_or_null(types[t].path)
		if not slot_node: continue
		
		var old = slot_node.get_node_or_null("AmmoMenu_" + t)
		if old: old.queue_free()

		var menu = VBoxContainer.new()
		menu.name = "AmmoMenu_" + t
		slot_node.add_child(menu)
		_ammo_menus[t] = menu
		
		menu.z_index = 150
		menu.z_as_relative = false
		menu.add_theme_constant_override("separation", 5)
		menu.visible = false
		
		for i in range(types[t].count - 1, -1, -1):
			var slot_p = PanelContainer.new()
			slot_p.custom_minimum_size = Vector2(40, 40)
			slot_p.mouse_filter = Control.MOUSE_FILTER_STOP
			
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0.9)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1, 0.1)
			slot_p.add_theme_stylebox_override("panel", sb)
			
			var lbl = Label.new()
			lbl.text = "T" + str(i+1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 12)
			slot_p.add_child(lbl)
			
			slot_p.gui_input.connect(_on_ammo_slot_clicked.bind(t, i))
			menu.add_child(slot_p)
		
		menu.size = menu.get_combined_minimum_size()
		var slot_width = 64 
		if slot_node is Control: slot_width = slot_node.size.x
		menu.position = Vector2((slot_width/2) - (menu.get_combined_minimum_size().x / 2), -menu.get_combined_minimum_size().y - 10)

func _update_ammo_menu_selection():
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p): return
	
	var sel_data = p.get("selected_ammo")
	if sel_data == null: sel_data = {}
	
	for type in _ammo_menus:
		var menu = _ammo_menus[type]
		var current_sel = sel_data.get(type, 0)
		
		var count = menu.get_child_count()
		for i in range(count):
			var slot = menu.get_child(i)
			var tier_index = count - 1 - i 
			
			var sb = slot.get_theme_stylebox("panel").duplicate()
			if tier_index == current_sel:
				sb.border_color = Color.CYAN
				sb.set_border_width_all(2)
				slot.modulate = Color(1.2, 1.2, 1.2, 1)
			else:
				sb.border_color = Color(1, 1, 1, 0.1)
				sb.set_border_width_all(1)
				slot.modulate = Color(0.7, 0.7, 0.7, 0.8)
			slot.add_theme_stylebox_override("panel", sb)

func _on_ammo_slot_clicked(event: InputEvent, type: String, tier: int):
	if event is InputEventMouseButton and event.pressed:
		var p = get_tree().get_first_node_in_group("player")
		if p and p.has_method("change_ammo"): 
			p.change_ammo(type, tier)
			_update_ammo_menu_selection()
			AudioManager.play_sfx("ui_click")

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
	
	# v252.20: Sistema de Acumulación Inteligente (Evitar Spam)
	var existing = null
	for child in _notifier_container.get_children():
		if child.get_meta("raw_msg", "") == msg:
			existing = child; break
		
		# Agrupación por tipo de recompensa (Ej: RECOMPENSA: +100 EXP)
		if "RECOMPENSA" in msg and "RECOMPENSA" in child.get_meta("raw_msg", ""):
			var units = ["EXP", "HUBS", "OHCU"]
			for u in units:
				if u in msg and u in child.get_meta("raw_msg", ""):
					existing = child; break
			if existing: break

	if existing:
		var old_msg = existing.get_meta("raw_msg", "")
		if "RECOMPENSA" in msg and "RECOMPENSA" in old_msg:
			# Sumar valores numéricos
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
		
		# Para mensajes genéricos, usar contador x2, x3...
		var count = existing.get_meta("count", 1) + 1
		existing.set_meta("count", count)
		existing.text = msg + " x" + str(count)
		_animate_notification(existing, true)
		return

	# Limitar a 5 notificaciones máximas para no tapar la pantalla
	if _notifier_container.get_child_count() >= 5:
		var first = _notifier_container.get_child(0)
		if is_instance_valid(first): first.queue_free()

	var label = Label.new()
	label.text = msg
	label.set_meta("raw_msg", msg)
	label.set_meta("count", 1)
	label.add_theme_font_size_override("font_size", 10)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.7) # Más transparente
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

func _make_clickable(node: Control, callback: Callable):
	if not node: return
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# v266.80: Inyectar un Botón invisible para máxima compatibilidad táctil
	var btn = node.get_node_or_null("TouchButton")
	if not btn:
		btn = Button.new()
		btn.name = "TouchButton"
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.modulate.a = 0 # Invisible
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		node.add_child(btn)
		node.move_child(btn, 0)
		
		# v266.710: Indicador visual de apuntado MOBA (Joystick de Skill)
		var aim_bg = Panel.new()
		aim_bg.name = "AimIndicatorBG"
		aim_bg.size = Vector2(160, 160) # Área de arrastre visual
		aim_bg.position = (node.size / 2) - Vector2(80, 80)
		aim_bg.visible = false
		aim_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = Color(0, 0.5, 1, 0.1)
		style_bg.set_border_width_all(2); style_bg.border_color = Color(0, 0.5, 1, 0.3)
		style_bg.set_corner_radius_all(80)
		aim_bg.add_theme_stylebox_override("panel", style_bg)
		node.add_child(aim_bg)
		
		var aim = Panel.new()
		aim.name = "AimIndicator"
		aim.size = Vector2(40, 40)
		aim.position = (node.size / 2) - Vector2(20, 20)
		aim.visible = false
		aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var style_aim = StyleBoxFlat.new()
		style_aim.bg_color = Color(0, 0.8, 1, 0.4)
		style_aim.set_border_width_all(2); style_aim.border_color = Color(0, 0.8, 1, 0.9)
		style_aim.set_corner_radius_all(20)
		aim.add_theme_stylebox_override("panel", style_aim)
		node.add_child(aim)
	
	# Usamos señales de botón que son más fiables en móvil
	# Limpiar conexiones previas para evitar disparos dobles v266.132
	for sig in [btn.button_down, btn.button_up]:
		for conn in sig.get_connections():
			sig.disconnect(conn.callable)
	
	btn.button_down.connect(func(): callback.call())
	
	btn.button_up.connect(func():
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p._skill_controller:
			var sc = p._skill_controller
			
			# v266.730: Ocultar indicadores
			var aim_ind = node.get_node_or_null("AimIndicator")
			if aim_ind: aim_ind.visible = false
			var aim_bg_ind = node.get_node_or_null("AimIndicatorBG")
			if aim_bg_ind: aim_bg_ind.visible = false
			
			# En Celular: siempre ejecutar al soltar (da tiempo para el arrastre)
			# En PC: respetar cast_mode (1 = ON_RELEASE)
			var is_mobile_btn = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
			if sc.is_aiming and (is_mobile_btn or sc.config.get("cast_mode") == 1):
				sc.execute_skill()
			sc.external_aim_vector = Vector2.ZERO
	)
	
	# v266.730: Manejar touch directo para multi-touch (gui_input recibe ScreenTouch)
	btn.gui_input.connect(_on_touch_button_input.bind(node, callback))

func _on_sphere_slot_gui_input(event: InputEvent, id: int):
	# Fallback para mouse/clics directos si el botón invisible no lo atrapa
	if event == null: # Viene del TouchButton
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p): p.trigger_skill_by_id("sphere_" + str(id))
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			# v266.30: Disparar con Click Izquierdo (Móviles)
			var p = get_tree().get_first_node_in_group("player")
			if is_instance_valid(p) and p.has_method("trigger_skill_by_id"):
				if event.pressed:
					var s_id = "sphere_" + str(id)
					p.trigger_skill_by_id(s_id)
				else:
					var sc = p._skill_controller
					if is_instance_valid(sc) and sc.is_aiming:
						if sc.config.get("cast_mode") == 1:
							sc.execute_skill(true)

func _on_touch_button_input(event: InputEvent, node: Control, callback: Callable):
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p) or not p._skill_controller: return
	var sc = p._skill_controller
	var aim = node.get_node_or_null("AimIndicator")
	var aim_bg = node.get_node_or_null("AimIndicatorBG")
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	
	# ── PRESS (ScreenTouch / Mouse) ──────────────────────────────────────────
	var is_press = (event is InputEventScreenTouch and event.pressed) or \
				   (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_press:
		var g_pos = event.global_position
		node.set_meta("touch_index", event.index if event is InputEventScreenTouch else 0)
		node.set_meta("touch_origin_global", g_pos) # v266.800: ORIGEN GLOBAL (Wild Rift Style)
		callback.call()
		
		if is_mobile:
			# El fondo del indicador se centra donde tocaste (Joystick Flotante)
			if aim_bg:
				aim_bg.visible = true
				aim_bg.global_position = g_pos - (aim_bg.size / 2)
			if aim:
				aim.visible = true
				aim.global_position = g_pos - (aim.size / 2)
		return

	# ── RELEASE ─────────────────────────────────────────────────────────────
	var is_release = (event is InputEventScreenTouch and not event.pressed) or \
					 (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_release:
		var stored_index = node.get_meta("touch_index", -1)
		if event is InputEventScreenTouch and event.index != stored_index: return
		
		if aim: aim.visible = false
		if aim_bg: aim_bg.visible = false
		
		# CRÍTICO: Ejecutar ANTES de limpiar el vector
		# En Celular: siempre ejecutar al soltar (sin importar cast_mode)
		# En PC: solo si cast_mode == ON_RELEASE (1)
		if sc.is_aiming:
			if is_mobile or sc.config.get("cast_mode") == 1:
				sc.execute_skill()
		
		# Limpiar DESPUÉS de ejecutar
		sc.external_aim_vector = Vector2.ZERO
		node.remove_meta("touch_index")
		node.remove_meta("touch_origin_global")
		return

	# ── DRAG (Apuntado MOBA Profesional) ─────────────────────────────────────
	if not is_mobile or not sc.is_aiming: return
	
	var is_drag = (event is InputEventScreenDrag) or \
				  (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if not is_drag: return
	
	if event is InputEventScreenDrag:
		if event.index != node.get_meta("touch_index", -1): return
	
	# CALCULO WILD RIFT: Desplazamiento global puro
	var g_origin = node.get_meta("touch_origin_global", event.global_position)
	var diff_global = event.global_position - g_origin
	
	# Convertir a unidades del mundo (escala de cámara)
	var cam = get_viewport().get_camera_2d()
	var zoom_val = cam.zoom.x if cam else 1.0
	var world_diff = diff_global / zoom_val
	
	var max_range = sc.current_skill.get("range", 500.0)
	var sensitivity = SettingsManager.mobile_aim_sensitivity
	
	if max_range <= 0:
		sc.external_aim_vector = world_diff.normalized() * 300.0 if world_diff.length() > 5 else Vector2.ZERO
	else:
		# 80px de arrastre en pantalla = Rango máximo de la habilidad
		var px_for_max = 80.0 / sensitivity
		var mapped_range = clamp(world_diff.length() * max_range / px_for_max, 10.0, max_range)
		sc.external_aim_vector = world_diff.normalized() * mapped_range if world_diff.length() > 5 else Vector2.ZERO
	
	# Indicador visual (Stick)
	if aim:
		aim.visible = true
		aim.global_position = event.global_position - (aim.size / 2)
	if aim_bg:
		aim_bg.visible = true
		aim_bg.global_position = g_origin - (aim_bg.size / 2)



func _on_base_slot_gui_input(event: InputEvent, skill_id: String):
	if event == null: # Viene del TouchButton
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p): p.trigger_skill_by_id(skill_id)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p):
			if event.pressed:
				p.trigger_skill_by_id(skill_id)
			else:
				# v266.45: Soporte para disparar al SOLTAR si está en ON_RELEASE
				var sc = p._skill_controller
				if is_instance_valid(sc) and sc.is_aiming:
					if sc.config.get("cast_mode") == 1: # ON_RELEASE
						sc.execute_skill()

# --- MENÚ ESC v220.85 ---
func toggle_esc_menu():
	if _esc_menu and _esc_menu.visible:
		_esc_menu.visible = false
		if is_editing_layout: toggle_hud_editing() # v266.90: Guardar y salir al cerrar el menú
		return
	
	if not _esc_menu:
		_create_esc_menu()
	
	_esc_menu.visible = true
	_esc_menu.reset_size() # v229.35: Forzar que Godot recalcule el tamaño antes de centrar
	_esc_menu.global_position = (get_viewport_rect().size - _esc_menu.size) / 2.0

func _restore_default_layout():
	# v266.650: Layout de fábrica = Layout "PC" de Caelli94 (valores exactos de la DB)
	# Resolución base: 1280x800
	if not is_editing_layout:
		active_slot_index = -1
		if NetworkManager:
			NetworkManager.send_event("saveHudLayout", { "positions": {} })
	
	# Layout exacto extraído de MongoDB (Caelli94 - Slot "PC")
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
	}
	
	# Aplicar el layout usando el mismo sistema que usa al cargar del servidor
	_apply_hud_data(default_layout, {})
	
	# Joystick: solo visible si está habilitado, si no -> fuera de pantalla
	var joy = _get_hud_node("VirtualJoystick")
	if joy:
		var joy_enabled = SettingsManager.mobile_mode if SettingsManager else false
		joy.visible = joy_enabled
		# v266.690: Siempre IGNORE. El joystick usa _input() manual, no necesita capturar via GUI.
		joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if joy_enabled:
			joy.global_position = Vector2(20, 680)
		else:
			joy.global_position = Vector2(-2000, -2000)

	
	# Resetear sliders si están visibles
	var editor_ui = get_node_or_null("EditLayoutUI")
	if editor_ui:
		var pp = editor_ui.find_child("PropertyPanel", true, false)
		if pp:
			var s_slider = pp.find_child("ScaleSlider", true, false)
			if s_slider: s_slider.value = 0.5
			var a_slider = pp.find_child("AlphaSlider", true, false)
			if a_slider: a_slider.value = 1.0

	print("[HUD] Layout restaurado de fábrica (Layout PC de referencia).")

	
	# v266.355: Si estamos editando, re-liberar para que el DragOverlay funcione
	if is_editing_layout:
		await get_tree().process_frame # Esperar a que los anchors reposicionen
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
		
		# Reposicionar manija
		var handle = get_node_or_null("SkillsMasterHandle")
		var skills_node = get_node_or_null("Skills")
		if handle and skills_node:
			handle.global_position = skills_node.global_position + Vector2(-35, 0)

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
	vbox.add_child(pvp_btn)
	
	var config_btn = Button.new()
	config_btn.text = "CONFIGURACIONES"
	config_btn.pressed.connect(func():
		_esc_menu.visible = false
		_open_settings()
	)
	vbox.add_child(config_btn)
	
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
	# v190.90: Notificador de Loot Grupal / Individual (Sincronizado con Server)
	var h = int(data.get("hubs", 0))
	var o = int(data.get("ohcu", 0))
	var e = int(data.get("exp", 0))
	
	# Notificaciones separadas por renglón con los valores REALES divididos por el server
	if e > 0: notify("RECOMPENSA: +" + _format_val(e) + " EXP", "success")
	if h > 0: notify("RECOMPENSA: +" + _format_val(h) + " HUBS", "info")
	if o > 0: notify("RECOMPENSA: +" + _format_val(o) + " OHCU", "warn")

func _on_enemy_dead(_data): pass
func _on_reward_received(_data): pass


func _setup_touch_buttons():
	var c_bar = get_node_or_null("ControlBar")
	if not c_bar: return
	
	# v238.25: Verificación de Admin tras Login Exitoso
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): return
	
	# v238.25: Botón Admin removido - Usar Command Center (HTML)
	
	var touch_btns = [
		{"id": "EscMenu", "icon": "⚙️", "tip": "Sistema (ESC)"},
		{"id": "Inventory", "icon": "🎒", "tip": "Inventario (F1)"}
	]
	# v266.200: Botón Admin removido - Usar Command Center (HTML)
	# if is_admin:
	# 	touch_btns.append({"id": "AdminPanel", "icon": "🛠️", "tip": "Admin (F2)"})
	
	for data in touch_btns:
		if c_bar.has_node("Icon" + data.id): continue
		
		var btn = Button.new()
		btn.name = "Icon" + data.id
		btn.text = data.icon
		btn.custom_minimum_size = Vector2(36, 36)
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.6); sb.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", sb)
		
		var h_sb = sb.duplicate(); h_sb.bg_color = Color(0.3, 0.5, 0.6, 0.8); h_sb.border_width_bottom = 2; h_sb.border_color = Color.CYAN
		btn.add_theme_stylebox_override("hover", h_sb)
		
		btn.pressed.connect(_on_icon_pressed.bind(data.id)) # v266.100: Conectar el botón
		
		c_bar.add_child(btn)
		_update_icon_tooltips() # Aplicar nombres tras añadir al padre
		print("[HUD] Botón táctil inyectado: ", data.id)

func _update_icon_tooltips():
	var c_bar = get_node_or_null("ControlBar")
	if not c_bar: return
	
	# v2.9.1: Crear el Label flotante si no existe
	var tooltip_lbl = get_node_or_null("ControlBar/TooltipAnchor/Label")
	if not tooltip_lbl:
		var anchor = Control.new()
		anchor.name = "TooltipAnchor"
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c_bar.add_child(anchor)
		c_bar.move_child(anchor, 0)
		anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		anchor.position.y = -30 # Posición arriba del bar
		
		tooltip_lbl = Label.new()
		tooltip_lbl.name = "Label"
		tooltip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tooltip_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		tooltip_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tooltip_lbl.add_theme_font_size_override("font_size", 12)
		tooltip_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		tooltip_lbl.add_theme_constant_override("outline_size", 4)
		anchor.add_child(tooltip_lbl)
		tooltip_lbl.visible = false

	var names = {
		"Inventory": "Inventario", "AdminPanel": "Admin", "Admin": "Admin",
		"Squad": "Equipo", "Party": "Equipo", "Chat": "Chat",
		"Stats": "Estadísticas", "Map": "Mapa", "Radar": "Minimapa", "RadarWindow": "Minimapa",
		"PvP": "Modo combate", "Talents": "Talentos", "Skills": "Habilidades"
	}
	
	for btn in c_bar.get_children():
		if btn.name == "TooltipAnchor": continue
		
		var b_name = btn.name.replace("Icon", "")
		var final_name = names.get(b_name, b_name)
		
		# Limpiar tooltip nativo para usar el nuestro
		btn.tooltip_text = ""
		
		if not btn.mouse_entered.is_connected(_on_icon_hover.bind(btn, final_name)):
			btn.mouse_entered.connect(_on_icon_hover.bind(btn, final_name))
			btn.mouse_exited.connect(_on_icon_unhover)
		
		if not btn.pressed.is_connected(_on_icon_pressed.bind(b_name)):
			btn.pressed.connect(_on_icon_pressed.bind(b_name))

func _on_icon_hover(btn: Button, txt: String):
	var lbl = get_node_or_null("ControlBar/TooltipAnchor/Label")
	if lbl:
		lbl.text = txt.capitalize() # v2.9.2: Camel Keys (Primera mayúscula, resto minúscula)
		lbl.visible = true
		# Centrar el label sobre el botón específico
		lbl.global_position.x = btn.global_position.x + (btn.size.x / 2) - (lbl.size.x / 2)
		lbl.global_position.y = btn.global_position.y - 25

func _on_icon_unhover():
	var lbl = get_node_or_null("ControlBar/TooltipAnchor/Label")
	if lbl: lbl.visible = false

func _open_settings():
	if not _settings_menu:
		var s_script = load("res://scripts/systems/SettingsUI.gd")
		if s_script:
			# v2.5: Capa de profundidad aislada (CanvasLayer)
			var canvas = CanvasLayer.new()
			canvas.name = "SettingsLayer"
			canvas.layer = 150 # Arriba del chat y minimapa
			add_child(canvas)
			
			_settings_menu = s_script.new()
			canvas.add_child(_settings_menu)
			_settings_menu.closed.connect(func(): toggle_esc_menu())

	if _settings_menu:
		_settings_menu.open()
		# Mover al frente si ya existía el canvas
		var canvas = _settings_menu.get_parent()
		if canvas is CanvasLayer:
			canvas.visible = true
func _setup_blind_overlay():
	if _blind_overlay: return
	_blind_overlay = ColorRect.new()
	_blind_overlay.name = "BlindOverlay"
	_blind_overlay.color = Color(0, 0, 0, 0)
	_blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind_overlay.z_index = 200 # Por encima de todo el HUD
	add_child(_blind_overlay)

func _on_blind_state(data: Dictionary):
	var active = data.get("active", false)
	var tw = create_tween()
	if active:
		tw.tween_property(_blind_overlay, "color:a", 1.0, 0.05) # Casi instantáneo
	else:
		tw.tween_property(_blind_overlay, "color:a", 0.0, 0.1) # Recuperación rápida

# --- SISTEMA DE EDICIÓN DE HUD v266.300 ---
func toggle_hud_editing(slot_index: int = -1):
	if is_editing_layout and slot_index != -1: return # Ya estamos editando
	
	is_editing_layout = !is_editing_layout
	
	# v266.300: UI Consolidada de Modo Edición
	var edit_container = get_node_or_null("EditLayoutUI")
	if is_editing_layout:
		_editing_slot_index = slot_index
		_backup_layout() # Guardar estado previo para poder cancelar
		
		if not edit_container:
			edit_container = CanvasLayer.new()
			edit_container.name = "EditLayoutUI"
			edit_container.layer = 110 # Por encima de todo
			
			# v266.580: Fondo de Cuadrícula para alineación (Shader)
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
			
			var panel = PanelContainer.new()
			panel.name = "TopBar"
			edit_container.add_child(panel)
			
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0.8)
			style.border_width_top = 2; style.border_color = Color.CYAN
			panel.add_theme_stylebox_override("panel", style)
			panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			panel.custom_minimum_size.y = 100
			
			var margin = MarginContainer.new()
			margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			panel.add_child(margin)
			
			var vbox = VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			margin.add_child(vbox)
			
			# Panel de Propiedades (Contextual) - v266.500
			var prop_panel = PanelContainer.new()
			prop_panel.name = "PropertyPanel"
			prop_panel.visible = false
			prop_panel.custom_minimum_size = Vector2(250, 120)
			
			# v266.525: Posicionamiento Robusto en el lateral derecho
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
			
			# Escala
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
			
			var scale_val_lbl = Label.new()
			scale_val_lbl.name = "ScaleVal"
			scale_val_lbl.text = "100%"
			scale_val_lbl.custom_minimum_size.x = 45
			
			scale_slider.value_changed.connect(func(v):
				if _selected_node_for_editing: 
					var final_v = v * 2.0
					_selected_node_for_editing.scale = Vector2(final_v, final_v)
					scale_val_lbl.text = str(int(final_v * 100)) + "%"
					# Si es SkillsContainer, forzar manija
					if _selected_node_for_editing.name == "Skills":
						var handle = get_node_or_null("SkillsMasterHandle")
						if handle: handle.global_position = _selected_node_for_editing.global_position + Vector2(-35, 0)
			)
			scale_row.add_child(scale_slider)
			scale_row.add_child(scale_val_lbl)
			
			# Transparencia
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
			
			var alpha_val_lbl = Label.new()
			alpha_val_lbl.name = "AlphaVal"
			alpha_val_lbl.text = "100%"
			alpha_val_lbl.custom_minimum_size.x = 45
			
			alpha_slider.value_changed.connect(func(v):
				if _selected_node_for_editing: 
					_selected_node_for_editing.modulate.a = v
					alpha_val_lbl.text = str(int(v * 100)) + "%"
			)
			alpha_row.add_child(alpha_slider)
			alpha_row.add_child(alpha_val_lbl)
			
			# --- Botones del Editor ---
			
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
				# v266.585: Toggle seguro para cerrar
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
		
		# Actualizar titulo si cambió el slot
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
	var skills_container = get_node_or_null("Skills")
	if is_instance_valid(skills_container):
		# v266.98: No poner overlay al contenedor (bloquea a los hijos)
		# En su lugar, crear una "manija" maestra al costado
		var handle = get_node_or_null("SkillsMasterHandle")
		if is_editing_layout:
			if not handle:
				handle = Button.new()
				handle.name = "SkillsMasterHandle"
				handle.text = "::" # Símbolo de arrastre
				handle.custom_minimum_size = Vector2(30, 60)
				add_child(handle)
			
			handle.visible = true
			handle.global_position = skills_container.global_position + Vector2(-35, 0)
		elif handle:
			handle.visible = false
			
		for child in skills_container.get_children():
			if child is Control and child.name != "DragOverlay":
				if is_editing_layout:
					var gp = child.global_position
					child.top_level = true # v266.95: Liberar del contenedor para mover libremente
					child.global_position = gp
				_make_node_draggable(child, child.name)
		
	# 2. Ventanas Mayores (v266.560: Solo mostrar joystick si está activo)
	var wins = ["CenterStats", "RadarWindow", "ChatUI"]
	if SettingsManager and SettingsManager.mobile_mode:
		wins.append("VirtualJoystick")
		
	for win_id in wins:
		var win = _get_hud_node(win_id)
		if win:
			_make_node_draggable(win, win_id)

func _make_node_draggable(node: Control, _hud_id: String):
	if not node: return
	
	var overlay = node.get_node_or_null("DragOverlay")
	if is_editing_layout:
		if not overlay:
			overlay = ColorRect.new()
			overlay.name = "DragOverlay"
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.color = Color(0, 1, 1, 0.4) # Más visible
			overlay.mouse_filter = Control.MOUSE_FILTER_STOP # Capturar el clic
			
			var border = ReferenceRect.new()
			border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			border.border_color = Color.CYAN
			border.border_width = 3
			border.editor_only = false
			overlay.add_child(border)
			node.add_child(overlay)
		
		overlay.visible = true
		node.move_child(overlay, node.get_child_count() - 1) # Asegurar que esté ARRIBA
		
		# Desactivar botones táctiles para que no interfieran con el drag
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
		print("[HUD] Aplicado slot: ", slot.name)
		
		# v266.310: Actualizar indicador de slot activo
		active_slot_index = index
		
		# v266.216: Sincronizar Caché Local para evitar reversión en resize
		if NetworkManager:
			NetworkManager.current_user_data["hudPositions"] = slot.positions
			NetworkManager.current_user_data["hud_layout"] = slot.positions
			
			# Persistir al servidor
			var payload = { "positions": slot.positions }
			NetworkManager.send_event("saveHudLayout", payload)
	else:
		# Si el slot está vacío, restaurar default
		print("[HUD] Slot vacío, restaurando layout de fábrica.")
		active_slot_index = -1
		_restore_default_layout()

func _save_hud_positions(slot_index: int = -1, slot_name: String = ""):
	var layout = {}
	var skills_container = get_node_or_null("Skills")
	if skills_container:
		layout["SkillsContainer"] = { 
			"x": skills_container.global_position.x, 
			"y": skills_container.global_position.y,
			"scale": skills_container.scale.x / 2.0,
			"alpha": skills_container.modulate.a
		}
		for child in skills_container.get_children():
			if child.name == "DragOverlay": continue
			layout[child.name] = { 
				"x": child.global_position.x, 
				"y": child.global_position.y,
				"scale": child.scale.x / 2.0,
				"alpha": child.modulate.a
			}
	
	# v266.220: Guardar también posiciones de ventanas principales
	for win_id in ["CenterStats", "RadarWindow", "ChatUI", "VirtualJoystick"]:
		var win = _get_hud_node(win_id)
		if win:
			layout[win_id] = { 
				"x": win.global_position.x, 
				"y": win.global_position.y,
				"scale": win.scale.x / 2.0,
				"alpha": win.modulate.a
			}
	
	if NetworkManager:
		# v266.216: Actualizar caché local
		NetworkManager.current_user_data["hudPositions"] = layout
		NetworkManager.current_user_data["hud_layout"] = layout
		
		# v266.300: Actualizar indicador de slot activo
		_update_active_slot_index(layout)
		
		var payload = { "positions": layout }
		if slot_index >= 0:
			payload["slotIndex"] = slot_index
			payload["name"] = slot_name
			if slot_index < _hud_layouts.size():
				_hud_layouts[slot_index].positions = layout
				if slot_name != "": _hud_layouts[slot_index].name = slot_name
		
		# v266.310: Actualizar indicador de slot activo tras guardar
		active_slot_index = slot_index
		
		NetworkManager.send_event("saveHudLayout", payload)
		print("[HUD] Layout enviado al servidor. Slot: ", str(slot_index) if slot_index >= 0 else "Global")

func _backup_layout():
	_layout_backup.clear()
	# Guardar SkillsContainer
	var sc = get_node_or_null("Skills")
	if sc:
		_layout_backup["SkillsContainer"] = { "x": sc.global_position.x, "y": sc.global_position.y }
		for child in sc.get_children():
			if child is Control and child.name != "DragOverlay":
				_layout_backup[child.name] = { "x": child.global_position.x, "y": child.global_position.y }
	
	# Guardar Ventanas principales
	for win_id in ["CenterStats", "RadarWindow", "ChatUI", "VirtualJoystick"]:
		var win = _get_hud_node(win_id)
		if win:
			_layout_backup[win_id] = { "x": win.global_position.x, "y": win.global_position.y }
	print("[HUD] Backup de layout creado.")

func _restore_layout_backup():
	if _layout_backup.is_empty(): return
	_apply_hud_data(_layout_backup, {})
	print("[HUD] Layout restaurado desde backup.")
