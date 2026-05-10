extends Control

# HangarTab.gd - Módulo extraído de Inventory.gd
# Maneja exclusivamente la pestaña de Gestión de Flota y Bodega.

var inv_main = null # Referencia al script principal de Inventory

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	
	# v233.05: NUEVO LAYOUT HANGAR (FLOTA ARRIBA / INVENTARIO A LA DERECHA)
	for n in get_children(): n.queue_free()

	var main_v = VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.add_theme_constant_override("separation", 20)
	add_child(main_v)
	
	# --- SECCIÓN 1: FLOTA (ARRIBA INTERIOR) ---
	var fleet_v = VBoxContainer.new()
	main_v.add_child(fleet_v)
	var f_lbl = Label.new(); f_lbl.text = "FLOTA DE COMBATE Y MODELOS ACTIVOS"; f_lbl.modulate = Color.CYAN; f_lbl.add_theme_font_size_override("font_size", 10); f_lbl.modulate.a = 0.6; fleet_v.add_child(f_lbl)
	
	var f_scroll = ScrollContainer.new(); f_scroll.custom_minimum_size = Vector2(0, 75); f_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; fleet_v.add_child(f_scroll)
	var f_grid = HBoxContainer.new(); f_grid.add_theme_constant_override("separation", 12); f_scroll.add_child(f_grid)
	for sid in inv_main.owned_ships: _create_fleet_card(sid, f_grid)
	
	# --- SECCIÓN 2: CUERPO (EQUIPO IZQ / INVENTARIO DER) ---
	var body_h = HBoxContainer.new(); body_h.size_flags_vertical = 3; body_h.add_theme_constant_override("separation", 30); main_v.add_child(body_h)
	
	# COLUMNA IZQUIERDA: GESTIÓN DE LA NAVE
	var left_v = VBoxContainer.new(); left_v.size_flags_horizontal = 3; left_v.size_flags_stretch_ratio = 1.3; body_h.add_child(left_v)
	
	var model = {}
	var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
	for ship in GameConstants.SHIP_MODELS: 
		if ship["id"] == viewing_id: model = ship; break
	if model.is_empty(): model = GameConstants.SHIP_MODELS[0]
	
	var name_h = HBoxContainer.new(); left_v.add_child(name_h)
	var s_title = Label.new(); s_title.text = model.get("name", "Nave").to_upper(); s_title.add_theme_font_size_override("font_size", 24); name_h.add_child(s_title)

	var slots_v = VBoxContainer.new(); slots_v.add_theme_constant_override("separation", 15); left_v.add_child(slots_v)
	var slots = model.get("slots") if model.has("slots") else {"w":0, "s":0, "e":0, "x":1}
	_render_group(slots_v, "w", "MODULOS DE ATAQUE (LASER/MISIL)", slots["w"])
	_render_group(slots_v, "s", "DEFENSA Y ESCUDOS", slots["s"])
	_render_group(slots_v, "e", "MOTORES Y PROPULSION", slots["e"])
	_render_group(slots_v, "x", "EXTRAS Y CPU", slots.get("x", 1))

	# COLUMNA DERECHA: BODEGA DE MATERIALES (TU MARCA AZUL)
	var right_v = VBoxContainer.new(); right_v.size_flags_horizontal = 3; right_v.size_flags_stretch_ratio = 1.0; body_h.add_child(right_v)
	var inv_lbl = Label.new(); inv_lbl.text = "BODEGA DE CARGA / INVENTARIO"; inv_lbl.modulate = Color.CYAN; inv_lbl.add_theme_font_size_override("font_size", 10); inv_lbl.modulate.a = 0.6; right_v.add_child(inv_lbl)
	
	var inv_scroll = ScrollContainer.new(); inv_scroll.size_flags_vertical = 3; right_v.add_child(inv_scroll)
	var inv_vbox = VBoxContainer.new(); inv_vbox.size_flags_horizontal = 3; inv_scroll.add_child(inv_vbox)
	
	if inv_main.inventory_items.is_empty(): 
		var no = Label.new(); no.text = "\nBODEGA VACÍA"; no.horizontal_alignment = 1; no.modulate.a = 0.2; inv_vbox.add_child(no)
	else: 
		for item in inv_main.inventory_items: _create_item_row(item, inv_vbox)

func _create_fleet_card(sid, parent):
	var model = {}
	for m in GameConstants.SHIP_MODELS: 
		if m["id"] == sid: 
			model = m
			break
	if model.is_empty(): return
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(150, 105)
	var is_active = (sid == inv_main.current_ship_id)
	var is_viewing = (sid == inv_main.selected_hangar_ship_id)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 1, 0, 0.05) if is_active else (Color(0, 0.5, 1, 0.05) if is_viewing else Color(0,0,0,0.6))
	sb.border_width_left = 3; sb.border_color = Color.GREEN if is_active else (Color.CYAN if is_viewing else Color(1,1,1,0.1))
	sb.corner_radius_top_right = 4; sb.corner_radius_bottom_right = 4; p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 2); p.add_child(v)
	var n = Label.new(); n.text = model["name"]; n.horizontal_alignment = 1; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
	
	# --- CÁLCULO DE STATS + BONOS (v262.990) ---
	var bonus_w = 0; var bonus_s = 0; var bonus_e = 0
	var ship_e = _find_ship_equip(sid)
	if ship_e:
		for it in ship_e.get("w", []): bonus_w += int(it.get("base", 0))
		for it in ship_e.get("s", []): bonus_s += int(it.get("base", 0))
		for it in ship_e.get("e", []): bonus_e += int(it.get("base", 0))
	
	var stats_grid = GridContainer.new(); stats_grid.columns = 2; stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(stats_grid)
	
	var create_stat = func(txt: String, base_val: int, bonus: int, label_color: Color):
		var lbl = Label.new(); lbl.text = txt; lbl.add_theme_font_size_override("font_size", 8); lbl.modulate = label_color; lbl.modulate.a = 0.7; stats_grid.add_child(lbl)
		var h_val = HBoxContainer.new(); h_val.add_theme_constant_override("separation", 2); stats_grid.add_child(h_val)
		var base_lbl = Label.new(); base_lbl.text = str(base_val); base_lbl.add_theme_font_size_override("font_size", 8); base_lbl.modulate = Color.WHITE; h_val.add_child(base_lbl)
		if bonus > 0:
			var b_lbl = Label.new(); b_lbl.text = "+" + str(bonus); b_lbl.add_theme_font_size_override("font_size", 7); b_lbl.modulate = Color.GREEN; h_val.add_child(b_lbl)
	
	create_stat.call("HP:", int(model.get("hp", 0)), 0, Color.GREEN)
	create_stat.call("SH:", int(model.get("shield", 0)), int(bonus_s), Color.AQUA)
	create_stat.call("VEL:", int(model.get("speed", 0)), int(bonus_e), Color.YELLOW)
	create_stat.call("ATK:", int(model.get("attack", 100)), int(bonus_w), Color.RED)

	v.add_spacer(false)

	if is_active:
		var st = Label.new(); st.text = "ACTIVA"; st.horizontal_alignment = 1; st.modulate = Color.GREEN; st.add_theme_font_size_override("font_size", 9); v.add_child(st)
	else:
		var btn_mini = Button.new(); btn_mini.text = "ACTIVAR"; btn_mini.add_theme_font_size_override("font_size", 8); btn_mini.custom_minimum_size = Vector2(0, 20); v.add_child(btn_mini)
		btn_mini.pressed.connect(func():
			btn_mini.text = "..."; btn_mini.disabled = true
			NetworkManager.send_event("switchShip", {"shipId": sid})
		)
	
	p.gui_input.connect(func(ev): 
		if ev is InputEventMouseButton and ev.pressed: 
			inv_main.selected_hangar_ship_id = sid
			# v263.010: Pedir datos al servidor SIEMPRE al seleccionar una nave
			NetworkManager.send_event("getShipEquip", sid)
			update_ui()
	)
	parent.add_child(p)

func _find_ship_equip(ship_id) -> Dictionary:
	if inv_main.equipped_by_ship.has(str(ship_id)):
		var d = inv_main.equipped_by_ship[str(ship_id)]
		if d and d is Dictionary: return d
	if inv_main.equipped_by_ship.has(int(ship_id)):
		var d = inv_main.equipped_by_ship[int(ship_id)]
		if d and d is Dictionary: return d
	if inv_main.equipped_by_ship.has(float(ship_id)):
		var d = inv_main.equipped_by_ship[float(ship_id)]
		if d and d is Dictionary: return d
	for key in inv_main.equipped_by_ship.keys():
		if str(key) == str(ship_id):
			var d = inv_main.equipped_by_ship[key]
			if d and d is Dictionary: return d
	if int(ship_id) == inv_main.current_ship_id:
		return inv_main.equipped_data
	return {}

func _render_group(parent, type, title, count):
	var l = Label.new(); l.text = title; l.modulate.a = 0.4; l.add_theme_font_size_override("font_size", 9); parent.add_child(l)
	var grid = GridContainer.new(); grid.columns = 10; parent.add_child(grid)
	
	var eq = []
	var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
	var ship_equip = _find_ship_equip(viewing_id)
	eq = ship_equip.get(type, [])
	
	for i in range(count):
		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(40, 40); var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.6); sb.border_width_left = 1; sb.border_color = Color(1,1,1,0.1); p.add_theme_stylebox_override("panel", sb)
		if i < eq.size():
			var item_data = eq[i]
			var item_id = str(item_data.get("id", "")).to_lower()
			var slot_abbrev = "?"
			var slot_text_color = Color.WHITE
			if item_id.begins_with("las"):
				slot_abbrev = "L" + item_id.replace("las", "")
				slot_text_color = Color.RED
				sb.border_color = Color(1, 0.2, 0.2, 0.8)
			elif item_id.begins_with("en"):
				slot_abbrev = "M" + item_id.replace("en", "")
				slot_text_color = Color.YELLOW
				sb.border_color = Color(1, 1, 0, 0.8)
			elif item_id.begins_with("sh"):
				slot_abbrev = "S" + item_id.replace("sh", "")
				slot_text_color = Color.CYAN
				sb.border_color = Color(0, 1, 1, 0.8)
			else:
				slot_abbrev = item_id.left(2).to_upper()
				slot_text_color = Color.MEDIUM_PURPLE
				sb.border_color = Color(0.7, 0.3, 1, 0.8)
			
			var it = Label.new()
			it.text = slot_abbrev
			it.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			it.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			it.add_theme_font_size_override("font_size", 9)
			it.modulate = slot_text_color
			it.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			p.add_child(it)
			
			p.gui_input.connect(func(ev): 
				if ev is InputEventMouseButton and ev.pressed: 
					if ev.double_click:
						var v_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
						NetworkManager.send_event("unequipItem", {
							"category": type, 
							"instanceId": item_data.get("instanceId", ""),
							"shipId": v_id
						})
			)
		else: var c = Label.new(); c.text = "+"; c.horizontal_alignment = 1; c.modulate.a = 0.1; p.add_child(c)
		grid.add_child(p)

func _create_item_row(it, parent):
	if not it or not it.has("name"): return 
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 45); var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.03); sb.border_width_left = 2; sb.border_color = Color.CYAN; p.add_theme_stylebox_override("panel", sb)
	var hb = HBoxContainer.new(); hb.offset_left = 8; p.add_child(hb); var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v)
	
	var item_id = str(it.get("id", "")).to_lower()
	var item_slot = inv_main._get_slot_from_id(item_id)
	var slot_color = Color.CYAN
	var slot_label = "MÓDULO"
	if item_slot == "w": slot_color = Color.RED; slot_label = "ARMA"
	elif item_slot == "s": slot_color = Color.AQUA; slot_label = "ESCUDO"
	elif item_slot == "e": slot_color = Color.YELLOW; slot_label = "MOTOR"
	elif item_slot == "x": slot_color = Color.MEDIUM_PURPLE; slot_label = "EXTRA"
	
	var n = Label.new(); n.text = str(it.get("name", "ITEM")).to_upper(); n.add_theme_font_size_override("font_size", 10); n.modulate = slot_color; v.add_child(n)
	
	var base_val = it.get("base", 0)
	var stat_text = ""
	if item_slot == "w": stat_text = "DAÑO: " + str(base_val)
	elif item_slot == "s": stat_text = "ESCUDO: " + str(base_val)
	elif item_slot == "e": stat_text = "VELOCIDAD: +" + str(base_val)
	
	var st = Label.new(); st.text = stat_text; st.add_theme_font_size_override("font_size", 8); st.modulate = Color.WHITE; st.modulate.a = 0.8; v.add_child(st)
	var t = Label.new(); t.text = slot_label; t.add_theme_font_size_override("font_size", 8); t.modulate = slot_color; t.modulate.a = 0.6; v.add_child(t)
	
	var icon_rect = TextureRect.new(); icon_rect.custom_minimum_size = Vector2(32, 32); icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; hb.add_child(icon_rect)
	hb.move_child(icon_rect, 0)
	
	var icon_path = ""
	if item_id.begins_with("las"): icon_path = "res://assets/Municiones/Laser1.png"
	elif item_id.begins_with("am_l"): icon_path = "res://assets/Municiones/Laser1.png"
	elif item_id.begins_with("am_m"): icon_path = "res://assets/Municiones/Misil1.png"
	elif item_id.begins_with("am_n"): icon_path = "res://assets/Municiones/Mina1.png"
	elif item_id.begins_with("en"): icon_path = "res://assets/Esferas/EsferaAmarilla1.png"
	elif item_id.begins_with("sh"): icon_path = "res://assets/Esferas/EsferaAzul1.png"
	
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
	
	sb.border_color = slot_color
	
	var actions_h = HBoxContainer.new(); hb.add_child(actions_h)
	var b_sell = Button.new(); b_sell.text = " VENDER "; b_sell.modulate = Color(1, 0.3, 0.3); b_sell.add_theme_font_size_override("font_size", 9)
	b_sell.pressed.connect(func(): NetworkManager.send_event("sellItem", {"instanceId": it.get("instanceId", "")}))
	actions_h.add_child(b_sell)

	var b = Button.new(); b.text = "EQUIPAR"; b.add_theme_font_size_override("font_size", 9)
	actions_h.add_child(b)

	var equip_func = func():
		var slot_key = inv_main._get_slot_from_id(str(it.get("id", "")).to_lower())
		var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
		var ship_config = null
		for s in GameConstants.SHIP_MODELS: if s["id"] == viewing_id: ship_config = s; break
		if ship_config:
			var max_s = ship_config["slots"].get(slot_key, 0)
			var current_e = _find_ship_equip(viewing_id).get(slot_key, [])
			if current_e.size() >= max_s:
				inv_main._show_result_modal("CHASIS LLENO", "Esta nave no tiene más espacio en " + slot_key.to_upper())
				return
		NetworkManager.send_event("equipItem", {"instanceId": it.get("instanceId", ""), "shipId": viewing_id})

	b.pressed.connect(equip_func)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.double_click:
			equip_func.call()
	)
	parent.add_child(p)
