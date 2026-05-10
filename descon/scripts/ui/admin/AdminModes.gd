extends Node

var admin_main = null

func setup(main):
	admin_main = main

func render(container):
	var lbl = Label.new(); lbl.text = "GESTIÓN DE MODOS DE JUEGO"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	
	var mode_tabs = TabContainer.new()
	mode_tabs.custom_minimum_size.y = 500
	container.add_child(mode_tabs)
	
	# Sub-pestaña 1: HORDAS
	var horde_scroll = ScrollContainer.new(); horde_scroll.name = "HORDAS"; mode_tabs.add_child(horde_scroll)
	var horde_v = VBoxContainer.new(); horde_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; horde_scroll.add_child(horde_v)
	_render_hordes_tab(horde_v)
	
	# Sub-pestaña 2: EXTRACCIÓN
	var extr_scroll = ScrollContainer.new(); extr_scroll.name = "EXTRACCIÓN"; mode_tabs.add_child(extr_scroll)
	var extr_v = VBoxContainer.new(); extr_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; extr_scroll.add_child(extr_v)
	var extr_l = Label.new(); extr_l.text = "\nMODO EXTRACCIÓN: PRÓXIMAMENTE"; extr_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; extr_v.add_child(extr_l)
	
	# Sub-pestaña 3: CAZA
	var hunt_scroll = ScrollContainer.new(); hunt_scroll.name = "CAZA"; mode_tabs.add_child(hunt_scroll)
	var hunt_v = VBoxContainer.new(); hunt_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hunt_scroll.add_child(hunt_v)
	var hunt_l = Label.new(); hunt_l.text = "\nMODO CAZA: PRÓXIMAMENTE"; hunt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hunt_v.add_child(hunt_l)

func _render_hordes_tab(container):
	var lbl = Label.new(); lbl.text = "EDITOR DINÁMICO DE EVENTOS POR OLEADAS"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	
	var config = GameConstants.HORDES_CONFIG
	
	# --- SECCIÓN 1: CONFIGURACIÓN GLOBAL ---
	var card_global = admin_main._create_card(container, "AJUSTES GLOBALES DEL EVENTO")
	var grid_global = admin_main._create_grid(card_global, 4)
	
	var btn_status = Button.new()
	btn_status.text = "EVENTO: ACTIVO" if config.active else "EVENTO: INACTIVO"
	btn_status.modulate = Color.GREEN if config.active else Color.RED
	btn_status.pressed.connect(func(): 
		GameConstants.HORDES_CONFIG.active = !GameConstants.HORDES_CONFIG.active
		admin_main._build_ui()
	)
	grid_global.add_child(btn_status)
	
	admin_main._add_input(grid_global, "MAPA OBJETIVO", str(config.map), func(v): GameConstants.HORDES_CONFIG.map = int(v))
	admin_main._add_input(grid_global, "TIEMPO ENTRE OLEADAS (S)", str(config.timeBetweenWaves), func(v): GameConstants.HORDES_CONFIG.timeBetweenWaves = int(v))
	admin_main._add_input(grid_global, "ÍNDICE ACTUAL", str(config.currentWaveIndex), func(v): GameConstants.HORDES_CONFIG.currentWaveIndex = int(v))

	# --- SECCIÓN 2: LISTADO DE OLEADAS ---
	container.add_child(HSeparator.new())
	var lbl_waves = Label.new(); lbl_waves.text = "ESTRUCTURA DE OLEADAS (SECUENCIAL)"; lbl_waves.modulate = Color.CYAN; container.add_child(lbl_waves)
	
	for i in range(config.waves.size()):
		var wave = config.waves[i]
		var wave_panel = admin_main._create_card(container, "OLEADA #" + str(i+1) + ": " + wave.name.to_upper())
		wave_panel.modulate = Color(1, 1, 1, 0.9)
		
		var hb_wave_top = HBoxContainer.new(); wave_panel.add_child(hb_wave_top)
		admin_main._add_input(hb_wave_top, "NOMBRE DE OLEADA", wave.name, func(v): GameConstants.HORDES_CONFIG.waves[i].name = v, true)
		admin_main._add_input(hb_wave_top, "MULT. RECOMPENSA", str(wave.rewardMultiplier), func(v): GameConstants.HORDES_CONFIG.waves[i].rewardMultiplier = float(v))
		
		var btn_del_wave = Button.new(); btn_del_wave.text = " ELIMINAR OLEADA "; btn_del_wave.modulate = Color.RED
		btn_del_wave.pressed.connect(func(): 
			GameConstants.HORDES_CONFIG.waves.remove_at(i)
			admin_main._build_ui()
		)
		hb_wave_top.add_child(btn_del_wave)
		
		# --- SUB-SECCIÓN: ENEMIGOS EN ESTA OLEADA ---
		var lbl_en = Label.new(); lbl_en.text = "ENEMIGOS EN ESTA FASE:"; lbl_en.add_theme_font_size_override("font_size", 9); lbl_en.modulate.a = 0.7; wave_panel.add_child(lbl_en)
		
		for j in range(wave.enemies.size()):
			var enemy_cfg = wave.enemies[j]
			var hb_enemy = HBoxContainer.new(); hb_enemy.add_theme_constant_override("separation", 10); wave_panel.add_child(hb_enemy)
			
			var search_box = LineEdit.new(); search_box.placeholder_text = "Filtrar..."; search_box.custom_minimum_size.x = 80; hb_enemy.add_child(search_box)
			var opt = OptionButton.new(); opt.custom_minimum_size.x = 180; hb_enemy.add_child(opt)
			
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
				if not found_current and GameConstants.ENEMY_MODELS.has(str(enemy_cfg.type)):
					var e_data = GameConstants.ENEMY_MODELS[str(enemy_cfg.type)]
					opt.add_item("(*) " + e_data.name + " [" + str(enemy_cfg.type) + "]", int(enemy_cfg.type))
					opt.selected = opt.get_item_count() - 1

			_populate_opt.call("")
			search_box.text_changed.connect(_populate_opt)
			
			opt.item_selected.connect(func(index):
				var selected_id = str(opt.get_item_id(index))
				GameConstants.HORDES_CONFIG.waves[i].enemies[j].type = selected_id
			)
			
			admin_main._add_input(hb_enemy, "CANTIDAD", str(enemy_cfg.count), func(v): GameConstants.HORDES_CONFIG.waves[i].enemies[j].count = int(v))
			
			var btn_del_en = Button.new(); btn_del_en.text = "X"; btn_del_en.modulate = Color.ORANGE
			btn_del_en.pressed.connect(func(): 
				GameConstants.HORDES_CONFIG.waves[i].enemies.remove_at(j)
				admin_main._build_ui()
			)
			hb_enemy.add_child(btn_del_en)
		
		var btn_add_en = Button.new(); btn_add_en.text = " + AÑADIR TIPO DE ENEMIGO "; btn_add_en.flat = true; btn_add_en.modulate = Color.GREEN
		btn_add_en.pressed.connect(func(): 
			GameConstants.HORDES_CONFIG.waves[i].enemies.append({"type": "1", "count": 5})
			admin_main._build_ui()
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
		admin_main._build_ui()
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
