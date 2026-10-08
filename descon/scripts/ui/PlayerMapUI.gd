extends Control

# ==============================================================================
# PlayerMapUI.gd - Módulo Standalone de Navegación Galáctica y Mapa de Sectores
# ==============================================================================
# - Ventana flotante/arrastrable "MAPA DE SECTORES GALÁCTICOS" (Atajo: 'M')
# - Selector de sectores interactivo con requerimientos de nivel, PvP y estado de misión
# - Detalles tácticos en tiempo real: Enemigos, % de cofres, tabla de drops y clima ambiental
# - Acceso directo a vista holográfica de mapa completo (WorldMapDialog)
# - Coordinación autoritativa de saltos hiperespaciales con el servidor (changeZone)
# ==============================================================================

var selected_zone_id: int = -1
var is_open: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

static var _item_name_cache: Dictionary = {}

# Referencias de UI
var window_panel: PanelContainer = null
var header_bar: Control = null
var content_container: HBoxContainer = null
var active_modales: Array = []


func _ready():
	add_to_group("map_ui")
	add_to_group("player_map_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	_build_ui_structure()
	_connect_network_signals()


func _connect_network_signals():
	if NetworkManager:
		if not NetworkManager.game_notification.is_connected(_on_game_notification):
			NetworkManager.game_notification.connect(_on_game_notification)
		if NetworkManager.has_signal("config_updated"):
			if not NetworkManager.config_updated.is_connected(_on_server_config_updated):
				NetworkManager.config_updated.connect(_on_server_config_updated)


func _on_server_config_updated(_cfg: Dictionary = {}):
	if is_open:
		update_ui()


func _on_game_notification(data: Dictionary):
	var msg = str(data.get("msg", ""))
	var type = str(data.get("type", "info"))
	if is_open and type == "error":
		_show_result_modal("AVISO DE NAVEGACIÓN", msg)


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
	window_panel.name = "GalacticMapWindow"
	window_panel.custom_minimum_size = Vector2(860, 560)
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
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# ──────────────────────────────────────────────────────────────────────────
	# A. CABECERA Y BOTÓN DE CIERRE
	# ──────────────────────────────────────────────────────────────────────────
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
	icon_title.text = " 🗺️ "
	icon_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(icon_title)

	var title_lbl = Label.new()
	title_lbl.text = "NAVEGACIÓN GALÁCTICA Y SECTORES"
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

	# Contenedor de contenido dinámico
	content_container = HBoxContainer.new()
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("separation", 16)
	main_vbox.add_child(content_container)


# ==============================================================================
# RENDERIZADO DE SECTORES Y DETALLES
# ==============================================================================
func update_ui():
	if not is_open: return
	for n in content_container.get_children():
		content_container.remove_child(n)
		n.queue_free()

	# ──────────────────────────────────────────────────────────────────────────
	# COLUMNA IZQUIERDA: LISTA DE SECTORES
	# ──────────────────────────────────────────────────────────────────────────
	var l_col = VBoxContainer.new()
	l_col.custom_minimum_size.x = 310
	l_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(l_col)

	var l_title = Label.new()
	l_title.text = " SECTORES CONOCIDOS"
	l_title.add_theme_font_size_override("font_size", 11)
	l_title.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	l_col.add_child(l_title)

	var s_scroll = ScrollContainer.new()
	s_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	l_col.add_child(s_scroll)

	var s_list = VBoxContainer.new()
	s_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_list.add_theme_constant_override("separation", 6)
	s_scroll.add_child(s_list)

	var current_zone_id = 1
	var p_node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p_node) and "current_zone" in p_node:
		current_zone_id = p_node.current_zone

	if selected_zone_id == -1:
		selected_zone_id = current_zone_id

	var sectors = []
	if GameConstants and "MAPS_CONFIG" in GameConstants:
		for z_id in GameConstants.MAPS_CONFIG:
			var zone_data = GameConstants.MAPS_CONFIG[z_id]
			var z_id_int = int(z_id)
			if zone_data.has("visible") and zone_data.get("visible") == false and z_id_int != current_zone_id:
				continue
			var sd = zone_data.duplicate()
			sd["id"] = z_id_int
			if not sd.has("color"): sd["color"] = "#ffffff"
			sectors.append(sd)

	var has_current = false
	for s in sectors:
		if s.id == current_zone_id:
			has_current = true
			break

	if not has_current:
		var custom_sector = {
			"id": current_zone_id,
			"name": GameConstants.MAPS_CONFIG.get(str(current_zone_id), {}).get("name", "INSTANCIA"),
			"desc": "Sector inestable y de alta hostilidad.",
			"color": "#ff00ff",
			"warpCost": 0,
			"minLevel": 1
		}
		sectors.append(custom_sector)

	sectors.sort_custom(func(a, b): return a.id < b.id)

	for s in sectors:
		var is_current = (s.id == current_zone_id)
		var is_selected = (s.id == selected_zone_id)

		var is_locked = false
		if s.get("unlockRequired", false) == true and not is_current:
			var unlock_key = "map:" + str(s.id)
			if NetworkManager and not NetworkManager.unlocks_cache.has(unlock_key):
				is_locked = true

		var gate_quest_name = ""
		if not is_locked and not is_current and NetworkManager:
			gate_quest_name = NetworkManager.get_sector_seal_quest(s.id)
			if gate_quest_name != "":
				is_locked = true

		var p = PanelContainer.new()
		p.custom_minimum_size = Vector2(0, 68)
		s_list.add_child(p)

		var sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		if is_selected:
			sb.bg_color = Color(0, 0.8, 1, 0.16)
			sb.border_width_left = 4; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
			sb.border_color = Color.CYAN
		elif is_current:
			sb.bg_color = Color(1, 0.8, 0, 0.12)
			sb.border_width_left = 4; sb.border_color = Color.GOLD
		else:
			sb.bg_color = Color(0.02, 0.04, 0.06, 0.75)
			sb.border_width_left = 3; sb.border_color = Color.from_string(str(s.get("color", "#ffffff")), Color.WHITE)

		p.add_theme_stylebox_override("panel", sb)

		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				selected_zone_id = s.id
				update_ui()
		)

		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		p.add_child(hb)

		var margin_l = Control.new(); margin_l.custom_minimum_size.x = 4; hb.add_child(margin_l)

		var v = VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(v)

		var n = Label.new()
		n.text = str(s.get("name", "SECTOR")).to_upper()
		n.add_theme_font_size_override("font_size", 10)
		if is_current: n.modulate = Color.GOLD
		v.add_child(n)

		var d = Label.new()
		d.text = str(s.get("desc", ""))
		d.add_theme_font_size_override("font_size", 8)
		d.modulate.a = 0.65
		v.add_child(d)

		var pvp_lbl = Label.new()
		pvp_lbl.add_theme_font_size_override("font_size", 8)
		var pvp_mode = str(s.get("pvpMode", "tranquila"))
		match pvp_mode:
			"tranquila":
				pvp_lbl.text = "🕊️ Zona Tranquila"
				pvp_lbl.modulate = Color(0.2, 0.9, 0.4)
			"mandatory":
				pvp_lbl.text = "⚔️ PvP Obligatorio"
				pvp_lbl.modulate = Color(1.0, 0.6, 0.1)
			"partial_drop":
				pvp_lbl.text = "🎒 PvP + Loot Parcial"
				pvp_lbl.modulate = Color(1.0, 0.8, 0.2)
			"full_drop":
				pvp_lbl.text = "💀 PvP + Loot Total"
				pvp_lbl.modulate = Color(1.0, 0.2, 0.2)
			"inferno":
				pvp_lbl.text = "🔥 INFIERNO - Nave Destruida"
				pvp_lbl.modulate = Color(1.0, 0.0, 0.0)
			_:
				pvp_lbl.text = "🕊️ Zona Neutral"
				pvp_lbl.modulate = Color(0.3, 0.9, 0.5)
		v.add_child(pvp_lbl)

		if is_locked:
			var lock_lbl = Label.new()
			lock_lbl.text = "🔒 PORTAL SELLADO" if gate_quest_name != "" else "🔒 SECTOR SELLADO"
			lock_lbl.modulate = Color(1.0, 0.35, 0.35)
			lock_lbl.add_theme_font_size_override("font_size", 8)
			v.add_child(lock_lbl)

		if is_current:
			var st = Label.new(); st.text = "📍 ESTÁS AQUÍ"; st.modulate = Color.GOLD; st.add_theme_font_size_override("font_size", 8); v.add_child(st)

		var raw_cost = s.get("warpCost")
		var cost = int(raw_cost) if raw_cost != null and (typeof(raw_cost) == TYPE_INT or typeof(raw_cost) == TYPE_FLOAT or (typeof(raw_cost) == TYPE_STRING and raw_cost.is_valid_int())) else 10

		var raw_min = s.get("minLevel")
		var min_level = int(raw_min) if raw_min != null and (typeof(raw_min) == TYPE_INT or typeof(raw_min) == TYPE_FLOAT or (typeof(raw_min) == TYPE_STRING and raw_min.is_valid_int())) else 1

		var current_level = 1
		if is_instance_valid(p_node) and "level" in p_node:
			current_level = int(p_node.level)

		var can_enter = current_level >= min_level

		var btns_vbox = VBoxContainer.new()
		btns_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(btns_vbox)

		var btn_travel = Button.new()
		if is_locked:
			btn_travel.text = "🔒 BLOQUEADO"
			btn_travel.modulate = Color(1.0, 0.3, 0.3)
			btn_travel.disabled = true
		elif not can_enter:
			btn_travel.text = "NIVEL " + str(min_level)
			btn_travel.modulate = Color.RED
			btn_travel.disabled = true
		else:
			btn_travel.text = ("SPAWN (" + str(cost) + ")") if is_current else ("VIAJAR (" + str(cost) + ")")
			btn_travel.disabled = false

		btn_travel.add_theme_font_size_override("font_size", 8)
		btn_travel.custom_minimum_size = Vector2(76, 24)
		btns_vbox.add_child(btn_travel)

		var margin_r = Control.new(); margin_r.custom_minimum_size.x = 4; hb.add_child(margin_r)

		if can_enter and not is_locked:
			btn_travel.pressed.connect(func():
				_request_warp_to_sector(s, is_current, cost)
			)

	# ──────────────────────────────────────────────────────────────────────────
	# COLUMNA DERECHA: DETALLES TÁCTICOS Y VISTA COMPLETA DEL MAPA
	# ──────────────────────────────────────────────────────────────────────────
	var r_col = VBoxContainer.new()
	r_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_child(r_col)

	var sel_zone_data = {}
	for s in sectors:
		if s.id == selected_zone_id:
			sel_zone_data = s; break

	var top_r_hb = HBoxContainer.new()
	top_r_hb.custom_minimum_size.y = 30
	r_col.add_child(top_r_hb)

	var sel_title = Label.new()
	sel_title.text = "DETALLES TÁCTICOS: " + str(sel_zone_data.get("name", "SECTOR")).to_upper()
	sel_title.add_theme_color_override("font_color", Color.CYAN)
	sel_title.add_theme_font_size_override("font_size", 12)
	sel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_r_hb.add_child(sel_title)

	var btn_view_full = Button.new()
	btn_view_full.text = " 🗺️ VER MAPA COMPLETO "
	btn_view_full.custom_minimum_size = Vector2(165, 26)
	btn_view_full.add_theme_font_size_override("font_size", 9)
	var vf_sb = StyleBoxFlat.new()
	vf_sb.bg_color = Color(0.02, 0.12, 0.18, 0.9)
	vf_sb.border_width_left = 1; vf_sb.border_width_top = 1
	vf_sb.border_width_right = 1; vf_sb.border_width_bottom = 1
	vf_sb.border_color = Color(0.0, 0.85, 1.0, 0.8)
	vf_sb.set_corner_radius_all(4)
	btn_view_full.add_theme_stylebox_override("normal", vf_sb)
	btn_view_full.pressed.connect(_open_full_map_view)
	top_r_hb.add_child(btn_view_full)

	var cols_hb = HBoxContainer.new()
	cols_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hb.add_theme_constant_override("separation", 14)
	r_col.add_child(cols_hb)

	# Sub-Columna 1: Enemigos y Botín (Drops)
	var col_enem = VBoxContainer.new()
	col_enem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols_hb.add_child(col_enem)

	var t_enem = Label.new()
	t_enem.text = "ENEMIGOS Y BOTÍN (DROPS)"
	t_enem.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	t_enem.add_theme_font_size_override("font_size", 10)
	col_enem.add_child(t_enem)

	var scroll_enem = ScrollContainer.new()
	scroll_enem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_enem.add_child(scroll_enem)

	var list_enem = VBoxContainer.new()
	list_enem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_enem.add_theme_constant_override("separation", 6)
	scroll_enem.add_child(list_enem)

	var spawns = sel_zone_data.get("spawns", [])
	var drop_mult = float(sel_zone_data.get("dropMultiplier", 1.0))

	if spawns.is_empty():
		var no_enem = Label.new(); no_enem.text = "No se detecta presencia enemiga hostil."
		no_enem.add_theme_font_size_override("font_size", 9); no_enem.modulate.a = 0.5
		list_enem.add_child(no_enem)
	else:
		var processed_types = []
		for sp in spawns:
			var raw_type = str(sp.get("type", ""))
			if raw_type == "" or raw_type in processed_types: continue
			processed_types.append(raw_type)

			var base_type = raw_type.split("-")[0]
			var enemy_cfg = {}
			if GameConstants and "ENEMY_MODELS" in GameConstants:
				if GameConstants.ENEMY_MODELS.has(raw_type): enemy_cfg = GameConstants.ENEMY_MODELS[raw_type]
				elif GameConstants.ENEMY_MODELS.has(base_type): enemy_cfg = GameConstants.ENEMY_MODELS[base_type]

			var e_panel = PanelContainer.new(); e_panel.custom_minimum_size.y = 48; list_enem.add_child(e_panel)
			var esb = StyleBoxFlat.new(); esb.bg_color = Color(1.0, 0.2, 0.2, 0.04); esb.set_border_width_all(1); esb.border_color = Color(1.0, 0.2, 0.2, 0.25); esb.set_corner_radius_all(4); e_panel.add_theme_stylebox_override("panel", esb)
			var ev = VBoxContainer.new(); ev.add_theme_constant_override("separation", 2); e_panel.add_child(ev)

			var e_name = enemy_cfg.get("name", "Enemigo T" + base_type)
			var e_hp = int(enemy_cfg.get("hp", 100))
			var e_sh = int(enemy_cfg.get("shield", 0))

			var e_title = Label.new(); e_title.text = e_name.to_upper() + " [HP: " + str(e_hp) + " | SH: " + str(e_sh) + "]"
			e_title.add_theme_font_size_override("font_size", 9); e_title.modulate = Color(1.0, 0.6, 0.6); ev.add_child(e_title)

			var c_chance = float(enemy_cfg.get("chestDropChance", 0.1)) * drop_mult
			var c_chance_pct = int(c_chance * 100)
			var e_chance_lbl = Label.new(); e_chance_lbl.text = "Probabilidad de Cofre: " + str(c_chance_pct) + "%"
			e_chance_lbl.add_theme_font_size_override("font_size", 8); e_chance_lbl.modulate = Color.DARK_GRAY; ev.add_child(e_chance_lbl)

			var drops = enemy_cfg.get("lootDrops", [])
			if not drops.is_empty():
				for d in drops:
					var item_id = d.get("itemId", "")
					var item_chance = int(float(d.get("chance", 0.1)) * 100)
					var item_amount = int(d.get("amount", 1))
					var item_name = _get_cached_item_name(item_id)
					var drop_qty = (" x" + str(item_amount)) if item_amount > 1 else ""
					var drop_lbl = Label.new(); drop_lbl.text = "  - " + item_name + drop_qty + " (" + str(item_chance) + "%)"
					drop_lbl.add_theme_font_size_override("font_size", 8); drop_lbl.modulate.a = 0.85; ev.add_child(drop_lbl)

	# Sub-Columna 2: Mecánicas Ambientales
	var col_amb = VBoxContainer.new()
	col_amb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols_hb.add_child(col_amb)

	var t_amb = Label.new()
	t_amb.text = "MECÁNICAS AMBIENTALES"
	t_amb.add_theme_color_override("font_color", Color.YELLOW)
	t_amb.add_theme_font_size_override("font_size", 10)
	col_amb.add_child(t_amb)

	var scroll_amb = ScrollContainer.new()
	scroll_amb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_amb.add_child(scroll_amb)

	var list_amb = VBoxContainer.new()
	list_amb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_amb.add_theme_constant_override("separation", 6)
	scroll_amb.add_child(list_amb)

	var ambience = sel_zone_data.get("ambience", [])
	if ambience.is_empty():
		var no_amb = Label.new(); no_amb.text = "Entorno estable. No se detectan anomalías climáticas."
		no_amb.add_theme_font_size_override("font_size", 9); no_amb.modulate.a = 0.5
		list_amb.add_child(no_amb)
	else:
		for a in ambience:
			var a_type = str(a.get("type", ""))
			var a_panel = PanelContainer.new(); a_panel.custom_minimum_size.y = 48; list_amb.add_child(a_panel)
			var asb = StyleBoxFlat.new(); asb.bg_color = Color(1.0, 0.8, 0, 0.04); asb.set_border_width_all(1); asb.border_color = Color(1.0, 0.8, 0, 0.25); asb.set_corner_radius_all(4); a_panel.add_theme_stylebox_override("panel", asb)
			var av = VBoxContainer.new(); av.add_theme_constant_override("separation", 2); a_panel.add_child(av)

			var a_title_lbl = Label.new()
			var a_desc_lbl = Label.new()
			a_title_lbl.add_theme_font_size_override("font_size", 9); a_title_lbl.modulate = Color.YELLOW
			a_desc_lbl.add_theme_font_size_override("font_size", 8); a_desc_lbl.modulate.a = 0.85

			var a_label = a_type.to_upper().replace("_", " ")
			var a_icon = "⚡"

			if GameConstants and "FULL_CONFIG" in GameConstants and GameConstants.FULL_CONFIG.has("ambienceLib"):
				var ambience_lib = GameConstants.FULL_CONFIG["ambienceLib"]
				if ambience_lib.has(a_type):
					var lib_entry = ambience_lib[a_type]
					if lib_entry.has("label"): a_label = lib_entry["label"]
					if lib_entry.has("icon"): a_icon = lib_entry["icon"]

			a_title_lbl.text = a_icon + " " + a_label.to_upper()

			match a_type:
				"freeze_hazard":
					var slow_pct = int(a.get("slowPercentage", 0))
					var slow_fix = int(a.get("slowFixed", 0))
					var dur = int(round(float(a.get("duration", 3000)) / 1000.0))
					var slow_desc = (str(slow_pct) + "%") if slow_pct > 0 else (str(slow_fix) + " unidades")
					a_desc_lbl.text = "Congela naves periódicamente.\nRalentiza en " + slow_desc + " durante " + str(dur) + "s."
				"radiation":
					var dmg = int(a.get("damage", 10))
					var ms = int(round(float(a.get("intervalMs", 3000)) / 1000.0))
					a_desc_lbl.text = "Campo electromagnético dañino.\nCausa " + str(dmg) + " de daño cada " + str(ms) + "s."
				"interferencia_hazard":
					var dur = int(round(float(a.get("duration", 5000)) / 1000.0))
					a_desc_lbl.text = "Frecuencia de pulso inestable.\nBloquea el uso de habilidades activas durante " + str(dur) + "s."
				"extreme_aggression":
					var h_mult = float(a.get("healthMult", 1.0))
					a_desc_lbl.text = "Zona de combate hiperactiva.\nMultiplicador de HP/Escudo de x" + str(h_mult) + "."
				"multiplicador":
					var mult = float(a.get("multiplier", 1.0))
					a_desc_lbl.text = "Zona con distorsión de poder.\nEnemigos se potencian por x" + str(mult) + "."
				"healing_penalty":
					a_desc_lbl.text = "Inhibe la regeneración de salud de naves en este sector."
				_:
					a_desc_lbl.text = "Anomalía detectada en este sector."

			av.add_child(a_title_lbl)
			av.add_child(a_desc_lbl)


func _open_full_map_view():
	var minimap_node = get_tree().get_first_node_in_group("minimap")
	if not is_instance_valid(minimap_node):
		var hud = get_tree().get_first_node_in_group("hud")
		if hud: minimap_node = hud.find_child("Minimap", true, false)

	if is_instance_valid(minimap_node) and minimap_node.has_method("open_world_map"):
		minimap_node.open_world_map(str(selected_zone_id))
	else:
		var WorldMapDialogScript = load("res://scripts/ui/WorldMapDialog.gd")
		if WorldMapDialogScript:
			var dlg = WorldMapDialogScript.new()
			get_tree().root.add_child(dlg)
			dlg.open(str(selected_zone_id))


func _request_warp_to_sector(sector: Dictionary, is_current: bool, cost: int):
	var p_node = get_tree().get_first_node_in_group("player")
	var ohcu_bal = 0
	if is_instance_valid(p_node) and "ohculianos" in p_node:
		ohcu_bal = int(p_node.ohculianos)

	if ohcu_bal < cost:
		_show_result_modal("FONDOS INSUFICIENTES", "Necesitas " + str(cost) + " OHCU para saltar a este sector.")
		return

	var sector_name = str(sector.get("name", "Sector"))
	var msg = ""
	if is_current:
		msg = "¿Deseas teletransportarte al punto de inicio (Spawn) de [color=cyan]" + sector_name + "[/color]?"
	else:
		msg = "¿Confirmas salto hiperespacial a [color=cyan]" + sector_name + "[/color]?"
	if cost > 0: msg += "\nCosto: [color=yellow]" + str(cost) + " OHCU[/color]"

	_show_confirm_modal("CONFIRMAR SALTO", msg, func():
		if NetworkManager:
			NetworkManager.send_event("changeZone", sector.get("id"))
		toggle()
	)


static func _get_cached_item_name(item_id: String) -> String:
	var clean_id = item_id.to_lower()
	if _item_name_cache.has(clean_id):
		return _item_name_cache[clean_id]

	var item_name = item_id
	if GameConstants and "SHOP_ITEMS" in GameConstants:
		for cat_key in GameConstants.SHOP_ITEMS:
			var category = GameConstants.SHOP_ITEMS[cat_key]
			if category is Array:
				for shop_item in category:
					if str(shop_item.get("id", "")).to_lower() == clean_id:
						item_name = str(shop_item.get("name", item_id))
						_item_name_cache[clean_id] = item_name
						return item_name
			elif category is Dictionary:
				for sub_key in category:
					var sub_list = category[sub_key]
					if sub_list is Array:
						for shop_item in sub_list:
							if str(shop_item.get("id", "")).to_lower() == clean_id:
								item_name = str(shop_item.get("name", item_id))
								_item_name_cache[clean_id] = item_name
								return item_name
	_item_name_cache[clean_id] = item_name
	return item_name


# ==============================================================================
# MODALES Y CONFIRMACIONES
# ==============================================================================
func _show_confirm_modal(title: String, message: String, on_confirm: Callable):
	_close_all_modales()

	# 1. Overlay a pantalla completa con atenuación y bloqueo de clics externos
	var overlay = PanelContainer.new()
	overlay.name = "ConfirmModalOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb_dim = StyleBoxFlat.new()
	sb_dim.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.add_theme_stylebox_override("panel", sb_dim)
	add_child(overlay)
	active_modales.append(overlay)

	# 2. CenterContainer para centrado geométrico perfecto (evita estiramiento vertical)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	# 3. Contenedor Premium Sci-Fi
	var m = PanelContainer.new()
	m.custom_minimum_size = Vector2(440, 200)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.022, 0.038, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color(0.0, 0.85, 1.0, 0.85)
	sb.set_corner_radius_all(8)
	sb.corner_detail = 12
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.75)
	sb.shadow_size = 22
	m.add_theme_stylebox_override("panel", sb)
	center.add_child(m)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	m.add_child(margin)

	var v = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var t = Label.new()
	t.text = "🌌  " + title.to_upper()
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0))
	v.add_child(t)

	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = "[center]" + message + "[/center]"
	rtl.fit_content = true
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rtl)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	v.add_child(hb)

	var btn_cancel = Button.new()
	btn_cancel.text = "CANCELAR"
	btn_cancel.custom_minimum_size = Vector2(130, 36)
	btn_cancel.add_theme_font_size_override("font_size", 10)
	var sb_c = StyleBoxFlat.new()
	sb_c.bg_color = Color(0.08, 0.12, 0.16, 0.7)
	sb_c.border_width_left = 1; sb_c.border_width_top = 1; sb_c.border_width_right = 1; sb_c.border_width_bottom = 1
	sb_c.border_color = Color(0.3, 0.45, 0.6, 0.5)
	sb_c.set_corner_radius_all(5)
	btn_cancel.add_theme_stylebox_override("normal", sb_c)
	var sb_ch = StyleBoxFlat.new()
	sb_ch.bg_color = Color(0.14, 0.18, 0.24, 0.85)
	sb_ch.border_width_left = 1; sb_ch.border_width_top = 1; sb_ch.border_width_right = 1; sb_ch.border_width_bottom = 1
	sb_ch.border_color = Color(0.5, 0.7, 0.9, 0.7)
	sb_ch.set_corner_radius_all(5)
	btn_cancel.add_theme_stylebox_override("hover", sb_ch)
	btn_cancel.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	btn_cancel.pressed.connect(func():
		active_modales.erase(overlay)
		overlay.queue_free()
	)
	hb.add_child(btn_cancel)

	var btn_ok = Button.new()
	btn_ok.text = "CONFIRMAR"
	btn_ok.custom_minimum_size = Vector2(130, 36)
	btn_ok.add_theme_font_size_override("font_size", 10)
	var sb_ok = StyleBoxFlat.new()
	sb_ok.bg_color = Color(0.0, 0.55, 0.75, 0.35)
	sb_ok.border_width_left = 1; sb_ok.border_width_top = 1; sb_ok.border_width_right = 1; sb_ok.border_width_bottom = 1
	sb_ok.border_color = Color(0.0, 0.85, 1.0)
	sb_ok.set_corner_radius_all(5)
	btn_ok.add_theme_stylebox_override("normal", sb_ok)
	var sb_okh = StyleBoxFlat.new()
	sb_okh.bg_color = Color(0.0, 0.7, 0.95, 0.55)
	sb_okh.border_width_left = 1; sb_okh.border_width_top = 1; sb_okh.border_width_right = 1; sb_okh.border_width_bottom = 1
	sb_okh.border_color = Color(0.3, 0.95, 1.0)
	sb_okh.set_corner_radius_all(5)
	btn_ok.add_theme_stylebox_override("hover", sb_okh)
	btn_ok.add_theme_color_override("font_color", Color.WHITE)
	btn_ok.pressed.connect(func():
		active_modales.erase(overlay)
		overlay.queue_free()
		on_confirm.call()
	)
	hb.add_child(btn_ok)


func _show_result_modal(title: String, message: String):
	_close_all_modales()

	var overlay = PanelContainer.new()
	overlay.name = "ResultModalOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb_dim = StyleBoxFlat.new()
	sb_dim.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.add_theme_stylebox_override("panel", sb_dim)
	add_child(overlay)
	active_modales.append(overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var m = PanelContainer.new()
	m.custom_minimum_size = Vector2(400, 180)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.022, 0.038, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = Color(1.0, 0.45, 0.45, 0.85)
	sb.set_corner_radius_all(8)
	sb.corner_detail = 12
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.75)
	sb.shadow_size = 20
	m.add_theme_stylebox_override("panel", sb)
	center.add_child(m)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	m.add_child(margin)

	var v = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var t = Label.new()
	t.text = "⚠️  " + title.to_upper()
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	v.add_child(t)

	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = "[center]" + message + "[/center]"
	rtl.fit_content = true
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rtl)

	var btn_ok = Button.new()
	btn_ok.text = "ENTENDIDO"
	btn_ok.custom_minimum_size = Vector2(130, 34)
	btn_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_ok.add_theme_font_size_override("font_size", 10)
	var sb_ok = StyleBoxFlat.new()
	sb_ok.bg_color = Color(0.8, 0.25, 0.25, 0.35)
	sb_ok.border_width_left = 1; sb_ok.border_width_top = 1; sb_ok.border_width_right = 1; sb_ok.border_width_bottom = 1
	sb_ok.border_color = Color(1.0, 0.4, 0.4)
	sb_ok.set_corner_radius_all(5)
	btn_ok.add_theme_stylebox_override("normal", sb_ok)
	var sb_okh = StyleBoxFlat.new()
	sb_okh.bg_color = Color(0.9, 0.3, 0.3, 0.55)
	sb_okh.border_width_left = 1; sb_okh.border_width_top = 1; sb_okh.border_width_right = 1; sb_okh.border_width_bottom = 1
	sb_okh.border_color = Color(1.0, 0.6, 0.6)
	sb_okh.set_corner_radius_all(5)
	btn_ok.add_theme_stylebox_override("hover", sb_okh)
	btn_ok.add_theme_color_override("font_color", Color.WHITE)
	btn_ok.pressed.connect(func():
		active_modales.erase(overlay)
		overlay.queue_free()
	)
	v.add_child(btn_ok)


# ==============================================================================
# CONTROL DE VISIBILIDAD, ATAJOS Y DRAG
# ==============================================================================
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
		_close_all_modales()
		z_index = 0


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(860.0, vp_size.x * 0.95)
	var target_h = min(560.0, vp_size.y * 0.92)
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

	if event.is_action_pressed("ui_map") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M):
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
