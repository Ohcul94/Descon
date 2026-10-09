extends Control

# TouchControls.gd (v1.1 - Componente de Controles Táctiles y Grid Container)

var virtual_joystick = null
var grid_container: GridContainer = null
var rows: int = 2

# v370.8: Colapso/Expansión de la barra de mini iconos
var collapsed: bool = false
var collapse_btn: Button = null

# v901.0: Un solo mini icono que despliega la lista de paneles de UI (check/uncheck)
# Reemplaza a los mini iconos que solo alternaban la visibilidad de un panel.
const UI_PANEL_ITEMS: Array = [
	{"id": "RadarWindow",     "icon": "🛰️", "label": "Minimapa"},
	{"id": "ChatUI",          "icon": "💬", "label": "Chat"},
	{"id": "PartyHUD",        "icon": "👥", "label": "Escuadrón"},
	{"id": "CombatMeter",     "icon": "📊", "label": "Métricas de Combate"},
	{"id": "TopLeft",         "icon": "📈", "label": "Diagnósticos (FPS/MS)"},
	{"id": "TargetFrame",     "icon": "🎯", "label": "Marco de Objetivo"},
	{"id": "StatusEffects",   "icon": "✨", "label": "Estados Activos"},
	{"id": "PortalBtnContainer", "icon": "🌀", "label": "Botón de Acción"},
]
const UI_PANEL_IDS: Array = ["RadarWindow", "ChatUI", "PartyHUD", "CombatMeter", "TopLeft", "TargetFrame", "StatusEffects", "PortalBtnContainer"]

var ui_list_btn: Button = null
var ui_list_panel: PanelContainer = null
var ui_list_checks: Dictionary = {}

func set_rows(p_rows: int):
	rows = p_rows
	if grid_container:
		grid_container.columns = 6 if rows == 2 else 10
		_reorder_icons_by_category()
		grid_container.reset_size()
		reset_size()
		_apply_bar_size()
		emit_signal("resized")

func _apply_bar_size():
	reset_size()
	if collapsed and is_instance_valid(collapse_btn):
		custom_minimum_size = collapse_btn.get_combined_minimum_size()
	else:
		custom_minimum_size = grid_container.get_combined_minimum_size()
	size = custom_minimum_size
	emit_signal("resized")

func _ready():
	print("[TouchControls] Inicializando controles táctiles.")
	
	# Crear un GridContainer dinámico de columnas según la configuración de filas
	grid_container = GridContainer.new()
	grid_container.name = "GridContainer"
	grid_container.columns = 6 if rows == 2 else 10
	grid_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 6)
	grid_container.add_theme_constant_override("v_separation", 6)
	add_child(grid_container)
	
	# Mover los hijos estáticos en diferido para evitar bloqueos del layout en _ready
	call_deferred("_defer_move_existing_children")
	
	# v266.400: Inyectar Joystick Virtual (Soporte Móvil)
	_setup_joystick()
	_update_joystick_visibility()

func _defer_move_existing_children():
	var existing_children = []
	for child in get_children():
		# v901.0: IconCollapse se queda fuera del grid para seguir visible al colapsar
		if child is Button and child.name != "GridContainer" and child.name != "IconCollapse":
			existing_children.append(child)
			
	for child in existing_children:
		remove_child(child)
		# v901.0: Los botones que solo alternaban un panel HUD pasan a la lista con checkboxes
		if _panel_id_for_button(child.name.replace("Icon", "")) != "":
			child.queue_free()
		else:
			grid_container.add_child(child)
	
	# Re-vincular y actualizar tooltips
	_update_icon_tooltips()
	
	# v238.20: Sincronía Táctil Autorizativa (Esperar al Login)
	if NetworkManager:
		if not NetworkManager.login_success.is_connected(_setup_touch_buttons):
			NetworkManager.login_success.connect(func(_d): 
				_setup_touch_buttons()
				_reorder_icons_by_category()
			)
			
	# También correr la configuración inicial de botones si ya estamos logueados
	if NetworkManager and NetworkManager.is_logged_in:
		_setup_touch_buttons()

	# Icono de escuadrón inicial (Siempre Visible)
	_setup_squad_and_events_icons()
	
	# Reordenar iconos por categoría después de que todos estén creados
	_reorder_icons_by_category()
	
	# Botón de colapso/expansión de la barra (solo afecta a los mini iconos)
	_setup_collapse_button()

	# v901.0: Mini icono único que despliega la lista de paneles de UI
	_setup_ui_list_button()

# v370.8: Botón que colapsa/expande únicamente los mini iconos de la barra.
# Los paneles que abren esos iconos (Chat, Stats, Radar, etc.) NO se ven afectados.
func _setup_collapse_button():
	if collapse_btn: return
	collapse_btn = Button.new()
	collapse_btn.name = "IconCollapse"
	collapse_btn.text = "◀"
	collapse_btn.custom_minimum_size = Vector2(36, 36)
	collapse_btn.tooltip_text = "Colapsar iconos de control"
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	sb.set_corner_radius_all(6)
	collapse_btn.add_theme_stylebox_override("normal", sb)
	
	var h_sb = sb.duplicate()
	h_sb.bg_color = Color(0.3, 0.5, 0.6, 0.8)
	h_sb.border_width_bottom = 2
	h_sb.border_color = Color.CYAN
	collapse_btn.add_theme_stylebox_override("hover", h_sb)
	
	var p_sb = sb.duplicate()
	p_sb.bg_color = Color(0.2, 0.4, 0.5, 0.9)
	collapse_btn.add_theme_stylebox_override("pressed", p_sb)
	
	collapse_btn.pressed.connect(_on_collapse_pressed)
	add_child(collapse_btn)
	_apply_bar_size()

func _on_collapse_pressed():
	var main_hud = get_parent()
	if main_hud and main_hud.has_method("is_editing_layout") and main_hud.is_editing_layout:
		return
	set_collapsed(!collapsed)

func set_collapsed(p_collapsed: bool):
	if collapsed == p_collapsed: return
	collapsed = p_collapsed
	grid_container.visible = not collapsed
	collapse_btn.text = "▶" if collapsed else "◀"
	collapse_btn.tooltip_text = "Expandir iconos de control" if collapsed else "Colapsar iconos de control"
	_apply_bar_size()

func _setup_squad_and_events_icons():
	# Icono Squad (Siempre Visible)
	if not grid_container.has_node("IconSquad"):
		var btn = Button.new()
		btn.name = "IconSquad"
		btn.text = "👥"
		btn.custom_minimum_size = Vector2(32,32)
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.1,0.1,0.1,0.6); sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(_on_icon_pressed.bind("Squad"))
		grid_container.add_child(btn)
		
	# Icono Eventos (Nuevo v2.2)
	if not grid_container.has_node("IconEvents"):
		var btn = Button.new()
		btn.name = "IconEvents"
		btn.text = "🏆"
		btn.tooltip_text = "Eventos y Modos de Juego [F2]"
		btn.custom_minimum_size = Vector2(32,32)
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.1,0.1,0.1,0.6); sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(_on_icon_pressed.bind("Events"))
		grid_container.add_child(btn)
		
	# Eliminar IconStay si existe de instancias previas
	if grid_container.has_node("IconStay"):
		grid_container.get_node("IconStay").queue_free()

# Iconos que abren menús/modales (no toggle de UI)
var _menu_icon_ids: Array = ["EscMenu", "Inventory", "Map", "Logistics", "Housing", "Events", "BattlePass", "Quests"]

func _get_icon_category(btn_name: String) -> String:
	if btn_name == "IconUIList":
		return "list"
	var id = btn_name.replace("Icon", "")
	if id in _menu_icon_ids:
		return "menu"
	return "toggle"

func _reorder_icons_by_category():
	if not is_instance_valid(grid_container): return
	
	var all_buttons: Array = []
	for child in grid_container.get_children():
		if child is Button:
			all_buttons.append(child)
	
	if all_buttons.is_empty(): return
	
	var list_btns: Array = []
	var menu_btns: Array = []
	var toggle_btns: Array = []
	for btn in all_buttons:
		var cat = _get_icon_category(btn.name)
		if cat == "list":
			list_btns.append(btn)
		elif cat == "menu":
			menu_btns.append(btn)
		else:
			toggle_btns.append(btn)
	
	var ordered: Array
	if rows == 2:
		ordered = toggle_btns + menu_btns
	else:
		ordered = menu_btns + toggle_btns
	# v901.0: El acceso a la lista de paneles siempre va primero (izquierda)
	ordered = list_btns + ordered
	
	for i in range(ordered.size()):
		grid_container.move_child(ordered[i], i)
	
	grid_container.reset_size()
	reset_size()
	custom_minimum_size = grid_container.get_combined_minimum_size()
	size = custom_minimum_size
	queue_redraw()

func _setup_joystick():
	if virtual_joystick: return
	var joy_script = load("res://scripts/ui/VirtualJoystick.gd")
	if joy_script:
		virtual_joystick = joy_script.new()
		virtual_joystick.name = "VirtualJoystick"
		get_parent().add_child.call_deferred(virtual_joystick) # Agregado al MainHUD
		virtual_joystick.joystick_updated.connect(_on_joystick_updated)
		print("[TouchControls] Joystick Virtual inyectado.")

func _on_joystick_updated(dir: Vector2):
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_method("set_joystick_direction"):
		p.set_joystick_direction(dir)

func _update_joystick_visibility():
	if not virtual_joystick:
		await get_tree().process_frame
	if virtual_joystick:
		var main_hud = get_parent()
		var editing = main_hud and main_hud.get("is_editing_layout")
		var enabled = SettingsManager.mobile_mode if SettingsManager else false
		# El joystick no participa del editor de layout (es flotante, sigue el tap)
		virtual_joystick.visible = enabled and not editing
		virtual_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if enabled and not editing:
			virtual_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
		elif not enabled:
			virtual_joystick.global_position = Vector2(-2000, -2000)

func sync_platform_mode():
	var is_mob = SettingsManager.mobile_mode if SettingsManager else false
	if is_instance_valid(grid_container):
		var cam_btn = grid_container.get_node_or_null("IconCamEdit")
		if not is_mob:
			if is_instance_valid(cam_btn):
				cam_btn.queue_free()
		else:
			if not is_instance_valid(cam_btn):
				_setup_touch_buttons()
				_reorder_icons_by_category()
	_update_joystick_visibility()

func _setup_touch_buttons():
	var is_mob = SettingsManager.mobile_mode if SettingsManager else false
	var touch_btns = [
		{"id": "EscMenu", "icon": "⚙️", "tip": "Sistema (ESC)"}
	]
	if is_mob:
		touch_btns.append({"id": "CamEdit", "icon": "🎥", "tip": "Cámara 3D"})
	# v901.0: CombatMeter y TopLeft salieron de la barra (ahora se activan/desactivan
	# desde la lista con checkboxes del mini icono 👁️)
	touch_btns.append_array([
		{"id": "Stats", "icon": "📊", "tip": "Estadísticas (C)"},
		{"id": "Inspect", "icon": "🔍", "tip": "Inspeccionar (Y)"},
		{"id": "Squad", "icon": "👥", "tip": "Equipo / Escuadrón (P)"},
		{"id": "Inventory", "icon": "🎒", "tip": "Equipamiento (V)"},
		{"id": "Talents", "icon": "🌱", "tip": "Talentos (T)"},
		{"id": "Clan", "icon": "🛡️", "tip": "Clan / Flota (G)"},
		{"id": "Quests", "icon": "📜", "tip": "Misiones (L)"},
		{"id": "Map", "icon": "🗺️", "tip": "Mapa Galáctico (M)"},
		{"id": "Logistics", "icon": "🏢", "tip": "Logística y Flota (F1)"},
		{"id": "Housing", "icon": "🏠", "tip": "Housing (F3)"},
		{"id": "BattlePass", "icon": "🎟️", "tip": "Pase de Batalla (F4)"}
	])
	
	for data in touch_btns:
		if grid_container.has_node("Icon" + data.id): continue
		
		var btn = Button.new()
		btn.name = "Icon" + data.id
		btn.text = data.icon
		btn.custom_minimum_size = Vector2(36, 36)
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.6); sb.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", sb)
		
		var h_sb = sb.duplicate(); h_sb.bg_color = Color(0.3, 0.5, 0.6, 0.8); h_sb.border_width_bottom = 2; h_sb.border_color = Color.CYAN
		btn.add_theme_stylebox_override("hover", h_sb)
		
		btn.pressed.connect(_on_icon_pressed.bind(data.id))
		grid_container.add_child(btn)
		_update_icon_tooltips()
		print("[TouchControls] Botón táctil inyectado: ", data.id)

func _update_icon_tooltips():
	var main_hud = get_parent()
	if not main_hud: return
	
	var tooltip_lbl = main_hud.get_node_or_null("ControlBarTooltipAnchor/Label")
	if not tooltip_lbl:
		var anchor = Control.new()
		anchor.name = "ControlBarTooltipAnchor"
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.z_index = 200 # v308.20: Dibujar por encima de otras ventanas (como ChatUI)
		main_hud.add_child(anchor)
		
		anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		anchor.position = position + Vector2(0, -35)
		anchor.size = size
		
		tooltip_lbl = Label.new()
		tooltip_lbl.name = "Label"
		tooltip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tooltip_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		tooltip_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tooltip_lbl.add_theme_font_size_override("font_size", 12)
		tooltip_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		tooltip_lbl.add_theme_constant_override("outline_size", 4)
		anchor.add_child(tooltip_lbl)
		tooltip_lbl.visible = false

	var names = {
		"Inventory": "Equipamiento", 
		"Map": "Mapa Galáctico",
		"Quests": "Misiones",
		"Logistics": "Logística y Flota",
		"EscMenu": "Sistema", 
		"Events": "Eventos",
		"AdminPanel": "Admin", "Admin": "Admin",
		"Squad": "Equipo", "Party": "Equipo", "Chat": "Chat",
		"Stats": "Estadísticas", "Inspect": "Inspeccionar", "Radar": "Minimapa", "RadarWindow": "Minimapa",
		"PvP": "Modo combate", "Talents": "Talentos", "Skills": "Habilidades",
		"Housing": "Housing", "BattlePass": "Pase de Batalla", "CamEdit": "Cámara Libre",
		"CombatMeter": "Métricas",
		"TopLeft": "Diagnósticos",
		"UIList": "Mostrar / Ocultar paneles"
	}
	
	names["Stay"] = "Quedarse quieto"
	var stay_key = _get_key_text_for_action("stay_still")
	if stay_key != "":
		names["Stay"] += " (" + stay_key + ")"
	
	var buttons = []
	if is_instance_valid(grid_container):
		buttons = grid_container.get_children()
	else:
		buttons = get_children()
		
	for btn in buttons:
		if not btn is Button: continue
		
		# Unificar tamaño y estilos visuales para que todos luzcan y se comporten igual a Housing
		btn.custom_minimum_size = Vector2(36, 36)
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		sb.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", sb)
		
		var h_sb = sb.duplicate()
		h_sb.bg_color = Color(0.3, 0.5, 0.6, 0.8)
		h_sb.border_width_bottom = 2
		h_sb.border_color = Color.CYAN
		btn.add_theme_stylebox_override("hover", h_sb)
		
		var p_sb = sb.duplicate()
		p_sb.bg_color = Color(0.2, 0.4, 0.5, 0.9)
		btn.add_theme_stylebox_override("pressed", p_sb)
		
		var b_name = btn.name.replace("Icon", "")
		var final_name = names.get(b_name, b_name)
		btn.tooltip_text = ""
		
		if not btn.mouse_entered.is_connected(_on_icon_hover.bind(btn, final_name)):
			btn.mouse_entered.connect(_on_icon_hover.bind(btn, final_name))
			btn.mouse_exited.connect(_on_icon_unhover)
		
		if not btn.pressed.is_connected(_on_icon_pressed.bind(b_name)):
			btn.pressed.connect(_on_icon_pressed.bind(b_name))

func _get_key_text_for_action(action: String) -> String:
	if not InputMap.has_action(action): return ""
	var evs = InputMap.action_get_events(action)
	if evs.size() > 0:
		return evs[0].as_text().replace(" (Physical)", "").replace(" - Physical", "").to_upper()
	return ""

func _on_icon_hover(btn: Button, txt: String):
	var main_hud = get_parent()
	if not main_hud: return
	var lbl = main_hud.get_node_or_null("ControlBarTooltipAnchor/Label")
	if lbl:
		lbl.text = txt # v308.20: Removidos paréntesis según solicitud del usuario
		lbl.visible = true
		lbl.global_position.x = btn.global_position.x + (btn.size.x / 2.0) - (lbl.get_combined_minimum_size().x / 2.0)
		lbl.global_position.y = btn.global_position.y - 25

func _on_icon_unhover():
	var main_hud = get_parent()
	if not main_hud: return
	var lbl = main_hud.get_node_or_null("ControlBarTooltipAnchor/Label")
	if lbl: lbl.visible = false

func _on_icon_pressed(id: String):
	# v901.0: Mini icono único de la lista de paneles de UI
	if id == "UIList":
		_toggle_ui_list()
		return
	var main_hud = get_parent()
	if is_instance_valid(main_hud) and main_hud.has_method("_on_icon_pressed"):
		main_hud._on_icon_pressed(id)

# =====================================================================
# v901.0: LISTA DE PANELES DE UI (un solo mini icono 👁️ con checkboxes)
# =====================================================================

# Traduce el id de un botón de la barra al id del panel HUD equivalente ("": no es panel)
func _panel_id_for_button(button_id: String) -> String:
	if button_id == "Chat":
		return "ChatUI"
	if button_id in UI_PANEL_IDS:
		return button_id
	return ""

func _setup_ui_list_button():
	if is_instance_valid(ui_list_btn): return
	if not is_instance_valid(grid_container): return

	ui_list_btn = Button.new()
	ui_list_btn.name = "IconUIList"
	ui_list_btn.text = "👁️"
	ui_list_btn.tooltip_text = "Mostrar / Ocultar paneles"
	ui_list_btn.custom_minimum_size = Vector2(36, 36)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	sb.set_corner_radius_all(6)
	ui_list_btn.add_theme_stylebox_override("normal", sb)

	var h_sb = sb.duplicate()
	h_sb.bg_color = Color(0.3, 0.5, 0.6, 0.8)
	h_sb.border_width_bottom = 2
	h_sb.border_color = Color.CYAN
	ui_list_btn.add_theme_stylebox_override("hover", h_sb)

	var p_sb = sb.duplicate()
	p_sb.bg_color = Color(0.2, 0.4, 0.5, 0.9)
	ui_list_btn.add_theme_stylebox_override("pressed", p_sb)

	ui_list_btn.pressed.connect(_on_icon_pressed.bind("UIList"))
	grid_container.add_child(ui_list_btn)

	set_process_input(true)
	_reorder_icons_by_category()

func _ensure_ui_list_panel():
	if is_instance_valid(ui_list_panel): return
	var main_hud = get_parent()
	if not is_instance_valid(main_hud): return

	# Estética táctil cian coherente con los marcos Sci-Fi del HUD
	ui_list_panel = PanelContainer.new()
	ui_list_panel.name = "UIListPanel"
	ui_list_panel.z_index = 300
	ui_list_panel.visible = false
	ui_list_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.02, 0.05, 0.08, 0.97)
	psb.border_width_left = 1
	psb.border_width_top = 1
	psb.border_width_right = 1
	psb.border_width_bottom = 1
	psb.border_color = Color(0.0, 0.82, 0.96, 0.85)
	psb.set_corner_radius_all(6)
	psb.content_margin_left = 14
	psb.content_margin_right = 14
	psb.content_margin_top = 10
	psb.content_margin_bottom = 10
	ui_list_panel.add_theme_stylebox_override("panel", psb)

	main_hud.add_child(ui_list_panel)
	ui_list_panel.custom_minimum_size = Vector2(230, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	ui_list_panel.add_child(vbox)

	var title = Label.new()
	title.name = "Title"
	title.text = "PANELES DE UI"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	for item in UI_PANEL_ITEMS:
		var cb = CheckBox.new()
		cb.name = "Chk_" + item.id
		cb.text = str(item.icon) + "  " + str(item.label)
		cb.add_theme_font_size_override("font_size", 13)
		cb.add_theme_constant_override("h_separation", 8)
		cb.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		cb.add_theme_color_override("font_hover_color", Color.CYAN)
		cb.add_theme_color_override("font_pressed_color", Color(0.0, 0.85, 1.0))
		cb.add_theme_color_override("font_hover_pressed_color", Color.CYAN)
		cb.add_theme_color_override("icon_normal_color", Color(0.55, 0.65, 0.7))
		cb.add_theme_color_override("icon_hover_color", Color.CYAN)
		cb.add_theme_color_override("icon_pressed_color", Color(0.0, 0.85, 1.0))
		cb.add_theme_color_override("icon_hover_pressed_color", Color.CYAN)
		cb.toggled.connect(_on_ui_panel_toggled.bind(item.id))
		vbox.add_child(cb)
		ui_list_checks[item.id] = cb

	vbox.add_child(HSeparator.new())

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var all_btn = Button.new()
	all_btn.text = "MARCAR TODO"
	all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_btn.add_theme_font_size_override("font_size", 11)
	all_btn.pressed.connect(_set_all_ui_panels.bind(true))
	btn_row.add_child(all_btn)

	var none_btn = Button.new()
	none_btn.text = "NINGUNO"
	none_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	none_btn.add_theme_font_size_override("font_size", 11)
	none_btn.pressed.connect(_set_all_ui_panels.bind(false))
	btn_row.add_child(none_btn)

	_apply_button_style(all_btn)
	_apply_button_style(none_btn)

func _apply_button_style(btn: Button):
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.1, 0.13, 0.95)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.0, 0.82, 0.96, 0.6)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)

	var h_sb = sb.duplicate()
	h_sb.border_color = Color.CYAN
	h_sb.bg_color = Color(0.1, 0.25, 0.3, 0.95)
	btn.add_theme_stylebox_override("hover", h_sb)

	var p_sb = sb.duplicate()
	p_sb.bg_color = Color(0.15, 0.35, 0.4, 0.95)
	btn.add_theme_stylebox_override("pressed", p_sb)

	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 0.95))
	btn.add_theme_color_override("font_hover_color", Color.CYAN)
	btn.add_theme_color_override("font_pressed_color", Color.CYAN)

func _toggle_ui_list():
	var main_hud = get_parent()
	# No interferir con el editor de layout (todas las ventanas se fuerzan visibles ahí)
	if is_instance_valid(main_hud) and main_hud.get("is_editing_layout"):
		return

	_ensure_ui_list_panel()
	if not is_instance_valid(ui_list_panel): return

	if ui_list_panel.visible:
		ui_list_panel.visible = false
		return

	_refresh_ui_list_state()
	ui_list_panel.visible = true
	_position_ui_list_panel()

func _refresh_ui_list_state():
	var main_hud = get_parent()
	for id in ui_list_checks:
		var cb = ui_list_checks[id]
		if not is_instance_valid(cb): continue
		var node = null
		if is_instance_valid(main_hud) and main_hud.has_method("_get_hud_node"):
			node = main_hud._get_hud_node(id)
		# Sin nodo = checkeado por defecto (los paneles nuevos nacen visibles)
		cb.set_pressed_no_signal(true if node == null else node.visible)

func _position_ui_list_panel():
	if not is_instance_valid(ui_list_panel) or not is_instance_valid(ui_list_btn): return
	ui_list_panel.reset_size()

	var vp_size = get_viewport_rect().size
	var panel_size = ui_list_panel.size
	if panel_size.y <= 0.0:
		panel_size = ui_list_panel.get_combined_minimum_size()
	var btn_rect = ui_list_btn.get_global_rect()

	# Se despliega hacia arriba anclado al mini icono (con margen de seguridad)
	var pos = Vector2(btn_rect.position.x, btn_rect.position.y - panel_size.y - 8.0)
	if pos.y < 6.0:
		pos.y = btn_rect.end.y + 8.0
		if pos.y + panel_size.y > vp_size.y - 6.0:
			pos.y = maxf(6.0, vp_size.y - panel_size.y - 6.0)
	if pos.x + panel_size.x > vp_size.x - 6.0:
		pos.x = vp_size.x - panel_size.x - 6.0
	if pos.x < 6.0:
		pos.x = 6.0

	ui_list_panel.global_position = pos

func _on_ui_panel_toggled(pressed: bool, panel_id: String):
	_apply_ui_panel_visibility(panel_id, pressed)
	# v901.0: La configuración se guarda por usuario en el servidor (hudConfig)
	var main_hud = get_parent()
	if is_instance_valid(main_hud) and main_hud.has_method("_persist_hud_visibility"):
		main_hud._persist_hud_visibility()

func _apply_ui_panel_visibility(panel_id: String, pressed: bool):
	var main_hud = get_parent()
	if not is_instance_valid(main_hud) or not main_hud.has_method("_get_hud_node"): return

	var node = main_hud._get_hud_node(panel_id)
	if node:
		node.visible = pressed
		if main_hud.has_method("_update_icon_state"):
			main_hud._update_icon_state(panel_id, pressed)

func _set_all_ui_panels(pressed: bool):
	var changed = false
	for id in ui_list_checks:
		var cb = ui_list_checks[id]
		if not is_instance_valid(cb): continue
		if cb.button_pressed == pressed: continue
		cb.set_pressed_no_signal(pressed)
		_apply_ui_panel_visibility(id, pressed)
		changed = true
	# Una sola persistencia por lote (evita inundar al servidor con saveHudLayout)
	if changed:
		var main_hud = get_parent()
		if is_instance_valid(main_hud) and main_hud.has_method("_persist_hud_visibility"):
			main_hud._persist_hud_visibility()

func _input(event):
	if not is_instance_valid(ui_list_panel) or not ui_list_panel.visible: return
	if event is InputEventMouseButton and event.pressed:
		if ui_list_panel.get_global_rect().has_point(event.position): return
		if is_instance_valid(ui_list_btn) and ui_list_btn.get_global_rect().has_point(event.position): return
		ui_list_panel.visible = false
