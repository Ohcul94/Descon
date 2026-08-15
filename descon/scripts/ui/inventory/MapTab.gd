extends Control

# MapTab.gd - MÓDULO DE NAVEGACIÓN GALÁCTICA (v301.5)
# Lógica de sectores y mapa interactivo extraída de Inventory.gd.

var inv_main = null
var selected_zone_id: int = -1

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var tab = self
	for n in tab.get_children(): 
		tab.remove_child(n)
		n.queue_free()
	
	var master_h = HBoxContainer.new(); master_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_h.add_theme_constant_override("separation", 20); tab.add_child(master_h)
	
	# Columna Izquierda: Lista de Sectores
	var l_col = VBoxContainer.new(); l_col.custom_minimum_size.x = 300; master_h.add_child(l_col)
	var l_title = Label.new(); l_title.text = " SECTORES CONOCIDOS"; l_title.modulate = Color.CYAN; l_title.add_theme_font_size_override("font_size", 11); l_col.add_child(l_title)
	
	var s_scroll = ScrollContainer.new(); s_scroll.size_flags_vertical = 3; l_col.add_child(s_scroll)
	s_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # v301.6: Evitar barra horizontal
	
	var s_list = VBoxContainer.new(); s_list.size_flags_horizontal = 3; s_scroll.add_child(s_list)
	
	var current_zone_id = 1
	var p_node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p_node) and "current_zone" in p_node:
		current_zone_id = p_node.current_zone

	if selected_zone_id == -1:
		selected_zone_id = current_zone_id

	var sectors = []
	for z_id in GameConstants.MAPS_CONFIG:
		var zone_data = GameConstants.MAPS_CONFIG[z_id]
		var z_id_int = int(z_id)
		
		# Filtrar si está inactivo/invisible, a menos que el jugador esté parado en ese mapa actualmente
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
		
		# v600.0: Sector sellado por misión (requiere desbloqueo de portal)
		var is_locked = false
		if s.get("unlockRequired", false) == true and not is_current:
			var unlock_key = "map:" + str(s.id)
			if not NetworkManager.unlocks_cache.has(unlock_key):
				is_locked = true

		# v600.1: Portal sellado por misión activa (portalGate en la quest)
		# v600.2: Soporta "zona" (todo el sector) y "zona|etiqueta" (portal específico)
		var gate_quest_name = ""
		if not is_locked and not is_current:
			gate_quest_name = NetworkManager.get_sector_seal_quest(s.id)
			if gate_quest_name != "":
				is_locked = true

		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 70); s_list.add_child(p)
		
		var sb = StyleBoxFlat.new()
		
		# Configuración de Fondo
		if is_selected:
			sb.bg_color = Color(0, 0.8, 1, 0.15) # Fondo cian más brillante para el seleccionado
		elif is_current:
			sb.bg_color = Color(1, 0.8, 0, 0.15) # Fondo dorado para la zona actual
		else:
			sb.bg_color = Color(0, 1, 1, 0.05) # Fondo normal
			
		# Configuración de Bordes
		if is_selected:
			# Borde completo cian para identificar claramente el mapa que se está mirando
			sb.border_width_left = 4
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
			sb.border_color = Color.CYAN
		elif is_current:
			sb.border_width_left = 5
			sb.border_color = Color.GOLD
		else:
			sb.border_width_left = 3
			sb.border_color = s.color
			
		if is_current:
			sb.shadow_color = Color(1, 0.8, 0, 0.2)
			sb.shadow_size = 4
			
		p.add_theme_stylebox_override("panel", sb)
		
		# Selección interactiva al hacer click en la tarjeta de sector
		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				selected_zone_id = s.id
				update_ui()
		)
		
		var hb = HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); p.add_child(hb)
		
		# Margen interno izquierdo
		var spacer = Control.new(); spacer.custom_minimum_size.x = 5; hb.add_child(spacer)
		
		var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v); v.alignment = BoxContainer.ALIGNMENT_CENTER
		var n = Label.new(); n.text = s.name; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
		if is_current: n.modulate = Color.GOLD
		
		var d = Label.new(); d.text = s.get("desc", ""); d.add_theme_font_size_override("font_size", 8); d.modulate.a = 0.6; v.add_child(d)
		
		var pvp_lbl = Label.new()
		pvp_lbl.add_theme_font_size_override("font_size", 8)
		var pvp_mode = s.get("pvpMode", "tranquila")
		if pvp_mode == "tranquila":
			pvp_lbl.text = "🕊️ Zona Tranquila"
			pvp_lbl.modulate = Color(0.2, 0.9, 0.4)
		elif pvp_mode == "mandatory":
			pvp_lbl.text = "⚔️ PvP Obligatorio"
			pvp_lbl.modulate = Color(1.0, 0.6, 0.1)
		elif pvp_mode == "partial_drop":
			pvp_lbl.text = "🎒 PvP + Loot Parcial"
			pvp_lbl.modulate = Color(1.0, 0.8, 0.2)
		elif pvp_mode == "full_drop":
			pvp_lbl.text = "💀 PvP + Loot Total"
			pvp_lbl.modulate = Color(1.0, 0.2, 0.2)
		elif pvp_mode == "inferno":
			pvp_lbl.text = "🔥 INFIERNO - Nave Destruida"
			pvp_lbl.modulate = Color(1.0, 0.0, 0.0)
		v.add_child(pvp_lbl)
		
		# v600.0: Aviso de sector sellado
		if is_locked:
			var lock_lbl = Label.new()
			if gate_quest_name != "":
				lock_lbl.text = "🔒 PORTAL SELLADO - Completa \"" + gate_quest_name + "\""
			else:
				lock_lbl.text = "🔒 SELLADO - Requiere desbloqueo por misión"
			lock_lbl.modulate = Color(1.0, 0.4, 0.4)
			lock_lbl.add_theme_font_size_override("font_size", 8)
			v.add_child(lock_lbl)
		
		if is_current:
			var st = Label.new(); st.text = "ESTÁS AQUÍ"
			st.modulate = Color.GOLD
			st.add_theme_font_size_override("font_size", 8); v.add_child(st)
		
		var raw_cost = s.get("warpCost")
		var cost = int(raw_cost) if raw_cost != null and (typeof(raw_cost) == TYPE_INT or typeof(raw_cost) == TYPE_FLOAT or (typeof(raw_cost) == TYPE_STRING and raw_cost.is_valid_int())) else 10
		
		var raw_min = s.get("minLevel")
		var min_level = int(raw_min) if raw_min != null and (typeof(raw_min) == TYPE_INT or typeof(raw_min) == TYPE_FLOAT or (typeof(raw_min) == TYPE_STRING and raw_min.is_valid_int())) else 1
		
		var current_level = 1
		if is_instance_valid(p_node) and "level" in p_node:
			current_level = int(p_node.level)
		
		var can_enter = current_level >= min_level
		
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
			btn_travel.text = "VIAJAR\n" + str(cost) + " OHCU" if cost > 0 else "VIAJAR\nGRATIS"
			btn_travel.disabled = is_current

		btn_travel.add_theme_font_size_override("font_size", 8)
		btn_travel.custom_minimum_size = Vector2(75, 45)
		btn_travel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(btn_travel)
		
		# Margen interno derecho
		var spacer2 = Control.new(); spacer2.custom_minimum_size.x = 5; hb.add_child(spacer2)
		
		if not is_current and can_enter:
			btn_travel.pressed.connect(func():
				if inv_main.ohcu < cost:
					inv_main._show_result_modal("FONDOS INSUFICIENTES", "Necesitas " + str(cost) + " OHCU para saltar a este sector.")
					return
				
				var msg = "¿Confirmas salto hiperespacial a [color=cyan]" + s.name + "[/color]?"
				if cost > 0: msg += "\nCosto: [color=yellow]" + str(cost) + " OHCU[/color]"
				
				inv_main._show_modal("CONFIRMAR SALTO", msg, func():
					NetworkManager.send_event("changeZone", s.id)
					inv_main.toggle()
				)
			)
	
	# Columna Derecha: Contenedor Principal de Detalles Dinámicos
	var r_col = VBoxContainer.new(); r_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; master_h.add_child(r_col)
	
	# Buscar data de la zona seleccionada
	var sel_zone_data = {}
	for s in sectors:
		if s.id == selected_zone_id:
			sel_zone_data = s
			break
	
	# Contenedor de dos columnas
	var cols_hb = HBoxContainer.new(); cols_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL; cols_hb.add_theme_constant_override("separation", 15); r_col.add_child(cols_hb)
	
	# --- COLUMNA 1: ENEMIGOS Y DROPS ---
	var col_enem = VBoxContainer.new(); col_enem.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols_hb.add_child(col_enem)
	var t_enem = Label.new(); t_enem.text = "ENEMIGOS Y BOTÍN (DROPS)"; t_enem.modulate = Color(1, 0.4, 0.4); t_enem.add_theme_font_size_override("font_size", 10); col_enem.add_child(t_enem)
	
	var scroll_enem = ScrollContainer.new(); scroll_enem.size_flags_vertical = Control.SIZE_EXPAND_FILL; col_enem.add_child(scroll_enem)
	var list_enem = VBoxContainer.new(); list_enem.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll_enem.add_child(list_enem)
	
	# Cargar enemigos configurados en spawns para el mapa
	var spawns = sel_zone_data.get("spawns", [])
	var drop_mult = float(sel_zone_data.get("dropMultiplier", 1.0))
	
	if spawns.is_empty():
		var no_enem = Label.new(); no_enem.text = "No se detecta presencia enemiga en este sector."
		no_enem.add_theme_font_size_override("font_size", 9); no_enem.modulate.a = 0.4
		list_enem.add_child(no_enem)
	else:
		# Evitar duplicados de tipos de enemigos en la lista visual
		var processed_types = []
		for sp in spawns:
			var raw_type = str(sp.get("type", ""))
			if raw_type == "" or raw_type in processed_types:
				continue
			processed_types.append(raw_type)
			
			# Limpiar tipo (ej: "1-A" -> "1")
			var base_type = raw_type.split("-")[0]
			var enemy_cfg = {}
			if GameConstants.ENEMY_MODELS.has(raw_type):
				enemy_cfg = GameConstants.ENEMY_MODELS[raw_type]
			elif GameConstants.ENEMY_MODELS.has(base_type):
				enemy_cfg = GameConstants.ENEMY_MODELS[base_type]
				
			var e_panel = PanelContainer.new(); e_panel.custom_minimum_size.y = 50; list_enem.add_child(e_panel)
			var esb = StyleBoxFlat.new(); esb.bg_color = Color(1, 0.2, 0.2, 0.03); esb.set_border_width_all(1); esb.border_color = Color(1, 0.2, 0.2, 0.1); e_panel.add_theme_stylebox_override("panel", esb)
			var ev = VBoxContainer.new(); ev.offset_left = 6; e_panel.add_child(ev)
			
			var e_name = enemy_cfg.get("name", "Enemigo T" + base_type)
			var e_hp = int(enemy_cfg.get("hp", 100))
			var e_sh = int(enemy_cfg.get("shield", 0))
			
			var e_title = Label.new(); e_title.text = e_name.to_upper() + " [HP: " + str(e_hp) + " | SH: " + str(e_sh) + "]"
			e_title.add_theme_font_size_override("font_size", 9); e_title.modulate = Color(1, 0.5, 0.5); ev.add_child(e_title)
			
			# Mostrar drop general de cofre
			var c_chance = float(enemy_cfg.get("chestDropChance", 0.1)) * drop_mult
			var c_chance_pct = int(c_chance * 100)
			
			var e_chance_lbl = Label.new(); e_chance_lbl.text = "Probabilidad de Cofre: " + str(c_chance_pct) + "%"
			e_chance_lbl.add_theme_font_size_override("font_size", 8); e_chance_lbl.modulate = Color.DARK_GRAY; ev.add_child(e_chance_lbl)
			
			# Mostrar items de drop
			var drops = enemy_cfg.get("lootDrops", [])
			if drops.is_empty():
				var no_drop = Label.new(); no_drop.text = "   • Sin drops de ítems específicos."
				no_drop.add_theme_font_size_override("font_size", 8); no_drop.modulate.a = 0.4; ev.add_child(no_drop)
			else:
				var drop_title = Label.new(); drop_title.text = "   Botín Posible:"
				drop_title.add_theme_font_size_override("font_size", 8); drop_title.modulate = Color.CYAN; ev.add_child(drop_title)
				for d in drops:
					var item_id = d.get("itemId", "")
					var item_chance = int(float(d.get("chance", 0.1)) * 100)
					
					# Buscar nombre del item en shopItems
					var item_name = item_id
					for cat_key in GameConstants.SHOP_ITEMS:
						var category = GameConstants.SHOP_ITEMS[cat_key]
						if category is Array:
							for shop_item in category:
								if str(shop_item.get("id", "")).to_lower() == item_id.to_lower():
									item_name = shop_item.get("name", item_id)
									break
						elif category is Dictionary:
							for sub_key in category:
								var sub_list = category[sub_key]
								if sub_list is Array:
									for shop_item in sub_list:
										if str(shop_item.get("id", "")).to_lower() == item_id.to_lower():
											item_name = shop_item.get("name", item_id)
											break
					var drop_lbl = Label.new(); drop_lbl.text = "     - " + item_name + " (" + str(item_chance) + "% chance)"
					drop_lbl.add_theme_font_size_override("font_size", 8); drop_lbl.modulate.a = 0.85; ev.add_child(drop_lbl)
	
	# --- COLUMNA 2: MECÁNICAS AMBIENTALES ---
	var col_amb = VBoxContainer.new(); col_amb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols_hb.add_child(col_amb)
	var t_amb = Label.new(); t_amb.text = "MECÁNICAS AMBIENTALES"; t_amb.modulate = Color.YELLOW; t_amb.add_theme_font_size_override("font_size", 10); col_amb.add_child(t_amb)
	
	var scroll_amb = ScrollContainer.new(); scroll_amb.size_flags_vertical = Control.SIZE_EXPAND_FILL; col_amb.add_child(scroll_amb)
	var list_amb = VBoxContainer.new(); list_amb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll_amb.add_child(list_amb)
	
	var ambience = sel_zone_data.get("ambience", [])
	if ambience.is_empty():
		var no_amb = Label.new(); no_amb.text = "Entorno estable. No se detectan anomalías climáticas."
		no_amb.add_theme_font_size_override("font_size", 9); no_amb.modulate.a = 0.4
		list_amb.add_child(no_amb)
	else:
		for a in ambience:
			var a_type = str(a.get("type", ""))
			var a_panel = PanelContainer.new(); a_panel.custom_minimum_size.y = 50; list_amb.add_child(a_panel)
			var asb = StyleBoxFlat.new(); asb.bg_color = Color(1, 0.8, 0, 0.03); asb.set_border_width_all(1); asb.border_color = Color(1, 0.8, 0, 0.1); a_panel.add_theme_stylebox_override("panel", asb)
			var av = VBoxContainer.new(); av.offset_left = 6; a_panel.add_child(av)
			
			var a_title_lbl = Label.new()
			var a_desc_lbl = Label.new()
			a_title_lbl.add_theme_font_size_override("font_size", 9); a_title_lbl.modulate = Color.YELLOW
			a_desc_lbl.add_theme_font_size_override("font_size", 8); a_desc_lbl.modulate.a = 0.85
			
			var a_label = a_type.to_upper().replace("_", " ")
			var a_icon = "❓"
			var a_desc_default = ""
			
			if GameConstants.FULL_CONFIG.has("ambienceLib"):
				var ambience_lib = GameConstants.FULL_CONFIG["ambienceLib"]
				if ambience_lib.has(a_type):
					var lib_entry = ambience_lib[a_type]
					if lib_entry.has("label"): a_label = lib_entry["label"]
					if lib_entry.has("icon"): a_icon = lib_entry["icon"]
					if lib_entry.has("desc"): a_desc_default = lib_entry["desc"]
					
			a_title_lbl.text = a_icon + " " + a_label.to_upper()
			
			match a_type:
				"freeze_hazard":
					var slow_pct = int(a.get("slowPercentage", 0))
					var slow_fix = int(a.get("slowFixed", 0))
					var dur = int(round(float(a.get("duration", 3000)) / 1000.0))
					var slow_desc = str(slow_pct) + "%" if slow_pct > 0 else str(slow_fix) + " unidades"
					a_desc_lbl.text = "Congela naves periódicamente.\nRalentiza en " + slow_desc + " durante " + str(dur) + "s."
				"radiation":
					var dmg = int(a.get("damage", 10))
					var ms = int(round(float(a.get("intervalMs", 3000)) / 1000.0))
					a_desc_lbl.text = "Campo electromagnético dañino.\nCausa " + str(dmg) + " de daño cada " + str(ms) + "s al escudo/casco."
				"interferencia_hazard":
					var dur = int(round(float(a.get("duration", 5000)) / 1000.0))
					a_desc_lbl.text = "Frecuencia de pulso inestable.\nBloquea el uso de habilidades activas durante " + str(dur) + "s."
				"extreme_aggression":
					var h_mult = float(a.get("healthMult", 1.0))
					var h_mult_str = str(h_mult) if h_mult != int(h_mult) else str(int(h_mult))
					a_desc_lbl.text = "Zona de combate hiperactiva.\nLos enemigos tienen un multiplicador de HP/Escudo de x" + h_mult_str + "."
				"multiplicador":
					var mult = float(a.get("multiplier", 1.0))
					var mult_str = str(mult) if mult != int(mult) else str(int(mult))
					a_desc_lbl.text = "Zona con distorsión de poder.\nEnemigos potencian vida, escudo, daño y velocidad por x" + mult_str + "."
				"healing_penalty":
					var pct = int(a.get("penaltyPercentage", 0))
					var fix = int(a.get("penaltyFixed", 0))
					var details = ""
					if pct > 0:
						details += "Reducción de curación del " + str(pct) + "%"
					if fix > 0:
						if details != "": details += " y "
						details += "reducción fija de " + str(fix) + " HP"
					if details == "":
						details = "Curación sin penalizaciones configuradas"
					a_desc_lbl.text = "Inhibe la regeneración de salud de naves en este sector.\n" + details + "."
				"vortex_hazard":
					a_desc_lbl.text = "Genera vórtices que succionan y dañan a las naves."
				"blindness_hazard":
					a_desc_lbl.text = "Oscurece la pantalla de las naves periódicamente."
				"gravity":
					a_desc_lbl.text = "Reduce la velocidad del dash."
				"nebula":
					a_desc_lbl.text = "Ralentiza a las naves de forma constante en el área."
				_:
					a_desc_lbl.text = a_desc_default if a_desc_default != "" else ("Parámetros: " + JSON.stringify(a))
			
			av.add_child(a_title_lbl)
			av.add_child(a_desc_lbl)
