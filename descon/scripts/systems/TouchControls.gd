extends Control

# TouchControls.gd (v1.0 - Componente de Controles Táctiles y Joystick)

var virtual_joystick = null

func _ready():
	print("[TouchControls] Inicializando controles táctiles.")
	
	# v266.400: Inyectar Joystick Virtual (Soporte Móvil)
	_setup_joystick()
	_update_joystick_visibility()
	
	# v238.20: Sincronía Táctil Autorizativa (Esperar al Login)
	if NetworkManager:
		if not NetworkManager.login_success.is_connected(_setup_touch_buttons):
			NetworkManager.login_success.connect(func(_d): _setup_touch_buttons())
			
	# También correr la configuración inicial de botones si ya estamos logueados
	if NetworkManager and NetworkManager.is_logged_in:
		_setup_touch_buttons()

	# Icono de escuadrón inicial (Siempre Visible)
	_setup_squad_and_events_icons()

func _setup_squad_and_events_icons():
	# Icono Squad (Siempre Visible)
	if not has_node("IconSquad"):
		var btn = Button.new()
		btn.name = "IconSquad"
		btn.text = "👥"
		btn.custom_minimum_size = Vector2(32,32)
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.1,0.1,0.1,0.6); sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(_on_icon_pressed.bind("Squad"))
		add_child(btn)
		move_child(btn, 0)
		
	# Icono Eventos (Nuevo v2.2)
	if not has_node("IconEvents"):
		var btn = Button.new()
		btn.name = "IconEvents"
		btn.text = "🏆"
		btn.tooltip_text = "Eventos y Modos de Juego [F2]"
		btn.custom_minimum_size = Vector2(32,32)
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.1,0.1,0.1,0.6); sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(_on_icon_pressed.bind("Events"))
		add_child(btn)
		move_child(btn, 1)

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
		var enabled = SettingsManager.mobile_mode if SettingsManager else false
		virtual_joystick.visible = enabled
		virtual_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if enabled:
			if NetworkManager and NetworkManager.current_user_data.has("hudPositions"):
				var data = NetworkManager.current_user_data["hudPositions"]
				if data.has("VirtualJoystick"):
					var pos_data = data["VirtualJoystick"]
					var screen_size = get_viewport_rect().size
					var rx = float(pos_data.get("x", 0.0))
					var ry = float(pos_data.get("y", 0.0))
					var final_pos = Vector2(rx * screen_size.x, ry * screen_size.y) if rx <= 2.0 else Vector2(rx, ry)
					virtual_joystick.global_position = final_pos
				else:
					virtual_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
		else:
			virtual_joystick.visible = false
			virtual_joystick.global_position = Vector2(-2000, -2000)

func _setup_touch_buttons():
	var touch_btns = [
		{"id": "EscMenu", "icon": "⚙️", "tip": "Sistema (ESC)"},
		{"id": "Inventory", "icon": "🎒", "tip": "Inventario (F1)"}
	]
	
	for data in touch_btns:
		if has_node("Icon" + data.id): continue
		
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
		add_child(btn)
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
		"Inventory": "Inventario", 
		"EscMenu": "Menu", 
		"Events": "Eventos",
		"AdminPanel": "Admin", "Admin": "Admin",
		"Squad": "Equipo", "Party": "Equipo", "Chat": "Chat",
		"Stats": "Estadísticas", "Map": "Mapa", "Radar": "Minimapa", "RadarWindow": "Minimapa",
		"PvP": "Modo combate", "Talents": "Talentos", "Skills": "Habilidades"
	}
	
	for btn in get_children():
		if not btn is Button: continue
		
		var b_name = btn.name.replace("Icon", "")
		var final_name = names.get(b_name, b_name)
		btn.tooltip_text = ""
		
		if not btn.mouse_entered.is_connected(_on_icon_hover.bind(btn, final_name)):
			btn.mouse_entered.connect(_on_icon_hover.bind(btn, final_name))
			btn.mouse_exited.connect(_on_icon_unhover)
		
		if not btn.pressed.is_connected(_on_icon_pressed.bind(b_name)):
			btn.pressed.connect(_on_icon_pressed.bind(b_name))

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
	var main_hud = get_parent()
	if is_instance_valid(main_hud) and main_hud.has_method("_on_icon_pressed"):
		main_hud._on_icon_pressed(id)
