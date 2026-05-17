extends Control

# SkillsHUD.gd (v1.0 - Componente de Habilidades)

var _ammo_nodes = {}
var _ammo_menus = {}
var _max_cds = {}
var _touch_registry = {}
var _is_interference_ui_active = false

var s1 = null
var s2 = null
var s3 = null
var s4 = null

var sl = null
var smi = null
var sei = null

func _ready():
	print("[SkillsHUD] Iniciando componente modular.")
	
	s1 = get_node_or_null("Sphere1Slot")
	s2 = get_node_or_null("Sphere2Slot")
	s3 = get_node_or_null("Sphere3Slot")
	s4 = get_node_or_null("Sphere4Slot")
	
	sl = get_node_or_null("LaserSlot")
	smi = get_node_or_null("MissileSlot")
	sei = get_node_or_null("MineSlot")
	
	# v230.10: Inyección dinámica del 4to slot si no existe en la escena
	if not s4 and s3:
		s4 = s3.duplicate()
		s4.name = "Sphere4Slot"
		s3.get_parent().add_child(s4)
		if not s3.get_parent() is BoxContainer:
			s4.position = s3.position + Vector2(s3.size.x + 10, 0)
		
		for child in s4.find_children("*", "Label", true, false):
			if child.text == "CUR" or child.text == "MOV" or child.text == "DEF":
				child.text = "ATQ"
			if child.text == "D" or child.text == "A" or child.text == "S":
				child.text = "R"
		print("[SkillsHUD] Sphere4Slot inyectado dinámicamente.")

	if s1: _make_clickable(s1, _on_sphere_slot_gui_input.bind(null, 0))
	if s2: _make_clickable(s2, _on_sphere_slot_gui_input.bind(null, 1))
	if s3: _make_clickable(s3, _on_sphere_slot_gui_input.bind(null, 2))
	if s4: _make_clickable(s4, _on_sphere_slot_gui_input.bind(null, 3))
	
	if sl: _make_clickable(sl, _on_base_slot_gui_input.bind(null, "laser"))
	if smi: _make_clickable(smi, _on_base_slot_gui_input.bind(null, "missile"))
	if sei: _make_clickable(sei, _on_base_slot_gui_input.bind(null, "mine"))
	
	_ammo_nodes["laser"] = get_node_or_null("LaserSlot/ammo-q")
	_ammo_nodes["missile"] = get_node_or_null("MissileSlot/ammo-w")
	_ammo_nodes["mine"] = get_node_or_null("MineSlot/ammo-e")

	if NetworkManager:
		if not NetworkManager.interference_event.is_connected(_on_interference_event):
			NetworkManager.interference_event.connect(_on_interference_event)
			
	set_process(true)

func _process(_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		return
	
	_handle_ammo_selector()
	
	_update_skill_ui("laser", p_node, get_node_or_null("LaserSlot"))
	_update_skill_ui("missile", p_node, get_node_or_null("MissileSlot"))
	_update_skill_ui("mine", p_node, get_node_or_null("MineSlot"))
	
	_update_sphere_ui(0, p_node, get_node_or_null("Sphere1Slot"))
	_update_sphere_ui(1, p_node, get_node_or_null("Sphere2Slot"))
	_update_sphere_ui(2, p_node, get_node_or_null("Sphere3Slot"))
	_update_sphere_ui(3, p_node, get_node_or_null("Sphere4Slot"))
	
	_sync_hud_keys()
	
	# Efecto Glitch en slots si hay interferencia
	if _is_interference_ui_active:
		for slot in find_children("*Slot", "Control", true, false):
			if not slot.has_meta("orig_pos"): slot.set_meta("orig_pos", slot.position)
			var op = slot.get_meta("orig_pos")
			
			slot.position = op + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
			slot.modulate.a = randf_range(0.6, 0.9)
	else:
		for slot in find_children("*Slot", "Control", true, false):
			if slot.has_meta("orig_pos"):
				slot.position = slot.get_meta("orig_pos")
				slot.modulate.a = 1.0
				slot.remove_meta("orig_pos")

func _on_interference_event(data: Dictionary):
	var duration = data.get("duration", 4000.0) / 1000.0
	set_interference_mode(true)
	await get_tree().create_timer(duration).timeout
	set_interference_mode(false)

func set_interference_mode(p_active: bool):
	_is_interference_ui_active = p_active
	for slot in find_children("*Slot", "Control", true, false):
		if p_active:
			slot.modulate = Color(1.0, 0.3, 0.3, 0.8) # Rojo Interferencia
		else:
			slot.modulate = Color(1, 1, 1, slot.modulate.a)

func _handle_ammo_selector():
	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	var is_ctrl = Input.is_key_pressed(KEY_CTRL)
	if is_ctrl:
		if _ammo_menus.is_empty():
			_create_ammo_menu()
		_toggle_ammo_menu(true)
	else:
		if not _ammo_menus.is_empty():
			_toggle_ammo_menu(false)

func _toggle_ammo_menu(p_show: bool):
	for type in _ammo_menus:
		var m = _ammo_menus[type]
		if is_instance_valid(m):
			m.visible = p_show
	
	if p_show:
		_update_ammo_menu_selection()

func _create_ammo_menu():
	var types = {
		"laser": {"path": "LaserSlot", "count": 6},
		"missile": {"path": "MissileSlot", "count": 3},
		"mine": {"path": "MineSlot", "count": 3}
	}
	
	for t in types:
		var slot_node = get_node_or_null(types[t].path)
		if not slot_node: continue
		
		var old = slot_node.get_node_or_null("AmmoMenu_" + t)
		if old: old.queue_free()

		var menu = VBoxContainer.new()
		menu.name = "AmmoMenu_" + t
		slot_node.add_child(menu)
		_ammo_menus[t] = menu
		
		menu.z_index = 150
		menu.z_as_relative = false
		menu.add_theme_constant_override("separation", 5)
		menu.visible = false
		
		for i in range(types[t].count - 1, -1, -1):
			var slot_p = PanelContainer.new()
			slot_p.custom_minimum_size = Vector2(40, 40)
			slot_p.mouse_filter = Control.MOUSE_FILTER_STOP
			
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0.9)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1, 0.1)
			slot_p.add_theme_stylebox_override("panel", sb)
			
			var lbl = Label.new()
			lbl.text = "T" + str(i+1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 12)
			slot_p.add_child(lbl)
			
			slot_p.gui_input.connect(_on_ammo_slot_clicked.bind(t, i))
			menu.add_child(slot_p)
		
		menu.size = menu.get_combined_minimum_size()
		var slot_width = 64 
		if slot_node is Control: slot_width = slot_node.size.x
		menu.position = Vector2((slot_width/2) - (menu.get_combined_minimum_size().x / 2), -menu.get_combined_minimum_size().y - 10)

func _update_ammo_menu_selection():
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p): return
	
	var sel_data = p.get("selected_ammo")
	if sel_data == null: sel_data = {}
	
	for type in _ammo_menus:
		var menu = _ammo_menus[type]
		var current_sel = sel_data.get(type, 0)
		
		var count = menu.get_child_count()
		for i in range(count):
			var slot = menu.get_child(i)
			var tier_index = count - 1 - i 
			
			var sb = slot.get_theme_stylebox("panel").duplicate()
			if tier_index == current_sel:
				sb.border_color = Color.CYAN
				sb.set_border_width_all(2)
				slot.modulate = Color(1.2, 1.2, 1.2, 1)
			else:
				sb.border_color = Color(1, 1, 1, 0.1)
				sb.set_border_width_all(1)
				slot.modulate = Color(0.7, 0.7, 0.7, 0.8)
			slot.add_theme_stylebox_override("panel", sb)

func _on_ammo_slot_clicked(event: InputEvent, type: String, tier: int):
	if event is InputEventMouseButton and event.pressed:
		var p = get_tree().get_first_node_in_group("player")
		if p and p.has_method("change_ammo"): 
			p.change_ammo(type, tier)
			_update_ammo_menu_selection()
			AudioManager.play_sfx("ui_click")

func _sync_hud_keys():
	var all_slots = find_children("*Slot", "Control", true, false)
	var slot_to_action = {
		"LaserSlot": "slot_1", "MissileSlot": "slot_2", "MineSlot": "slot_3",
		"Sphere1Slot": "slot_4", "Sphere2Slot": "slot_5", 
		"Sphere3Slot": "slot_6", "Sphere4Slot": "slot_7"
	}

	for slot in all_slots:
		var action = slot_to_action.get(slot.name, "")
		if action == "": continue
		
		var lbl = slot.get_node_or_null("BindingLabel")
		if not is_instance_valid(lbl):
			lbl = Label.new()
			lbl.name = "BindingLabel"
			lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.offset_top = 8 
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color.CYAN)
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_constant_override("outline_size", 4)
			slot.add_child(lbl)
			
		if is_instance_valid(lbl):
			var evs = InputMap.action_get_events(action)
			if evs.size() > 0:
				var txt = evs[0].as_text().replace(" (Physical)", "").replace(" - Physical", "")
				if txt.begins_with("Mouse Button"): txt = "M" + txt.replace("Mouse Button ", "")
				lbl.text = txt.to_upper()
			else:
				lbl.text = "-"
			
			slot.move_child(lbl, slot.get_child_count() - 1)
			lbl.visible = true
		
		for child in slot.get_children():
			if child is Label and child.name != "BindingLabel" and child.name != "CD":
				if child.name == "Key":
					child.visible = false
					continue
				child.visible = true
				if child.name != "ammo-q" and child.name != "ammo-w" and child.name != "ammo-e":
					child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					child.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
					child.grow_horizontal = Control.GROW_DIRECTION_BOTH

func _format_val(v):
	var s = str(int(v))
	var r = ""
	var c = 0
	for i in range(s.length()-1,-1,-1):
		r = s[i] + r
		c += 1
		if c == 3 and i != 0:
			r = "." + r
			c = 0
	return r

func _update_skill_ui(type: String, ref, slot):
	if not slot: return
	var l_fill = slot.get_node_or_null("Fill")
	var l_cd = slot.get_node_or_null("CD")
	var l_am = _ammo_nodes.get(type)
	
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(type, 0.0)
	
	if l_fill:
		if not _max_cds.has(type) or rv > _max_cds[type]:
			_max_cds[type] = max(rv, 0.5)
		if rv < 0.01:
			_max_cds[type] = lerp(_max_cds[type], 0.5, 0.01)

		var max_cd = _max_cds[type]
		var pct = clamp(rv / max_cd, 0.0, 1.0)
		
		var parent_h = slot.size.y if slot.size.y > 0 else 65.0
		var parent_w = slot.size.x if slot.size.x > 0 else 65.0
		
		l_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_fill.size = Vector2(parent_w, parent_h * pct)
		l_fill.position = Vector2(0, parent_h * (1.0 - pct))
		l_fill.visible = rv > 0.02
	
	if l_cd:
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1)) + "s"
			
	if l_am and ref.get("ammo") != null:
		var a_list = ref.get("ammo").get(type, [0,0,0,0,0,0])
		var sel_data = ref.get("selected_ammo")
		var sel = sel_data.get(type, 0) if sel_data != null else 0
		var a_count = a_list[sel] if a_list.size() > sel else 0
		l_am.text = "T" + str(int(sel + 1)) + ": " + _format_val(a_count)
		l_am.modulate = Color(1.0, 1.0, 0.0) 
		l_am.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		l_am.offset_bottom = -5 
		l_am.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_am.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l_am.add_theme_font_size_override("font_size", 10)
		l_am.visible = true

func _update_sphere_ui(id: int, ref, slot):
	if not slot: return
	var p_size = slot.size if slot.size.y > 0 else Vector2(65, 65)
	var l_fill = slot.get_node_or_null("Fill")
	
	var key = "sphere_" + str(id)
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(key, 0.0)
	
	if l_fill:
		if not _max_cds.has(key) or rv > _max_cds[key]:
			_max_cds[key] = max(rv, 1.0)
		
		var max_cd = _max_cds[key]
		var pct = clamp(rv / max_cd, 0.0, 1.0)
		
		l_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_fill.size = Vector2(p_size.x, p_size.y * pct)
		l_fill.position = Vector2(0, p_size.y * (1.0 - pct))
		l_fill.visible = rv > 0.05
	
	var l_cd = slot.get_node_or_null("CD")
	if not l_cd:
		l_cd = Label.new()
		l_cd.name = "CD"
		l_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l_cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_cd.add_theme_color_override("font_color", Color.RED)
		l_cd.add_theme_font_size_override("font_size", 12)
		slot.add_child(l_cd)
	
	if is_instance_valid(l_cd):
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1)) + "s"
		l_cd.modulate = Color.RED
	
	var type_color = Color.WHITE
	var sm = ref.get_node_or_null("SpheresManager")
	var equipped = false
	
	if is_instance_valid(sm) and sm.spheres_data.size() > id:
		var skill = sm.spheres_data[id]["equipped"]
		equipped = skill != null
		if skill:
			var raw_type = "ataque"
			if typeof(skill) == TYPE_DICTIONARY: raw_type = str(skill.get("type", "ataque")).to_lower()
			else: raw_type = str(skill.get("type")).to_lower() if skill.get("type") else "ataque"
			
			if "ataque" in raw_type: type_color = Color.RED
			elif "defensa" in raw_type: type_color = Color.AQUA
			elif "curación" in raw_type or "curacion" in raw_type: type_color = Color.GREEN
			elif "utilidad" in raw_type or "movimiento" in raw_type: type_color = Color.YELLOW
			else: type_color = Color.WHITE
	
	var final_text_color = Color.RED if rv > 0.05 else type_color
	slot.modulate = Color(1, 1, 1, slot.modulate.a) 
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6) if equipped else Color(0, 0, 0, 0.2)
	sb.draw_center = true
	sb.border_width_left = 2; sb.border_width_right = 2; sb.border_width_top = 2; sb.border_width_bottom = 2
	sb.border_color = Color.AQUA if equipped else Color(0.2, 0.2, 0.2, 0.5)
	sb.set_corner_radius_all(p_size.x) 
	sb.set_content_margin_all(2)
	sb.anti_aliasing = true
	
	if slot.has_method("add_theme_stylebox_override"):
		slot.add_theme_stylebox_override("normal", sb)
		slot.add_theme_stylebox_override("hover", sb)
		slot.add_theme_stylebox_override("pressed", sb)
		slot.add_theme_stylebox_override("disabled", sb)
		if slot is PanelContainer:
			slot.add_theme_stylebox_override("panel", sb)
	
	var short_txt = "VACÍO"
	if equipped:
		if type_color == Color.RED: short_txt = "ATQ"
		elif type_color == Color.AQUA: short_txt = "DEF"
		elif type_color == Color.GREEN: short_txt = "CUR"
		elif type_color == Color.YELLOW: short_txt = "UTIL"

	for child in slot.get_children():
		if child is Label:
			if child.name == "CD":
				child.modulate = Color.RED
				child.add_theme_color_override("font_color", Color.RED)
			elif child.name == "Key":
				pass
			else:
				child.text = short_txt
				child.add_theme_color_override("font_color", final_text_color) 
				child.modulate.a = 1.0 if equipped else 0.3

func _make_clickable(node: Control, callback: Callable):
	if not node: return
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var btn = node.get_node_or_null("TouchButton")
	if not btn:
		btn = Button.new()
		btn.name = "TouchButton"
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.modulate.a = 0 
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		node.add_child(btn)
		node.move_child(btn, 0)
		
		var aim_bg = Panel.new()
		aim_bg.name = "AimIndicatorBG"
		aim_bg.size = Vector2(160, 160)
		aim_bg.position = (node.size / 2) - Vector2(80, 80)
		aim_bg.visible = false
		aim_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = Color(0, 0.5, 1, 0.1)
		style_bg.set_border_width_all(2); style_bg.border_color = Color(0, 0.5, 1, 0.3)
		style_bg.set_corner_radius_all(80)
		aim_bg.add_theme_stylebox_override("panel", style_bg)
		node.add_child(aim_bg)
		
		var aim = Panel.new()
		aim.name = "AimIndicator"
		aim.size = Vector2(40, 40)
		aim.position = (node.size / 2) - Vector2(20, 20)
		aim.visible = false
		aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var style_aim = StyleBoxFlat.new()
		style_aim.bg_color = Color(0, 0.8, 1, 0.4)
		style_aim.set_border_width_all(2); style_aim.border_color = Color(0, 0.8, 1, 0.9)
		style_aim.set_corner_radius_all(20)
		aim.add_theme_stylebox_override("panel", style_aim)
		node.add_child(aim)
	
	btn.gui_input.connect(_on_touch_button_input.bind(node, callback))
	_touch_registry[node] = callback

func _on_sphere_slot_gui_input(event: InputEvent, id: int):
	if event == null: 
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p): p.trigger_skill_by_id("sphere_" + str(id))
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p.has_method("trigger_skill_by_id"):
			if event.pressed:
				var s_id = "sphere_" + str(id)
				p.trigger_skill_by_id(s_id)
			else:
				var sc = p._skill_controller
				if is_instance_valid(sc) and sc.is_aiming:
					if sc.config.get("cast_mode") == 1:
						sc.execute_skill(true)

func _on_base_slot_gui_input(event: InputEvent, skill_id: String):
	if event == null: 
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p): p.trigger_skill_by_id(skill_id)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p = get_tree().get_first_node_in_group("player")
		if is_instance_valid(p):
			if event.pressed:
				p.trigger_skill_by_id(skill_id)
			else:
				var sc = p._skill_controller
				if is_instance_valid(sc) and sc.is_aiming:
					if sc.config.get("cast_mode") == 1:
						sc.execute_skill()

func _on_touch_button_input(event: InputEvent, node: Control, callback: Callable):
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p) or not p._skill_controller: return
	var sc = p._skill_controller
	var aim = node.get_node_or_null("AimIndicator")
	var aim_bg = node.get_node_or_null("AimIndicatorBG")
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	
	# PRESS
	var is_press = (event is InputEventScreenTouch and event.pressed) or \
				   (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_press:
		var g_pos = event.position
		node.set_meta("touch_index", event.index if event is InputEventScreenTouch else 0)
		node.set_meta("touch_origin_global", g_pos)
		callback.call()
		
		if is_mobile:
			if aim_bg:
				aim_bg.visible = true
				aim_bg.global_position = g_pos - (aim_bg.size / 2)
			if aim:
				aim.visible = true
				aim.global_position = g_pos - (aim.size / 2)
		
		get_viewport().set_input_as_handled()
		return

	# RELEASE
	var is_release = (event is InputEventScreenTouch and not event.pressed) or \
					 (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_release:
		var stored_index = node.get_meta("touch_index", -1)
		if event is InputEventScreenTouch and event.index != stored_index: return
		
		if aim: aim.visible = false
		if aim_bg: aim_bg.visible = false
		
		if sc.is_aiming:
			if is_mobile or sc.config.get("cast_mode") == 1:
				sc.execute_skill()
		
		sc.external_aim_vector = Vector2.ZERO
		node.remove_meta("touch_index")
		node.remove_meta("touch_origin_global")
		return

	# DRAG
	if not is_mobile or not sc.is_aiming: return
	
	var is_drag = (event is InputEventScreenDrag) or \
				  (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if not is_drag: return
	
	if event is InputEventScreenDrag:
		if event.index != node.get_meta("touch_index", -1): return
	
	var g_origin = node.get_meta("touch_origin_global", event.position)
	var diff_global = event.position - g_origin
	
	var cam = get_viewport().get_camera_2d()
	var zoom_val = cam.zoom.x if cam else 1.0
	var world_diff = diff_global / zoom_val
	
	var max_range = sc.current_skill.get("range", 500.0)
	var sensitivity = SettingsManager.mobile_aim_sensitivity
	
	if max_range <= 0:
		sc.external_aim_vector = world_diff if world_diff.length() > 5 else Vector2.ZERO
	else:
		var px_for_max = 80.0 / sensitivity
		var mapped_range = clamp(world_diff.length() * max_range / px_for_max, 10.0, max_range)
		sc.external_aim_vector = world_diff.normalized() * mapped_range if world_diff.length() > 5 else Vector2.ZERO
	
	if aim:
		aim.visible = true
		aim.global_position = event.position - (aim.size / 2)
	if aim_bg:
		aim_bg.visible = true
		aim_bg.global_position = g_origin - (aim_bg.size / 2)
	
	get_viewport().set_input_as_handled()
