extends Control

# HangarTab.gd - REPARACIÓN DE INTERACCIÓN (v263.070)
# Corregido: Doble click, desequipado y limpieza de iconos inexistentes.

var inv_main = null

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var h = self
	for n in h.get_children(): 
		h.remove_child(n)
		n.queue_free()

	# v303.15: Renderizado inmediato (Paridad con Talentos y Esferas)
	# Eliminado el bloqueo is_empty() para evitar estados de "congelamiento" visual.
	var loading_lbl = null
	if inv_main.equipped_by_ship.is_empty() and inv_main.owned_ships.is_empty():
		loading_lbl = Label.new()
		loading_lbl.text = "SINCRONIZANDO CON LA RED OHCULIANA..."
		loading_lbl.modulate = Color.CYAN
		loading_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(loading_lbl)
		# No retornamos, permitimos que se cree la estructura base si es necesario


	var main_v = VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.add_theme_constant_override("separation", 20)
	main_v.mouse_filter = Control.MOUSE_FILTER_STOP # v305.40: Bloquear click-through
	h.add_child(main_v)
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# --- SECCIÓN 1: FLOTA ---
	var fleet_v = VBoxContainer.new()
	main_v.add_child(fleet_v)
	var f_lbl = Label.new(); f_lbl.text = "FLOTA DE COMBATE Y MODELOS ACTIVOS"; f_lbl.modulate = Color.CYAN; f_lbl.add_theme_font_size_override("font_size", 10); f_lbl.modulate.a = 0.6; fleet_v.add_child(f_lbl)
	
	var f_scroll = ScrollContainer.new(); f_scroll.custom_minimum_size = Vector2(0, 115); f_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; fleet_v.add_child(f_scroll)
	var f_grid = HBoxContainer.new(); f_grid.add_theme_constant_override("separation", 12); f_scroll.add_child(f_grid)
	
	if inv_main.owned_ships.is_empty():
		_create_fleet_card(1, f_grid)
	else:
		for sid in inv_main.owned_ships: _create_fleet_card(sid, f_grid)
	
	# --- SECCIÓN 2: CUERPO ---
	var body_h = HBoxContainer.new(); body_h.size_flags_vertical = 3; body_h.add_theme_constant_override("separation", 30); main_v.add_child(body_h)
	
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

	var right_v = VBoxContainer.new(); right_v.size_flags_horizontal = 3; right_v.size_flags_stretch_ratio = 1.0; body_h.add_child(right_v)
	var inv_lbl = Label.new(); inv_lbl.text = "BODEGA DE CARGA / INVENTARIO"; inv_lbl.modulate = Color.CYAN; inv_lbl.add_theme_font_size_override("font_size", 10); inv_lbl.modulate.a = 0.6; right_v.add_child(inv_lbl)
	
	var inv_scroll = ScrollContainer.new(); inv_scroll.size_flags_vertical = 3; right_v.add_child(inv_scroll)
	var inv_vbox = VBoxContainer.new(); inv_vbox.size_flags_horizontal = 3; inv_scroll.add_child(inv_vbox)
	
	if inv_main.inventory_items.is_empty(): 
		var no = Label.new(); no.text = "\nBODEGA VACÍA"; no.horizontal_alignment = 1; no.modulate.a = 0.2; inv_vbox.add_child(no)
	else: 
		# v305.90: Ordenar inventario por categoría (Armas > Escudos > Motores > Extras)
		var sorted_items = inv_main.inventory_items.duplicate()
		sorted_items.sort_custom(func(a, b):
			var slot_a = inv_main._get_slot_from_id(str(a.get("id", "")))
			var slot_b = inv_main._get_slot_from_id(str(b.get("id", "")))
			var order = {"w": 0, "s": 1, "e": 2, "x": 3}
			return order.get(slot_a, 99) < order.get(slot_b, 99)
		)
		for item in sorted_items: _create_item_row(item, inv_vbox)

func _create_fleet_card(sid, parent):
	var model = {}
	for m in GameConstants.SHIP_MODELS: if m["id"] == sid: model = m; break
	if model.is_empty(): return
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(150, 115)
	var is_active = (sid == inv_main.current_ship_id)
	var is_viewing = (sid == inv_main.selected_hangar_ship_id)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 1, 0, 0.05) if is_active else (Color(0, 0.5, 1, 0.05) if is_viewing else Color(0,0,0,0.6))
	sb.border_width_left = 3; sb.border_color = Color.GREEN if is_active else (Color.CYAN if is_viewing else Color(1,1,1,0.1))
	sb.corner_radius_top_right = 4; sb.corner_radius_bottom_right = 4; p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP # v305.50: Bloquear click-through
	
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 2); p.add_child(v)
	var n = Label.new(); n.text = model["name"]; n.horizontal_alignment = 1; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
	
	var bonus_w = 0; var bonus_s = 0; var bonus_e = 0
	var ship_e = _find_ship_equip(sid)
	if ship_e:
		for it in ship_e.get("w", []): bonus_w += int(it.get("base", 0))
		for it in ship_e.get("s", []): bonus_s += int(it.get("base", 0))
		for it in ship_e.get("e", []): bonus_e += int(it.get("base", 0))
	
	var stats_grid = GridContainer.new(); stats_grid.columns = 2; stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(stats_grid)
	var create_stat = func(txt, base_val, bonus, label_color):
		var lbl = Label.new(); lbl.text = txt; lbl.add_theme_font_size_override("font_size", 8); lbl.modulate = label_color; lbl.modulate.a = 0.7; stats_grid.add_child(lbl)
		var h_val = HBoxContainer.new(); h_val.add_theme_constant_override("separation", 2); stats_grid.add_child(h_val)
		var base_lbl = Label.new(); base_lbl.text = str(base_val); base_lbl.add_theme_font_size_override("font_size", 8); base_lbl.modulate = Color.WHITE; h_val.add_child(base_lbl)
		if bonus > 0:
			var b_lbl = Label.new(); b_lbl.text = "+" + str(bonus); b_lbl.add_theme_font_size_override("font_size", 7); b_lbl.modulate = Color.GREEN; h_val.add_child(b_lbl)
	
	create_stat.call("HP:", int(model.get("hp", 0)), 0, Color.GREEN)
	create_stat.call("SH:", int(model.get("shield", 0)), int(bonus_s), Color.AQUA)
	create_stat.call("VEL:", int(model.get("speed", 0)), int(bonus_e), Color.YELLOW)
	create_stat.call("ATK:", int(model.get("attack", 100)), int(bonus_w), Color.RED)

	if is_active:
		var st = Label.new(); st.text = "ACTIVA"; st.horizontal_alignment = 1; st.modulate = Color.GREEN; st.add_theme_font_size_override("font_size", 9); v.add_child(st)
	else:
		var btn_mini = Button.new(); btn_mini.text = "ACTIVAR"; btn_mini.add_theme_font_size_override("font_size", 8); v.add_child(btn_mini)
		btn_mini.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_mini.pressed.connect(func(): NetworkManager.send_event("switchShip", {"shipId": sid}))
	
	p.gui_input.connect(func(ev): 
		if ev is InputEventMouseButton and ev.pressed: 
			get_viewport().set_input_as_handled() # v305.61: Bloqueo absoluto de propagación
			inv_main.selected_hangar_ship_id = sid
			NetworkManager.send_event("getShipEquip", sid)
			update_ui()
	)
	parent.add_child(p)

func _find_ship_equip(ship_id) -> Dictionary:
	var sid_str = str(ship_id)
	if inv_main.equipped_by_ship.has(sid_str): return inv_main.equipped_by_ship[sid_str]
	if int(ship_id) == inv_main.current_ship_id: return inv_main.equipped_data
	return {}

func _render_group(parent, type, title, count):
	var l = Label.new(); l.text = title; l.modulate.a = 0.4; l.add_theme_font_size_override("font_size", 9); parent.add_child(l)
	var grid = GridContainer.new(); grid.columns = 10; parent.add_child(grid)
	
	var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
	var ship_equip = _find_ship_equip(viewing_id)
	var eq = ship_equip.get(type, [])
	
	for i in range(count):
		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(40, 40); var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.6); p.add_theme_stylebox_override("panel", sb)
		if i < eq.size():
			var item_data = eq[i]
			var item_id = str(item_data.get("id", "")).to_lower()
			var slot_abbrev = "?"
			var slot_text_color = Color.WHITE
			if item_id.begins_with("las"):
				slot_abbrev = "L" + item_id.replace("las", ""); slot_text_color = Color.RED
			elif item_id.begins_with("en"):
				slot_abbrev = "M" + item_id.replace("en", ""); slot_text_color = Color.YELLOW
			elif item_id.begins_with("sh"):
				slot_abbrev = "S" + item_id.replace("sh", ""); slot_text_color = Color.CYAN
			else:
				slot_abbrev = item_id.left(2).to_upper(); slot_text_color = Color.MEDIUM_PURPLE
			
			var it = Label.new(); it.text = slot_abbrev; it.horizontal_alignment = 1; it.vertical_alignment = 1; it.modulate = slot_text_color; it.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(it)
			
			# v305.80: Reparación agresiva para ítems de base de datos con rutas rotas
			var icon_path = str(item_data.get("icon", ""))
			if icon_path == "" or icon_path == "null" or "placeholder" in icon_path or not ResourceLoader.exists(icon_path):
				var search_id = str(item_data.get("id", "")).to_lower()
				
				# Mapa de emergencia (Hardcoded fallback para seguridad total)
				var emergency_map = {
					"las1": "res://assets/Armas/Arma1/Arma1.png", "las2": "res://assets/Armas/Arma2/Arma2.png", "las3": "res://assets/Armas/Arma3/Arma3.png",
					"las4": "res://assets/Armas/Arma4/Arma4.png", "las5": "res://assets/Armas/Arma5/Arma5.png", "las6": "res://assets/Armas/Arma6/Arma6.png",
					"sh1": "res://assets/Escudos/Escudo1/Escudo1.png", "sh2": "res://assets/Escudos/Escudo2/Escudo2.png", "sh3": "res://assets/Escudos/Escudo3/Escudo3.png",
					"sh4": "res://assets/Escudos/Escudo4/Escudo4.png", "sh5": "res://assets/Escudos/Escudo5/Escudo5.png", "sh6": "res://assets/Escudos/Escudo6/Escudo6.png",
					"en1": "res://assets/Motores/Motor1/Motor1.png", "en2": "res://assets/Motores/Motor2/Motor2.png", "en3": "res://assets/Motores/Motor3/Motor3.png"
				}
				if emergency_map.has(search_id):
					icon_path = emergency_map[search_id]
				else:
					# Búsqueda segura en SHOP_ITEMS (v305.81)
					for cat_key in GameConstants.SHOP_ITEMS:
						var category = GameConstants.SHOP_ITEMS[cat_key]
						if category is Dictionary: # Caso AMMO
							for sub_key in category:
								var sub_list = category[sub_key]
								if sub_list is Array:
									for shop_item in sub_list:
										if str(shop_item.get("id", "")).to_lower() == search_id:
											icon_path = str(shop_item.get("icon", ""))
											break
								if icon_path != "" and icon_path != "null": break
						elif category is Array: # Caso Armas, Motores, etc
							for shop_item in category:
								if str(shop_item.get("id", "")).to_lower() == search_id:
									icon_path = str(shop_item.get("icon", ""))
									break
						if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path): break
				
				# v305.70: GENERADOR AUTOMÁTICO DE RUTAS (Última instancia)
				if not ResourceLoader.exists(icon_path):
					icon_path = _get_fallback_icon(search_id)
			
			if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path):
				var tex_res = load(icon_path)
				if tex_res:
					it.visible = false # Ocultar texto si hay imagen
					var tex = TextureRect.new()
					tex.texture = tex_res
					tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
					p.add_child(tex)
			
			p.gui_input.connect(func(ev): 
				if ev is InputEventMouseButton and ev.pressed:
					get_viewport().set_input_as_handled() # v305.61: Bloqueo absoluto
					if ev.double_click:
						# DESEQUIPAR con Doble Click
						NetworkManager.send_event("unequipItem", {"category": type, "instanceId": item_data.get("instanceId", ""), "shipId": viewing_id})
			)
		else: var c = Label.new(); c.text = "+"; c.horizontal_alignment = 1; c.modulate.a = 0.1; p.add_child(c)
		grid.add_child(p)

func _create_item_row(it, parent):
	if not it or not it.has("name"): return 
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 45); var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.03); p.add_theme_stylebox_override("panel", sb)
	var hb = HBoxContainer.new(); hb.offset_left = 8; p.add_child(hb); var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var item_id = str(it.get("id", "")).to_lower()
	var item_slot = inv_main._get_slot_from_id(item_id)
	var slot_color = Color.CYAN
	if item_slot == "w": slot_color = Color.RED
	elif item_slot == "s": slot_color = Color.AQUA
	elif item_slot == "e": slot_color = Color.YELLOW
	elif item_slot == "x": slot_color = Color.MEDIUM_PURPLE
	
	var n = Label.new(); n.text = str(it.get("name", "ITEM")).to_upper(); n.add_theme_font_size_override("font_size", 10); n.modulate = slot_color; v.add_child(n); n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_val = int(it.get("base", 0))
	var stat_text = ""
	if item_slot == "w": stat_text = "DAÑO: " + str(base_val)
	elif item_slot == "s": stat_text = "ESCUDO: " + str(base_val)
	elif item_slot == "e": stat_text = "VELOCIDAD: +" + str(base_val)
	var st = Label.new(); st.text = stat_text; st.add_theme_font_size_override("font_size", 8); st.modulate.a = 0.8; v.add_child(st); st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# v305.80: Reparación agresiva en la bodega
	var icon_path = str(it.get("icon", ""))
	var search_id = str(it.get("id", "")).to_lower()
	if icon_path == "" or icon_path == "null" or "placeholder" in icon_path or not ResourceLoader.exists(icon_path):
		# Búsqueda segura en SHOP_ITEMS (v305.81)
		for cat_key in GameConstants.SHOP_ITEMS:
			var category = GameConstants.SHOP_ITEMS[cat_key]
			if category is Dictionary: # Caso AMMO
				for sub_key in category:
					var sub_list = category[sub_key]
					if sub_list is Array:
						for shop_item in sub_list:
							if str(shop_item.get("id", "")).to_lower() == search_id:
								icon_path = str(shop_item.get("icon", ""))
								break
					if icon_path != "" and icon_path != "null": break
			elif category is Array:
				for shop_item in category:
					if str(shop_item.get("id", "")).to_lower() == search_id:
						icon_path = str(shop_item.get("icon", ""))
						break
			if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path): break
		
		# v305.70: Generador Automático
		if not ResourceLoader.exists(icon_path):
			icon_path = _get_fallback_icon(search_id)
	
	# Fallback para láseres clásicos si aún no tienen icono en ninguna parte
	if (icon_path == "" or icon_path == "null") and item_id.begins_with("las"): 
		icon_path = "res://assets/Municiones/Laser1.png"
	
	if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path):
		var tex_res = load(icon_path)
		if tex_res:
			var icon_rect = TextureRect.new()
			icon_rect.texture = tex_res
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # v305.62: Añadido expand mode
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(32, 32) # v305.82: Tamaño mínimo para bodega
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# v305.62: Inyectar en el row si es posible (ajuste de diseño)
			if hb: hb.add_child(icon_rect); hb.move_child(icon_rect, 0)
	
	# Borde eliminado (v305.90)
	
	var action_hb = HBoxContainer.new(); action_hb.add_theme_constant_override("separation", 5); hb.add_child(action_hb)
	
	var b_sell = Button.new(); b_sell.text = "VENDER"; b_sell.modulate = Color(1, 0.4, 0.4); b_sell.add_theme_font_size_override("font_size", 8)
	b_sell.pressed.connect(func(): NetworkManager.send_event("sellItem", {"instanceId": it.get("instanceId", "")}))
	action_hb.add_child(b_sell)

	var b_equip = Button.new(); b_equip.text = "EQUIPAR"; b_equip.add_theme_font_size_override("font_size", 9); action_hb.add_child(b_equip)
	var equip_func = func():
		var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
		NetworkManager.send_event("equipItem", {"instanceId": it.get("instanceId", ""), "shipId": viewing_id})
	
	b_equip.pressed.connect(equip_func)
	
	# Doble Click en toda la fila para equipar
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.double_click:
			equip_func.call()
	)
	
	parent.add_child(p)

func _get_fallback_icon(id: String) -> String:
	# v305.70: Reconstrucción algorítmica de rutas según nomenclatura estándar
	if id.begins_with("las"):
		var n = id.replace("las", "")
		return "res://assets/Armas/Arma" + n + "/Arma" + n + ".png"
	elif id.begins_with("sh"):
		var n = id.replace("sh", "")
		return "res://assets/Escudos/Escudo" + n + "/Escudo" + n + ".png"
	elif id.begins_with("en"):
		var n = id.replace("en", "")
		return "res://assets/Motores/Motor" + n + "/Motor" + n + ".png"
	elif id.begins_with("ext"):
		return ""
	return ""