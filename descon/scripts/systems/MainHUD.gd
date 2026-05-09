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

var radar_title: Label = null # v243.60: Titulo del Minimapa (Nombre del Sector)

var _ammo_nodes = {} # Etiquetas de texto de munición
var _ammo_menus = {} # v226.70: Menús anclados a cada botón
var _esc_menu: Control = null
var _settings_menu: Control = null
var _pvp_status: bool = false
var _blind_overlay: ColorRect = null # v260.90: Efecto de Ceguera (Humo)
var is_editing_layout: bool = false


func _ready():
	print("[HUD] Sistema v190.41 inicializado.")
	
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

func _on_game_notification(data: Dictionary):
	var msg = data.get("msg", "")
	var type = data.get("type", "info")
	notify(msg, type)

func _on_server_data_received(p_data: Dictionary):
	if p_data.has("gameData"):
		var gd = p_data.gameData
		var layout = gd.get("hudPositions", gd.get("hud_layout", {}))
		var config = gd.get("hudConfig", gd.get("hud_config", {}))
		_apply_hud_data(layout, config)

func _input(event: InputEvent):
	# v244.60: Bloquear menú de sistema en el login
	if not NetworkManager or not NetworkManager.is_logged_in: return
	
	# v2.7: Bloqueo de seguridad para ESC (Si hay algún menú de UI abierto)
	var ui_nodes = get_tree().get_nodes_in_group("inventory_ui")
	for ui in ui_nodes:
		if ui.visible: return


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
			var rx = float(pos_data.get("x", 0.0))
			var ry = float(pos_data.get("y", 0.0))
			if rx <= 2.0 and ry <= 2.0:
				node.global_position = Vector2(rx * screen_size.x, ry * screen_size.y)
			else:
				node.global_position = Vector2(rx, ry)
	
	for win_id in config:
		var node = _get_hud_node(win_id)
		if node: node.visible = bool(config[win_id])

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

	var all_slots = []
	for child in skills_container.get_children():
		if "Slot" in child.name:
			all_slots.append(child)
	
	all_slots.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)

	for i in range(min(all_slots.size(), 7)):
		var slot = all_slots[i]
		var action = "slot_" + str(i + 1)
		
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
	
	var node = get_node_or_null(real_id)
	if not node:
		var sc = get_node_or_null("Skills")
		if sc: node = sc.get_node_or_null(id) # Probar con el ID original (e.g. LaserSlot)
		
	if not node: node = get_parent().get_node_or_null(real_id)
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
	
	# Usamos señales de botón que son más fiables en móvil
	if not btn.button_down.is_connected(func(): callback.call()):
		btn.button_down.connect(func(): callback.call())
	
	if not btn.button_up.is_connected(func(): 
		# Simular el evento de release para ON_RELEASE
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p._skill_controller:
			var sc = p._skill_controller
			if sc.is_aiming and sc.config.get("cast_mode") == 1:
				sc.execute_skill()
	):
		btn.button_up.connect(func():
			var p = get_tree().get_first_node_in_group("player")
			if is_instance_valid(p) and p._skill_controller:
				var sc = p._skill_controller
				if sc.is_aiming and sc.config.get("cast_mode") == 1:
					sc.execute_skill()
		)

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
					p.trigger_skill_by_id(s_id) # v266.60: Auto-detección en el Player
				else:
					# v266.45: Soporte para disparar al SOLTAR si está en ON_RELEASE
					var sc = p._skill_controller
					if is_instance_valid(sc) and sc.is_aiming:
						if sc.config.get("cast_mode") == 1: # ON_RELEASE
							sc.execute_skill()

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
	
	# v266.90: Botón de Edición de HUD
	var edit_btn = Button.new()
	edit_btn.text = "EDITAR LAYOUT HUD"
	edit_btn.pressed.connect(toggle_hud_editing)
	vbox.add_child(edit_btn)
	
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
	
	var user_name = player.get("username")
	var is_admin = (user_name == "Caelli94")
	
	var touch_btns = [{"id": "Inventory", "icon": "🎒", "tip": "Inventario (F1)"}]
	if is_admin:
		touch_btns.append({"id": "AdminPanel", "icon": "🛠️", "tip": "Admin (F2)"})
	
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

# --- SISTEMA DE EDICIÓN DE HUD v266.90 ---
func toggle_hud_editing():
	is_editing_layout = !is_editing_layout
	print("[HUD] Modo Edición Layout: ", is_editing_layout)
	
	# Si cerramos, guardamos
	if not is_editing_layout:
		_save_hud_positions()
	
	_esc_menu.visible = false # Cerrar menú al editar
	
	# Hacer que todo sea movible
	var skills_container = get_node_or_null("Skills")
	if is_instance_valid(skills_container):
		_make_node_draggable(skills_container, "SkillsContainer")
		for child in skills_container.get_children():
			_make_node_draggable(child, child.name)

func _make_node_draggable(node: Control, hud_id: String):
	if not node: return
	
	var overlay = node.get_node_or_null("DragOverlay")
	if is_editing_layout:
		if not overlay:
			overlay = ColorRect.new()
			overlay.name = "DragOverlay"
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.color = Color(0, 1, 1, 0.3)
			overlay.mouse_filter = Control.MOUSE_FILTER_PASS
			
			var border = ReferenceRect.new()
			border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			border.border_color = Color.CYAN
			border.border_width = 2
			border.editor_only = false
			overlay.add_child(border)
			
			node.add_child(overlay)
			
			# Conectar lógica de arrastre
			overlay.gui_input.connect(_on_drag_input.bind(node, hud_id))
		overlay.visible = true
	elif overlay:
		overlay.visible = false

var _dragging_node: Control = null
var _drag_offset: Vector2 = Vector2.ZERO

func _on_drag_input(event: InputEvent, node: Control, hud_id: String):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging_node = node
				_drag_offset = node.global_position - get_global_mouse_position()
			else:
				_dragging_node = null
	
	if event is InputEventMouseMotion and _dragging_node == node:
		node.global_position = get_global_mouse_position() + _drag_offset

func _save_hud_positions():
	var layout = {}
	var skills_container = get_node_or_null("Skills")
	if skills_container:
		layout["SkillsContainer"] = { "x": skills_container.global_position.x, "y": skills_container.global_position.y }
		for child in skills_container.get_children():
			if child.name == "DragOverlay": continue
			layout[child.name] = { "x": child.global_position.x, "y": child.global_position.y }
	
	if NetworkManager:
		NetworkManager.send_event("saveHUDLayout", { "positions": layout })
		print("[HUD] Layout global guardado en el servidor.")
