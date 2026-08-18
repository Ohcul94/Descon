extends Control

# HangarTab.gd - REPARACIÓN DE INTERACCIÓN (v300.80)
# Corregido: Doble click, desequipado, limpieza de iconos y visor 3D central.

var inv_main = null
var preview_mesh: Node3D = null
var _model_cache: Dictionary = {}
var _texture_cache: Dictionary = {}

func setup(p_inv_main):
	inv_main = p_inv_main
	set_process(true)

func update_ui():
	if not inv_main: return
	var h = self
	# Guardar la posición de scroll horizontal antes de limpiar
	var last_scroll_h = 0
	if h.get_child_count() > 0:
		var main_v_node = h.get_child(0)
		if main_v_node and main_v_node.get_child_count() > 0:
			var fleet_v_node = main_v_node.get_child(0)
			if fleet_v_node and fleet_v_node.get_child_count() > 1:
				var f_scroll_node = fleet_v_node.get_child(1)
				if f_scroll_node is ScrollContainer:
					last_scroll_h = f_scroll_node.scroll_horizontal

	for n in h.get_children(): 
		h.remove_child(n)
		n.queue_free()
		
	preview_mesh = null

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
		
	if last_scroll_h > 0:
		f_scroll.scroll_horizontal = last_scroll_h
		f_scroll.set_deferred("scroll_horizontal", last_scroll_h)
	
	# --- SECCIÓN 2: CUERPO ---
	var body_h = HBoxContainer.new(); body_h.size_flags_vertical = 3; body_h.add_theme_constant_override("separation", 20); main_v.add_child(body_h)
	
	# Columna 1: Slots (Izquierda)
	var left_v = VBoxContainer.new(); left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left_v.size_flags_stretch_ratio = 1.1; body_h.add_child(left_v)
	
	var model = {}
	var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
	for ship in GameConstants.SHIP_MODELS: 
		if ship["id"] == viewing_id: model = ship; break
	if model.is_empty(): model = GameConstants.SHIP_MODELS[0]
	
	var name_h = HBoxContainer.new(); left_v.add_child(name_h)
	var s_title = Label.new(); s_title.text = model.get("name", "Nave").to_upper(); s_title.add_theme_font_size_override("font_size", 20); name_h.add_child(s_title)

	var slots_v = VBoxContainer.new(); slots_v.add_theme_constant_override("separation", 15); left_v.add_child(slots_v)
	var slots = model.get("slots") if model.has("slots") else {"w":0, "s":0, "e":0, "x":1}
	_render_group(slots_v, "w", "MODULO DE ATAQUE", slots["w"])
	_render_group(slots_v, "s", "MODULO DE DEFENSA", slots["s"])
	_render_group(slots_v, "e", "MODULO DE MOTOR", slots["e"])
	_render_group(slots_v, "x", "MODULO DE EXTRAS", slots.get("x", 1))

	# Columna 2: Visor 3D de la Nave (Centro)
	var middle_v = VBoxContainer.new(); middle_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; middle_v.size_flags_stretch_ratio = 1.3; body_h.add_child(middle_v)
	
	var vp_container = SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_container.custom_minimum_size = Vector2(250, 250)
	middle_v.add_child(vp_container)
	
	var vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	if "use_hdr_3d" in vp: vp.use_hdr_3d = false
	vp_container.add_child(vp)
	
	var node3d = Node3D.new()
	vp.add_child(node3d)
	
	# Ambiente
	var env = WorldEnvironment.new()
	var world_env = Environment.new()
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color(0.15, 0.15, 0.3)
	world_env.ambient_light_energy = 0.4
	world_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = world_env
	node3d.add_child(env)
	
	# Cámara (Añadida al árbol ANTES de look_at)
	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 40.0
	cam.position = Vector3(0, 1.3, 3.3)
	node3d.add_child(cam)
	cam.look_at(Vector3(0, 0.1, 0))
	
	# Luz Clave
	var key_light = DirectionalLight3D.new()
	key_light.light_energy = 1.8
	key_light.light_color = Color(1.0, 0.9, 0.75)
	key_light.shadow_enabled = false
	key_light.rotation_degrees = Vector3(-35, 45, 0)
	node3d.add_child(key_light)
	
	# Luz de Relleno
	var fill_light = DirectionalLight3D.new()
	fill_light.light_energy = 0.6
	fill_light.light_color = Color(0.7, 0.8, 1.0)
	fill_light.shadow_enabled = false
	fill_light.rotation_degrees = Vector3(25, -135, 0)
	node3d.add_child(fill_light)
	
	# Cargar modelo de la nave
	var ship_id = int(viewing_id)
	var glb_path = ""
	var ship_data = {}
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == ship_id:
				ship_data = s
				break
				
	if ship_data.has("assetPath") and ship_data.assetPath != "":
		glb_path = ship_data.assetPath
	else:
		match ship_id:
			1: glb_path = "res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb"
			2: glb_path = "res://assets/Personajes/3D/Nave2/Nave2.glb"
			3: glb_path = "res://assets/Personajes/3D/Nave3/Nave3.glb"
			4: glb_path = "res://assets/Personajes/3D/Nave4/Nave4.glb"
			5: glb_path = "res://assets/Personajes/3D/Nave5/Nave5.glb"
			6: glb_path = "res://assets/Personajes/3D/Nave6/Nave6.glb"
		
	if glb_path != "" and ResourceLoader.exists(glb_path):
		var model_scene = null
		if _model_cache.has(glb_path):
			model_scene = _model_cache[glb_path]
		else:
			model_scene = load(glb_path)
			_model_cache[glb_path] = model_scene
			
		if model_scene:
			var ship_model = model_scene.instantiate()
			_clean_internal_lights_in_ui(ship_model)
			
			# v390.0: Parche para que las naves 1 a 6 se mantengan siempre iluminadas (Unshaded)
			if ship_id >= 1 and ship_id <= 6:
				_make_materials_unshaded_in_ui(ship_model)
			
			var pivot = Node3D.new()
			pivot.name = "ShipPivot"
			node3d.add_child(pivot)
			pivot.add_child(ship_model)
			
			pivot.scale = Vector3(1.3, 1.3, 1.3)
			
			# Orientación corregida según el modelado del asset
			if ship_data.has("rotX") or ship_data.has("rotY") or ship_data.has("rotZ"):
				ship_model.rotation_degrees.x = float(ship_data.get("rotX", 0))
				ship_model.rotation_degrees.y = float(ship_data.get("rotY", 0))
				ship_model.rotation_degrees.z = float(ship_data.get("rotZ", 0))
			else:
				match ship_id:
					3: ship_model.rotation_degrees = Vector3(0, 1, 98)
					4: ship_model.rotation_degrees = Vector3(0, -180, 52)
					6: ship_model.rotation_degrees.y = 180
					_: ship_model.rotation_degrees = Vector3.ZERO
				
			preview_mesh = pivot

	# Columna 3: Bodega de Carga (Derecha)
	var right_v = VBoxContainer.new(); right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right_v.size_flags_stretch_ratio = 1.0; body_h.add_child(right_v)
	var inv_lbl = Label.new(); inv_lbl.text = "INVENTARIO"; inv_lbl.modulate = Color.CYAN; inv_lbl.add_theme_font_size_override("font_size", 10); inv_lbl.modulate.a = 0.6; right_v.add_child(inv_lbl)
	
	var inv_scroll = ScrollContainer.new(); inv_scroll.size_flags_vertical = 3; inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right_v.add_child(inv_scroll)
	var inv_vbox = VBoxContainer.new(); inv_vbox.size_flags_horizontal = 3; inv_scroll.add_child(inv_vbox)
	
	if inv_main.inventory_items.is_empty(): 
		var no = Label.new(); no.text = "\nINVENTARIO VACÍO"; no.horizontal_alignment = 1; no.modulate.a = 0.2; inv_vbox.add_child(no)
	else: 
		# v305.90: Ordenar inventario por categoría (Armas > Escudos > Motores > Extras)
		var sorted_items = inv_main.inventory_items.duplicate()
		sorted_items.sort_custom(func(a, b):
			var slot_a = inv_main._get_slot_from_id(str(a.get("id", "")))
			var slot_b = inv_main._get_slot_from_id(str(b.get("id", "")))
			var order = {"w": 0, "s": 1, "e": 2, "x": 3}
			return order.get(slot_a, 99) < order.get(slot_b, 99)
		)
		for item in sorted_items:
			if _is_item_hidden(str(item.get("id", ""))): continue # v620.0: Ojito de visibilidad
			_create_item_row(item, inv_vbox)

# v620.0: Ojito de visibilidad — ¿el ítem está oculto en la config del servidor?
func _is_item_hidden(item_id: String) -> bool:
	if item_id == "": return false
	for cat_key in GameConstants.SHOP_ITEMS:
		var category = GameConstants.SHOP_ITEMS[cat_key]
		if category is Dictionary: # Caso AMMO
			for sub_key in category:
				var sub_list = category[sub_key]
				if sub_list is Array:
					for shop_item in sub_list:
						if str(shop_item.get("id", "")).to_lower() == item_id.to_lower():
							return shop_item.get("hidden", false)
		elif category is Array: # Caso Armas, Escudos, Motores, etc
			for shop_item in category:
				if str(shop_item.get("id", "")).to_lower() == item_id.to_lower():
					return shop_item.get("hidden", false)
	return false

func _create_fleet_card(sid, parent):
	var model = {}
	for m in GameConstants.SHIP_MODELS: if m["id"] == sid: model = m; break
	if model.is_empty() or model.get("hidden", false): return
	
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
	
	var total_hp_bonus = 0.0
	var hp_mod_flat = 0.0
	var hp_mod_pct = 0.0
	var total_sh_bonus = 0.0
	var shield_mod_flat = 0.0
	var shield_mod_pct = 0.0
	var speed_bonus = 0.0
	var speed_mod_flat = 0.0
	var speed_mod_pct = 0.0
	var bonus_w = 0.0
	var dmg_mod_flat = 0.0
	var dmg_mod_pct = 0.0

	var ship_e = _find_ship_equip(sid)
	if ship_e:
		# Armas (w) - base ataque | modifica Velocidad y Vida
		for it in ship_e.get("w", []):
			if _is_item_hidden(str(it.get("id", ""))): continue # v620.0: Ojito de visibilidad
			bonus_w += float(it.get("base", 0))
			var sv = float(it.get("speedMod", 0))
			if it.get("speedModType", "percent") == "flat": speed_mod_flat += sv
			else: speed_mod_pct += sv
			var hv = float(it.get("hpMod", 0))
			if it.get("hpModType", "percent") == "flat": hp_mod_flat += hv
			else: hp_mod_pct += hv
		# Escudos (s) - base escudo | modifica Vida y Velocidad
		for it in ship_e.get("s", []):
			if _is_item_hidden(str(it.get("id", ""))): continue # v620.0: Ojito de visibilidad
			total_sh_bonus += float(it.get("base", 0))
			var hv = float(it.get("hpMod", 0))
			if it.get("hpModType", "percent") == "flat": hp_mod_flat += hv
			else: hp_mod_pct += hv
			var sv = float(it.get("speedMod", 0))
			if it.get("speedModType", "percent") == "flat": speed_mod_flat += sv
			else: speed_mod_pct += sv
		# Motores (e) - base velocidad | modifica Escudo y Vida
		for it in ship_e.get("e", []):
			if _is_item_hidden(str(it.get("id", ""))): continue # v620.0: Ojito de visibilidad
			speed_bonus += float(it.get("base", 0))
			var shv = float(it.get("shieldMod", 0))
			if it.get("shieldModType", "percent") == "flat": shield_mod_flat += shv
			else: shield_mod_pct += shv
			var hv = float(it.get("hpMod", 0))
			if it.get("hpModType", "percent") == "flat": hp_mod_flat += hv
			else: hp_mod_pct += hv
		# Extras (x)
		for it in ship_e.get("x", []):
			if _is_item_hidden(str(it.get("id", ""))): continue # v620.0: Ojito de visibilidad
			total_hp_bonus += float(it.get("base", 0))

	# Aplicar el cálculo
	var base_hp = float(model.get("hp", 0))
	var base_sh = float(model.get("shield", 0))
	var base_speed = float(model.get("speed", 0))
	var base_atk = 100.0
	if model.has("baseDmg"): base_atk = float(model.baseDmg)
	elif model.has("base_damage"): base_atk = float(model.base_damage)

	var final_hp = (base_hp + total_hp_bonus + hp_mod_flat) * (1.0 + hp_mod_pct / 100.0)
	var final_sh = (base_sh + total_sh_bonus + shield_mod_flat) * (1.0 + shield_mod_pct / 100.0)
	var final_speed = (base_speed + speed_bonus + speed_mod_flat) * (1.0 + speed_mod_pct / 100.0)
	var final_atk = ((base_atk + bonus_w) * (1.0 + dmg_mod_pct / 100.0)) + dmg_mod_flat

	var bonus_hp = int(round(final_hp - base_hp))
	var bonus_sh = int(round(final_sh - base_sh))
	var bonus_e = int(round(final_speed - base_speed))
	var bonus_atk = int(round(final_atk - base_atk))
	
	var stats_grid = GridContainer.new(); stats_grid.columns = 2; stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(stats_grid)
	var create_stat = func(txt, base_val, bonus, label_color):
		var lbl = Label.new(); lbl.text = txt; lbl.add_theme_font_size_override("font_size", 8); lbl.modulate = label_color; lbl.modulate.a = 0.7; stats_grid.add_child(lbl)
		var h_val = HBoxContainer.new(); h_val.add_theme_constant_override("separation", 2); stats_grid.add_child(h_val)
		var base_lbl = Label.new(); base_lbl.text = str(base_val); base_lbl.add_theme_font_size_override("font_size", 8); base_lbl.modulate = Color.WHITE; h_val.add_child(base_lbl)
		if bonus > 0:
			var b_lbl = Label.new(); b_lbl.text = "+" + str(bonus); b_lbl.add_theme_font_size_override("font_size", 7); b_lbl.modulate = Color.GREEN; h_val.add_child(b_lbl)
	
	create_stat.call("HP:", int(base_hp), int(bonus_hp), Color.GREEN)
	create_stat.call("SH:", int(base_sh), int(bonus_sh), Color.AQUA)
	create_stat.call("VEL:", int(base_speed), int(bonus_e), Color.YELLOW)
	create_stat.call("ATK:", int(base_atk), int(bonus_atk), Color.RED)

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
	# v620.0: Ojito de visibilidad — ítems ocultos no se muestran equipados
	var eq = []
	if ship_equip.has(type) and ship_equip[type] is Array:
		for it in ship_equip[type]:
			if not _is_item_hidden(str(it.get("id", ""))):
				eq.append(it)
	
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
				var tex_res = null
				if _texture_cache.has(icon_path):
					tex_res = _texture_cache[icon_path]
				else:
					tex_res = load(icon_path)
					_texture_cache[icon_path] = tex_res
					
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
						var player_node = get_tree().get_first_node_in_group("player")
						var in_combat = false
						if is_instance_valid(player_node) and player_node.has_method("is_in_combat"):
							in_combat = player_node.is_in_combat()
						
						if not in_combat:
							# v308.3: Actualización optimista local al desequipar
							var sid_str2 = str(viewing_id)
							if inv_main.equipped_by_ship.has(sid_str2) and inv_main.equipped_by_ship[sid_str2].has(type):
								inv_main.equipped_by_ship[sid_str2][type].remove_at(i)
								inv_main.inventory_items.append(item_data.duplicate(true))
								inv_main.inv_main_preserve_ship_id = viewing_id  # Preservar vista de nave
								call_deferred("update_ui")  # v308.4: Diferido para no destruir el nodo durante su propio evento
							NetworkManager.send_event("unequipItem", {"category": type, "instanceId": item_data.get("instanceId", ""), "shipId": viewing_id})
						else:
							NetworkManager.game_notification.emit({
								"msg": "ERROR: No puedes modificar tu equipamiento en combate.",
								"type": "error"
							})
			)
		else: var c = Label.new(); c.text = "+"; c.horizontal_alignment = 1; c.modulate.a = 0.1; p.add_child(c)
		grid.add_child(p)

func _create_item_row(it, parent):
	if not it or not it.has("name"): return 
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 45); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL; var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.03); p.add_theme_stylebox_override("panel", sb)
	var hb = HBoxContainer.new(); hb.add_theme_constant_override("separation", 8); p.add_child(hb); var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var item_id = str(it.get("id", "")).to_lower()
	var item_type = str(it.get("type", "")).to_lower()
	var is_material_or_recipe = (item_type == "resource" or item_type == "recipe" or item_id.begins_with("mat_") or item_id.begins_with("recipe_"))
	var is_consumible = (item_type == "consumible")
	
	var item_slot = inv_main._get_slot_from_id(item_id)
	var slot_color = Color.CYAN
	if item_slot == "w": slot_color = Color.RED
	elif item_slot == "s": slot_color = Color.AQUA
	elif item_slot == "e": slot_color = Color.YELLOW
	elif item_slot == "x": slot_color = Color.MEDIUM_PURPLE
	
	var amount = int(it.get("amount", 1))
	var name_text = str(it.get("name", "ITEM")).to_upper()
	if amount > 1:
		name_text += " (x" + str(amount) + ")"
	var n = Label.new(); n.text = name_text; n.add_theme_font_size_override("font_size", 10); n.modulate = slot_color; n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(n); n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_val = int(round(float(it.get("base", 0))))
	var stat_text = ""
	if item_slot == "w":
		stat_text = "DAÑO: " + str(base_val)
		var sp_m = int(round(float(it.get("speedMod", 0))))
		if sp_m != 0:
			var t = "+" if sp_m > 0 else ""
			var suffix = "%" if it.get("speedModType", "percent") == "percent" else ""
			stat_text += " | VEL: " + t + str(sp_m) + suffix
		var hp_m = int(round(float(it.get("hpMod", 0))))
		if hp_m != 0:
			var t = "+" if hp_m > 0 else ""
			var suffix = "%" if it.get("hpModType", "percent") == "percent" else ""
			stat_text += " | HP: " + t + str(hp_m) + suffix
	elif item_slot == "s":
		stat_text = "ESCUDO: " + str(base_val)
		var hp_m = int(round(float(it.get("hpMod", 0))))
		if hp_m != 0:
			var t = "+" if hp_m > 0 else ""
			var suffix = "%" if it.get("hpModType", "percent") == "percent" else ""
			stat_text += " | HP: " + t + str(hp_m) + suffix
		var sp_m = int(round(float(it.get("speedMod", 0))))
		if sp_m != 0:
			var t = "+" if sp_m > 0 else ""
			var suffix = "%" if it.get("speedModType", "percent") == "percent" else ""
			stat_text += " | VEL: " + t + str(sp_m) + suffix
	elif item_slot == "e":
		stat_text = "VELOCIDAD: +" + str(base_val)
		var sh_m = int(round(float(it.get("shieldMod", 0))))
		if sh_m != 0:
			var t = "+" if sh_m > 0 else ""
			var suffix = "%" if it.get("shieldModType", "percent") == "percent" else ""
			stat_text += " | ESCUDO: " + t + str(sh_m) + suffix
		var hp_m = int(round(float(it.get("hpMod", 0))))
		if hp_m != 0:
			var t = "+" if hp_m > 0 else ""
			var suffix = "%" if it.get("hpModType", "percent") == "percent" else ""
			stat_text += " | HP: " + t + str(hp_m) + suffix
	var st = Label.new(); st.text = stat_text; st.add_theme_font_size_override("font_size", 8); st.modulate.a = 0.8; st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(st); st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# v400.0: Requisitos de equipamiento — indicador visual de bloqueo en la bodega
	if NetworkManager and not is_material_or_recipe:
		var req_check = NetworkManager.check_equip_requirements(item_id)
		if not req_check.get("ok", true):
			var req_lbl = Label.new()
			req_lbl.text = "🔒 " + str(req_check.get("msg", "REQUISITOS NO CUMPLIDOS"))
			req_lbl.add_theme_font_size_override("font_size", 7)
			req_lbl.modulate = Color(1, 0.35, 0.35)
			v.add_child(req_lbl)
			req_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.modulate = Color(0.65, 0.65, 0.65, 0.75)
	
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
		var tex_res = null
		if _texture_cache.has(icon_path):
			tex_res = _texture_cache[icon_path]
		else:
			tex_res = load(icon_path)
			_texture_cache[icon_path] = tex_res
			
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
	
	# v700.0: Los ítems consumibles (naves/esferas fabricadas) no se venden a NPC — se comercian en el Mercado
	if not is_consumible:
		var b_sell = Button.new(); b_sell.text = "VENDER"; b_sell.modulate = Color(1, 0.4, 0.4); b_sell.add_theme_font_size_override("font_size", 8)
		b_sell.pressed.connect(func():
			# v308.5: Validación previa de combate en cliente antes de confirmar
			var player_node = get_tree().get_first_node_in_group("player")
			if is_instance_valid(player_node):
				var time_since_combat = Time.get_ticks_msec() - player_node.last_combat_time
				var combat_delay = 60000 # Cooldown autoritativo de 60s
				if time_since_combat < combat_delay:
					var remaining = int(ceil((combat_delay - time_since_combat) / 1000.0))
					NetworkManager.game_notification.emit({
						"msg": "ERROR: Sistemas calientes. Espera " + str(remaining) + "s para vender.", 
						"type": "error"
					})
					return

			var single_refund = 0
			for cat_key in GameConstants.SHOP_ITEMS:
				var category = GameConstants.SHOP_ITEMS[cat_key]
				if category is Array:
					for shop_item in category:
						if str(shop_item.get("id", "")).to_lower() == search_id:
							var prices = shop_item.get("prices", {})
							if prices.has("hubs"):
								single_refund = int(prices["hubs"] / 2)
								break
				if single_refund > 0: break
			
			var msg_name = str(it.get("name", "ITEM")).to_upper()
			
			if amount > 1:
				var slider_container = VBoxContainer.new()
				slider_container.add_theme_constant_override("separation", 10)
				
				var val_lbl = Label.new()
				val_lbl.text = "Cantidad a vender:"
				val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				slider_container.add_child(val_lbl)
				
				var input_hb = HBoxContainer.new()
				input_hb.alignment = BoxContainer.ALIGNMENT_CENTER
				input_hb.add_theme_constant_override("separation", 10)
				slider_container.add_child(input_hb)
				
				var slider = HSlider.new()
				slider.min_value = 1
				slider.max_value = amount
				slider.value = amount
				slider.step = 1
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				input_hb.add_child(slider)
				
				var input_edit = LineEdit.new()
				input_edit.text = str(amount)
				input_edit.custom_minimum_size.x = 65
				input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
				input_hb.add_child(input_edit)

				var refund_lbl = Label.new()
				refund_lbl.text = "(Reembolso: " + str(single_refund * amount) + " HUBS)"
				refund_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				slider_container.add_child(refund_lbl)
				
				slider.value_changed.connect(func(val):
					input_edit.text = str(int(val))
					refund_lbl.text = "(Reembolso: " + str(single_refund * int(val)) + " HUBS)"
				)
				
				input_edit.text_changed.connect(func(new_text):
					var val = int(new_text)
					if val < 1: val = 1
					elif val > amount: val = amount
					slider.value = val
					refund_lbl.text = "(Reembolso: " + str(single_refund * val) + " HUBS)"
				)
				
				input_edit.text_submitted.connect(func(_new_text):
					input_edit.release_focus()
				)
				
				var msg = "¿Confirmas la venta de parte de [color=yellow]" + msg_name + "[/color]?"
				inv_main._show_modal("CONFIRMAR VENTA PARCIAL", msg, func():
					NetworkManager.send_event("sellItem", {"instanceId": it.get("instanceId", ""), "quantity": int(slider.value)})
				, slider_container)
			else:
				var msg = "¿Confirmas la venta de [color=yellow]" + msg_name + "[/color] por [color=green]" + str(single_refund) + " HUBS[/color]?"
				inv_main._show_modal("CONFIRMAR VENTA", msg, func():
					NetworkManager.send_event("sellItem", {"instanceId": it.get("instanceId", "")})
				)
		)
		action_hb.add_child(b_sell)

	if amount > 1:
		var b_split = Button.new(); b_split.text = "SEPARAR"; b_split.modulate = Color(0.4, 0.8, 1); b_split.add_theme_font_size_override("font_size", 8)
		b_split.pressed.connect(func():
			var slider_container = VBoxContainer.new()
			slider_container.add_theme_constant_override("separation", 10)
			
			var val_lbl = Label.new()
			val_lbl.text = "Cantidad a separar:"
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slider_container.add_child(val_lbl)
			
			var input_hb = HBoxContainer.new()
			input_hb.alignment = BoxContainer.ALIGNMENT_CENTER
			input_hb.add_theme_constant_override("separation", 10)
			slider_container.add_child(input_hb)
			
			var slider = HSlider.new()
			slider.min_value = 1
			slider.max_value = amount - 1
			slider.value = amount - 1
			slider.step = 1
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			input_hb.add_child(slider)
			
			var input_edit = LineEdit.new()
			input_edit.text = str(amount - 1)
			input_edit.custom_minimum_size.x = 65
			input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
			input_hb.add_child(input_edit)

			var remain_lbl = Label.new()
			remain_lbl.text = "(Quedan: 1)"
			remain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slider_container.add_child(remain_lbl)
			
			slider.value_changed.connect(func(val):
				input_edit.text = str(int(val))
				remain_lbl.text = "(Quedan: " + str(amount - int(val)) + ")"
			)
			
			input_edit.text_changed.connect(func(new_text):
				var val = int(new_text)
				if val < 1: val = 1
				elif val > amount - 1: val = amount - 1
				slider.value = val
				remain_lbl.text = "(Quedan: " + str(amount - val) + ")"
			)
			
			input_edit.text_submitted.connect(func(_new_text):
				input_edit.release_focus()
			)
			
			var msg = "¿Cuántas unidades deseas separar de este stack?"
			inv_main._show_modal("SEPARAR STACK", msg, func():
				NetworkManager.send_event("splitStack", {"instanceId": it.get("instanceId", ""), "quantity": int(slider.value)})
			, slider_container)
		)
		action_hb.add_child(b_split)

	if not is_material_or_recipe and not is_consumible:
		var b_equip = Button.new(); b_equip.text = "EQUIPAR"; b_equip.add_theme_font_size_override("font_size", 9); action_hb.add_child(b_equip)
		var equip_func = func():
			var player_node = get_tree().get_first_node_in_group("player")
			var in_combat = false
			if is_instance_valid(player_node) and player_node.has_method("is_in_combat"):
				in_combat = player_node.is_in_combat()
			
			var viewing_id = inv_main.selected_hangar_ship_id if inv_main.selected_hangar_ship_id != -1 else inv_main.current_ship_id
			var iid = it.get("instanceId", "")

			# v400.0: Requisitos de equipamiento (nivel, misiones completadas) — validación local UX
			if NetworkManager:
				var req_check = NetworkManager.check_equip_requirements(str(it.get("id", "")))
				if not req_check.get("ok", true):
					NetworkManager.game_notification.emit({
						"msg": "EQUIPAMIENTO BLOQUEADO: " + str(req_check.get("msg", "Requisitos no cumplidos")),
						"type": "error"
					})
					return

			if not in_combat:
				# v308.3: Actualización optimista local — Respuesta visual inmediata sin esperar al servidor
				var sid_str = str(viewing_id)
				if not inv_main.equipped_by_ship.has(sid_str):
					inv_main.equipped_by_ship[sid_str] = {"w": [], "s": [], "e": [], "x": []}
				var slot = inv_main._get_slot_from_id(str(it.get("id", "")))
				inv_main.equipped_by_ship[sid_str][slot].append(it.duplicate(true))
				inv_main.inventory_items = inv_main.inventory_items.filter(func(x): return x.get("instanceId", "") != iid)
				inv_main.inv_main_preserve_ship_id = viewing_id  # Preservar para que _on_inventory_received no cambie la vista
				call_deferred("update_ui")  # v308.4: Diferido para no destruir el nodo durante su propio evento de botón
				NetworkManager.send_event("equipItem", {"instanceId": iid, "shipId": viewing_id})
			else:
				NetworkManager.game_notification.emit({
					"msg": "ERROR: No puedes modificar tu equipamiento en combate.",
					"type": "error"
				})
		
		b_equip.pressed.connect(equip_func)
		
		# Doble Click en toda la fila para equipar
		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.double_click:
				equip_func.call()
		)

	# v700.0: Ítems consumibles (naves fabricadas/compradas en el Mercado) — botón USAR para desbloquear
	if is_consumible:
		var b_use = Button.new(); b_use.text = "USAR"; b_use.modulate = Color(0.5, 1, 0.6); b_use.add_theme_font_size_override("font_size", 9)
		b_use.pressed.connect(func():
			var iid = it.get("instanceId", "")
			var use_msg = "¿Deseas usar [color=yellow]" + str(it.get("name", "ITEM")).to_upper() + "[/color]? Se consumirá el ítem."
			inv_main._show_modal("USAR ÍTEM", use_msg, func():
				NetworkManager.send_event("useConsumableItem", {"instanceId": iid})
			)
		)
		action_hb.add_child(b_use)
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

func _clean_internal_lights_in_ui(node):
	for child in node.get_children():
		if child is Light3D:
			child.queue_free()
		else:
			_clean_internal_lights_in_ui(child)

# v390.0: Configura materiales Unshaded para las naves 1 a 6 en el visor del hangar
func _make_materials_unshaded_in_ui(node: Node):
	if not is_instance_valid(node): return
	if node is MeshInstance3D:
		if node.material_override and node.material_override is BaseMaterial3D:
			node.material_override = node.material_override.duplicate()
			node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if mat and mat is BaseMaterial3D:
				var dup_mat = mat.duplicate()
				dup_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				node.set_surface_override_material(i, dup_mat)
			else:
				var active_mat = node.get_active_material(i)
				if active_mat and active_mat is BaseMaterial3D:
					var dup_mat = active_mat.duplicate()
					dup_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					node.set_surface_override_material(i, dup_mat)
	for child in node.get_children():
		_make_materials_unshaded_in_ui(child)

func _process(delta):
	if is_instance_valid(preview_mesh):
		preview_mesh.rotate_y(delta * 0.5)
