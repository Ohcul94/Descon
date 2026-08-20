extends Control

# SpheresTab.gd - RESTAURACIÓN ESTÉTICA PREMIUM (v301.4 - Skill Icons)
# v760.0: REWORK ESFERAS CRAFTEABLES
#   - Las esferas ya no se equipan directo: son ítems crafteados que se INSTALAN en los slots (máx 4).
#   - Sin esfera instalada no se puede equipar ninguna habilidad.
#   - La skill debe coincidir con el color de la esfera instalada:
#     Roja→ATAQUE | Azul→DEFENSA | Verde→CURACIÓN | Amarilla→UTILIDAD/MOVIMIENTO.
#   - 3 sub-pestañas: SISTEMA ORBITAL (slots) | MIS ESFERAS (inventario) | BIBLIOTECA DE HABILIDADES.

var inv_main = null
var _preloaded_skills: Array = []
var _texture_cache: Dictionary = {}
var _has_preloaded: bool = false

const SUB_TAB_ORBITAL: int = 0
const SUB_TAB_MIS_ESFERAS: int = 1
const SUB_TAB_BIBLIOTECA: int = 2

func _get_color_from_skill_type(skill_type: String) -> Color:
	match skill_type.to_upper():
		"ATAQUE": return Color.RED
		"DEFENSA": return Color.AQUA
		"CURACIÓN", "CURACION": return Color.GREEN
		"MOVIMIENTO", "UTILIDAD": return Color.YELLOW
		_: return Color.SLATE_GRAY

# ============================================================
# v760.0: HELPERS DE ESFERAS FÍSICAS (colores)
# ============================================================

# Clave de color de la esfera instalada en un slot ("roja"/"azul"/"verde"/"amarilla"/"")
func _sphere_color_key(slot_data) -> String:
	if typeof(slot_data) != TYPE_DICTIONARY: return ""
	var sp = slot_data.get("sphere")
	if sp == null or typeof(sp) != TYPE_DICTIONARY: return ""
	var c: String = str(sp.get("type", sp.get("sphereColor", ""))).to_lower()
	match c:
		"roja", "red": return "roja"
		"azul", "blue": return "azul"
		"verde", "green": return "verde"
		"amarilla", "amarillo", "yellow": return "amarilla"
	return ""

func _sphere_color_name(key: String) -> String:
	match key:
		"roja": return "Roja"
		"azul": return "Azul"
		"verde": return "Verde"
		"amarilla": return "Amarilla"
	return ""

func _sphere_color_of_item(item) -> String:
	if typeof(item) != TYPE_DICTIONARY: return ""
	var sc: String = str(item.get("sphereColor", "")).to_lower()
	if sc != "": return sc
	var iid: String = str(item.get("id", "")).to_lower()
	if iid == "esfera_roja": return "roja"
	if iid == "esfera_azul": return "azul"
	if iid == "esfera_verde": return "verde"
	if iid == "esfera_amarilla": return "amarilla"
	return ""

# Color de esfera requerido por un tipo de skill
func _sphere_color_for_type(skill_type: String) -> String:
	var t: String = skill_type.to_lower()
	t = t.replace("ó", "o").replace("é", "e").replace("í", "i").replace("á", "a").replace("ú", "u").replace("ü", "u")
	if t == "ataque": return "roja"
	if t == "defensa": return "azul"
	if t == "curacion": return "verde"
	return "amarilla"

func _color_to_rgb(key: String) -> Color:
	match key:
		"roja": return Color(0.9, 0.35, 0.3)
		"azul": return Color(0.3, 0.65, 0.9)
		"verde": return Color(0.35, 0.85, 0.4)
		"amarilla": return Color(0.95, 0.9, 0.35)
	return Color.WHITE

func _color_label(key: String) -> String:
	match key:
		"roja": return "ROJA"
		"azul": return "AZUL"
		"verde": return "VERDE"
		"amarilla": return "AMARILLA"
	return ""

func _type_label_for_sphere(key: String) -> String:
	match key:
		"roja": return "ATAQUE"
		"azul": return "DEFENSA"
		"verde": return "CURACIÓN"
		_: return "UTILIDAD / MOVIMIENTO"

func _sphere_icon_path(key: String) -> String:
	var cn: String = _sphere_color_name(key)
	if cn == "": return ""
	return "res://assets/Esferas/Esfera" + cn + "1.png"

# Ítems de esfera que el jugador tiene en su inventario (bodega)
func _get_owned_spheres() -> Array:
	var owned: Array = []
	if inv_main == null: return owned
	for item in inv_main.inventory_items:
		if typeof(item) != TYPE_DICTIONARY: continue
		if _sphere_color_of_item(item) != "":
			owned.append(item)
	return owned

func _count_installed_by_color() -> Dictionary:
	var counts := {}
	var sm = inv_main.spheres_manager if inv_main else null
	if is_instance_valid(sm):
		for s in sm.spheres_data:
			var key: String = _sphere_color_key(s)
			if key != "":
				counts[key] = int(counts.get(key, 0)) + 1
	return counts

func _count_owned_by_color() -> Dictionary:
	var counts := {}
	for item in _get_owned_spheres():
		var key: String = _sphere_color_of_item(item)
		if key != "":
			counts[key] = int(counts.get(key, 0)) + 1
	return counts

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
	var own_tab = Control.new(); own_tab.name = "MIS ESFERAS"; sub_tabs.add_child(own_tab)
	var lib_tab = Control.new(); lib_tab.name = "BIBLIOTECA DE HABILIDADES"; sub_tabs.add_child(lib_tab)
	
	sub_tabs.current_tab = prev_idx
	
	_render_spheres_equipment(eq_tab, sub_tabs)
	_render_owned_spheres(own_tab, sub_tabs)
	_render_spheres_library(lib_tab, sub_tabs)

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

func _switch_subtab(sub_tabs, idx: int):
	if sub_tabs:
		sub_tabs.current_tab = idx
	update_ui()

# ============================================================
# SUB-TAB 1: SISTEMA ORBITAL (los 4 slots)
# ============================================================
func _render_spheres_equipment(tab, sub_tabs):
	var master_v = VBoxContainer.new(); master_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); master_v.offset_top = 20; tab.add_child(master_v)
	
	var sm = inv_main.spheres_manager
	if not is_instance_valid(sm):
		var err = Label.new(); err.text = "SISTEMA ORBITAL NO INICIALIZADO"; err.horizontal_alignment = 1; master_v.add_child(err)
		return

	var player_node = get_tree().get_first_node_in_group("player")
	var is_comb = player_node and player_node.has_method("is_in_combat") and player_node.is_in_combat()
	
	# v760.0: Resumen de esferas instaladas
	var installed_total = 0
	for i in range(min(sm.spheres_data.size(), 4)):
		if sm.has_installed_sphere(i): installed_total += 1
	var summary = Label.new()
	summary.text = "ESFERAS INSTALADAS: %d / 4" % installed_total
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.modulate = Color.CYAN if installed_total > 0 else Color(1, 1, 1, 0.4)
	summary.add_theme_font_size_override("font_size", 11)
	master_v.add_child(summary)
	
	# v760.0: Banner de selección de esfera (flujo instalación desde un slot)
	if inv_main.get("pending_sphere_slot") != null and int(inv_main.pending_sphere_slot) >= 0:
		var banner = Label.new()
		banner.text = "➡️ SELECCIONÁ UNA ESFERA EN 'MIS ESFERAS' PARA EL " + str(sm.spheres_data[inv_main.pending_sphere_slot].get("name", "SLOT")).to_upper()
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.modulate = Color.YELLOW
		banner.add_theme_font_size_override("font_size", 10)
		master_v.add_child(banner)
		var cancel_b = Button.new(); cancel_b.text = "CANCELAR SELECCIÓN"; cancel_b.add_theme_font_size_override("font_size", 9)
		cancel_b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cancel_b.pressed.connect(func(): inv_main.pending_sphere_slot = -1; update_ui())
		master_v.add_child(cancel_b)
	
	# v760.0: Banner de confirmación de instalación (flujo desde MIS ESFERAS)
	if inv_main.get("pending_sphere_item") != null:
		var banner2 = Label.new()
		banner2.text = "➡️ CLICK EN UN SLOT VACÍO PARA INSTALAR LA ESFERA SELECCIONADA"
		banner2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner2.modulate = Color.YELLOW
		banner2.add_theme_font_size_override("font_size", 10)
		master_v.add_child(banner2)
		var cancel_b2 = Button.new(); cancel_b2.text = "CANCELAR SELECCIÓN"; cancel_b2.add_theme_font_size_override("font_size", 9)
		cancel_b2.pressed.connect(func(): inv_main.pending_sphere_item = null; update_ui())
		master_v.add_child(cancel_b2)
	
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

	var spheres_h = HBoxContainer.new(); spheres_h.alignment = BoxContainer.ALIGNMENT_CENTER; spheres_h.add_theme_constant_override("separation", 30); master_v.add_child(spheres_h)

	for i in range(4):
		if i >= sm.spheres_data.size(): break
		var s_data = sm.spheres_data[i]
		var s_color = s_data.get("color", Color.WHITE)
		var sphere_key: String = _sphere_color_key(s_data)
		var has_sphere = sm.has_installed_sphere(i)
		var equipped = s_data.get("equipped")
		var installed_sp = s_data.get("sphere")
		
		if typeof(s_color) == TYPE_STRING:
			var c_str = s_color.replace("(","").replace(")","").replace(" ","")
			if "," in c_str:
				var parts = c_str.split(",")
				if parts.size() >= 3:
					s_color = Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
			else: s_color = Color(c_str)
		
		# v680.0: Desbloqueo de slots de esferas por requisitos (validación local UX; el servidor es autoritativo)
		var slot_check := {"ok": true, "msg": ""}
		if NetworkManager:
			slot_check = NetworkManager.check_sphere_slot_requirements(i)
		var slot_locked: bool = not slot_check.get("ok", true)
		var slot_req_msg: String = str(slot_check.get("msg", ""))
		
		var sphere_col = _color_to_rgb(sphere_key) if has_sphere else s_color
		
		var v_box = VBoxContainer.new(); spheres_h.add_child(v_box)
		v_box.custom_minimum_size = Vector2(192, 0)
		var s_label = Label.new(); s_label.text = s_data["name"]; s_label.horizontal_alignment = 1; s_label.modulate = sphere_col if has_sphere else Color(1, 1, 1, 0.5); v_box.add_child(s_label)
		
		# ===== v760.1: ESFERA SLOT (slot APARTE, ARRIBA de la habilidad) =====
		var sphere_panel = PanelContainer.new(); sphere_panel.custom_minimum_size = Vector2(192, 148); v_box.add_child(sphere_panel)
		sphere_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sp_sb = StyleBoxFlat.new(); sp_sb.bg_color = Color(0.05, 0.05, 0.08, 0.6); sp_sb.border_width_left = 2; sp_sb.border_width_right = 2; sp_sb.border_width_top = 2; sp_sb.border_width_bottom = 2; sp_sb.border_color = sphere_col; sp_sb.corner_radius_top_left = 10; sp_sb.corner_radius_top_right = 10; sp_sb.corner_radius_bottom_left = 4; sp_sb.corner_radius_bottom_right = 4; sphere_panel.add_theme_stylebox_override("panel", sp_sb)
		
		var sp_center = CenterContainer.new(); sphere_panel.add_child(sp_center)
		var sp_info = VBoxContainer.new(); sp_info.alignment = BoxContainer.ALIGNMENT_CENTER; sp_center.add_child(sp_info)
		
		if has_sphere:
			sp_sb.border_color = _color_to_rgb(sphere_key)
			sp_sb.border_width_left = 3; sp_sb.border_width_right = 3; sp_sb.border_width_top = 3; sp_sb.border_width_bottom = 3
			var sphere_icon_path = _sphere_icon_path(sphere_key)
			if sphere_icon_path != "" and ResourceLoader.exists(sphere_icon_path):
				var s_tex_rect = TextureRect.new()
				s_tex_rect.texture = load(sphere_icon_path)
				s_tex_rect.custom_minimum_size = Vector2(52, 52)
				s_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				s_tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				s_tex_rect.modulate = _color_to_rgb(sphere_key)
				sp_info.add_child(s_tex_rect)
			var sp_name = Label.new()
			sp_name.text = str(installed_sp.get("name", "ESFERA")).to_upper() if typeof(installed_sp) == TYPE_DICTIONARY else "ESFERA"
			sp_name.horizontal_alignment = 1
			sp_name.modulate = _color_to_rgb(sphere_key)
			sp_name.add_theme_font_size_override("font_size", 10)
			sp_info.add_child(sp_name)
			var type_lbl = Label.new()
			type_lbl.text = _type_label_for_sphere(sphere_key)
			type_lbl.horizontal_alignment = 1
			type_lbl.modulate = _color_to_rgb(sphere_key)
			type_lbl.add_theme_font_size_override("font_size", 8)
			sp_info.add_child(type_lbl)
		else:
			var empty_lbl = Label.new()
			empty_lbl.text = "🔮\nSIN ESFERA"
			empty_lbl.horizontal_alignment = 1
			empty_lbl.modulate = Color(1, 1, 1, 0.4)
			empty_lbl.add_theme_font_size_override("font_size", 12)
			sp_info.add_child(empty_lbl)
		
		# Botones del slot de esfera (instalar / retirar)
		if not slot_locked:
			if not has_sphere:
				var b_install = Button.new(); b_install.text = "INSTALAR ESFERA"; b_install.add_theme_font_size_override("font_size", 9); v_box.add_child(b_install)
				b_install.modulate = Color(0.6, 1, 0.7)
				if is_comb:
					b_install.disabled = true
				else:
					b_install.pressed.connect(func():
						inv_main.pending_sphere_slot = i
						inv_main.pending_sphere_item = null
						_switch_subtab(sub_tabs, SUB_TAB_MIS_ESFERAS)
					)
			else:
				var b_retirar = Button.new(); b_retirar.text = "RETIRAR ESFERA"; b_retirar.add_theme_font_size_override("font_size", 9); v_box.add_child(b_retirar)
				b_retirar.modulate = Color(1, 0.7, 0.3)
				if is_comb:
					b_retirar.disabled = true
				else:
					b_retirar.pressed.connect(func():
						var sp_display_name = str(installed_sp.get("name", "LA ESFERA")) if typeof(installed_sp) == TYPE_DICTIONARY else "LA ESFERA"
						inv_main._show_modal("RETIRAR ESFERA", "¿Deseas retirar [color=orange]" + sp_display_name + "[/color] del " + str(s_data.get("name", "SLOT")) + "? Volverá a tu inventario y la habilidad equipada se desequipará.", func():
							NetworkManager.send_event("unequipSphereItem", {"sphereId": i})
						)
					)
		
		# ===== v760.1: HABILIDAD SLOT (ABAJO — la skill vive dentro de la esfera instalada) =====
		var skill_panel = PanelContainer.new(); skill_panel.custom_minimum_size = Vector2(192, 128); v_box.add_child(skill_panel)
		skill_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sk_sb = StyleBoxFlat.new(); sk_sb.bg_color = Color(0.02, 0.03, 0.06, 0.6); sk_sb.border_width_left = 2; sk_sb.border_width_right = 2; sk_sb.border_width_top = 2; sk_sb.border_width_bottom = 2; sk_sb.border_color = sphere_col if has_sphere else Color(1, 1, 1, 0.2); sk_sb.corner_radius_top_left = 4; sk_sb.corner_radius_top_right = 4; sk_sb.corner_radius_bottom_left = 10; sk_sb.corner_radius_bottom_right = 10; skill_panel.add_theme_stylebox_override("panel", sk_sb)
		
		var sk_center = CenterContainer.new(); skill_panel.add_child(sk_center)
		var sk_info = VBoxContainer.new(); sk_info.alignment = BoxContainer.ALIGNMENT_CENTER; sk_center.add_child(sk_info)
		
		var s_name = "SIN HABILIDAD"
		if equipped:
			if typeof(equipped) == TYPE_DICTIONARY: s_name = str(equipped.get("skill_name", "SKILL"))
			elif "skill_name" in equipped: s_name = str(equipped.skill_name)
			var display_name = s_name
			if NetworkManager and NetworkManager.server_config:
				var server_skills = NetworkManager.server_config.get("skillsData", {})
				var lookup_name = s_name.to_upper().strip_edges()
				if "REFLECT" in lookup_name:
					for key in server_skills.keys():
						if "REFLECT" in key.to_upper():
							lookup_name = key
							break
				if server_skills.has(lookup_name):
					display_name = server_skills[lookup_name].get("name", server_skills[lookup_name].get("label", s_name))
			s_name = display_name
			
			var tex = _load_skill_icon_texture(s_name)
			if tex:
				var icon_rect = TextureRect.new()
				icon_rect.texture = tex
				icon_rect.custom_minimum_size = Vector2(44, 44)
				icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				sk_info.add_child(icon_rect)
		
		var skill_lbl = Label.new()
		skill_lbl.text = s_name.to_upper()
		skill_lbl.horizontal_alignment = 1
		skill_lbl.add_theme_font_size_override("font_size", 9)
		skill_lbl.modulate = Color.WHITE if equipped else Color(1, 1, 1, 0.35)
		sk_info.add_child(skill_lbl)
		
		# Botones del slot de habilidad (equipar / reconfigurar / desequipar)
		if not slot_locked:
			if has_sphere:
				if equipped:
					var b_reconf = Button.new(); b_reconf.text = "RECONFIGURAR"; b_reconf.add_theme_font_size_override("font_size", 9); v_box.add_child(b_reconf)
					if is_comb:
						b_reconf.disabled = true
					else:
						b_reconf.pressed.connect(func():
							inv_main.pending_skill_to_equip = null
							inv_main.selected_sphere_type_filter = _type_label_for_sphere(sphere_key)
							_switch_subtab(sub_tabs, SUB_TAB_BIBLIOTECA)
						)
					var bu = Button.new(); bu.text = "DESEQUIPAR"; bu.add_theme_font_size_override("font_size", 9); bu.modulate = Color(1, 0.4, 0.4); v_box.add_child(bu)
					if is_comb:
						bu.disabled = true
					else:
						bu.pressed.connect(func(): NetworkManager.send_event("unequipSphere", {"sphereId": i}))
				else:
					var b_skill = Button.new(); b_skill.text = "EQUIPAR HABILIDAD"; b_skill.add_theme_font_size_override("font_size", 9); v_box.add_child(b_skill)
					b_skill.modulate = Color(0.6, 0.9, 1)
					if is_comb:
						b_skill.disabled = true
					else:
						b_skill.pressed.connect(func():
							inv_main.pending_skill_to_equip = null
							inv_main.selected_sphere_type_filter = _type_label_for_sphere(sphere_key)
							_switch_subtab(sub_tabs, SUB_TAB_BIBLIOTECA)
						)
			else:
				var no_sphere_lbl = Label.new()
				no_sphere_lbl.text = "REQUIERE ESFERA"
				no_sphere_lbl.horizontal_alignment = 1
				no_sphere_lbl.add_theme_font_size_override("font_size", 8)
				no_sphere_lbl.modulate = Color(1, 1, 1, 0.4)
				v_box.add_child(no_sphere_lbl)
		
		if slot_locked:
			var lock_lbl = Label.new()
			lock_lbl.text = "🔒 " + slot_req_msg
			lock_lbl.add_theme_font_size_override("font_size", 8)
			lock_lbl.modulate = Color(1, 0.35, 0.35)
			lock_lbl.horizontal_alignment = 1
			lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v_box.add_child(lock_lbl)
		
		# v301.5: Interacción de click en el SLOT DE ESFERA (instalar desde MIS ESFERAS)
		sphere_panel.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				if is_comb: return
				if slot_locked:
					if NetworkManager:
						NetworkManager.game_notification.emit({
							"msg": "ESFERA BLOQUEADA: " + slot_req_msg,
							"type": "error"
						})
					return
				
				# v760.0: Flujo de instalación de esfera (pendiente desde MIS ESFERAS)
				if inv_main.get("pending_sphere_item") != null:
					if has_sphere:
						NetworkManager.game_notification.emit({
							"msg": "Este slot ya tiene una esfera instalada. Retírala primero.",
							"type": "error"
						})
						return
					var p_item = inv_main.pending_sphere_item
					var p_key = _sphere_color_of_item(p_item)
					inv_main._show_modal("INSTALAR ESFERA", "¿Deseas instalar [color=" + str(_color_to_rgb(p_key)) + "]" + str(p_item.get("name", "ESFERA")) + "[/color] en el " + str(s_data.get("name", "SLOT")) + "? Se consumirá el ítem de tu inventario.", func():
						NetworkManager.send_event("equipSphereItem", {"sphereId": i, "instanceId": str(p_item.get("instanceId", ""))})
						if is_instance_valid(sm):
							sm.install_sphere(i, {
								"id": p_item.get("id", ""),
								"name": p_item.get("name", "Esfera"),
								"type": p_key,
								"color": p_item.get("color", ""),
								"icon": p_item.get("icon", ""),
								"instanceId": str(p_item.get("instanceId", ""))
							})
						inv_main.pending_sphere_item = null
						update_ui()
					)
					return
				else:
					inv_main.selected_sphere_slot = i; update_ui()
		)
		
		# v301.5: Interacción de click en el SLOT DE HABILIDAD (confirmar equipamiento de skill)
		skill_panel.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				if is_comb: return
				if slot_locked:
					if NetworkManager:
						NetworkManager.game_notification.emit({
							"msg": "ESFERA BLOQUEADA: " + slot_req_msg,
							"type": "error"
						})
					return
				
				# v301.5: Confirmación de equipamiento de skill
				if inv_main.get("pending_skill_to_equip") != null:
					if not has_sphere:
						NetworkManager.game_notification.emit({
							"msg": "Este slot no tiene esfera instalada. Instala una esfera primero.",
							"type": "error"
						})
						return
					var skill = inv_main.pending_skill_to_equip
					# v760.0: La skill debe coincidir con el color de la esfera instalada
					if is_instance_valid(sm) and not sm.skill_matches_sphere(i, skill.type):
						NetworkManager.game_notification.emit({
							"msg": "LA ESFERA " + _color_label(sphere_key) + " SOLO ACEPTA HABILIDADES DE " + _type_label_for_sphere(sphere_key) + ".",
							"type": "error"
						})
						inv_main.pending_skill_to_equip = null
						update_ui()
						return
					# v400.0: Requisitos de equipamiento (validación local UX en confirmación de slot)
					if NetworkManager:
						var req_check = NetworkManager.check_equip_requirements("", skill.skill_name)
						if not req_check.get("ok", true):
							NetworkManager.game_notification.emit({
								"msg": "HABILIDAD BLOQUEADA: " + str(req_check.get("msg", "Requisitos no cumplidos")),
								"type": "error"
							})
							inv_main.pending_skill_to_equip = null
							update_ui()
							return
					NetworkManager.send_event("equipSphere", {"sphereId": i, "skill": {"skill_name": skill.skill_name, "power_value": skill.power_value, "type": skill.type}})
					if is_instance_valid(inv_main.spheres_manager): inv_main.spheres_manager.equip_item(i, skill)
					inv_main.pending_skill_to_equip = null
					update_ui()
				else:
					inv_main.selected_sphere_slot = i; update_ui()
		)
		
		# v760.0: Efecto visual "Esperando Selección" — resaltar slots de habilidad compatibles
		if inv_main.get("pending_skill_to_equip") != null and not slot_locked and has_sphere:
			var skill_p = inv_main.pending_skill_to_equip
			var compatible = is_instance_valid(sm) and sm.skill_matches_sphere(i, skill_p.type)
			if compatible:
				var tween = create_tween().set_loops()
				if is_instance_valid(sk_sb):
					tween.tween_property(sk_sb, "border_color", Color.WHITE, 0.4)
					tween.tween_property(sk_sb, "border_color", _color_to_rgb(sphere_key), 0.4)
			else:
				v_box.modulate.a = 0.4
				var incompat = Label.new()
				incompat.text = "NO COMPATIBLE"
				incompat.add_theme_font_size_override("font_size", 8)
				incompat.modulate = Color(1, 0.4, 0.4)
				incompat.horizontal_alignment = 1
				v_box.add_child(incompat)
		
		# v680.0: Slot bloqueado → atenuado y con borde neutro
		if slot_locked:
			v_box.modulate.a = 0.45
			sp_sb.bg_color = Color(0.05, 0.05, 0.08, 0.4)
			sp_sb.border_color = Color(1, 1, 1, 0.15)
			sk_sb.bg_color = Color(0.05, 0.05, 0.08, 0.4)
			sk_sb.border_color = Color(1, 1, 1, 0.15)

# ============================================================
# SUB-TAB 2: MIS ESFERAS (inventario de esferas físicas)
# ============================================================
func _render_owned_spheres(tab, sub_tabs):
	var main_v = VBoxContainer.new(); main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); main_v.offset_left = 20; main_v.offset_right = -20; main_v.offset_top = 20; tab.add_child(main_v)
	
	var player_node = get_tree().get_first_node_in_group("player")
	var is_comb = player_node and player_node.has_method("is_in_combat") and player_node.is_in_combat()
	
	var sm = inv_main.spheres_manager
	var installed_counts: Dictionary = _count_installed_by_color()
	var owned: Array = _get_owned_spheres()
	var owned_counts: Dictionary = _count_owned_by_color()
	var installed_total = 0
	for c in installed_counts.values(): installed_total += int(c)
	
	# Banner de selección de slot (flujo desde SISTEMA ORBITAL)
	if inv_main.get("pending_sphere_slot") != null and int(inv_main.pending_sphere_slot) >= 0:
		var slot_name = "SLOT"
		if is_instance_valid(sm) and inv_main.pending_sphere_slot < sm.spheres_data.size():
			slot_name = str(sm.spheres_data[inv_main.pending_sphere_slot].get("name", "SLOT")).to_upper()
		var banner = Label.new()
		banner.text = "➡️ SELECCIONÁ LA ESFERA A INSTALAR EN " + slot_name
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.modulate = Color.YELLOW
		banner.add_theme_font_size_override("font_size", 11)
		main_v.add_child(banner)
	
	# Resumen
	var title = Label.new()
	title.text = "TUS ESFERAS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color.CYAN
	title.add_theme_font_size_override("font_size", 13)
	main_v.add_child(title)
	
	var summary = Label.new()
	summary.text = "INSTALADAS: %d/4   •   EN BODEGA: %d" % [installed_total, owned.size()]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 11)
	summary.modulate = Color(0.8, 0.8, 0.9, 0.9)
	main_v.add_child(summary)
	
	# Contadores por color
	var color_h = HBoxContainer.new(); color_h.alignment = BoxContainer.ALIGNMENT_CENTER; color_h.add_theme_constant_override("separation", 18); main_v.add_child(color_h)
	for key in ["roja", "azul", "verde", "amarilla"]:
		var inst: int = int(installed_counts.get(key, 0))
		var own: int = int(owned_counts.get(key, 0))
		var c_lbl = Label.new()
		c_lbl.text = "● " + _color_label(key) + ": " + str(inst) + " eq + " + str(own) + " bdg"
		c_lbl.modulate = _color_to_rgb(key)
		c_lbl.add_theme_font_size_override("font_size", 10)
		color_h.add_child(c_lbl)
	
	main_v.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var grid = GridContainer.new(); grid.columns = 3; grid.size_flags_horizontal = 3; grid.add_theme_constant_override("h_separation", 15); grid.add_theme_constant_override("v_separation", 15); scroll.add_child(grid)
	
	if owned.is_empty():
		var empty_v = VBoxContainer.new(); grid.add_child(empty_v)
		var empty_lbl = Label.new()
		empty_lbl.text = "NO TENÉS ESFERAS EN LA BODEGA.\n\nFabricalas en la pestaña CRAFTEO:\n• Esfera Roja (ATAQUE)\n• Esfera Azul (DEFENSA)\n• Esfera Verde (CURACIÓN)\n• Esfera Amarilla (UTILIDAD)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.modulate = Color(0.7, 0.7, 0.8, 0.8)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_v.add_child(empty_lbl)
	else:
		for item in owned:
			_create_sphere_card(item, grid, sub_tabs, is_comb)
	
	if is_comb:
		var warn = Label.new()
		warn.text = "⚠️ SISTEMA BLOQUEADO: EN COMBATE"
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.modulate = Color.RED
		warn.add_theme_font_size_override("font_size", 10)
		main_v.add_child(warn)

func _create_sphere_card(item, parent, sub_tabs, is_comb):
	var key: String = _sphere_color_of_item(item)
	var col = _color_to_rgb(key)
	
	var p = PanelContainer.new(); p.custom_minimum_size = Vector2(200, 170)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.02, 0.04, 0.08, 0.7); sb.border_width_left = 3; sb.border_color = col; sb.corner_radius_top_right = 8; sb.corner_radius_bottom_right = 8; p.add_theme_stylebox_override("panel", sb)
	
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 5); p.add_child(v)
	
	var icon_path = str(item.get("icon", ""))
	if icon_path == "": icon_path = _sphere_icon_path(key)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex_rect = TextureRect.new()
		tex_rect.texture = load(icon_path)
		tex_rect.custom_minimum_size = Vector2(56, 56)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex_rect.modulate = col
		v.add_child(tex_rect)
	
	var name_lbl = Label.new()
	name_lbl.text = str(item.get("name", "ESFERA")).to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.modulate = col
	name_lbl.add_theme_font_size_override("font_size", 11)
	v.add_child(name_lbl)
	
	var type_lbl = Label.new()
	type_lbl.text = _type_label_for_sphere(key)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.modulate = Color(0.8, 0.8, 0.8, 0.7)
	type_lbl.add_theme_font_size_override("font_size", 8)
	v.add_child(type_lbl)
	
	var b = Button.new(); b.text = "INSTALAR"; b.custom_minimum_size = Vector2(0, 30); b.add_theme_font_size_override("font_size", 10)
	if is_comb:
		b.disabled = true
	else:
		b.pressed.connect(func():
			# Si hay un slot pendiente de selección (flujo desde SISTEMA ORBITAL) → instalar directo
			if inv_main.get("pending_sphere_slot") != null and int(inv_main.pending_sphere_slot) >= 0:
				var slot_id = int(inv_main.pending_sphere_slot)
				var sm = inv_main.spheres_manager
				var slot_locked = false
				if NetworkManager:
					var sc = NetworkManager.check_sphere_slot_requirements(slot_id)
					slot_locked = not sc.get("ok", true)
				if slot_locked:
					NetworkManager.game_notification.emit({
						"msg": "SLOT BLOQUEADO: No cumple los requisitos de nivel.",
						"type": "error"
					})
					return
				if is_instance_valid(sm) and sm.has_installed_sphere(slot_id):
					NetworkManager.game_notification.emit({
						"msg": "Ese slot ya tiene una esfera instalada. Retírala primero.",
						"type": "error"
					})
					return
				inv_main._show_modal("INSTALAR ESFERA", "¿Deseas instalar [color=yellow]" + str(item.get("name", "ESFERA")) + "[/color] en el " + str(sm.spheres_data[slot_id].get("name", "SLOT")) + "? Se consumirá el ítem de tu inventario.", func():
					NetworkManager.send_event("equipSphereItem", {"sphereId": slot_id, "instanceId": str(item.get("instanceId", ""))})
					if is_instance_valid(sm):
						sm.install_sphere(slot_id, {
							"id": item.get("id", ""),
							"name": item.get("name", "Esfera"),
							"type": key,
							"color": item.get("color", ""),
							"icon": item.get("icon", ""),
							"instanceId": str(item.get("instanceId", ""))
						})
					inv_main.pending_sphere_slot = -1
					update_ui()
				)
			else:
				# Flujo inverso: seleccionar la esfera y elegir slot en SISTEMA ORBITAL
				inv_main.pending_sphere_item = item
				inv_main.pending_sphere_slot = -1
				_switch_subtab(sub_tabs, SUB_TAB_ORBITAL)
		)
	v.add_child(b)
	parent.add_child(p)

# ============================================================
# SUB-TAB 3: BIBLIOTECA DE HABILIDADES
# ============================================================
func _render_spheres_library(tab, sub_tabs):
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
	
	# v760.0: Requisito de ESFERA INSTALADA del color correcto (además de los requisitos v400.0)
	var sphere_required_key: String = _sphere_color_for_type(str(skill.type))
	var has_compatible_sphere = false
	var usable_slots: Array = []
	if is_instance_valid(inv_main.spheres_manager):
		var sm = inv_main.spheres_manager
		for si in range(min(sm.spheres_data.size(), 4)):
			if not sm.has_installed_sphere(si): continue
			var slot_key: String = _sphere_color_key(sm.spheres_data[si])
			if slot_key != sphere_required_key: continue
			if NetworkManager:
				var sc = NetworkManager.check_sphere_slot_requirements(si)
				if not sc.get("ok", true): continue
			usable_slots.append(si)
			has_compatible_sphere = true
	
	# v400.0: Requisitos de equipamiento — indicador visual de bloqueo en biblioteca
	var req_msg = ""
	var req_ok = true
	if NetworkManager and not is_equipped:
		var req_check = NetworkManager.check_equip_requirements("", skill.skill_name)
		req_ok = req_check.get("ok", true)
		req_msg = str(req_check.get("msg", ""))
	
	var locked_by_sphere = (not is_equipped and not has_compatible_sphere and not is_comb)
	if locked_by_sphere:
		b_equip.disabled = true
		b_equip.modulate = Color(1, 0.4, 0.4)
		var sphere_lbl = Label.new()
		sphere_lbl.text = "🔒 REQUIERE ESFERA " + _color_label(sphere_required_key) + " INSTALADA\n(Fabrícala en CRAFTEO e instálala en SISTEMA ORBITAL)"
		sphere_lbl.add_theme_font_size_override("font_size", 8)
		sphere_lbl.modulate = _color_to_rgb(sphere_required_key)
		sphere_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v_info.add_child(sphere_lbl)
		skill_card.modulate.a = 0.55
	
	if not req_ok and not is_equipped:
		b_equip.disabled = true
		b_equip.modulate = Color(1, 0.4, 0.4)
		var req_lbl = Label.new()
		req_lbl.text = "🔒 " + req_msg
		req_lbl.add_theme_font_size_override("font_size", 8)
		req_lbl.modulate = Color(1, 0.35, 0.35)
		v_info.add_child(req_lbl)
		skill_card.modulate.a = 0.55

	if is_equipped: skill_card.modulate.a = 0.5
	elif is_comb: skill_card.modulate.a = 0.6
	
	b_equip.pressed.connect(func():
		# v400.0: Requisitos de equipamiento de habilidades (validación local UX)
		if NetworkManager:
			var req_check = NetworkManager.check_equip_requirements("", skill.skill_name)
			if not req_check.get("ok", true):
				NetworkManager.game_notification.emit({
					"msg": "HABILIDAD BLOQUEADA: " + str(req_check.get("msg", "Requisitos no cumplidos")),
					"type": "error"
				})
				return
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
