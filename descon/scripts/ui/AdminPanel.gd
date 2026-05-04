extends "res://scripts/systems/HUDWindow.gd"

# AdminPanel.gd (Godot Master Admin v3.0)
# Portabilidad total del sistema legacy con soporte para edición en tiempo real.

var current_tab = "ships"

func _ready():
	add_to_group("admin_panel_ui") # v244.86: Coordinación global
	window_id = "AdminPanel"
	header_height = 30
	z_index = 200 # Por encima de todo
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	super._ready()
	_create_drag_handler()
	
	# v190.60: Sincronía de Dimensiones al 85%
	# v190.62: Sincronía Responsive
	get_viewport().size_changed.connect(func(): queue_redraw())
	
	_update_window_size()
	
	# v190.50: Limpiar UI vieja y preparar contenedor dinámico
	for n in get_children(): if n.name != "Header": n.queue_free()
	
	var main_v = VBoxContainer.new()
	main_v.name = "MainVBox"
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_top = 45; main_v.offset_bottom = -15; main_v.offset_left = 15; main_v.offset_right = -15
	add_child(main_v)
	
	_build_ui()

func _draw():
	if not visible: return
	var screen_size = get_viewport_rect().size
	var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
	var r_pos = Vector2.ZERO # El panel ya está posicionado por _update_window_size()
	
	# v226.35: Fondo consistente con F1 (0.98 opacidad)
	draw_rect(Rect2(r_pos, r_size), Color(0.02, 0.02, 0.05, 0.98))
	draw_rect(Rect2(r_pos, Vector2(r_size.x, 35)), Color(0, 0.08, 0.12, 1.0))
	draw_rect(Rect2(r_pos, r_size), Color(0, 0.8, 1, 0.5), false, 1.5)
	
	# Botones de Control Visuales [X]
	var f = get_theme_font("font")
	draw_rect(Rect2(r_pos.x + r_size.x - 35, r_pos.y+8, 25, 18), Color(0, 1, 1), false, 1.0)
	draw_string(f, r_pos + Vector2(r_size.x-30, 22), "[X]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 1, 1))

func _input(event):
	# v190.65: Primero capturar clic para el botón cerrar [X] (Sin importar el foco)
	if event is InputEventMouseButton and event.pressed and visible:
		var screen_size = get_viewport_rect().size
		var r_size = Vector2(screen_size.x * 0.85, screen_size.y * 0.85)
		var x_rect = Rect2(global_position.x + r_size.x - 35, global_position.y + 8, 25, 18)
		if x_rect.has_point(event.position): 
			toggle()
			get_viewport().set_input_as_handled()
			return


	if event is InputEventKey and event.pressed:
		# v244.60: Bloquear panel admin en el login
		if not NetworkManager or not NetworkManager.is_logged_in: return

		if event.keycode == KEY_F2:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			toggle()
			get_viewport().set_input_as_handled()

func toggle():
	visible = !visible
	if visible: 
		_update_window_size()
		_refresh_ui()
		# v226.36: PRIORIDAD ABSOLUTA - Mover al frente
		if get_parent(): get_parent().move_child(self, get_parent().get_child_count() - 1)
		z_index = 200
	else:
		z_index = 0
	queue_redraw()

func _update_window_size():
	var screen_size = get_viewport_rect().size
	var target_w = screen_size.x * 0.85
	var target_h = screen_size.y * 0.85
	
	custom_minimum_size = Vector2(target_w, target_h)
	size = custom_minimum_size
	
	# Centrar en pantalla
	position = (screen_size - size) / 2.0
	
	# v210.10: El Header ya no es necesario como nodo visual sino como zona de arrastre
	header_height = 35

func _build_ui():
	var main_v = get_node_or_null("MainVBox")
	if not main_v: return
	for n in main_v.get_children(): n.queue_free()
	
	# 1. Barra de Pestañas Estilizada
	var tab_bar = HBoxContainer.new(); main_v.add_child(tab_bar)
	tab_bar.add_theme_constant_override("separation", 5)
	
	var tabs = {"ships": "NAVES", "enemies": "ENEMIGOS", "hordes": "HORDAS", "map": "MONITOR", "items": "ITEMS", "ammo": "MUNICIÓN", "spheres": "ESFERAS"}
	for k in tabs:
		var b = Button.new(); b.text = tabs[k]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.flat = true
		
		# Estilo de Pestaña F1
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0.6, 0.8, 0.3) if current_tab == k else Color(0, 0, 0, 0.2)
		sb.border_width_bottom = 2 if current_tab == k else 0
		sb.border_color = Color.CYAN
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		
		b.modulate = Color.CYAN if current_tab == k else Color(0.7, 0.7, 0.7)
		b.pressed.connect(func(): current_tab = k; _build_ui())
		tab_bar.add_child(b)
	
	var sep = Control.new(); sep.custom_minimum_size.y = 10; main_v.add_child(sep)
	
	# 2. Área de Trabajo (Scrollable) con estilo oscuro
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; main_v.add_child(scroll)
	var content = VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(content)
	content.add_theme_constant_override("separation", 12)
	
	# 3. Renderizado según Tab
	match current_tab:
		"ships": _render_ships(content)
		"enemies": _render_enemies(content)
		"hordes": _render_hordes(content)
		"map": _render_map_selection(content)
		"items": _render_items(content)
		"ammo": _render_ammo(content)
		"spheres": _render_spheres(content)
	
	# 4. Botón de Guardado Maestro Mejorado
	var save_p = PanelContainer.new(); main_v.add_child(save_p)
	var s_sb = StyleBoxFlat.new(); s_sb.bg_color = Color(0.1, 0.5, 0.2, 0.4); s_sb.set_border_width_all(1); s_sb.border_color = Color.GREEN
	save_p.add_theme_stylebox_override("panel", s_sb)
	
	var save_btn = Button.new(); save_btn.text = "Sincronizar Cambios con el Universo (SERVER)"; save_btn.flat = true
	save_btn.pressed.connect(_on_save_global_pressed)
	save_p.add_child(save_btn)



func _render_ships(container):
	for i in range(GameConstants.SHIP_MODELS.size()):
		var ship = GameConstants.SHIP_MODELS[i]
		var card = _create_card(container, "REF_ID [" + str(ship.id) + "] - " + ship.name.to_upper())
		var grid = _create_grid(card, 5) # Subir a 5 columnas para el nombre
		
		# Propiedades Básicas (v226.15: RENOMBRAR SOPORTE)
		_add_input(grid, "NOMBRE", ship.name, func(v): GameConstants.SHIP_MODELS[i].name = v, true)
		_add_input(grid, "HP", str(int(ship.hp)), func(v): GameConstants.SHIP_MODELS[i].hp = int(float(v)))
		_add_input(grid, "SH", str(int(ship.shield)), func(v): GameConstants.SHIP_MODELS[i].shield = int(float(v)))
		_add_input(grid, "SPD", str(int(ship.speed)), func(v): GameConstants.SHIP_MODELS[i].speed = int(float(v)))
		
		# Slots
		_add_input(grid, "W_SLOT", str(ship.slots.w), func(v): GameConstants.SHIP_MODELS[i].slots.w = int(v))
		_add_input(grid, "S_SLOT", str(ship.slots.s), func(v): GameConstants.SHIP_MODELS[i].slots.s = int(v))
		_add_input(grid, "E_SLOT", str(ship.slots.e), func(v): GameConstants.SHIP_MODELS[i].slots.e = int(v))
		_add_input(grid, "X_SLOT", str(ship.slots.x), func(v): GameConstants.SHIP_MODELS[i].slots.x = int(v))
		
		# Economía
		_add_input(grid, "HUBS", str(int(ship.prices.hubs)), func(v): GameConstants.SHIP_MODELS[i].prices.hubs = int(float(v)))
		_add_input(grid, "OHCU", str(int(ship.prices.ohcu)), func(v): GameConstants.SHIP_MODELS[i].prices.ohcu = int(float(v)))

func _render_enemies(container):
	for id in GameConstants.ENEMY_MODELS:
		var enemy = GameConstants.ENEMY_MODELS[id]
		var card = _create_card(container, "ENTIDAD [" + str(id) + "] - " + enemy.name.to_upper())
		var grid = _create_grid(card, 4)
		
		_add_input(grid, "NOMBRE", enemy.name, func(v): GameConstants.ENEMY_MODELS[id].name = v, true)
		_add_input(grid, "HP", str(enemy.hp), func(v): GameConstants.ENEMY_MODELS[id].hp = int(v))
		_add_input(grid, "SH", str(enemy.shield), func(v): GameConstants.ENEMY_MODELS[id].shield = int(v))
		_add_input(grid, "DMG", str(enemy.bulletDamage), func(v): GameConstants.ENEMY_MODELS[id].bulletDamage = int(v))
		_add_input(grid, "RATE", str(enemy.fireRate), func(v): GameConstants.ENEMY_MODELS[id].fireRate = int(v))
		_add_input(grid, "R_HUBS", str(enemy.rewardHubs), func(v): GameConstants.ENEMY_MODELS[id].rewardHubs = int(v))
		_add_input(grid, "R_OHCU", str(enemy.get("rewardOhcu", 0)), func(v): GameConstants.ENEMY_MODELS[id].rewardOhcu = int(v))
		_add_input(grid, "R_EXP", str(enemy.get("rewardExp", 100)), func(v): GameConstants.ENEMY_MODELS[id].rewardExp = int(v))
		_add_input(grid, "SPD", str(enemy.get("speed", 3.0)), func(v): GameConstants.ENEMY_MODELS[id].speed = float(v))
		_add_input(grid, "B_SPD", str(enemy.get("bulletSpeed", 800)), func(v): GameConstants.ENEMY_MODELS[id].bulletSpeed = int(v))
		_add_input(grid, "RANGE", str(enemy.get("fireRange", 600)), func(v): GameConstants.ENEMY_MODELS[id].fireRange = int(v))
		_add_input(grid, "RAGETIME", str(enemy.get("rageTimer", 20)), func(v): GameConstants.ENEMY_MODELS[id].rageTimer = int(v))

func _render_items(container):
	for cat in ["weapons", "shields", "engines"]:
		var label = Label.new(); label.text = "\nSISTEMA: " + cat.to_upper(); label.modulate = Color.GOLD; container.add_child(label)
		var list = GameConstants.SHOP_ITEMS.get(cat, [])
		for i in range(list.size()):
			var item = list[i]
			var card = _create_card(container, "ITEM: " + item.name.to_upper())
			var grid = _create_grid(card, 4)
			_add_input(grid, "NOMBRE", item.name, func(v): GameConstants.SHOP_ITEMS[cat][i].name = v, true)
			_add_input(grid, "BASE", str(item.get("base", 0)), func(v): GameConstants.SHOP_ITEMS[cat][i].base = int(v))
			_add_input(grid, "HUBS", str(item.prices.hubs), func(v): GameConstants.SHOP_ITEMS[cat][i].prices.hubs = int(v))
			_add_input(grid, "OHCU", str(item.prices.ohcu), func(v): GameConstants.SHOP_ITEMS[cat][i].prices.ohcu = int(v))

func _render_ammo(container):
	for cat in ["laser", "missile", "mine"]:
		var label = Label.new(); label.text = "\nMUNICIÓN: " + cat.to_upper(); label.modulate = Color.GOLD; container.add_child(label)
		var mults = GameConstants.AMMO_MULTIPLIERS.get(cat, [])
		var shop_ammo = GameConstants.SHOP_ITEMS.ammo.get(cat, [])
		
		for i in range(mults.size()):
			var item_name = "TIER T" + str(i+1)
			if i < shop_ammo.size(): item_name = shop_ammo[i].name
			
			var card = _create_card(container, item_name.to_upper())
			var grid = _create_grid(card, 5)
			
			if i < shop_ammo.size():
				_add_input(grid, "NOMBRE", shop_ammo[i].name, func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].name = v, true)
				_add_input(grid, "MULT", str(mults[i]), func(v): GameConstants.AMMO_MULTIPLIERS[cat][i] = float(v))
				_add_input(grid, "RANGO", str(shop_ammo[i].get("range", 600)), func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].range = int(v))
				_add_input(grid, "P_HUBS", str(shop_ammo[i].prices.hubs), func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].prices.hubs = int(v))
				_add_input(grid, "P_OHCU", str(shop_ammo[i].prices.ohcu), func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].prices.ohcu = int(v))

func _render_spheres(container):
	var lbl = Label.new(); lbl.text = "CONFIGURACIÓN DE HABILIDADES DE ESFERAS"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	
	# v3.1: Agrupación por Colores (Azul, Verde, Rojo, etc.)
	var sphere_tabs = TabContainer.new()
	sphere_tabs.custom_minimum_size.y = 450
	container.add_child(sphere_tabs)
	
	var categories = {
		"AZUL (Defensa)": ["Defensa", "Escudo"],
		"VERDE (Curación)": ["Curación", "Reparación"],
		"ROJO (Ataque)": ["Ataque", "Combat", "Daño"],
		"AMARILLO (Movimiento)": ["Movimiento", "Velocidad"]
	}
	
	var tab_nodes = {}
	for cat_name in categories:
		var scroll = ScrollContainer.new()
		scroll.name = cat_name
		sphere_tabs.add_child(scroll)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 10)
		scroll.add_child(vbox)
		tab_nodes[cat_name] = vbox

	# v3.1: Renderizar cada habilidad en su pestaña correspondiente
	for s_name in GameConstants.SKILLS_DATA:
		var skill = GameConstants.SKILLS_DATA[s_name]
		var target_cat = ""
		
		for cat_name in categories:
			if skill.type in categories[cat_name]:
				target_cat = cat_name; break
		
		if target_cat == "": continue # Ignorar si no tiene categoría válida
		
		var card = _create_card(tab_nodes[target_cat], "ESFERA: " + s_name.to_upper())
		
		# v3.3: Cabecera con botón de eliminar
		var header_hb = HBoxContainer.new()
		card.add_child(header_hb)
		card.move_child(header_hb, 0) # Poner arriba del grid
		
		# v3.5: Usar referencia para evitar error de captura en lambdas
		var k_ref = {"name": s_name}
		var grid = _create_grid(card, 5)
		
		# v3.4: Input de NOMBRE más ancho
		var name_hb = VBoxContainer.new(); grid.add_child(name_hb)
		var name_l = Label.new(); name_l.text = "NOMBRE"; name_l.add_theme_font_size_override("font_size", 9); name_l.modulate.a = 0.5; name_hb.add_child(name_l)
		var name_inp = LineEdit.new(); name_inp.text = s_name; name_inp.custom_minimum_size.x = 200; name_hb.add_child(name_inp)
		name_inp.text_changed.connect(func(v):
			if v == "" or v == k_ref.name: return
			var data = GameConstants.SKILLS_DATA[k_ref.name]
			GameConstants.SKILLS_DATA.erase(k_ref.name)
			GameConstants.SKILLS_DATA[v] = data
			k_ref.name = v
		)
		
		# v3.4: Selector de TIPO (OptionButton)
		var type_hb = VBoxContainer.new(); grid.add_child(type_hb)
		var type_l = Label.new(); type_l.text = "TIPO"; type_l.add_theme_font_size_override("font_size", 9); type_l.modulate.a = 0.5; type_hb.add_child(type_l)
		var type_opt = OptionButton.new(); type_hb.add_child(type_opt)
		var types = ["Defensa", "Curación", "Ataque", "Movimiento"]
		for t in types:
			type_opt.add_item(t)
			if t == skill.type: type_opt.selected = type_opt.get_item_count() - 1
		
		type_opt.item_selected.connect(func(idx):
			GameConstants.SKILLS_DATA[k_ref.name].type = type_opt.get_item_text(idx)
		)

		_add_input(grid, "COOLDOWN (S)", str(skill.get("cd", 10.0)), func(v): GameConstants.SKILLS_DATA[k_ref.name].cd = float(v))
		_add_input(grid, "RANGO", str(skill.get("range", 0)), func(v): GameConstants.SKILLS_DATA[k_ref.name].range = float(v))

		# Botón de eliminar (v3.3)
		var btn_del = Button.new(); btn_del.text = " ELIMINAR ESFERA "; btn_del.modulate = Color.RED; btn_del.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn_del.pressed.connect(func():
			GameConstants.SKILLS_DATA.erase(k_ref.name)
			_build_ui()
		)
		grid.add_child(btn_del)
		
		if skill.has("amount"):
			_add_input(grid, "VALOR (HP/SH)", str(skill.amount), func(v): GameConstants.SKILLS_DATA[k_ref.name].amount = int(v))
		if skill.has("speed"):
			_add_input(grid, "VELOCIDAD", str(skill.speed), func(v): GameConstants.SKILLS_DATA[k_ref.name].speed = float(v))
		if skill.has("reflect_mult"):
			_add_input(grid, "MULT. DAÑO", str(skill.reflect_mult), func(v): GameConstants.SKILLS_DATA[k_ref.name].reflect_mult = float(v))

	# Botón para añadir nuevas (v3.1)
	var add_btn = Button.new(); add_btn.text = " [+] AÑADIR NUEVA HABILIDAD / ESFERA "; add_btn.modulate = Color.CYAN
	add_btn.pressed.connect(func():
		var new_name = "NUEVA_ESFERA_" + str(GameConstants.SKILLS_DATA.size() + 1)
		GameConstants.SKILLS_DATA[new_name] = { "type": "Defensa", "cd": 15.0, "range": 0, "amount": 1000 }
		_build_ui()
	)
	container.add_child(add_btn)

func _render_map_selection(container):
	var lbl = Label.new(); lbl.text = "SISTEMA DE VISUALIZACIÓN Y NAVEGACIÓN"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	
	var info = Label.new(); info.text = "Desde aquí puedes abrir el monitor táctico o teletransportarte a sectores específicos."; info.modulate.a = 0.6; info.add_theme_font_size_override("font_size", 9); container.add_child(info)
	
	# --- SECCIÓN 1: MONITOR ---
	var btn_open = Button.new(); btn_open.text = "ABRIR MONITOR TÁCTICO (MODAL)"; btn_open.custom_minimum_size = Vector2(0, 50); btn_open.modulate = Color.CYAN
	btn_open.pressed.connect(_on_open_map_pressed)
	container.add_child(btn_open)

	# --- SECCIÓN 2: TELETRANSPORTE (WARP) ---
	container.add_child(HSeparator.new())
	var warp_l = Label.new(); warp_l.text = "TELETRANSPORTE POR SECTOR (WARP INTERNO)"; warp_l.modulate = Color.CYAN; container.add_child(warp_l)
	
	var warp_h = HBoxContainer.new(); warp_h.add_theme_constant_override("separation", 10); container.add_child(warp_h)
	for i in range(1, 9):
		var b = Button.new(); b.text = " SECTOR " + str(i) + " "; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 8: b.modulate = Color.RED; b.text = "[ BOSS 1 MAP ]"
		
		b.pressed.connect(func(): 
			NetworkManager.send_event("warpToZone", {"zone": i})
			visible = false # Cerrar panel al viajar
		)
		warp_h.add_child(b)
	
	container.add_child(HSeparator.new())
	var btn_view = Button.new(); btn_view.text = "REFORZAR SCANNER DE LOOT (LIMPIEZA VISUAL)"; btn_view.custom_minimum_size = Vector2(0, 40)
	btn_view.pressed.connect(func(): 
		var world = get_tree().get_first_node_in_group("world_node")
		if world:
			for en_id in world.enemies.keys():
				var en = world.enemies[en_id]
				if is_instance_valid(en): en.queue_free()
			world.enemies.clear()
			print("[ADMIN] Scanner reforzado: Entidades purgadas.")
	)

	container.add_child(btn_view)

func _render_hordes(container):
	var lbl = Label.new(); lbl.text = "EDITOR DINÁMICO DE EVENTOS POR OLEADAS"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	
	var config = GameConstants.HORDES_CONFIG
	
	# --- SECCIÓN 1: CONFIGURACIÓN GLOBAL ---
	var card_global = _create_card(container, "AJUSTES GLOBALES DEL EVENTO")
	var grid_global = _create_grid(card_global, 4)
	
	var btn_status = Button.new()
	btn_status.text = "EVENTO: ACTIVO" if config.active else "EVENTO: INACTIVO"
	btn_status.modulate = Color.GREEN if config.active else Color.RED
	btn_status.pressed.connect(func(): 
		GameConstants.HORDES_CONFIG.active = !GameConstants.HORDES_CONFIG.active
		_build_ui()
	)
	grid_global.add_child(btn_status)
	
	_add_input(grid_global, "MAPA OBJETIVO", str(config.map), func(v): GameConstants.HORDES_CONFIG.map = int(v))
	_add_input(grid_global, "TIEMPO ENTRE OLEADAS (S)", str(config.timeBetweenWaves), func(v): GameConstants.HORDES_CONFIG.timeBetweenWaves = int(v))
	_add_input(grid_global, "ÍNDICE ACTUAL", str(config.currentWaveIndex), func(v): GameConstants.HORDES_CONFIG.currentWaveIndex = int(v))

	# --- SECCIÓN 2: LISTADO DE OLEADAS ---
	container.add_child(HSeparator.new())
	var lbl_waves = Label.new(); lbl_waves.text = "ESTRUCTURA DE OLEADAS (SECUENCIAL)"; lbl_waves.modulate = Color.CYAN; container.add_child(lbl_waves)
	
	for i in range(config.waves.size()):
		var wave = config.waves[i]
		var wave_panel = _create_card(container, "OLEADA #" + str(i+1) + ": " + wave.name.to_upper())
		wave_panel.modulate = Color(1, 1, 1, 0.9)
		
		var hb_wave_top = HBoxContainer.new(); wave_panel.add_child(hb_wave_top)
		_add_input(hb_wave_top, "NOMBRE DE OLEADA", wave.name, func(v): GameConstants.HORDES_CONFIG.waves[i].name = v, true)
		_add_input(hb_wave_top, "MULT. RECOMPENSA", str(wave.rewardMultiplier), func(v): GameConstants.HORDES_CONFIG.waves[i].rewardMultiplier = float(v))
		
		var btn_del_wave = Button.new(); btn_del_wave.text = " ELIMINAR OLEADA "; btn_del_wave.modulate = Color.RED
		btn_del_wave.pressed.connect(func(): 
			GameConstants.HORDES_CONFIG.waves.remove_at(i)
			_build_ui()
		)
		hb_wave_top.add_child(btn_del_wave)
		
		# --- SUB-SECCIÓN: ENEMIGOS EN ESTA OLEADA ---
		var lbl_en = Label.new(); lbl_en.text = "ENEMIGOS EN ESTA FASE:"; lbl_en.add_theme_font_size_override("font_size", 9); lbl_en.modulate.a = 0.7; wave_panel.add_child(lbl_en)
		
		for j in range(wave.enemies.size()):
			var enemy_cfg = wave.enemies[j]
			var hb_enemy = HBoxContainer.new(); hb_enemy.add_theme_constant_override("separation", 10); wave_panel.add_child(hb_enemy)
			
			# --- BUSCADOR Y SELECTOR DE ENEMIGO (v246.00) ---
			var search_box = LineEdit.new(); search_box.placeholder_text = "Filtrar..."; search_box.custom_minimum_size.x = 80; hb_enemy.add_child(search_box)
			var opt = OptionButton.new(); opt.custom_minimum_size.x = 180; hb_enemy.add_child(opt)
			
			# Función anidada para refrescar el OptionButton basado en el filtro
			var _populate_opt = func(filter_text: String):
				opt.clear()
				var f = filter_text.to_lower()
				var found_current = false
				for eid in GameConstants.ENEMY_MODELS:
					var e_name = GameConstants.ENEMY_MODELS[eid].name
					if f == "" or f in e_name.to_lower() or f in str(eid):
						opt.add_item(e_name + " [" + str(eid) + "]", int(eid))
						if str(eid) == str(enemy_cfg.type): 
							opt.selected = opt.get_item_count() - 1
							found_current = true
				
				# Si el enemigo actual no está en el filtro, lo añadimos igual para no romper la UI
				if not found_current and GameConstants.ENEMY_MODELS.has(str(enemy_cfg.type)):
					var e_data = GameConstants.ENEMY_MODELS[str(enemy_cfg.type)]
					opt.add_item("(*) " + e_data.name + " [" + str(enemy_cfg.type) + "]", int(enemy_cfg.type))
					opt.selected = opt.get_item_count() - 1

			# Inicializar y conectar
			_populate_opt.call("")
			search_box.text_changed.connect(_populate_opt)
			
			opt.item_selected.connect(func(index):
				var selected_id = str(opt.get_item_id(index))
				GameConstants.HORDES_CONFIG.waves[i].enemies[j].type = selected_id
			)
			
			_add_input(hb_enemy, "CANTIDAD", str(enemy_cfg.count), func(v): GameConstants.HORDES_CONFIG.waves[i].enemies[j].count = int(v))
			
			var btn_del_en = Button.new(); btn_del_en.text = "X"; btn_del_en.modulate = Color.ORANGE
			btn_del_en.pressed.connect(func(): 
				GameConstants.HORDES_CONFIG.waves[i].enemies.remove_at(j)
				_build_ui()
			)
			hb_enemy.add_child(btn_del_en)
		
		var btn_add_en = Button.new(); btn_add_en.text = " + AÑADIR TIPO DE ENEMIGO "; btn_add_en.flat = true; btn_add_en.modulate = Color.GREEN
		btn_add_en.pressed.connect(func(): 
			GameConstants.HORDES_CONFIG.waves[i].enemies.append({"type": "1", "count": 5})
			_build_ui()
		)
		wave_panel.add_child(btn_add_en)

	# --- SECCIÓN 3: ACCIONES FINALES ---
	var btn_add_wave = Button.new(); btn_add_wave.text = " [+] AÑADIR NUEVA OLEADA AL FINAL "; btn_add_wave.custom_minimum_size.y = 40
	btn_add_wave.pressed.connect(func(): 
		GameConstants.HORDES_CONFIG.waves.append({
			"name": "Nueva Oleada",
			"enemies": [{"type": "1", "count": 10}],
			"rewardMultiplier": 1.0
		})
		_build_ui()
	)
	container.add_child(btn_add_wave)
	
	container.add_child(HSeparator.new())
	var hb_ctrls = HBoxContainer.new(); container.add_child(hb_ctrls)
	
	var btn_start = Button.new(); btn_start.text = "REINICIAR E INICIAR EVENTO"; btn_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btn_start.modulate = Color.CYAN
	btn_start.pressed.connect(func(): NetworkManager.send_event("startHordeEvent", {}))
	hb_ctrls.add_child(btn_start)
	
	var btn_stop = Button.new(); btn_stop.text = "DETENER Y LIMPIAR"; btn_stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btn_stop.modulate = Color.ORANGE
	btn_stop.pressed.connect(func(): NetworkManager.send_event("stopHordeEvent", {}))
	hb_ctrls.add_child(btn_stop)


func _on_open_map_pressed():
	var world = get_tree().get_first_node_in_group("world_node")
	if not is_instance_valid(world): return
	
	var hud = world.get_node_or_null("HUD")
	if not hud: hud = world # Fallback si no hay nodo HUD
	
	var amap = hud.get_node_or_null("AdminMap")
	if not amap:
		# Instanciar dinámicamente si no existe
		var script = load("res://scripts/ui/AdminMap.gd")
		if script:
			amap = Control.new()
			amap.name = "AdminMap"
			amap.set_script(script)
			hud.add_child(amap)
			print("[ADMIN] Monitor Táctico instanciado en el HUD.")
	
	if is_instance_valid(amap):
		amap.visible = !amap.visible
		if amap.visible:
			amap.get_parent().move_child(amap, amap.get_parent().get_child_count() - 1)
			print("[ADMIN] Monitor Táctico activado.")
	
	visible = false # Cerrar el panel admin para ver el mapa

# --- HELPERS UI ---
func _create_card(parent, title):
	var p = PanelContainer.new(); parent.add_child(p)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0.2, 0.3, 0.2); sb.set_border_width_all(1); sb.border_color = Color(0, 0.8, 1, 0.3)
	p.add_theme_stylebox_override("panel", sb)
	
	var vb = VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); p.add_child(vb)
	var l = Label.new(); l.text = title; l.modulate = Color.CYAN; l.add_theme_font_size_override("font_size", 11); vb.add_child(l)
	return vb

func _create_grid(parent, cols):
	var g = GridContainer.new(); g.columns = cols; g.add_theme_constant_override("h_separation", 15); parent.add_child(g)
	return g

func _add_input(parent, label, val, on_change, is_text = false):
	var hb = VBoxContainer.new(); parent.add_child(hb)
	var l = Label.new(); l.text = label; l.add_theme_font_size_override("font_size", 9); l.modulate.a = 0.5; hb.add_child(l)
	
	var display_val = val
	if not is_text:
		# v226.55: ELIMINACIÓN TOTAL DE DECIMALES (Pedido del usuario para limpieza visual)
		display_val = str(int(float(val)))
	
	var inp = LineEdit.new(); inp.text = str(display_val); inp.custom_minimum_size = Vector2(100, 0); hb.add_child(inp)
	inp.text_changed.connect(on_change)

func _refresh_ui(): _build_ui()

func _on_save_global_pressed():
	# Enviar TODA la configuración al servidor
	var config = {
		"shipModels": GameConstants.SHIP_MODELS,
		"enemyModels": GameConstants.ENEMY_MODELS,
		"shopItems": GameConstants.SHOP_ITEMS,
		"ammoMultipliers": GameConstants.AMMO_MULTIPLIERS,
		"hordeConfig": GameConstants.HORDES_CONFIG,
		"skillsData": GameConstants.SKILLS_DATA
	}
	NetworkManager.send_event("saveAdminConfig", config)
	print("[ADMIN] Configuración Global enviada al servidor.")
	visible = false

func _create_drag_handler():
	var handle = Panel.new(); handle.name = "Header"; handle.custom_minimum_size = Vector2(500, 25)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.0); handle.add_theme_stylebox_override("panel", sb)
	add_child(handle); move_child(handle, 0)
