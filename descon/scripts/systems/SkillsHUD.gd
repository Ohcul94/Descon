extends Control

# SkillsHUD.gd (v1.0 - Componente de Habilidades)

var _ammo_nodes = {}
var _max_cds = {}
var _touch_registry = {}
var _is_interference_ui_active = false
var _cooldown_fill_shader: Shader = null

# Apuntado MOBA: el drag se sigue a nivel HUD (no del botón) para que
# funcione aunque el dedo salga del rectángulo chiquito del slot.
var _aim_drag_active: bool = false
var _aim_touch_index: int = -1
var _aim_origin_vp: Vector2 = Vector2.ZERO
var _aim_node: Control = null

# v301.4: Cache de texturas de íconos para no recargar desde disco en cada frame
var _skill_icon_cache: Dictionary = {}

# Iconos de munición (estilo skill icons) — 1 por tipo, compartido entre tiers
var _ammo_icon_cache: Dictionary = {}
var _ammo_icon_paths: Dictionary = {
	"laser": "res://assets/Municiones/Iconos/laser/Laser.png",
	"missile": "res://assets/Municiones/Iconos/missile/Missile.png",
	"mine": "res://assets/Municiones/Iconos/mine/Mine.png",
	"siphon": "res://assets/Municiones/Iconos/siphon/Siphon.png",
	"emp": "res://assets/Municiones/Iconos/emp/Emp.png",
	"electron": "res://assets/Municiones/Iconos/electron/Electron.png",
	"melee": "res://assets/Municiones/Iconos/melee/Melee.png",
	"heal": "res://assets/Municiones/Iconos/heal/Heal.png",
}

var _skill_icon_paths: Dictionary = {
	"BLINK": "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
	"TURBO-IMPULSO": "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png",
	"HYPER-DASH": "res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png",
	"INVULNERABILIDAD": "res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png",
	"STEALTH": "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
	"RESURRECCION": "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
	"REFLECT-OMEGA": "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
	"ESFERA DE TERROR": "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
	"PROVOCACION": "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
	"HOOKSHOT": "res://assets/Skills/Iconos/Ataque/Hookshot/Hookshot.png",

	"VINCULO VITAL": "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
	"REGENERACION ALFA": "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
	"BALIZA DE CURACION": "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
	"AUTO-REPARACION": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"NANO-REGENERACION": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"ESCUDO CELULAR": "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png",
	"SMOKE-BOMB": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"FROST-TRAIL": "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
	"BARRERA DE VIENTO": "res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png",
}

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
			child.text = ""
		print("[SkillsHUD] Sphere4Slot inyectado dinámicamente.")

	if s1: _make_clickable(s1, _on_sphere_slot_gui_input.bind(null, 0))
	if s2: _make_clickable(s2, _on_sphere_slot_gui_input.bind(null, 1))
	if s3: _make_clickable(s3, _on_sphere_slot_gui_input.bind(null, 2))
	if s4: _make_clickable(s4, _on_sphere_slot_gui_input.bind(null, 3))
	
	if sl: _make_clickable(sl, _on_base_slot_gui_input.bind(null, 0))
	if smi: _make_clickable(smi, _on_base_slot_gui_input.bind(null, 1))
	if sei: _make_clickable(sei, _on_base_slot_gui_input.bind(null, 2))
	
	_ammo_nodes[0] = get_node_or_null("LaserSlot/ammo-q")
	_ammo_nodes[1] = get_node_or_null("MissileSlot/ammo-w")
	_ammo_nodes[2] = get_node_or_null("MineSlot/ammo-e")
	for idx in _ammo_nodes:
		if is_instance_valid(_ammo_nodes[idx]): _ammo_nodes[idx].visible = false

	if NetworkManager:
		if not NetworkManager.interference_event.is_connected(_on_interference_event):
			NetworkManager.interference_event.connect(_on_interference_event)
		if NetworkManager.config_updated.is_connected(_on_config_updated):
			NetworkManager.config_updated.disconnect(_on_config_updated)
		NetworkManager.config_updated.connect(_on_config_updated)
			
	_ensure_ammo_popup()
	set_process(true)

func _process(_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		return
	
	# Monitoreo de hover de 2 segundos para desplegar popup arriba del cuadrito
	if is_instance_valid(_current_hover_slot):
		var btn = _current_hover_slot.get_node_or_null("TouchButton") as Button
		var is_hovering = false
		if is_instance_valid(btn):
			is_hovering = btn.is_hovered()
		else:
			is_hovering = _current_hover_slot.get_global_rect().has_point(_current_hover_slot.get_global_mouse_position())
		
		if not is_hovering:
			_on_slot_mouse_exited(_current_hover_slot)
		else:
			if not _hover_triggered:
				_hover_timer += _delta
				if _hover_timer >= 2.0:
					_hover_triggered = true
					_show_ammo_popup_for_slot(_current_hover_slot)

	_update_skill_ui(0, p_node, get_node_or_null("LaserSlot"))
	_update_skill_ui(1, p_node, get_node_or_null("MissileSlot"))
	_update_skill_ui(2, p_node, get_node_or_null("MineSlot"))
	
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
			lbl.add_theme_color_override("font_color", Color.WHITE)
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
		
		# ¿Hay icono de munición visible? Si sí, el label de tipo "Label" queda oculto
		var ammo_icon = slot.get_node_or_null("AmmoIconRect") as TextureRect
		var has_ammo_icon = is_instance_valid(ammo_icon) and ammo_icon.visible and ammo_icon.texture != null

		for child in slot.get_children():
			if child is Label and child.name != "BindingLabel" and child.name != "CD":
				if child.name == "Key" or child.name == "ammo-q" or child.name == "ammo-w" or child.name == "ammo-e":
					child.visible = false
					continue
				# El label central de tipo de munición se oculta si hay icono
				if child.name == "Label" and has_ammo_icon:
					child.visible = false
					continue
				child.visible = true
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

func _fmt_time_ms(v) -> String:
	var sec = float(v) / 1000.0
	return _fmt_num(sec) + "s"

func _fmt_num(v) -> String:
	var f = float(v)
	if abs(f - round(f)) < 0.0001:
		return str(int(round(f)))
	var s = "%.2f" % f
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

var _current_hover_slot: Control = null
var _hover_timer: float = 0.0
var _hover_triggered: bool = false
var _ammo_popup: PanelContainer = null
var _ammo_popup_content: VBoxContainer = null

func _ensure_ammo_popup():
	if is_instance_valid(_ammo_popup):
		return
	_ammo_popup = PanelContainer.new()
	_ammo_popup.name = "AmmoHUDHoverPopup"
	_ammo_popup.top_level = true
	_ammo_popup.z_index = 250
	_ammo_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_popup.visible = false
	_ammo_popup.custom_minimum_size = Vector2(250, 0)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.04, 0.08, 0.95)
	sb.border_color = Color(0.0, 0.85, 1.0, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_ammo_popup.add_theme_stylebox_override("panel", sb)

	_ammo_popup_content = VBoxContainer.new()
	_ammo_popup_content.name = "ContentVBox"
	_ammo_popup_content.alignment = BoxContainer.ALIGNMENT_BEGIN
	_ammo_popup_content.add_theme_constant_override("separation", 3)
	_ammo_popup_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_popup_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ammo_popup_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_ammo_popup.add_child(_ammo_popup_content)

	var target_parent = get_parent()
	if not is_instance_valid(target_parent):
		target_parent = self
	target_parent.add_child(_ammo_popup)

func _on_slot_mouse_entered(slot_node: Control):
	if slot_node != sl and slot_node != smi and slot_node != sei:
		return
	if _current_hover_slot == slot_node:
		return
	_current_hover_slot = slot_node
	_hover_timer = 0.0
	_hover_triggered = false

func _on_slot_mouse_exited(slot_node: Control):
	if _current_hover_slot == slot_node:
		_current_hover_slot = null
		_hover_timer = 0.0
		_hover_triggered = false
		_hide_ammo_popup()

func _hide_ammo_popup():
	if is_instance_valid(_ammo_popup):
		_ammo_popup.visible = false

func _show_ammo_popup_for_slot(slot: Control):
	if not is_instance_valid(slot):
		return
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or not p_node.get("ammo_slots"):
		return

	var slot_idx = -1
	if slot == sl: slot_idx = 0
	elif slot == smi: slot_idx = 1
	elif slot == sei: slot_idx = 2

	if slot_idx < 0 or slot_idx >= p_node.ammo_slots.size():
		return
	var type = str(p_node.ammo_slots[slot_idx]).to_lower()
	if type.is_empty():
		return

	var t_idx = int(p_node.selected_ammo.get(type, 0)) if p_node.get("selected_ammo") else 0
	_update_popup_content(type, t_idx, p_node)

	_ammo_popup.visible = true
	_ammo_popup.size = Vector2(250, 0)
	_ammo_popup.reset_size()
	var min_s = _ammo_popup.get_combined_minimum_size()
	var popup_w = max(min_s.x, 250.0)
	var popup_h = max(min_s.y, 40.0)
	_ammo_popup.size = Vector2(popup_w, popup_h)

	var slot_rect = slot.get_global_rect()
	var center_x = slot_rect.position.x + (slot_rect.size.x * 0.5) - (popup_w * 0.5)
	var top_y = slot_rect.position.y - popup_h - 12.0

	var vp_size = get_viewport_rect().size
	center_x = clamp(center_x, 10.0, vp_size.x - popup_w - 10.0)
	top_y = max(10.0, top_y)

	_ammo_popup.global_position = Vector2(center_x, top_y)

func _update_popup_content(type: String, t_idx: int, ref):
	_ensure_ammo_popup()
	if not is_instance_valid(_ammo_popup_content):
		return

	for child in _ammo_popup_content.get_children():
		_ammo_popup_content.remove_child(child)
		child.queue_free()

	var type_names = {
		"laser": "LÁSER FRONTAL", "missile": "MISIL TÁCTICO", "mine": "MINA DE PROXIMIDAD",
		"melee": "CORTADOR MELEE", "heal": "PROYECTIL CURATIVO", "siphon": "ROBO DE VIDA",
		"emp": "PULSO EMP", "electron": "ELECTRÓN"
	}
	var type_colors = {
		"laser": Color(0.3, 0.85, 1.0), "missile": Color(1.0, 0.55, 0.2), "mine": Color(1.0, 0.85, 0.2),
		"melee": Color(1.0, 0.35, 0.35), "heal": Color(0.35, 1.0, 0.55), "siphon": Color(1.0, 0.45, 0.95),
		"emp": Color(0.4, 0.65, 1.0), "electron": Color(0.35, 0.95, 1.0)
	}

	var name_str = type_names.get(type, type.to_upper())
	var accent_color = type_colors.get(type, Color(0.0, 0.85, 1.0))

	var sb = _ammo_popup.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = accent_color

	var title_lbl = Label.new()
	title_lbl.text = "=== " + name_str + " ==="
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", accent_color)
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 3)
	_ammo_popup_content.add_child(title_lbl)

	var cfg = {}
	if GameConstants:
		var ammo_base = GameConstants.SHOP_ITEMS.get("ammo", {})
		var list = ammo_base.get(type, [])
		if typeof(list) == TYPE_ARRAY and t_idx >= 0 and t_idx < list.size():
			cfg = list[t_idx] if typeof(list[t_idx]) == TYPE_DICTIONARY else {}

	var default_ranges = {"laser": 500.0, "missile": 800.0, "mine": 1100.0, "melee": 200.0, "heal": 600.0, "siphon": 600.0, "emp": 500.0, "electron": 500.0}
	var default_speeds = {"laser": 1000.0, "missile": 800.0, "mine": 1200.0, "melee": 1500.0, "heal": 1000.0, "siphon": 1200.0, "emp": 800.0, "electron": 600.0}
	var default_cds = {"laser": 1000.0, "missile": 3000.0, "mine": 5000.0, "melee": 1000.0, "heal": 2000.0, "siphon": 3000.0, "emp": 4000.0, "electron": 4000.0}

	var ts = get_tree().get_first_node_in_group("talent_system")
	var dyn_bonuses: Dictionary = ts.get_dynamic_bonuses() if is_instance_valid(ts) else {}
	var dmg_bonus = dyn_bonuses.get("ammo:" + type + ":damage", null)
	var r_bonus = dyn_bonuses.get("ammo:" + type + ":range", null)
	var spd_bonus = dyn_bonuses.get("ammo:" + type + ":bulletSpeed", null)
	var cd_bonus = dyn_bonuses.get("ammo:" + type + ":cooldown", null)

	var ship_dmg = float(ref.base_laser_damage) if (is_instance_valid(ref) and "base_laser_damage" in ref) else 100.0

	var add_line = func(text: String, col: Color):
		var lbl = Label.new()
		lbl.text = text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("outline_size", 2)
		_ammo_popup_content.add_child(lbl)

	# 1. Daño
	var mults = GameConstants.AMMO_MULTIPLIERS.get(type, [1.0]) if GameConstants else [1.0]
	var base_m = float(mults[t_idx]) if (typeof(mults) == TYPE_ARRAY and t_idx < mults.size() and mults[t_idx] != null) else 1.0
	var base_dmg = round(ship_dmg * base_m)
	if dmg_bonus:
		var d_val = float(dmg_bonus.get("val", 0.0))
		var total_m = base_m
		if dmg_bonus.get("flat", false):
			total_m += d_val
			var final_dmg = round(ship_dmg * total_m)
			var added_dmg = final_dmg - base_dmg
			add_line.call("💥 Daño: %s + %s = %s DMG" % [_fmt_num(base_dmg), _fmt_num(added_dmg), _fmt_num(final_dmg)], Color(1.0, 0.45, 0.45))
		elif d_val != 0.0:
			total_m = base_m * (1.0 + d_val)
			var final_dmg = round(ship_dmg * total_m)
			var added_dmg = final_dmg - base_dmg
			add_line.call("💥 Daño: %s + %s (+%s%%) = %s DMG" % [_fmt_num(base_dmg), _fmt_num(added_dmg), _fmt_num(d_val * 100.0), _fmt_num(final_dmg)], Color(1.0, 0.45, 0.45))
		else:
			add_line.call("💥 Daño: %s DMG (x%s)" % [_fmt_num(base_dmg), _fmt_num(base_m)], Color(1.0, 0.45, 0.45))
	else:
		add_line.call("💥 Daño: %s DMG (x%s)" % [_fmt_num(base_dmg), _fmt_num(base_m)], Color(1.0, 0.45, 0.45))

	# 2. Alcance
	var base_r = float(cfg.range) if cfg.has("range") else float(default_ranges.get(type, 500.0))
	if r_bonus:
		var r_val = float(r_bonus.get("val", 0.0))
		if r_bonus.get("flat", false):
			var total_r = base_r + r_val
			add_line.call("🎯 Alcance: %s + %s = %s" % [_fmt_num(base_r), _fmt_num(r_val), _fmt_num(total_r)], Color(0.35, 0.9, 1.0))
		elif r_val != 0.0:
			var added = base_r * r_val
			var total_r = base_r * (1.0 + r_val)
			add_line.call("🎯 Alcance: %s + %s (+%s%%) = %s" % [_fmt_num(base_r), _fmt_num(added), _fmt_num(r_val * 100.0), _fmt_num(total_r)], Color(0.35, 0.9, 1.0))
		else:
			add_line.call("🎯 Alcance: %s" % [_fmt_num(base_r)], Color(0.35, 0.9, 1.0))
	else:
		add_line.call("🎯 Alcance: %s" % [_fmt_num(base_r)], Color(0.35, 0.9, 1.0))

	# 3. Velocidad
	var base_spd = float(cfg.bulletSpeed) if cfg.has("bulletSpeed") else float(default_speeds.get(type, 800.0))
	if spd_bonus:
		var s_val = float(spd_bonus.get("val", 0.0))
		if spd_bonus.get("flat", false):
			var total_spd = base_spd + s_val
			add_line.call("⚡ Velocidad: %s + %s = %s" % [_fmt_num(base_spd), _fmt_num(s_val), _fmt_num(total_spd)], Color(1.0, 0.9, 0.35))
		elif s_val != 0.0:
			var added = base_spd * s_val
			var total_spd = base_spd * (1.0 + s_val)
			add_line.call("⚡ Velocidad: %s + %s (+%s%%) = %s" % [_fmt_num(base_spd), _fmt_num(added), _fmt_num(s_val * 100.0), _fmt_num(total_spd)], Color(1.0, 0.9, 0.35))
		else:
			add_line.call("⚡ Velocidad: %s" % [_fmt_num(base_spd)], Color(1.0, 0.9, 0.35))
	else:
		add_line.call("⚡ Velocidad: %s" % [_fmt_num(base_spd)], Color(1.0, 0.9, 0.35))

	# 4. Cooldown
	var base_cd_ms = float(cfg.cooldown) if cfg.has("cooldown") else float(default_cds.get(type, 1000.0))
	if cd_bonus:
		var c_val = float(cd_bonus.get("val", 0.0))
		if c_val != 0.0:
			var total_cd_ms = max(50.0, base_cd_ms * (1.0 - abs(c_val)))
			var diff_ms = base_cd_ms - total_cd_ms
			var base_cd_s = _fmt_time_ms(base_cd_ms)
			var total_cd_s = _fmt_time_ms(total_cd_ms)
			add_line.call("⏱️ Recarga: %s - %s (-%s%%) = %s" % [base_cd_s, _fmt_time_ms(diff_ms), _fmt_num(abs(c_val) * 100.0), total_cd_s], Color(0.4, 1.0, 0.5))
		else:
			add_line.call("⏱️ Recarga: %s" % [_fmt_time_ms(base_cd_ms)], Color(0.4, 1.0, 0.5))
	else:
		add_line.call("⏱️ Recarga: %s" % [_fmt_time_ms(base_cd_ms)], Color(0.4, 1.0, 0.5))

	# 5. Canalizado
	if cfg.has("castTimeMs") and int(cfg.castTimeMs) > 0:
		add_line.call("⏳ Canalizado: " + _fmt_time_ms(cfg.castTimeMs), Color(0.85, 0.85, 1.0))

	# 6. Radio de explosión
	if cfg.has("explosionRadius") and int(cfg.explosionRadius) > 0:
		add_line.call("💣 Radio de explosión: " + _fmt_num(cfg.explosionRadius), Color(1.0, 0.65, 0.25))

	# 7. Duración en mapa
	if cfg.has("lifetimeMs") and int(cfg.lifetimeMs) > 0:
		add_line.call("⏳ Duración en mapa: " + _fmt_time_ms(cfg.lifetimeMs), Color(0.75, 0.75, 0.85))

	# 8. Efectos específicos
	match type:
		"heal":
			if cfg.has("healPctPvE"):
				add_line.call("💚 Cura: +" + _fmt_num(cfg.healPctPvE) + "% de daño como vida (PvE)", Color(0.35, 1.0, 0.55))
			if cfg.has("healPctVictimPvP") or cfg.has("healPctAttackerPvP"):
				add_line.call("💚 Cura PvP: aliado +" + _fmt_num(cfg.get("healPctVictimPvP", 80)) + "% / atacante +" + _fmt_num(cfg.get("healPctAttackerPvP", 30)) + "%", Color(0.35, 1.0, 0.55))
		"siphon":
			if cfg.has("siphonPct"):
				add_line.call("🔮 Robo de vida: absorbe +" + _fmt_num(cfg.siphonPct) + "% de daño", Color(1.0, 0.45, 0.95))
		"emp":
			if cfg.has("silenceDurationMs"):
				add_line.call("📡 Silencio EMP: anula habilidades por " + _fmt_time_ms(cfg.silenceDurationMs), Color(0.4, 0.65, 1.0))
		"melee":
			if cfg.has("slowDurationMs"):
				add_line.call("⚔️ Ralentización: %s (-%s vel.)" % [_fmt_time_ms(cfg.slowDurationMs), _fmt_num(cfg.get("slowAmount", 200))], Color(1.0, 0.55, 0.35))
		"electron":
			if cfg.has("speedBuffPct"):
				add_line.call("⚛️ Buff Velocidad: +%s%% por impacto (%s, máx %s acum.)" % [_fmt_num(cfg.speedBuffPct), _fmt_time_ms(cfg.get("speedBuffDurationMs", 3000)), _fmt_num(cfg.get("speedBuffMaxStacks", 4))], Color(0.35, 0.95, 1.0))

func _get_cooldown_fill_shader() -> Shader:
	if _cooldown_fill_shader == null:
		_cooldown_fill_shader = Shader.new()
		_cooldown_fill_shader.code = "shader_type canvas_item;
render_mode blend_mix;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec4 color = COLOR;
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	
	vec2 uv = UV - vec2(0.5);
	float angle = atan(uv.y, uv.x);
	float target_angle = fract((angle + PI / 2.0) / (2.0 * PI));
	
	if (target_angle < progress) {
		COLOR = color;
	} else {
		COLOR = vec4(vec3(gray), color.a);
	}
}"
	return _cooldown_fill_shader

var _cooldown_dark_shader: Shader = null

func _get_cooldown_dark_shader() -> Shader:
	if _cooldown_dark_shader == null:
		_cooldown_dark_shader = Shader.new()
		_cooldown_dark_shader.code = "shader_type canvas_item;
render_mode blend_mix;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float angle = atan(uv.y, uv.x);
	float target_angle = fract((angle + PI / 2.0) / (2.0 * PI));
	if (target_angle >= 1.0 - progress) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.55);
	} else {
		COLOR = vec4(0.0);
	}
}"
	return _cooldown_dark_shader

func _update_skill_ui(slot_idx: int, ref, slot):
	if not slot or not ref.get("ammo_slots"): return
	var type = ref.ammo_slots[slot_idx]
	var l_fill = slot.get_node_or_null("Fill")
	var l_cd = slot.get_node_or_null("CD")
	var l_am = _ammo_nodes.get(slot_idx)
	if is_instance_valid(l_am):
		l_am.visible = false
	
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(type, 0.0)
	
	if l_fill:
		l_fill.visible = false
		
	if not _max_cds.has(type) or rv > _max_cds[type]:
		_max_cds[type] = max(rv, 0.5)
	if rv < 0.01:
		_max_cds[type] = lerp(_max_cds[type], 0.5, 0.01)

	var max_cd = _max_cds[type]
	
	# Asegurar que el slot no tenga material propio
	slot.material = null
	
	# v410: Tinte de Silencio (Polimorfia) o Interferencia
	var is_silenced = (ref.get("is_polymorphed") == true and not ref.get("poly_can_use_skills")) or ref.get("is_silenced") == true
	if is_silenced:
		slot.modulate = Color(0.5, 0.25, 0.7, 0.85) # Violeta de silencio
	elif _is_interference_ui_active:
		slot.modulate = Color(1.0, 0.3, 0.3, 0.8) # Rojo de interferencia
	else:
		slot.modulate = Color(1, 1, 1, 1)
	
	# Icono de munición del slot (según tipo equipado en ammo_slots)
	_update_ammo_slot_icon(slot, type)
	# Limpiar tooltip nativo del motor para usar el popup flotante centrado de 2s
	slot.tooltip_text = ""
	var btn_s = slot.get_node_or_null("TouchButton")
	if is_instance_valid(btn_s):
		btn_s.tooltip_text = ""

	# Control de Overlay de Cooldown Oscuro (encima del icono)
	var overlay = slot.get_node_or_null("CooldownOverlay") as ColorRect
	if rv > 0.05 and max_cd > 0.05:
		var progress = clamp(rv / max_cd, 0.0, 1.0)
		if not is_instance_valid(overlay):
			overlay = ColorRect.new()
			overlay.name = "CooldownOverlay"
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(overlay)
		# Siempre por encima del icono y Fill, debajo de labels de texto
		slot.move_child(overlay, _cooldown_overlay_index(slot))

		var mat = overlay.material as ShaderMaterial
		if not mat or mat.shader != _get_cooldown_dark_shader():
			mat = ShaderMaterial.new()
			mat.shader = _get_cooldown_dark_shader()
			overlay.material = mat
		mat.set_shader_parameter("progress", progress)
		overlay.visible = true
	else:
		if is_instance_valid(overlay):
			overlay.visible = false
	
	if l_cd:
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1))
		l_cd.add_theme_color_override("font_outline_color", Color.BLACK)
		l_cd.add_theme_constant_override("outline_size", 4)
		l_cd.add_theme_font_size_override("font_size", 12)
			
	if l_am and ref.get("ammo") != null:
		var a_list = ref.get("ammo").get(type, [0])
		var _a_count = a_list[0] if a_list.size() > 0 else 0
		
		var main_label = null
		for child in slot.get_children():
			if child is Label and not child.name in ["BindingLabel", "CD", "ammo-q", "ammo-w", "ammo-e", "Key"]:
				main_label = child
				break
		if main_label:
			var type_names = {
				"laser": "LÁSER",
				"missile": "MISIL",
				"mine": "MINA",
				"melee": "MELEE",
				"heal": "CURAR",
				"siphon": "SIFÓN",
				"emp": "EMP",
				"electron": "ELECTRÓN"
			}
			# Si hay icono cargado, ocultar el label de texto (el icono ya identifica el tipo)
			var has_icon = slot.get_node_or_null("AmmoIconRect") != null and (slot.get_node_or_null("AmmoIconRect") as TextureRect).texture != null
			main_label.visible = not has_icon
			if not has_icon:
				main_label.text = type_names.get(type, type.to_upper())
		
		# Munición como ítem directo: ocultar contador numérico de balas
		l_am.visible = false

func _update_sphere_ui(id: int, ref, slot):
	if not slot: return
	var l_fill = slot.get_node_or_null("Fill")
	
	var key = "sphere_" + str(id)
	var cds = ref.get("cooldowns")
	if cds == null: cds = {}
	var rv = cds.get(key, 0.0)
	
	var sm = ref.get_node_or_null("SpheresManager")
	var skill = null
	var max_cd = 1.0
	var type_color = Color.WHITE
	
	if is_instance_valid(sm) and sm.spheres_data.size() > id:
		skill = sm.spheres_data[id]["equipped"]
		if skill:
			var s_name = ""
			if typeof(skill) == TYPE_DICTIONARY: s_name = skill.get("skill_name", "")
			else: s_name = str(skill.skill_name)
			
			# v320.40: Limpiar acentos para coincidir exactamente con Constants.gd
			var clean_name = s_name.to_upper().strip_edges().replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")
			if GameConstants.SKILLS_DATA.has(clean_name):
				max_cd = float(GameConstants.SKILLS_DATA[clean_name].get("cd", 5000.0)) / 1000.0
			elif "cooldown" in skill:
				max_cd = skill.cooldown
				
			var raw_type = "ataque"
			if typeof(skill) == TYPE_DICTIONARY: raw_type = str(skill.get("type", "ataque")).to_lower()
			else: raw_type = str(skill.get("type")).to_lower() if skill.get("type") else "ataque"
			
			if "ataque" in raw_type: type_color = Color.RED
			elif "defensa" in raw_type: type_color = Color.AQUA
			elif "curación" in raw_type or "curacion" in raw_type: type_color = Color.GREEN
			elif "utilidad" in raw_type or "movimiento" in raw_type: type_color = Color.YELLOW
			else: type_color = Color.WHITE
			
	if l_fill:
		l_fill.visible = false
		
	# Asegurar que el slot no tenga material propio
	slot.material = null
	
	var progress = 1.0
	if rv > 0.05 and max_cd > 0.05:
		progress = clamp(1.0 - (rv / max_cd), 0.0, 1.0)
	
	var l_cd = slot.get_node_or_null("CD")
	if not l_cd:
		l_cd = Label.new()
		l_cd.name = "CD"
		l_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l_cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l_cd.add_theme_color_override("font_color", Color.WHITE)
		l_cd.add_theme_color_override("font_outline_color", Color.BLACK)
		l_cd.add_theme_constant_override("outline_size", 4)
		l_cd.add_theme_font_size_override("font_size", 12)
		slot.add_child(l_cd)
	
	if is_instance_valid(l_cd):
		l_cd.visible = rv > 0.05
		l_cd.text = str(snapped(rv, 0.1))
		l_cd.modulate = Color.WHITE
		l_cd.add_theme_color_override("font_outline_color", Color.BLACK)
		l_cd.add_theme_constant_override("outline_size", 4)
		l_cd.add_theme_font_size_override("font_size", 12)
	
	# v410: Tinte de Silencio (Polimorfia) o Interferencia
	var is_silenced = (ref.get("is_polymorphed") == true and not ref.get("poly_can_use_skills")) or ref.get("is_silenced") == true
	if is_silenced:
		slot.modulate = Color(0.5, 0.25, 0.7, 0.85) # Violeta de silencio
	elif _is_interference_ui_active:
		slot.modulate = Color(1.0, 0.3, 0.3, 0.8) # Rojo de interferencia
	else:
		slot.modulate = Color(1, 1, 1, slot.modulate.a) 
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6) if skill else Color(0, 0, 0, 0.2)
	sb.draw_center = true
	sb.border_width_left = 2; sb.border_width_right = 2; sb.border_width_top = 2; sb.border_width_bottom = 2
	sb.border_color = type_color if skill else Color(0.2, 0.2, 0.2, 0.5)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(2)
	sb.anti_aliasing = true
	
	if slot.has_method("add_theme_stylebox_override"):
		slot.add_theme_stylebox_override("normal", sb)
		slot.add_theme_stylebox_override("hover", sb)
		slot.add_theme_stylebox_override("pressed", sb)
		slot.add_theme_stylebox_override("disabled", sb)
		if slot is PanelContainer:
			slot.add_theme_stylebox_override("panel", sb)
	
	var skill_icon_tex: Texture2D = null
	var equipped_name = ""
	if skill:
		if typeof(skill) == TYPE_DICTIONARY: equipped_name = skill.get("skill_name", "")
		elif "skill_name" in skill: equipped_name = str(skill.skill_name)
		
		if equipped_name != "":
			var clean_name = equipped_name.to_upper().strip_edges().replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")
			var lookup_name = clean_name
			
			if _skill_icon_cache.has(clean_name):
				skill_icon_tex = _skill_icon_cache[clean_name]
			else:
				var icon_path = _skill_icon_paths.get(clean_name, "")
				if icon_path == "" or not ResourceLoader.exists(icon_path):
					var server_skills = {}
					if NetworkManager and NetworkManager.server_config:
						server_skills = NetworkManager.server_config.get("skillsData", {})
					# Claves del server suelen llevar acentos (VÍNCULO VITAL, etc.)
					var lookup_accented = equipped_name.to_upper().strip_edges()
					if server_skills.has(lookup_name):
						icon_path = server_skills[lookup_name].get("icon", "")
					elif server_skills.has(lookup_accented):
						icon_path = server_skills[lookup_accented].get("icon", "")
					else:
						for sk_key in server_skills:
							if str(sk_key).to_upper().strip_edges().replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U") == clean_name:
								icon_path = server_skills[sk_key].get("icon", "")
								break
				
				if icon_path != "" and ResourceLoader.exists(icon_path):
					skill_icon_tex = load(icon_path)
				if skill_icon_tex:
					_skill_icon_cache[clean_name] = skill_icon_tex
	
	if skill_icon_tex:
		var icon_rect = slot.get_node_or_null("SkillIconRect") as TextureRect
		if not is_instance_valid(icon_rect):
			icon_rect = TextureRect.new()
			icon_rect.name = "SkillIconRect"
			icon_rect.layout_mode = 1
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_rect.anchor_left = 0.0
			icon_rect.anchor_top = 0.0
			icon_rect.anchor_right = 1.0
			icon_rect.anchor_bottom = 1.0
			icon_rect.offset_left = 6; icon_rect.offset_right = -6
			icon_rect.offset_top = 6; icon_rect.offset_bottom = -6

			slot.add_child(icon_rect)

			var target_idx = 0
			var fill_node = slot.get_node_or_null("Fill")
			if is_instance_valid(fill_node):
				target_idx = max(target_idx, fill_node.get_index() + 1)
			slot.move_child(icon_rect, target_idx)
		icon_rect.texture = skill_icon_tex
		
		# Aplicar Shader de CD Radial al icono de la esfera
		if progress < 1.0:
			var mat = icon_rect.material as ShaderMaterial
			if not mat or mat.shader != _get_cooldown_fill_shader():
				mat = ShaderMaterial.new()
				mat.shader = _get_cooldown_fill_shader()
				icon_rect.material = mat
			mat.set_shader_parameter("progress", progress)
		else:
			icon_rect.material = null
	elif not skill:
		var old_icon = slot.get_node_or_null("SkillIconRect")
		if is_instance_valid(old_icon):
			old_icon.queue_free()

	for child in slot.get_children():
		if child is Label:
			if child.name == "CD":
				child.modulate = Color.WHITE
				child.add_theme_color_override("font_color", Color.WHITE)
				child.add_theme_color_override("font_outline_color", Color.BLACK)
				child.add_theme_constant_override("outline_size", 4)
				child.add_theme_font_size_override("font_size", 12)
			elif child.name == "Key":
				pass
			elif child.name == "BindingLabel":
				child.modulate.a = 1.0


func _on_config_updated(_config: Dictionary = {}):
	_skill_icon_cache.clear()
	_ammo_icon_cache.clear()

func clear_icon_cache():
	_skill_icon_cache.clear()
	_ammo_icon_cache.clear()

# Obtiene (con cache) la textura del icono de munición para un tipo dado
func _get_ammo_icon(ammo_type: String) -> Texture2D:
	if ammo_type.is_empty():
		return null
	var key = ammo_type.to_lower()
	if _ammo_icon_cache.has(key):
		return _ammo_icon_cache[key]
	var path = _ammo_icon_paths.get(key, "")
	if path == "" or not ResourceLoader.exists(path):
		_ammo_icon_cache[key] = null
		return null
	var tex = load(path) as Texture2D
	_ammo_icon_cache[key] = tex
	return tex

# Crea/actualiza el TextureRect del icono dentro de un slot del HUD
func _update_ammo_slot_icon(slot, ammo_type: String):
	if not slot:
		return
	var icon = slot.get_node_or_null("AmmoIconRect") as TextureRect
	var tex = _get_ammo_icon(ammo_type)
	if tex == null:
		if is_instance_valid(icon):
			icon.visible = false
			icon.texture = null
		return
	if not is_instance_valid(icon):
		icon = TextureRect.new()
		icon.name = "AmmoIconRect"
		# Idéntico a SkillIconRect: FULL_RECT simétrico + KEEP_ASPECT_CENTERED
		icon.layout_mode = 1
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		# Debajo de Fill y CooldownOverlay, encima del fondo del panel
		var fill_node = slot.get_node_or_null("Fill")
		var start_idx = 0
		if is_instance_valid(fill_node):
			start_idx = fill_node.get_index() + 1
		slot.move_child(icon, start_idx)
	icon.texture = tex
	icon.visible = true
	# Mismos insets que SkillIconRect (6) — el rect cuadrado llena el slot y KEEP_ASPECT centra el PNG
	icon.layout_mode = 1
	icon.anchor_left = 0.0
	icon.anchor_top = 0.0
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.size_flags_horizontal = Control.SIZE_FILL
	icon.size_flags_vertical = Control.SIZE_FILL
	# Asegurar orden: Fill < icon < CooldownOverlay
	var fill_n = slot.get_node_or_null("Fill")
	if is_instance_valid(fill_n) and icon.get_index() < fill_n.get_index():
		slot.move_child(icon, fill_n.get_index() + 1)

# Índice correcto para el overlay de cooldown (encima del icono, debajo de labels)
func _cooldown_overlay_index(slot) -> int:
	# Buscar el índice más alto entre Fill y AmmoIconRect
	var idx = 0
	var fill_n = slot.get_node_or_null("Fill")
	if is_instance_valid(fill_n):
		idx = max(idx, fill_n.get_index())
	var icon_n = slot.get_node_or_null("AmmoIconRect")
	if is_instance_valid(icon_n):
		idx = max(idx, icon_n.get_index())
	return idx + 1

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
	
	if not btn.gui_input.is_connected(_on_touch_button_input.bind(node, callback)):
		btn.gui_input.connect(_on_touch_button_input.bind(node, callback))
	if not btn.mouse_entered.is_connected(_on_slot_mouse_entered.bind(node)):
		btn.mouse_entered.connect(_on_slot_mouse_entered.bind(node))
	if not btn.mouse_exited.is_connected(_on_slot_mouse_exited.bind(node)):
		btn.mouse_exited.connect(_on_slot_mouse_exited.bind(node))
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
						sc.execute_skill()

func _on_base_slot_gui_input(event: InputEvent, slot_idx: int):
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p) or not p.get("ammo_slots"): return
	var skill_id = p.ammo_slots[slot_idx]
	if event == null: 
		p.trigger_skill_by_id(skill_id)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			p.trigger_skill_by_id(skill_id)
		else:
			var sc = p._skill_controller
			if is_instance_valid(sc) and sc.is_aiming:
				if sc.config.get("cast_mode") == 1:
					sc.execute_skill()

func _vp_pos_from_local(node: Control, local_pos: Vector2) -> Vector2:
	return node.get_global_transform() * local_pos

func _set_aim_indicators_visible(node: Control, visible_flag: bool, vp_pos: Vector2 = Vector2.ZERO):
	if not is_instance_valid(node): return
	var aim = node.get_node_or_null("AimIndicator")
	var aim_bg = node.get_node_or_null("AimIndicatorBG")
	if aim_bg:
		aim_bg.visible = visible_flag
		if visible_flag:
			aim_bg.global_position = vp_pos - (aim_bg.size / 2)
	if aim:
		aim.visible = visible_flag
		if visible_flag:
			aim.global_position = vp_pos - (aim.size / 2)

func _on_touch_button_input(event: InputEvent, node: Control, callback: Callable):
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p) or not p._skill_controller: return
	var sc = p._skill_controller
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	
	# PRESS — solo inicia el aim; drag/release los maneja SkillsHUD._input
	var is_press = (event is InputEventScreenTouch and event.pressed) or \
				   (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_press:
		_hide_ammo_popup()
		_current_hover_slot = null
		_hover_timer = 0.0
		_hover_triggered = false
		# Un solo aim a la vez: evita doble start por emulación touch→mouse
		# y que un segundo dedo robe el apuntado.
		if _aim_drag_active:
			get_viewport().set_input_as_handled()
			return
		
		var vp_pos = _vp_pos_from_local(node, event.position)
		_aim_drag_active = true
		_aim_touch_index = event.index if event is InputEventScreenTouch else 0
		_aim_origin_vp = vp_pos
		_aim_node = node
		node.set_meta("touch_index", _aim_touch_index)
		node.set_meta("touch_origin_global", vp_pos)
		callback.call()
		
		if is_mobile:
			var s_type = sc.current_skill.get("type", -1) if is_instance_valid(sc) else -1
			# Solo mostrar indicador de joystick/drag táctil en el botón si la habilidad es DIRECCIONAL (0) o ÁREA (2)
			if s_type == 0 or s_type == 2:
				_set_aim_indicators_visible(node, true, vp_pos)
			else:
				_set_aim_indicators_visible(node, false)
		
		get_viewport().set_input_as_handled()
		return

	# RELEASE — fallback si por algún motivo llega al botón (normalmente lo come _input)
	var is_release = (event is InputEventScreenTouch and not event.pressed) or \
					 (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_release and _aim_drag_active and node == _aim_node:
		_finish_aim_drag(sc, is_mobile)
		get_viewport().set_input_as_handled()
		return

func _finish_aim_drag(sc, is_mobile: bool):
	if is_instance_valid(_aim_node):
		_set_aim_indicators_visible(_aim_node, false)
		_aim_node.remove_meta("touch_index")
		_aim_node.remove_meta("touch_origin_global")
	
	if sc.is_aiming:
		# En móvil y en modo ON_RELEASE: al soltar el dedo se dispara al instante
		if is_mobile or sc.config.get("cast_mode") == 1:
			sc.execute_skill()
	
	sc.external_aim_vector = Vector2.ZERO
	_aim_drag_active = false
	_aim_touch_index = -1
	_aim_origin_vp = Vector2.ZERO
	_aim_node = null

func _update_aim_drag_from_vp(sc, vp_pos: Vector2):
	if not is_instance_valid(_aim_node): return
	
	var s_type = sc.current_skill.get("type", -1)
	# Habilidades INSTANT o POINT_CLICK (como Reflect o Escudo Celular) no usan arrastre direccional
	if s_type != 0 and s_type != 2:
		sc.external_aim_vector = Vector2.ZERO
		return
	
	var diff_global = vp_pos - _aim_origin_vp
	
	var cam = get_viewport().get_camera_2d()
	var zoom_val = cam.zoom.x if cam else 1.0
	var world_diff = diff_global / zoom_val
	
	var raw_range = sc.current_skill.get("range")
	var max_range = 500.0
	if raw_range != null and (raw_range is int or raw_range is float or raw_range is String):
		max_range = float(raw_range)
	if max_range <= 0.0:
		max_range = 500.0
	var sensitivity = SettingsManager.mobile_aim_sensitivity if SettingsManager else 1.0
	
	# Umbral: un micro-drag en táctil (> 5px) ya debe apuntar
	if diff_global.length() > 5.0:
		var screen_dir = diff_global.normalized()
		var map_node = get_tree().get_first_node_in_group("map")
		var oriented_dir = screen_dir
		if is_instance_valid(map_node) and map_node.has_method("get_camera_oriented_direction"):
			oriented_dir = map_node.get_camera_oriented_direction(screen_dir)
		
		var px_for_max = 80.0 / maxf(sensitivity, 0.01)
		var mapped_range = clamp(world_diff.length() * max_range / px_for_max, 10.0, max_range)
		sc.external_aim_vector = oriented_dir * mapped_range
	else:
		sc.external_aim_vector = Vector2.ZERO
	
	_set_aim_indicators_visible(_aim_node, true, vp_pos)

func _input(event: InputEvent):
	if not _aim_drag_active: return
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p) or not p._skill_controller: return
	var sc = p._skill_controller
	var is_mobile = get_node_or_null("/root/SettingsManager") and SettingsManager.mobile_mode
	
	# TOUCH DRAG — sigue el dedo aunque salga del botón
	if event is InputEventScreenDrag:
		if _aim_touch_index != -1 and event.index != _aim_touch_index:
			return
		if is_mobile and sc.is_aiming:
			_update_aim_drag_from_vp(sc, event.position)
			get_viewport().set_input_as_handled()
		return
	
	# TOUCH RELEASE — solo si es el dedo del aim (evita que un segundo toque corte el cast)
	if event is InputEventScreenTouch and not event.pressed:
		if _aim_touch_index != -1 and event.index != _aim_touch_index:
			return
		_finish_aim_drag(sc, is_mobile)
		get_viewport().set_input_as_handled()
		return
	
	# Emulación mouse (F10 / testing móvil en PC) o Android que solo reporta MouseMotion
	if event is InputEventMouseMotion:
		if is_mobile and sc.is_aiming and (_aim_touch_index == 0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			_update_aim_drag_from_vp(sc, event.position)
			get_viewport().set_input_as_handled()
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _aim_touch_index != 0 and _aim_touch_index != -1: return
		_finish_aim_drag(sc, is_mobile)
		get_viewport().set_input_as_handled()
		return
