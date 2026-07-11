extends Control

# SpheresTab.gd - RESTAURACIÓN ESTÉTICA PREMIUM (v301.4 - Skill Icons)
# Recuperada la estética orbital original con corrección de carga de habilidades.
# v301.4: Soporte para íconos PNG desde el servidor (skillsData[name].icon)

var inv_main = null
var _preloaded_skills: Array = []
var _texture_cache: Dictionary = {}
var _has_preloaded: bool = false

func _get_color_from_skill_type(skill_type: String) -> Color:
	match skill_type.to_upper():
		"ATAQUE": return Color.RED
		"DEFENSA": return Color.AQUA
		"CURACIÓN", "CURACION": return Color.GREEN
		"MOVIMIENTO", "UTILIDAD": return Color.YELLOW
		_: return Color.SLATE_GRAY

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

	for n in root_tab.get_children(): 
		root_tab.remove_child(n)
		n.queue_free()
	
	var sub_tabs = TabContainer.new()
	sub_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_tab.add_child(sub_tabs)
	
	var eq_tab = Control.new(); eq_tab.name = "SISTEMA ORBITAL"; sub_tabs.add_child(eq_tab)
	var lib_tab = Control.new(); lib_tab.name = "BIBLIOTECA DE HABILIDADES"; sub_tabs.add_child(lib_tab)
	
	sub_tabs.current_tab = prev_idx
	
	_render_spheres_equipment(eq_tab, sub_tabs)
	_render_spheres_library(lib_tab)

func _preload_resources_once():
	if _has_preloaded: return
	_preloaded_skills.clear()
	
	var skill_configs = [
		{"path": "res://scripts/resources/skills/Skill_TurboImpulse.gd", "icon": "⚡"},
		{"path": "res://scripts/resources/skills/Skill_HyperDash.gd", "icon": "💨"},
		{"path": "res://scripts/resources/skills/Skill_Invulnerability.gd", "icon": "🛡️"},
		{"path": "res://scripts/resources/skills/Skill_Blink.gd", "icon": "✨"},
		{"path": "res://scripts/resources/skills/Skill_Resurreccion.gd", "icon": "🕊️"},
		{"path": "res://scripts/resources/skills/Skill_Stealth.gd", "icon": "👻"},
		{"path": "res://scripts/resources/skills/Skill_ShieldCell.gd", "icon": "🛡️"},
		{"path": "res://scripts/resources/skills/Skill_FrostTrail.gd", "icon": "❄️"},
		{"path": "res://scripts/resources/skills/Skill_SmokeBomb.gd", "icon": "☁️"},
		{"path": "res://scripts/resources/skills/Skill_WindBarrier.gd", "icon": "🌀"},
		{"path": "res://scripts/resources/skills/Skill_Provocacion.gd", "icon": "😡"},
		{"path": "res://scripts/resources/skills/Skill_RepairKit.gd", "icon": "🔧"},
		{"path": "res://scripts/resources/skills/Skill_RegenPath.gd", "icon": "🧪"},
		{"path": "res://scripts/resources/skills/Skill_AlphaRegen.gd", "icon": "💚"},
		{"path": "res://scripts/resources/skills/Skill_VitalLink.gd", "icon": "🔗"},
		{"path": "res://scripts/resources/skills/Skill_HealBeacon.gd", "icon": "📡"},
		{"path": "res://scripts/resources/skills/Skill_Reflect.gd", "icon": "🛡️"},
		{"path": "res://scripts/resources/skills/Skill_FearSphere.gd", "icon": "💀"}
	]
	
	for cfg in skill_configs:
		if ResourceLoader.exists(cfg["path"]):
			var script = load(cfg["path"])
			if script:
				var s_inst = script.new()
				var s_name = s_inst.skill_name
				var s_type = s_inst.get("type") if "type" in s_inst else "ATAQUE"
				
				# Cargar textura si existe
				var tex_icon: Texture2D = _load_skill_icon_texture(s_name)
				
				_preloaded_skills.append({
					"instance": s_inst,
					"name": s_name,
					"icon_text": cfg["icon"],
					"tex_icon": tex_icon,
					"default_type": s_type
				})
	_has_preloaded = true

# v301.4: Intenta cargar textura desde ruta res:// del servidor (Optimizado con Caché)
func _load_skill_icon_texture(skill_name: String) -> Texture2D:
	var clean_name = skill_name.to_upper().strip_edges()
	if _texture_cache.has(clean_name):
		return _texture_cache[clean_name]
		
	var server_skills = {}
	if NetworkManager and NetworkManager.server_config:
		server_skills = NetworkManager.server_config.get("skillsData", {})
		
	var lookup_key = clean_name
	if "REFLECT" in clean_name:
		for key in server_skills.keys():
			if "REFLECT" in key.to_upper():
				lookup_key = key
				break
	
	if not server_skills.has(lookup_key):
		_texture_cache[clean_name] = null
		return null
		
	var icon_path = server_skills[lookup_key].get("icon", "")
	if icon_path == "" or not icon_path.ends_with(".png"):
		_texture_cache[clean_name] = null
		return null
		
	if ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		_texture_cache[clean_name] = tex
		return tex
		
	_texture_cache[clean_name] = null
	return null

func _render_spheres_equipment(tab, _sub_tabs):
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_v.offset_top = 20; tab.add_child(master_v)
	
	var sm = inv_main.spheres_manager
	if not is_instance_valid(sm):
		var err = Label.new(); err.text = "SISTEMA ORBITAL NO INICIALIZADO"; err.horizontal_alignment = 1; master_v.add_child(err)
		return

	var player_node = get_tree().get_first_node_in_group("player")
	var is_comb = player_node and player_node.has_method("is_in_combat") and player_node.is_in_combat()
	
	if is_comb:
		var warning_lbl = Label.new()
		warning_lbl.text = "⚠️ SISTEMA BLOQUEADO: EN COMBATE"
		warning_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning_lbl.modulate = Color.RED
		warning_lbl.add_theme_font_size_override("font_size", 12)
		master_v.add_child(warning_lbl)
		
		var sep = Control.new()
		sep.custom_minimum_size = Vector2(0, 10)
		master_v.add_child(sep)

	var spheres_h = HBoxContainer.new(); spheres_h.alignment = BoxContainer.ALIGNMENT_CENTER; spheres_h.add_theme_constant_override("separation", 60); master_v.add_child(spheres_h)

	for i in range(4):
		if i >= sm.spheres_data.size(): break
		var s_data = sm.spheres_data[i]
		var s_color = s_data.get("color", Color.WHITE)
		
		if typeof(s_color) == TYPE_STRING:
			var c_str = s_color.replace("(","").replace(")","").replace(" ","")
			if "," in c_str:
				var parts = c_str.split(",")
				if parts.size() >= 3:
					s_color = Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
			else: s_color = Color(c_str)
		
		var v_box = VBoxContainer.new(); spheres_h.add_child(v_box)
		var s_label = Label.new(); s_label.text = s_data["name"]; s_label.horizontal_alignment = 1; s_label.modulate = s_color; v_box.add_child(s_label)
		
		var p_ui = PanelContainer.new(); p_ui.custom_minimum_size = Vector2(180, 180); v_box.add_child(p_ui)
		p_ui.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; p_ui.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.05, 0.08, 0.6); sb.border_width_left = 2; sb.border_width_right = 2; sb.border_width_top = 2; sb.border_width_bottom = 2; sb.border_color = s_color; sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12; sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12; p_ui.add_theme_stylebox_override("panel", sb)
		
		if not s_data.get("equipped"): sb.bg_color = s_color; sb.bg_color.a = 0.05
		
		var equipped = s_data.get("equipped")
		var center = CenterContainer.new(); p_ui.add_child(center)
		var info_v = VBoxContainer.new(); info_v.alignment = BoxContainer.ALIGNMENT_CENTER; center.add_child(info_v)
		
		var s_name = "VACÍO"
		if equipped:
			if typeof(equipped) == TYPE_DICTIONARY: s_name = str(equipped.get("skill_name", "SKILL"))
			elif "skill_name" in equipped: s_name = str(equipped.skill_name)
		
		var type_txt = s_data.get("type", "ATAQUE")
		var final_color = Color.SLATE_GRAY
		if equipped:
			final_color = s_color
			var raw_type = "ATAQUE"
			if typeof(equipped) == TYPE_DICTIONARY: raw_type = equipped.get("type", "ATAQUE")
			else: raw_type = equipped.type if "type" in equipped else "ATAQUE"
			type_txt = str(raw_type).to_upper(); final_color = _get_color_from_skill_type(type_txt)
		else: type_txt = "NINGUNO"
		
		sb.border_color = final_color
		
		# v301.4: Mostrar ícono PNG de la habilidad equipada dentro de la esfera (Tamaño triple: 160x160)
		var has_custom_icon = false
		if equipped and s_name != "VACÍO":
			var tex = _load_skill_icon_texture(s_name)
			if tex:
				has_custom_icon = true
				var icon_rect = TextureRect.new()
				icon_rect.texture = tex
				icon_rect.custom_minimum_size = Vector2(160, 160)
				icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				icon_rect.modulate = final_color
				info_v.add_child(icon_rect)
				
		# Si tiene ícono personalizado, removemos los bordes y el fondo del recuadro
		if has_custom_icon:
			sb.bg_color = Color(0,0,0,0)
			sb.border_width_left = 0; sb.border_width_right = 0; sb.border_width_top = 0; sb.border_width_bottom = 0
		
		var display_name = s_name
		if s_name != "VACÍO" and NetworkManager and NetworkManager.server_config:
			var server_skills = NetworkManager.server_config.get("skillsData", {})
			var lookup_name = s_name.to_upper().strip_edges()
			if "REFLECT" in lookup_name:
				for key in server_skills.keys():
					if "REFLECT" in key.to_upper():
						lookup_name = key
						break
			if server_skills.has(lookup_name):
				display_name = server_skills[lookup_name].get("name", server_skills[lookup_name].get("label", s_name))
		
		var name_lbl = Label.new(); name_lbl.text = display_name.to_upper(); name_lbl.horizontal_alignment = 1; name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.modulate = final_color if equipped else Color(1, 1, 1, 0.3); info_v.add_child(name_lbl)
		
		var type_label = Label.new(); type_label.text = type_txt; type_label.modulate = final_color; type_label.horizontal_alignment = 1; type_label.add_theme_font_size_override("font_size", 9); v_box.add_child(type_label)
		
		var b = Button.new(); b.text = "RECONFIGURAR" if equipped else "EQUIPAR NÚCLEO"; b.add_theme_font_size_override("font_size", 9); v_box.add_child(b)
		if is_comb:
			b.disabled = true
		else:
			b.pressed.connect(func():
				inv_main.selected_sphere_slot = i
				inv_main.selected_sphere_type_filter = "ANY"
				if equipped: inv_main.selected_sphere_type_filter = type_txt
				
				# v301.6: Búsqueda segura del TabContainer (Fix: Reconfigurar no hacía nada)
				for child in get_children():
					if child is TabContainer:
						child.current_tab = 1
						break
				update_ui()
			)
		
		if equipped:
			var bu = Button.new(); bu.text = "DESEQUIPAR"; bu.add_theme_font_size_override("font_size", 9); bu.modulate = Color(1, 0.4, 0.4); v_box.add_child(bu)
			if is_comb:
				bu.disabled = true
			else:
				bu.pressed.connect(func(): NetworkManager.send_event("unequipSphere", {"sphereId": i}))
		
		# v301.5: Interacción de equipamiento (Click en el slot para confirmar)
		p_ui.gui_input.connect(func(ev): 
			if ev is InputEventMouseButton and ev.pressed:
				if is_comb: return
				if inv_main.get("pending_skill_to_equip") != null:
					# Confirmar equipamiento
					var skill = inv_main.pending_skill_to_equip
					NetworkManager.send_event("equipSphere", {"sphereId": i, "skill": {"skill_name": skill.skill_name, "power_value": skill.power_value, "type": skill.type}})
					if is_instance_valid(inv_main.spheres_manager): inv_main.spheres_manager.equip_item(i, skill)
					inv_main.pending_skill_to_equip = null
					update_ui()
				else:
					inv_main.selected_sphere_slot = i; update_ui()
		)
		
		# v301.5: Efecto visual de "Esperando Selección"
		if inv_main.get("pending_skill_to_equip") != null:
			var tween = create_tween().set_loops()
			if is_instance_valid(sb):
				tween.tween_property(sb, "border_color", Color.WHITE, 0.4)
				tween.tween_property(sb, "border_color", final_color, 0.4)


func _render_spheres_library(tab):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); main_v.offset_left = 20; main_v.offset_right = -20; main_v.offset_top = 20; tab.add_child(main_v)
	
	var player_node = get_tree().get_first_node_in_group("player")
	var is_comb = player_node and player_node.has_method("is_in_combat") and player_node.is_in_combat()
	
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
	
	# v301.3: Carga segura y optimizada con pre-caché de recursos (Estilo AAA)
	_preload_resources_once()
	
	var all_skills = []
	var server_skills = {}
	if NetworkManager and NetworkManager.server_config:
		server_skills = NetworkManager.server_config.get("skillsData", {})
		
	for skill_info in _preloaded_skills:
		var s_inst = skill_info["instance"]
		var s_name = skill_info["name"]
		var s_type = skill_info["default_type"]
		
		# DINAMISMO AAA: Si el servidor tiene info de esta skill, la usamos por encima del script local
		if server_skills.has(s_name):
			s_type = server_skills[s_name].get("type", s_type)
			
		all_skills.append({
			"instance": s_inst,
			"color": _get_color_from_skill_type(s_type),
			"icon": skill_info["icon_text"],
			"tex_icon": skill_info["tex_icon"],
			"type": s_type.to_upper()
		})

	var currently_equipped = []
	if is_instance_valid(inv_main.spheres_manager):
		for s in inv_main.spheres_manager.spheres_data:
			var eq = s.get("equipped")
			if eq: currently_equipped.append(eq.get("skill_name") if typeof(eq) == TYPE_DICTIONARY else eq.skill_name)

	for s_info in all_skills:
		if inv_main.selected_sphere_type_filter != "ANY" and s_info["type"].to_upper() != inv_main.selected_sphere_type_filter: continue
		var s_inst = s_info["instance"]
		var is_already_on = s_inst.skill_name in currently_equipped
		_create_skill_card(s_inst, s_info["color"], s_info["icon"], s_info.get("tex_icon"), grid, is_already_on, is_comb)

func _create_skill_card(skill, color, icon_text, tex_icon: Texture2D, parent, is_equipped, is_comb = false):
	var skill_card = PanelContainer.new(); skill_card.custom_minimum_size = Vector2(350, 120); parent.add_child(skill_card)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0.05, 0.7); sb.border_width_left = 4; sb.border_color = color; sb.corner_radius_top_right = 8; sb.corner_radius_bottom_right = 8; skill_card.add_theme_stylebox_override("panel", sb)
	
	var hb = HBoxContainer.new(); hb.offset_left = 15; skill_card.add_child(hb)
	var icon_box = CenterContainer.new(); icon_box.custom_minimum_size = Vector2(60, 0); hb.add_child(icon_box)
	
	# v301.4: Mostrar TextureRect con PNG si existe, sino Label con emoji como fallback
	if tex_icon:
		var icon_rect = TextureRect.new()
		icon_rect.texture = tex_icon
		icon_rect.custom_minimum_size = Vector2(48, 48)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.modulate = color
		icon_box.add_child(icon_rect)
	else:
		var ico = Label.new(); ico.text = icon_text; ico.add_theme_font_size_override("font_size", 30); ico.modulate = color; icon_box.add_child(ico)
	
	var s_name = skill.skill_name
	var display_name = s_name
	var description_text = skill.description
	
	if NetworkManager and NetworkManager.server_config:
		var server_skills = NetworkManager.server_config.get("skillsData", {})
		var lookup_name = s_name.to_upper().strip_edges()
		if "REFLECT" in lookup_name:
			for key in server_skills.keys():
				if "REFLECT" in key.to_upper():
					lookup_name = key
					break
		if server_skills.has(lookup_name):
			var s_data = server_skills[lookup_name]
			display_name = s_data.get("name", s_data.get("label", s_name))
			description_text = s_data.get("desc", description_text)

	var v_info = VBoxContainer.new(); v_info.size_flags_horizontal = 3; v_info.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_child(v_info)
	var name_l = Label.new(); name_l.text = display_name; name_l.add_theme_font_size_override("font_size", 14); name_l.modulate = color; v_info.add_child(name_l)
	var desc_l = Label.new(); desc_l.text = description_text; desc_l.add_theme_font_size_override("font_size", 10); desc_l.modulate.a = 0.6; desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v_info.add_child(desc_l)
	
	var b_equip = Button.new(); b_equip.text = "YA EQUIPADA" if is_equipped else "EQUIPAR"; b_equip.disabled = is_equipped or is_comb; b_equip.custom_minimum_size = Vector2(80, 0); b_equip.size_flags_vertical = 4; hb.add_child(b_equip)
	if is_equipped: skill_card.modulate.a = 0.5
	elif is_comb: skill_card.modulate.a = 0.6
	
	b_equip.pressed.connect(func():
		# v301.5: Flujo de selección manual de slot
		inv_main.pending_skill_to_equip = skill
		inv_main.selected_sphere_type_filter = skill.type
		
		# v301.6: Búsqueda segura del TabContainer (Evitar error de scope)
		for child in get_children():
			if child is TabContainer:
				child.current_tab = 0
				break
		update_ui()
	)
