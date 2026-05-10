extends Control

# SpheresTab.gd - RESTAURACIÓN PREMIUM (v263.050)
# Estética orbital original restaurada con soporte modular.

var inv_main = null

func setup(p_inv_main):
	inv_main = p_inv_main

func update_ui():
	if not inv_main: return
	var root_tab = self
	
	var prev_idx = 0
	for child in root_tab.get_children():
		if child is TabContainer:
			prev_idx = child.current_tab
			break

	for n in root_tab.get_children(): n.queue_free()
	
	var sub_tabs = TabContainer.new()
	sub_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_tab.add_child(sub_tabs)
	
	var eq_tab = Control.new(); eq_tab.name = "SISTEMA ORBITAL"; sub_tabs.add_child(eq_tab)
	var lib_tab = Control.new(); lib_tab.name = "BIBLIOTECA DE HABILIDADES"; sub_tabs.add_child(lib_tab)
	
	sub_tabs.current_tab = prev_idx
	
	_render_spheres_equipment(eq_tab, sub_tabs)
	_render_spheres_library(lib_tab)

func _render_spheres_equipment(tab, _sub_tabs):
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_v.offset_top = 20; tab.add_child(master_v)
	var spheres_h = HBoxContainer.new(); spheres_h.alignment = BoxContainer.ALIGNMENT_CENTER; spheres_h.add_theme_constant_override("separation", 60); master_v.add_child(spheres_h)
	
	var sm = inv_main.spheres_manager
	if not is_instance_valid(sm):
		var err = Label.new(); err.text = "SISTEMA ORBITAL NO INICIALIZADO"; err.horizontal_alignment = 1; master_v.add_child(err)
		return

	for i in range(4):
		if i >= sm.spheres_data.size(): break
		var s_data = sm.spheres_data[i]
		var s_color = s_data.get("color", Color.WHITE)
		
		# Saneamiento de color (HEX/CSV)
		if typeof(s_color) == TYPE_STRING:
			var c_str = s_color.replace("(","").replace(")","").replace(" ","")
			if "," in c_str:
				var parts = c_str.split(",")
				if parts.size() >= 3:
					s_color = Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
			else: s_color = Color(c_str)
		
		var v_box = VBoxContainer.new(); spheres_h.add_child(v_box)
		var s_label = Label.new(); s_label.text = s_data["name"]; s_label.horizontal_alignment = 1; s_label.modulate = s_color; v_box.add_child(s_label)
		
		var p_ui = PanelContainer.new(); p_ui.custom_minimum_size = Vector2(140, 140); v_box.add_child(p_ui)
		p_ui.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; p_ui.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0,0,0,0.6); sb.border_width_left = 3; sb.border_width_right = 3; sb.border_width_top = 3; sb.border_width_bottom = 3; sb.border_color = s_color; sb.corner_radius_top_left = 70; sb.corner_radius_top_right = 70; sb.corner_radius_bottom_left = 70; sb.corner_radius_bottom_right = 70; p_ui.add_theme_stylebox_override("panel", sb)
		
		if not s_data.get("equipped"): sb.bg_color = s_color; sb.bg_color.a = 0.05
		
		var equipped = s_data.get("equipped")
		var center = CenterContainer.new(); p_ui.add_child(center)
		var info_v = VBoxContainer.new(); center.add_child(info_v)
		
		var s_name = "VACÍO"
		if equipped:
			if typeof(equipped) == TYPE_DICTIONARY: s_name = str(equipped.get("skill_name", "SKILL"))
			elif "skill_name" in equipped: s_name = str(equipped.skill_name)
		
		var name_lbl = Label.new(); name_lbl.text = s_name.to_upper(); name_lbl.horizontal_alignment = 1; name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.modulate.a = 1.0 if equipped else 0.3; info_v.add_child(name_lbl)
		
		if equipped:
			var p_val = 0
			if typeof(equipped) == TYPE_DICTIONARY: p_val = equipped.get("power_value", 0)
			elif "power_value" in equipped: p_val = equipped.power_value
			var pwr = Label.new(); pwr.text = "POT: " + str(p_val); pwr.add_theme_font_size_override("font_size", 9); pwr.modulate = s_color; pwr.horizontal_alignment = 1; info_v.add_child(pwr)
		
		var type_txt = s_data.get("type", "ATAQUE")
		var final_color = Color.SLATE_GRAY
		if equipped:
			final_color = s_color
			var raw_type = "ATAQUE"
			if typeof(equipped) == TYPE_DICTIONARY: raw_type = equipped.get("type", "ATAQUE")
			else: raw_type = equipped.type if "type" in equipped else "ATAQUE"
			type_txt = str(raw_type).to_upper()
			if type_txt == "ATAQUE": final_color = Color.RED
			elif type_txt == "DEFENSA": final_color = Color.AQUA
			elif type_txt in ["CURACIÓN", "CURACION"]: final_color = Color.GREEN
			elif type_txt in ["MOVIMIENTO", "UTILIDAD"]: final_color = Color.YELLOW
		else: type_txt = "NINGUNO"
		
		sb.border_color = final_color
		var type_label = Label.new(); type_label.text = type_txt; type_label.modulate = final_color; type_label.horizontal_alignment = 1; type_label.add_theme_font_size_override("font_size", 9); v_box.add_child(type_label)
		
		var b = Button.new(); b.text = "RECONFIGURAR" if equipped else "EQUIPAR NÚCLEO"; b.add_theme_font_size_override("font_size", 9); v_box.add_child(b)
		b.pressed.connect(func():
			inv_main.selected_sphere_slot = i
			inv_main.selected_sphere_type_filter = "ANY"
			if equipped: inv_main.selected_sphere_type_filter = type_txt
			# Si fuera necesario cambiar a la pestaña 1 (Biblioteca)
			# _sub_tabs.current_tab = 1
		)
		
		if equipped:
			var bu = Button.new(); bu.text = "DESEQUIPAR"; bu.add_theme_font_size_override("font_size", 9); bu.modulate = Color(1, 0.4, 0.4); v_box.add_child(bu)
			bu.pressed.connect(func(): NetworkManager.send_event("unequipSphere", {"sphereId": i}))
		
		p_ui.gui_input.connect(func(ev): 
			if ev is InputEventMouseButton and ev.pressed: inv_main.selected_sphere_slot = i; update_ui()
		)

func _render_spheres_library(tab):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); main_v.offset_left = 20; main_v.offset_right = -20; main_v.offset_top = 20; tab.add_child(main_v)
	
	var filter_h = HBoxContainer.new(); filter_h.alignment = BoxContainer.ALIGNMENT_CENTER; filter_h.add_theme_constant_override("separation", 15); main_v.add_child(filter_h)
	var filters = ["ANY", "ATAQUE", "DEFENSA", "CURACIÓN", "UTILIDAD"]
	for f in filters:
		var fb = Button.new(); fb.text = " " + f + " "; fb.flat = (inv_main.selected_sphere_type_filter != f)
		fb.add_theme_font_size_override("font_size", 10)
		if f == "ATAQUE": fb.modulate = Color.RED
		elif f == "DEFENSA": fb.modulate = Color.AQUA
		elif f == "CURACIÓN": fb.modulate = Color.GREEN
		elif f == "UTILIDAD": fb.modulate = Color.YELLOW
		fb.pressed.connect(func(): inv_main.selected_sphere_type_filter = f; update_ui())
		filter_h.add_child(fb)
	
	main_v.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var grid = GridContainer.new(); grid.columns = 2; grid.size_flags_horizontal = 3; grid.add_theme_constant_override("h_separation", 20); grid.add_theme_constant_override("v_separation", 20); scroll.add_child(grid)
	
	var all_skills = [
		{"class": Skill_TurboImpulse, "color": Color.YELLOW, "icon": "⚡", "type": "UTILIDAD"},
		{"class": Skill_HyperDash, "color": Color.YELLOW, "icon": "💨", "type": "UTILIDAD"},
		{"class": Skill_Invulnerability, "color": Color.YELLOW, "icon": "🛡️", "type": "UTILIDAD"},
		{"class": Skill_Blink, "color": Color.YELLOW, "icon": "✨", "type": "UTILIDAD"},
		{"class": Skill_Stealth, "color": Color.YELLOW, "icon": "👻", "type": "UTILIDAD"},
		{"class": Skill_ShieldCell, "color": Color.AQUA, "icon": "🛡️", "type": "DEFENSA"},
		{"class": Skill_Fortress, "color": Color.AQUA, "icon": "🏰", "type": "DEFENSA"},
		{"class": Skill_FrostTrail, "color": Color.AQUA, "icon": "❄️", "type": "DEFENSA"},
		{"class": Skill_SmokeBomb, "color": Color.AQUA, "icon": "☁️", "type": "DEFENSA"},
		{"class": Skill_RepairKit, "color": Color.GREEN, "icon": "🔧", "type": "CURACIÓN"},
		{"class": Skill_RegenPath, "color": Color.GREEN, "icon": "🧪", "type": "CURACIÓN"},
		{"class": Skill_Reflect, "color": Color.RED, "icon": "🛡️", "type": "ATAQUE"},
		{"class": Skill_PlasmaBlast, "color": Color.RED, "icon": "💥", "type": "ATAQUE"}
	]
	
	var currently_equipped = []
	if is_instance_valid(inv_main.spheres_manager):
		for s in inv_main.spheres_manager.spheres_data:
			var eq = s.get("equipped")
			if eq: currently_equipped.append(eq.get("skill_name") if typeof(eq) == TYPE_DICTIONARY else eq.skill_name)

	for s_info in all_skills:
		if inv_main.selected_sphere_type_filter != "ANY" and s_info["type"] != inv_main.selected_sphere_type_filter: continue
		var s_inst = s_info["class"].new()
		var is_already_on = s_inst.skill_name in currently_equipped
		_create_skill_card(s_inst, s_info["color"], s_info["icon"], grid, is_already_on)

func _create_skill_card(skill, color, icon_text, parent, is_equipped):
	var skill_card = PanelContainer.new(); skill_card.custom_minimum_size = Vector2(350, 120); parent.add_child(skill_card)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0.05, 0.7); sb.border_width_left = 4; sb.border_color = color; sb.corner_radius_top_right = 8; sb.corner_radius_bottom_right = 8; skill_card.add_theme_stylebox_override("panel", sb)
	
	var hb = HBoxContainer.new(); hb.offset_left = 15; skill_card.add_child(hb)
	var icon_box = CenterContainer.new(); icon_box.custom_minimum_size = Vector2(60, 0); hb.add_child(icon_box)
	var ico = Label.new(); ico.text = icon_text; ico.add_theme_font_size_override("font_size", 30); ico.modulate = color; icon_box.add_child(ico)
	
	var v_info = VBoxContainer.new(); v_info.size_flags_horizontal = 3; v_info.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_child(v_info)
	var name_l = Label.new(); name_l.text = skill.skill_name; name_l.add_theme_font_size_override("font_size", 14); name_l.modulate = color; v_info.add_child(name_l)
	var desc_l = Label.new(); desc_l.text = skill.description; desc_l.add_theme_font_size_override("font_size", 10); desc_l.modulate.a = 0.6; desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v_info.add_child(desc_l)
	
	var b_equip = Button.new(); b_equip.text = "YA EQUIPADA" if is_equipped else "EQUIPAR"; b_equip.disabled = is_equipped; b_equip.custom_minimum_size = Vector2(80, 0); b_equip.size_flags_vertical = 4; hb.add_child(b_equip)
	if is_equipped: skill_card.modulate.a = 0.5
	
	b_equip.pressed.connect(func():
		var target_idx = inv_main.selected_sphere_slot
		if target_idx == -1 and is_instance_valid(inv_main.spheres_manager):
			for i in range(4):
				if inv_main.spheres_manager.spheres_data[i]["equipped"] == null: target_idx = i; break
		if target_idx != -1:
			NetworkManager.send_event("equipSphere", {"sphereId": target_idx, "skill": {"skill_name": skill.skill_name, "power_value": skill.power_value, "type": skill.type}})
			if is_instance_valid(inv_main.spheres_manager): inv_main.spheres_manager.equip_item(target_idx, skill)
			update_ui()
	)
