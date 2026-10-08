extends Control

# ==============================================================================
# PlayerInventoryUI.gd - Sistema de Equipamiento e Inventario Estilo Mu Online
# ==============================================================================
# - Ventana flotante/arrastrable "EQUIPAMIENTO"
# - Selector de naves integrado en la cabecera del Paperdoll (◀ NAVE ▶ + [ACTIVAR])
# - Slots de Armas, Escudos, Motores y Extras estrictamente CUADRADOS (46x46)
# - Estadísticas en vivo: ATK, ESC, VEL, HP
# - Rejilla táctica de la mochila con filtros por categoría
# - Coordinación 100% autoritativa con el servidor (equipItem, unequipItem, switchShip, sellItem)
# ==============================================================================

const ItemInfoHelper = preload("res://scripts/ui/inventory/ItemInfoHelper.gd")

# Estado de datos del inventario y la flota
var inventory_items: Array = []
var equipped_data: Dictionary = {"w": [], "s": [], "e": [], "x": []}
var equipped_by_ship: Dictionary = {}
var owned_ships: Array = []
var current_ship_id: int = 1   # Nave activa en el servidor
var viewing_ship_id: int = 1   # Nave siendo inspeccionada/configurada actualmente
var hubs: int = 0
var ohcu: int = 0
var is_open: bool = false

# Filtro activo de la mochila: "all", "modules", "consumables", "resources"
var current_filter: String = "all"
var selected_item_for_info: Dictionary = {}

# Arrastre de ventana
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Referencias de nodos de UI
var window_panel: PanelContainer = null
var header_bar: Control = null

# Selector de naves
var ship_dropdown_btn: MenuButton = null
var ship_activate_btn: Button = null
var ship_status_label: Label = null

# Contenedores de slots del Paperdoll
var left_slots_container: VBoxContainer = null
var right_slots_container: VBoxContainer = null
var bottom_engine_container: HBoxContainer = null
var bottom_extra_container: HBoxContainer = null

# Stats del Paperdoll
var stat_atk_label: Label = null
var stat_def_label: Label = null
var stat_vel_label: Label = null
var stat_hp_label: Label = null

# Mochila / Rejilla
var bag_grid: GridContainer = null
var bag_capacity_label: Label = null
var filter_btns: Dictionary = {}

# Balances
var hubs_label: Label = null
var ohcu_label: Label = null

# Visor 3D de la nave
var vp_container: SubViewportContainer = null
var sub_viewport: SubViewport = null
var ship_pivot: Node3D = null
var current_rendered_ship_id: int = -1

# Tooltip detallado de ítem
var tooltip_panel: PanelContainer = null
var tooltip_target_node: Control = null
var tooltip_title: Label = null
var tooltip_type: Label = null
var tooltip_stats: Label = null
var tooltip_reqs: Label = null
var tooltip_actions_hb: HBoxContainer = null

# Modales activos
var active_modales: Array = []


func _ready():
	add_to_group("inventory_ui")
	add_to_group("player_inventory_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	_build_ui_structure()
	_connect_network_signals()
	_connect_player_signals()
	
	InventoryCache.preload_all()
	
	if NetworkManager and NetworkManager.is_logged_in and NetworkManager.current_user_data:
		_on_inventory_received(NetworkManager.current_user_data)


func _connect_network_signals():
	if not NetworkManager: return
	if not NetworkManager.inventory_data.is_connected(_on_inventory_received):
		NetworkManager.inventory_data.connect(_on_inventory_received)
	if not NetworkManager.login_success.is_connected(_on_auth_data):
		NetworkManager.login_success.connect(_on_auth_data)
	if not NetworkManager.auth_success.is_connected(_on_auth_data):
		NetworkManager.auth_success.connect(_on_auth_data)
	if NetworkManager.has_signal("ship_equip_data"):
		if not NetworkManager.ship_equip_data.is_connected(_on_ship_equip_data):
			NetworkManager.ship_equip_data.connect(_on_ship_equip_data)
	if not NetworkManager.game_notification.is_connected(_on_game_notification):
		NetworkManager.game_notification.connect(_on_game_notification)
	if NetworkManager.has_signal("config_updated"):
		if not NetworkManager.config_updated.is_connected(_on_server_config_updated):
			NetworkManager.config_updated.connect(_on_server_config_updated)
	if NetworkManager.has_signal("admin_config_updated"):
		if not NetworkManager.admin_config_updated.is_connected(_on_server_config_updated):
			NetworkManager.admin_config_updated.connect(_on_server_config_updated)


func _on_server_config_updated(_cfg: Dictionary = {}):
	if is_open:
		update_ui()


func _connect_player_signals():
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_signal("stats_changed"):
		if not p.stats_changed.is_connected(_on_player_stats_changed):
			p.stats_changed.connect(_on_player_stats_changed)


func _on_auth_data(d: Dictionary):
	_on_inventory_received(d)


func _on_player_stats_changed(p_data: Dictionary):
	if p_data.has("hubs"): hubs = int(p_data["hubs"])
	if p_data.has("ohcu"): ohcu = int(p_data["ohcu"])
	_update_currencies_ui()


func _on_ship_equip_data(data: Dictionary):
	var sid = str(data.get("shipId", -1))
	var equip = data.get("equip", {})
	if sid == "-1" or not equip: return
	equipped_by_ship[sid] = equip
	if is_open and str(viewing_ship_id) == sid:
		update_ui()


func _on_game_notification(data: Dictionary):
	var msg = str(data.get("msg", ""))
	var type = str(data.get("type", "info"))
	if is_open and type == "error":
		_show_message_modal("AVISO DEL SISTEMA", msg)


# ==============================================================================
# CONSTRUCCIÓN DE LA INTERFAZ
# ==============================================================================
func _build_ui_structure():
	var blocker = Control.new()
	blocker.name = "ClickBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blocker)

	# Ventana principal
	window_panel = PanelContainer.new()
	window_panel.name = "MuInventoryWindow"
	window_panel.custom_minimum_size = Vector2(430, 680)
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	window_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
	)
	
	var sb_win = StyleBoxFlat.new()
	sb_win.bg_color = Color(0.012, 0.022, 0.035, 0.97)
	sb_win.border_width_left = 2; sb_win.border_width_top = 2
	sb_win.border_width_right = 2; sb_win.border_width_bottom = 2
	sb_win.border_color = Color(0.0, 0.82, 0.96, 0.75)
	sb_win.set_corner_radius_all(8)
	sb_win.shadow_color = Color(0, 0, 0, 0.65)
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
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# ──────────────────────────────────────────────────────────────────────────
	# A. CABECERA: "EQUIPAMIENTO"
	# ──────────────────────────────────────────────────────────────────────────
	header_bar = PanelContainer.new()
	header_bar.custom_minimum_size = Vector2(0, 34)
	var sb_header = StyleBoxFlat.new()
	sb_header.bg_color = Color(0.02, 0.05, 0.08, 0.9)
	sb_header.border_width_bottom = 1
	sb_header.border_color = Color(0.0, 0.82, 0.96, 0.4)
	sb_header.corner_radius_top_left = 6
	sb_header.corner_radius_top_right = 6
	header_bar.add_theme_stylebox_override("panel", sb_header)
	header_bar.gui_input.connect(_on_header_gui_input)
	main_vbox.add_child(header_bar)

	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 8)
	header_bar.add_child(h_box)

	var icon_title = Label.new()
	icon_title.text = " 🛡️ "
	icon_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(icon_title)

	var title_lbl = Label.new()
	title_lbl.text = "EQUIPAMIENTO"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_box.add_child(title_lbl)

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

	# ──────────────────────────────────────────────────────────────────────────
	# B. PAPERDOLL DE EQUIPAMIENTO
	# ──────────────────────────────────────────────────────────────────────────
	var equip_panel = PanelContainer.new()
	var sb_equip = StyleBoxFlat.new()
	sb_equip.bg_color = Color(0.018, 0.03, 0.045, 0.8)
	sb_equip.border_width_left = 1; sb_equip.border_width_top = 1
	sb_equip.border_width_right = 1; sb_equip.border_width_bottom = 1
	sb_equip.border_color = Color(0.15, 0.28, 0.38, 0.5)
	sb_equip.set_corner_radius_all(6)
	equip_panel.add_theme_stylebox_override("panel", sb_equip)
	main_vbox.add_child(equip_panel)

	var equip_vbox = VBoxContainer.new()
	equip_vbox.add_theme_constant_override("separation", 6)
	var equip_margin = MarginContainer.new()
	equip_margin.add_theme_constant_override("margin_top", 8)
	equip_margin.add_theme_constant_override("margin_bottom", 8)
	equip_margin.add_theme_constant_override("margin_left", 8)
	equip_margin.add_theme_constant_override("margin_right", 8)
	equip_margin.add_child(equip_vbox)
	equip_panel.add_child(equip_margin)

	# Fila 1: SELECTOR DE NAVES INTEGRADO (◀  NOPLA 5  ▶   [ACTIVAR] / ● ACTIVA)
	var ship_selector_hb = HBoxContainer.new()
	ship_selector_hb.add_theme_constant_override("separation", 6)
	ship_selector_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	equip_vbox.add_child(ship_selector_hb)

	var btn_prev = Button.new()
	btn_prev.text = "◀"
	btn_prev.custom_minimum_size = Vector2(26, 26)
	btn_prev.add_theme_font_size_override("font_size", 9)
	var sb_arrow = StyleBoxFlat.new()
	sb_arrow.bg_color = Color(0.08, 0.14, 0.2, 0.8)
	sb_arrow.border_width_left = 1; sb_arrow.border_width_top = 1
	sb_arrow.border_width_right = 1; sb_arrow.border_width_bottom = 1
	sb_arrow.border_color = Color(0.0, 0.82, 0.96, 0.4)
	sb_arrow.set_corner_radius_all(4)
	btn_prev.add_theme_stylebox_override("normal", sb_arrow)
	btn_prev.pressed.connect(_cycle_previous_ship)
	ship_selector_hb.add_child(btn_prev)

	# Menú desplegable con el nombre de la nave
	ship_dropdown_btn = MenuButton.new()
	ship_dropdown_btn.custom_minimum_size = Vector2(170, 26)
	ship_dropdown_btn.add_theme_font_size_override("font_size", 11)
	ship_dropdown_btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	var sb_drop = StyleBoxFlat.new()
	sb_drop.bg_color = Color(0.04, 0.08, 0.12, 0.9)
	sb_drop.border_width_left = 1; sb_drop.border_width_top = 1
	sb_drop.border_width_right = 1; sb_drop.border_width_bottom = 1
	sb_drop.border_color = Color(0.2, 0.4, 0.6, 0.5)
	sb_drop.set_corner_radius_all(4)
	ship_dropdown_btn.add_theme_stylebox_override("normal", sb_drop)
	ship_dropdown_btn.get_popup().id_pressed.connect(_on_ship_menu_selected)
	ship_selector_hb.add_child(ship_dropdown_btn)

	var btn_next = Button.new()
	btn_next.text = "▶"
	btn_next.custom_minimum_size = Vector2(26, 26)
	btn_next.add_theme_font_size_override("font_size", 9)
	btn_next.add_theme_stylebox_override("normal", sb_arrow)
	btn_next.pressed.connect(_cycle_next_ship)
	ship_selector_hb.add_child(btn_next)

	var ship_sp = Control.new()
	ship_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_selector_hb.add_child(ship_sp)

	# Botón Activar (visible cuando se visualiza una nave no activa)
	ship_activate_btn = Button.new()
	ship_activate_btn.text = "ACTIVAR"
	ship_activate_btn.custom_minimum_size = Vector2(80, 26)
	ship_activate_btn.add_theme_font_size_override("font_size", 9)
	var sb_act = StyleBoxFlat.new()
	sb_act.bg_color = Color(0.05, 0.35, 0.25, 0.9)
	sb_act.border_width_left = 1; sb_act.border_width_top = 1
	sb_act.border_width_right = 1; sb_act.border_width_bottom = 1
	sb_act.border_color = Color.GREEN
	sb_act.set_corner_radius_all(4)
	ship_activate_btn.add_theme_stylebox_override("normal", sb_act)
	ship_activate_btn.pressed.connect(_on_activate_ship_pressed)
	ship_selector_hb.add_child(ship_activate_btn)

	# Badge Activa (visible cuando la nave vista ya es la activa)
	ship_status_label = Label.new()
	ship_status_label.text = "● ACTIVA"
	ship_status_label.add_theme_font_size_override("font_size", 10)
	ship_status_label.add_theme_color_override("font_color", Color.GREEN)
	ship_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ship_selector_hb.add_child(ship_status_label)

	# Fila 2: El Paperdoll Central (Slots Armas Cuadraditos + Visor 3D Centro + Slots Escudos Cuadraditos)
	var doll_hb = HBoxContainer.new()
	doll_hb.add_theme_constant_override("separation", 10)
	doll_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	equip_vbox.add_child(doll_hb)

	# Columna Izquierda: Armas (W)
	var left_v = VBoxContainer.new()
	left_v.custom_minimum_size.x = 94
	left_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 4)
	doll_hb.add_child(left_v)

	var l_title = Label.new()
	l_title.text = "ARMAS (W)"
	l_title.add_theme_font_size_override("font_size", 9)
	l_title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 0.85))
	l_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_v.add_child(l_title)

	left_slots_container = VBoxContainer.new()
	left_slots_container.add_theme_constant_override("separation", 5)
	left_slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	left_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_slots_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_child(left_slots_container)

	# Centro: Visor 3D
	var center_panel = PanelContainer.new()
	center_panel.custom_minimum_size = Vector2(182, 160)
	var sb_center = StyleBoxFlat.new()
	sb_center.bg_color = Color(0.0, 0.05, 0.08, 0.5)
	sb_center.border_width_left = 1; sb_center.border_width_top = 1
	sb_center.border_width_right = 1; sb_center.border_width_bottom = 1
	sb_center.border_color = Color(0.0, 0.6, 0.8, 0.3)
	sb_center.set_corner_radius_all(6)
	center_panel.add_theme_stylebox_override("panel", sb_center)
	doll_hb.add_child(center_panel)

	_setup_3d_ship_viewport(center_panel)

	# Columna Derecha: Escudos (S)
	var right_v = VBoxContainer.new()
	right_v.custom_minimum_size.x = 94
	right_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", 4)
	doll_hb.add_child(right_v)

	var r_title = Label.new()
	r_title.text = "ESCUDOS (S)"
	r_title.add_theme_font_size_override("font_size", 9)
	r_title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0, 0.85))
	r_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_v.add_child(r_title)

	right_slots_container = VBoxContainer.new()
	right_slots_container.add_theme_constant_override("separation", 5)
	right_slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	right_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_slots_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_v.add_child(right_slots_container)

	# Fila 3: Motores (E) y Extras (X) abajo
	var bottom_doll_hb = HBoxContainer.new()
	bottom_doll_hb.add_theme_constant_override("separation", 12)
	bottom_doll_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	equip_vbox.add_child(bottom_doll_hb)

	# Motores
	var eng_v = VBoxContainer.new()
	eng_v.add_theme_constant_override("separation", 2)
	bottom_doll_hb.add_child(eng_v)

	var eng_lbl = Label.new()
	eng_lbl.text = "MOTOR (E)"
	eng_lbl.add_theme_font_size_override("font_size", 8)
	eng_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.8))
	eng_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eng_v.add_child(eng_lbl)

	bottom_engine_container = HBoxContainer.new()
	bottom_engine_container.add_theme_constant_override("separation", 4)
	bottom_engine_container.alignment = BoxContainer.ALIGNMENT_CENTER
	eng_v.add_child(bottom_engine_container)

	# Extras
	var ext_v = VBoxContainer.new()
	ext_v.add_theme_constant_override("separation", 2)
	bottom_doll_hb.add_child(ext_v)

	var ext_lbl = Label.new()
	ext_lbl.text = "EXTRAS (X)"
	ext_lbl.add_theme_font_size_override("font_size", 8)
	ext_lbl.add_theme_color_override("font_color", Color(0.8, 0.45, 1.0, 0.8))
	ext_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ext_v.add_child(ext_lbl)

	bottom_extra_container = HBoxContainer.new()
	bottom_extra_container.add_theme_constant_override("separation", 4)
	bottom_extra_container.alignment = BoxContainer.ALIGNMENT_CENTER
	ext_v.add_child(bottom_extra_container)

	# Fila 4: Tarjetas Rápidas de Estadísticas Tácticas (ATK, ESC, VEL, HP)
	var stats_hb = HBoxContainer.new()
	stats_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_hb.add_theme_constant_override("separation", 6)
	equip_vbox.add_child(stats_hb)

	stat_atk_label = _create_stat_badge(stats_hb, "⚔️ ATK", Color(1.0, 0.35, 0.35))
	stat_def_label = _create_stat_badge(stats_hb, "🛡️ ESC", Color(0.0, 0.85, 1.0))
	stat_vel_label = _create_stat_badge(stats_hb, "⚡ VEL", Color(1.0, 0.85, 0.2))
	stat_hp_label = _create_stat_badge(stats_hb, "❤️ HP", Color(0.3, 1.0, 0.5))

	# ──────────────────────────────────────────────────────────────────────────
	# C. SECCIÓN DE MOCHILA / BODEGA (REJILLA MU ONLINE)
	# ──────────────────────────────────────────────────────────────────────────
	var bag_panel = PanelContainer.new()
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb_bag = StyleBoxFlat.new()
	sb_bag.bg_color = Color(0.015, 0.025, 0.04, 0.9)
	sb_bag.border_width_left = 1; sb_bag.border_width_top = 1
	sb_bag.border_width_right = 1; sb_bag.border_width_bottom = 1
	sb_bag.border_color = Color(0.12, 0.22, 0.32, 0.6)
	sb_bag.set_corner_radius_all(6)
	bag_panel.add_theme_stylebox_override("panel", sb_bag)
	main_vbox.add_child(bag_panel)

	var bag_vbox = VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 6)
	var bag_margin = MarginContainer.new()
	bag_margin.add_theme_constant_override("margin_top", 6)
	bag_margin.add_theme_constant_override("margin_bottom", 6)
	bag_margin.add_theme_constant_override("margin_left", 6)
	bag_margin.add_theme_constant_override("margin_right", 6)
	bag_margin.add_child(bag_vbox)
	bag_panel.add_child(bag_margin)

	var filters_hb = HBoxContainer.new()
	filters_hb.add_theme_constant_override("separation", 4)
	bag_vbox.add_child(filters_hb)

	filter_btns["all"] = _create_filter_tab(filters_hb, "TODOS", "all")
	filter_btns["modules"] = _create_filter_tab(filters_hb, "EQUIPO", "modules")
	filter_btns["consumables"] = _create_filter_tab(filters_hb, "USABLES", "consumables")
	filter_btns["resources"] = _create_filter_tab(filters_hb, "RECURSOS", "resources")

	var filter_sp = Control.new()
	filter_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters_hb.add_child(filter_sp)

	bag_capacity_label = Label.new()
	bag_capacity_label.text = "0/36"
	bag_capacity_label.add_theme_font_size_override("font_size", 9)
	bag_capacity_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.7))
	bag_capacity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filters_hb.add_child(bag_capacity_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_vbox.add_child(scroll)

	bag_grid = GridContainer.new()
	bag_grid.columns = 6
	bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_grid.add_theme_constant_override("h_separation", 6)
	bag_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(bag_grid)

	# ──────────────────────────────────────────────────────────────────────────
	# D. PIE DE VENTANA: SALDOS (HUBS / OHCU) Y ACCIONES RÁPIDAS
	# ──────────────────────────────────────────────────────────────────────────
	var footer_hb = HBoxContainer.new()
	footer_hb.add_theme_constant_override("separation", 10)
	footer_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(footer_hb)

	var hubs_box = HBoxContainer.new()
	hubs_box.add_theme_constant_override("separation", 3)
	var hubs_icon = Label.new(); hubs_icon.text = "🟡"; hubs_icon.add_theme_font_size_override("font_size", 10); hubs_box.add_child(hubs_icon)
	hubs_label = Label.new()
	hubs_label.text = "0 HUBS"
	hubs_label.add_theme_font_size_override("font_size", 10)
	hubs_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.85))
	hubs_box.add_child(hubs_label)
	footer_hb.add_child(hubs_box)

	var ohcu_box = HBoxContainer.new()
	ohcu_box.add_theme_constant_override("separation", 3)
	var ohcu_icon = Label.new(); ohcu_icon.text = "💎"; ohcu_icon.add_theme_font_size_override("font_size", 10); ohcu_box.add_child(ohcu_icon)
	ohcu_label = Label.new()
	ohcu_label.text = "0 OHC"
	ohcu_label.add_theme_font_size_override("font_size", 10)
	ohcu_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.9))
	ohcu_box.add_child(ohcu_label)
	footer_hb.add_child(ohcu_box)

	var foot_sp = Control.new()
	foot_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hb.add_child(foot_sp)

	var btn_sort = Button.new()
	btn_sort.text = " 🔄 ORDENAR "
	btn_sort.add_theme_font_size_override("font_size", 9)
	var sb_sort = StyleBoxFlat.new()
	sb_sort.bg_color = Color(0.08, 0.15, 0.22, 0.8)
	sb_sort.border_width_bottom = 1
	sb_sort.border_color = Color.CYAN
	sb_sort.set_corner_radius_all(4)
	btn_sort.add_theme_stylebox_override("normal", sb_sort)
	btn_sort.pressed.connect(_sort_inventory)
	footer_hb.add_child(btn_sort)

	_setup_tooltip_panel()


func _create_stat_badge(parent: Control, title: String, color: Color) -> Label:
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(92, 26)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.08)
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(color.r, color.g, color.b, 0.4)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 4)
	p.add_child(hb)

	var t = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 8)
	t.add_theme_color_override("font_color", color)
	hb.add_child(t)

	var v = Label.new()
	v.text = "0"
	v.add_theme_font_size_override("font_size", 8)
	v.add_theme_color_override("font_color", Color.WHITE)
	hb.add_child(v)
	return v


func _create_filter_tab(parent: Control, label_text: String, filter_key: String) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 8)
	btn.custom_minimum_size = Vector2(58, 22)
	_update_filter_button_style(btn, filter_key == current_filter)
	btn.pressed.connect(func():
		current_filter = filter_key
		for k in filter_btns:
			_update_filter_button_style(filter_btns[k], k == current_filter)
		_render_bag_grid()
	)
	parent.add_child(btn)
	return btn


func _update_filter_button_style(btn: Button, is_selected: bool):
	var sb = StyleBoxFlat.new()
	if is_selected:
		sb.bg_color = Color(0.0, 0.6, 0.8, 0.4)
		sb.border_width_bottom = 2
		sb.border_color = Color.CYAN
	else:
		sb.bg_color = Color(0.05, 0.08, 0.12, 0.6)
	sb.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", sb)


# ==============================================================================
# VISOR 3D DE LA NAVE
# ==============================================================================
func _setup_3d_ship_viewport(parent: Control):
	vp_container = SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(vp_container)

	sub_viewport = SubViewport.new()
	sub_viewport.own_world_3d = true
	sub_viewport.transparent_bg = true
	sub_viewport.msaa_3d = Viewport.MSAA_DISABLED
	sub_viewport.positional_shadow_atlas_size = 0
	if "use_hdr_3d" in sub_viewport: sub_viewport.use_hdr_3d = false
	vp_container.add_child(sub_viewport)

	var node3d = Node3D.new()
	sub_viewport.add_child(node3d)

	var env = WorldEnvironment.new()
	var w_env = Environment.new()
	w_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w_env.ambient_light_color = Color(0.2, 0.25, 0.35)
	w_env.ambient_light_energy = 0.7
	w_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = w_env
	node3d.add_child(env)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 38.0
	cam.position = Vector3(0, 1.2, 3.2)
	node3d.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.1, 0))

	var key_light = DirectionalLight3D.new()
	key_light.light_energy = 1.9
	key_light.light_color = Color(1.0, 0.95, 0.85)
	key_light.shadow_enabled = false
	key_light.rotation_degrees = Vector3(-35, 45, 0)
	node3d.add_child(key_light)

	var fill_light = DirectionalLight3D.new()
	fill_light.light_energy = 0.8
	fill_light.light_color = Color(0.4, 0.8, 1.0)
	fill_light.shadow_enabled = false
	fill_light.rotation_degrees = Vector3(25, -135, 0)
	node3d.add_child(fill_light)

	ship_pivot = Node3D.new()
	ship_pivot.name = "ShipPivot"
	ship_pivot.scale = Vector3(1.15, 1.15, 1.15)
	node3d.add_child(ship_pivot)


func _update_3d_ship_model():
	if not is_instance_valid(ship_pivot): return
	if current_rendered_ship_id == viewing_ship_id and ship_pivot.get_child_count() > 0:
		return
	
	current_rendered_ship_id = viewing_ship_id
	for c in ship_pivot.get_children():
		ship_pivot.remove_child(c)
		c.queue_free()

	var ship_data = {}
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == viewing_ship_id:
				ship_data = s
				break

	var glb_path = ""
	if ship_data.has("assetPath") and ship_data.assetPath != "":
		glb_path = ship_data.assetPath
	else:
		match viewing_ship_id:
			1: glb_path = "res://assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb"
			2: glb_path = "res://assets/Personajes/3D/Nave2/Nave2.glb"
			3: glb_path = "res://assets/Personajes/3D/Nave3/Nave3.glb"
			4: glb_path = "res://assets/Personajes/3D/Nave4/Nave4.glb"
			5: glb_path = "res://assets/Personajes/3D/Nave5/Nave5.glb"
			6: glb_path = "res://assets/Personajes/3D/Nave6/Nave6.glb"

	if glb_path != "" and ResourceLoader.exists(glb_path):
		var model_scene = InventoryCache.get_model(glb_path)
		if not model_scene:
			model_scene = load(glb_path)
		
		if model_scene:
			var instance = model_scene.instantiate()
			_clean_internal_lights(instance)
			if viewing_ship_id >= 1 and viewing_ship_id <= 6:
				_make_materials_unshaded(instance)
			ship_pivot.add_child(instance)

			if ship_data.has("rotX") or ship_data.has("rotY") or ship_data.has("rotZ"):
				instance.rotation_degrees.x = float(ship_data.get("rotX", 0))
				instance.rotation_degrees.y = float(ship_data.get("rotY", 0))
				instance.rotation_degrees.z = float(ship_data.get("rotZ", 0))
			else:
				match viewing_ship_id:
					3: instance.rotation_degrees = Vector3(0, 1, 98)
					4: instance.rotation_degrees = Vector3(0, -180, 52)
					6: instance.rotation_degrees.y = 180
					_: instance.rotation_degrees = Vector3.ZERO


func _clean_internal_lights(node: Node):
	for child in node.get_children():
		if child is Light3D: child.queue_free()
		else: _clean_internal_lights(child)


func _make_materials_unshaded(node: Node):
	if node is MeshInstance3D:
		if node.material_override and node.material_override is BaseMaterial3D:
			if node.material_override.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				node.material_override = node.material_override.duplicate()
				node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		else:
			var s_count = node.get_surface_override_material_count()
			if s_count == 0 and node.mesh: s_count = node.mesh.get_surface_count()
			for i in range(s_count):
				var mat = node.get_surface_override_material(i)
				if mat and mat is BaseMaterial3D:
					if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
						var dup = mat.duplicate()
						dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						node.set_surface_override_material(i, dup)
	for c in node.get_children():
		_make_materials_unshaded(c)


func _process(delta):
	if is_open and is_instance_valid(ship_pivot):
		ship_pivot.rotation.y += delta * 0.65
	
	if is_instance_valid(tooltip_panel) and tooltip_panel.visible:
		if tooltip_target_node == null or not is_instance_valid(tooltip_target_node):
			hide_tooltip()


# ==============================================================================
# SELECTOR DE NAVES (HANGAR INTEGRADO) Y VISIBILIDAD ADMINDASH
# ==============================================================================
# v620.0: Ojito de visibilidad — respeta las naves ocultas en el AdminDash
func _is_ship_hidden(sid: int) -> bool:
	if not GameConstants.SHIP_MODELS: return false
	for m in GameConstants.SHIP_MODELS:
		if int(m.get("id", -1)) == sid:
			return bool(m.get("hidden", false))
	return false


# v620.0: Ojito de visibilidad — respeta ítems ocultos en el AdminDash
func _is_item_hidden(item_id: String) -> bool:
	if item_id == "": return false
	var search_id = item_id.to_lower()
	if GameConstants.SHOP_ITEMS:
		for cat_key in GameConstants.SHOP_ITEMS:
			var category = GameConstants.SHOP_ITEMS[cat_key]
			if category is Dictionary:
				for sub_key in category:
					var sub_list = category[sub_key]
					if sub_list is Array:
						for shop_item in sub_list:
							if str(shop_item.get("id", "")).to_lower() == search_id:
								return bool(shop_item.get("hidden", false))
			elif category is Array:
				for shop_item in category:
					if str(shop_item.get("id", "")).to_lower() == search_id:
						return bool(shop_item.get("hidden", false))
	return false


func _get_available_ships() -> Array:
	var list: Array = []
	if not owned_ships.is_empty():
		for s in owned_ships:
			var sid = int(s)
			if sid > 0 and not list.has(sid):
				# No incluir naves ocultas por el AdminDash
				if _is_ship_hidden(sid):
					continue
				list.append(sid)
	
	if list.is_empty():
		# Si la nave activa no está oculta, incluirla
		if not _is_ship_hidden(int(current_ship_id)):
			list = [int(current_ship_id)]
		else:
			# Si la activa está oculta, buscar el primer modelo visible en GameConstants
			if GameConstants.SHIP_MODELS:
				for m in GameConstants.SHIP_MODELS:
					if not m.get("hidden", false):
						list.append(int(m.get("id", 1)))
						break
			if list.is_empty():
				list = [1]
	return list


func _get_ship_display_name(sid: int) -> String:
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == sid:
				return str(s.get("name", "Nave " + str(sid))).to_upper()
	return "NAVE " + str(sid)


func _update_ship_selector_ui():
	var list = _get_available_ships()
	if not list.has(viewing_ship_id):
		if list.has(current_ship_id):
			viewing_ship_id = current_ship_id
		elif not list.is_empty():
			viewing_ship_id = list[0]
		current_rendered_ship_id = -1
		_update_3d_ship_model()

	var current_idx = list.find(viewing_ship_id)
	var total_count = list.size()
	var s_name = _get_ship_display_name(viewing_ship_id)
	
	if is_instance_valid(ship_dropdown_btn):
		var count_str = ""
		if total_count > 1 and current_idx >= 0:
			count_str = " (" + str(current_idx + 1) + "/" + str(total_count) + ")"
		ship_dropdown_btn.text = s_name + count_str + " ▼"
		
		# Actualizar opciones del popup
		var popup = ship_dropdown_btn.get_popup()
		popup.clear()
		for sid in list:
			var item_name = _get_ship_display_name(sid)
			if sid == current_ship_id: item_name += " [ACTIVA]"
			popup.add_item(item_name, sid)

	# Actualizar botón Activar vs Badge Activa
	var is_active = (viewing_ship_id == current_ship_id)
	if is_instance_valid(ship_activate_btn):
		ship_activate_btn.visible = not is_active
	if is_instance_valid(ship_status_label):
		ship_status_label.visible = is_active


func _cycle_previous_ship():
	var list = _get_available_ships()
	if list.size() <= 1: return
	var idx = list.find(viewing_ship_id)
	if idx == -1: idx = 0
	idx = (idx - 1 + list.size()) % list.size()
	_select_ship_to_view(list[idx])


func _cycle_next_ship():
	var list = _get_available_ships()
	if list.size() <= 1: return
	var idx = list.find(viewing_ship_id)
	if idx == -1: idx = 0
	idx = (idx + 1) % list.size()
	_select_ship_to_view(list[idx])


func _on_ship_menu_selected(sid: int):
	_select_ship_to_view(sid)


func _select_ship_to_view(sid: int):
	viewing_ship_id = sid
	var sid_str = str(viewing_ship_id)
	if not equipped_by_ship.has(sid_str):
		if NetworkManager:
			NetworkManager.send_event("getShipEquip", viewing_ship_id)
	update_ui()


func _on_activate_ship_pressed():
	if _is_player_in_combat():
		NetworkManager.game_notification.emit({
			"msg": "ERROR: Sistemas de armas calientes. Espera fuera de combate para cambiar de nave.",
			"type": "error"
		})
		return
	
	if NetworkManager:
		NetworkManager.send_event("switchShip", {"shipId": viewing_ship_id})
		current_ship_id = viewing_ship_id
		update_ui()


# ==============================================================================
# TOOLTIP DETALLADO DE ÍTEM
# ==============================================================================
func _setup_tooltip_panel():
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "ItemTooltip"
	tooltip_panel.visible = false
	tooltip_panel.custom_minimum_size = Vector2(230, 0)
	tooltip_panel.size = Vector2(230, 80)
	tooltip_panel.z_index = 150
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tooltip_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	tooltip_panel.add_child(margin)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size.x = 210
	margin.add_child(v)

	tooltip_title = Label.new()
	tooltip_title.add_theme_font_size_override("font_size", 11)
	tooltip_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_title.custom_minimum_size.x = 210
	v.add_child(tooltip_title)

	tooltip_type = Label.new()
	tooltip_type.add_theme_font_size_override("font_size", 8)
	tooltip_type.modulate = Color(0.7, 0.7, 0.7)
	tooltip_type.custom_minimum_size.x = 210
	v.add_child(tooltip_type)

	v.add_child(HSeparator.new())

	tooltip_stats = Label.new()
	tooltip_stats.add_theme_font_size_override("font_size", 9)
	tooltip_stats.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	tooltip_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_stats.custom_minimum_size.x = 210
	v.add_child(tooltip_stats)

	tooltip_reqs = Label.new()
	tooltip_reqs.add_theme_font_size_override("font_size", 8)
	tooltip_reqs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_reqs.custom_minimum_size.x = 210
	v.add_child(tooltip_reqs)

	tooltip_actions_hb = HBoxContainer.new()
	tooltip_actions_hb.add_theme_constant_override("separation", 6)
	v.add_child(tooltip_actions_hb)


func show_tooltip(item: Dictionary, target: Control, is_equipped_slot: bool = false, slot_type: String = "", slot_index: int = -1):
	if not is_instance_valid(target) or item.is_empty(): return
	tooltip_target_node = target
	selected_item_for_info = item

	var rarity = int(item.get("rarity", 0))
	var rarity_color = ItemInfoHelper.rarity_color(rarity)
	if item.has("color") and str(item.get("color", "")) != "":
		rarity_color = Color.from_string(str(item["color"]), rarity_color)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.025, 0.04, 0.98)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = rarity_color
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.75)
	sb.shadow_size = 12
	tooltip_panel.add_theme_stylebox_override("panel", sb)

	tooltip_title.text = str(item.get("name", "ÍTEM")).to_upper()
	tooltip_title.add_theme_color_override("font_color", rarity_color)

	var amount = int(item.get("amount", 1))
	var type_line = ItemInfoHelper.rarity_label(rarity) + " | " + str(item.get("type", "MÓDULO")).to_upper()
	if amount > 1: type_line += " x" + str(amount)
	tooltip_type.text = type_line

	tooltip_stats.text = ItemInfoHelper.format_stats(item)

	var req_text = ""
	if NetworkManager:
		var req_check = NetworkManager.check_equip_requirements(str(item.get("id", "")))
		if not req_check.get("ok", true):
			req_text = "🔒 " + str(req_check.get("msg", "Requisitos no cumplidos"))
			tooltip_reqs.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			req_text = "✔ Requisitos cumplidos"
			tooltip_reqs.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	tooltip_reqs.text = req_text
	tooltip_reqs.visible = (req_text != "")

	for c in tooltip_actions_hb.get_children():
		tooltip_actions_hb.remove_child(c)
		c.queue_free()

	if is_equipped_slot:
		var btn_unequip = Button.new()
		btn_unequip.text = "DESEQUIPAR"
		btn_unequip.add_theme_font_size_override("font_size", 8)
		btn_unequip.pressed.connect(func():
			_unequip_item(slot_type, slot_index, item)
			hide_tooltip()
		)
		tooltip_actions_hb.add_child(btn_unequip)
	else:
		var item_type = str(item.get("type", "")).to_lower()
		var is_consumable = (item_type == "consumible")
		var is_resource = (item_type == "resource" or item_type == "recipe" or str(item.get("id", "")).begins_with("mat_"))

		if not is_resource and not is_consumable:
			var btn_equip = Button.new()
			btn_equip.text = "EQUIPAR"
			btn_equip.add_theme_font_size_override("font_size", 8)
			btn_equip.pressed.connect(func():
				_equip_item(item)
				hide_tooltip()
			)
			tooltip_actions_hb.add_child(btn_equip)
		elif is_consumable:
			var btn_use = Button.new()
			btn_use.text = "USAR"
			btn_use.add_theme_font_size_override("font_size", 8)
			btn_use.modulate = Color(0.5, 1.0, 0.6)
			btn_use.pressed.connect(func():
				_use_item(item)
				hide_tooltip()
			)
			tooltip_actions_hb.add_child(btn_use)

		if amount > 1:
			var btn_split = Button.new()
			btn_split.text = "SEPARAR"
			btn_split.add_theme_font_size_override("font_size", 8)
			btn_split.pressed.connect(func():
				_open_split_modal(item)
				hide_tooltip()
			)
			tooltip_actions_hb.add_child(btn_split)

		if not is_consumable:
			var btn_sell = Button.new()
			btn_sell.text = "VENDER"
			btn_sell.add_theme_font_size_override("font_size", 8)
			btn_sell.modulate = Color(1.0, 0.45, 0.45)
			btn_sell.pressed.connect(func():
				_open_sell_modal(item)
				hide_tooltip()
			)
			tooltip_actions_hb.add_child(btn_sell)

	tooltip_panel.visible = true
	# Resetear y forzar tamaño compacto de inmediato para evitar estiramiento inicial
	tooltip_panel.size = Vector2(230, 0)
	tooltip_panel.reset_size()

	var min_s = tooltip_panel.get_combined_minimum_size()
	var final_w = maxf(230.0, min_s.x)
	var final_h = maxf(min_s.y, 70.0)
	if final_h > 360.0:
		final_h = 360.0
	tooltip_panel.size = Vector2(final_w, final_h)

	if get_parent() and tooltip_panel.get_parent() == self:
		move_child(tooltip_panel, get_child_count() - 1)

	var target_pos = target.global_position
	var new_pos = target_pos + Vector2(-final_w - 12, 0)
	if new_pos.x < 10:
		new_pos.x = target_pos.x + target.size.x + 12
	var vp_h = get_viewport_rect().size.y
	if new_pos.y + final_h > vp_h:
		new_pos.y = maxf(10.0, vp_h - final_h - 10.0)
	if new_pos.y < 10: new_pos.y = 10
	tooltip_panel.global_position = new_pos


func hide_tooltip():
	if is_instance_valid(tooltip_panel):
		tooltip_panel.visible = false
	tooltip_target_node = null


# ==============================================================================
# RENDERIZADO Y ACTUALIZACIÓN DE DATOS
# ==============================================================================
func update_ui():
	if not is_open: return
	hide_tooltip()
	
	_update_3d_ship_model()
	_update_ship_selector_ui()
	_update_ship_info_and_stats()
	_render_equipment_slots()
	_render_bag_grid()
	_update_currencies_ui()


func _update_ship_info_and_stats():
	var ship_model = {}
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == viewing_ship_id:
				ship_model = s; break
	if ship_model.is_empty() and GameConstants.SHIP_MODELS.size() > 0:
		ship_model = GameConstants.SHIP_MODELS[0]

	var base_hp = float(ship_model.get("hp", 100))
	var base_sh = float(ship_model.get("shield", 100))
	var base_speed = float(ship_model.get("speed", 250))
	var base_atk = float(ship_model.get("baseDmg", ship_model.get("base_damage", 100)))

	var total_hp_bonus = 0.0; var hp_mod_flat = 0.0; var hp_mod_pct = 0.0
	var total_sh_bonus = 0.0; var shield_mod_flat = 0.0; var shield_mod_pct = 0.0
	var speed_bonus = 0.0; var speed_mod_flat = 0.0; var speed_mod_pct = 0.0
	var bonus_w = 0.0; var dmg_mod_flat = 0.0; var dmg_mod_pct = 0.0

	var ship_e = _get_viewing_ship_equip()

	for it in ship_e.get("w", []):
		if _is_item_hidden(str(it.get("id", ""))): continue
		bonus_w += float(it.get("base", 0))
		var sv = float(it.get("speedMod", 0))
		if it.get("speedModType", "percent") == "flat": speed_mod_flat += sv
		else: speed_mod_pct += sv
		var hv = float(it.get("hpMod", 0))
		if it.get("hpModType", "percent") == "flat": hp_mod_flat += hv
		else: hp_mod_pct += hv

	for it in ship_e.get("s", []):
		if _is_item_hidden(str(it.get("id", ""))): continue
		total_sh_bonus += float(it.get("base", 0))
		var hv = float(it.get("hpMod", 0))
		if it.get("hpModType", "percent") == "flat": hp_mod_flat += hv
		else: hp_mod_pct += hv
		var sv = float(it.get("speedMod", 0))
		if it.get("speedModType", "percent") == "flat": speed_mod_flat += sv
		else: speed_mod_pct += sv

	for it in ship_e.get("e", []):
		if _is_item_hidden(str(it.get("id", ""))): continue
		speed_bonus += float(it.get("base", 0))
		var shv = float(it.get("shieldMod", 0))
		if it.get("shieldModType", "percent") == "flat": shield_mod_flat += shv
		else: shield_mod_pct += shv
		var hv = float(it.get("hpMod", 0))
		if it.get("hpModType", "percent") == "flat": hp_mod_flat += hv
		else: hp_mod_pct += hv

	for it in ship_e.get("x", []):
		if _is_item_hidden(str(it.get("id", ""))): continue
		total_hp_bonus += float(it.get("base", 0))

	var final_hp = (base_hp + total_hp_bonus + hp_mod_flat) * (1.0 + hp_mod_pct / 100.0)
	var final_sh = (base_sh + total_sh_bonus + shield_mod_flat) * (1.0 + shield_mod_pct / 100.0)
	var final_speed = (base_speed + speed_bonus + speed_mod_flat) * (1.0 + speed_mod_pct / 100.0)
	var final_atk = ((base_atk + bonus_w) * (1.0 + dmg_mod_pct / 100.0)) + dmg_mod_flat

	stat_atk_label.text = str(int(round(final_atk)))
	stat_def_label.text = str(int(round(final_sh)))
	stat_vel_label.text = str(int(round(final_speed)))
	stat_hp_label.text = str(int(round(final_hp)))


func _get_viewing_ship_equip() -> Dictionary:
	var sid_str = str(viewing_ship_id)
	if equipped_by_ship.has(sid_str): return equipped_by_ship[sid_str]
	if viewing_ship_id == current_ship_id and not equipped_data.is_empty(): return equipped_data
	return {"w": [], "s": [], "e": [], "x": []}


func _filter_slot_items(items: Array) -> Array:
	var out = []
	for it in items:
		if it != null and it is Dictionary and _is_item_hidden(str(it.get("id", ""))):
			out.append(null)
		else:
			out.append(it)
	return out


# Renderizado de ranuras estrictamente CUADRADAS (W, S, E, X)
func _render_equipment_slots():
	var ship_model = {}
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == viewing_ship_id: ship_model = s; break
	var slot_caps = ship_model.get("slots", {"w": 1, "s": 1, "e": 1, "x": 1})
	var ship_equip = _get_viewing_ship_equip()

	_populate_slot_column(left_slots_container, "w", slot_caps.get("w", 1), _filter_slot_items(ship_equip.get("w", [])), Color(1.0, 0.25, 0.25))
	_populate_slot_column(right_slots_container, "s", slot_caps.get("s", 1), _filter_slot_items(ship_equip.get("s", [])), Color(0.0, 0.85, 1.0))
	_populate_slot_row(bottom_engine_container, "e", slot_caps.get("e", 1), _filter_slot_items(ship_equip.get("e", [])), Color(1.0, 0.85, 0.2))
	_populate_slot_row(bottom_extra_container, "x", slot_caps.get("x", 1), _filter_slot_items(ship_equip.get("x", [])), Color(0.8, 0.45, 1.0))


func _populate_slot_column(container: Control, slot_type: String, max_slots: int, items_array: Array, theme_color: Color):
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

	var grid = GridContainer.new()
	grid.columns = 2 if max_slots >= 4 else 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(grid)

	for i in range(max_slots):
		var item_data = items_array[i] if i < items_array.size() else null
		var slot_card = _create_slot_card(slot_type, i, item_data, theme_color)
		grid.add_child(slot_card)


func _populate_slot_row(container: Control, slot_type: String, max_slots: int, items_array: Array, theme_color: Color):
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

	var grid = GridContainer.new()
	grid.columns = 6 if slot_type == "e" else 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(grid)

	for i in range(max_slots):
		var item_data = items_array[i] if i < items_array.size() else null
		var slot_card = _create_slot_card(slot_type, i, item_data, theme_color)
		grid.add_child(slot_card)


func _create_slot_card(slot_type: String, slot_index: int, item_data, theme_color: Color) -> PanelContainer:
	var p = PanelContainer.new()
	# Tamaño estrictamente CUADRADO (46x46) para que queden bonitos y uniformes
	p.custom_minimum_size = Vector2(46, 46)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 2
	sb.content_margin_top = 2
	sb.content_margin_right = 2
	sb.content_margin_bottom = 2
	if item_data != null:
		var rarity = int(item_data.get("rarity", 0))
		var r_color = ItemInfoHelper.rarity_color(rarity)
		sb.bg_color = Color(r_color.r, r_color.g, r_color.b, 0.12)
		sb.border_width_left = 2; sb.border_width_top = 2
		sb.border_width_right = 2; sb.border_width_bottom = 2
		sb.border_color = r_color
	else:
		sb.bg_color = Color(0.02, 0.04, 0.06, 0.75)
		sb.border_width_left = 1; sb.border_width_top = 1
		sb.border_width_right = 1; sb.border_width_bottom = 1
		sb.border_color = Color(theme_color.r, theme_color.g, theme_color.b, 0.35)
	p.add_theme_stylebox_override("panel", sb)

	var center = CenterContainer.new()
	center.custom_minimum_size = Vector2(42, 42)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(center)

	if item_data != null:
		var icon_path = _resolve_item_icon(item_data)
		if icon_path != "":
			var tex_rect = TextureRect.new()
			tex_rect.texture = _load_cached_texture(icon_path)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.custom_minimum_size = Vector2(36, 36)
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center.add_child(tex_rect)
		else:
			var fallback_lbl = Label.new()
			fallback_lbl.text = slot_type.to_upper() + str(slot_index + 1)
			fallback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			fallback_lbl.add_theme_font_size_override("font_size", 9)
			fallback_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center.add_child(fallback_lbl)

		p.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				if ev.double_click or ev.button_index == MOUSE_BUTTON_RIGHT:
					hide_tooltip()
					_unequip_item(slot_type, slot_index, item_data)
					get_viewport().set_input_as_handled()
				elif ev.button_index == MOUSE_BUTTON_LEFT:
					show_tooltip(item_data, p, true, slot_type, slot_index)
					get_viewport().set_input_as_handled()
		)
	else:
		var placeholder = Label.new()
		var glyph = "+"
		match slot_type:
			"w": glyph = "⚔"
			"s": glyph = "🛡"
			"e": glyph = "⚡"
			"x": glyph = "💎"
		placeholder.text = glyph
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 12)
		placeholder.modulate = Color(theme_color.r, theme_color.g, theme_color.b, 0.3)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(placeholder)

	return p


# Renderizado de la Mochila (GridContainer de 6 columnas)
func _render_bag_grid():
	for c in bag_grid.get_children():
		bag_grid.remove_child(c)
		c.queue_free()

	var filtered_items: Array = []
	for it in inventory_items:
		if it == null or not it is Dictionary: continue
		var iid = str(it.get("id", "")).to_lower()
		if _is_item_hidden(iid): continue # v620.0: Ojito de visibilidad del AdminDash
		var itype = str(it.get("type", "")).to_lower()
		var slot_code = _get_slot_from_id(iid)

		match current_filter:
			"modules":
				if slot_code in ["w", "s", "e", "x"] and itype != "resource" and itype != "recipe" and itype != "consumible":
					filtered_items.append(it)
			"consumables":
				if itype == "consumible" or int(it.get("grantShip", 0)) > 0:
					filtered_items.append(it)
			"resources":
				if itype == "resource" or itype == "recipe" or iid.begins_with("mat_") or iid.begins_with("recipe_"):
					filtered_items.append(it)
			_:
				filtered_items.append(it)

	bag_capacity_label.text = str(inventory_items.size()) + " / 48"

	for item in filtered_items:
		var slot_cell = _create_bag_slot_cell(item)
		bag_grid.add_child(slot_cell)

	var total_slots_shown = max(30, filtered_items.size())
	for i in range(filtered_items.size(), total_slots_shown):
		var empty_cell = _create_empty_bag_cell()
		bag_grid.add_child(empty_cell)


func _create_bag_slot_cell(item: Dictionary) -> PanelContainer:
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(50, 50)
	
	var rarity = int(item.get("rarity", 0))
	var rarity_color = ItemInfoHelper.rarity_color(rarity)
	if item.has("color") and str(item.get("color", "")) != "":
		rarity_color = Color.from_string(str(item["color"]), rarity_color)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.08)
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.border_color = rarity_color
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)

	var icon_path = _resolve_item_icon(item)
	if icon_path != "":
		var tex_rect = TextureRect.new()
		tex_rect.texture = _load_cached_texture(icon_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(38, 38)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tex_rect)

	var amount = int(item.get("amount", 1))
	if amount > 1:
		var amt_lbl = Label.new()
		amt_lbl.text = "x" + str(amount)
		amt_lbl.add_theme_font_size_override("font_size", 8)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		amt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		amt_lbl.add_theme_constant_override("outline_size", 3)
		amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(amt_lbl)

	if NetworkManager:
		var req_check = NetworkManager.check_equip_requirements(str(item.get("id", "")))
		if not req_check.get("ok", true):
			var lock_lbl = Label.new()
			lock_lbl.text = "🔒"
			lock_lbl.add_theme_font_size_override("font_size", 8)
			lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(lock_lbl)

	p.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.double_click or ev.button_index == MOUSE_BUTTON_RIGHT:
				hide_tooltip()
				_on_item_double_clicked(item)
				get_viewport().set_input_as_handled()
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				show_tooltip(item, p, false)
				get_viewport().set_input_as_handled()
	)

	return p


func _create_empty_bag_cell() -> PanelContainer:
	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(50, 50)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.03, 0.045, 0.5)
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(0.1, 0.16, 0.22, 0.4)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _update_currencies_ui():
	if is_instance_valid(hubs_label):
		hubs_label.text = _format_thousands(hubs) + " HUBS"
	if is_instance_valid(ohcu_label):
		ohcu_label.text = _format_thousands(ohcu) + " OHC"


func _format_thousands(v: int) -> String:
	var s = str(v)
	var res = ""
	var c = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		c += 1
		if c == 3 and i != 0:
			res = "." + res
			c = 0
	return res


# ==============================================================================
# LÓGICA DE EQUIPAR / DESEQUIPAR / USAR / VENDER
# ==============================================================================
func _on_item_double_clicked(item: Dictionary):
	var itype = str(item.get("type", "")).to_lower()
	if itype == "consumible" or int(item.get("grantShip", 0)) > 0:
		_use_item(item)
	elif itype != "resource" and itype != "recipe" and not str(item.get("id", "")).begins_with("mat_"):
		_equip_item(item)


func _equip_item(item: Dictionary):
	if _is_player_in_combat():
		NetworkManager.game_notification.emit({
			"msg": "ERROR: No puedes modificar tu equipamiento en combate.",
			"type": "error"
		})
		return

	var iid = item.get("instanceId", "")
	var item_id = str(item.get("id", ""))

	if NetworkManager:
		var req_check = NetworkManager.check_equip_requirements(item_id)
		if not req_check.get("ok", true):
			NetworkManager.game_notification.emit({
				"msg": "EQUIPAMIENTO BLOQUEADO: " + str(req_check.get("msg", "Requisitos no cumplidos")),
				"type": "error"
			})
			return

	var slot = _get_slot_from_id(item_id)
	var sid_str = str(viewing_ship_id)
	if not equipped_by_ship.has(sid_str):
		equipped_by_ship[sid_str] = {"w": [], "s": [], "e": [], "x": []}

	var ship_model = {}
	if GameConstants.SHIP_MODELS:
		for s in GameConstants.SHIP_MODELS:
			if int(s.get("id")) == viewing_ship_id: ship_model = s; break
	var slot_caps = ship_model.get("slots", {"w": 1, "s": 1, "e": 1, "x": 1})
	var max_for_slot = slot_caps.get(slot, 1)

	if equipped_by_ship[sid_str][slot].size() >= max_for_slot:
		NetworkManager.game_notification.emit({
			"msg": "SLOTS LLENOS: Desequipa un módulo de esa categoría primero.",
			"type": "error"
		})
		return

	equipped_by_ship[sid_str][slot].append(item.duplicate(true))
	inventory_items = inventory_items.filter(func(x): return x.get("instanceId", "") != iid)
	update_ui()

	if NetworkManager:
		NetworkManager.send_event("equipItem", {"instanceId": iid, "shipId": viewing_ship_id})


func _unequip_item(slot_type: String, slot_index: int, item_data: Dictionary):
	if _is_player_in_combat():
		NetworkManager.game_notification.emit({
			"msg": "ERROR: No puedes modificar tu equipamiento en combate.",
			"type": "error"
		})
		return

	var sid_str = str(viewing_ship_id)
	if equipped_by_ship.has(sid_str) and equipped_by_ship[sid_str].has(slot_type):
		if slot_index >= 0 and slot_index < equipped_by_ship[sid_str][slot_type].size():
			equipped_by_ship[sid_str][slot_type].remove_at(slot_index)
			inventory_items.append(item_data.duplicate(true))
			update_ui()
			
			if NetworkManager:
				NetworkManager.send_event("unequipItem", {
					"category": slot_type,
					"instanceId": item_data.get("instanceId", ""),
					"shipId": viewing_ship_id
				})


func _use_item(item: Dictionary):
	var iid = item.get("instanceId", "")
	var it_name = str(item.get("name", "ÍTEM"))
	var msg = "¿Deseas usar [color=yellow]" + it_name + "[/color]? Se consumirá el ítem."
	_show_confirm_modal("USAR ÍTEM", msg, func():
		if NetworkManager:
			NetworkManager.send_event("useConsumableItem", {"instanceId": iid})
	)


func _open_split_modal(item: Dictionary):
	var amount = int(item.get("amount", 1))
	if amount <= 1: return

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	var lbl = Label.new(); lbl.text = "Cantidad a separar:"; lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)

	var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hb)

	var slider = HSlider.new()
	slider.min_value = 1; slider.max_value = amount - 1; slider.value = amount - 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(slider)

	var edit = LineEdit.new()
	edit.text = str(amount - 1); edit.custom_minimum_size.x = 60
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(edit)

	slider.value_changed.connect(func(val): edit.text = str(int(val)))
	edit.text_changed.connect(func(txt): slider.value = clamp(int(txt), 1, amount - 1))

	var msg = "¿Cuántas unidades deseas separar del stack?"
	_show_confirm_modal("SEPARAR STACK", msg, func():
		if NetworkManager:
			NetworkManager.send_event("splitStack", {
				"instanceId": item.get("instanceId", ""),
				"quantity": int(slider.value)
			})
	, v)


func _open_sell_modal(item: Dictionary):
	if _is_player_in_combat():
		NetworkManager.game_notification.emit({
			"msg": "ERROR: Sistemas calientes. Espera para vender.",
			"type": "error"
		})
		return

	var amount = int(item.get("amount", 1))
	var search_id = str(item.get("id", "")).to_lower()
	var single_refund = 0

	for cat_key in GameConstants.SHOP_ITEMS:
		var category = GameConstants.SHOP_ITEMS[cat_key]
		if category is Array:
			for shop_item in category:
				if str(shop_item.get("id", "")).to_lower() == search_id:
					var prices = shop_item.get("prices", {})
					if prices.has("hubs"): single_refund = int(prices["hubs"] / 2)
					break
		if single_refund > 0: break

	var it_name = str(item.get("name", "ÍTEM"))
	if amount > 1:
		var v = VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)

		var lbl = Label.new(); lbl.text = "Cantidad a vender:"; lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lbl)

		var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(hb)

		var slider = HSlider.new()
		slider.min_value = 1; slider.max_value = amount; slider.value = amount
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(slider)

		var edit = LineEdit.new()
		edit.text = str(amount); edit.custom_minimum_size.x = 60
		edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(edit)

		var ref_lbl = Label.new(); ref_lbl.text = "Reembolso: " + str(single_refund * amount) + " HUBS"
		ref_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ref_lbl)

		slider.value_changed.connect(func(val):
			edit.text = str(int(val))
			ref_lbl.text = "Reembolso: " + str(single_refund * int(val)) + " HUBS"
		)
		edit.text_changed.connect(func(txt):
			var v_int = clamp(int(txt), 1, amount)
			slider.value = v_int
			ref_lbl.text = "Reembolso: " + str(single_refund * v_int) + " HUBS"
		)

		var msg = "¿Confirmas la venta de [color=yellow]" + it_name + "[/color]?"
		_show_confirm_modal("CONFIRMAR VENTA PARCIAL", msg, func():
			if NetworkManager:
				NetworkManager.send_event("sellItem", {
					"instanceId": item.get("instanceId", ""),
					"quantity": int(slider.value)
				})
		, v)
	else:
		var msg = "¿Confirmas la venta de [color=yellow]" + it_name + "[/color] por [color=green]" + str(single_refund) + " HUBS[/color]?"
		_show_confirm_modal("CONFIRMAR VENTA", msg, func():
			if NetworkManager:
				NetworkManager.send_event("sellItem", {"instanceId": item.get("instanceId", "")})
		)


func _sort_inventory():
	if inventory_items.is_empty(): return
	var order = {"w": 0, "s": 1, "e": 2, "x": 3, "consumible": 4, "resource": 5}
	inventory_items.sort_custom(func(a, b):
		var sa = _get_slot_from_id(str(a.get("id", "")))
		var sb = _get_slot_from_id(str(b.get("id", "")))
		var oa = order.get(sa, 99)
		var ob = order.get(sb, 99)
		if oa != ob: return oa < ob
		var ra = int(a.get("rarity", 0))
		var rb = int(b.get("rarity", 0))
		if ra != rb: return ra > rb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	_render_bag_grid()


func _is_player_in_combat() -> bool:
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_method("is_in_combat"):
		return p.is_in_combat()
	return false


# ==============================================================================
# RESOLUCIÓN DE ÍCONOS Y TEXTURAS
# ==============================================================================
func _get_slot_from_id(item_id: String) -> String:
	var id = item_id.to_lower()
	if id.begins_with("las") or id.begins_with("w"): return "w"
	elif id.begins_with("sh") or id.begins_with("s"): return "s"
	elif id.begins_with("en") or id.begins_with("e"):
		if id.begins_with("esfera_"): return "x"
		return "e"
	return "x"


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


func _load_cached_texture(path: String) -> Texture2D:
	if path == "": return null
	var t = InventoryCache.get_texture(path)
	if t: return t
	if ResourceLoader.exists(path): return load(path)
	return null


# ==============================================================================
# SINCRONIZACIÓN CON EL SERVIDOR
# ==============================================================================
func _on_inventory_received(data: Dictionary):
	if data.has("player") and typeof(data.player) == TYPE_DICTIONARY:
		data = data.player
	if data.has("gameData") and typeof(data.gameData) == TYPE_DICTIONARY:
		var gd = data.gameData
		for k in gd.keys():
			if not data.has(k) or (data[k] is Array and data[k].is_empty()) or (data[k] is Dictionary and data[k].is_empty()):
				data[k] = gd[k]

	if data.has("inventory") or data.has("items"):
		inventory_items = data.get("inventory", data.get("items", []))
	if data.has("equipped"):
		equipped_data = data.equipped
	if data.has("ownedShips"):
		owned_ships = data.ownedShips
	if data.has("currentShipId"):
		current_ship_id = int(data.currentShipId)
		if not owned_ships.has(viewing_ship_id):
			viewing_ship_id = current_ship_id
	if data.has("ohcu"): ohcu = int(data.ohcu)
	if data.has("hubs"): hubs = int(data.hubs)
	if data.has("equippedByShip"):
		var raw = data.equippedByShip
		equipped_by_ship = {}
		for key in raw.keys():
			equipped_by_ship[str(key)] = raw[key]

	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p):
		p.hubs = hubs
		p.ohculianos = ohcu
		p.inventory = inventory_items
		p.equipped = equipped_data
		if p.has_method("_recalculate_stats"): p._recalculate_stats()
		elif p.has_method("_emit_stats"): p._emit_stats()

	if is_open:
		call_deferred("update_ui")


# ==============================================================================
# CONTROL DE VISIBILIDAD, ATAJOS Y DRAG
# ==============================================================================
func toggle():
	is_open = !is_open
	visible = is_open

	if is_open:
		hide_tooltip()
		_reposition_window()
		_connect_player_signals()
		viewing_ship_id = current_ship_id
		if NetworkManager: NetworkManager.send_event("getInventory", {})
		update_ui()
		if get_parent():
			get_parent().move_child(self, get_parent().get_child_count() - 1)
			z_index = 105
	else:
		hide_tooltip()
		_close_all_modales()
		z_index = 0


func _reposition_window():
	var vp_size = get_viewport_rect().size
	var target_w = min(430.0, vp_size.x * 0.95)
	var target_h = min(680.0, vp_size.y * 0.92)
	window_panel.custom_minimum_size = Vector2(target_w, target_h)
	window_panel.size = Vector2(target_w, target_h)
	var pos_x = vp_size.x - target_w - 20.0
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

	if event.is_action_pressed("ui_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not is_open: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if active_modales.size() > 0:
			var m = active_modales.pop_back()
			if is_instance_valid(m): m.queue_free()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(tooltip_panel) and tooltip_panel.visible:
			hide_tooltip()
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
		return


# ==============================================================================
# MODALES DE CONFIRMACIÓN
# ==============================================================================
func _show_confirm_modal(title: String, msg: String, on_confirm: Callable, custom_node: Control = null):
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 130
	get_tree().root.add_child(canvas_layer)
	active_modales.append(canvas_layer)

	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)

	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(380, 180)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.03, 0.05, 0.98)
	sb.border_width_top = 2
	sb.border_color = Color.CYAN
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	overlay.add_child(p)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 15)
	p.add_child(v)

	var tl = Label.new(); tl.text = title; tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_color", Color.CYAN); v.add_child(tl)

	var rt = RichTextLabel.new(); rt.bbcode_enabled = true; rt.text = "[center]" + msg + "[/center]"
	rt.fit_content = true; v.add_child(rt)

	if custom_node: v.add_child(custom_node)

	var hb = HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 15)
	v.add_child(hb)

	var btn_ok = Button.new(); btn_ok.text = "CONFIRMAR"; btn_ok.custom_minimum_size = Vector2(100, 32)
	btn_ok.pressed.connect(func():
		on_confirm.call()
		active_modales.erase(canvas_layer)
		canvas_layer.queue_free()
	)
	hb.add_child(btn_ok)

	var btn_cancel = Button.new(); btn_cancel.text = "CANCELAR"; btn_cancel.custom_minimum_size = Vector2(100, 32)
	btn_cancel.pressed.connect(func():
		active_modales.erase(canvas_layer)
		canvas_layer.queue_free()
	)
	hb.add_child(btn_cancel)


func _show_message_modal(title: String, msg: String):
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 131
	get_tree().root.add_child(canvas_layer)
	active_modales.append(canvas_layer)

	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(overlay)

	var p = PanelContainer.new()
	p.custom_minimum_size = Vector2(340, 140)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.04, 0.98)
	sb.border_width_top = 2
	sb.border_color = Color(1.0, 0.35, 0.35)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	overlay.add_child(p)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)

	var tl = Label.new(); tl.text = title; tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35)); v.add_child(tl)

	var lb = Label.new(); lb.text = msg; lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(lb)

	var btn = Button.new(); btn.text = "ENTENDIDO"; btn.custom_minimum_size = Vector2(100, 30)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		active_modales.erase(canvas_layer)
		canvas_layer.queue_free()
	)
	v.add_child(btn)


func _close_all_modales():
	for m in active_modales:
		if is_instance_valid(m): m.queue_free()
	active_modales.clear()
