extends Control

# MapTab.gd - MÓDULO DE NAVEGACIÓN GALÁCTICA (v301.5)
# Lógica de sectores y mapa interactivo extraída de Inventory.gd.

var inv_main = null

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var tab = self
	for n in tab.get_children(): n.queue_free()
	
	var master_h = HBoxContainer.new(); master_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_h.add_theme_constant_override("separation", 20); tab.add_child(master_h)
	
	# Columna Izquierda: Lista de Sectores
	var l_col = VBoxContainer.new(); l_col.custom_minimum_size.x = 300; master_h.add_child(l_col)
	var l_title = Label.new(); l_title.text = " SECTORES CONOCIDOS"; l_title.modulate = Color.CYAN; l_title.add_theme_font_size_override("font_size", 11); l_col.add_child(l_title)
	
	var s_scroll = ScrollContainer.new(); s_scroll.size_flags_vertical = 3; l_col.add_child(s_scroll)
	s_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # v301.6: Evitar barra horizontal
	
	var s_list = VBoxContainer.new(); s_list.size_flags_horizontal = 3; s_scroll.add_child(s_list)
	
	var sectors = []
	for z_id in GameConstants.MAPS_CONFIG:
		var zone_data = GameConstants.MAPS_CONFIG[z_id]
		var sd = zone_data.duplicate()
		sd["id"] = int(z_id)
		if not sd.has("color"): sd["color"] = "#ffffff"
		sectors.append(sd)
		
	sectors.sort_custom(func(a, b): return a.id < b.id)
	
	var current_zone_id = 1
	var p_node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p_node) and "current_zone" in p_node:
		current_zone_id = p_node.current_zone
	
	var current_zone_name = "MAPA 1"

	for s in sectors:
		var is_current = (s.id == current_zone_id)
		if is_current: current_zone_name = s.name

		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(0, 70); s_list.add_child(p)
		
		var sb = StyleBoxFlat.new()
		if is_current:
			sb.bg_color = Color(1, 0.8, 0, 0.15)
			sb.border_width_left = 5
			sb.border_color = Color.GOLD
			sb.shadow_color = Color(1, 0.8, 0, 0.2)
			sb.shadow_size = 4
		else:
			sb.bg_color = Color(0,1,1,0.05)
			sb.border_width_left = 3
			sb.border_color = s.color
			
		p.add_theme_stylebox_override("panel", sb)
		
		var hb = HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); p.add_child(hb)
		
		# Margen interno izquierdo
		var spacer = Control.new(); spacer.custom_minimum_size.x = 5; hb.add_child(spacer)
		
		var v = VBoxContainer.new(); v.size_flags_horizontal = 3; hb.add_child(v); v.alignment = BoxContainer.ALIGNMENT_CENTER
		var n = Label.new(); n.text = s.name; n.add_theme_font_size_override("font_size", 11); v.add_child(n)
		if is_current: n.modulate = Color.GOLD
		
		var d = Label.new(); d.text = s.get("desc", ""); d.add_theme_font_size_override("font_size", 8); d.modulate.a = 0.6; v.add_child(d)
		
		if is_current:
			var st = Label.new(); st.text = "ESTÁS AQUÍ"
			st.modulate = Color.GOLD
			st.add_theme_font_size_override("font_size", 8); v.add_child(st)
		
		var cost = int(s.get("warpCost", 10))
		var min_level = int(s.get("minLevel", 1))
		var current_level = int(p_node.level) if is_instance_valid(p_node) and "level" in p_node else 1
		var can_enter = current_level >= min_level
		var btn_travel = Button.new()
		
		if not can_enter:
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
	
	# Columna Derecha: El Mapa Interactivo
	var r_col = VBoxContainer.new(); r_col.size_flags_horizontal = 3; master_h.add_child(r_col)
	var map_container = PanelContainer.new(); map_container.size_flags_vertical = 3; r_col.add_child(map_container)
	var msb = StyleBoxFlat.new(); msb.bg_color = Color(0,0,0,0.8); msb.set_border_width_all(1); msb.border_color = Color(0,1,1,0.2); map_container.add_theme_stylebox_override("panel", msb)
	
	var map_logic = Control.new()
	map_logic.name = "MapLogic"
	map_logic.size_flags_horizontal = 3
	map_logic.size_flags_vertical = 3
	map_logic.set_script(load("res://scripts/ui/AdminMap.gd"))
	map_logic.is_embedded = true
	map_logic.r_pos = Vector2(0, 0)
	map_logic.r_margin = Vector2(5, 5)
	map_container.add_child(map_logic)
	
	call_deferred("_setup_map_logic", current_zone_name)

func _setup_map_logic(zone_name = "MAPA 1"):
	var logic_node = find_child("MapLogic", true, false)
	if is_instance_valid(logic_node):
		logic_node.current_sector_name = zone_name
		logic_node.visible = true
		logic_node.custom_minimum_size = Vector2(400, 400)
		logic_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		logic_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		logic_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
