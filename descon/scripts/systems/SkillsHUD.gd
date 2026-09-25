extends Control

# SkillsHUD.gd (v1.0 - Componente de Habilidades)

var _ammo_nodes = {}
var _ammo_menus = {}
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

	if NetworkManager:
		if not NetworkManager.interference_event.is_connected(_on_interference_event):
			NetworkManager.interference_event.connect(_on_interference_event)
		if NetworkManager.config_updated.is_connected(_on_config_updated):
			NetworkManager.config_updated.disconnect(_on_config_updated)
		NetworkManager.config_updated.connect(_on_config_updated)
			
	set_process(true)

func _process(_delta):
	var p_node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p_node) or p_node.get("is_dead") or p_node.get("entity_id") == "":
		return
	
	_handle_ammo_selector()
	
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
			# v620.0: Ojito de visibilidad — tiers ocultos no se muestran ni se pueden seleccionar
			if _is_ammo_tier_hidden(t, i):
				continue
			var slot_p = PanelContainer.new()
			slot_p.custom_minimum_size = Vector2(40, 40)
			slot_p.mouse_filter = Control.MOUSE_FILTER_STOP
			slot_p.set_meta("tier_index", i)
			
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0.9)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1, 0.1)
			slot_p.add_theme_stylebox_override("panel", sb)
			
			# Icono de munición estilo skill (fondo del tier)
			var ammo_tex = _get_ammo_icon(t)
			if ammo_tex:
				var tier_icon = TextureRect.new()
				tier_icon.name = "AmmoTierIcon"
				tier_icon.texture = ammo_tex
				tier_icon.layout_mode = 1
				tier_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tier_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tier_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot_p.add_child(tier_icon)
				# Centrado simétrico dentro del botón del tier
				tier_icon.anchor_left = 0.0
				tier_icon.anchor_top = 0.0
				tier_icon.anchor_right = 1.0
				tier_icon.anchor_bottom = 1.0
				tier_icon.offset_left = 2
				tier_icon.offset_top = 2
				tier_icon.offset_right = -2
				tier_icon.offset_bottom = -2
				# Fondo tenue para que el label Tn siga siendo legible
				var dim = ColorRect.new()
				dim.name = "TierLabelDim"
				dim.color = Color(0, 0, 0, 0.35)
				dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot_p.add_child(dim)
				dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

			var lbl = Label.new()
			lbl.name = "TierLabel"
			lbl.text = "T" + str(i+1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_constant_override("outline_size", 4)
			slot_p.add_child(lbl)

			slot_p.gui_input.connect(_on_ammo_slot_clicked.bind(t, i))
			menu.add_child(slot_p)
		
		menu.size = menu.get_combined_minimum_size()
		var slot_width = 64 
		if slot_node is Control: slot_width = slot_node.size.x
		menu.position = Vector2((slot_width/2) - (menu.get_combined_minimum_size().x / 2), -menu.get_combined_minimum_size().y - 10)

# v620.0: Ojito de visibilidad — ¿el tier de munición está oculto en la config del servidor?
func _is_ammo_tier_hidden(ammo_type: String, tier_idx: int) -> bool:
	var ammo_base = GameConstants.SHOP_ITEMS.get("ammo", {})
	var list = ammo_base.get(ammo_type, [])
	if typeof(list) != TYPE_ARRAY or tier_idx < 0 or tier_idx >= list.size():
		return false
	return list[tier_idx].get("hidden", false)

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
			# v620.0: Ojito de visibilidad — usar el índice real del tier guardado en el slot
			var tier_index = int(slot.get_meta("tier_index", count - 1 - i)) 
			
			var sb = slot.get_theme_stylebox("panel").duplicate()
			# v400.0: Requisitos de equipamiento — tiers bloqueados en rojo tenue
			var tier_locked = false
			if NetworkManager:
				tier_locked = not NetworkManager.check_equip_requirements("", "", type, tier_index).get("ok", true)
			if tier_locked:
				sb.border_color = Color(1, 0.25, 0.25, 0.8)
				sb.bg_color = Color(0.25, 0.05, 0.05, 0.4)
				sb.set_border_width_all(1)
				slot.modulate = Color(0.5, 0.5, 0.5, 0.7)
			elif tier_index == current_sel:
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
			# v400.0: Requisitos de equipamiento de munición (validación local UX)
			if NetworkManager:
				var req_check = NetworkManager.check_equip_requirements("", "", type, tier)
				if not req_check.get("ok", true):
					NetworkManager.game_notification.emit({
						"msg": "MUNICIÓN BLOQUEADA: " + str(req_check.get("msg", "Requisitos no cumplidos")),
						"type": "error"
					})
					return
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
				if child.name == "Key":
					child.visible = false
					continue
				# El label central de tipo de munición se oculta si hay icono
				if child.name == "Label" and has_ammo_icon:
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
	var is_silenced = ref.get("is_polymorphed") == true and not ref.get("poly_can_use_skills")
	if is_silenced:
		slot.modulate = Color(0.5, 0.25, 0.7, 0.85) # Violeta de silencio
	elif _is_interference_ui_active:
		slot.modulate = Color(1.0, 0.3, 0.3, 0.8) # Rojo de interferencia
	else:
		slot.modulate = Color(1, 1, 1, 1)
	
	# Icono de munición del slot (según tipo equipado en ammo_slots)
	_update_ammo_slot_icon(slot, type)

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
		var a_list = ref.get("ammo").get(type, [0,0,0,0,0,0])
		var sel_data = ref.get("selected_ammo")
		var sel = sel_data.get(type, 0) if sel_data != null else 0
		var a_count = a_list[sel] if a_list.size() > sel else 0
		
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
		
		l_am.text = "T" + str(int(sel + 1)) + ": " + _format_val(a_count)
		if rv > 0.05:
			l_am.modulate = Color(0.5, 0.5, 0.5) # Modulado gris opaco en CD
		else:
			l_am.modulate = Color(0.0, 1.0, 0.0) # Verde brillante
			
		l_am.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		l_am.offset_bottom = -2 
		l_am.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_am.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l_am.add_theme_font_size_override("font_size", 9)
		l_am.visible = true

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
	var is_silenced = ref.get("is_polymorphed") == true and not ref.get("poly_can_use_skills")
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
