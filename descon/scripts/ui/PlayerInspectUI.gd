extends Control

# ==============================================================================
# PlayerInspectUI.gd - Módulo de Inspección de Jugador (Atajo: 'Y')
# ==============================================================================
# - Permite inspeccionar el equipamiento y habilidades equipadas de cualquier
#   jugador objetivo (aliado o enemigo). No permite auto-inspección.
# - Estética Sci-Fi unificada con el resto de módulos (PlayerInventoryUI, PlayerStatsUI).
# - Proporciones equilibradas, tipografía clara y slots de alta visibilidad.
# - Consulta en tiempo real a SpheresManager y sincronización autoritativa con el servidor.
# ==============================================================================

const ItemInfoHelper = preload("res://scripts/ui/inventory/ItemInfoHelper.gd")

var is_open: bool = false
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var window_panel: PanelContainer = null
var header_bar: Control = null
var target_player_node: Node = null
var inspected_data: Dictionary = {}

# Contenedores UI principales
var pilot_title_label: Label = null
var ship_info_label: Label = null
var clan_info_label: Label = null
var hp_bar: ProgressBar = null
var hp_label: Label = null
var shield_bar: ProgressBar = null
var shield_label: Label = null

var skills_container: HBoxContainer = null
var equip_container: HBoxContainer = null

# Rutas de iconos de habilidades registradas en el juego
var _skill_icons: Dictionary = {
	"BLINK": "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
	"DESTELLO": "res://assets/Skills/Iconos/Utilidad/Destello/Destello.png",
	"TURBO-IMPULSO": "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png",
	"TURBO IMPULSO": "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png",
	"HYPER-DASH": "res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png",
	"HYPERDASH": "res://assets/Skills/Iconos/Utilidad/HyperDash/HyperDash.png",
	"INVULNERABILIDAD": "res://assets/Skills/Iconos/Utilidad/Invulnerabilidad/Invulnerabilidad.png",
	"STEALTH": "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
	"INVISIBILIDAD": "res://assets/Skills/Iconos/Utilidad/Invisibilidad/Invisibilidad.png",
	"RESURRECCION": "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
	"RESURRECCIÓN": "res://assets/Skills/Iconos/Utilidad/Resurrecion/Resurrecion.png",
	"REFLECT-OMEGA": "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
	"REFLECT": "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png",
	"ESFERA DE TERROR": "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
	"MIEDO": "res://assets/Skills/Iconos/Ataque/Miedo/Miedo.png",
	"PROVOCACION": "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
	"PROVOCACIÓN": "res://assets/Skills/Iconos/Ataque/Provocacion/Provocacion.png",
	"HOOKSHOT": "res://assets/Skills/Iconos/Ataque/Hookshot/Hookshot.png",
	"VINCULO VITAL": "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
	"VÍNCULO VITAL": "res://assets/Skills/Iconos/Cura/Vinculo Vital/Vinculo Vital.png",
	"REGENERACION ALFA": "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
	"REGENERACIÓN ALFA": "res://assets/Skills/Iconos/Cura/Regeneracion Alfa/Regeneracion Alfa.png",
	"BALIZA DE CURACION": "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
	"BALIZA DE CURACIÓN": "res://assets/Skills/Iconos/Cura/Baliza Curativa/Baliza Curativa.png",
	"AUTO-REPARACION": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"AUTO-REPARACIÓN": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"NANO-REGENERACION": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"NANO-REGENERACIÓN": "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png",
	"ESCUDO CELULAR": "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png",
	"SMOKE-BOMB": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"BOMBA DE HUMO": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"FROST-TRAIL": "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
	"CAMINO DE HIELO": "res://assets/Skills/Iconos/Defensa/Camino de Hielo/Camino de Hielo.png",
	"BARRERA DE VIENTO": "res://assets/Skills/Iconos/Defensa/Barrera de Viento/Barrera de Viento.png",
	"DIMENSION EXTRAÑA": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png",
	"DIMENSIÓN EXTRAÑA": "res://assets/Skills/Iconos/Defensa/Bomba de Humo/Bomba de Humo.png"
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

	# Ventana flotante principal con estilo unificado cian espacial
	window_panel = PanelContainer.new()
	window_panel.name = "InspectWindow"
	window_panel.custom_minimum_size = Vector2(640, 610)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	window_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
	)

	var sb_win = StyleBoxFlat.new()
	sb_win.bg_color = Color(0.012, 0.022, 0.038, 0.98)
	sb_win.border_width_left = 2; sb_win.border_width_top = 2
	sb_win.border_width_right = 2; sb_win.border_width_bottom = 2
	sb_win.border_color = Color(0.0, 0.85, 1.0, 0.8) # Borde cian espacial
	sb_win.set_corner_radius_all(8)
	sb_win.corner_detail = 12
	sb_win.anti_aliasing = true
	sb_win.shadow_color = Color(0, 0, 0, 0.4)
	sb_win.shadow_size = 10
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

	# 1. Cabecera arrastrable
	header_bar = PanelContainer.new()
	header_bar.custom_minimum_size = Vector2(0, 34)
	var sb_header = StyleBoxFlat.new()
	sb_header.bg_color = Color(0.01, 0.05, 0.09, 0.9)
	sb_header.border_width_bottom = 1
	sb_header.border_color = Color(0.2, 0.8, 1.0, 0.5)
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
	pilot_title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
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
	btn_close.pressed.connect(close)
	h_box.add_child(btn_close)

	# 2. Panel superior: Datos del Piloto y Barras de Estado
	var info_panel = PanelContainer.new()
	var sb_info = StyleBoxFlat.new()
	sb_info.bg_color = Color(0.015, 0.04, 0.07, 0.85)
	sb_info.border_width_left = 1; sb_info.border_width_top = 1
	sb_info.border_width_right = 1; sb_info.border_width_bottom = 1
	sb_info.border_color = Color(0.0, 0.7, 0.9, 0.35)
	sb_info.set_corner_radius_all(6)
	info_panel.add_theme_stylebox_override("panel", sb_info)
	main_vbox.add_child(info_panel)

	var info_margin = MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 12)
	info_margin.add_theme_constant_override("margin_right", 12)
	info_margin.add_theme_constant_override("margin_top", 8)
	info_margin.add_theme_constant_override("margin_bottom", 8)
	info_panel.add_child(info_margin)

	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 6)
	info_margin.add_child(info_vbox)

	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 20)
	info_vbox.add_child(top_row)

	ship_info_label = Label.new()
	ship_info_label.text = "NAVE: Identificando..."
	ship_info_label.add_theme_font_size_override("font_size", 11)
	ship_info_label.modulate = Color(0.2, 0.85, 1.0)
	top_row.add_child(ship_info_label)

	clan_info_label = Label.new()
	clan_info_label.text = "FLOTA: Sin Clan"
	clan_info_label.add_theme_font_size_override("font_size", 11)
	clan_info_label.modulate = Color(0.4, 1.0, 0.7)
	top_row.add_child(clan_info_label)

	# Barras de Salud y Escudo proporcionales
	var bars_vbox = VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 5)
	info_vbox.add_child(bars_vbox)

	# Escudo
	var sh_box = HBoxContainer.new()
	sh_box.add_theme_constant_override("separation", 8)
	bars_vbox.add_child(sh_box)

	var lbl_sh_title = Label.new()
	lbl_sh_title.text = "ESCUDO:"
	lbl_sh_title.custom_minimum_size.x = 65
	lbl_sh_title.add_theme_font_size_override("font_size", 10)
	lbl_sh_title.modulate = Color(0.0, 0.85, 1.0)
	sh_box.add_child(lbl_sh_title)

	shield_bar = ProgressBar.new()
	shield_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shield_bar.custom_minimum_size.y = 16
	shield_bar.show_percentage = false
	var sb_sh = StyleBoxFlat.new()
	sb_sh.bg_color = Color(0.0, 0.75, 0.9, 0.9)
	sb_sh.set_corner_radius_all(3)
	shield_bar.add_theme_stylebox_override("fill", sb_sh)
	var sb_sh_bg = StyleBoxFlat.new()
	sb_sh_bg.bg_color = Color(0.03, 0.1, 0.15, 0.8)
	sb_sh_bg.set_corner_radius_all(3)
	shield_bar.add_theme_stylebox_override("background", sb_sh_bg)
	sh_box.add_child(shield_bar)

	shield_label = Label.new()
	shield_label.text = "0 / 0"
	shield_label.custom_minimum_size.x = 100
	shield_label.add_theme_font_size_override("font_size", 10)
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sh_box.add_child(shield_label)

	# Casco / HP
	var hp_box = HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 8)
	bars_vbox.add_child(hp_box)

	var lbl_hp_title = Label.new()
	lbl_hp_title.text = "CASCO:"
	lbl_hp_title.custom_minimum_size.x = 65
	lbl_hp_title.add_theme_font_size_override("font_size", 10)
	lbl_hp_title.modulate = Color(0.2, 0.9, 0.35)
	hp_box.add_child(lbl_hp_title)

	hp_bar = ProgressBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size.y = 16
	hp_bar.show_percentage = false
	var sb_hp = StyleBoxFlat.new()
	sb_hp.bg_color = Color(0.12, 0.8, 0.28, 0.9)
	sb_hp.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("fill", sb_hp)
	var sb_hp_bg = StyleBoxFlat.new()
	sb_hp_bg.bg_color = Color(0.05, 0.14, 0.08, 0.8)
	sb_hp_bg.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("background", sb_hp_bg)
	hp_box.add_child(hp_bar)

	hp_label = Label.new()
	hp_label.text = "0 / 0"
	hp_label.custom_minimum_size.x = 100
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_box.add_child(hp_label)

	# 3. SECCIÓN: HABILIDADES EQUIPADAS
	var skills_sec_panel = PanelContainer.new()
	var sb_sec1 = StyleBoxFlat.new()
	sb_sec1.bg_color = Color(0.015, 0.035, 0.06, 0.8)
	sb_sec1.border_width_left = 1; sb_sec1.border_width_top = 1
	sb_sec1.border_width_right = 1; sb_sec1.border_width_bottom = 1
	sb_sec1.border_color = Color(0.0, 0.75, 0.9, 0.3)
	sb_sec1.set_corner_radius_all(6)
	skills_sec_panel.add_theme_stylebox_override("panel", sb_sec1)
	main_vbox.add_child(skills_sec_panel)

	var skills_m = MarginContainer.new()
	skills_m.add_theme_constant_override("margin_left", 12)
	skills_m.add_theme_constant_override("margin_right", 12)
	skills_m.add_theme_constant_override("margin_top", 8)
	skills_m.add_theme_constant_override("margin_bottom", 10)
	skills_sec_panel.add_child(skills_m)

	var skills_vb = VBoxContainer.new()
	skills_vb.add_theme_constant_override("separation", 8)
	skills_m.add_child(skills_vb)

	var skills_header = Label.new()
	skills_header.text = "⚡ HABILIDADES EQUIPADAS DEL PILOTO"
	skills_header.add_theme_font_size_override("font_size", 11)
	skills_header.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	skills_vb.add_child(skills_header)

	skills_container = HBoxContainer.new()
	skills_container.add_theme_constant_override("separation", 14)
	skills_vb.add_child(skills_container)

	# 4. SECCIÓN: EQUIPAMIENTO Y MÓDULOS DE LA NAVE
	var equip_sec_panel = PanelContainer.new()
	equip_sec_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb_sec2 = StyleBoxFlat.new()
	sb_sec2.bg_color = Color(0.015, 0.035, 0.06, 0.8)
	sb_sec2.border_width_left = 1; sb_sec2.border_width_top = 1
	sb_sec2.border_width_right = 1; sb_sec2.border_width_bottom = 1
	sb_sec2.border_color = Color(0.0, 0.75, 0.9, 0.3)
	sb_sec2.set_corner_radius_all(6)
	equip_sec_panel.add_theme_stylebox_override("panel", sb_sec2)
	main_vbox.add_child(equip_sec_panel)

	var equip_m = MarginContainer.new()
	equip_m.add_theme_constant_override("margin_left", 12)
	equip_m.add_theme_constant_override("margin_right", 12)
	equip_m.add_theme_constant_override("margin_top", 8)
	equip_m.add_theme_constant_override("margin_bottom", 10)
	equip_sec_panel.add_child(equip_m)

	var equip_vb = VBoxContainer.new()
	equip_vb.add_theme_constant_override("separation", 8)
	equip_m.add_child(equip_vb)

	var equip_header = Label.new()
	equip_header.text = "🛡️ MÓDULOS Y EQUIPAMIENTO DE LA NAVE"
	equip_header.add_theme_font_size_override("font_size", 11)
	equip_header.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	equip_vb.add_child(equip_header)

	var scroll_equip = ScrollContainer.new()
	scroll_equip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_equip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	equip_vb.add_child(scroll_equip)

	equip_container = HBoxContainer.new()
	equip_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_container.add_theme_constant_override("separation", 12)
	scroll_equip.add_child(equip_container)


# ==============================================================================
# LÓGICA DE APERTURA E INSPECCIÓN
# ==============================================================================
func _process(_delta: float):
	if not is_open: return
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")
	if is_instance_valid(main_hud) and "_target_entity" in main_hud:
		var cur_tgt = main_hud._target_entity
		if is_instance_valid(cur_tgt) and cur_tgt != target_player_node:
			var local_player = get_tree().get_first_node_in_group("player")
			if cur_tgt != local_player and (cur_tgt.is_in_group("remote_players") or cur_tgt.is_in_group("player")):
				target_player_node = cur_tgt
				_open_with_target(cur_tgt)


func inspect_current_target():
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")

	var target = null
	if is_instance_valid(main_hud) and "_target_entity" in main_hud:
		target = main_hud._target_entity

	# Abrir siempre la ventana para asegurar respuesta inmediata
	is_open = true
	visible = true
	_reposition_window()
	if get_parent():
		get_parent().move_child(self, get_parent().get_child_count() - 1)
		z_index = 110

	# 1. Si no hay objetivo actual pero ya teníamos uno inspeccionado previamente
	if not is_instance_valid(target) and is_instance_valid(target_player_node):
		target = target_player_node

	# 2. Si no hay objetivo
	if not is_instance_valid(target):
		_show_hint_state("Selecciona a otro piloto (haz clic en él) para inspeccionar su nave y habilidades.")
		return

	# 3. Bloquear inspección a uno mismo
	var local_player = get_tree().get_first_node_in_group("player")
	if target == local_player:
		_show_hint_state("No puedes inspeccionarte a ti mismo. Usa tus menús de Estadísticas (E) o Equipamiento (P).")
		return

	if NetworkManager and NetworkManager.is_logged_in:
		var target_uname = str(target.get("username")) if "username" in target else ""
		if target_uname != "" and target_uname.to_lower() == NetworkManager.login_name.to_lower():
			_show_hint_state("No puedes inspeccionarte a ti mismo. Usa tus menús de Estadísticas (E) o Equipamiento (P).")
			return

	# 4. Validar que sea nave de un jugador
	var is_remote = target.is_in_group("remote_players")
	var is_player = target.is_in_group("player") or is_remote
	if not is_player:
		_show_hint_state("El objetivo seleccionado no es la nave de un piloto.")
		return

	target_player_node = target
	_open_with_target(target)


func _show_hint_state(msg: String):
	pilot_title_label.text = "INSPECCIÓN DE PILOTO"
	ship_info_label.text = "NAVE: Sin objetivo"
	clan_info_label.text = "FLOTA: -"

	hp_bar.max_value = 1.0; hp_bar.value = 0.0
	hp_label.text = "- / -"
	shield_bar.max_value = 1.0; shield_bar.value = 0.0
	shield_label.text = "- / -"

	for c in skills_container.get_children():
		c.queue_free()
	var sk_hint = Label.new()
	sk_hint.text = msg
	sk_hint.add_theme_font_size_override("font_size", 10)
	sk_hint.modulate = Color(0.3, 0.85, 1.0, 0.8)
	skills_container.add_child(sk_hint)

	_render_equipment({}, { "w": 1, "s": 1, "e": 1, "x": 1 })


func _open_with_target(target: Node):
	is_open = true
	visible = true
	_reposition_window()
	if get_parent():
		get_parent().move_child(self, get_parent().get_child_count() - 1)
		z_index = 110

	# 1. Cargar datos locales de la entidad inmediatamente para respuesta instantánea
	_load_data_from_target_node(target)

	# 2. Consultar al servidor para datos autoritativos y enriquecidos
	if NetworkManager and NetworkManager.network_connected:
		var uname = str(target.get("username")) if "username" in target else str(target.name)
		NetworkManager.send_event("inspectPlayer", { "username": uname, "id": target.get("entity_id") })


func _load_data_from_target_node(target: Node):
	var uname = str(target.get("username")) if "username" in target and str(target.get("username")) != "" else str(target.name)
	var tag = str(target.get("clan_tag")) if "clan_tag" in target and str(target.get("clan_tag")) != "" else ""
	var ship_id = int(target.get("current_ship_id")) if "current_ship_id" in target else 1
	var hp = float(target.get("current_hp")) if "current_hp" in target else 0.0
	var max_h = float(target.get("max_hp")) if "max_hp" in target else 0.0
	var sh = float(target.get("current_shield")) if "current_shield" in target else 0.0
	var max_s = float(target.get("max_shield")) if "max_shield" in target else 0.0

	var ship_name = "Nave #" + str(ship_id)
	var slots_def = { "w": 1, "s": 1, "e": 1, "x": 1 }
	if GameConstants.SHIP_MODELS:
		for sm in GameConstants.SHIP_MODELS:
			if int(sm.get("id")) == ship_id:
				ship_name = str(sm.get("name", ship_name))
				slots_def = sm.get("slots", slots_def)
				if max_h <= 0.0:
					max_h = float(sm.get("hp", 1000.0))
					hp = max_h
				if max_s <= 0.0:
					max_s = float(sm.get("shield", 500.0))
					sh = max_s
				break

	if max_h <= 0.0: max_h = 1000.0; hp = 1000.0
	if max_s <= 0.0: max_s = 500.0; sh = 500.0

	pilot_title_label.text = "INSPECCIÓN DE PILOTO: " + (("[" + tag + "] ") if tag != "" else "") + uname
	ship_info_label.text = "NAVE: " + ship_name + " (#" + str(ship_id) + ")"
	clan_info_label.text = "FLOTA: " + (("[" + tag + "]") if tag != "" else "Piloto Libre")

	hp_bar.max_value = max(1.0, max_h)
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(max_h)]

	shield_bar.max_value = max(1.0, max_s)
	shield_bar.value = sh
	shield_label.text = "%d / %d" % [int(sh), int(max_s)]

	# Cargar equipamiento local si existe
	var eq = target.get("equipped") if "equipped" in target else {}
	_render_equipment(eq if typeof(eq) == TYPE_DICTIONARY else {}, slots_def)

	# Cargar habilidades reales equipadas desde SpheresManager
	var sm = target.get_node_or_null("SpheresManager")
	var skills_arr = []
	if is_instance_valid(sm) and "spheres_data" in sm:
		for s_data in sm.spheres_data:
			var eq_skill = s_data.get("equipped")
			if eq_skill != null:
				skills_arr.append(eq_skill)
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
	var ship_name = str(data.get("shipName", "Nave #" + str(ship_id)))
	var hp = float(data.get("hp", 1000.0))
	var max_h = float(data.get("maxHp", 1000.0))
	var sh = float(data.get("shield", 500.0))
	var max_s = float(data.get("maxShield", 500.0))

	var slots_def = data.get("shipSlots", {})
	if (slots_def == null or (typeof(slots_def) == TYPE_DICTIONARY and slots_def.is_empty())) and GameConstants.SHIP_MODELS:
		for sm in GameConstants.SHIP_MODELS:
			if int(sm.get("id")) == ship_id:
				slots_def = sm.get("slots", { "w": 1, "s": 1, "e": 1, "x": 1 })
				if ship_name == ("Nave #" + str(ship_id)):
					ship_name = str(sm.get("name", ship_name))
				break

	if slots_def == null or typeof(slots_def) != TYPE_DICTIONARY or slots_def.is_empty():
		slots_def = { "w": 1, "s": 1, "e": 1, "x": 1 }

	pilot_title_label.text = "INSPECCIÓN DE PILOTO: " + (("[" + tag + "] ") if tag != "" else "") + uname
	ship_info_label.text = "NAVE: " + ship_name + " (#" + str(ship_id) + ")"
	clan_info_label.text = "FLOTA: " + (("[" + tag + "]") if tag != "" else "Piloto Libre")

	hp_bar.max_value = max(1.0, max_h)
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [int(hp), int(max_h)]

	shield_bar.max_value = max(1.0, max_s)
	shield_bar.value = sh
	shield_label.text = "%d / %d" % [int(sh), int(max_s)]

	if data.has("equipped") and typeof(data["equipped"]) == TYPE_DICTIONARY:
		_render_equipment(data["equipped"], slots_def)
	else:
		_render_equipment({}, slots_def)

	if data.has("skills") and typeof(data["skills"]) == TYPE_ARRAY:
		_render_skills(data["skills"])


# ==============================================================================
# RENDERIZADO DE HABILIDADES (SKILLS)
# ==============================================================================
func _render_skills(skills_list: Array):
	for c in skills_container.get_children():
		c.queue_free()

	if skills_list.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "El piloto no tiene habilidades equipadas en sus esferas."
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.modulate = Color(0.6, 0.75, 0.85, 0.6)
		skills_container.add_child(empty_lbl)
		return

	for sk in skills_list:
		var sk_name = ""
		var sk_texture: Texture2D = null
		var sk_type = "Ataque"

		if sk is Resource:
			sk_name = str(sk.get("skill_name"))
			if sk.get("icon") and sk.get("icon") is Texture2D:
				sk_texture = sk.get("icon")
			if sk.get("type"):
				sk_type = str(sk.get("type"))
		elif typeof(sk) == TYPE_DICTIONARY:
			sk_name = str(sk.get("skill_name", sk.get("name", sk.get("id", ""))))
			sk_type = str(sk.get("type", "Ataque"))
			if sk.has("icon") and sk["icon"] is Texture2D:
				sk_texture = sk["icon"]
			elif sk.has("icon_path") and ResourceLoader.exists(str(sk["icon_path"])):
				sk_texture = load(str(sk["icon_path"]))
		else:
			sk_name = str(sk)

		if sk_name == "":
			continue

		# Normalizar nombre sin acentos para mapeo de icono
		var clean_name = sk_name.to_upper().strip_edges().replace("Ó", "O").replace("É", "E").replace("Í", "I").replace("Á", "A").replace("Ú", "U").replace("Ü", "U")

		# Determinar color por categoría de habilidad
		var type_color = Color(0.9, 0.35, 0.35) # Ataque
		var type_lower = sk_type.to_lower()
		if "defensa" in type_lower:
			type_color = Color(0.2, 0.85, 1.0) # Celeste
		elif "cura" in type_lower:
			type_color = Color(0.25, 0.95, 0.45) # Verde
		elif "utilidad" in type_lower or "movimiento" in type_lower:
			type_color = Color(1.0, 0.85, 0.25) # Amarillo/Dorado

		# Resolver icono si aún no lo tiene
		if sk_texture == null:
			var icon_p = _skill_icons.get(clean_name, "")
			if icon_p != "" and ResourceLoader.exists(icon_p):
				sk_texture = load(icon_p)
			else:
				var fallback_path = ""
				if "defensa" in type_lower:
					fallback_path = "res://assets/Skills/Iconos/Defensa/Escudo Celular/Escudo Celular.png"
				elif "cura" in type_lower:
					fallback_path = "res://assets/Skills/Iconos/Cura/Auto Reparacion/AutoReparacion.png"
				elif "utilidad" in type_lower:
					fallback_path = "res://assets/Skills/Iconos/Utilidad/Turbo Impulso/Turbo Impulso.png"
				else:
					fallback_path = "res://assets/Skills/Iconos/Ataque/Reflect/Reflect.png"

				if ResourceLoader.exists(fallback_path):
					sk_texture = load(fallback_path)

		var p = PanelContainer.new()
		p.custom_minimum_size = Vector2(58, 58)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.015, 0.04, 0.08, 0.95)
		sb.border_width_left = 2; sb.border_width_top = 2
		sb.border_width_right = 2; sb.border_width_bottom = 2
		sb.border_color = type_color
		sb.set_corner_radius_all(6)
		p.add_theme_stylebox_override("panel", sb)

		var v = VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		p.add_child(v)

		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(36, 36)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if sk_texture:
			tex_rect.texture = sk_texture
		v.add_child(tex_rect)

		var lbl = Label.new()
		lbl.text = sk_name.substr(0, 9)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.modulate = type_color
		v.add_child(lbl)

		p.tooltip_text = "%s\nTipo: %s" % [sk_name, sk_type]
		skills_container.add_child(p)


# ==============================================================================
# RENDERIZADO DE EQUIPAMIENTO POR CATEGORÍAS (SLOTS DINÁMICOS POR MODELO)
# ==============================================================================
func _render_equipment(equip_dict: Dictionary, slots_def: Dictionary = {}):
	for c in equip_container.get_children():
		c.queue_free()

	if slots_def == null or slots_def.is_empty():
		slots_def = { "w": 1, "s": 1, "e": 1, "x": 1 }

	var categories = [
		{"key": "w", "label": "ARMAS", "color": Color(0.95, 0.35, 0.35), "limit": int(slots_def.get("w", 1)), "glyph": "⚔"},
		{"key": "s", "label": "ESCUDOS", "color": Color(0.2, 0.85, 1.0), "limit": int(slots_def.get("s", 1)), "glyph": "🛡"},
		{"key": "e", "label": "MOTORES", "color": Color(1.0, 0.85, 0.25), "limit": int(slots_def.get("e", 1)), "glyph": "⚡"},
		{"key": "x", "label": "MÓDULOS", "color": Color(0.8, 0.5, 1.0), "limit": int(slots_def.get("x", 1)), "glyph": "💎"}
	]

	for cat in categories:
		var cat_panel = PanelContainer.new()
		cat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb_cat = StyleBoxFlat.new()
		sb_cat.bg_color = Color(0.01, 0.03, 0.06, 0.6)
		sb_cat.border_width_left = 1; sb_cat.border_width_top = 1
		sb_cat.border_width_right = 1; sb_cat.border_width_bottom = 1
		sb_cat.border_color = Color(cat.color.r, cat.color.g, cat.color.b, 0.3)
		sb_cat.set_corner_radius_all(5)
		cat_panel.add_theme_stylebox_override("panel", sb_cat)
		equip_container.add_child(cat_panel)

		var cat_margin = MarginContainer.new()
		cat_margin.add_theme_constant_override("margin_left", 6)
		cat_margin.add_theme_constant_override("margin_right", 6)
		cat_margin.add_theme_constant_override("margin_top", 6)
		cat_margin.add_theme_constant_override("margin_bottom", 6)
		cat_panel.add_child(cat_margin)

		var cat_vb = VBoxContainer.new()
		cat_vb.add_theme_constant_override("separation", 6)
		cat_margin.add_child(cat_vb)

		var items = equip_dict.get(cat.key, [])
		var items_arr = items if typeof(items) == TYPE_ARRAY else []

		# Contar items realmente equipados
		var equipped_count = 0
		for it in items_arr:
			if it != null and typeof(it) == TYPE_DICTIONARY and not it.is_empty():
				equipped_count += 1

		var cat_title = Label.new()
		cat_title.text = "%s (%d/%d)" % [cat.label, equipped_count, cat.limit]
		cat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cat_title.add_theme_font_size_override("font_size", 9)
		cat_title.modulate = cat.color
		cat_vb.add_child(cat_title)

		for slot_idx in range(cat.limit):
			var item = items_arr[slot_idx] if slot_idx < items_arr.size() else null
			_create_equip_slot(cat_vb, item, cat.label, cat.color, cat.glyph)


func _create_equip_slot(parent: Control, item, cat_label: String, border_col: Color, glyph: String = ""):
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(56, 56)

	var sb = StyleBoxFlat.new()
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.set_corner_radius_all(5)

	if item != null and typeof(item) == TYPE_DICTIONARY and not item.is_empty():
		var rarity = int(item.get("rarity", 0))
		var r_color = ItemInfoHelper.rarity_color(rarity)

		sb.bg_color = Color(r_color.r, r_color.g, r_color.b, 0.15)
		sb.border_color = r_color
		sb.border_width_left = 2; sb.border_width_top = 2
		sb.border_width_right = 2; sb.border_width_bottom = 2
		p.add_theme_stylebox_override("panel", sb)

		var center = CenterContainer.new()
		center.custom_minimum_size = Vector2(52, 52)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(center)

		var item_name = str(item.get("name", item.get("id", "Módulo")))
		var item_tier = int(item.get("tier", item.get("level", 1)))
		var icon_path = _resolve_item_icon(item)

		var icon_node = null
		if ModelIconGenerator and ModelIconGenerator.has_method("make_icon_rect"):
			icon_node = ModelIconGenerator.make_icon_rect(item, icon_path, Vector2(36, 36))

		if icon_node:
			center.add_child(icon_node)
		else:
			var icon_rect = TextureRect.new()
			icon_rect.custom_minimum_size = Vector2(36, 36)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var tex = _get_item_icon(item)
			if tex: icon_rect.texture = tex
			center.add_child(icon_rect)

		# Pequeño badge con el Tier
		var tier_badge = Label.new()
		tier_badge.text = "T" + str(item_tier)
		tier_badge.add_theme_font_size_override("font_size", 8)
		tier_badge.modulate = r_color
		p.add_child(tier_badge)

		p.tooltip_text = "%s (%s)\nTier %d" % [item_name, cat_label, item_tier]
	else:
		# Slot vacío con silueta tenue
		sb.bg_color = Color(0.015, 0.03, 0.05, 0.45)
		sb.border_color = Color(border_col.r, border_col.g, border_col.b, 0.25)
		p.add_theme_stylebox_override("panel", sb)

		var center = CenterContainer.new()
		center.custom_minimum_size = Vector2(52, 52)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(center)

		var empty_lbl = Label.new()
		empty_lbl.text = glyph if glyph != "" else "-"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.modulate = Color(border_col.r, border_col.g, border_col.b, 0.3)
		center.add_child(empty_lbl)
		p.tooltip_text = "Slot vacío (%s)" % cat_label

	parent.add_child(p)


func _resolve_item_icon(item: Dictionary) -> String:
	var icon_path = str(item.get("icon", ""))
	var search_id = str(item.get("id", "")).to_lower()
	if icon_path != "" and icon_path != "null" and ResourceLoader.exists(icon_path):
		return icon_path

	var emergency_map = {
		"las1": "res://assets/Armas/Arma1/Arma1.png", "las2": "res://assets/Armas/Arma2/Arma2.png", "las3": "res://assets/Armas/Arma3/Arma3.png",
		"las4": "res://assets/Armas/Arma4/Arma4.png", "las5": "res://assets/Armas/Arma5/Arma5.png", "las6": "res://assets/Armas/Arma6/Arma6.png",
		"sh1": "res://assets/Escudos/Escudo1/Escudo1.png", "sh2": "res://assets/Escudos/Escudo2/Escudo2.png", "sh3": "res://assets/Escudos/Escudo3/Escudo3.png",
		"sh4": "res://assets/Escudos/Escudo4/Escudo4.png", "sh5": "res://assets/Escudos/Escudo5/Escudo5.png", "sh6": "res://assets/Escudos/Escudo6/Escudo6.png",
		"en1": "res://assets/Motores/Motor1/Motor1.png", "en2": "res://assets/Motores/Motor2/Motor2.png", "en3": "res://assets/Motores/Motor3/Motor3.png"
	}
	if emergency_map.has(search_id): return emergency_map[search_id]

	if GameConstants and "SHOP_ITEMS" in GameConstants:
		for cat_key in GameConstants.SHOP_ITEMS:
			var category = GameConstants.SHOP_ITEMS[cat_key]
			if category is Dictionary:
				for sub_key in category:
					var sub_list = category[sub_key]
					if sub_list is Array:
						for shop_item in sub_list:
							if str(shop_item.get("id", "")).to_lower() == search_id:
								var ic = str(shop_item.get("icon", ""))
								if ic != "" and ResourceLoader.exists(ic): return ic
			elif category is Array:
				for shop_item in category:
					if str(shop_item.get("id", "")).to_lower() == search_id:
						var ic = str(shop_item.get("icon", ""))
						if ic != "" and ResourceLoader.exists(ic): return ic

	if search_id.begins_with("las"):
		return "res://assets/Armas/Arma" + search_id.replace("las", "") + "/Arma" + search_id.replace("las", "") + ".png"
	elif search_id.begins_with("sh"):
		return "res://assets/Escudos/Escudo" + search_id.replace("sh", "") + "/Escudo" + search_id.replace("sh", "") + ".png"
	elif search_id.begins_with("en"):
		return "res://assets/Motores/Motor" + search_id.replace("en", "") + "/Motor" + search_id.replace("en", "") + ".png"

	return ""


func _get_item_icon(item: Dictionary) -> Texture2D:
	if item.is_empty():
		return null
	var icon_path = _resolve_item_icon(item)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var t = InventoryCache.get_texture(icon_path)
		if t: return t
		return load(icon_path)
	return null


func toggle():
	if is_open:
		close()
	else:
		inspect_current_target()


func close():
	is_open = false
	visible = false
	z_index = 0
	target_player_node = null


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(640.0, vp_size.x * 0.92)
	var target_h = min(610.0, vp_size.y * 0.90)
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
	if not is_open: return

	var focus_node = get_viewport().gui_get_focus_owner()
	if focus_node is LineEdit or focus_node is TextEdit: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _notify_user(msg: String, type: String = "info"):
	var main_hud = get_tree().get_first_node_in_group("hud")
	if not is_instance_valid(main_hud):
		main_hud = get_tree().get_first_node_in_group("main_hud")
	if is_instance_valid(main_hud) and main_hud.has_method("notify"):
		main_hud.notify(msg, type)
	else:
		print("[INSPECT] ", msg)
