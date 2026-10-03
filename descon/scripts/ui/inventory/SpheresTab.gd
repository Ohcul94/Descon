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
	# v760.3: Si hay habilidad equipada, la esfera SE ADAPTA al color de la habilidad
	var eq = slot_data.get("equipped")
	if eq != null:
		var st = ""
		if typeof(eq) == TYPE_DICTIONARY: st = str(eq.get("type", "")).to_lower()
		elif "type" in eq: st = str(eq.type).to_lower()
		if st != "":
			return _sphere_color_for_type(st)
			
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

func _skill_type_matches_filter(skill_type: String, filter: String) -> bool:
	if filter == "ANY": return true
	var s_t = skill_type.to_upper().strip_edges()
	var f = filter.to_upper().strip_edges()
	if f == "UTILIDAD" or f == "MOVIMIENTO" or f == "UTILIDAD / MOVIMIENTO":
		return s_t == "UTILIDAD" or s_t == "MOVIMIENTO" or s_t == "UTILIDAD / MOVIMIENTO"
	if f == "CURACIÓN" or f == "CURACION":
		return s_t == "CURACIÓN" or s_t == "CURACION"
	return s_t == f

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

# v760.4: ¿El jugador posee al menos una esfera de este color (instalada o en bodega)?
func _player_owns_sphere_color(req_color: String) -> bool:
	var inst_counts = _count_installed_by_color()
	if int(inst_counts.get(req_color, 0)) > 0:
		return true
	var owned_counts = _count_owned_by_color()
	if int(owned_counts.get(req_color, 0)) > 0:
		return true
	return false

# v760.4: Trasladar/intercambiar automáticamente la esfera del color requerido al slot destino
func _sync_sphere_swap(target_slot: int, req_color: String):
	var sm = inv_main.spheres_manager if inv_main else null
	if not is_instance_valid(sm): return
	var cur_sp = sm.spheres_data[target_slot].get("sphere")
	if cur_sp and typeof(cur_sp) == TYPE_DICTIONARY:
		var cur_c = _sphere_color_key(sm.spheres_data[target_slot])
		if cur_c == req_color: return
	
	for j in range(min(sm.spheres_data.size(), 4)):
		if j == target_slot: continue
		var other_c = _sphere_color_key(sm.spheres_data[j])
		if other_c == req_color:
			var temp_sp = sm.spheres_data[target_slot].get("sphere")
			var temp_type = sm.spheres_data[target_slot].get("type")
			var temp_color = sm.spheres_data[target_slot].get("color")
			var temp_eq = sm.spheres_data[target_slot].get("equipped")

			sm.spheres_data[target_slot]["sphere"] = sm.spheres_data[j].get("sphere")
			sm.spheres_data[target_slot]["type"] = sm.spheres_data[j].get("type")
			sm.spheres_data[target_slot]["color"] = sm.spheres_data[j].get("color")

			sm.spheres_data[j]["sphere"] = temp_sp
			sm.spheres_data[j]["type"] = temp_type
			sm.spheres_data[j]["color"] = temp_color

			var j_new_c = _sphere_color_key(sm.spheres_data[j])
			if temp_eq != null and _sphere_color_for_type(str(temp_eq.get("type", ""))) == j_new_c:
				sm.spheres_data[j]["equipped"] = temp_eq
			else:
				sm.spheres_data[j]["equipped"] = null
			break


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
		{"path": "res://scripts/resources/skills/Skill_FearSphere.gd", "icon": "💀"},
		{"path": "res://scripts/resources/skills/Skill_Hookshot.gd", "icon": "🪝"}
	]
	
	for cfg in skill_configs:
		if ResourceLoader.exists(cfg["path"]):
			var script = InventoryCache.get_cached_script(cfg["path"])
			if not script:
				script = load(cfg["path"])
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
	# Normalizar acentos para matchear claves del server (VÍNCULO VITAL, REGENERACIÓN ALFA…)
	var clean_name_no_accents = clean_name.replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")
	if "REFLECT" in clean_name:
		for key in server_skills.keys():
			if "REFLECT" in key.to_upper():
				lookup_key = key
				break
	if not server_skills.has(lookup_key):
		if server_skills.has(clean_name_no_accents):
			lookup_key = clean_name_no_accents
		else:
			for key in server_skills.keys():
				var k = str(key).to_upper().strip_edges().replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")
				if k == clean_name_no_accents:
					lookup_key = key
					break
	
	if not server_skills.has(lookup_key):
		_texture_cache[clean_name] = null
		return null
		
	var icon_path = server_skills[lookup_key].get("icon", "")
	var lower_path = icon_path.to_lower() if icon_path else ""
	if icon_path == "" or not (lower_path.ends_with(".png") or lower_path.ends_with(".jpg") or lower_path.ends_with(".jpeg") or lower_path.ends_with(".webp")):
		_texture_cache[clean_name] = null
		return null
		
	if ResourceLoader.exists(icon_path):
		var tex = InventoryCache.get_texture(icon_path)
		if not tex:
			tex = load(icon_path)
		_texture_cache[clean_name] = tex
		return tex
		
	_texture_cache[clean_name] = null
	return null

func _switch_subtab(sub_tabs, idx: int):
	if sub_tabs:
		sub_tabs.current_tab = idx
	update_ui()

# v760.2: Selector visual e intuitivo de slots para esferas o habilidades
func _show_slot_picker(title: String, item_or_skill, is_sphere: bool, on_slot_chosen: Callable):
	var sm = inv_main.spheres_manager if inv_main else null
	if not is_instance_valid(sm): return

	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "SlotPickerCanvas"
	canvas_layer.layer = 125
	get_tree().root.add_child(canvas_layer)

	var overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(520, 260)
	overlay.add_child(p)

	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_left = -p.custom_minimum_size.x / 2.0
	p.offset_right = p.custom_minimum_size.x / 2.0
	p.offset_top = -p.custom_minimum_size.y / 2.0
	p.offset_bottom = p.custom_minimum_size.y / 2.0

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.08, 0.96)
	sb.border_width_left = 2; sb.border_width_right = 2
	sb.border_width_top = 3; sb.border_width_bottom = 2
	sb.border_color = Color.CYAN
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 15)
	p.add_child(v)

	var target_name = ""
	if typeof(item_or_skill) == TYPE_DICTIONARY:
		target_name = str(item_or_skill.get("name", item_or_skill.get("skill_name", "")))
	elif "skill_name" in item_or_skill:
		target_name = str(item_or_skill.skill_name)

	var title_lbl = Label.new()
	title_lbl.text = title + ": " + target_name.to_upper()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.modulate = Color.CYAN
	title_lbl.add_theme_font_size_override("font_size", 14)
	v.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Selecciona el slot en el que deseas colocarlo:"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.modulate = Color(0.8, 0.8, 0.8, 0.8)
	sub_lbl.add_theme_font_size_override("font_size", 11)
	v.add_child(sub_lbl)

	var slots_h = HBoxContainer.new()
	slots_h.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_h.add_theme_constant_override("separation", 12)
	v.add_child(slots_h)

	for i in range(min(sm.spheres_data.size(), 4)):
		var s_data = sm.spheres_data[i]
		var sc = {"ok": true, "msg": ""}
		if NetworkManager:
			sc = NetworkManager.check_sphere_slot_requirements(i)
		var slot_locked = not sc.get("ok", true)

		var slot_btn = Button.new()
		slot_btn.custom_minimum_size = Vector2(110, 110)
		slot_btn.disabled = slot_locked
		slot_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var btn_v = VBoxContainer.new()
		btn_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn_v.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_btn.add_child(btn_v)

		var s_name_lbl = Label.new()
		s_name_lbl.text = "SLOT " + str(i + 1)
		s_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_name_lbl.add_theme_font_size_override("font_size", 12)
		s_name_lbl.modulate = Color.WHITE if not slot_locked else Color(0.6, 0.6, 0.6)
		btn_v.add_child(s_name_lbl)

		if slot_locked:
			var lk = Label.new()
			lk.text = "[BLOQUEADO]\n" + str(sc.get("msg", ""))
			lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lk.add_theme_font_size_override("font_size", 8)
			lk.modulate = Color(1, 0.4, 0.4)
			lk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn_v.add_child(lk)
		else:
			var cur_sp = s_data.get("sphere")
			var cur_sk = s_data.get("equipped")

			var sp_txt = "Sin Esfera"
			var sp_col = Color(1, 1, 1, 0.4)
			if cur_sp and typeof(cur_sp) == TYPE_DICTIONARY:
				var sp_c = _sphere_color_of_item(cur_sp)
				sp_txt = str(cur_sp.get("name", "Esfera"))
				sp_col = _color_to_rgb(sp_c)

			var sk_txt = "Sin Skill"
			var sk_col = Color(1, 1, 1, 0.4)
			if cur_sk:
				if typeof(cur_sk) == TYPE_DICTIONARY:
					sk_txt = str(cur_sk.get("skill_name", "Skill"))
				elif "skill_name" in cur_sk:
					sk_txt = str(cur_sk.skill_name)
				sk_col = Color(0.6, 1, 0.8)

			var sp_lbl = Label.new()
			sp_lbl.text = ("🔄 " if (is_sphere and cur_sp) else "") + sp_txt
			sp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sp_lbl.add_theme_font_size_override("font_size", 9)
			sp_lbl.modulate = sp_col
			sp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn_v.add_child(sp_lbl)

			var sk_lbl = Label.new()
			sk_lbl.text = ("🔄 " if (not is_sphere and cur_sk) else "") + sk_txt
			sk_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sk_lbl.add_theme_font_size_override("font_size", 8)
			sk_lbl.modulate = sk_col
			sk_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn_v.add_child(sk_lbl)

		var target_idx = i
		slot_btn.pressed.connect(func():
			canvas_layer.queue_free()
			on_slot_chosen.call(target_idx)
		)
		slots_h.add_child(slot_btn)

	var close_b = Button.new()
	close_b.text = "CANCELAR"
	close_b.custom_minimum_size = Vector2(120, 32)
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_b.pressed.connect(func(): canvas_layer.queue_free())
	v.add_child(close_b)

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
		banner.text = ">> SELECCIONA UNA ESFERA EN 'MIS ESFERAS' PARA EL " + str(sm.spheres_data[inv_main.pending_sphere_slot].get("name", "SLOT")).to_upper()
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.modulate = Color.YELLOW
		banner.add_theme_font_size_override("font_size", 10)
		master_v.add_child(banner)
		var cancel_b = Button.new(); cancel_b.text = "CANCELAR SELECCIÓN"; cancel_b.add_theme_font_size_override("font_size", 9)
		cancel_b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cancel_b.pressed.connect(func(): inv_main.pending_sphere_slot = -1; update_ui())
		master_v.add_child(cancel_b)
	
	# v760.2: Banner de selección de habilidad (flujo asignación de habilidad)
	if inv_main.get("selected_sphere_slot") != null and int(inv_main.selected_sphere_slot) >= 0:
		var banner_sk = Label.new()
		banner_sk.text = ">> SELECCIONA UNA HABILIDAD EN 'BIBLIOTECA' PARA EL " + str(sm.spheres_data[inv_main.selected_sphere_slot].get("name", "SLOT")).to_upper()
		banner_sk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner_sk.modulate = Color.CYAN
		banner_sk.add_theme_font_size_override("font_size", 10)
		master_v.add_child(banner_sk)
		var cancel_sk = Button.new(); cancel_sk.text = "CANCELAR ASIGNACIÓN"; cancel_sk.add_theme_font_size_override("font_size", 9)
		cancel_sk.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cancel_sk.pressed.connect(func(): inv_main.selected_sphere_slot = -1; update_ui())
		master_v.add_child(cancel_sk)

	# v760.0: Banner de confirmación de instalación (flujo desde MIS ESFERAS)
	if inv_main.get("pending_sphere_item") != null:
		var banner2 = Label.new()
		banner2.text = ">> CLICK EN UN SLOT PARA INSTALAR LA ESFERA SELECCIONADA"
		banner2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner2.modulate = Color.YELLOW
		banner2.add_theme_font_size_override("font_size", 10)
		master_v.add_child(banner2)
		var cancel_b2 = Button.new(); cancel_b2.text = "CANCELAR SELECCIÓN"; cancel_b2.add_theme_font_size_override("font_size", 9)
		cancel_b2.pressed.connect(func(): inv_main.pending_sphere_item = null; update_ui())
		master_v.add_child(cancel_b2)
	
	if is_comb:
		var warning_lbl = Label.new()
		warning_lbl.text = "[!] SISTEMA BLOQUEADO: EN COMBATE"
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
		var equipped = s_data.get("equipped")
		var has_sphere = sm.has_installed_sphere(i) or (equipped != null)
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
				var sphere_tex = InventoryCache.get_texture(sphere_icon_path)
				s_tex_rect.texture = sphere_tex if sphere_tex else load(sphere_icon_path)
				s_tex_rect.custom_minimum_size = Vector2(84, 84)
				s_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				s_tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				s_tex_rect.modulate = _color_to_rgb(sphere_key)
				sp_info.add_child(s_tex_rect)
			var sp_name = Label.new()
			var name_str = ("ESFERA " + _sphere_color_name(sphere_key)).to_upper()
			if sphere_key == "":
				name_str = str(installed_sp.get("name", "ESFERA")).to_upper() if typeof(installed_sp) == TYPE_DICTIONARY else "ESFERA"
			sp_name.text = name_str
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
			empty_lbl.text = "SIN ESFERA"
			empty_lbl.horizontal_alignment = 1
			empty_lbl.modulate = Color(1, 1, 1, 0.4)
			empty_lbl.add_theme_font_size_override("font_size", 12)
			sp_info.add_child(empty_lbl)
		
		# Botones del slot de esfera (instalar / cambiar / retirar)
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
				var b_cambiar = Button.new(); b_cambiar.text = "CAMBIAR ESFERA"; b_cambiar.add_theme_font_size_override("font_size", 9); v_box.add_child(b_cambiar)
				b_cambiar.modulate = Color(0.6, 1, 0.9)
				if is_comb:
					b_cambiar.disabled = true
				else:
					b_cambiar.pressed.connect(func():
						inv_main.pending_sphere_slot = i
						inv_main.pending_sphere_item = null
						_switch_subtab(sub_tabs, SUB_TAB_MIS_ESFERAS)
					)

				var b_retirar = Button.new(); b_retirar.text = "RETIRAR ESFERA"; b_retirar.add_theme_font_size_override("font_size", 9); v_box.add_child(b_retirar)
				b_retirar.modulate = Color(1, 0.7, 0.3)
				if is_comb:
					b_retirar.disabled = true
				else:
					b_retirar.pressed.connect(func():
						var sp_display_name = str(installed_sp.get("name", "LA ESFERA")) if typeof(installed_sp) == TYPE_DICTIONARY else "LA ESFERA"
						inv_main._show_modal("RETIRAR ESFERA", "¿Deseas retirar [color=orange]" + sp_display_name + "[/color] del " + str(s_data.get("name", "SLOT")) + "? Volverá a tu bodega y la habilidad equipada se desinstalará automáticamente.", func():
							NetworkManager.send_event("unequipSphereItem", {"sphereId": i})
							if is_instance_valid(sm):
								sm.remove_sphere(i)
							update_ui()
						)
					)
		
		# ===== HABILIDAD SLOT =====
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
				icon_rect.custom_minimum_size = Vector2(110, 110)
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
			if equipped:
				var b_reconf = Button.new(); b_reconf.text = "RECONFIGURAR"; b_reconf.add_theme_font_size_override("font_size", 9); v_box.add_child(b_reconf)
				if is_comb:
					b_reconf.disabled = true
				else:
					b_reconf.pressed.connect(func():
						inv_main.pending_skill_to_equip = null
						inv_main.selected_sphere_slot = i
						inv_main.selected_sphere_type_filter = "ANY"
						_switch_subtab(sub_tabs, SUB_TAB_BIBLIOTECA)
					)
				var bu = Button.new(); bu.text = "DESEQUIPAR"; bu.add_theme_font_size_override("font_size", 9); bu.modulate = Color(1, 0.4, 0.4); v_box.add_child(bu)
				if is_comb:
					bu.disabled = true
				else:
					bu.pressed.connect(func():
						NetworkManager.send_event("unequipSphere", {"sphereId": i})
						if is_instance_valid(sm):
							sm.equip_item(i, null)
						update_ui()
					)
			else:
				var b_skill = Button.new(); b_skill.text = "EQUIPAR HABILIDAD"; b_skill.add_theme_font_size_override("font_size", 9); v_box.add_child(b_skill)
				b_skill.modulate = Color(0.6, 0.9, 1)
				if is_comb:
					b_skill.disabled = true
				else:
					b_skill.pressed.connect(func():
						inv_main.pending_skill_to_equip = null
						inv_main.selected_sphere_slot = i
						inv_main.selected_sphere_type_filter = "ANY"
						_switch_subtab(sub_tabs, SUB_TAB_BIBLIOTECA)
					)
		
		if slot_locked:
			var lock_lbl = Label.new()
			lock_lbl.text = "[BLOQUEADO] " + slot_req_msg
			lock_lbl.add_theme_font_size_override("font_size", 8)
			lock_lbl.modulate = Color(1, 0.35, 0.35)
			lock_lbl.horizontal_alignment = 1
			lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v_box.add_child(lock_lbl)
		
		# Interacción de click en el SLOT DE ESFERA (instalar o reemplazar esfera)
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
				
				# Flujo de instalación de esfera (pendiente desde MIS ESFERAS)
				if inv_main.get("pending_sphere_item") != null:
					var p_item = inv_main.pending_sphere_item
					var p_key = _sphere_color_of_item(p_item)
					var action_word = "instalar" if not has_sphere else "reemplazar con"
					inv_main._show_modal("INSTALAR ESFERA", "¿Deseas " + action_word + " [color=" + str(_color_to_rgb(p_key)) + "]" + str(p_item.get("name", "ESFERA")) + "[/color] en el " + str(s_data.get("name", "SLOT")) + "?", func():
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
		
		# Interacción de click en el SLOT DE HABILIDAD (confirmar equipamiento de skill)
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
				
				if not has_sphere:
					if NetworkManager:
						NetworkManager.game_notification.emit({
							"msg": "Debes instalar una esfera en este slot primero.",
							"type": "error"
						})
					inv_main.pending_sphere_slot = i
					inv_main.pending_sphere_item = null
					_switch_subtab(sub_tabs, SUB_TAB_MIS_ESFERAS)
					return
				
				# Confirmación de equipamiento de skill
				if inv_main.get("pending_skill_to_equip") != null:
					var skill = inv_main.pending_skill_to_equip
					# Validación de requisitos de la habilidad
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
					inv_main.selected_sphere_slot = i
					inv_main.selected_sphere_type_filter = "ANY"
					_switch_subtab(sub_tabs, SUB_TAB_BIBLIOTECA)
		)
		
		# Efecto visual "Esperando Selección" — resaltar slots cuando hay ítem o skill pendiente
		if inv_main.get("pending_skill_to_equip") != null and not slot_locked:
			var tween = create_tween().set_loops()
			if is_instance_valid(sk_sb):
				tween.tween_property(sk_sb, "border_color", Color.WHITE, 0.3)
				tween.tween_property(sk_sb, "border_color", Color(0.3, 0.8, 1.0), 0.3)
		elif inv_main.get("pending_sphere_item") != null and not slot_locked:
			var tween2 = create_tween().set_loops()
			if is_instance_valid(sp_sb):
				tween2.tween_property(sp_sb, "border_color", Color.WHITE, 0.3)
				tween2.tween_property(sp_sb, "border_color", Color.YELLOW, 0.3)
		
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
		banner.text = ">> SELECCIONA LA ESFERA A INSTALAR EN " + slot_name
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
	summary.text = "INSTALADAS: %d/4  -  EN BODEGA: %d" % [installed_total, owned.size()]
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
		c_lbl.text = _color_label(key) + ": " + str(inst) + " eq / " + str(own) + " bodega"
		c_lbl.modulate = _color_to_rgb(key)
		c_lbl.add_theme_font_size_override("font_size", 10)
		color_h.add_child(c_lbl)
	
	main_v.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = 3; main_v.add_child(scroll)
	var grid = GridContainer.new(); grid.columns = 3; grid.size_flags_horizontal = 3; grid.add_theme_constant_override("h_separation", 15); grid.add_theme_constant_override("v_separation", 15); scroll.add_child(grid)
	
	if owned.is_empty():
		var empty_v = VBoxContainer.new(); grid.add_child(empty_v)
		var empty_lbl = Label.new()
		empty_lbl.text = "NO TENES ESFERAS EN LA BODEGA.\n\nFabricalas en la pestaña CRAFTEO:\n- Esfera Roja (ATAQUE)\n- Esfera Azul (DEFENSA)\n- Esfera Verde (CURACION)\n- Esfera Amarilla (UTILIDAD)"
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
		warn.text = "[!] SISTEMA BLOQUEADO: EN COMBATE"
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
		var sp_item_tex = InventoryCache.get_texture(icon_path)
		tex_rect.texture = sp_item_tex if sp_item_tex else load(icon_path)
		tex_rect.custom_minimum_size = Vector2(80, 80)
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
			var sm = inv_main.spheres_manager
			var target_slot_id = -1
			
			# Si el jugador ya había seleccionado un slot específico desde SISTEMA ORBITAL
			if inv_main.get("pending_sphere_slot") != null and int(inv_main.pending_sphere_slot) >= 0:
				target_slot_id = int(inv_main.pending_sphere_slot)
				
			if target_slot_id >= 0:
				var slot_id = target_slot_id
				var slot_locked = false
				var slot_req_msg = ""
				if NetworkManager:
					var sc = NetworkManager.check_sphere_slot_requirements(slot_id)
					slot_locked = not sc.get("ok", true)
					slot_req_msg = str(sc.get("msg", ""))
				if slot_locked:
					NetworkManager.game_notification.emit({
						"msg": "SLOT BLOQUEADO: " + slot_req_msg,
						"type": "error"
					})
					return
				
				var has_prev = is_instance_valid(sm) and sm.has_installed_sphere(slot_id)
				var action_txt = "reemplazar por" if has_prev else "instalar"
				var note_txt = " La esfera anterior volverá a tu bodega." if has_prev else " Se consumirá el ítem de tu inventario."
				
				inv_main._show_modal("INSTALAR ESFERA", "¿Deseas " + action_txt + " [color=yellow]" + str(item.get("name", "ESFERA")) + "[/color] en el " + str(sm.spheres_data[slot_id].get("name", "SLOT")) + "?" + note_txt, func():
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
					_switch_subtab(sub_tabs, SUB_TAB_ORBITAL)
				)
			else:
				# Selector interactivo de ranura (Slot 1, 2, 3 o 4)
				_show_slot_picker("INSTALAR ESFERA", item, true, func(chosen_slot):
					var has_prev = is_instance_valid(sm) and sm.has_installed_sphere(chosen_slot)
					var action_txt = "reemplazar por" if has_prev else "instalar"
					var note_txt = " La esfera anterior volverá a tu bodega." if has_prev else " Se consumirá el ítem de tu inventario."
					
					inv_main._show_modal("INSTALAR ESFERA", "¿Deseas " + action_txt + " [color=yellow]" + str(item.get("name", "ESFERA")) + "[/color] en el " + str(sm.spheres_data[chosen_slot].get("name", "SLOT")) + "?" + note_txt, func():
						NetworkManager.send_event("equipSphereItem", {"sphereId": chosen_slot, "instanceId": str(item.get("instanceId", ""))})
						if is_instance_valid(sm):
							sm.install_sphere(chosen_slot, {
								"id": item.get("id", ""),
								"name": item.get("name", "Esfera"),
								"type": key,
								"color": item.get("color", ""),
								"icon": item.get("icon", ""),
								"instanceId": str(item.get("instanceId", ""))
							})
						inv_main.pending_sphere_slot = -1
						_switch_subtab(sub_tabs, SUB_TAB_ORBITAL)
					)
				)
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
	
	# Banner superior cuando el usuario seleccionó un slot específico desde SISTEMA ORBITAL
	if inv_main.get("selected_sphere_slot") != null and int(inv_main.selected_sphere_slot) >= 0:
		var slot_num = int(inv_main.selected_sphere_slot) + 1
		var banner_panel = PanelContainer.new()
		var b_sb = StyleBoxFlat.new()
		b_sb.bg_color = Color(0.04, 0.16, 0.28, 0.9)
		b_sb.border_width_left = 4
		b_sb.border_color = Color.CYAN
		b_sb.set_corner_radius_all(6)
		banner_panel.add_theme_stylebox_override("panel", b_sb)
		
		var bh = HBoxContainer.new()
		bh.alignment = BoxContainer.ALIGNMENT_CENTER
		bh.add_theme_constant_override("separation", 20)
		banner_panel.add_child(bh)
		
		var b_lbl = Label.new()
		b_lbl.text = ">> EQUIPANDO EN: SLOT " + str(slot_num) + " (Haz click en EQUIPAR en cualquier habilidad para asignarla aquí)"
		b_lbl.modulate = Color.CYAN
		b_lbl.add_theme_font_size_override("font_size", 11)
		bh.add_child(b_lbl)
		
		var b_cancel = Button.new()
		b_cancel.text = "CANCELAR SELECCIÓN"
		b_cancel.add_theme_font_size_override("font_size", 9)
		b_cancel.pressed.connect(func():
			inv_main.selected_sphere_slot = -1
			update_ui()
		)
		bh.add_child(b_cancel)
		main_v.add_child(banner_panel)
		main_v.add_child(HSeparator.new())
	
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
		if not _skill_type_matches_filter(s_info["type"], inv_main.selected_sphere_type_filter): continue
		var s_inst = s_info["instance"]
		_create_skill_card(s_inst, s_info["color"], s_info["icon"], s_info.get("tex_icon"), grid, is_equipped_check_if_already_exists(s_inst.skill_name, currently_equipped), is_comb, sub_tabs)

func is_equipped_check_if_already_exists(s_name: String, currently_equipped: Array) -> bool:
	for eq in currently_equipped:
		if eq == s_name:
			return true
	return false

func _create_skill_card(skill, color, icon_text, tex_icon: Texture2D, parent, is_equipped, is_comb = false, sub_tabs = null):
	var skill_card = PanelContainer.new(); skill_card.custom_minimum_size = Vector2(380, 140); parent.add_child(skill_card)
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0.05, 0.7); sb.border_width_left = 4; sb.border_color = color; sb.corner_radius_top_right = 8; sb.corner_radius_bottom_right = 8; skill_card.add_theme_stylebox_override("panel", sb)
	
	var hb = HBoxContainer.new(); hb.offset_left = 15; skill_card.add_child(hb)
	var icon_box = CenterContainer.new(); icon_box.custom_minimum_size = Vector2(120, 0); hb.add_child(icon_box)
	
	# v301.4: Mostrar TextureRect con PNG si existe, sino Label con emoji como fallback
	if tex_icon:
		var icon_rect = TextureRect.new()
		icon_rect.texture = tex_icon
		icon_rect.custom_minimum_size = Vector2(110, 110)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.modulate = color
		icon_box.add_child(icon_rect)
	else:
		var ico = Label.new(); ico.text = icon_text; ico.add_theme_font_size_override("font_size", 72); ico.modulate = color; icon_box.add_child(ico)
	
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
	
	# Requisitos de equipamiento de habilidades (nivel / quest / build)
	var req_msg = ""
	var req_ok = true
	if NetworkManager and not is_equipped:
		var req_check = NetworkManager.check_equip_requirements("", skill.skill_name)
		req_ok = req_check.get("ok", true)
		req_msg = str(req_check.get("msg", ""))
	
	if not req_ok and not is_equipped:
		b_equip.disabled = true
		b_equip.modulate = Color(1, 0.4, 0.4)
		var req_lbl = Label.new()
		req_lbl.text = "[BLOQUEADO] " + req_msg
		req_lbl.add_theme_font_size_override("font_size", 8)
		req_lbl.modulate = Color(1, 0.35, 0.35)
		v_info.add_child(req_lbl)
		skill_card.modulate.a = 0.55

	# v760.4: Requisito de tener la esfera del color correspondiente (en slots o bodega)
	var req_sphere_color: String = _sphere_color_for_type(str(skill.type))
	var has_sphere_owned: bool = _player_owns_sphere_color(req_sphere_color)
	if not has_sphere_owned and not is_equipped:
		b_equip.disabled = true
		b_equip.modulate = Color(1, 0.4, 0.4)
		var sp_req_lbl = Label.new()
		sp_req_lbl.text = "[REQUIERE ESFERA " + _color_label(req_sphere_color) + "]\n(No posees esta esfera. Fabrícala en CRAFTEO)"
		sp_req_lbl.add_theme_font_size_override("font_size", 8)
		sp_req_lbl.modulate = _color_to_rgb(req_sphere_color)
		sp_req_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v_info.add_child(sp_req_lbl)
		skill_card.modulate.a = 0.55

	if is_equipped: skill_card.modulate.a = 0.5
	elif is_comb: skill_card.modulate.a = 0.6
	
	b_equip.pressed.connect(func():
		# Validación local de requisitos de nivel/quest
		if NetworkManager:
			var req_check = NetworkManager.check_equip_requirements("", skill.skill_name)
			if not req_check.get("ok", true):
				NetworkManager.game_notification.emit({
					"msg": "HABILIDAD BLOQUEADA: " + str(req_check.get("msg", "Requisitos no cumplidos")),
					"type": "error"
				})
				return
		
		# Validación de posesión de esfera del color requerido
		if not _player_owns_sphere_color(req_sphere_color):
			if NetworkManager:
				NetworkManager.game_notification.emit({
					"msg": "REQUIERE ESFERA " + _color_label(req_sphere_color) + ". Fabrícala en CRAFTEO.",
					"type": "error"
				})
			return
		
		var sm = inv_main.spheres_manager
		
		# Opción A: El jugador seleccionó un slot específico de antemano (desde SISTEMA ORBITAL)
		if inv_main.get("selected_sphere_slot") != null and int(inv_main.selected_sphere_slot) >= 0:
			var slot_id = int(inv_main.selected_sphere_slot)
			if NetworkManager:
				var sc = NetworkManager.check_sphere_slot_requirements(slot_id)
				if not sc.get("ok", true):
					NetworkManager.game_notification.emit({
						"msg": "SLOT BLOQUEADO: " + str(sc.get("msg", "Requisitos no cumplidos")),
						"type": "error"
					})
					return
			
			_sync_sphere_swap(slot_id, req_sphere_color)
			NetworkManager.send_event("equipSphere", {"sphereId": slot_id, "skill": {"skill_name": skill.skill_name, "power_value": skill.power_value, "type": skill.type}})
			if is_instance_valid(sm): 
				sm.equip_item(slot_id, skill)
			inv_main.selected_sphere_slot = -1
			inv_main.pending_skill_to_equip = null
			
			if NetworkManager:
				NetworkManager.game_notification.emit({
					"msg": "HABILIDAD EQUIPADA EN SLOT " + str(slot_id + 1),
					"type": "success"
				})
			_switch_subtab(sub_tabs, SUB_TAB_ORBITAL)
		else:
			# Opción B: No seleccionó slot de antemano -> Selector libre de slots (Slot 1, 2, 3 o 4)
			_show_slot_picker("EQUIPAR HABILIDAD", skill, false, func(chosen_slot):
				_sync_sphere_swap(chosen_slot, req_sphere_color)
				NetworkManager.send_event("equipSphere", {"sphereId": chosen_slot, "skill": {"skill_name": skill.skill_name, "power_value": skill.power_value, "type": skill.type}})
				if is_instance_valid(sm): 
					sm.equip_item(chosen_slot, skill)
				inv_main.selected_sphere_slot = -1
				inv_main.pending_skill_to_equip = null
				
				if NetworkManager:
					NetworkManager.game_notification.emit({
						"msg": "HABILIDAD EQUIPADA EN SLOT " + str(chosen_slot + 1),
						"type": "success"
					})
				_switch_subtab(sub_tabs, SUB_TAB_ORBITAL)
			)
	)
