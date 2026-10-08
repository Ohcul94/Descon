extends Control

# ==============================================================================
# PlayerInspectUI.gd - Módulo de Inspección de Jugador (Atajo: 'Y')
# ==============================================================================
# - Permite inspeccionar el equipamiento y habilidades equipadas de cualquier
#   jugador (aliado o enemigo) seleccionado como objetivo.
# - Integrado con NetworkManager para consulta autoritativa en tiempo real.
# - Compatible con Touch & Mouse drag, bloqueo de clicks hacia el mundo.
# ==============================================================================

const ItemInfoHelper = preload("res://scripts/ui/inventory/ItemInfoHelper.gd")

var is_open: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var window_panel: PanelContainer = null
var header_bar: Control = null
var target_player_node: Node = null
var inspected_data: Dictionary = {}

# Contenedores UI
var pilot_title_label: Label = null
var ship_info_label: Label = null
var clan_info_label: Label = null
var hp_bar: ProgressBar = null
var hp_label: Label = null
var shield_bar: ProgressBar = null
var shield_label: Label = null

var equip_grid: GridContainer = null
var skills_container: HBoxContainer = null
var tooltip_panel: PanelContainer = null
var tooltip_label: Label = null

# Rutas de iconos de habilidades para visualización
var _skill_icons: Dictionary = {
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
	"BARRERA DE VIENTO": "res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png"
}


func _ready():
	add_to_group("player_inspect_ui")
	add_to_group("inspect_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build_ui_structure()
	_connect_signals()


func _connect_signals():
	if NetworkManager and NetworkManager.has_signal("player_inspect_data"):
		if not NetworkManager.player_inspect_data.is_connected(_on_server_inspect_data):
			NetworkManager.player_inspect_data.connect(_on_server_inspect_data)


func _build_ui_structure():
	var blocker = Control.new()
	blocker.name = "ClickBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blocker)

	# Ventana flotante principal
	window_panel = PanelContainer.new()
	window_panel.name = "InspectWindow"
	window_panel.custom_minimum_size = Vector2(580, 560)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	window_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
	)

	var sb_win = StyleBoxFlat.new()
	sb_win.bg_color = Color(0.015, 0.025, 0.04, 0.96)
	sb_win.border_width_left = 2; sb_win.border_width_top = 2
	sb_win.border_width_right = 2; sb_win.border_width_bottom = 2
	sb_win.border_color = Color(1.0, 0.75, 0.1, 0.75) # Acento dorado táctico
	sb_win.set_corner_radius_all(8)
	sb_win.shadow_color = Color(0, 0, 0, 0.75)
	sb_win.shadow_size = 25
	window_panel.add_theme_stylebox_override("panel", sb_win)
	add_child(window_panel)

	_reposition_window()

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	window_panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# Cabecera arrastrable
	header_bar = PanelContainer.new()
	header_bar.custom_minimum_size = Vector2(0, 34)
	var sb_header = StyleBoxFlat.new()
	sb_header.bg_color = Color(0.06, 0.04, 0.01, 0.9)
	sb_header.border_width_bottom = 1
	sb_header.border_color = Color(1.0, 0.75, 0.1, 0.5)
	sb_header.corner_radius_top_left = 6
	sb_header.corner_radius_top_right = 6
	header_bar.add_theme_stylebox_override("panel", sb_header)
	header_bar.gui_input.connect(_on_header_gui_input)
	main_vbox.add_child(header_bar)

	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 8)
	header_bar.add_child(h_box)

	var icon_title = Label.new()
	icon_title.text = " 🔍 "
	icon_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(icon_title)

	pilot_title_label = Label.new()
	pilot_title_label.text = "INSPECCIÓN DE PILOTO"
	pilot_title_label.add_theme_font_size_override("font_size", 12)
	pilot_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	pilot_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(pilot_title_label)

	var spacer_h = Control.new()
	spacer_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_box.add_child(spacer_h)

	var btn_close = Button.new()
	btn_close.text = " ✕ "
	btn_close.custom_minimum_size = Vector2(28, 24)
	btn_close.add_theme_font_size_override("font_size", 11)
	btn_close.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	var sb_close = StyleBoxFlat.new()
	sb_close.bg_color = Color(0.18, 0.05, 0.07, 0.7)
	sb_close.set_corner_radius_all(4)
	btn_close.add_theme_stylebox_override("normal", sb_close)
	btn_close.pressed.connect(toggle)
	h_box.add_child(btn_close)

	# Fila de datos del Piloto y Nave
	var info_panel = PanelContainer.new()
	var sb_info = StyleBoxFlat.new()
	sb_info.bg_color = Color(0.01, 0.02, 0.03, 0.8)
	sb_info.set_corner_radius_all(6)
	info_panel.add_theme_stylebox_override("panel", sb_info)
	main_vbox.add_child(info_panel)

	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 6)
	info_panel.add_child(info_vbox)

	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 15)
	info_vbox.add_child(top_row)

	ship_info_label = Label.new()
	ship_info_label.text = "NAVE: Desconocida"
	ship_info_label.add_theme_font_size_override("font_size", 10)
	ship_info_label.modulate = Color.CYAN
	top_row.add_child(ship_info_label)

	clan_info_label = Label.new()
	clan_info_label.text = "FLOTA: Sin Clan"
	clan_info_label.add_theme_font_size_override("font_size", 10)
	clan_info_label.modulate = Color.GOLD
	top_row.add_child(clan_info_label)

	# Barras de Salud y Escudo
	var bars_vbox = VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 4)
	info_vbox.add_child(bars_vbox)

	# Escudo
	var sh_box = HBoxContainer.new()
	sh_box.add_theme_constant_override("separation", 8)
	bars_vbox.add_child(sh_box)
	var lbl_sh_title = Label.new()
	lbl_sh_title.text = "ESCUDO:"
	lbl_sh_title.custom_minimum_size.x = 55
	lbl_sh_title.add_theme_font_size_override("font_size", 9)
	lbl_sh_title.modulate = Color.CYAN
	sh_box.add_child(lbl_sh_title)
	shield_bar = ProgressBar.new()
	shield_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shield_bar.custom_minimum_size.y = 12
	shield_bar.show_percentage = false
	var sb_sh = StyleBoxFlat.new()
	sb_sh.bg_color = Color(0.0, 0.75, 0.85, 0.9)
	shield_bar.add_theme_stylebox_override("fill", sb_sh)
	sh_box.add_child(shield_bar)
	shield_label = Label.new()
	shield_label.text = "0 / 0"
	shield_label.custom_minimum_size.x = 90
	shield_label.add_theme_font_size_override("font_size", 9)
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sh_box.add_child(shield_label)

	# HP
	var hp_box = HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 8)
	bars_vbox.add_child(hp_box)
	var lbl_hp_title = Label.new()
	lbl_hp_title.text = "CASCO:"
	lbl_hp_title.custom_minimum_size.x = 55
	lbl_hp_title.add_theme_font_size_override("font_size", 9)
	lbl_hp_title.modulate = Color.GREEN
	hp_box.add_child(lbl_hp_title)
	hp_bar = ProgressBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size.y = 12
	hp_bar.show_percentage = false
	var sb_hp = StyleBoxFlat.new()
	sb_hp.bg_color = Color(0.1, 0.8, 0.2, 0.9)
	hp_bar.add_theme_stylebox_override("fill", sb_hp)
	hp_box.add_child(hp_bar)
	hp_label = Label.new()
	hp_label.text = "0 / 0"
	hp_label.custom_minimum_size.x = 90
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_box.add_child(hp_label)

	# SECCIÓN DE HABILIDADES EQUIPADAS
	var skills_header = Label.new()
	skills_header.text = "⚡ HABILIDADES EQUIPADAS DEL PILOTO"
	skills_header.add_theme_font_size_override("font_size", 10)
	skills_header.modulate = Color(1.0, 0.85, 0.2)
	main_vbox.add_child(skills_header)

	var skills_scroll = ScrollContainer.new()
	skills_scroll.custom_minimum_size.y = 65
	main_vbox.add_child(skills_scroll)

	skills_container = HBoxContainer.new()
	skills_container.add_theme_constant_override("separation", 10)
	skills_scroll.add_child(skills_container)

	# SECCIÓN DE EQUIPAMIENTO
	var equip_header = Label.new()
	equip_header.text = "🛡️ MÓDULOS Y EQUIPAMIENTO DE LA NAVE"
	equip_header.add_theme_font_size_override("font_size", 10)
	equip_header.modulate = Color(0.3, 0.9, 1.0)
	main_vbox.add_child(equip_header)

	var scroll_equip = ScrollContainer.new()
	scroll_equip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll_equip)

	equip_grid = GridContainer.new()
	equip_grid.columns = 6
	equip_grid.add_theme_constant_override("h_separation", 8)
	equip_grid.add_theme_constant_override("v_separation", 8)
	scroll_equip.add_child(equip_grid)


func inspect_current_target():
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")
	
	var target = null
	if is_instance_valid(main_hud) and "_target_entity" in main_hud:
		target = main_hud._target_entity
	
	if not is_instance_valid(target):
		_notify_user("Selecciona a un piloto para inspeccionar (Aliado o Enemigo)", "warn")
		return

	# Verificar si es jugador (local o remoto)
	var is_player = target.is_in_group("player") or target.is_in_group("remote_players")
	if not is_player:
		_notify_user("Solo puedes inspeccionar naves de jugadores", "warn")
		return

	target_player_node = target
	_open_with_target(target)


func _open_with_target(target: Node):
	is_open = true
	visible = true
	_reposition_window()
	if get_parent():
		get_parent().move_child(self, get_parent().get_child_count() - 1)
		z_index = 110

	# 1. Cargar datos locales de la entidad inmediatamente
	_load_data_from_target_node(target)

	# 2. Consultar al servidor para datos autoritativos y enriquecidos
	if NetworkManager and NetworkManager.network_connected:
		var uname = target.get("username") if "username" in target else target.name
		NetworkManager.send_event("inspectPlayer", { "username": uname, "id": target.get("entity_id") })


func _load_data_from_target_node(target: Node):
	var uname = str(target.get("username")) if "username" in target and str(target.get("username")) != "" else target.name
	var tag = str(target.get("clan_tag")) if "clan_tag" in target and str(target.get("clan_tag")) != "" else ""
	var ship_id = int(target.get("current_ship_id")) if "current_ship_id" in target else 1
	var hp = float(target.get("current_hp")) if "current_hp" in target else 1000.0
	var max_h = float(target.get("max_hp")) if "max_hp" in target else 1000.0
	var sh = float(target.get("current_shield")) if "current_shield" in target else 500.0
	var max_s = float(target.get("max_shield")) if "max_shield" in target else 500.0

	pilot_title_label.text = "INSPECCIÓN DE PILOTO: " + (("[" + tag + "] ") if tag != "" else "") + uname
	ship_info_label.text = "NAVE ID: #" + str(ship_id)
	clan_info_label.text = "FLOTA: " + (("[" + tag + "]") if tag != "" else "Piloto Libre")

	hp_bar.max_value = max(1.0, max_h)
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(max_h)]

	shield_bar.max_value = max(1.0, max_s)
	shield_bar.value = sh
	shield_label.text = "%d / %d" % [int(sh), int(max_s)]

	# Cargar equipamiento local si existe
	var eq = target.get("equipped") if "equipped" in target else {}
	_render_equipment(eq)

	# Cargar habilidades desde SpheresManager si está presente
	var sm = target.get_node_or_null("SpheresManager")
	var skills_arr = []
	if is_instance_valid(sm) and "spheres_data" in sm:
		for s_data in sm.spheres_data:
			var sph = s_data.get("sphere")
			if typeof(sph) == TYPE_DICTIONARY and sph.has("skill"):
				skills_arr.append(sph["skill"])
			elif typeof(sph) == TYPE_DICTIONARY and sph.has("name"):
				skills_arr.append(sph["name"])
	_render_skills(skills_arr)


func _on_server_inspect_data(data: Dictionary):
	if not is_open: return
	if data.get("success", false) == false:
		_notify_user(str(data.get("msg", "No se pudo inspeccionar")), "warn")
		return

	inspected_data = data
	var uname = str(data.get("username", ""))
	var tag = str(data.get("clanTag", ""))
	var ship_id = int(data.get("currentShipId", 1))
	var hp = float(data.get("hp", 1000.0))
	var max_h = float(data.get("maxHp", 1000.0))
	var sh = float(data.get("shield", 500.0))
	var max_s = float(data.get("maxShield", 500.0))

	pilot_title_label.text = "INSPECCIÓN DE PILOTO: " + (("[" + tag + "] ") if tag != "" else "") + uname
	ship_info_label.text = "NAVE ID: #" + str(ship_id)
	clan_info_label.text = "FLOTA: " + (("[" + tag + "]") if tag != "" else "Piloto Libre")

	hp_bar.max_value = max(1.0, max_h)
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(max_h)]

	shield_bar.max_value = max(1.0, max_s)
	shield_bar.value = sh
	shield_label.text = "%d / %d" % [int(sh), int(max_s)]

	if data.has("equipped") and typeof(data["equipped"]) == TYPE_DICTIONARY:
		_render_equipment(data["equipped"])

	if data.has("skills"):
		var sk = data["skills"]
		var skills_list = []
		if typeof(sk) == TYPE_ARRAY:
			skills_list = sk
		elif typeof(sk) == TYPE_DICTIONARY:
			for k in sk.keys():
				skills_list.append(sk[k])
		_render_skills(skills_list)


func _render_skills(skills_list: Array):
	for c in skills_container.get_children():
		c.queue_free()

	if skills_list.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Sin habilidades activas configuradas en esferas."
		empty_lbl.add_theme_font_size_override("font_size", 9)
		empty_lbl.modulate.a = 0.5
		skills_container.add_child(empty_lbl)
		return

	for sk in skills_list:
		var sk_name = str(sk)
		if typeof(sk) == TYPE_DICTIONARY:
			sk_name = str(sk.get("name", sk.get("id", "Habilidad")))

		var p = PanelContainer.new()
		p.custom_minimum_size = Vector2(46, 46)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.12, 0.9)
		sb.border_width_left = 1; sb.border_width_top = 1
		sb.border_width_right = 1; sb.border_width_bottom = 1
		sb.border_color = Color.GOLD
		sb.set_corner_radius_all(5)
		p.add_theme_stylebox_override("panel", sb)

		var v = VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(v)

		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(30, 30)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var icon_path = _skill_icons.get(sk_name.to_upper(), "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			tex_rect.texture = load(icon_path)
		else:
			var default_icon = "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png"
			if ResourceLoader.exists(default_icon):
				tex_rect.texture = load(default_icon)
		v.add_child(tex_rect)

		var lbl = Label.new()
		lbl.text = sk_name.substr(0, 7)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.modulate = Color.YELLOW
		v.add_child(lbl)

		p.tooltip_text = "Habilidad: " + sk_name
		skills_container.add_child(p)


func _render_equipment(equip_dict: Dictionary):
	for c in equip_grid.get_children():
		c.queue_free()

	var categories = [
		{"key": "w", "label": "ARMAS", "color": Color.INDIAN_RED},
		{"key": "s", "label": "ESCUDOS", "color": Color.AQUAMARINE},
		{"key": "e", "label": "MOTORES", "color": Color.GOLD},
		{"key": "x", "label": "MÓDULOS", "color": Color.PLUM}
	]

	var total_items = 0
	for cat in categories:
		var items = equip_dict.get(cat.key, [])
		if typeof(items) == TYPE_ARRAY and items.size() > 0:
			for item in items:
				total_items += 1
				_create_equip_card(item, cat.label, cat.color)

	if total_items == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "El piloto no tiene módulos ni armas equipadas en esta nave."
		empty_lbl.add_theme_font_size_override("font_size", 9)
		empty_lbl.modulate.a = 0.5
		equip_grid.add_child(empty_lbl)


func _create_equip_card(item: Dictionary, cat_label: String, border_col: Color):
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(74, 74)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.07, 0.95)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = border_col
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)

	var v = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)

	var item_name = str(item.get("name", item.get("id", "Módulo")))
	var item_tier = int(item.get("tier", item.get("level", 1)))
	var icon_tex = InventoryCache.get_item_icon(item)

	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(38, 38)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if icon_tex:
		icon_rect.texture = icon_tex
	v.add_child(icon_rect)

	var name_lbl = Label.new()
	name_lbl.text = item_name.substr(0, 9)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.modulate = border_col
	v.add_child(name_lbl)

	var t_lbl = Label.new()
	t_lbl.text = cat_label + " T" + str(item_tier)
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_font_size_override("font_size", 7)
	t_lbl.modulate.a = 0.6
	v.add_child(t_lbl)

	p.tooltip_text = "%s (%s)\nTier %d" % [item_name, cat_label, item_tier]
	equip_grid.add_child(p)


func toggle():
	if is_open:
		is_open = false
		visible = false
		z_index = 0
	else:
		inspect_current_target()


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(580.0, vp_size.x * 0.95)
	var target_h = min(560.0, vp_size.y * 0.90)
	window_panel.custom_minimum_size = Vector2(target_w, target_h)
	window_panel.size = Vector2(target_w, target_h)
	var pos_x = max(10.0, (vp_size.x - target_w) / 2.0)
	var pos_y = max(10.0, (vp_size.y - target_h) / 2.0)
	window_panel.position = Vector2(pos_x, pos_y)


func _on_header_gui_input(event: InputEvent):
	var handled = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_offset = window_panel.global_position - event.global_position
		else:
			is_dragging = false
		handled = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_offset = window_panel.global_position - event.position
		else:
			is_dragging = false
		handled = true
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and is_dragging:
		var event_pos = event.global_position if "global_position" in event else event.position
		var new_pos = event_pos + drag_offset
		var vp_size = get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - window_panel.size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - window_panel.size.y)
		window_panel.global_position = new_pos
		handled = true

	if handled:
		get_viewport().set_input_as_handled()


func _input(event: InputEvent):
	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	if event.is_action_pressed("ui_inspect") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y):
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not is_open: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()


func _notify_user(msg: String, type: String = "info"):
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")
	if is_instance_valid(main_hud) and main_hud.has_method("notify"):
		main_hud.notify(msg, type)
	else:
		print("[INSPECT] ", msg)
