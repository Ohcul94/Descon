extends Node

var admin_main = null

func setup(main):
	admin_main = main

func render_zones(container):
	var lbl = Label.new(); lbl.text = "CONFIGURACIÓN DE ZONAS (MAPAS)"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	for z_id in GameConstants.MAPS_CONFIG:
		var zone = GameConstants.MAPS_CONFIG[z_id]
		var card = admin_main._create_card(container, "ZONA " + str(z_id) + " - " + zone.name.to_upper())
		var grid = admin_main._create_grid(card, 5)
		var z_ref = {"id": z_id}
		admin_main._add_input(grid, "NOMBRE", zone.name, func(v): GameConstants.MAPS_CONFIG[z_ref.id].name = v, true)
		admin_main._add_input(grid, "DESCRIPCIÓN", zone.desc, func(v): GameConstants.MAPS_CONFIG[z_ref.id].desc = v, true)
		admin_main._add_color_input(grid, "COLOR", zone.get("color", "#ffffff"), func(v): GameConstants.MAPS_CONFIG[z_ref.id].color = v.to_html())
		admin_main._add_input(grid, "COSTO DE WARP", str(zone.get("warpCost", 10)), func(v): GameConstants.MAPS_CONFIG[z_ref.id].warpCost = int(v))
		admin_main._add_input(grid, "NIVEL MÍNIMO", str(zone.get("minLevel", 1)), func(v): GameConstants.MAPS_CONFIG[z_ref.id].minLevel = int(v))

func render_spheres(container):
	var lbl = Label.new(); lbl.text = "CONFIGURACIÓN DE HABILIDADES DE ESFERAS"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	var sphere_tabs = TabContainer.new(); sphere_tabs.custom_minimum_size.y = 450; container.add_child(sphere_tabs)
	var categories = { "AZUL (Defensa)": ["Defensa", "Escudo"], "VERDE (Curación)": ["Curación", "Reparación"], "ROJO (Ataque)": ["Ataque", "Combat", "Daño"], "AMARILLO (Utilidad)": ["Utilidad", "Movimiento", "Velocidad"] }
	var tab_nodes = {}
	for cat_name in categories:
		var scroll = ScrollContainer.new(); scroll.name = cat_name; sphere_tabs.add_child(scroll)
		var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 10); scroll.add_child(vbox)
		tab_nodes[cat_name] = vbox

	for s_name in GameConstants.SKILLS_DATA:
		var skill = GameConstants.SKILLS_DATA[s_name]; var target_cat = ""
		for cat_name in categories:
			if skill.type in categories[cat_name]: target_cat = cat_name; break
		if target_cat == "": continue
		
		var card = admin_main._create_card(tab_nodes[target_cat], "ESFERA: " + s_name.to_upper())
		var header_hb = HBoxContainer.new(); card.add_child(header_hb); card.move_child(header_hb, 0)
		var k_ref = {"name": s_name}; var grid = admin_main._create_grid(card, 5)
		
		var name_hb = VBoxContainer.new(); grid.add_child(name_hb)
		var name_l = Label.new(); name_l.text = "NOMBRE"; name_l.add_theme_font_size_override("font_size", 9); name_l.modulate.a = 0.5; name_hb.add_child(name_l)
		var name_inp = LineEdit.new(); name_inp.text = s_name; name_inp.custom_minimum_size.x = 200; name_hb.add_child(name_inp)
		name_inp.text_changed.connect(func(v):
			if v == "" or v == k_ref.name: return
			var data = GameConstants.SKILLS_DATA[k_ref.name]; GameConstants.SKILLS_DATA.erase(k_ref.name); GameConstants.SKILLS_DATA[v] = data; k_ref.name = v
		)
		
		var type_hb = VBoxContainer.new(); grid.add_child(type_hb)
		var type_l = Label.new(); type_l.text = "TIPO"; type_l.add_theme_font_size_override("font_size", 9); type_l.modulate.a = 0.5; type_hb.add_child(type_l)
		var type_opt = OptionButton.new(); type_hb.add_child(type_opt)
		var types = ["Defensa", "Curación", "Ataque", "Utilidad"]
		for t in types:
			type_opt.add_item(t); if t == skill.type: type_opt.selected = type_opt.get_item_count() - 1
		type_opt.item_selected.connect(func(idx): GameConstants.SKILLS_DATA[k_ref.name].type = type_opt.get_item_text(idx))

		admin_main._add_input(grid, "COOLDOWN (S)", str(skill.get("cd", 10.0)), func(v): GameConstants.SKILLS_DATA[k_ref.name].cd = float(v))
		admin_main._add_input(grid, "RANGO", str(skill.get("range", 0)), func(v): GameConstants.SKILLS_DATA[k_ref.name].range = float(v))

		var target_hb = VBoxContainer.new(); grid.add_child(target_hb)
		var target_l = Label.new(); target_l.text = "PUEDE LANZARSE A OTROS"; target_l.add_theme_font_size_override("font_size", 9); target_l.modulate.a = 0.5; target_hb.add_child(target_l)
		var target_sw = CheckButton.new(); target_sw.text = "ACTIVADO"; target_sw.button_pressed = skill.get("canTargetOthers", false); target_hb.add_child(target_sw)
		
		var filters_vb = VBoxContainer.new(); filters_vb.visible = target_sw.button_pressed; grid.add_child(filters_vb)
		var filters_l = Label.new(); filters_l.text = "FILTROS DE OBJETIVO:"; filters_l.add_theme_font_size_override("font_size", 9); filters_l.modulate.a = 0.5; filters_vb.add_child(filters_l)
		var filters_grid = GridContainer.new(); filters_grid.columns = 2; filters_vb.add_child(filters_grid)
		var f_data = skill.get("targetFilters", {"allies": true, "enemies": false, "bosses": false, "players": true})
		var filter_labels = {"allies": "ALIADOS", "enemies": "ENEMIGOS", "bosses": "BOSSES", "players": "JUGADORES"}
		for f_key in filter_labels:
			var cb = CheckBox.new(); cb.text = filter_labels[f_key]; cb.button_pressed = f_data.get(f_key, false); cb.add_theme_font_size_override("font_size", 9); filters_grid.add_child(cb)
			cb.toggled.connect(func(v):
				if not GameConstants.SKILLS_DATA[k_ref.name].has("targetFilters"): GameConstants.SKILLS_DATA[k_ref.name]["targetFilters"] = {"allies": false, "enemies": false, "bosses": false, "players": false}
				GameConstants.SKILLS_DATA[k_ref.name]["targetFilters"][f_key] = v
			)
		target_sw.toggled.connect(func(v):
			GameConstants.SKILLS_DATA[k_ref.name].canTargetOthers = v; filters_vb.visible = v
			if v and not GameConstants.SKILLS_DATA[k_ref.name].has("targetFilters"): GameConstants.SKILLS_DATA[k_ref.name]["targetFilters"] = {"allies": true, "enemies": false, "bosses": false, "players": true}
		)

		var btn_del = Button.new(); btn_del.text = " ELIMINAR ESFERA "; btn_del.modulate = Color.RED; btn_del.size_flags_horizontal = Control.SIZE_SHRINK_END
		btn_del.pressed.connect(func(): GameConstants.SKILLS_DATA.erase(k_ref.name); admin_main._build_ui())
		grid.add_child(btn_del)
		
		if skill.has("amount"): admin_main._add_input(grid, "VALOR (HP/SH)", str(skill.amount), func(v): GameConstants.SKILLS_DATA[k_ref.name].amount = int(v))
		if skill.has("speed"): admin_main._add_input(grid, "VELOCIDAD", str(skill.speed), func(v): GameConstants.SKILLS_DATA[k_ref.name].speed = float(v))
		if skill.has("reflect_mult"): admin_main._add_input(grid, "MULT. DAÑO", str(skill.reflect_mult), func(v): GameConstants.SKILLS_DATA[k_ref.name].reflect_mult = float(v))
		if skill.has("duration"): admin_main._add_input(grid, "DURACIÓN (S)", str(skill.duration), func(v): GameConstants.SKILLS_DATA[k_ref.name].duration = float(v))
		if skill.has("slow_amount"): admin_main._add_input(grid, "PUNTOS DE SLOW (KM/H)", str(int(skill.slow_amount * 100)), func(v): GameConstants.SKILLS_DATA[k_ref.name].slow_amount = float(v) / 100.0)

	var add_btn = Button.new(); add_btn.text = " [+] AÑADIR NUEVA HABILIDAD / ESFERA "; add_btn.modulate = Color.CYAN
	add_btn.pressed.connect(func():
		var new_name = "NUEVA_ESFERA_" + str(GameConstants.SKILLS_DATA.size() + 1); GameConstants.SKILLS_DATA[new_name] = { "type": "Defensa", "cd": 15.0, "range": 0, "amount": 1000 }; admin_main._build_ui()
	)
	container.add_child(add_btn)

func render_map_selection(container):
	var lbl = Label.new(); lbl.text = "SISTEMA DE VISUALIZACIÓN Y NAVEGACIÓN"; lbl.modulate = Color.GOLD; container.add_child(lbl)
	var btn_open = Button.new(); btn_open.text = "ABRIR MONITOR TÁCTICO (MODAL)"; btn_open.custom_minimum_size = Vector2(0, 50); btn_open.modulate = Color.CYAN
	btn_open.pressed.connect(admin_main._on_open_map_pressed); container.add_child(btn_open)
	container.add_child(HSeparator.new())
	var warp_h = HBoxContainer.new(); warp_h.add_theme_constant_override("separation", 10); container.add_child(warp_h)
	for i in range(1, 10):
		var b = Button.new(); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "[ LOBY ]" if i == 1 else ("[ BOSS 1 MAP ]" if i == 9 else " SECTOR " + str(i-1) + " ")
		b.pressed.connect(func(): NetworkManager.send_event("warpToZone", {"zone": i}); admin_main.visible = false)
		warp_h.add_child(b)
	container.add_child(HSeparator.new())
	var btn_view = Button.new(); btn_view.text = "REFORZAR SCANNER DE LOOT (LIMPIEZA VISUAL)"; btn_view.custom_minimum_size = Vector2(0, 40)
	btn_view.pressed.connect(func(): 
		var world = get_tree().get_first_node_in_group("world_node")
		if world:
			for en_id in world.enemies.keys():
				var en = world.enemies[en_id]; if is_instance_valid(en): en.queue_free()
			world.enemies.clear()
	); container.add_child(btn_view)
